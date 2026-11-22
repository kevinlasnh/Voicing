import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';
import 'connection_race.dart';
import 'connection_recovery_policy.dart';
import 'connection_tuning.dart';
import 'network_profile.dart';
import 'saved_server.dart';
import 'server_address_book.dart';
import 'voicing_protocol.dart';
import 'voicing_websocket.dart';

/// 建链工厂（可注入接缝）。
///
/// 默认使用生产实现 [VoicingWebSocketConnector.connect]；单元测试注入 fake
/// channel 即可完全脱离真实 socket。探测与正式连接都走同一条工厂，因此测试
/// 可以用「同一 IP 第 N 次连接返回什么」来驱动完整流程。
typedef VoicingChannelFactory = VoicingWebSocketChannel Function(
  Uri uri, {
  Duration? connectTimeout,
  bool preferNativeWifi,
});

/// 单台已配对设备的只读 UI 状态（2026-11-22 多设备新增）。
///
/// 「设备选择」子菜单直接消费这个列表：每台设备带自己的连接状态、同步状态，
/// 以及它是否是当前发送目标（[isActive]）。
class PairedDeviceState {
  const PairedDeviceState({
    required this.server,
    required this.status,
    required this.isActive,
    required this.syncEnabled,
  });

  final SavedServer server;
  final ConnectionStatus status;
  final bool isActive;
  final bool syncEnabled;

  String get deviceKey => server.deviceKey;
  String get displayName => server.displayName;
  bool get connected => status == ConnectionStatus.connected;
}

/// 单台设备的运行时连接句柄（2026-11-22 多设备重构）。
///
/// 旧实现把「一台设备」的全部状态（channel/心跳/重连 timer/竞速句柄/
/// generation）摊在 controller 的成员变量里；多设备后每台设备各持一份，
/// 互不干扰。generation 只在本设备内递增，用来丢弃旧 socket / 旧竞速回调。
class _DeviceLink {
  _DeviceLink({required this.server}) : currentIp = server.ip;

  SavedServer server;

  /// 最近一次用于建链的候选地址（竞速 winner / 正式连接地址）。
  String currentIp;

  ConnectionStatus status = ConnectionStatus.disconnected;
  bool syncEnabled = true;
  VoicingWebSocketChannel? channel;
  StreamSubscription<dynamic>? subscription;
  int generation = 0;
  int reconnectAttempt = 0;
  Timer? reconnectTimer;
  RaceHandle? race;
  DateTime? lastPong;
  DateTime? connectedSince;
  DateTime? connectStartedAt;
  bool disposed = false;

  String get deviceKey => server.deviceKey;
  bool get connected => status == ConnectionStatus.connected;
}

/// Android 端连接状态机（2026-11-22 升级为多设备并发连接）。
///
/// 行为要点：
/// - 配对不再互相覆盖：每扫一台新 PC 就追加到设备列表，同一 `device_id`
///   重扫只合并地址簿历史；手动 IP 输入命中已有候选地址时更新该设备。
/// - 所有已配对设备并发建链（各自独立竞速/心跳/重连），不再只有一台在线。
/// - 消息只发给「当前选中设备」（[activeDeviceKey]），切换目标不改动其它
///   设备连接；设备选择子菜单读取 [pairedDevices] 展示各设备实时状态。
/// - 文本提交 / shadow 增量 / ack 清空输入全部以活跃设备为准，其它设备的
///   ack 不会误清当前输入框。
/// - 旧单设备存储（schema v1/v2）由 [SavedServerStore.loadSnapshot] 迁移成
///   设备列表，协议与 QR schema 完全不变，已发布 PC 端无需改动。
class VoicingConnectionController extends ChangeNotifier {
  static const Duration _shadowFinalizeDelay = Duration(milliseconds: 700);
  static const int _maxSentTextHistory = 20;

  VoicingConnectionController({
    ConnectionRecoveryPolicy recoveryPolicy = const ConnectionRecoveryPolicy(
      heartbeatTimeout: Duration(
        seconds: VoicingProtocol.heartbeatTimeoutSec,
      ),
      udpReconnectCooldown: Duration(
        milliseconds: VoicingProtocol.udpReconnectCooldownMs,
      ),
      normalConnectTimeout: Duration(
        seconds: VoicingProtocol.connectTimeoutSec,
      ),
      maxReconnectDelay: Duration(
        seconds: VoicingProtocol.maxReconnectDelaySec,
      ),
    ),
    SavedServerStore savedServerStore = const SavedServerStore(),
    ConnectionTuning tuning = const ConnectionTuning(),
    NetworkSnapshotProvider? networkSnapshotProvider,
    VoicingChannelFactory channelFactory = VoicingWebSocketConnector.connect,
  })  : _recoveryPolicy = recoveryPolicy,
        _savedServerStore = savedServerStore,
        _tuning = tuning,
        _networkProvider = networkSnapshotProvider ??
            NetworkSnapshotProvider.platform(
              debounce: tuning.networkChangeDebounce,
              snapshotTimeout: tuning.nativeSnapshotTimeout,
            ),
        _channelFactory = channelFactory,
        _connectionRace = ConnectionRace(tuning: tuning) {
    textController.addListener(_onTextControllerChanged);
  }

  final TextEditingController textController = TextEditingController();
  final ConnectionRecoveryPolicy _recoveryPolicy;
  final SavedServerStore _savedServerStore;
  final ConnectionTuning _tuning;
  final NetworkSnapshotProvider _networkProvider;
  final VoicingChannelFactory _channelFactory;
  final ConnectionRace _connectionRace;

  /// 设备列表：key = [SavedServer.deviceKey]，value = 该设备的运行时链接。
  /// 使用 Map 保持配对先后顺序，UI 子菜单按这个顺序展示（稳定不跳动）。
  final Map<String, _DeviceLink> _links = <String, _DeviceLink>{};
  String? _activeDeviceKey;

  bool _syncEnabledFallback = true;
  bool _autoEnterEnabled = false;
  Timer? _heartbeatTimer;
  String _lastSentText = '';
  final List<String> _sentTextHistory = <String>[];
  int? _recallHistoryIndex;
  final bool _shadowModeEnabled = true;
  int _lastSentLength = 0;
  bool _wasComposing = false;
  DateTime? _foregroundRecoveryUntil;
  Timer? _foregroundRecoveryTimer;
  Timer? _shadowFinalizeTimer;
  bool _displayConnectedDuringForegroundRecovery = false;

  // 网络画像：初始化时拉取一次，之后订阅原生变化。
  NetworkSnapshot _networkSnapshot = NetworkSnapshot.empty;
  StreamSubscription<NetworkSnapshot>? _networkSubscription;

  // QR 并行竞速句柄；同一时刻最多一个。
  RaceHandle? _qrRace;

  // 持久化串行队列：多台设备的成功历史/失败计数可能并发落盘，
  // 队列保证永远按生成顺序整体写回，不会出现旧快照覆盖新快照。
  Future<void> _persistQueue = Future<void>.value();

  bool _disposed = false;

  ConnectionStatus get status =>
      _activeLink?.status ?? ConnectionStatus.disconnected;

  ConnectionStatus get displayStatus {
    if (_displayConnectedDuringForegroundRecovery && _activeLink != null) {
      return ConnectionStatus.connected;
    }
    return status;
  }

  bool get syncEnabled => _activeLink?.syncEnabled ?? _syncEnabledFallback;
  bool get autoEnterEnabled => _autoEnterEnabled;
  String get serverIp =>
      _activeLink?.currentIp ??
      _activeLink?.server.ip ??
      VoicingProtocol.defaultServerIp;
  int get serverPort =>
      _activeLink?.server.port ?? VoicingProtocol.websocketPort;
  String get lastSentText => _lastSentText;

  /// 当前网络画像 Key（空字符串表示未知）；供 UI/日志/测试读取。
  String get currentNetworkKey => _networkSnapshot.networkKey;

  /// 当前网络快照（测试与调试用；生产逻辑内部使用）。
  NetworkSnapshot get networkSnapshot => _networkSnapshot;

  bool _qrScanMode = false;
  List<Offset>? _lastQrCorners;
  bool _qrPairingSucceeded = false;
  bool _qrPairingFailed = false;
  int _qrPairingGeneration = 0;

  bool get qrScanMode => _qrScanMode;
  bool get hasStoredServer => _links.isNotEmpty;
  SavedServer? get savedServer => _activeLink?.server;
  List<Offset>? get lastQrCorners => _lastQrCorners;
  bool get qrPairingSucceeded => _qrPairingSucceeded;
  bool get qrPairingFailed => _qrPairingFailed;

  /// 已配对设备列表（配对顺序稳定；含各自连接状态与当前活跃标记）。
  List<PairedDeviceState> get pairedDevices {
    final activeKey = _activeDeviceKey;
    return _links.values
        .map(
          (link) => PairedDeviceState(
            server: link.server,
            status: link.status,
            isActive: link.deviceKey == activeKey,
            syncEnabled: link.syncEnabled,
          ),
        )
        .toList(growable: false);
  }

