import '../../../core/errors/app_exception.dart';

/// Sleeps for a duration. Injected so tests can run polling instantly.
typedef Sleep = Future<void> Function(Duration);

Future<void> realSleep(Duration d) => Future<void>.delayed(d);

/// Bounded back-off schedule for confirming payments with the server.
///
/// Default: 2s, 2s, 3s, 5s, 8s, then every 10s, for at most ~2 minutes.
class PollSchedule {
  const PollSchedule({
    this.steps = const [
      Duration(seconds: 2),
      Duration(seconds: 2),
      Duration(seconds: 3),
      Duration(seconds: 5),
      Duration(seconds: 8),
    ],
    this.cap = const Duration(seconds: 10),
    this.maxTotal = const Duration(minutes: 2),
    this.maxConsecutiveErrors = 4,
  });

  final List<Duration> steps;
  final Duration cap;
  final Duration maxTotal;

  /// Transient errors tolerated in a row before giving up.
  final int maxConsecutiveErrors;

  Duration delayAt(int attempt) => attempt < steps.length ? steps[attempt] : cap;
}

enum PollEnd { done, timedOut, failed, cancelled }

class PollResult<T> {
  const PollResult(this.end, {this.last, this.error});
  final PollEnd end;
  final T? last;
  final Object? error;
}

/// Calls [fetch] immediately and then on [schedule] until [isDone] returns
/// true, the total budget is spent, a non-transient error occurs, or
/// [isCancelled] returns true. [onUpdate] receives every successful fetch.
///
/// Elapsed time is accumulated from the scheduled delays (not wall clock) so
/// the bound is deterministic under test.
Future<PollResult<T>> pollUntil<T>({
  required Future<T> Function() fetch,
  required bool Function(T value) isDone,
  required Sleep sleep,
  PollSchedule schedule = const PollSchedule(),
  void Function(T value)? onUpdate,
  bool Function()? isCancelled,
}) async {
  var elapsed = Duration.zero;
  var attempt = 0;
  var errors = 0;
  T? last;
  Object? lastError;
  while (true) {
    if (isCancelled?.call() ?? false) {
      return PollResult(PollEnd.cancelled, last: last);
    }
    try {
      final value = await fetch();
      errors = 0;
      last = value;
      if (isCancelled?.call() ?? false) {
        return PollResult(PollEnd.cancelled, last: last);
      }
      onUpdate?.call(value);
      if (isDone(value)) return PollResult(PollEnd.done, last: value);
    } catch (e) {
      final ex = AppException.from(e);
      final transient =
          ex.kind == AppErrorKind.network || ex.kind == AppErrorKind.server ||
              ex.kind == AppErrorKind.rateLimited;
      lastError = ex;
      errors++;
      if (!transient || errors >= schedule.maxConsecutiveErrors) {
        return PollResult(PollEnd.failed, last: last, error: ex);
      }
    }
    var delay = schedule.delayAt(attempt++);
    if (lastError is AppException && lastError.retryAfter != null &&
        lastError.retryAfter! > delay) {
      delay = lastError.retryAfter!;
    }
    lastError = null;
    if (elapsed + delay > schedule.maxTotal) {
      return PollResult(PollEnd.timedOut, last: last);
    }
    elapsed += delay;
    await sleep(delay);
  }
}
