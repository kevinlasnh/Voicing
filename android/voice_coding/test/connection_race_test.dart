import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicing/connection_race.dart';
import 'package:voicing/connection_tuning.dart';

/// `ConnectionRace` 单元测试：全部用 fake dial + 极短 Duration，不碰真实网络。
///
/// 覆盖：首个成功胜出、stagger 启动、全部失败、整体预算超时、外部取消、
/// 单候选超时与资源取消（通过 RaceCancellation 观察探测侧清理回调）。
void main() {
  const tuning = ConnectionTuning(
    raceStagger: Duration(milliseconds: 20),
    raceWidth: 3,
    raceBudget: Duration(milliseconds: 300),
    knownNetworkAttemptTimeout: Duration(milliseconds: 100),
  );

  test('first success wins immediately and skips later stagger candidates', () async {
    final started = <String>[];
    final dialed = <String>[];
    const race = ConnectionRace(tuning: tuning);
    final handle = race.start(
      candidates: const ['192.168.1.50', '10.0.0.5', '100.64.0.7'],
      attempt: (candidate, cancellation) async {
        dialed.add(candidate.ip);
        return true;
      },
      isCancelled: () => false,
      onAttemptStarted: (candidate, _) => started.add(candidate.ip),
      attemptTimeout: const Duration(milliseconds: 60),
    );

    final result = await handle.done;

    expect(result.succeeded, isTrue);
    expect(result.winner!.candidate.ip, '192.168.1.50');
    expect(result.failures, isEmpty);
    expect(dialed, ['192.168.1.50']);
    expect(started, ['192.168.1.50']);
    expect(result.cancelled, isFalse);
    expect(result.budgetExhausted, isFalse);
  });

  test('candidates start after stagger * index', () async {
    final launches = <String, Duration>{};
    const race = ConnectionRace(tuning: tuning);
    final handle = race.start(
      candidates: const ['a-ip', 'b-ip', 'c-ip'],
      attempt: (candidate, cancellation) async => false,
      isCancelled: () => false,
      attemptTimeout: const Duration(milliseconds: 50),
      onAttemptStarted: (candidate, launchDelay) =>
          launches[candidate.ip] = launchDelay,
    );

    final result = await handle.done;

    expect(result.succeeded, isFalse);
    expect(result.failures.length, 3);
    expect(launches.length, 3);
    // 只断言下界：Timer 在 CI 上只会更晚，不会更早。
    expect(launches['a-ip']!.inMilliseconds, lessThan(15));
    expect(launches['b-ip']!.inMilliseconds, greaterThanOrEqualTo(15));
    expect(launches['c-ip']!.inMilliseconds, greaterThanOrEqualTo(35));
  });

  test('all candidates failing returns null winner with every failure recorded', () async {
    const race = ConnectionRace(tuning: tuning);
    final handle = race.start(
      candidates: const ['a-ip', 'b-ip'],
      attempt: (candidate, cancellation) async => false,
      isCancelled: () => false,
      attemptTimeout: const Duration(milliseconds: 50),
    );

    final result = await handle.done;

    expect(result.winner, isNull);
    expect(result.cancelled, isFalse);
    expect(result.budgetExhausted, isFalse);
    expect(
      result.failures.map((failure) => failure.candidate.ip).toSet(),
      {'a-ip', 'b-ip'},
    );
    expect(
      result.failures.every((f) => f.reason == RaceFailureReason.failed),
      isTrue,
    );
  });

  test('overall budget expires, cancels in-flight attempts and returns null', () async {
    final cancelled = <String>[];
    const race = ConnectionRace(
      tuning: ConnectionTuning(
        raceStagger: Duration(milliseconds: 5),
        raceWidth: 3,
        raceBudget: Duration(milliseconds: 40),
        knownNetworkAttemptTimeout: Duration(milliseconds: 500),
      ),
    );
    final handle = race.start(
      candidates: const ['a-ip', 'b-ip'],
      attempt: (candidate, cancellation) {
        cancellation.whenCancelled(() => cancelled.add(candidate.ip));
        return Completer<bool>().future;
      },
      isCancelled: () => false,
      attemptTimeout: const Duration(milliseconds: 500),
    );

    final result = await handle.done;

    expect(result.winner, isNull);
    expect(result.budgetExhausted, isTrue);
    expect(result.elapsed.inMilliseconds, lessThan(400));
    expect(cancelled.toSet(), {'a-ip', 'b-ip'});
    expect(
      result.failures
          .where((f) => f.reason == RaceFailureReason.budgetExhausted)
          .length,
      2,
    );
  });

  test('single candidate timeout triggers cancellation cleanup', () async {
    var cleanedUp = false;
    const race = ConnectionRace(
      tuning: ConnectionTuning(
        raceStagger: Duration(milliseconds: 1),
        raceWidth: 3,
        raceBudget: Duration(milliseconds: 500),
      ),
    );
    final handle = race.start(
      candidates: const ['slow-ip'],
      attempt: (candidate, cancellation) {
        cancellation.whenCancelled(() => cleanedUp = true);
        return Completer<bool>().future;
      },
      isCancelled: () => false,
      attemptTimeout: const Duration(milliseconds: 20),
      budget: const Duration(milliseconds: 300),
    );

    final result = await handle.done;

    expect(result.winner, isNull);
    expect(result.failures.single.reason, RaceFailureReason.timeout);
    expect(cleanedUp, isTrue);
  });

  test('external cancel returns cancelled result and cancels in-flight probes', () async {
    final cancelled = <String>[];
    const race = ConnectionRace(tuning: tuning);
    final handle = race.start(
      candidates: const ['a-ip', 'b-ip'],
      attempt: (candidate, cancellation) {
        cancellation.whenCancelled(() => cancelled.add(candidate.ip));
        return Completer<bool>().future;
      },
      isCancelled: () => false,
      attemptTimeout: const Duration(milliseconds: 500),
      budget: const Duration(milliseconds: 500),
    );

    // 等两个候选都通过 stagger 启动后再取消，才能真正覆盖「在飞探测被清理」；
    // 20ms stagger，等 40ms 留出调度余量。
    await Future<void>.delayed(const Duration(milliseconds: 40));
    handle.cancel();
    final result = await handle.done;

    expect(result.winner, isNull);
    expect(result.cancelled, isTrue);
    expect(cancelled.toSet(), {'a-ip', 'b-ip'});
  });

  test('winner cancels the still-running sibling probe', () async {
    var siblingCancelled = false;
    const race = ConnectionRace(
      tuning: ConnectionTuning(
        raceStagger: Duration(milliseconds: 5),
        raceWidth: 2,
        raceBudget: Duration(milliseconds: 300),
      ),
    );
    final handle = race.start(
      candidates: const ['slow-ip', 'fast-ip'],
      attempt: (candidate, cancellation) {
        if (candidate.ip == 'slow-ip') {
          cancellation.whenCancelled(() => siblingCancelled = true);
          return Completer<bool>().future;
        }
        return Future<bool>.delayed(
          const Duration(milliseconds: 15),
          () => true,
        );
      },
      isCancelled: () => false,
      attemptTimeout: const Duration(milliseconds: 200),
      budget: const Duration(milliseconds: 300),
    );

    final result = await handle.done;

    expect(result.winner!.candidate.ip, 'fast-ip');
    expect(siblingCancelled, isTrue);
  });

  test('empty candidate list finishes without waiting for budget', () async {
    const race = ConnectionRace(tuning: tuning);
    final result = await race
        .start(
          candidates: const [],
          attempt: (candidate, cancellation) async => true,
          isCancelled: () => false,
        )
        .done;

    expect(result.winner, isNull);
    expect(result.failures, isEmpty);
    expect(result.elapsed.inMilliseconds, lessThan(50));
  });
}