  int get pairedDeviceCount => _links.length;
  String? get activeDeviceKey => _activeDeviceKey;

  SavedServer? get activeDevice => _activeLink?.server;

  /// 活跃设备显示名（未配对时为空字符串），头部状态栏用它提示发往哪台 PC。
  String get activeDeviceName => _activeLink?.server.displayName ?? '';

  _DeviceLink? get _activeLink {
    final key = _activeDeviceKey;
    if (key == null) {
      return null;
    }
    final link = _links[key];
    if (link == null || link.disposed) {
      return null;
    }
    return link;
  }

  // ---------------------------------------------------------------------------
  // QR 扫码配对
  // ---------------------------------------------------------------------------

  void enterQrScanMode() {
    _qrPairingGeneration++;
    _qrRace?.cancel();
    _qrRace = null;
    _qrScanMode = true;
    _qrPairingSucceeded = false;
    _qrPairingFailed = false;
    notifyListeners();
  }

  void exitQrScanMode() {
    _qrPairingGeneration++;
    _qrRace?.cancel();
    _qrRace = null;
    _qrScanMode = false;
    _lastQrCorners = null;
    _qrPairingSucceeded = false;
    _qrPairingFailed = false;
    notifyListeners();
  }

  void handleQrDetected(String rawValue, List<Offset> corners) {
    try {
      final map = jsonDecode(rawValue) as Map<String, dynamic>;
      if (map['v'] != 1 || map['type'] != 'voicing') {
        AppLogger.info('扫到非 Voicing 二维码: $rawValue');
        return;
      }
      _lastQrCorners = corners;
      _qrPairingSucceeded = false;
      _qrPairingFailed = false;
      notifyListeners();
      final generation = ++_qrPairingGeneration;
      unawaited(_completeQrPairing(map, generation));
    } catch (error) {
      AppLogger.warning('QR payload 解析失败: $error');
    }
  }

  /// QR 配对：对全部候选并行竞速（Happy Eyeballs）。
  ///
  /// 成功后的语义从「替换唯一已保存设备」改为「新增或合并到设备列表」：
  /// - 新 PC：追加到列表并设为当前发送目标，旧设备的连接保持不变；
  /// - 同一 PC 重扫：按 `device_id` 找到原记录，合并地址簿历史，不产生重复。
  Future<void> _completeQrPairing(
    Map<String, dynamic> map,
    int generation,
  ) async {
    final startedAt = DateTime.now();
    final scannedServer = _buildSavedServerFromQrPayload(
      map,
      lastConnectedTs: startedAt.millisecondsSinceEpoch,
    );
    if (scannedServer == null) {
      AppLogger.warning('QR payload 缺少有效连接信息: $map');
      await _finishQrPairing(
        startedAt: startedAt,
        success: false,
        generation: generation,
      );
      return;
    }

    final qrCandidateIps = _readQrCandidateIps(map, scannedServer.ip);
    // 扫描当下就能判断「哪些候选属于当前网络」，先给地址簿打网络上下文；
    // 其它候选（docker 网段、别的 WiFi 的 IP、Tailscale）保持未知，避免污染排序。
    final scannedBook = ServerAddressBook.initialBookForCandidates(
      candidateIps: qrCandidateIps,
      snapshot: _networkSnapshot,
      nowMs: startedAt.millisecondsSinceEpoch,
    );
    final serverWithBook = scannedServer.copyWith(addresses: scannedBook);
    final timeout = _attemptTimeout();

    AppLogger.info(
      'QR 并行探测开始: candidates=${qrCandidateIps.join(", ")} '
      'networkKey=${_networkKeyForLog()} '
      'attemptTimeout=${timeout.inMilliseconds}ms '
      'budget=${_tuning.raceBudget.inMilliseconds}ms',
    );
    _qrRace?.cancel();
    final handle = _connectionRace.start(
      candidates: qrCandidateIps,
      attempt: (candidate, cancellation) => _probeQrCandidate(
        ip: candidate.ip,
        port: serverWithBook.port,
        timeout: timeout,
        cancellation: cancellation,
      ),
      isCancelled: () => generation != _qrPairingGeneration || !_qrScanMode,
      attemptTimeout: timeout,
      budget: _tuning.raceBudget,
      onAttemptStarted: (candidate, launchDelay) => AppLogger.info(
        'QR 候选探测启动: ip=${candidate.ip} '
        'stagger=${launchDelay.inMilliseconds}ms '
        'networkKey=${_networkKeyForLog()}',
      ),
      onAttemptFailed: (failure) => AppLogger.warning(
        'QR 候选探测失败: ip=${failure.candidate.ip} '
        'reason=${failure.reason.name} '
        'elapsed=${failure.elapsed.inMilliseconds}ms '
        'networkKey=${_networkKeyForLog()}',
      ),
      onWinner: (outcome) => AppLogger.info(
        'QR 候选探测 winner: ip=${outcome.candidate.ip} '
        'elapsed=${outcome.elapsed.inMilliseconds}ms '
        'attempt=${outcome.attemptElapsed.inMilliseconds}ms '
        'networkKey=${_networkKeyForLog()}',
      ),
    );
    _qrRace = handle;
    final result = await handle.done;
    if (identical(_qrRace, handle)) {
      _qrRace = null;
    }
    if (generation != _qrPairingGeneration || !_qrScanMode || result.cancelled) {
      return;
    }

    final winner = result.winner;
    final winnerServer = winner == null
        ? null
        : serverWithBook.copyWith(
            ip: winner.candidate.ip,
            ips: qrCandidateIps,
          );
    if (winner == null) {
      AppLogger.warning(
        'QR 并行探测全部失败: failures=${_describeRaceFailures(result.failures)} '
        'budgetExhausted=${result.budgetExhausted} '
        'networkKey=${_networkKeyForLog()}',
      );
    }
    await _finishQrPairing(
      startedAt: startedAt,
      success: winnerServer != null,
      generation: generation,
      scannedServer: winnerServer,
    );
  }

  Future<void> _finishQrPairing({
    required DateTime startedAt,
    required bool success,
    required int generation,
    SavedServer? scannedServer,
  }) async {
    if (_disposed || generation != _qrPairingGeneration || !_qrScanMode) {
      return;
    }

    final revealRemaining =
        _tuning.qrResultRevealDelay - DateTime.now().difference(startedAt);
    if (!revealRemaining.isNegative) {
      await Future<void>.delayed(revealRemaining);
    }

    if (generation != _qrPairingGeneration || !_qrScanMode) {
      return;
    }

    if (success && scannedServer != null) {
      _qrPairingSucceeded = true;
      _qrPairingFailed = false;
      notifyListeners();
      await Future<void>.delayed(_tuning.qrSuccessHoldDelay);

      if (generation != _qrPairingGeneration || !_qrScanMode) {
        return;
      }

      _qrScanMode = false;
      _lastQrCorners = null;
      _qrPairingSucceeded = false;
      _qrPairingFailed = false;
      await _adoptScannedDevice(scannedServer);
      notifyListeners();
      return;
    }

    AppLogger.warning(
      'QR 连通性测试未通过: networkKey=${_networkKeyForLog()}',
    );
    _qrPairingSucceeded = false;
    _qrPairingFailed = true;
    notifyListeners();
    await Future<void>.delayed(_tuning.qrFailureHoldDelay);
    if (generation != _qrPairingGeneration || !_qrScanMode) {
      return;
    }
    _qrScanMode = false;
    _lastQrCorners = null;
    _qrPairingSucceeded = false;
    _qrPairingFailed = false;
    notifyListeners();
  }

  /// 查找本次待并入设备对应的已有链接（deviceKey 命中优先，其次旧数据升级）。
  ///
  /// 旧版手动 IP 记录的 deviceKey 是 `legacy:ip:port`，扫码/正式 connected 后
  /// 才能拿到 PC 的 `device_id`。这里额外按候选地址重叠匹配，避免同一台 PC
  /// 在 key 升级时被当成新设备重复加进列表。
  _DeviceLink? _findExistingLinkForServer(SavedServer incoming) {
    final direct = _links[incoming.deviceKey];
    if (direct != null) {
      return direct;
    }
    for (final link in _links.values) {
      if (link.disposed) {
        continue;
      }
      final existing = link.server;
      if (incoming.hasDeviceId && existing.deviceId == incoming.deviceId) {
        return link;
      }
      if (incoming.hasDeviceId &&
          !existing.hasDeviceId &&
          existing.candidateIps.any(incoming.candidateIps.contains)) {
        return link;
      }
    }
    return null;
  }

