import 'dart:async';

import 'connection_tuning.dart';

/// 单候选探测函数：返回 true 表示该候选建链 + 握手成功。
///
/// [cancellation] 在本候选被超时 / 竞速结束 / 整体取消时触发，探测实现必须在
/// 回调里完成「subscription.cancel + sink.close」等资源清理，避免连接泄漏。
typedef RaceAttempt = Future<bool> Function(
  RaceCandidate candidate,
  RaceCancellation cancellation,
);

typedef RaceAttemptStartedCallback = void Function(
  RaceCandidate candidate,
  Duration launchDelay,
);

typedef RaceAttemptFailedCallback = void Function(RaceFailure failure);

typedef RaceWinnerCallback = void Function(RaceOutcome outcome);

/// 参与竞速的候选；[index] 是它在原始候选列表中的顺序（决定 stagger 延迟）。
class RaceCandidate {
  const RaceCandidate({required this.ip, required this.index});

  final String ip;
  final int index;

  @override
  String toString() => 'RaceCandidate($ip, index=$index)';
}

enum RaceFailureReason {
  /// 探测返回 false 或抛异常。
  failed,

  /// 单候选超时；探测实现会通过 cancellation 收到清理信号。
  timeout,

  /// 整体竞速被取消（generation 变化 / dispose）。
  cancelled,

  /// 整体竞速预算到点，该候选还没来得及启动或仍在飞行中。
  budgetExhausted,
}

class RaceFailure {
  const RaceFailure({
    required this.candidate,
    required this.reason,
    required this.elapsed,
  });

  final RaceCandidate candidate;
  final RaceFailureReason reason;

  /// 从该候选启动到失败判定之间的耗时。
  final Duration elapsed;

  @override
  String toString() =>
      '${candidate.ip} ${reason.name} after ${elapsed.inMilliseconds}ms';
}

class RaceOutcome {
  const RaceOutcome({
    required this.candidate,
    required this.elapsed,
    required this.attemptElapsed,
  });

  final RaceCandidate candidate;

  /// 从整体竞速开始到 winner 判定的耗时。
  final Duration elapsed;

  /// 从 winner 候选启动到成功的耗时。
  final Duration attemptElapsed;

  @override
  String toString() =>
      '${candidate.ip} won in ${elapsed.inMilliseconds}ms '
      '(attempt ${attemptElapsed.inMilliseconds}ms)';
}

/// 一次并行竞速的完整结果；全部失败/预算超时/取消时 [winner] 为 null。
class ConnectionRaceResult {
  const ConnectionRaceResult({
    this.winner,
    this.failures = const <RaceFailure>[],
    this.cancelled = false,
    this.budgetExhausted = false,
    required this.elapsed,
  });

  final RaceOutcome? winner;
  final List<RaceFailure> failures;
  final bool cancelled;
  final bool budgetExhausted;
  final Duration elapsed;

  bool get succeeded => winner != null;

  /// 实际启动过的候选数（失败记录 + winner）。
  int get attemptedCount => failures.length + (winner == null ? 0 : 1);

  @override
  String toString() =>
      'ConnectionRaceResult(winner=$winner, failures=${failures.length}, '
      'cancelled=$cancelled, budgetExhausted=$budgetExhausted, '
      'elapsed=${elapsed.inMilliseconds}ms)';
}

/// 取消令牌：探测实现注册清理回调，竞速在超时/取消时统一触发。
class RaceCancellation {
  final List<void Function()> _callbacks = <void Function()>[];
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void whenCancelled(void Function() callback) {
    if (_cancelled) {
      _runSafely(callback);
      return;
    }
    _callbacks.add(callback);
  }

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    final callbacks = List<void Function()>.of(_callbacks);
    _callbacks.clear();
    for (final callback in callbacks) {
      _runSafely(callback);
    }
  }

  void _runSafely(void Function() callback) {
    try {
      callback();
    } catch (_) {
      // 清理回调不允许反过来打断竞速收尾。
    }
  }
}

/// 竞速句柄：调用方可以 cancel（generation 变化 / dispose / 网络切换）。
///
/// 2026-11-20 修复：句柄必须复用 _RaceRun 内部那个已经会被 complete 的
/// Completer。此前这里自己 new 了一个 Completer，_RaceRun 结束的是另一个，
/// 导致所有 `await handle.done` 永久挂起（测试 30s 超时）。句柄只持有引用，
/// 不拥有完成权。
class RaceHandle {
  RaceHandle._(this._cancel, this._completer);

  final void Function() _cancel;
  final Completer<ConnectionRaceResult> _completer;

  Future<ConnectionRaceResult> get done => _completer.future;

  void cancel() => _cancel();
}

