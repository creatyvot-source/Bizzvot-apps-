import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../shared/widgets/feedback.dart';

/// Client-side cooldown after a `429`. Honors `Retry-After` when the server
/// sends it; otherwise waits [fallback]. Counts down once per second.
class Cooldown extends ChangeNotifier {
  Cooldown({this.fallback = const Duration(seconds: 30)});

  final Duration fallback;

  /// Upper bound so a bad header can't lock the form for hours.
  static const _max = Duration(minutes: 15);
  static const _min = Duration(seconds: 5);

  Timer? _timer;
  int _secondsLeft = 0;

  int get secondsLeft => _secondsLeft;
  bool get active => _secondsLeft > 0;

  /// Starts a cooldown from a rate-limit error.
  void startFrom(AppException e) => start(e.retryAfter ?? fallback);

  void start(Duration duration) {
    final clamped = Duration(
      seconds: math.max(
        _min.inSeconds,
        math.min(_max.inSeconds, (duration.inMilliseconds / 1000).ceil()),
      ),
    );
    _timer?.cancel();
    _secondsLeft = clamped.inSeconds;
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      _secondsLeft = math.max(0, _secondsLeft - 1);
      if (_secondsLeft == 0) t.cancel();
      notifyListeners();
    });
  }

  void reset() {
    _timer?.cancel();
    _secondsLeft = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Human-readable remaining time, e.g. `45s` or `2m 05s`.
String formatCooldown(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '${m}m ${s}s';
}

/// Primary submit button that is disabled (with a countdown label) while a
/// [Cooldown] is active, and shows a spinner while [onPressed] runs.
class CooldownSubmitButton extends StatelessWidget {
  const CooldownSubmitButton({
    super.key,
    required this.label,
    required this.cooldown,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final Cooldown cooldown;
  final Future<void> Function()? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cooldown,
      builder: (context, _) {
        final waiting = cooldown.active;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BusyButton(
              label: waiting
                  ? 'Try again in ${formatCooldown(cooldown.secondsLeft)}'
                  : label,
              icon: waiting ? null : icon,
              onPressed: waiting ? null : onPressed,
            ),
            if (waiting) ...[
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                liveRegion: true,
                child: Text(
                  'Too many attempts. Please wait before trying again.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