  /// 设备身份升级（legacy key -> PC device_id）后同步重排 Map Key 与活跃 Key，
  /// 保证 controller 内「Map Key == link.server.deviceKey」的不变量。
  ///
  /// 如果新 Key 已被另一条链接占用（历史脏数据），合并地址簿到已有链接并移除
  /// 当前链接，避免同一个 device_id 在设备选择菜单里出现两份。
  void _syncLinkKey(_DeviceLink link, String oldKey) {
    final newKey = link.server.deviceKey;
    if (newKey == oldKey) {
      return;
    }
    final existing = _links[newKey];
    if (existing != null && !identical(existing, link)) {
      existing.server = existing.server.mergeAddressHistoryFrom(link.server);
      if (_activeDeviceKey == oldKey) {
        _activeDeviceKey = newKey;
      }
      _links.remove(oldKey);
      _disposeLink(link);
      AppLogger.info(
        '设备 Key 冲突合并: $oldKey -> $newKey（保留已有链接）',
      );
      if (!existing.connected) {
        _beginDeviceRace(existing, reason: 'merge duplicated device');
      }
      return;
    }

    final entries = _links.entries.toList(growable: false);
    _links.clear();
    for (final entry in entries) {
      if (identical(entry.value, link)) {
        _links[newKey] = link;
      } else {
        _links[entry.key] = entry.value;
      }
    }
    if (_activeDeviceKey == oldKey) {
      _activeDeviceKey = newKey;
    }
    AppLogger.info('设备 Key 升级: $oldKey -> $newKey');
  }

  /// 把扫码成功的设备并入列表并立即建立正式连接。
  ///
  /// 不再弹「替换已保存设备」确认：不同 PC 是并列新增，同一 PC 重扫只合并。
  Future<void> _adoptScannedDevice(SavedServer scannedServer) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final networkContext = _currentNetworkContext();
    var book = scannedServer.addressBook.recordSuccess(
      ip: scannedServer.ip,
      networkKey: networkContext.networkKey,
      networkKind: networkContext.networkKind,
      nowMs: nowMs,
    );
    var serverToSave = scannedServer.copyWith(
      ip: scannedServer.ip,
      ips: scannedServer.candidateIps,
      addresses: book,
    );

    // 优先按 deviceKey 命中；旧 legacy 记录按候选地址重叠匹配后原地升级 Key。
    var link = _findExistingLinkForServer(serverToSave);
    if (link != null) {
      final oldKey = link.deviceKey;
      // 同一台 PC 重扫：把旧地址簿历史并进来（不同网络的成功地址都保留），
      // 再以本次 winner 地址为主地址；已有连接先保留，正式重连在下面统一做。
      serverToSave = serverToSave.mergeAddressHistoryFrom(link.server);
      book = serverToSave.addressBook.trimmed(
        nowMs: nowMs,
        maxAddresses: _tuning.addressBookMaxAddresses,
      );
      serverToSave = serverToSave.copyWith(
        addresses: book,
        ips: SavedServer.normalizeIpCandidates(
          serverToSave.ip,
          <dynamic>[...serverToSave.candidateIps, ...book.ips],
        ),
        lastConnectedTs: nowMs,
      );
      link.server = serverToSave;
      link.currentIp = scannedServer.ip;
      _syncLinkKey(link, oldKey);
      AppLogger.info(
        'QR 重扫已配对设备，合并历史: key=${link.deviceKey} '
        'ip=${scannedServer.ip} addresses=${book.ips.join(", ")} '
        'networkKeys=${book.successfulNetworkKeys.join("|")}',
      );
    } else {
      book = book.trimmed(
        nowMs: nowMs,
        maxAddresses: _tuning.addressBookMaxAddresses,
      );
      serverToSave = serverToSave.copyWith(
        addresses: book,
        ips: SavedServer.normalizeIpCandidates(
          serverToSave.ip,
          <dynamic>[...serverToSave.candidateIps, ...book.ips],
        ),
        lastConnectedTs: nowMs,
      );
      link = _DeviceLink(server: serverToSave);
      _links[link.deviceKey] = link;
      link.currentIp = scannedServer.ip;
      AppLogger.info(
        'QR 配对新增设备: key=${link.deviceKey} ip=${scannedServer.ip} '
        'name=${serverToSave.displayName} '
        'pairedDevices=${_links.length} '
        'addresses=${book.ips.join(", ")}',
      );
    }

