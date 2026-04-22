import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'app_logger.dart';
import 'connection_recovery_policy.dart';
import 'voicing_protocol.dart';

class VoicingConnectionController extends ChangeNotifier {
  static const Duration _shadowFinalizeDelay = Duration(milliseconds: 700);

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
  }) : _recoveryPolicy = recoveryPolicy {
    textController.addListener(_onTextControllerChanged);
  }

  final TextEditingController textController = TextEditingController();
  final ConnectionRecoveryPolicy _recoveryPolicy;

  static const String _prefKeyManualIp = 'manual_server_ip';
  static const String _prefKeyManualPort = 'manual_server_port';

  WebSocketChannel? _channel;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  bool _syncEnabled = true;
  bool _autoEnterEnabled = false;
  Timer? _reconnectTimer;
  String _serverIp = VoicingProtocol.defaultServerIp;
  int _serverPort = VoicingProtocol.websocketPort;
  bool _manualMode = false;
  String _lastSentText = '';
  final bool _shadowModeEnabled = true;
  int _lastSentLength = 0;
  bool _wasComposing = false;
  RawDatagramSocket? _udpSocket;
  StreamSubscription<RawSocketEvent>? _udpSubscription;
  Timer? _heartbeatTimer;
  DateTime? _lastPong;
  int _reconnectAttempt = 0;
  int _connectionGeneration = 0;
  DateTime? _lastConnectStartedAt;
  DateTime? _foregroundRecoveryUntil;
  Timer? _foregroundRecoveryTimer;
  Timer? _shadowFinalizeTimer;
  bool _displayConnectedDuringForegroundRecovery = false;

  ConnectionStatus get status => _status;
  ConnectionStatus get displayStatus => _displayConnectedDuringForegroundRecovery
      ? ConnectionStatus.connected
      : _status;
  bool get syncEnabled => _syncEnabled;
  bool get autoEnterEnabled => _autoEnterEnabled;
  String get serverIp => _serverIp;
  int get serverPort => _serverPort;
  bool get manualMode => _manualMode;
  String get lastSentText => _lastSentText;

  Future<void> initialize() async {
    await _loadAutoEnterPreference();
    await _loadManualServerPreference();
    if (_manualMode) {
      AppLogger.info('手动服务器模式已启用: $_serverIp:$_serverPort');
    } else {
      await _restartUdpDiscovery(reason: 'init');
    }
    _forceReconnect(resetBackoff: true, reason: 'init');
  }

  Future<void> handleLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused) {
      _stopHeartbeat();
    } else if (state == AppLifecycleState.resumed &&
        _recoveryPolicy.shouldForceReconnectOnResume()) {
      _beginForegroundRecovery();
      if (!_manualMode) {
        await _restartUdpDiscovery(reason: 'app resumed');
      }
      _forceReconnect(resetBackoff: true, reason: 'app resumed');
    }
  }

  void refreshConnection() {
    _forceReconnect(resetBackoff: true, reason: 'manual refresh');
  }

  void recallLastText() {
    if (_lastSentText.isEmpty) {
      return;
    }

    textController.text = _lastSentText;
    textController.selection = TextSelection.fromPosition(
      TextPosition(offset: _lastSentText.length),
    );
  }

  void sendText() {
    final text = textController.text.trim();
    if (text.isEmpty || _status != ConnectionStatus.connected || !_syncEnabled) {
      return;
    }

    if (_hasPendingShadowBuffer(text)) {
      _finalizeShadowInput(forceEnter: _autoEnterEnabled);
      return;
    }

    _shadowFinalizeTimer?.cancel();
    try {
      _channel?.sink.add(
        json.encode(
          VoicingProtocol.buildTextMessage(
            text,
            autoEnter: _autoEnterEnabled,
            sendMode: VoicingProtocol.textSendModeSubmit,
          ),
        ),
      );
      _lastSentText = text;
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
    _udpSubscription?.cancel();
    _udpSubscription = null;
    _udpSocket?.close();
    _udpSocket = null;
    super.dispose();
  }

  void _forceReconnect({
    bool resetBackoff = false,
    String reason = '',
  }) {
    if (resetBackoff) {
      _reconnectAttempt = 0;
    }

    if (reason.isNotEmpty) {
      AppLogger.info('开始重连: $reason');
    }

    _connect();
  }

  void _connect() {
    final int connectionId = ++_connectionGeneration;
    final bool foregroundRecoveryActive = _isForegroundRecoveryActive();
    _lastConnectStartedAt = DateTime.now();
    _setStatus(ConnectionStatus.connecting);

    _reconnectTimer?.cancel();
    _stopHeartbeat();
    _channel?.sink.close();
    _lastPong = null;

    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse('ws://$_serverIp:$_serverPort'),
        connectTimeout: _recoveryPolicy.resolveConnectTimeout(
          foregroundRecoveryActive: foregroundRecoveryActive,
        ),
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
        return;
      }
      AppLogger.error('Connection error', error: error, stackTrace: stackTrace);
      _handleDisconnect(connectionId: connectionId);
    }
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
        _endForegroundRecovery();
        _status = ConnectionStatus.connected;
        _syncEnabled = data['sync_enabled'] ?? true;
        _reconnectAttempt = 0;
        _lastPong = DateTime.now();
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
    _status = foregroundRecoveryActive
        ? ConnectionStatus.connecting
        : ConnectionStatus.disconnected;
    _syncEnabled = true;
    notifyListeners();

    final reconnectDelay = _recoveryPolicy.reconnectDelay(
      reconnectAttempt: _reconnectAttempt,
      foregroundRecoveryActive: foregroundRecoveryActive,
    );
    _reconnectAttempt = foregroundRecoveryActive ? 0 : _reconnectAttempt + 1;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      reconnectDelay,
      () {
        if (_status == ConnectionStatus.disconnected) {
          _connect();
        } else if (_status == ConnectionStatus.connecting) {
          _connect();
        }
      },
    );
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
      final elapsed = _lastPong == null ? 0 : now.difference(_lastPong!).inSeconds;
      AppLogger.warning('心跳超时 (${elapsed}s)，判定连接死亡');
      _handleDisconnect();
      return;
    }

    _sendPing();
  }

  void _sendPing() {
    try {
      _channel?.sink.add(json.encode(VoicingProtocol.buildPingMessage()));
    } catch (error, stackTrace) {
      AppLogger.warning('Ping 发送失败', error: error, stackTrace: stackTrace);
      _handleDisconnect();
    }
  }

  Future<void> _startUdpDiscovery() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        VoicingProtocol.udpBroadcastPort,
      );
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.multicastLoopback = true;
      AppLogger.info('UDP 发现监听已启动，端口: ${VoicingProtocol.udpBroadcastPort}');

      _udpSubscription = _udpSocket!.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read) {
          return;
        }

        final datagram = _udpSocket!.receive();
        if (datagram == null) {
          return;
        }

        final message = utf8.decode(datagram.data);
        _handleUdpDiscovery(message, datagram.address.address);
      });
    } catch (error, stackTrace) {
      AppLogger.warning(
        'UDP 发现启动失败',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _restartUdpDiscovery({String reason = ''}) async {
    await _stopUdpDiscovery();
    await _startUdpDiscovery();
    if (reason.isNotEmpty) {
      AppLogger.info('UDP 发现监听已重建: $reason');
    }
  }

  Future<void> _stopUdpDiscovery() async {
    await _udpSubscription?.cancel();
    _udpSubscription = null;
    _udpSocket?.close();
    _udpSocket = null;
  }

  void _handleUdpDiscovery(String message, String sourceIp) {
    if (_manualMode) {
      return;
    }
    try {
      final announcement = VoicingProtocol.parseUdpDiscoveryMessage(message);
      if (announcement == null) {
        return;
      }

      final now = DateTime.now();
      final bool foregroundRecoveryActive = _isForegroundRecoveryActive(now: now);
      final bool serverChanged = _serverIp != announcement.ip ||
          _serverPort != announcement.port;
      final bool shouldReconnectFromBroadcast = _recoveryPolicy.shouldReconnectFromUdp(
        serverChanged: serverChanged,
        foregroundRecoveryActive: foregroundRecoveryActive,
        status: _status,
        lastConnectStartedAt: _lastConnectStartedAt,
        now: now,
      );

      if (serverChanged) {
        AppLogger.info(
          'UDP 发现服务器: ${announcement.ip}:${announcement.port} (来源: $sourceIp)',
        );
        _serverIp = announcement.ip;
        _serverPort = announcement.port;
        notifyListeners();
      }

      if (shouldReconnectFromBroadcast) {
        _reconnectTimer?.cancel();
        _forceReconnect(
          resetBackoff: true,
          reason: serverChanged ? 'udp server update' : 'udp recovery probe',
        );
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'UDP 消息解析失败',
        error: error,
        stackTrace: stackTrace,
      );
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
      _sendShadowIncrement(currentText);
    }

    _wasComposing = isComposing;
  }

  void _sendShadowIncrement(String currentText) {
    if (currentText.length <= _lastSentLength) {
      return;
    }

    final increment = currentText.substring(_lastSentLength);
    try {
      _channel?.sink.add(
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
      () => _finalizeShadowInput(forceEnter: _autoEnterEnabled),
    );
  }

  void _finalizeShadowInput({required bool forceEnter}) {
    _shadowFinalizeTimer?.cancel();
    _shadowFinalizeTimer = null;

    final currentText = textController.text.trim();
    if (!_hasPendingShadowBuffer(currentText)) {
      return;
    }

    if (forceEnter &&
        _status == ConnectionStatus.connected &&
        _syncEnabled) {
      try {
        _channel?.sink.add(
          json.encode(
            VoicingProtocol.buildTextMessage(
              '',
              autoEnter: true,
              sendMode: VoicingProtocol.textSendModeCommit,
            ),
          ),
        );
      } catch (error, stackTrace) {
        AppLogger.warning('自动 Enter 提交失败', error: error, stackTrace: stackTrace);
      }
    }

    _lastSentLength = 0;
    _wasComposing = false;
    textController.clear();
  }

  Future<void> _loadAutoEnterPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoEnterEnabled = prefs.getBool('auto_enter_enabled') ?? false;
      AppLogger.info('加载自动 Enter 设置: $_autoEnterEnabled');
    } catch (error, stackTrace) {
      AppLogger.warning('加载自动 Enter 设置失败', error: error, stackTrace: stackTrace);
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
      AppLogger.warning('保存自动 Enter 设置失败', error: error, stackTrace: stackTrace);
    }
  }

  Future<void> _loadManualServerPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ip = prefs.getString(_prefKeyManualIp);
      final port = prefs.getInt(_prefKeyManualPort);
      if (ip != null && ip.isNotEmpty) {
        _manualMode = true;
        _serverIp = ip;
        _serverPort = port ?? VoicingProtocol.websocketPort;
      }
    } catch (error, stackTrace) {
      AppLogger.warning('加载手动服务器设置失败', error: error, stackTrace: stackTrace);
    }
  }

  Future<void> setManualServer(String ip, {int? port}) async {
    final trimmed = ip.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final resolvedPort = port ?? VoicingProtocol.websocketPort;
    _manualMode = true;
    _serverIp = trimmed;
    _serverPort = resolvedPort;
    await _stopUdpDiscovery();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyManualIp, trimmed);
      await prefs.setInt(_prefKeyManualPort, resolvedPort);
    } catch (error, stackTrace) {
      AppLogger.warning('保存手动服务器设置失败', error: error, stackTrace: stackTrace);
    }
    AppLogger.info('切换到手动服务器: $trimmed:$resolvedPort');
    notifyListeners();
    _forceReconnect(resetBackoff: true, reason: 'manual server set');
  }

  Future<void> clearManualServer() async {
    if (!_manualMode) {
      return;
    }
    _manualMode = false;
    _serverIp = VoicingProtocol.defaultServerIp;
    _serverPort = VoicingProtocol.websocketPort;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyManualIp);
      await prefs.remove(_prefKeyManualPort);
    } catch (error, stackTrace) {
      AppLogger.warning('清除手动服务器设置失败', error: error, stackTrace: stackTrace);
    }
    AppLogger.info('清除手动服务器，切回 UDP 自动发现');
    notifyListeners();
    await _restartUdpDiscovery(reason: 'manual server cleared');
    _forceReconnect(resetBackoff: true, reason: 'manual server cleared');
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    notifyListeners();
  }
}