/// Happy Eyeballs 并行竞速（2026-11-20 新增）。
///
/// 语义：
/// - 第 0 个候选立即启动，第 i 个候选在 `raceStagger * i` 后启动；
/// - 同时最多 [ConnectionTuning.raceWidth] 路在飞行，空位释放后按 stagger
///   顺延启动后续候选；
/// - 单候选超过 [attemptTimeout] 判定失败，并通过 [RaceCancellation] 让探测
///   侧关闭 socket / subscription；
/// - 首个成功立即返回 winner 并取消其余 timers / 在飞候选；
/// - 全部失败、整体预算到点、外部 cancel 都返回 winner=null 的完整结果，
///   绝不让调用方永久等待。
///
/// 该类不依赖任何真实网络；[RaceAttempt] 由调用方注入，单元测试用 fake 与
/// 极短 Duration 驱动。
class ConnectionRace {
  const ConnectionRace({this.tuning = const ConnectionTuning()});

  final ConnectionTuning tuning;

  RaceHandle start({
    required List<String> candidates,
    required RaceAttempt attempt,
    required bool Function() isCancelled,
    Duration? attemptTimeout,
    Duration? budget,
    RaceAttemptStartedCallback? onAttemptStarted,
    RaceAttemptFailedCallback? onAttemptFailed,
    RaceWinnerCallback? onWinner,
  }) {
    final completer = Completer<ConnectionRaceResult>();
    final run = _RaceRun(
      tuning: tuning,
      candidates: List<String>.of(candidates),
      attempt: attempt,
      isCancelled: isCancelled,
      attemptTimeout: attemptTimeout ?? tuning.knownNetworkAttemptTimeout,
      budget: budget ?? tuning.raceBudget,
      completer: completer,
      onAttemptStarted: onAttemptStarted,
      onAttemptFailed: onAttemptFailed,
      onWinner: onWinner,
    );
    final handle = RaceHandle._(run.cancel, completer);
    run.start();
    return handle;
  }
}

class _ActiveAttempt {
  _ActiveAttempt({
    required this.candidate,
    required this.cancellation,
    required this.launchedAt,
  });

  final RaceCandidate candidate;
  final RaceCancellation cancellation;
  final Duration launchedAt;
  Timer? timeoutTimer;
  bool settled = false;

  void settle() {
    settled = true;
    timeoutTimer?.cancel();
  }
}

class _RaceRun {
  _RaceRun({
    required this.tuning,
    required this.candidates,
    required this.attempt,
    required this.isCancelled,
    required this.attemptTimeout,
    required this.budget,
    required this.completer,
    required this.onAttemptStarted,
    required this.onAttemptFailed,
    required this.onWinner,
  });

  final ConnectionTuning tuning;
  final List<String> candidates;
  final RaceAttempt attempt;
  final bool Function() isCancelled;
  final Duration attemptTimeout;
  final Duration budget;
  final Completer<ConnectionRaceResult> completer;
  final RaceAttemptStartedCallback? onAttemptStarted;
  final RaceAttemptFailedCallback? onAttemptFailed;
  final RaceWinnerCallback? onWinner;

  final Stopwatch _stopwatch = Stopwatch()..start();
  final List<RaceFailure> _failures = <RaceFailure>[];
  final Map<int, _ActiveAttempt> _active = <int, _ActiveAttempt>{};
  final List<Timer> _staggerTimers = <Timer>[];
  Timer? _budgetTimer;
  int _nextIndex = 0;
  bool _finished = false;

  void start() {
    if (candidates.isEmpty) {
      _finish(cancelled: false, budgetExhausted: false);
      return;
    }
    _budgetTimer = Timer(budget, () {
      _finish(cancelled: false, budgetExhausted: true);
    });
    _pump();
  }

  /// 按 stagger + 并发宽度启动候选；没有空位或未到启动时间就等待。
  void _pump() {
    if (_finished) {
      return;
    }
    if (isCancelled()) {
      cancel();
      return;
    }
    while (_active.length < tuning.raceWidth && _nextIndex < candidates.length) {
      final launchDelay = tuning.raceStagger * _nextIndex;
      final elapsed = _stopwatch.elapsed;
      if (launchDelay > elapsed) {
        final timer = Timer(launchDelay - elapsed, () {
          if (!_finished) {
            _pump();
          }
        });
        _staggerTimers.add(timer);
        return;
      }
      final index = _nextIndex;
      _nextIndex++;
      _launch(index);
    }
    if (_nextIndex >= candidates.length && _active.isEmpty) {
      _finish(cancelled: false, budgetExhausted: false);
    }
  }

