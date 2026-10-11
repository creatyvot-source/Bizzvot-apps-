import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// App entry. Crash reporting hooks go here; reporters must redact tokens
/// and personal data (see docs/SECURITY.md).
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _report(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _report(error, stack);
    return true;
  };

  runApp(const ProviderScope(child: BizzvotApp()));
}

void _report(Object error, StackTrace? stack) {
  // Only the error type is logged: messages may contain request data.
  if (kDebugMode) debugPrint('Unhandled ${error.runtimeType}');
  // TODO(release): forward to crash reporting with PII scrubbing.
}
