import 'package:bizzvot/core/auth/session_controller.dart';
import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/features/auth/domain/auth_errors.dart';
import 'package:bizzvot/features/auth/presentation/forgot_password_screen.dart';
import 'package:bizzvot/features/auth/presentation/owner_login_screen.dart';
import 'package:bizzvot/features/auth/presentation/register_screen.dart';
import 'package:bizzvot/features/auth/presentation/reset_password_screen.dart';
import 'package:bizzvot/features/auth/presentation/staff_login_screen.dart';
import 'package:bizzvot/features/auth/presentation/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test_harness.dart';

FilledButton _button(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

void main() {
  late FakeAuthFlow auth;
  setUp(() => auth = FakeAuthFlow());

  group('WelcomeScreen', () {
    testWidgets('offers owner, staff and register choices', (tester) async {
      await tester.pumpWidget(authHarness(const WelcomeScreen(), auth: auth));
      expect(find.text('Owner sign-in'), findsOneWidget);
      expect(find.text('Staff sign-in'), findsOneWidget);
      expect(find.text('Create an organization'), findsOneWidget);
      expect(find.text('Privacy & legal'), findsOneWidget);
      expect(find.text('You’ve been signed out'), findsNothing);
    });

    testWidgets('shows a dismissible banner after an involuntary sign-out',
        (tester) async {
      await tester.pumpWidget(authHarness(
        const WelcomeScreen(),
        auth: auth,
        session: const SignedOut(expired: true),
      ));
      expect(find.text('You’ve been signed out'), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      expect(find.text('You’ve been signed out'), findsNothing);
    });
  });

  group('OwnerLoginScreen', () {
    Future<void> submit(WidgetTester tester) async {
      await enterField(tester, 'Email', 'owner@x.com');
      await enterField(tester, 'Password', 'secret123');
      await tapText(tester, 'Sign in');
    }

    testWidgets('validates before calling the API', (tester) async {
      await tester.pumpWidget(authHarness(const OwnerLoginScreen(), auth: auth));
      await tapText(tester, 'Sign in');
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('generic message for unknown/locked accounts', (tester) async {
      auth.error = const AppException(
        AppErrorKind.forbidden,
        'Account locked until 10:00',
        statusCode: 403,
      );
      await tester.pumpWidget(authHarness(const OwnerLoginScreen(), auth: auth));
      await submit(tester);
      expect(auth.calls, ['loginOwner']);
      expect(find.text(AuthMessages.invalidCredentials), findsOneWidget);
      expect(find.textContaining('locked'), findsNothing);
    });

    testWidgets('guides staff accounts to staff sign-in', (tester) async {
      auth.error = const AppException(
        AppErrorKind.forbidden,
        'x',
        code: 'USE_STAFF_LOGIN',
        statusCode: 403,
      );
      await tester.pumpWidget(authHarness(const OwnerLoginScreen(), auth: auth));
      await submit(tester);
      expect(find.text(AuthMessages.useStaffLogin), findsOneWidget);
      expect(find.text('Go to staff sign-in'), findsOneWidget);
    });

    testWidgets('super_admin sees the admin sign-in message', (tester) async {
      auth.error = const AppException(
        AppErrorKind.forbidden,
        'Use the admin sign-in page',
        statusCode: 403,
      );
      await tester.pumpWidget(authHarness(const OwnerLoginScreen(), auth: auth));
      await submit(tester);
      expect(find.text('Use the admin sign-in page'), findsOneWidget);
    });

    testWidgets('429 disables submit until Retry-After elapses', (tester) async {
      auth.error = const AppException(
        AppErrorKind.rateLimited,
        'Too many',
        statusCode: 429,
        retryAfter: Duration(seconds: 10),
      );
      await tester.pumpWidget(authHarness(const OwnerLoginScreen(), auth: auth));
      await submit(tester);

      expect(find.text('Try again in 10s'), findsOneWidget);
      expect(_button(tester, 'Try again in 10s').onPressed, isNull);

      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Try again in 6s'), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
      expect(_button(tester, 'Sign in').onPressed, isNotNull);
    });
  });

  testWidgets('StaffLoginScreen uses the staff endpoint', (tester) async {
    await tester.pumpWidget(authHarness(const StaffLoginScreen(), auth: auth));
    await enterField(tester, 'Email', 'staff@x.com');
    await enterField(tester, 'Password', 'secret123');
    await tapText(tester, 'Sign in');
    expect(auth.calls, ['loginStaff']);
  });

  group('ForgotPasswordScreen', () {
    testWidgets('same neutral confirmation for unknown accounts', (tester) async {
      auth.error = const AppException(AppErrorKind.notFound, 'No such user', statusCode: 404);
      await tester.pumpWidget(authHarness(const ForgotPasswordScreen(), auth: auth));
      await enterField(tester, 'Email', 'nobody@x.com');
      await tapText(tester, 'Send reset link');
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.text(AuthMessages.forgotNeutral), findsOneWidget);
      expect(find.textContaining('No such user'), findsNothing);
    });

    testWidgets('same confirmation on success', (tester) async {
      await tester.pumpWidget(authHarness(const ForgotPasswordScreen(), auth: auth));
      await enterField(tester, 'Email', 'me@x.com');
      await tapText(tester, 'Send reset link');
      expect(find.text(AuthMessages.forgotNeutral), findsOneWidget);
      // Resend is throttled.
      expect(find.textContaining('Send again in'), findsOneWidget);
      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('offline errors are shown so the user can retry', (tester) async {
      auth.error = const AppException(AppErrorKind.network, 'You appear to be offline.');
      await tester.pumpWidget(authHarness(const ForgotPasswordScreen(), auth: auth));
      await enterField(tester, 'Email', 'me@x.com');
      await tapText(tester, 'Send reset link');
      expect(find.text('You appear to be offline.'), findsOneWidget);
      expect(find.text('Check your email'), findsNothing);
    });
  });

  group('RegisterScreen', () {
    Future<void> fill(WidgetTester tester) async {
      await enterField(tester, 'Organization name', 'Acme');
      await enterField(tester, 'Your name', 'Olive');
      await enterField(tester, 'Work email', 'olive@acme.com');
      await enterField(tester, 'Password', 'secret123');
      await enterField(tester, 'Confirm password', 'secret123');
    }

    testWidgets('requires agreeing to the terms', (tester) async {
      await tester.pumpWidget(authHarness(const RegisterScreen(), auth: auth));
      await fill(tester);
      await tapText(tester, 'Create organization');
      expect(auth.calls, isEmpty);
      expect(find.text('You need to agree to the Terms and Privacy Policy'), findsOneWidget);

      await tapText(tester, 'I agree to the Terms of Service and Privacy Policy');
      await tapText(tester, 'Create organization');
      expect(auth.calls, ['register']);
      expect(auth.lastRegister?.organizationName, 'Acme');
      expect(auth.lastRegister?.phone, isNull);
    });

    testWidgets('409 uses neutral wording', (tester) async {
      auth.error = const AppException(
        AppErrorKind.conflict,
        'Email olive@acme.com already registered',
        statusCode: 409,
      );
      await tester.pumpWidget(authHarness(const RegisterScreen(), auth: auth));
      await fill(tester);
      await tapText(tester, 'I agree to the Terms of Service and Privacy Policy');
      await tapText(tester, 'Create organization');
      expect(find.textContaining('already registered'), findsNothing);
      expect(find.textContaining('couldn’t create an account'), findsOneWidget);
    });
  });

  group('ResetPasswordScreen', () {
    testWidgets('missing token shows an invalid-link state', (tester) async {
      await tester.pumpWidget(authHarness(const ResetPasswordScreen(), auth: auth));
      expect(find.text('Link not valid'), findsOneWidget);
      expect(find.text('Request a new link'), findsOneWidget);
    });

    testWidgets('expired token switches to the invalid-link state', (tester) async {
      auth.error = const AppException(AppErrorKind.gone, 'Expired', statusCode: 410);
      await tester.pumpWidget(
        authHarness(const ResetPasswordScreen(token: 'tok'), auth: auth),
      );
      await enterField(tester, 'New password', 'newpass123');
      await enterField(tester, 'Confirm new password', 'newpass123');
      await tapText(tester, 'Update password');
      expect(auth.calls, ['resetPassword']);
      expect(find.text('Link not valid'), findsOneWidget);
    });

    testWidgets('success state', (tester) async {
      await tester.pumpWidget(
        authHarness(const ResetPasswordScreen(token: 'tok'), auth: auth),
      );
      await enterField(tester, 'New password', 'newpass123');
      await enterField(tester, 'Confirm new password', 'different1');
      await tapText(tester, 'Update password');
      expect(find.text('Passwords don’t match'), findsOneWidget);
      expect(auth.calls, isEmpty);

      await enterField(tester, 'Confirm new password', 'newpass123');
      await tapText(tester, 'Update password');
      expect(find.text('Password updated'), findsOneWidget);
    });
  });
}