  void _launch(int index) {
    final candidate = RaceCandidate(ip: candidates[index], index: index);
    final cancellation = RaceCancellation();
    final launchedAt = _stopwatch.elapsed;
    final active = _ActiveAttempt(
      candidate: candidate,
      cancellation: cancellation,
      launchedAt: launchedAt,
    );
    _active[index] = active;
    onAttemptStarted?.call(candidate, launchedAt);

    active.timeoutTimer = Timer(attemptTimeout, () {
      if (active.settled || _finished) {
        return;
      }
      active.settle();
      // 先让探测侧关闭资源，再记录超时，日志里能看到真实清理顺序。
      cancellation.cancel();
      _recordFailure(
        candidate,
        RaceFailureReason.timeout,
        _stopwatch.elapsed - launchedAt,
      );
    });

    Future<bool> attemptFuture;
    try {
      attemptFuture = attempt(candidate, cancellation);
    } catch (error, stackTrace) {
      attemptFuture = Future<bool>.error(error, stackTrace);
    }
    attemptFuture.then(
      (success) {
        if (_finished || active.settled) {
          return;
        }
        active.settle();
        final elapsed = _stopwatch.elapsed - launchedAt;
        if (success) {
          _finishWithWinner(candidate, elapsed);
        } else {
          _recordFailure(candidate, RaceFailureReason.failed, elapsed);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_finished || active.settled) {
          return;
        }
        active.settle();
        _recordFailure(
          candidate,
          RaceFailureReason.failed,
          _stopwatch.elapsed - launchedAt,
        );
      },
    );
  }

  void _recordFailure(
    RaceCandidate candidate,
    RaceFailureReason reason,
    Duration elapsed,
  ) {
    if (_finished) {
      return;
    }
    _active.remove(candidate.index);
    final failure = RaceFailure(
      candidate: candidate,
      reason: reason,
      elapsed: elapsed,
    );
    _failures.add(failure);
    onAttemptFailed?.call(failure);
    _pump();
  }

  void _finishWithWinner(RaceCandidate candidate, Duration attemptElapsed) {
    if (_finished) {
      return;
    }
    final elapsed = _stopwatch.elapsed;
    _finished = true;
    _cancelAllResources();
    final outcome = RaceOutcome(
      candidate: candidate,
      elapsed: elapsed,
      attemptElapsed: attemptElapsed,
    );
    onWinner?.call(outcome);
    if (!completer.isCompleted) {
      completer.complete(
        ConnectionRaceResult(
          winner: outcome,
          failures: List<RaceFailure>.unmodifiable(_failures),
          elapsed: elapsed,
        ),
      );
    }
  }

  void cancel() {
    if (_finished) {
      return;
    }
    _finish(cancelled: true, budgetExhausted: false);
  }

  void _finish({required bool cancelled, required bool budgetExhausted}) {
    if (_finished) {
      return;
    }
    final elapsed = _stopwatch.elapsed;
    _finished = true;
    // 还在飞行的候选按取消/预算原因记录，便于日志区分「全失败」与「没等到」。
    final inFlightReason = budgetExhausted
        ? RaceFailureReason.budgetExhausted
        : RaceFailureReason.cancelled;
    for (final active in List<_ActiveAttempt>.of(_active.values)) {
      final failure = RaceFailure(
        candidate: active.candidate,
        reason: inFlightReason,
        elapsed: elapsed - active.launchedAt,
      );
      _failures.add(failure);
      onAttemptFailed?.call(failure);
    }
    if (budgetExhausted) {
      // 没来得及启动的候选也显式记录，便于日志确认「预算不够」而不是「全失败」。
      for (var index = _nextIndex; index < candidates.length; index++) {
        if (_active.containsKey(index)) {
          continue;
        }
        _failures.add(
          RaceFailure(
            candidate: RaceCandidate(ip: candidates[index], index: index),
            reason: RaceFailureReason.budgetExhausted,
            elapsed: Duration.zero,
          ),
        );
      }
    }
    _cancelAllResources();
    if (!completer.isCompleted) {
      completer.complete(
        ConnectionRaceResult(
          failures: List<RaceFailure>.unmodifiable(_failures),
          cancelled: cancelled,
          budgetExhausted: budgetExhausted,
          elapsed: elapsed,
        ),
      );
    }
  }

  void _cancelAllResources() {
    _budgetTimer?.cancel();
    _budgetTimer = null;
    for (final timer in _staggerTimers) {
      timer.cancel();
    }
    _staggerTimers.clear();
    final activeAttempts = List<_ActiveAttempt>.of(_active.values);
    _active.clear();
    for (final active in activeAttempts) {
      active.settle();
      active.cancellation.cancel();
    }
  }
}
