import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';
import 'connection_recovery_policy.dart';
import 'saved_server.dart';
import 'voicing_protocol.dart';
import 'voicing_websocket.dart';

typedef DeviceReplacementPrompt = Future<bool> Function(
  SavedServer current,
  SavedServer incoming,
);

class VoicingConnectionController extends ChangeNotifier {
  static const Duration _shadowFinalizeDelay = Duration(milliseconds: 700);
  static const Duration _qrResultRevealDelay = Duration(milliseconds: 760);
  static const Duration _qrSuccessHoldDelay = Duration(milliseconds: 1100);
  static const Duration _qrFailureHoldDelay = Duration(milliseconds: 1700);
  static const Duration _qrProbeTimeout = Duration(seconds: 3);
  static const Duration _savedCandidateConnectTimeout = Duration(seconds: 2);
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
    DeviceReplacementPrompt? confirmDeviceReplacement,
  })  : _recoveryPolicy = recoveryPolicy,
        _savedServerStore = savedServerStore,
        _confirmDeviceReplacement = confirmDeviceReplacement {
    textController.addListener(_onTextControllerChanged);
  }

  final TextEditingController textController = TextEditingController();
  final ConnectionRecoveryPolicy _recoveryPolicy;
  final SavedServerStore _savedServerStore;
  final DeviceReplacementPrompt? _confirmDeviceReplacement;

  VoicingWebSocketChannel? _channel;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  bool _syncEnabled = true;
  bool _autoEnterEnabled = false;
  Timer? _reconnectTimer;
  String _serverIp = VoicingProtocol.defaultServerIp;
  int _serverPort = VoicingProtocol.websocketPort;
  String _lastSentText = '';
  final List<String> _sentTextHistory = <String>[];
  int? _recallHistoryIndex;
  final bool _shadowModeEnabled = true;
  int _lastSentLength = 0;
  bool _wasComposing = false;
  Timer? _heartbeatTimer;
  DateTime? _lastPong;
  int _reconnectAttempt = 0;
  int _connectionGeneration = 0;
  DateTime? _foregroundRecoveryUntil;
  Timer? _foregroundRecoveryTimer;
  Timer? _shadowFinalizeTimer;
  bool _displayConnectedDuringForegroundRecovery = false;
  SavedServer? _savedServer;
  bool _manualMode = false;
  List<String> _savedCandidateAttempts = const [];
  int _savedCandidateAttemptIndex = 0;
  int? _savedCandidateConnectionId;

  ConnectionStatus get status => _status;
  ConnectionStatus get displayStatus =>
      _displayConnectedDuringForegroundRecovery
          ? ConnectionStatus.connected
          : _status;
  bool get syncEnabled => _syncEnabled;
  bool get autoEnterEnabled => _autoEnterEnabled;
  String get serverIp => _serverIp;
  int get serverPort => _serverPort;
  String get lastSentText => _lastSentText;

  bool _qrScanMode = false;
  List<Offset>? _lastQrCorners;
  bool _qrPairingSucceeded = false;
  bool _qrPairingFailed = false;
  int _qrPairingGeneration = 0;

  bool get qrScanMode => _qrScanMode;
  bool get hasStoredServer => _savedServer != null;
  SavedServer? get savedServer => _savedServer;
  List<Offset>? get lastQrCorners => _lastQrCorners;
  bool get qrPairingSucceeded => _qrPairingSucceeded;
  bool get qrPairingFailed => _qrPairingFailed;

  void enterQrScanMode() {
    _qrPairingGeneration++;
    _qrScanMode = true;
    _qrPairingSucceeded = false;
    _qrPairingFailed = false;
    notifyListeners();
  }

  void exitQrScanMode() {
    _qrPairingGeneration++;
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
    SavedServer? connectedServer;
    for (final candidateIp in qrCandidateIps) {
      if (generation != _qrPairingGeneration || !_qrScanMode) {
        return;
      }
      final candidateServer = scannedServer.copyWith(
        ip: candidateIp,
        ips: qrCandidateIps,
      );
      final success = await _probeQrConnection(
        candidateServer.ip,
        candidateServer.port,
      );
      if (success) {
        connectedServer = candidateServer;
        break;
      }
    }
    await _finishQrPairing(
      startedAt: startedAt,
      success: connectedServer != null,
      generation: generation,
      scannedServer: connectedServer,
    );
  }

  Future<bool> _probeQrConnection(String ip, int port) async {
    if (Platform.isAndroid) {
      return _probeQrConnectionOnce(
        ip,
        port,
        preferNativeWifi: true,
      );
    }

    return _probeQrConnectionOnce(
      ip,
      port,
      preferNativeWifi: false,
    );
  }

  Future<bool> _probeQrConnectionOnce(
    String ip,
    int port, {
    required bool preferNativeWifi,
  }) async {
    VoicingWebSocketChannel? probeChannel;
    StreamSubscription<dynamic>? subscription;
    Timer? timeoutTimer;
    final completer = Completer<bool>();

    void finish(bool success) {
      if (!completer.isCompleted) {
        completer.complete(success);
      }
    }

    try {
      probeChannel = VoicingWebSocketConnector.connect(
        Uri.parse('ws://$ip:$port'),
        connectTimeout: _qrProbeTimeout,
        preferNativeWifi: preferNativeWifi,
      );
      timeoutTimer = Timer(_qrProbeTimeout, () => finish(false));
      subscription = probeChannel.stream.listen(
        (message) {
          try {
            final data = VoicingProtocol.decodeMessage(message);
            final type = data?['type'];
            if (type == VoicingProtocol.typeConnected) {
              final sendFuture = probeChannel?.sink.add(
                json.encode(VoicingProtocol.buildQrScanProbeMessage()),
              );
              if (sendFuture != null) {
                unawaited(
                  sendFuture.catchError((Object error, StackTrace stackTrace) {
                    AppLogger.warning(
                      'QR 连通性测试探测消息发送失败',
                      error: error,
                      stackTrace: stackTrace,
                    );
                    finish(false);
                  }),
                );
              }
            } else if (type == VoicingProtocol.typePong) {
              finish(true);
            }
          } catch (error, stackTrace) {
            AppLogger.warning('QR 连通性测试消息解析失败',
                error: error, stackTrace: stackTrace);
            finish(false);
          }
        },
        onError: (error, stackTrace) {
          AppLogger.warning('QR 连通性测试失败', error: error, stackTrace: stackTrace);
          finish(false);
        },
        onDone: () => finish(false),
      );

      final success = await completer.future;
      return success;
    } catch (error, stackTrace) {
      AppLogger.warning('QR 连通性测试连接失败', error: error, stackTrace: stackTrace);
      return false;
    } finally {
      timeoutTimer?.cancel();
      if (subscription != null) {
        unawaited(subscription.cancel());
      }
      if (probeChannel != null) {
        unawaited(probeChannel.sink.close());
      }
    }
  }

  Future<void> _finishQrPairing({
    required DateTime startedAt,
    required bool success,
    required int generation,
    SavedServer? scannedServer,
  }) async {
    if (generation != _qrPairingGeneration || !_qrScanMode) {
      return;
    }

    final revealRemaining =
        _qrResultRevealDelay - DateTime.now().difference(startedAt);
    if (!revealRemaining.isNegative) {
      await Future.delayed(revealRemaining);
    }

    if (generation != _qrPairingGeneration || !_qrScanMode) {
      return;
    }

    if (success && scannedServer != null) {
      final accepted = await _confirmScannedServer(scannedServer);
      if (generation != _qrPairingGeneration || !_qrScanMode) {
        return;
      }
      if (!accepted) {
        _qrScanMode = false;
        _lastQrCorners = null;
        _qrPairingSucceeded = false;
        _qrPairingFailed = false;
        notifyListeners();
        AppLogger.info('用户取消替换已保存设备');
        return;
      }

      _qrPairingSucceeded = true;
      _qrPairingFailed = false;
      notifyListeners();
      await Future.delayed(_qrSuccessHoldDelay);

      if (generation != _qrPairingGeneration || !_qrScanMode) {
        return;
      }

      _qrScanMode = false;
      _lastQrCorners = null;
      _qrPairingSucceeded = false;
      _qrPairingFailed = false;
      final serverToSave = _savedServer == null
          ? scannedServer
          : scannedServer.mergeCandidateIpsFrom(_savedServer!);
      await _saveManualServer(
        serverToSave.copyWith(
          lastConnectedTs: DateTime.now().millisecondsSinceEpoch,
        ),
        notify: false,
      );
      notifyListeners();
      _forceReconnect(resetBackoff: true, reason: 'qr scan success');
      return;
    }

    AppLogger.warning('QR 连通性测试未通过');
    _qrPairingSucceeded = false;
    _qrPairingFailed = true;
    notifyListeners();
    await Future.delayed(_qrFailureHoldDelay);
    if (generation != _qrPairingGeneration || !_qrScanMode) {
      return;
    }
    _qrScanMode = false;
    _lastQrCorners = null;
    _qrPairingSucceeded = false;
    _qrPairingFailed = false;
    notifyListeners();
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
      if (ip.isNotEmpty && !candidates.contains(ip)) {
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

  Future<bool> _confirmScannedServer(SavedServer incoming) async {
    final current = _savedServer;
    if (current == null ||
        !current.hasDeviceId ||
        !incoming.hasDeviceId ||
        current.deviceId == incoming.deviceId) {
      return true;
    }

    final confirm = _confirmDeviceReplacement;
    if (confirm == null) {
      return true;
    }

    try {
      return await confirm(current, incoming);
    } catch (error, stackTrace) {
      AppLogger.warning('设备替换确认失败', error: error, stackTrace: stackTrace);
      return false;
    }
  }

  Future<void> _loadSavedServerPreference() async {
    try {
      final server = await _savedServerStore.load();
      if (server == null) {
        return;
      }
      _savedServer = server;
      _manualMode = true;
      _serverIp = server.ip;
      _serverPort = server.port;
      AppLogger.info(
        '加载保存服务器: ${server.ip}:${server.port}; candidates=${server.candidateIps.join(', ')}',
      );
    } catch (error, stackTrace) {
      AppLogger.warning('加载保存服务器失败', error: error, stackTrace: stackTrace);
    }
  }

  Future<void> _saveManualServer(
    SavedServer server, {
    bool notify = true,
  }) async {
    _savedServer = server;
    _manualMode = true;
    _serverIp = server.ip;
    _serverPort = server.port;
    await _persistSavedServer(server);
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _persistSavedServer(SavedServer server) async {
    try {
      await _savedServerStore.save(server);
      AppLogger.info('保存服务器: ${server.ip}:${server.port}');
    } catch (error, stackTrace) {
      AppLogger.warning('保存服务器失败', error: error, stackTrace: stackTrace);
    }
  }

  void _maybeUpdateSavedServerFromConnectedMessage(
    Map<String, dynamic> data,
  ) {
    final current = _savedServer;
    if (current == null) {
      return;
    }

    final connectedDeviceId = SavedServer.readString(data['device_id']);
    if (current.hasDeviceId &&
        connectedDeviceId.isNotEmpty &&
        current.deviceId != connectedDeviceId) {
      AppLogger.warning(
        '已保存设备与连接设备不一致: saved=${current.deviceId}, connected=$connectedDeviceId',
      );
      return;
    }

    final connectedName = SavedServer.readString(data['name']).isNotEmpty
        ? SavedServer.readString(data['name'])
        : SavedServer.readString(data['computer_name']);
    final updated = current.copyWith(
      deviceId: current.hasDeviceId ? current.deviceId : connectedDeviceId,
      ip: _serverIp,
      ips: current.candidateIps,
      port: _serverPort,
      name: connectedName.isNotEmpty ? connectedName : current.name,
      os: SavedServer.readString(data['os']).isNotEmpty
          ? SavedServer.readString(data['os'])
          : current.os,
      lastConnectedTs: DateTime.now().millisecondsSinceEpoch,
    );

    if (updated == current) {
      return;
    }

    _savedServer = updated;
    unawaited(_persistSavedServer(updated));
  }

  void resetStubForDemo() {
    _qrPairingGeneration++;
    _savedServer = null;
    _manualMode = false;
    _qrScanMode = false;
    _lastQrCorners = null;
    _qrPairingSucceeded = false;
    _qrPairingFailed = false;
    notifyListeners();
  }

  Future<void> initialize() async {
    await _loadAutoEnterPreference();
    await _loadSavedServerPreference();
    _connectToSavedServerOrStayDisconnected(reason: 'init');
  }

  Future<void> handleLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused) {
      _stopHeartbeat();
    } else if (state == AppLifecycleState.resumed &&
        _recoveryPolicy.shouldForceReconnectOnResume()) {
      _beginForegroundRecovery();
      _connectToSavedServerOrStayDisconnected(reason: 'app resumed');
    }
  }

  void refreshConnection() {
    if (_status == ConnectionStatus.connected) {
      _forceReconnect(resetBackoff: true, reason: 'manual refresh connected');
      return;
    }
    _connectToSavedServerOrStayDisconnected(reason: 'manual refresh');
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

    final server = SavedServer(
      deviceId: deviceId.trim(),
      ip: normalizedIp,
      ips: [normalizedIp],
      port: port,
      name: name.trim(),
      os: os.trim(),
      lastConnectedTs: DateTime.now().millisecondsSinceEpoch,
    );
    await _saveManualServer(server);
    if (reconnect) {
      _forceReconnect(resetBackoff: true, reason: 'manual server update');
    }
  }

  Future<void> clearManualServer() async {
    _savedServer = null;
    _manualMode = false;
    _clearSavedCandidateAttempts();
    await _savedServerStore.clear();
    _disconnectAndStayDisconnected();
    notifyListeners();
  }

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
    final text = textController.text.trim();
    if (text.isEmpty ||
        _status != ConnectionStatus.connected ||
        !_syncEnabled) {
      return;
    }

    if (_hasPendingShadowBuffer(text)) {
      await _finalizeShadowInput(forceEnter: _autoEnterEnabled);
      return;
    }

    _shadowFinalizeTimer?.cancel();
    try {
      await _channel?.sink.add(
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
      _handleDisconnect();
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _foregroundRecoveryTimer?.cancel();
    _shadowFinalizeTimer?.cancel();
    textController.removeListener(_onTextControllerChanged);
    _connectionGeneration++;
    _channel?.sink.close();
    textController.dispose();
    super.dispose();
  }

  void _forceReconnect({
    bool resetBackoff = false,
    String reason = '',
    Duration? connectTimeout,
  }) {
    if (resetBackoff) {
      _reconnectAttempt = 0;
    }

    if (reason.isNotEmpty) {
      AppLogger.info('开始重连: $reason');
    }

    _connect(connectTimeout: connectTimeout);
  }

  void _connectToSavedServerOrStayDisconnected({required String reason}) {
    _clearSavedCandidateAttempts();
    _reconnectTimer?.cancel();
    _connectionGeneration++;
    _stopHeartbeat();
    _channel?.sink.close();
    _lastPong = null;

    final saved = _savedServer;
    if (_manualMode && saved != null) {
      _setStatus(ConnectionStatus.connecting);
      _startSavedCandidateAttempts(
        saved,
        saved.candidateIps,
        reason: 'saved QR device reconnect: $reason',
      );
      return;
    }

    AppLogger.info('未保存二维码设备，不进行 UDP 自动发现: $reason');
    _setStatus(ConnectionStatus.disconnected);
  }

  void _disconnectAndStayDisconnected() {
    _clearSavedCandidateAttempts();
    _reconnectTimer?.cancel();
    _connectionGeneration++;
    _stopHeartbeat();
    _channel?.sink.close();
    _lastPong = null;
    _syncEnabled = true;
    _setStatus(ConnectionStatus.disconnected);
  }

  int _connect({
    bool preferNativeWifi = true,
    Duration? connectTimeout,
  }) {
    final int connectionId = ++_connectionGeneration;
    final bool foregroundRecoveryActive = _isForegroundRecoveryActive();
    _setStatus(ConnectionStatus.connecting);

    _reconnectTimer?.cancel();
    _stopHeartbeat();
    _channel?.sink.close();
    _lastPong = null;

    try {
      _channel = VoicingWebSocketConnector.connect(
        Uri.parse('ws://$_serverIp:$_serverPort'),
        connectTimeout: connectTimeout ??
            _recoveryPolicy.resolveConnectTimeout(
              foregroundRecoveryActive: foregroundRecoveryActive,
            ),
        preferNativeWifi: preferNativeWifi,
      );

      _channel!.stream.listen(
        (message) => _handleMessage(message, connectionId),
        onError: (error, stackTrace) {
          if (connectionId != _connectionGeneration) {
            return;
          }
          AppLogger.warning(
            'WebSocket error',
            error: error,
            stackTrace: stackTrace,
          );
          _handleDisconnect(connectionId: connectionId);
        },
        onDone: () {
          if (connectionId != _connectionGeneration) {
            return;
          }
          _handleDisconnect(connectionId: connectionId);
        },
      );
    } catch (error, stackTrace) {
      if (connectionId != _connectionGeneration) {
        return connectionId;
      }
      AppLogger.error('Connection error', error: error, stackTrace: stackTrace);
      _handleDisconnect(connectionId: connectionId);
    }
    return connectionId;
  }

  void _handleMessage(dynamic message, int connectionId) {
    if (connectionId != _connectionGeneration) {
      return;
    }

    try {
      final data = VoicingProtocol.decodeMessage(message);
      if (data == null) {
        return;
      }

      final type = data['type'];
      if (type == VoicingProtocol.typeConnected) {
        _clearSavedCandidateAttempts();
        _endForegroundRecovery();
        _status = ConnectionStatus.connected;
        _syncEnabled = data['sync_enabled'] ?? true;
        _reconnectAttempt = 0;
        _lastPong = DateTime.now();
        _maybeUpdateSavedServerFromConnectedMessage(data);
        _startHeartbeat();
        notifyListeners();
      } else if (type == VoicingProtocol.typeAck) {
        final shouldClearInput = data['clear_input'];
        if (shouldClearInput is bool ? shouldClearInput : true) {
          textController.clear();
        }
      } else if (type == VoicingProtocol.typeSyncDisabled) {
        _lastPong = DateTime.now();
        _syncEnabled = data['sync_enabled'] ?? false;
        notifyListeners();
      } else if (type == VoicingProtocol.typeSyncState ||
          type == VoicingProtocol.typePong) {
        _lastPong = DateTime.now();
        _syncEnabled = data['sync_enabled'] ?? true;
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

  void _handleDisconnect({int? connectionId}) {
    if (connectionId != null && connectionId != _connectionGeneration) {
      return;
    }

    final now = DateTime.now();
    final bool foregroundRecoveryActive = _isForegroundRecoveryActive(now: now);
    _stopHeartbeat();
    if (_tryNextSavedCandidateAfterDisconnect(connectionId)) {
      return;
    }
    _status = foregroundRecoveryActive
        ? ConnectionStatus.connecting
        : ConnectionStatus.disconnected;
    _syncEnabled = true;
    notifyListeners();

    final saved = _savedServer;
    if (!_manualMode || saved == null) {
      _clearSavedCandidateAttempts();
      _reconnectTimer?.cancel();
      AppLogger.info('无已保存二维码设备，断开后不自动重连');
      return;
    }

    final reconnectDelay = _recoveryPolicy.reconnectDelay(
      reconnectAttempt: _reconnectAttempt,
      foregroundRecoveryActive: foregroundRecoveryActive,
    );
    _reconnectAttempt = foregroundRecoveryActive ? 0 : _reconnectAttempt + 1;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      reconnectDelay,
      () {
        if (_status == ConnectionStatus.disconnected ||
            _status == ConnectionStatus.connecting) {
          final latestSaved = _savedServer;
          if (_manualMode && latestSaved != null) {
            _startSavedCandidateAttempts(
              latestSaved,
              latestSaved.candidateIps,
              reason: 'saved QR device reconnect after disconnect',
            );
          } else {
            _setStatus(ConnectionStatus.disconnected);
          }
        }
      },
    );
  }

  void _startSavedCandidateAttempts(
    SavedServer saved,
    List<String> candidates, {
    required String reason,
  }) {
    final attempts = SavedServer.normalizeIpCandidates(saved.ip, candidates);
    if (attempts.isEmpty) {
      return;
    }

    _savedCandidateAttempts = attempts;
    _savedCandidateAttemptIndex = 0;
    AppLogger.info('开始保存地址候选连接: ${attempts.join(', ')} ($reason)');
    _connectCurrentSavedCandidateAttempt(reason: reason);
  }

  void _connectCurrentSavedCandidateAttempt({required String reason}) {
    final saved = _savedServer;
    if (saved == null ||
        _savedCandidateAttemptIndex < 0 ||
        _savedCandidateAttemptIndex >= _savedCandidateAttempts.length) {
      _clearSavedCandidateAttempts();
      return;
    }

    final candidateIp = _savedCandidateAttempts[_savedCandidateAttemptIndex];
    _serverIp = candidateIp;
    _serverPort = saved.port;
    final attemptNumber = _savedCandidateAttemptIndex + 1;
    final totalAttempts = _savedCandidateAttempts.length;
    AppLogger.info(
      '尝试保存地址候选 $attemptNumber/$totalAttempts: $candidateIp:${saved.port} ($reason)',
    );
    _savedCandidateConnectionId = _connect(
      connectTimeout: _savedCandidateConnectTimeout,
    );
  }

  bool _tryNextSavedCandidateAfterDisconnect(int? connectionId) {
    final saved = _savedServer;
    if (!_manualMode || saved == null) {
      _clearSavedCandidateAttempts();
      return false;
    }

    if (_savedCandidateConnectionId == connectionId &&
        _savedCandidateAttempts.isNotEmpty) {
      final nextIndex = _savedCandidateAttemptIndex + 1;
      if (nextIndex >= _savedCandidateAttempts.length) {
        AppLogger.warning('保存地址候选全部失败: ${_savedCandidateAttempts.join(', ')}');
        _clearSavedCandidateAttempts();
        return false;
      }
      _savedCandidateAttemptIndex = nextIndex;
      _connectCurrentSavedCandidateAttempt(reason: 'previous candidate failed');
      return true;
    }

    final remaining = _remainingSavedCandidatesAfter(_serverIp, saved);
    if (remaining.isEmpty) {
      _clearSavedCandidateAttempts();
      return false;
    }

    _startSavedCandidateAttempts(
      saved,
      remaining,
      reason: 'current saved address failed',
    );
    return true;
  }

  List<String> _remainingSavedCandidatesAfter(
      String failedIp, SavedServer saved) {
    final candidates = saved.candidateIps;
    if (candidates.length <= 1) {
      return const [];
    }

    final failedIndex = candidates.indexOf(failedIp);
    if (failedIndex < 0) {
      return candidates;
    }

    final reordered = <String>[
      ...candidates.skip(failedIndex + 1),
      ...candidates.take(failedIndex),
    ];
    return reordered.where((ip) => ip != failedIp).toList();
  }

  void _clearSavedCandidateAttempts() {
    _savedCandidateAttempts = const [];
    _savedCandidateAttemptIndex = 0;
    _savedCandidateConnectionId = null;
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: VoicingProtocol.heartbeatIntervalSec),
      (_) => _checkHeartbeat(),
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _checkHeartbeat() {
    if (_status != ConnectionStatus.connected) {
      _stopHeartbeat();
      return;
    }

    final now = DateTime.now();
    if (_recoveryPolicy.isHeartbeatExpired(
      status: _status,
      lastPong: _lastPong,
      now: now,
    )) {
      final elapsed =
          _lastPong == null ? 0 : now.difference(_lastPong!).inSeconds;
      AppLogger.warning('心跳超时 (${elapsed}s)，判定连接死亡');
      _handleDisconnect();
      return;
    }

    _sendPing();
  }

  void _sendPing() {
    unawaited(_sendPingAsync());
  }

  Future<void> _sendPingAsync() async {
    try {
      await _channel?.sink.add(json.encode(VoicingProtocol.buildPingMessage()));
    } catch (error, stackTrace) {
      AppLogger.warning('Ping 发送失败', error: error, stackTrace: stackTrace);
      _handleDisconnect();
    }
  }

  void _beginForegroundRecovery() {
    final now = DateTime.now();
    _foregroundRecoveryUntil = _recoveryPolicy.startForegroundRecovery(now);
    _displayConnectedDuringForegroundRecovery =
        _status == ConnectionStatus.connected;
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

  void _onTextControllerChanged() {
    final currentText = textController.text;

    if (currentText.length < _lastSentLength) {
      _lastSentLength = currentText.length;
    }

    if (!_shadowModeEnabled ||
        _status != ConnectionStatus.connected ||
        !_syncEnabled) {
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

    final increment = currentText.substring(_lastSentLength);
    try {
      await _channel?.sink.add(
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

    final currentText = textController.text.trim();
    if (!_hasPendingShadowBuffer(currentText)) {
      return;
    }

    if (forceEnter && _status == ConnectionStatus.connected && _syncEnabled) {
      try {
        await _channel?.sink.add(
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
        _handleDisconnect();
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

  void _setStatus(ConnectionStatus status) {
    _status = status;
    notifyListeners();
  }
}
