import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/errors/app_exception.dart';

/// Disables a submit action after a `429`, honouring `Retry-After`.
mixin CooldownState<T extends StatefulWidget> on State<T> {
  Timer? _cooldown;

  bool get coolingDown => _cooldown?.isActive ?? false;

  void startCooldown(Duration d) {
    _cooldown?.cancel();
    _cooldown = Timer(d, () {
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  /// Starts a cooldown when [error] is a rate-limit. Returns true if so.
  bool applyRateLimit(Object error) {
    final e = AppException.from(error);
    if (e.kind != AppErrorKind.rateLimited) return false;
    startCooldown(e.retryAfter ?? const Duration(seconds: 30));
    return true;
  }

  @override
  void dispose() {
    _cooldown?.cancel();
    super.dispose();
  }
}
