package com.voicecoding.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkAddress
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import okhttp3.Dns
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface
import java.net.URI
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private val logTag = "VoicingNativeWs"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val nextConnectionId = AtomicInteger(1)
    private val connections = ConcurrentHashMap<Int, NativeWebSocketConnection>()
    private val pendingEvents = mutableListOf<Map<String, Any?>>()
    private var eventSink: EventChannel.EventSink? = null
    private var keyboardInsetSink: EventChannel.EventSink? = null
    private var lastKeyboardInsetDp = 0.0
    private var hasKeyboardInset = false

    // 2026-11-20 新增：网络画像变化事件（Dart 侧做 400ms 防抖后再触发重连）。
    private var networkStateSink: EventChannel.EventSink? = null
    private var networkStateCallback: ConnectivityManager.NetworkCallback? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        installKeyboardInsetListener()
    }

    override fun onDestroy() {
        // 必须成对注销 NetworkCallback，避免 Activity 销毁后继续回调已释放的 sink。
        stopNetworkStateMonitoring()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "voicing/network"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "connectWifiWebSocket" -> {
                    val requestedId = call.argument<Int>("id")
                    val url = call.argument<String>("url")
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 8000
                    if (url.isNullOrBlank()) {
                        result.error("invalid_url", "WebSocket url is required", null)
                        return@setMethodCallHandler
                    }
                    val id = connectWifiWebSocket(requestedId, url, timeoutMs)
                    result.success(id)
                }
                "sendWebSocketMessage" -> {
                    val id = call.argument<Int>("id")
                    val message = call.argument<String>("message") ?: ""
                    val webSocket = id?.let { connections[it]?.webSocket }
                    if (id == null || webSocket == null) {
                        result.error("not_connected", "WebSocket is not connected", null)
                        return@setMethodCallHandler
                    }
                    if (!webSocket.send(message)) {
                        result.error("send_failed", "WebSocket refused the message", null)
                        return@setMethodCallHandler
                    }
                    result.success(true)
                }
                "closeWebSocket" -> {
                    val id = call.argument<Int>("id")
                    val code = call.argument<Int>("code") ?: 1000
                    val reason = call.argument<String>("reason") ?: ""
                    if (id != null) {
                        connections[id]?.webSocket?.close(code, reason)
                        emitEvent(id, "closed", mapOf("code" to code, "reason" to reason))
                        cleanupConnection(id)
                    }
                    result.success(null)
                }
                "getNetworkSnapshot" -> {
                    // 2026-11-20 新增：Dart 侧网络画像（跨网络候选排序/自适应重连）的
                    // 一次性快照入口。复用现有 voicing/network channel，不新增权限。
                    try {
                        result.success(buildNetworkSnapshot())
                    } catch (error: Exception) {
                        result.error(
                            "snapshot_failed",
                            error.message ?: "network snapshot failed",
                            null
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "voicing/network_events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                flushPendingEvents()
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "voicing/keyboard_insets"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                keyboardInsetSink = events
                events?.success(lastKeyboardInsetDp)
            }

            override fun onCancel(arguments: Any?) {
                keyboardInsetSink = null
            }
        })

        // 2026-11-20 新增：网络画像变化事件通道。WiFi/蜂窝/VPN/以太网接口
        // 或前缀长度变化时推送整份快照；Dart 侧 NetworkSnapshotProvider 负责
        // 400ms 防抖与静默降级，这里只做原生采集与主线程投递。
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "voicing/network_state_events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                networkStateSink = events
                startNetworkStateMonitoring()
                emitNetworkSnapshot()
            }

            override fun onCancel(arguments: Any?) {
                networkStateSink = null
                stopNetworkStateMonitoring()
            }
        })
    }

    private fun installKeyboardInsetListener() {
        val rootView = window.decorView
        ViewCompat.setOnApplyWindowInsetsListener(rootView) { _, insets ->
            emitKeyboardInset(insets)
            insets
        }
        ViewCompat.setWindowInsetsAnimationCallback(
            rootView,
            object : WindowInsetsAnimationCompat.Callback(DISPATCH_MODE_CONTINUE_ON_SUBTREE) {
                override fun onProgress(
                    insets: WindowInsetsCompat,
                    runningAnimations: MutableList<WindowInsetsAnimationCompat>
                ): WindowInsetsCompat {
                    emitKeyboardInset(insets)
                    return insets
                }
            }
        )
        ViewCompat.requestApplyInsets(rootView)
    }

    private fun emitKeyboardInset(insets: WindowInsetsCompat) {
        val imeBottomPx = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom
        val imeBottomDp = imeBottomPx / resources.displayMetrics.density.toDouble()
        if (hasKeyboardInset && abs(imeBottomDp - lastKeyboardInsetDp) < 0.1) {
            return
        }
        lastKeyboardInsetDp = imeBottomDp
        hasKeyboardInset = true

        if (Looper.myLooper() == Looper.getMainLooper()) {
            keyboardInsetSink?.success(imeBottomDp)
        } else {
            mainHandler.post {
                keyboardInsetSink?.success(imeBottomDp)
            }
        }
    }

    private fun connectWifiWebSocket(requestedId: Int?, url: String, timeoutMs: Int): Int {
        val id = requestedId ?: nextConnectionId.getAndIncrement()
        val connectivityManager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        connections[id] = NativeWebSocketConnection()
        try {
            val targetHost = try {
                URI(url).host
            } catch (_: Exception) {
                null
            }
            // 2026-09-25：按目标地址分两种选路方式。
            // 1) Tailscale CGNAT 目标（100.64.0.0/10）：PC 端现在会把 Tailscale 地址
            //    作为兜底候选写进 QR。这类地址只能经 VPN 隧道到达，绝不能绑定物理
            //    WiFi，否则连接必然失败；此时直接用系统默认网络（即隧道）。
            // 2) 其它目标：先按 WiFi 分级挑网络，完全没有 WiFi 候选时退回
            //    activeNetwork，而不是像旧实现那样直接报错结束。
            val tailscaleTarget = isTailscaleCgnatHost(targetHost)
            val network = if (tailscaleTarget) {
                Log.i(
                    logTag,
                    "Target $targetHost is in the Tailscale CGNAT range; using the default network (VPN tunnel)"
                )
                connectivityManager.activeNetwork
            } else {
                findCurrentWifiNetwork(connectivityManager, targetHost)
                    ?: connectivityManager.activeNetwork
            }
            if (network == null) {
                emitEvent(
                    id,
                    "failure",
                    mapOf("message" to "No usable network (no WiFi candidate and no active network)")
                )
                cleanupConnection(id)
                return id
            }
            Log.i(
                logTag,
                "Selected network=$network for target=$targetHost tailscaleTarget=$tailscaleTarget " +
                    describeCapabilities(connectivityManager.getNetworkCapabilities(network))
            )
            openWifiBoundWebSocket(id, url, timeoutMs, network, connectivityManager)
        } catch (error: Exception) {
            emitEvent(
                id,
                "failure",
                mapOf("message" to (error.message ?: "requestNetwork failed"))
            )
            cleanupConnection(id)
        }
        return id
    }

    private fun findCurrentWifiNetwork(
        connectivityManager: ConnectivityManager,
        targetHost: String?
    ): Network? {
        val networks = connectivityManager.allNetworks
        val targetAddress = parseIpv4Address(targetHost)

        // 分级挑选，取代原来的「必须 WiFi 且非 VPN」硬判定。
        // routed* 记录命中目标网段的网络，best* 记录优先级最高（tier 最小）的网络。
        var routedNetwork: Network? = null
        var routedTier = Int.MAX_VALUE
        var routedInterfaceName: String? = null
        var bestNetwork: Network? = null
        var bestTier = Int.MAX_VALUE
        var bestInterfaceName: String? = null

        for (network in networks) {
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: continue
            val tier = wifiCapabilityTier(capabilities) ?: continue
            val linkProperties = connectivityManager.getLinkProperties(network)
            val interfaceName = linkProperties?.interfaceName
            val routeMatchesTarget =
                targetAddress != null &&
                    linkProperties?.linkAddresses?.any {
                        linkAddressContains(it, targetAddress)
                    } == true
            Log.i(
                logTag,
                "WiFi candidate network=$network tier=$tier iface=$interfaceName " +
                    "target=$targetHost routeMatchesTarget=$routeMatchesTarget " +
                    describeCapabilities(capabilities)
            )
            if (routeMatchesTarget && tier < routedTier) {
                routedNetwork = network
                routedTier = tier
                routedInterfaceName = interfaceName
            }
            if (tier < bestTier) {
                bestNetwork = network
                bestTier = tier
                bestInterfaceName = interfaceName
            }
        }

        if (routedNetwork != null) {
            Log.i(
                logTag,
                "Selected routed WiFi network=$routedNetwork tier=$routedTier iface=$routedInterfaceName"
            )
            return routedNetwork
        }

        if (bestNetwork != null) {
            Log.i(
                logTag,
                "Selected best-effort WiFi network=$bestNetwork tier=$bestTier iface=$bestInterfaceName"
            )
            return bestNetwork
        }

        Log.w(
            logTag,
            "No WiFi-capable network found among ${networks.size} networks for target=$targetHost"
        )
        return null
    }

    /**
     * 2026-09-25 新增：给候选网络分级，取代原先「TRANSPORT_WIFI 且 NET_CAPABILITY_NOT_VPN」
     * 的硬判定。
     *
     * 背景：用户手机开启 Tailscale 后完全连不上 PC。原实现把「非 VPN」当成物理 WiFi 的必要
     * 条件，一旦 capability 组合变化就一个候选都匹配不到，而且调用方会直接报
     * "Physical WiFi network is unavailable" 且不做任何回退。Android 9 起 VPN 调用
     * setUnderlyingNetworks() 后，系统会把底层网络的 transport 传播给 VPN 网络，
     * capability 组合因此不再稳定。
     *
     * 现在改为：只要这个网络与 WiFi 有关就当作候选，VPN 状态只影响优先级（tier 越小越优先），
     * 不影响「能不能用」。返回 null 表示该网络与 WiFi 完全无关（例如纯蜂窝）。
     */
    private fun wifiCapabilityTier(capabilities: NetworkCapabilities): Int? {
        if (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
            return null
        }
        val hasVpnTransport = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        val notVpn = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        return when {
            !hasVpnTransport && notVpn -> 0   // 理想：纯物理 WiFi
            !hasVpnTransport -> 1             // 有 WiFi transport 但 capability 异常，仍按物理 WiFi 处理
            else -> 2                         // VPN 网络继承了 WiFi transport，作为最后候选
        }
    }

    /**
     * 2026-09-25 新增：把网络能力展开成可读字符串，用于诊断 VPN / 多网络场景下的选网问题。
     * 只记录 transport 与 capability 名称，不涉及任何用户内容。
     */
    private fun describeCapabilities(capabilities: NetworkCapabilities?): String {
        if (capabilities == null) {
            return "caps=null"
        }
        val transports = mutableListOf<String>()
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) transports.add("wifi")
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) transports.add("cell")
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) transports.add("vpn")
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) transports.add("eth")
        val caps = mutableListOf<String>()
        if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)) caps.add("not_vpn")
        if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) caps.add("internet")
        if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) caps.add("validated")
        return "transports=${transports.joinToString("|")} caps=${caps.joinToString("|")}"
    }

    private fun parseIpv4Address(host: String?): Inet4Address? {
        if (host.isNullOrBlank()) {
            return null
        }
        if (!Regex("""^\d{1,3}(?:\.\d{1,3}){3}$""").matches(host)) {
            return null
        }
        return try {
            val address = InetAddress.getByName(host)
            address as? Inet4Address
        } catch (_: Exception) {
            null
        }
    }

    private fun linkAddressContains(linkAddress: LinkAddress, target: Inet4Address): Boolean {
        val localAddress = linkAddress.address as? Inet4Address ?: return false
        val prefixLength = linkAddress.prefixLength
        if (prefixLength < 0 || prefixLength > 32) {
            return false
        }

        val mask = if (prefixLength == 0) {
            0
        } else {
            -1 shl (32 - prefixLength)
        }
        return (ipv4ToInt(localAddress) and mask) == (ipv4ToInt(target) and mask)
    }

    private fun ipv4ToInt(address: Inet4Address): Int {
        val bytes = address.address
        return ((bytes[0].toInt() and 0xff) shl 24) or
            ((bytes[1].toInt() and 0xff) shl 16) or
            ((bytes[2].toInt() and 0xff) shl 8) or
            (bytes[3].toInt() and 0xff)
    }

    /**
     * 2026-09-25 新增：判断目标地址是否属于 Tailscale 使用的 100.64.0.0/10（CGNAT）段。
     *
     * PC 端现在把 Tailscale 地址作为兜底候选写入 QR payload。手机在 VPN lockdown
     * 模式下无法绕过 VPN 访问局域网，但走隧道可以到达该地址，因此这类目标必须使用
     * 系统默认网络（VPN），而不能绑定物理 WiFi —— 否则连接必然失败。
     */
    private fun isTailscaleCgnatHost(host: String?): Boolean {
        val address = parseIpv4Address(host) ?: return false
        val value = ipv4ToInt(address)
        // 100.64.0.0/10（RFC 6598 共享地址段）：
        // 掩码 0xFFC00000 的有符号 Int 表示为 -4194304，基址 0x64400000 即 100.64.0.0。
        val cgnatMask = -4194304
        val cgnatBase = 0x64400000
        return (value and cgnatMask) == cgnatBase
    }

    private fun openWifiBoundWebSocket(
        id: Int,
        url: String,
        timeoutMs: Int,
        network: Network,
        connectivityManager: ConnectivityManager
    ) {
        val current = connections[id] ?: return
        val linkProperties = connectivityManager.getLinkProperties(network)
        Log.i(logTag, "Opening WiFi-bound WebSocket id=$id url=$url iface=${linkProperties?.interfaceName}")
        val client = OkHttpClient.Builder()
            .socketFactory(network.socketFactory)
            .dns(object : Dns {
                override fun lookup(hostname: String): List<InetAddress> {
                    return network.getAllByName(hostname).toList()
                }
            })
            .connectTimeout(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .build()

        val request = Request.Builder().url(url).build()
        val webSocket = client.newWebSocket(
            request,
            object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    Log.i(logTag, "WebSocket open id=$id")
                    emitEvent(id, "open")
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    Log.i(logTag, "WebSocket message id=$id length=${text.length}")
                    emitEvent(id, "message", mapOf("data" to text))
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    webSocket.close(code, reason)
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    Log.i(logTag, "WebSocket closed id=$id code=$code reason=$reason")
                    emitEvent(id, "closed", mapOf("code" to code, "reason" to reason))
                    cleanupConnection(id)
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    Log.w(logTag, "WebSocket failure id=$id message=${t.message}", t)
                    emitEvent(
                        id,
                        "failure",
                        mapOf("message" to (t.message ?: "WebSocket failure"))
                    )
                    cleanupConnection(id)
                }
            }
        )

        current.webSocket = webSocket
        current.client = client
    }

    private fun emitEvent(
        id: Int,
        event: String,
        extra: Map<String, Any?> = emptyMap()
    ) {
        val payload = HashMap<String, Any?>()
        payload["id"] = id
        payload["event"] = event
        payload.putAll(extra)
        mainHandler.post {
            val sink = eventSink
            if (sink == null) {
                pendingEvents.add(payload)
            } else {
                sink.success(payload)
            }
        }
    }

    private fun flushPendingEvents() {
        mainHandler.post {
            val sink = eventSink ?: return@post
            if (pendingEvents.isEmpty()) {
                return@post
            }
            val events = pendingEvents.toList()
            pendingEvents.clear()
            events.forEach { sink.success(it) }
        }
    }

    private fun cleanupConnection(id: Int) {
        val connection = connections.remove(id) ?: return
        val connectivityManager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val callback = connection.networkCallback
        if (callback != null) {
            try {
                connectivityManager.unregisterNetworkCallback(callback)
            } catch (_: Exception) {
            }
        }
        connection.webSocket?.cancel()
        connection.client?.dispatcher?.executorService?.shutdown()
        connection.client?.connectionPool?.evictAll()
    }

    /**
     * 2026-11-20 新增：构建网络画像快照，供 Dart 侧做跨网络候选排序与自适应重连。
     *
     * 只读取 IPv4 地址 + 前缀长度 + 接口类型，不读 SSID、不申请定位权限，也不
     * 触碰 WebSocket WiFi 绑定/connection id 逻辑。数据来源两层：
     * 1) ConnectivityManager.allNetworks + LinkProperties：带 transport 类型与
     *    真实前缀长度；
     * 2) NetworkInterface.getNetworkInterfaces()：兜底覆盖未注册成 Network 的
     *    接口（部分 VPN / tethering），按 name+ip 去重。
     *
     * 返回结构与 Dart 侧 NetworkSnapshot.fromNativeMap 严格对应：
     * {approximate: false, interfaces: [{name, ip, prefixLength, kind}]}
     */
    private fun buildNetworkSnapshot(): Map<String, Any?> {
        val connectivityManager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val interfaces = mutableListOf<Map<String, Any?>>()
        val seen = HashSet<String>()
        val kindByInterface = HashMap<String, String>()

        try {
            for (network in connectivityManager.allNetworks) {
                val capabilities = connectivityManager.getNetworkCapabilities(network)
                    ?: continue
                val linkProperties = connectivityManager.getLinkProperties(network)
                    ?: continue
                val interfaceName = linkProperties.interfaceName ?: continue
                val kind = classifyNetworkKind(capabilities)
                kindByInterface[interfaceName] = kind
                for (linkAddress in linkProperties.linkAddresses) {
                    val address = linkAddress.address
                    if (address !is Inet4Address ||
                        address.isLoopbackAddress ||
                        address.isLinkLocalAddress
                    ) {
                        continue
                    }
                    val ip = address.hostAddress ?: continue
                    if (!seen.add("$interfaceName/$ip")) {
                        continue
                    }
                    interfaces.add(
                        mapOf<String, Any?>(
                            "name" to interfaceName,
                            "ip" to ip,
                            "prefixLength" to linkAddress.prefixLength,
                            "kind" to kind
                        )
                    )
                }
            }
        } catch (error: Exception) {
            Log.w(
                logTag,
                "buildNetworkSnapshot: allNetworks enumeration failed: ${error.message}"
            )
        }

        try {
            val networkInterfaces = NetworkInterface.getNetworkInterfaces()
            if (networkInterfaces != null) {
                while (networkInterfaces.hasMoreElements()) {
                    val networkInterface = networkInterfaces.nextElement()
                    val interfaceName = networkInterface.name
                    val kind = kindByInterface[interfaceName]
                        ?: classifyInterfaceName(interfaceName)
                    for (interfaceAddress in networkInterface.interfaceAddresses) {
                        val address = interfaceAddress.address
                        if (address !is Inet4Address ||
                            address.isLoopbackAddress ||
                            address.isLinkLocalAddress
                        ) {
                            continue
                        }
                        val ip = address.hostAddress ?: continue
                        if (!seen.add("$interfaceName/$ip")) {
                            continue
                        }
                        interfaces.add(
                            mapOf<String, Any?>(
                                "name" to interfaceName,
                                "ip" to ip,
                                "prefixLength" to interfaceAddress.networkPrefixLength.toInt(),
                                "kind" to kind
                            )
                        )
                    }
                }
            }
        } catch (error: Exception) {
            Log.w(
                logTag,
                "buildNetworkSnapshot: NetworkInterface enumeration failed: ${error.message}"
            )
        }

        Log.i(logTag, "network snapshot: ifaces=$interfaces")
        return mapOf("approximate" to false, "interfaces" to interfaces)
    }

    /** 依据 NetworkCapabilities 给出接口类型；VPN 优先，避免被底层 WiFi transport 混淆。 */
    private fun classifyNetworkKind(capabilities: NetworkCapabilities?): String {
        if (capabilities == null) {
            return "unknown"
        }
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "unknown"
        }
    }

    /** NetworkInterface 兜底枚举没有 transport 信息时，按接口命名约定近似类型。 */
    private fun classifyInterfaceName(interfaceName: String): String {
        val name = interfaceName.lowercase()
        return when {
            name.startsWith("wlan") ||
                name.startsWith("wifi") ||
                name.startsWith("ap") -> "wifi"
            name.startsWith("tun") ||
                name.startsWith("ppp") ||
                name.startsWith("wg") ||
                name.contains("tailscale") -> "vpn"
            name.startsWith("rmnet") ||
                name.startsWith("ccmni") ||
                name.startsWith("wwan") ||
                name.startsWith("radio") -> "mobile"
            name.startsWith("eth") -> "ethernet"
            else -> "unknown"
        }
    }

    /**
     * 2026-11-20 新增：注册全局网络回调，网络可用/丢失/链路属性/能力变化时
     * 重新采集快照并通过 EventChannel 推送。优先注册「所有网络」的回调；若
     * 系统限制空 request，则回退到默认网络回调。任何异常都只降级不崩溃。
     */
    private fun startNetworkStateMonitoring() {
        if (networkStateCallback != null) {
            return
        }
        val connectivityManager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                scheduleNetworkSnapshotEmit()
            }

            override fun onLost(network: Network) {
                scheduleNetworkSnapshotEmit()
            }

            override fun onLinkPropertiesChanged(
                network: Network,
                linkProperties: LinkProperties
            ) {
                scheduleNetworkSnapshotEmit()
            }

            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities
            ) {
                scheduleNetworkSnapshotEmit()
            }
        }
        try {
            connectivityManager.registerNetworkCallback(
                NetworkRequest.Builder().build(),
                callback
            )
            networkStateCallback = callback
            Log.i(logTag, "network state monitoring started (all networks)")
        } catch (error: Exception) {
            Log.w(
                logTag,
                "registerNetworkCallback failed, fallback to default: ${error.message}"
            )
            try {
                connectivityManager.registerDefaultNetworkCallback(callback)
                networkStateCallback = callback
                Log.i(logTag, "network state monitoring started (default network)")
            } catch (fallbackError: Exception) {
                Log.w(
                    logTag,
                    "network state monitoring unavailable: ${fallbackError.message}"
                )
            }
        }
    }

    private fun stopNetworkStateMonitoring() {
        val callback = networkStateCallback ?: return
        networkStateCallback = null
        val connectivityManager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        try {
            connectivityManager.unregisterNetworkCallback(callback)
        } catch (_: Exception) {
        }
    }

    /** NetworkCallback 在系统线程回调，必须切回主线程再调用 EventSink。 */
    private fun scheduleNetworkSnapshotEmit() {
        mainHandler.post {
            emitNetworkSnapshot()
        }
    }

    private fun emitNetworkSnapshot() {
        val sink = networkStateSink ?: return
        try {
            sink.success(buildNetworkSnapshot())
        } catch (error: Exception) {
            Log.w(logTag, "emit network snapshot failed: ${error.message}")
        }
    }

    private data class NativeWebSocketConnection(
        val networkCallback: ConnectivityManager.NetworkCallback? = null,
        var webSocket: WebSocket? = null,
        var client: OkHttpClient? = null
    )
}
