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

typedef DeviceReplacementPrompt = Future<bool> Function(
  SavedServer current,
  SavedServer incoming,
);

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
    DeviceReplacementPrompt? confirmDeviceReplacement,
    ConnectionTuning tuning = const ConnectionTuning(),
    NetworkSnapshotProvider? networkSnapshotProvider,
    VoicingChannelFactory channelFactory = VoicingWebSocketConnector.connect,
  })  : _recoveryPolicy = recoveryPolicy,
        _savedServerStore = savedServerStore,
        _confirmDeviceReplacement = confirmDeviceReplacement,
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
  final DeviceReplacementPrompt? _confirmDeviceReplacement;
  final ConnectionTuning _tuning;
  final NetworkSnapshotProvider _networkProvider;
  final VoicingChannelFactory _channelFactory;
  final ConnectionRace _connectionRace;

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
  DateTime? _connectStartedAt;
  DateTime? _connectedSince;

  // 网络画像（2026-11-20 新增）：初始化时拉取一次，之后订阅原生变化。
  NetworkSnapshot _networkSnapshot = NetworkSnapshot.empty;
  StreamSubscription<NetworkSnapshot>? _networkSubscription;

  // 并行竞速句柄：同一时刻最多一个 saved race + 一个 QR race，
  // generation 变化 / dispose 时必须成对 cancel，避免旧回调污染新连接。
  RaceHandle? _savedRace;
  RaceHandle? _qrRace;

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
  bool get hasStoredServer => _savedServer != null;
  SavedServer? get savedServer => _savedServer;
  List<Offset>? get lastQrCorners => _lastQrCorners;
  bool get qrPairingSucceeded => _qrPairingSucceeded;
  bool get qrPairingFailed => _qrPairingFailed;

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
  /// 2026-11-20 重构：原实现按候选串行 probe（每个 3s），跨网络时最坏 N*3s；
  /// 现在全部候选按 stagger 并行探测，首个完成「connected + ping(source=qr_scan)
  /// + pong」的候选即 winner，整体预算 [_tuning.raceBudget]。760ms reveal、
  /// 成功/失败 hold、设备替换确认、generation 隔离语义保持不变。
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

  /// 已保存设备重连：地址簿评分排序 → 前 N 个候选并行竞速 → 正式建链。
  ///
  /// 2026-11-20 重构：替换旧的串行 `_savedCandidateAttempts` 机制。旧实现
  /// 每个候选 2s 串行尝试，N 个候选最坏 N*2s；现在 winner 通常是评分最高的
  /// 同 networkKey / 同子网地址，首包 RTT 内就能确定，1~2 秒目标可达。
  void _beginSavedServerRace(SavedServer saved, {required String reason}) {
    _reconnectTimer?.cancel();
    _cancelSavedRace();
    final generation = ++_connectionGeneration;
    _stopHeartbeat();
    _channel?.sink.close();
    _channel = null;
    _lastPong = null;
    _connectStartedAt = null;
    _setStatus(ConnectionStatus.connecting);

    final ranked = _rankedSavedCandidateIps(saved);
    if (ranked.isEmpty) {
      AppLogger.warning('已保存设备没有可用候选地址，保持断开');
      _setStatus(ConnectionStatus.disconnected);
      return;
    }
    _logCandidateRanking(saved, ranked, reason: reason);
    final candidates = ranked
        .take(_tuning.savedRaceCandidateCount)
        .toList(growable: false);
    final timeout = _attemptTimeout();
    AppLogger.info(
      '已保存设备并行竞速开始: candidates=${candidates.join(", ")} '
      'networkKey=${_networkKeyForLog()} '
      'attemptTimeout=${timeout.inMilliseconds}ms '
      'budget=${_tuning.raceBudget.inMilliseconds}ms reason=$reason',
    );

    final handle = _connectionRace.start(
      candidates: candidates,
      attempt: (candidate, cancellation) => _probeSavedCandidate(
        ip: candidate.ip,
        port: saved.port,
        timeout: timeout,
        cancellation: cancellation,
      ),
      isCancelled: () => generation != _connectionGeneration,
      attemptTimeout: timeout,
      budget: _tuning.raceBudget,
      onAttemptStarted: (candidate, launchDelay) => AppLogger.info(
        '已保存候选探测启动: ip=${candidate.ip} '
        'stagger=${launchDelay.inMilliseconds}ms '
        'networkKey=${_networkKeyForLog()}',
      ),
      onAttemptFailed: (failure) => AppLogger.warning(
        '已保存候选探测失败: ip=${failure.candidate.ip} '
        'reason=${failure.reason.name} '
        'elapsed=${failure.elapsed.inMilliseconds}ms '
        'networkKey=${_networkKeyForLog()}',
      ),
      onWinner: (outcome) => AppLogger.info(
        '已保存候选探测 winner: ip=${outcome.candidate.ip} '
        'elapsed=${outcome.elapsed.inMilliseconds}ms '
        'attempt=${outcome.attemptElapsed.inMilliseconds}ms '
        'networkKey=${_networkKeyForLog()}',
      ),
    );
    _savedRace = handle;
    unawaited(
      handle.done.then(
        (result) => _handleSavedRaceCompleted(
          saved: saved,
          generation: generation,
          result: result,
        ),
      ),
    );
  }

  Future<void> _handleSavedRaceCompleted({
    required SavedServer saved,
    required int generation,
    required ConnectionRaceResult result,
  }) async {
    if (generation != _connectionGeneration) {
      return;
    }
    // 本轮竞速已结束；generation 校验保证不会误清新一轮竞速的句柄。
    _savedRace = null;
    if (result.cancelled) {
      AppLogger.info('已保存设备竞速被取消（generation 变化/网络切换）');
      return;
    }

    final winner = result.winner;
    if (winner == null) {
      AppLogger.warning(
        '已保存设备竞速全部失败: failures=${_describeRaceFailures(result.failures)} '
        'budgetExhausted=${result.budgetExhausted} '
        'networkKey=${_networkKeyForLog()}',
      );
      await _recordRaceFailures(result.failures);
      if (generation != _connectionGeneration) {
        return;
      }
      _enterReconnectBackoff(reason: 'saved race failed');
      return;
    }

    // 失败候选只累加失败计数，绝不写入成功历史；成功历史等正式 connected 后再写。
    await _recordRaceFailures(result.failures);
    if (generation != _connectionGeneration) {
      return;
    }
    final latest = _savedServer ?? saved;
    _serverIp = winner.candidate.ip;
    _serverPort = latest.port;
    AppLogger.info(
      '已保存设备竞速胜出，开始正式建链: ip=$_serverIp:$_serverPort '
      'raceElapsed=${result.elapsed.inMilliseconds}ms '
      'networkKey=${_networkKeyForLog()}',
    );
    _connect(
      connectTimeout: _attemptTimeout(),
      reason: 'saved race winner',
    );
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
  List<String> _rankedSavedCandidateIps(SavedServer saved) {
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

  void _logCandidateRanking(
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
      '候选评分排序 networkKey=${_networkKeyForLog()}: '
      '${parts.join(" > ")}; reason=$reason',
    );
  }

  /// 把竞速中真实探测失败的候选计入地址簿失败计数（不写成功历史）。
  Future<void> _recordRaceFailures(Iterable<RaceFailure> failures) async {
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
    final current = _savedServer;
    if (current == null) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var book = current.addressBook;
    for (final failure in attempted) {
      book = book.recordFailure(ip: failure.candidate.ip, nowMs: nowMs);
    }
    book = book.trimmed(
      nowMs: nowMs,
      maxAddresses: _tuning.addressBookMaxAddresses,
    );
    final updated = current.copyWith(
      ips: SavedServer.normalizeIpCandidates(
        current.ip,
        <dynamic>[...current.candidateIps, ...book.ips],
      ),
      addresses: book,
    );
    if (updated == current) {
      return;
    }
    _savedServer = updated;
    AppLogger.info(
      '记录候选失败计数: ${attempted.map((failure) => failure.candidate.ip).join(", ")} '
      'networkKey=${_networkKeyForLog()}',
    );
    await _persistSavedServer(updated);
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
        _tuning.qrResultRevealDelay - DateTime.now().difference(startedAt);
    if (!revealRemaining.isNegative) {
      await Future<void>.delayed(revealRemaining);
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
      await Future<void>.delayed(_tuning.qrSuccessHoldDelay);

      if (generation != _qrPairingGeneration || !_qrScanMode) {
        return;
      }

      _qrScanMode = false;
      _lastQrCorners = null;
      _qrPairingSucceeded = false;
      _qrPairingFailed = false;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      // 探针完成 connected + ping(qr_scan) + pong 才算真正连上，此时才写成功历史。
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
      final previous = _savedServer;
      if (previous != null) {
        // 同一台 PC 的历史地址簿整体合并：不同网络的地址都保留（核心不变量）。
        serverToSave = serverToSave.mergeAddressHistoryFrom(previous);
      }
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
      AppLogger.info(
        'QR 配对成功保存: ip=${serverToSave.ip} '
        'networkKey=${_networkKeyForLog()} '
        'addresses=${book.ips.join(", ")} '
        'networkKeys=${book.successfulNetworkKeys.join("|")}',
      );
      await _saveManualServer(serverToSave, notify: false);
      notifyListeners();
      _forceReconnect(resetBackoff: true, reason: 'qr scan success');
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
  /// 规则：已连接时不打断当前连接（只更新快照供以后排序）；连接中/断开时
  /// 立即用新快照重排候选并重新竞速，不等 backoff。
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
    if (_status == ConnectionStatus.connected) {
      AppLogger.info('当前已连接，忽略网络变化，不打断现有连接');
      return;
    }
    if (_qrScanMode) {
      AppLogger.info('正在扫码配对，暂不触发自适应重连');
      return;
    }
    final saved = _savedServer;
    if (!_manualMode || saved == null) {
      return;
    }
    AppLogger.info('网络变化触发立即重排候选并重连（跳过 backoff）');
    _beginSavedServerRace(saved, reason: 'network changed');
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
        '加载保存服务器: ${server.ip}:${server.port}; '
        'candidates=${server.candidateIps.join(', ')}; '
        'addresses=${server.addressBook.ips.join(', ')}; '
        'networkKeys=${server.addressBook.successfulNetworkKeys.join("|")}',
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
      AppLogger.info(
        '保存服务器: ${server.ip}:${server.port} '
        'schema=${server.schemaVersion} addresses=${server.addressBook.ips.length}',
      );
    } catch (error, stackTrace) {
      AppLogger.warning('保存服务器失败', error: error, stackTrace: stackTrace);
    }
  }

  /// 正式 connected 后才调用：写成功历史（网络 Key + 计数）并提升 primary。
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
    final connectedOs = SavedServer.readString(data['os']);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final networkContext = _currentNetworkContext();
    final book = current.addressBook
        .recordSuccess(
          ip: _serverIp,
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
      ip: _serverIp,
      ips: SavedServer.normalizeIpCandidates(
        _serverIp,
        <dynamic>[...current.candidateIps, ...book.ips],
      ),
      port: _serverPort,
      name: connectedName.isNotEmpty ? connectedName : current.name,
      os: connectedOs.isNotEmpty ? connectedOs : current.os,
      lastConnectedTs: nowMs,
      addresses: book,
    );

    if (updated == current) {
      return;
    }

    _savedServer = updated;
    AppLogger.info(
      '记录连接成功历史: ip=$_serverIp networkKey=${_networkKeyForLog()} '
      'ok=${updated.addressBook.addressFor(_serverIp)?.successCount ?? 0} '
      'networkKeys=${book.successfulNetworkKeys.join("|")}',
    );
    unawaited(_persistSavedServer(updated));
  }

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

  void resetStubForDemo() {
    _qrPairingGeneration++;
    _qrRace?.cancel();
    _qrRace = null;
    _savedRace?.cancel();
    _savedRace = null;
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
    _networkSnapshot = await _loadInitialNetworkSnapshot();
    _subscribeToNetworkChanges();
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

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final server = SavedServer(
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
    await _saveManualServer(server);
    if (reconnect) {
      _forceReconnect(resetBackoff: true, reason: 'manual server update');
    }
  }

  Future<void> clearManualServer() async {
    _savedServer = null;
    _manualMode = false;
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
    final savedRace = _savedRace;
    _savedRace = null;
    savedRace?.cancel();
    final qrRace = _qrRace;
    _qrRace = null;
    qrRace?.cancel();
    final subscription = _networkSubscription;
    _networkSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    unawaited(_networkProvider.dispose());
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

    _connect(connectTimeout: connectTimeout, reason: reason);
  }

  void _connectToSavedServerOrStayDisconnected({required String reason}) {
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    final saved = _savedServer;
    if (_manualMode && saved != null) {
      _beginSavedServerRace(saved, reason: reason);
      return;
    }

    _cancelSavedRace();
    _connectionGeneration++;
    _channel?.sink.close();
    _channel = null;
    _lastPong = null;
    _connectStartedAt = null;
    AppLogger.info('未保存二维码设备，不进行 UDP 自动发现: $reason');
    _setStatus(ConnectionStatus.disconnected);
  }

  void _disconnectAndStayDisconnected() {
    _reconnectTimer?.cancel();
    _cancelSavedRace();
    _connectionGeneration++;
    _stopHeartbeat();
    _channel?.sink.close();
    _channel = null;
    _lastPong = null;
    _connectStartedAt = null;
    _connectedSince = null;
    _syncEnabled = true;
    _setStatus(ConnectionStatus.disconnected);
  }

  void _cancelSavedRace() {
    final handle = _savedRace;
    _savedRace = null;
    handle?.cancel();
  }

  int _connect({
    bool preferNativeWifi = true,
    Duration? connectTimeout,
    String reason = '',
  }) {
    final int connectionId = ++_connectionGeneration;
    final bool foregroundRecoveryActive = _isForegroundRecoveryActive();
    _setStatus(ConnectionStatus.connecting);

    _reconnectTimer?.cancel();
    _stopHeartbeat();
    _channel?.sink.close();
    _channel = null;
    _lastPong = null;
    _connectStartedAt = DateTime.now();
    final timeout = connectTimeout ??
        _recoveryPolicy.resolveConnectTimeout(
          foregroundRecoveryActive: foregroundRecoveryActive,
        );
    AppLogger.info(
      '建立正式连接: id=$connectionId ip=$_serverIp:$_serverPort '
      'timeout=${timeout.inMilliseconds}ms '
      'networkKey=${_networkKeyForLog()} reason=${reason.isEmpty ? "connect" : reason}',
    );

    try {
      _channel = _channelFactory(
        Uri.parse('ws://$_serverIp:$_serverPort'),
        connectTimeout: timeout,
        preferNativeWifi: preferNativeWifi,
      );

      _channel!.stream.listen(
        (message) => _handleMessage(message, connectionId),
        onError: (error, stackTrace) {
          if (connectionId != _connectionGeneration) {
            return;
          }
          _logConnectFailure('WebSocket error', error: error, stackTrace: stackTrace);
          _handleDisconnect(connectionId: connectionId);
        },
        onDone: () {
          if (connectionId != _connectionGeneration) {
            return;
          }
          _logConnectFailure('WebSocket closed');
          _handleDisconnect(connectionId: connectionId);
        },
      );
    } catch (error, stackTrace) {
      if (connectionId != _connectionGeneration) {
        return connectionId;
      }
      _logConnectFailure('Connection error', error: error, stackTrace: stackTrace);
      _handleDisconnect(connectionId: connectionId);
    }
    return connectionId;
  }

  void _logConnectFailure(
    String reason, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final elapsed = _connectStartedAt == null
        ? null
        : DateTime.now().difference(_connectStartedAt!);
    AppLogger.warning(
      '连接失败: ip=$_serverIp:$_serverPort reason=$reason '
      'elapsed=${elapsed?.inMilliseconds ?? 0}ms '
      'networkKey=${_networkKeyForLog()}',
      error: error,
      stackTrace: stackTrace,
    );
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
        _connectedSince = DateTime.now();
        final connectElapsed = _connectStartedAt == null
            ? null
            : DateTime.now().difference(_connectStartedAt!);
        AppLogger.info(
          '连接成功: ip=$_serverIp:$_serverPort '
          'elapsed=${connectElapsed?.inMilliseconds ?? 0}ms '
          'networkKey=${_networkKeyForLog()}',
        );
        // 只有真正收到 connected 才写成功历史 + 提升 primary。
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
    _cancelSavedRace();
    if (_status == ConnectionStatus.connected) {
      final connectedFor =
          _connectedSince == null ? null : now.difference(_connectedSince!);
      AppLogger.warning(
        '连接断开: ip=$_serverIp:$_serverPort '
        'connectedFor=${connectedFor?.inMilliseconds ?? 0}ms '
        'networkKey=${_networkKeyForLog()}',
      );
    }
    _status = foregroundRecoveryActive
        ? ConnectionStatus.connecting
        : ConnectionStatus.disconnected;
    _syncEnabled = true;
    _connectedSince = null;
    notifyListeners();
    _scheduleBackoffReconnect(
      foregroundRecoveryActive: foregroundRecoveryActive,
      reason: 'connection lost',
    );
  }

  void _enterReconnectBackoff({required String reason}) {
    final now = DateTime.now();
    final bool foregroundRecoveryActive = _isForegroundRecoveryActive(now: now);
    _status = foregroundRecoveryActive
        ? ConnectionStatus.connecting
        : ConnectionStatus.disconnected;
    _syncEnabled = true;
    notifyListeners();
    _scheduleBackoffReconnect(
      foregroundRecoveryActive: foregroundRecoveryActive,
      reason: reason,
    );
  }

  void _scheduleBackoffReconnect({
    required bool foregroundRecoveryActive,
    required String reason,
  }) {
    final saved = _savedServer;
    if (!_manualMode || saved == null) {
      _reconnectTimer?.cancel();
      AppLogger.info('无已保存二维码设备，断开后不自动重连');
      return;
    }

    final reconnectDelay = _recoveryPolicy.reconnectDelay(
      reconnectAttempt: _reconnectAttempt,
      foregroundRecoveryActive: foregroundRecoveryActive,
    );
    _reconnectAttempt = foregroundRecoveryActive ? 0 : _reconnectAttempt + 1;

    AppLogger.info(
      '计划重连: delay=${reconnectDelay.inMilliseconds}ms '
      'attempt=$_reconnectAttempt reason=$reason '
      'networkKey=${_networkKeyForLog()}',
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      reconnectDelay,
      () {
        if (_status != ConnectionStatus.disconnected &&
            _status != ConnectionStatus.connecting) {
          return;
        }
        final latestSaved = _savedServer;
        if (_manualMode && latestSaved != null) {
          _beginSavedServerRace(latestSaved, reason: reason);
        } else {
          _setStatus(ConnectionStatus.disconnected);
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
