import 'package:bizzvot/app/theme.dart';
import 'package:bizzvot/core/auth/auth_repository.dart';
import 'package:bizzvot/core/auth/session_controller.dart';
import 'package:bizzvot/core/config/app_config.dart';
import 'package:bizzvot/features/auth/data/auth_flow_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records calls; throws the configured error (if any) for each action.
class FakeAuthFlow implements AuthFlowRepository {
  Object? error;
  final calls = <String>[];
  RegisterRequest? lastRegister;
  String? lastEmail;

  Future<void> _run(String name) async {
    calls.add(name);
    final e = error;
    if (e != null) throw e;
  }

  @override
  Future<void> loginOwner(String email, String password) {
    lastEmail = email;
    return _run('loginOwner');
  }

  @override
  Future<void> loginStaff(String email, String password) {
    lastEmail = email;
    return _run('loginStaff');
  }

  @override
  Future<void> register(RegisterRequest request) {
    lastRegister = request;
    return _run('register');
  }

  @override
  Future<void> forgotPassword(String email) {
    lastEmail = email;
    return _run('forgotPassword');
  }

  @override
  Future<void> resetPassword({required String token, required String password}) =>
      _run('resetPassword');

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _run('changePassword');
}

class FixedSession extends SessionController {
  FixedSession(this.initial);
  final SessionState initial;

  @override
  SessionState build() => initial;
}

Widget authHarness(
  Widget screen, {
  required FakeAuthFlow auth,
  SessionState session = const SignedOut(),
}) =>
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        authFlowRepositoryProvider.overrideWithValue(auth),
        sessionControllerProvider.overrideWith(() => FixedSession(session)),
        currentConfigProvider.overrideWithValue(AppConfig.defaults),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: screen),
    );

Future<void> enterField(WidgetTester tester, String label, String text) async {
  final f = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  // Let the focused field's scroll-into-view animation finish.
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pump();
  await tester.pump();
}

Future<void> tapButton(WidgetTester tester, String label) async {
  final f = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pump();
  await tester.pump();
}
