import 'dart:typed_data';
import 'dart:ui';

import 'package:bizzvot/app/theme.dart';
import 'package:bizzvot/features/public_card/data/external_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Pumps [home] at `/` inside a GoRouter-backed app. Any other location
/// renders a placeholder showing the path, so navigation can be asserted.
Future<void> pumpTestApp(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/:rest(.*)',
        builder: (_, s) => Scaffold(body: Text('route:${s.uri.path}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
}

/// Records launches and shares instead of calling platform plugins.
class FakeExternalActions implements ExternalActions {
  final opened = <Uri>[];
  final sharedText = <String>[];
  final sharedFiles = <String>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async =>
      sharedText.add(text);

  @override
  Future<void> shareFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? subject,
    Rect? origin,
  }) async => sharedFiles.add(fileName);
}