    final previousActiveKey = _activeDeviceKey;
    _activeDeviceKey = link.deviceKey;
    // 只有发送目标真正变化时才重置 shadow 记账：同设备重扫不应把已发往该
    // PC 的 shadow 增量当成「新目标」重发全文，否则 PC 上可能重复粘贴。
    if (previousActiveKey != _activeDeviceKey) {
      _resetShadowStateForDeviceSwitch();
    }
    _schedulePersistDevices();
    // 探测阶段已证明该候选可达；直接对 winner 建正式连接，避免再竞速一轮。
    _connectDevice(link, reason: 'qr scan success');
  }

  SavedServer? _buildSavedServerFromQrPayload(
    Map<String, dynamic> map, {
    required int lastConnectedTs,
  }) {
    final ip = SavedServer.readString(map['ip']);
    final port = SavedServer.readInt(map['port']);
    if (ip.isEmpty || port == null) {
      return null;
    }

    return SavedServer(
      deviceId: SavedServer.readString(map['device_id']),
      ip: ip,
      port: port,
      name: SavedServer.readString(map['name']),
      os: SavedServer.readString(map['os']),
      lastConnectedTs: lastConnectedTs,
    );
  }

  List<String> _readQrCandidateIps(Map<String, dynamic> map, String primaryIp) {
    final candidates = <String>[];

    void addCandidate(dynamic value) {
      final ip = SavedServer.readString(value);
      if (ip.isEmpty || !Ipv4.isValid(ip)) {
        return;
      }
      if (!candidates.contains(ip)) {
        candidates.add(ip);
      }
    }

    final rawIps = map['ips'];
    if (rawIps is List) {
      for (final rawIp in rawIps) {
        addCandidate(rawIp);
      }
    }
    addCandidate(primaryIp);
    return candidates;
  }

  // ---------------------------------------------------------------------------
  // 设备列表 / 活跃设备
  // ---------------------------------------------------------------------------

  /// 选择当前发送目标。切换只改路由，不影响其它设备的连接。
  void selectDevice(String deviceKey) {
    final link = _links[deviceKey];
    if (link == null || link.disposed) {
      return;
    }
    if (_activeDeviceKey == deviceKey) {
      // 重复点选同一台设备：若当前未连接，顺手触发一次重连，行为更符合直觉。
      if (!link.connected) {
        _beginDeviceRace(link, reason: 'active device reselected');
      }
      return;
    }

    _activeDeviceKey = deviceKey;
    _resetShadowStateForDeviceSwitch();
    _schedulePersistDevices();
    AppLogger.info(
      '切换发送目标: ${link.server.displayName}($deviceKey) '
      'status=${link.status.name} syncEnabled=${link.syncEnabled} '
      'pairedDevices=${_links.length}',
    );
    notifyListeners();
    if (!link.connected && link.status != ConnectionStatus.connecting) {
      _beginDeviceRace(link, reason: 'device selected');
    }
  }

  /// 从已配对列表移除一台设备（供 UI 长按/删除使用）。
  void removeDevice(String deviceKey) {
    final link = _links.remove(deviceKey);
    if (link == null) {
      return;
    }
    _disposeLink(link);
    if (_activeDeviceKey == deviceKey) {
      _activeDeviceKey = _firstFallbackDeviceKey();
      _resetShadowStateForDeviceSwitch();
    }
    AppLogger.info(
      '移除已配对设备: $deviceKey; 剩余=${_links.length} '
      'active=${_activeDeviceKey ?? "none"}',
    );
    _schedulePersistDevices();
    notifyListeners();
  }

  String? _firstFallbackDeviceKey() {
    String? firstKey;
    String? connectedKey;
    for (final link in _links.values) {
      firstKey ??= link.deviceKey;
      if (link.connected) {
        connectedKey = link.deviceKey;
        break;
      }
    }
    return connectedKey ?? firstKey;
  }

  void _resetShadowStateForDeviceSwitch() {
    _shadowFinalizeTimer?.cancel();
    _shadowFinalizeTimer = null;
    _lastSentLength = 0;
    _lastSentText = '';
    _wasComposing = false;
  }

  // ---------------------------------------------------------------------------
  // 网络快照
  // ---------------------------------------------------------------------------

  Future<NetworkSnapshot> _loadInitialNetworkSnapshot() async {
    try {
      final snapshot = await _networkProvider.snapshot();
      AppLogger.info(
        '初始化网络画像: networkKey=${snapshot.networkKey.isEmpty ? "unknown" : snapshot.networkKey} '
        'interfaces=${snapshot.interfaces.join(", ")} '
        'approximate=${snapshot.approximate} '
        'tailscale=${snapshot.hasTailscale}',
      );
      return snapshot;
    } catch (error, stackTrace) {
      AppLogger.warning(
        '初始化网络画像失败，按未知网络处理',
        error: error,
        stackTrace: stackTrace,
      );
      return NetworkSnapshot.empty;
    }
  }

  void _subscribeToNetworkChanges() {
    try {
      _networkSubscription = _networkProvider.changes.listen(
        _onNetworkSnapshotChanged,
        onError: (Object error, StackTrace stackTrace) {
          AppLogger.warning(
            '网络状态订阅失败，网络自适应降级（连接不受影响）',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        '网络状态订阅异常，网络自适应降级',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 网络快照变化（已由 provider 做 400ms 防抖）。
  ///
  /// 规则：已连接的设备不打断（只更新快照供以后排序）；未连接的设备立即用
  /// 新快照重排候选并重新竞速，不等 backoff。多设备时逐台判断，互不影响。
  void _onNetworkSnapshotChanged(NetworkSnapshot snapshot) {
    final previous = _networkSnapshot;
    _networkSnapshot = snapshot;
    if (snapshot.signature == previous.signature) {
      return;
    }
    AppLogger.info(
      '网络快照变化: networkKey=${previous.networkKey.isEmpty ? "unknown" : previous.networkKey} '
      '-> ${snapshot.networkKey.isEmpty ? "unknown" : snapshot.networkKey} '
      'interfaces=${snapshot.interfaces.join(", ")}',
    );
    if (_qrScanMode) {
      AppLogger.info('正在扫码配对，暂不触发自适应重连');
      return;
    }
    if (_links.isEmpty) {
      return;
    }
    for (final link in _links.values.toList(growable: false)) {
      if (link.disposed) {
        continue;
      }
      if (link.connected) {
        AppLogger.info(
          '设备 ${link.server.displayName} 已连接，忽略网络变化，不打断现有连接',
        );
        continue;
      }
      AppLogger.info(
        '网络变化触发设备 ${link.server.displayName} 立即重排候选并重连（跳过 backoff）',
      );
      _beginDeviceRace(link, reason: 'network changed');
    }
  }

  // ---------------------------------------------------------------------------
  // 初始化 / 生命周期 / 手动服务器
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    await _loadAutoEnterPreference();
    _networkSnapshot = await _loadInitialNetworkSnapshot();
    _subscribeToNetworkChanges();
    await _loadPairedDevicesPreference();
    _connectAllDevices(reason: 'init');
  }

  Future<void> handleLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused) {
      _stopHeartbeatTimer();
    } else if (state == AppLifecycleState.resumed &&
        _recoveryPolicy.shouldForceReconnectOnResume()) {
      _beginForegroundRecovery();
      _connectAllDevices(reason: 'app resumed', resetBackoff: true);
    }
  }

  /// 手动「刷新连接」：所有设备重新竞速建链（多设备下用户预期整表刷新）。
  void refreshConnection() {
    if (_links.isEmpty) {
      AppLogger.info('刷新连接：当前没有已配对设备');
      return;
    }
    for (final link in _links.values.toList(growable: false)) {
      if (link.disposed) {
        continue;
      }
      _beginDeviceRace(link, reason: 'manual refresh');
    }
  }

  Future<void> setManualServer({
    required String ip,
    int port = VoicingProtocol.websocketPort,
    String deviceId = '',
    String name = '',
    String os = '',
    bool reconnect = true,
  }) async {
    final normalizedIp = ip.trim();
    if (normalizedIp.isEmpty) {
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final incoming = SavedServer(
      deviceId: deviceId.trim(),
      ip: normalizedIp,
      ips: [normalizedIp],
      port: port,
      name: name.trim(),
      os: os.trim(),
      lastConnectedTs: nowMs,
      addresses: ServerAddressBook.initialBookForCandidates(
        candidateIps: [normalizedIp],
        snapshot: _networkSnapshot,
        nowMs: nowMs,
      ),
    );

    // 手动输入已有候选地址（含 QR 配对过的 PC）时更新原设备，避免出现
    // 「同一台 PC 既在 QR 列表里又有一条 legacy 手动记录」的重复项。
    // 带 device_id 的调用直接按 deviceKey 命中；手动对话框没有 device_id，
    // 才退化为按候选地址匹配，且必须保留原设备的 device_id/name/os 身份字段，
    // 否则 Map Key 会与 link.server.deviceKey 不一致。
    final matchedKey = incoming.hasDeviceId
        ? (_links.containsKey(incoming.deviceKey) ? incoming.deviceKey : null)
        : _findDeviceKeyByAddress(normalizedIp);
    final mapKey = matchedKey ??
        incoming.deviceKey;
    var link = _links[mapKey];
    SavedServer serverToSave = incoming;
    if (link != null) {
      final identityPreserved = incoming.copyWith(
        deviceId: incoming.deviceId.isNotEmpty
            ? incoming.deviceId
            : link.server.deviceId,
        name: incoming.name.isNotEmpty ? incoming.name : link.server.name,
        os: incoming.os.isNotEmpty ? incoming.os : link.server.os,
      );
      serverToSave = identityPreserved.mergeAddressHistoryFrom(link.server);
      final oldKey = link.deviceKey;
      link.server = serverToSave;
      link.currentIp = normalizedIp;
      _syncLinkKey(link, oldKey);
      AppLogger.info(
        '手动地址命中已有设备，更新连接信息: key=${link.deviceKey} '
        'ip=$normalizedIp:$port',
      );
    } else {
      link = _DeviceLink(server: serverToSave);
      _links[link.deviceKey] = link;
      link.currentIp = normalizedIp;
      AppLogger.info(
        '手动新增设备: key=${link.deviceKey} ip=$normalizedIp:$port',
      );
    }

    final previousActiveKey = _activeDeviceKey;
    _activeDeviceKey = link.deviceKey;
    if (previousActiveKey != _activeDeviceKey) {
      _resetShadowStateForDeviceSwitch();
    }
    _schedulePersistDevices();
    notifyListeners();
    if (reconnect) {
      _connectDevice(link, reason: 'manual server update');
    }
  }

  String? _findDeviceKeyByAddress(String ip) {
    for (final entry in _links.entries) {
      if (entry.value.server.candidateIps.contains(ip)) {
        return entry.key;
      }
    }
    return null;
  }

  /// 清空全部配对设备（保留旧 API 名；多设备语义为「解除全部配对」）。
  Future<void> clearManualServer() async {
    final links = _links.values.toList(growable: false);
    _links.clear();
    _activeDeviceKey = null;
    for (final link in links) {
      _disposeLink(link);
    }
    // 清空操作也必须排进持久化队列尾部，避免之前排队的快照在 clear 之后
    // 又把旧设备列表写回本地存储。
    _persistQueue = _persistQueue.then((_) => _savedServerStore.clear());
    await _persistQueue;
    _resetShadowStateForDeviceSwitch();
    _syncEnabledFallback = true;
    AppLogger.info('已清空全部配对设备');
    notifyListeners();
  }

  Future<void> _loadPairedDevicesPreference() async {
    try {
      final snapshot = await _savedServerStore.loadSnapshot();
      if (snapshot.servers.isEmpty) {
        AppLogger.info('本机没有已配对设备，等待扫码或手动输入');
        return;
      }
      final normalized = _normalizeLoadedServers(snapshot.servers);
      for (final server in normalized) {
        _links[server.deviceKey] = _DeviceLink(server: server);
      }
      final storedActiveKey = snapshot.activeDeviceKey;
      _activeDeviceKey = _links.containsKey(storedActiveKey)
          ? storedActiveKey
          : normalized.first.deviceKey;
      AppLogger.info(
        '加载已配对设备: count=${_links.length} '
        'active=${_links[_activeDeviceKey]?.server.displayName ?? _activeDeviceKey} '
        'devices=${normalized.map((s) => "${s.displayName}(${s.deviceKey})").join(" | ")}',
      );
    } catch (error, stackTrace) {
      AppLogger.warning('加载已配对设备失败', error: error, stackTrace: stackTrace);
    }
  }

  /// 读盘归一化：同 deviceKey 的重复记录合并地址簿，保留最近连接的那份主信息。
  List<SavedServer> _normalizeLoadedServers(List<SavedServer> servers) {
    final merged = <String, SavedServer>{};
    for (final server in servers) {
      final existing = merged[server.deviceKey];
      if (existing == null) {
        merged[server.deviceKey] = server;
        continue;
      }
      final newer = server.lastConnectedTs >= existing.lastConnectedTs
          ? server
          : existing;
      final older = identical(newer, server) ? existing : server;
      merged[server.deviceKey] = newer.mergeAddressHistoryFrom(older);
    }
    return merged.values.toList(growable: false);
  }

  /// 并发连接全部已配对设备（每台设备内部再并行竞速候选）。
  void _connectAllDevices({
    required String reason,
    bool resetBackoff = false,
  }) {
    if (_links.isEmpty) {
      _setFallbackDisconnectedState();
      AppLogger.info('未保存二维码设备，不进行 UDP 自动发现: $reason');
      return;
    }
    for (final link in _links.values.toList(growable: false)) {
      if (link.disposed) {
        continue;
      }
      if (resetBackoff) {
        link.reconnectAttempt = 0;
      }
      _beginDeviceRace(link, reason: reason);
    }
  }

  // ---------------------------------------------------------------------------
  // 单设备竞速与建链
  // ---------------------------------------------------------------------------

  /// 单台设备的候选评分排序 → 前 N 个并行竞速 → winner 正式建链。
  void _beginDeviceRace(_DeviceLink link, {required String reason}) {
    if (link.disposed || _disposed) {
      return;
    }
    if (!identical(_links[link.deviceKey], link)) {
      return;
    }

    link.reconnectTimer?.cancel();
    link.reconnectTimer = null;
    _cancelLinkRace(link);

    final generation = ++link.generation;
    _stopLinkChannel(link);
    link.lastPong = null;
    link.connectedSince = null;
    link.connectStartedAt = null;
    link.status = ConnectionStatus.connecting;
    notifyListeners();

    final ranked = _rankedDeviceCandidateIps(link.server);
    if (ranked.isEmpty) {
      AppLogger.warning(
        '设备 ${link.server.displayName} 没有可用候选地址，保持断开',
      );
      link.status = ConnectionStatus.disconnected;
      notifyListeners();
      _scheduleLinkBackoffReconnect(link, reason: 'no candidates');
      return;
    }
    _logDeviceCandidateRanking(link.server, ranked, reason: reason);
    final candidates = ranked
        .take(_tuning.savedRaceCandidateCount)
        .toList(growable: false);
    final timeout = _attemptTimeout();
    AppLogger.info(
      '设备并行竞速开始: device=${link.server.displayName} '
      'key=${link.deviceKey} candidates=${candidates.join(", ")} '
      'networkKey=${_networkKeyForLog()} '
      'attemptTimeout=${timeout.inMilliseconds}ms '
      'budget=${_tuning.raceBudget.inMilliseconds}ms reason=$reason',
    );

    final handle = _connectionRace.start(
      candidates: candidates,
      attempt: (candidate, cancellation) => _probeSavedCandidate(
        ip: candidate.ip,
        port: link.server.port,
        timeout: timeout,
        cancellation: cancellation,
      ),
      isCancelled: () =>
          link.disposed ||
          _disposed ||
          generation != link.generation ||
          !identical(_links[link.deviceKey], link),
      attemptTimeout: timeout,
      budget: _tuning.raceBudget,
      onAttemptStarted: (candidate, launchDelay) => AppLogger.info(
        '设备候选探测启动: device=${link.server.displayName} '
        'ip=${candidate.ip} stagger=${launchDelay.inMilliseconds}ms '
        'networkKey=${_networkKeyForLog()}',
      ),
      onAttemptFailed: (failure) => AppLogger.warning(
        '设备候选探测失败: device=${link.server.displayName} '
        'ip=${failure.candidate.ip} reason=${failure.reason.name} '
        'elapsed=${failure.elapsed.inMilliseconds}ms '
        'networkKey=${_networkKeyForLog()}',
      ),
      onWinner: (outcome) => AppLogger.info(
        '设备候选探测 winner: device=${link.server.displayName} '
        'ip=${outcome.candidate.ip} elapsed=${outcome.elapsed.inMilliseconds}ms '
        'attempt=${outcome.attemptElapsed.inMilliseconds}ms '
        'networkKey=${_networkKeyForLog()}',
      ),
    );
    link.race = handle;
    unawaited(
      handle.done.then(
        (result) => _handleDeviceRaceCompleted(
          link: link,
          generation: generation,
          result: result,
        ),
      ),
    );
  }

  Future<void> _handleDeviceRaceCompleted({
    required _DeviceLink link,
    required int generation,
    required ConnectionRaceResult result,
  }) async {
    if (link.disposed || _disposed || generation != link.generation) {
      return;
    }
    if (!identical(_links[link.deviceKey], link)) {
      return;
    }
    link.race = null;
    if (result.cancelled) {
      AppLogger.info(
        '设备 ${link.server.displayName} 竞速被取消（generation 变化/网络切换/移除）',
      );
      return;
    }

    final winner = result.winner;
    if (winner == null) {
      AppLogger.warning(
        '设备 ${link.server.displayName} 竞速全部失败: '
        'failures=${_describeRaceFailures(result.failures)} '
        'budgetExhausted=${result.budgetExhausted} '
        'networkKey=${_networkKeyForLog()}',
      );
      await _recordDeviceRaceFailures(link, result.failures);
      if (link.disposed || generation != link.generation) {
        return;
      }
      _enterLinkReconnectBackoff(link, reason: 'device race failed');
      return;
    }

    // 失败候选只累加失败计数，绝不写入成功历史；成功历史等正式 connected 后再写。
    await _recordDeviceRaceFailures(link, result.failures);
    if (link.disposed || generation != link.generation) {
      return;
    }
    link.currentIp = winner.candidate.ip;
    AppLogger.info(
      '设备 ${link.server.displayName} 竞速胜出，开始正式建链: '
      'ip=${link.currentIp}:${link.server.port} '
      'raceElapsed=${result.elapsed.inMilliseconds}ms '
      'networkKey=${_networkKeyForLog()}',
    );
    _connectDevice(link, reason: 'device race winner');
  }

  /// 并行探测一个已保存候选：只要求收到 `connected`（保持旧串行实现语义）。
  Future<bool> _probeSavedCandidate({
    required String ip,
    required int port,
    required Duration timeout,
    required RaceCancellation cancellation,
  }) async {
    return _probeChannel(
      ip: ip,
      port: port,
      timeout: timeout,
      cancellation: cancellation,
      requireQrScanPong: false,
      logLabel: '已保存候选',
    );
  }

  /// 并行探测一个 QR 候选：必须完成 connected + ping(source=qr_scan) + pong。
  Future<bool> _probeQrCandidate({
    required String ip,
    required int port,
    required Duration timeout,
    required RaceCancellation cancellation,
  }) async {
    return _probeChannel(
      ip: ip,
      port: port,
      timeout: timeout,
      cancellation: cancellation,
      requireQrScanPong: true,
      logLabel: 'QR 候选',
    );
  }

  /// 统一的手握探测实现：建链 → （QR 场景）ping(qr_scan) → pong。
  ///
  /// 该 Future 一定会在成功/失败/超时/竞速取消时完成；finally 成对取消
  /// subscription 并关闭 sink，避免并行竞速产生连接泄漏。
  Future<bool> _probeChannel({
    required String ip,
    required int port,
    required Duration timeout,
    required RaceCancellation cancellation,
    required bool requireQrScanPong,
    required String logLabel,
  }) async {
    if (cancellation.isCancelled) {
      return false;
    }
    VoicingWebSocketChannel? probeChannel;
    StreamSubscription<dynamic>? subscription;
    final completer = Completer<bool>();
    var finished = false;
    final startedAt = DateTime.now();

    void finish(bool success) {
      if (finished) {
        return;
      }
      finished = true;
      if (!completer.isCompleted) {
        completer.complete(success);
      }
    }

    cancellation.whenCancelled(() {
      if (!finished) {
        AppLogger.info(
          '$logLabel探测取消: ip=$ip elapsed=${DateTime.now().difference(startedAt).inMilliseconds}ms '
          'networkKey=${_networkKeyForLog()}',
        );
      }
      finish(false);
    });

    try {
      probeChannel = _channelFactory(
        Uri.parse('ws://$ip:$port'),
        connectTimeout: timeout,
        preferNativeWifi: Platform.isAndroid,
      );
      subscription = probeChannel.stream.listen(
        (message) {
          try {
            final data = VoicingProtocol.decodeMessage(message);
            final type = data?['type'];
            if (type == VoicingProtocol.typeConnected) {
              if (requireQrScanPong) {
                final sendFuture = probeChannel?.sink.add(
                  json.encode(VoicingProtocol.buildQrScanProbeMessage()),
                );
                if (sendFuture != null) {
                  unawaited(
                    sendFuture.catchError((Object error, StackTrace stackTrace) {
                      AppLogger.warning(
                        '$logLabel探测消息发送失败: ip=$ip',
                        error: error,
                        stackTrace: stackTrace,
                      );
                      finish(false);
                    }),
                  );
                }
              } else {
                finish(true);
              }
            } else if (type == VoicingProtocol.typePong) {
              finish(true);
            }
          } catch (error, stackTrace) {
            AppLogger.warning(
              '$logLabel消息解析失败: ip=$ip',
              error: error,
              stackTrace: stackTrace,
            );
            finish(false);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          AppLogger.warning(
            '$logLabel探测失败: ip=$ip '
            'elapsed=${DateTime.now().difference(startedAt).inMilliseconds}ms '
            'networkKey=${_networkKeyForLog()}',
            error: error,
            stackTrace: stackTrace,
          );
          finish(false);
        },
        onDone: () => finish(false),
      );
      return await completer.future;
    } catch (error, stackTrace) {
      AppLogger.warning(
        '$logLabel建链失败: ip=$ip '
        'elapsed=${DateTime.now().difference(startedAt).inMilliseconds}ms '
        'networkKey=${_networkKeyForLog()}',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      if (subscription != null) {
        unawaited(subscription.cancel());
      }
      final currentChannel = probeChannel;
      if (currentChannel != null) {
        unawaited(currentChannel.sink.close());
      }
    }
  }

  /// 已保存设备的候选评分排序（networkKey 命中 > 同子网 > Tailscale > ...）。
  List<String> _rankedDeviceCandidateIps(SavedServer saved) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final book = saved.addressBook;
    final ranked = <String>[];
    final seen = <String>{};
    for (final ip in book.rankedIpsFor(
      _networkSnapshot,
      nowMs: nowMs,
      weights: _tuning.addressWeights,
    )) {
      if (ip.isNotEmpty && seen.add(ip)) {
        ranked.add(ip);
      }
    }
    // 防御：地址簿万一缺失候选（旧数据被裁剪/手工改坏），仍把 ip/ips 补到末尾。
    for (final ip in saved.candidateIps) {
      if (seen.add(ip)) {
        ranked.add(ip);
      }
    }
    return ranked;
  }

  void _logDeviceCandidateRanking(
    SavedServer saved,
    List<String> ranked, {
    required String reason,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final book = saved.addressBook;
    final parts = <String>[];
    for (final ip in ranked) {
      final entry = book.addressFor(ip);
      final score = entry == null
          ? 0
          : book.scoreOf(
              entry,
              _networkSnapshot,
              nowMs: nowMs,
              weights: _tuning.addressWeights,
            );
      parts.add(
        '$ip(score=$score, key=${entry?.networkKey ?? ""}, '
        'ok=${entry?.successCount ?? 0}, fail=${entry?.failureCount ?? 0})',
      );
    }
    AppLogger.info(
      '候选评分排序 device=${saved.displayName} networkKey=${_networkKeyForLog()}: '
      '${parts.join(" > ")}; reason=$reason',
    );
  }

  /// 把竞速中真实探测失败的候选计入该设备的地址簿失败计数（不写成功历史）。
  Future<void> _recordDeviceRaceFailures(
    _DeviceLink link,
    Iterable<RaceFailure> failures,
  ) async {
    final attempted = failures
        .where(
          (failure) =>
              failure.reason == RaceFailureReason.failed ||
              failure.reason == RaceFailureReason.timeout,
        )
        .toList(growable: false);
    if (attempted.isEmpty) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var book = link.server.addressBook;
    for (final failure in attempted) {
      book = book.recordFailure(ip: failure.candidate.ip, nowMs: nowMs);
    }
    book = book.trimmed(
      nowMs: nowMs,
      maxAddresses: _tuning.addressBookMaxAddresses,
    );
    final updated = link.server.copyWith(
      ips: SavedServer.normalizeIpCandidates(
        link.server.ip,
        <dynamic>[...link.server.candidateIps, ...book.ips],
      ),
      addresses: book,
    );
    if (updated == link.server) {
      return;
    }
    link.server = updated;
    AppLogger.info(
      '记录候选失败计数: device=${updated.displayName} '
      'ips=${attempted.map((failure) => failure.candidate.ip).join(", ")} '
      'networkKey=${_networkKeyForLog()}',
    );
    _schedulePersistDevices();
  }

  /// 对 winner 建立正式 WebSocket 连接（单设备单 channel）。
  void _connectDevice(
    _DeviceLink link, {
    bool preferNativeWifi = true,
    Duration? connectTimeout,
    String reason = '',
  }) {
    if (link.disposed || _disposed) {
      return;
    }
    final connectionId = ++link.generation;
    final bool foregroundRecoveryActive = _isForegroundRecoveryActive();
    link.status = ConnectionStatus.connecting;
    link.reconnectTimer?.cancel();
    link.reconnectTimer = null;
    _stopLinkChannel(link);
    link.lastPong = null;
    link.connectStartedAt = DateTime.now();
    link.connectedSince = null;
    final timeout = connectTimeout ??
        _recoveryPolicy.resolveConnectTimeout(
          foregroundRecoveryActive: foregroundRecoveryActive,
        );
    AppLogger.info(
      '建立正式连接: device=${link.server.displayName} key=${link.deviceKey} '
      'id=$connectionId ip=${link.currentIp}:${link.server.port} '
      'timeout=${timeout.inMilliseconds}ms '
      'networkKey=${_networkKeyForLog()} reason=${reason.isEmpty ? "connect" : reason}',
    );

    try {
      final channel = _channelFactory(
        Uri.parse('ws://${link.currentIp}:${link.server.port}'),
        connectTimeout: timeout,
        preferNativeWifi: preferNativeWifi,
      );
      link.channel = channel;
      link.subscription = channel.stream.listen(
        (message) => _handleDeviceMessage(link, message, connectionId),
        onError: (error, stackTrace) {
          if (connectionId != link.generation || link.disposed) {
            return;
          }
          _logDeviceConnectFailure(
            link,
            'WebSocket error',
            error: error,
            stackTrace: stackTrace,
          );
          _handleDeviceDisconnect(link, connectionId: connectionId);
        },
        onDone: () {
          if (connectionId != link.generation || link.disposed) {
            return;
          }
          _logDeviceConnectFailure(link, 'WebSocket closed');
          _handleDeviceDisconnect(link, connectionId: connectionId);
        },
      );
    } catch (error, stackTrace) {
      if (connectionId != link.generation || link.disposed) {
        return;
      }
      _logDeviceConnectFailure(
        link,
        'Connection error',
        error: error,
        stackTrace: stackTrace,
      );
      _handleDeviceDisconnect(link, connectionId: connectionId);
    }
    notifyListeners();
  }

  void _logDeviceConnectFailure(
    _DeviceLink link,
    String reason, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final elapsed = link.connectStartedAt == null
        ? null
        : DateTime.now().difference(link.connectStartedAt!);
    AppLogger.warning(
      '连接失败: device=${link.server.displayName} '
      'ip=${link.currentIp}:${link.server.port} reason=$reason '
      'elapsed=${elapsed?.inMilliseconds ?? 0}ms '
      'networkKey=${_networkKeyForLog()}',
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _handleDeviceMessage(
    _DeviceLink link,
    dynamic message,
    int connectionId,
  ) {
    if (connectionId != link.generation || link.disposed) {
      return;
    }

    try {
      final data = VoicingProtocol.decodeMessage(message);
      if (data == null) {
        return;
      }

      final type = data['type'];
      if (type == VoicingProtocol.typeConnected) {
        _endForegroundRecovery();
        link.status = ConnectionStatus.connected;
        link.syncEnabled = data['sync_enabled'] ?? true;
        link.reconnectAttempt = 0;
        link.lastPong = DateTime.now();
        link.connectedSince = DateTime.now();
        link.reconnectTimer?.cancel();
        link.reconnectTimer = null;
        final connectElapsed = link.connectStartedAt == null
            ? null
            : DateTime.now().difference(link.connectStartedAt!);
        AppLogger.info(
          '连接成功: device=${link.server.displayName} '
          'key=${link.deviceKey} ip=${link.currentIp}:${link.server.port} '
          'elapsed=${connectElapsed?.inMilliseconds ?? 0}ms '
          'networkKey=${_networkKeyForLog()}',
        );
        // 只有真正收到 connected 才写成功历史 + 提升 primary。
        _maybeUpdateDeviceFromConnectedMessage(link, data);
        _ensureHeartbeatTimer();
        notifyListeners();
      } else if (type == VoicingProtocol.typeAck) {
        // 多设备下只有当前活跃设备的 ACK 才允许清空输入框，避免别的设备
        // 迟到 ACK 把用户正在给活跃设备输入的内容清掉。
        if (!_isActiveLink(link)) {
          return;
        }
        final shouldClearInput = data['clear_input'];
        if (shouldClearInput is bool ? shouldClearInput : true) {
          textController.clear();
        }
      } else if (type == VoicingProtocol.typeSyncDisabled) {
        link.lastPong = DateTime.now();
        link.syncEnabled = data['sync_enabled'] ?? false;
        notifyListeners();
      } else if (type == VoicingProtocol.typeSyncState ||
          type == VoicingProtocol.typePong) {
        link.lastPong = DateTime.now();
        link.syncEnabled = data['sync_enabled'] ?? true;
        notifyListeners();
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Message parse error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  bool _isActiveLink(_DeviceLink link) {
    return identical(_activeLink, link);
  }

  /// 正式 connected 后才调用：写成功历史（网络 Key + 计数）并提升 primary。
  void _maybeUpdateDeviceFromConnectedMessage(
    _DeviceLink link,
    Map<String, dynamic> data,
  ) {
    final current = link.server;
    final connectedDeviceId = SavedServer.readString(data['device_id']);
    if (current.hasDeviceId &&
        connectedDeviceId.isNotEmpty &&
        current.deviceId != connectedDeviceId) {
      AppLogger.warning(
        '已保存设备与连接设备不一致: saved=${current.deviceId}, '
        'connected=$connectedDeviceId device=${current.displayName}',
      );
      return;
    }

    final connectedName = SavedServer.readString(data['name']).isNotEmpty
        ? SavedServer.readString(data['name'])
        : SavedServer.readString(data['computer_name']);
    final connectedOs = SavedServer.readString(data['os']);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final networkContext = _currentNetworkContext();
    final book = current.addressBook
        .recordSuccess(
          ip: link.currentIp,
          networkKey: networkContext.networkKey,
          networkKind: networkContext.networkKind,
          nowMs: nowMs,
        )
        .trimmed(
          nowMs: nowMs,
          maxAddresses: _tuning.addressBookMaxAddresses,
        );
    final updated = current.copyWith(
      deviceId: current.hasDeviceId ? current.deviceId : connectedDeviceId,
      ip: link.currentIp,
      ips: SavedServer.normalizeIpCandidates(
        link.currentIp,
        <dynamic>[...current.candidateIps, ...book.ips],
      ),
      port: link.server.port,
      name: connectedName.isNotEmpty ? connectedName : current.name,
      os: connectedOs.isNotEmpty ? connectedOs : current.os,
      lastConnectedTs: nowMs,
      addresses: book,
    );

    if (updated == current) {
      return;
    }

    final oldKey = current.deviceKey;
    link.server = updated;
    _syncLinkKey(link, oldKey);
    AppLogger.info(
      '记录连接成功历史: device=${updated.displayName} key=${updated.deviceKey} '
      'ip=${link.currentIp} networkKey=${_networkKeyForLog()} '
      'ok=${updated.addressBook.addressFor(link.currentIp)?.successCount ?? 0} '
      'networkKeys=${book.successfulNetworkKeys.join("|")}',
    );
    _schedulePersistDevices();
  }

  // ---------------------------------------------------------------------------
  // 断线重连 / 心跳
  // ---------------------------------------------------------------------------

  void _handleDeviceDisconnect(_DeviceLink link, {int? connectionId}) {
    if (link.disposed || _disposed) {
      return;
    }
    if (connectionId != null && connectionId != link.generation) {
      return;
    }

    final now = DateTime.now();
    final bool foregroundRecoveryActive = _isForegroundRecoveryActive(now: now);
    _cancelLinkRace(link);
    if (link.status == ConnectionStatus.connected) {
      final connectedFor = link.connectedSince == null
          ? null
          : now.difference(link.connectedSince!);
      AppLogger.warning(
        '连接断开: device=${link.server.displayName} '
        'ip=${link.currentIp}:${link.server.port} '
        'connectedFor=${connectedFor?.inMilliseconds ?? 0}ms '
        'networkKey=${_networkKeyForLog()}',
      );
    }
    // 递增 generation：同一 socket 可能连续触发 onError + onDone，
    // 只有第一次进入这里会真正改变状态并安排重连。
    link.generation++;
    _stopLinkChannel(link);
    link.status = foregroundRecoveryActive
        ? ConnectionStatus.connecting
        : ConnectionStatus.disconnected;
    link.syncEnabled = true;
    link.lastPong = null;
    link.connectedSince = null;
    link.connectStartedAt = null;
    notifyListeners();
    _scheduleLinkBackoffReconnect(
      link,
      foregroundRecoveryActive: foregroundRecoveryActive,
      reason: 'connection lost',
    );
  }

  void _enterLinkReconnectBackoff(_DeviceLink link, {required String reason}) {
    if (link.disposed || _disposed) {
      return;
    }
    final now = DateTime.now();
    final bool foregroundRecoveryActive = _isForegroundRecoveryActive(now: now);
    link.status = foregroundRecoveryActive
        ? ConnectionStatus.connecting
        : ConnectionStatus.disconnected;
    link.syncEnabled = true;
    notifyListeners();
    _scheduleLinkBackoffReconnect(
      link,
      foregroundRecoveryActive: foregroundRecoveryActive,
      reason: reason,
    );
  }

  void _scheduleLinkBackoffReconnect(
    _DeviceLink link, {
    required String reason,
    bool? foregroundRecoveryActive,
  }) {
    if (link.disposed || _disposed) {
      return;
    }
    if (!identical(_links[link.deviceKey], link)) {
      return;
    }
    final bool activeRecovery =
        foregroundRecoveryActive ?? _isForegroundRecoveryActive();
    final reconnectDelay = _recoveryPolicy.reconnectDelay(
      reconnectAttempt: link.reconnectAttempt,
      foregroundRecoveryActive: activeRecovery,
    );
    link.reconnectAttempt = activeRecovery ? 0 : link.reconnectAttempt + 1;

    AppLogger.info(
      '计划重连: device=${link.server.displayName} '
      'delay=${reconnectDelay.inMilliseconds}ms '
      'attempt=${link.reconnectAttempt} reason=$reason '
      'networkKey=${_networkKeyForLog()}',
    );
    link.reconnectTimer?.cancel();
    link.reconnectTimer = Timer(
      reconnectDelay,
      () {
        if (link.disposed || _disposed) {
          return;
        }
        if (!identical(_links[link.deviceKey], link)) {
          return;
        }
        if (link.status == ConnectionStatus.connected) {
          return;
        }
        _beginDeviceRace(link, reason: reason);
      },
    );
  }

  void _ensureHeartbeatTimer() {
    if (_heartbeatTimer != null || _disposed) {
      return;
    }
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: VoicingProtocol.heartbeatIntervalSec),
      (_) => _checkHeartbeats(),
    );
  }

  void _stopHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _checkHeartbeats() {
    if (_disposed || _links.isEmpty) {
      _stopHeartbeatTimer();
      return;
    }
    final now = DateTime.now();
    for (final link in _links.values.toList(growable: false)) {
      if (link.disposed || !link.connected) {
        continue;
      }
      if (_recoveryPolicy.isHeartbeatExpired(
        status: link.status,
        lastPong: link.lastPong,
        now: now,
      )) {
        final elapsed =
            link.lastPong == null ? 0 : now.difference(link.lastPong!).inSeconds;
        AppLogger.warning(
          '心跳超时 (${elapsed}s)，判定设备 ${link.server.displayName} 连接死亡',
        );
        _handleDeviceDisconnect(link);
        continue;
      }
      _sendPing(link);
    }
    if (!_links.values.any((link) => !link.disposed && link.connected)) {
      _stopHeartbeatTimer();
    }
  }

  void _sendPing(_DeviceLink link) {
    final generation = link.generation;
    unawaited(
      () async {
        try {
          await link.channel?.sink.add(
            json.encode(VoicingProtocol.buildPingMessage()),
          );
        } catch (error, stackTrace) {
          AppLogger.warning(
            'Ping 发送失败: device=${link.server.displayName}',
            error: error,
            stackTrace: stackTrace,
          );
          if (link.disposed || generation != link.generation) {
            return;
          }
          _handleDeviceDisconnect(link);
        }
      }(),
    );
  }

  // ---------------------------------------------------------------------------
  // 前台恢复
  // ---------------------------------------------------------------------------

  void _beginForegroundRecovery() {
    final now = DateTime.now();
    _foregroundRecoveryUntil = _recoveryPolicy.startForegroundRecovery(now);
    _displayConnectedDuringForegroundRecovery = status == ConnectionStatus.connected;
    _foregroundRecoveryTimer?.cancel();
    _foregroundRecoveryTimer = Timer(
      _foregroundRecoveryUntil!.difference(now),
      () {
        if (_displayConnectedDuringForegroundRecovery) {
          _displayConnectedDuringForegroundRecovery = false;
          notifyListeners();
        }
      },
    );
    notifyListeners();
  }

  void _endForegroundRecovery() {
    _foregroundRecoveryUntil = null;
    _foregroundRecoveryTimer?.cancel();
    _foregroundRecoveryTimer = null;
    _displayConnectedDuringForegroundRecovery = false;
  }

  bool _isForegroundRecoveryActive({DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    final active = _recoveryPolicy.isForegroundRecoveryActive(
      recoveryUntil: _foregroundRecoveryUntil,
      now: currentTime,
    );
    if (!active) {
      _foregroundRecoveryUntil = null;
    }
    return active;
  }

  // ---------------------------------------------------------------------------
  // 文本发送（只发往活跃设备）
  // ---------------------------------------------------------------------------

  void recallLastText() {
    if (_sentTextHistory.isEmpty) {
      return;
    }

    final previousIndex = _recallHistoryIndex;
    final nextIndex = previousIndex == null
        ? _sentTextHistory.length - 1
        : previousIndex > 0
            ? previousIndex - 1
            : 0;
    _recallHistoryIndex = nextIndex;
    final recalledText = _sentTextHistory[nextIndex];

    textController.text = recalledText;
    textController.selection = TextSelection.fromPosition(
      TextPosition(offset: recalledText.length),
    );
  }

  Future<void> sendText() async {
    final link = _activeLink;
    final text = textController.text.trim();
    if (text.isEmpty ||
        link == null ||
        !link.connected ||
        !link.syncEnabled) {
      return;
    }

    if (_hasPendingShadowBuffer(text)) {
      await _finalizeShadowInput(forceEnter: _autoEnterEnabled);
      return;
    }

    _shadowFinalizeTimer?.cancel();
    try {
      await link.channel?.sink.add(
        json.encode(
          VoicingProtocol.buildTextMessage(
            text,
            autoEnter: _autoEnterEnabled,
            sendMode: VoicingProtocol.textSendModeSubmit,
          ),
        ),
      );
      _recordSentText(text);
      _lastSentLength = 0;
    } catch (error, stackTrace) {
      AppLogger.error('发送失败', error: error, stackTrace: stackTrace);
      _handleDeviceDisconnect(link);
    }
  }

  void _onTextControllerChanged() {
    final currentText = textController.text;

    if (currentText.length < _lastSentLength) {
      _lastSentLength = currentText.length;
    }

    final link = _activeLink;
    if (!_shadowModeEnabled ||
        link == null ||
        !link.connected ||
        !link.syncEnabled) {
      return;
    }

    final composing = textController.value.composing;
    final isComposing = composing.isValid && !composing.isCollapsed;
    if (_wasComposing && !isComposing) {
      unawaited(_sendShadowIncrement(currentText));
    }

    _wasComposing = isComposing;
  }

  Future<void> _sendShadowIncrement(String currentText) async {
    if (currentText.length <= _lastSentLength) {
      return;
    }

    final link = _activeLink;
    if (link == null || !link.connected) {
      return;
    }

    final increment = currentText.substring(_lastSentLength);
    try {
      await link.channel?.sink.add(
        json.encode(
          VoicingProtocol.buildTextMessage(
            increment,
            autoEnter: false,
            sendMode: VoicingProtocol.textSendModeShadow,
          ),
        ),
      );
      _lastSentLength = currentText.length;
      _lastSentText = currentText;
      _scheduleShadowFinalize();
    } catch (error, stackTrace) {
      AppLogger.warning('自动发送失败', error: error, stackTrace: stackTrace);
    }
  }

  bool _hasPendingShadowBuffer(String text) {
    return _lastSentLength > 0 &&
        _lastSentLength == text.length &&
        _lastSentText == text;
  }

  void _scheduleShadowFinalize() {
    _shadowFinalizeTimer?.cancel();
    _shadowFinalizeTimer = Timer(
      _shadowFinalizeDelay,
      () => unawaited(_finalizeShadowInput(forceEnter: _autoEnterEnabled)),
    );
  }

  Future<void> _finalizeShadowInput({required bool forceEnter}) async {
    _shadowFinalizeTimer?.cancel();
    _shadowFinalizeTimer = null;

    final link = _activeLink;
    final currentText = textController.text.trim();
    if (!_hasPendingShadowBuffer(currentText)) {
      return;
    }

    if (forceEnter && link != null && link.connected && link.syncEnabled) {
      try {
        await link.channel?.sink.add(
          json.encode(
            VoicingProtocol.buildTextMessage(
              '',
              autoEnter: true,
              sendMode: VoicingProtocol.textSendModeCommit,
            ),
          ),
        );
        _recordSentText(currentText);
        _wasComposing = false;
        return;
      } catch (error, stackTrace) {
        AppLogger.warning('自动 Enter 提交失败',
            error: error, stackTrace: stackTrace);
        _handleDeviceDisconnect(link);
        return;
      }
    }

    _recordSentText(currentText);
    _lastSentLength = 0;
    _wasComposing = false;
    textController.clear();
  }

  void _recordSentText(String text) {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return;
    }

    _lastSentText = normalizedText;
    _sentTextHistory.add(normalizedText);
    if (_sentTextHistory.length > _maxSentTextHistory) {
      _sentTextHistory.removeRange(
        0,
        _sentTextHistory.length - _maxSentTextHistory,
      );
    }
    _recallHistoryIndex = null;
  }

  // ---------------------------------------------------------------------------
  // 持久化
  // ---------------------------------------------------------------------------

  /// 把当前设备列表 + 活跃设备 Key 追加到串行写队列（保证写入顺序）。
  void _schedulePersistDevices() {
    if (_disposed) {
      return;
    }
    final servers = _links.values
        .where((link) => !link.disposed)
        .map((link) => link.server)
        .toList(growable: false);
    final activeKey = _activeDeviceKey ?? '';
    _persistQueue = _persistQueue
        .then((_) => _persistDevicesSnapshot(servers, activeKey))
        .catchError((Object error, StackTrace stackTrace) {
      AppLogger.warning('保存设备列表失败', error: error, stackTrace: stackTrace);
    });
  }

  Future<void> _persistDevicesSnapshot(
    List<SavedServer> servers,
    String activeKey,
  ) async {
    try {
      await _savedServerStore.saveAll(servers, activeDeviceKey: activeKey);
      AppLogger.info(
        '保存设备列表: count=${servers.length} active=$activeKey '
        'devices=${servers.map((server) => server.displayName).join(" | ")}',
      );
    } catch (error, stackTrace) {
      AppLogger.warning('保存设备列表失败', error: error, stackTrace: stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // 辅助
  // ---------------------------------------------------------------------------

  /// 当前网络环境上下文（记录成功历史用）：networkKey 描述手机所在网络。
  SavedAddressNetworkContext _currentNetworkContext() {
    return SavedAddressNetworkContext(
      networkKey: _networkSnapshot.networkKey,
      networkKind: _networkSnapshot.networkKey.isEmpty
          ? 'unknown'
          : _networkSnapshot.primaryKind,
    );
  }

  String _networkKeyForLog() {
    final key = _networkSnapshot.networkKey;
    return key.isEmpty ? 'unknown' : key;
  }

  Duration _attemptTimeout() {
    return _tuning.attemptTimeoutFor(networkKnown: _networkSnapshot.isKnown);
  }

  String _describeRaceFailures(Iterable<RaceFailure> failures) {
    return failures
        .map(
          (failure) =>
              '${failure.candidate.ip}:${failure.reason.name}'
              '/${failure.elapsed.inMilliseconds}ms',
        )
        .join(', ');
  }

  void _cancelLinkRace(_DeviceLink link) {
    final handle = link.race;
    link.race = null;
    handle?.cancel();
  }

  void _stopLinkChannel(_DeviceLink link) {
    final subscription = link.subscription;
    link.subscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    final channel = link.channel;
    link.channel = null;
    if (channel != null) {
      unawaited(channel.sink.close());
    }
  }

  void _disposeLink(_DeviceLink link) {
    link.disposed = true;
    link.generation++;
    link.reconnectTimer?.cancel();
    link.reconnectTimer = null;
    _cancelLinkRace(link);
    _stopLinkChannel(link);
  }

  void _setFallbackDisconnectedState() {
    _syncEnabledFallback = true;
    notifyListeners();
  }

  /// 测试/演示用：只重置内存态，不动已持久化的设备列表。
  void resetStubForDemo() {
    _qrPairingGeneration++;
    _qrRace?.cancel();
    _qrRace = null;
    final links = _links.values.toList(growable: false);
    _links.clear();
    _activeDeviceKey = null;
    for (final link in links) {
      _disposeLink(link);
    }
    _qrScanMode = false;
    _lastQrCorners = null;
    _qrPairingSucceeded = false;
    _qrPairingFailed = false;
    notifyListeners();
  }

  Future<void> _loadAutoEnterPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoEnterEnabled = prefs.getBool('auto_enter_enabled') ?? false;
      AppLogger.info('加载自动 Enter 设置: $_autoEnterEnabled');
    } catch (error, stackTrace) {
      AppLogger.warning('加载自动 Enter 设置失败',
          error: error, stackTrace: stackTrace);
    }
  }

  Future<void> toggleAutoEnter() async {
    _autoEnterEnabled = !_autoEnterEnabled;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_enter_enabled', _autoEnterEnabled);
      AppLogger.info('保存自动 Enter 设置: $_autoEnterEnabled');
    } catch (error, stackTrace) {
      AppLogger.warning('保存自动 Enter 设置失败',
          error: error, stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    // 让在途 QR 配对流程失效：_finishQrPairing 内部有 760/1100/1700ms 的
    // reveal/hold 延时，页面在窗口内销毁时必须在每个 await 后看到 generation
    // 变化/扫码态关闭，否则会在 disposed ChangeNotifier 上 notifyListeners。
    _qrPairingGeneration++;
    _qrScanMode = false;
    _lastQrCorners = null;
    _qrPairingSucceeded = false;
    _qrPairingFailed = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _foregroundRecoveryTimer?.cancel();
    _foregroundRecoveryTimer = null;
    _shadowFinalizeTimer?.cancel();
    _shadowFinalizeTimer = null;
    final qrRace = _qrRace;
    _qrRace = null;
    qrRace?.cancel();
    final subscription = _networkSubscription;
    _networkSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    unawaited(_networkProvider.dispose());
    final links = _links.values.toList(growable: false);
    _links.clear();
    _activeDeviceKey = null;
    for (final link in links) {
      _disposeLink(link);
    }
    textController.removeListener(_onTextControllerChanged);
    textController.dispose();
    super.dispose();
  }

}
