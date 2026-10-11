import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exception.dart';
import 'app.dart';

/// App entry. Crash reporting hooks go here; reporters must redact tokens
/// and personal data (see docs/SECURITY.md).
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Inter font'], ofl);
  });

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _report(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _report(error, stack);
    return true;
  };

  runApp(const ProviderScope(retry: providerRetry, child: BizzvotApp()));
}

void _report(Object error, StackTrace? stack) {
  // Only the error type is logged: messages may contain request data.
  if (kDebugMode) debugPrint('Unhandled ${error.runtimeType}');
  // TODO(release): forward to crash reporting with PII scrubbing.
}

/// Riverpod retries failed providers by default. Only transient network /
/// 5xx failures are retried (max 2, backoff); 4xx such as 403/404/409/429
/// must never be retried automatically.
Duration? providerRetry(int retryCount, Object error) {
  if (retryCount >= 2) return null;
  final e = AppException.from(error);
  if (e.kind != AppErrorKind.network && e.kind != AppErrorKind.server) {
    return null;
  }
  return Duration(milliseconds: 500 * (1 << retryCount));
}
