package com.voicecoding.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkAddress
import android.net.Network
import android.net.NetworkCapabilities
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        installKeyboardInsetListener()
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
                    result.success(webSocket.send(message))
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
            val network = findCurrentWifiNetwork(connectivityManager, targetHost)
            if (network == null) {
                emitEvent(
                    id,
                    "failure",
                    mapOf("message" to "Physical WiFi network is unavailable")
                )
                cleanupConnection(id)
                return id
            }
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
        var fallbackNetwork: Network? = null
        var fallbackInterfaceName: String? = null

        for (network in networks) {
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: continue
            if (
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            ) {
                val linkProperties = connectivityManager.getLinkProperties(network)
                val interfaceName = linkProperties?.interfaceName
                val routeMatchesTarget =
                    targetAddress != null &&
                        linkProperties?.linkAddresses?.any {
                            linkAddressContains(it, targetAddress)
                        } == true
                Log.i(
                    logTag,
                    "Physical WiFi candidate network=$network iface=$interfaceName " +
                        "target=$targetHost routeMatchesTarget=$routeMatchesTarget"
                )
                if (routeMatchesTarget) {
                    Log.i(logTag, "Selected routed physical WiFi network=$network iface=$interfaceName")
                    return network
                }
                if (fallbackNetwork == null) {
                    fallbackNetwork = network
                    fallbackInterfaceName = interfaceName
                }
            }
        }

        if (fallbackNetwork != null) {
            Log.i(logTag, "Selected fallback physical WiFi network=$fallbackNetwork iface=$fallbackInterfaceName")
            return fallbackNetwork
        }

        Log.w(
            logTag,
            "No physical WiFi network found among ${networks.size} networks for target=$targetHost"
        )
        return null
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

    private data class NativeWebSocketConnection(
        val networkCallback: ConnectivityManager.NetworkCallback? = null,
        var webSocket: WebSocket? = null,
        var client: OkHttpClient? = null
    )
}
