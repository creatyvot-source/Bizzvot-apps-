import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/features/auth/domain/auth_errors.dart';
import 'package:bizzvot/features/auth/presentation/widgets/cooldown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyLoginError', () {
    LoginFailure owner(AppException e) =>
        classifyLoginError(e, portal: LoginPortal.owner);
    LoginFailure staff(AppException e) =>
        classifyLoginError(e, portal: LoginPortal.staff);

    test('unknown, wrong password and locked accounts look identical', () {
      final cases = [
        const AppException(AppErrorKind.unauthenticated, 'Invalid credentials', statusCode: 401),
        const AppException(AppErrorKind.notFound, 'User not found', statusCode: 404),
        const AppException(AppErrorKind.forbidden, 'Account locked', statusCode: 403,
            code: 'ACCOUNT_LOCKED'),
        const AppException(AppErrorKind.unknown, 'Locked', statusCode: 423),
        const AppException(AppErrorKind.validation, 'Bad', statusCode: 400),
      ];
      for (final e in cases) {
        final f = owner(e);
        expect(f.kind, LoginFailureKind.invalidCredentials, reason: e.message);
        expect(f.message, AuthMessages.invalidCredentials);
      }
    });

    test('staff account on owner portal → staff guidance (code or message)', () {
      expect(
        owner(const AppException(AppErrorKind.forbidden, 'Nope', code: 'USE_STAFF_LOGIN')).kind,
        LoginFailureKind.wrongPortal,
      );
      expect(
        owner(const AppException(AppErrorKind.forbidden, 'Please use the staff sign-in')).kind,
        LoginFailureKind.wrongPortal,
      );
      expect(
        owner(const AppException(AppErrorKind.forbidden, 'x', code: 'ROLE_MISMATCH')).message,
        AuthMessages.useStaffLogin,
      );
    });

    test('owner account on staff portal → owner guidance', () {
      final f = staff(const AppException(AppErrorKind.forbidden, 'Use owner login'));
      expect(f.kind, LoginFailureKind.wrongPortal);
      expect(f.message, AuthMessages.useOwnerLogin);
      // "staff" in a staff-portal message is not a portal hint.
      expect(
        staff(const AppException(AppErrorKind.unauthenticated, 'Invalid staff credentials')).kind,
        LoginFailureKind.invalidCredentials,
      );
    });

    test('super_admin → admin message', () {
      final f = owner(const AppException(
        AppErrorKind.forbidden,
        'Use the admin sign-in page',
        statusCode: 403,
      ));
      expect(f.kind, LoginFailureKind.adminAccount);
      expect(f.message, 'Use the admin sign-in page');
    });

    test('rate limit and connectivity keep their own handling', () {
      final rl = owner(const AppException(
        AppErrorKind.rateLimited,
        'Slow',
        retryAfter: Duration(seconds: 9),
      ));
      expect(rl.kind, LoginFailureKind.rateLimited);
      expect(rl.retryAfter, const Duration(seconds: 9));

      final offline = owner(const AppException(AppErrorKind.network, 'You appear to be offline.'));
      expect(offline.kind, LoginFailureKind.other);
      expect(offline.message, 'You appear to be offline.');
    });
  });

  group('isInvalidResetToken', () {
    test('expired/unknown token responses', () {
      expect(isInvalidResetToken(const AppException(AppErrorKind.gone, 'x')), isTrue);
      expect(isInvalidResetToken(const AppException(AppErrorKind.notFound, 'x')), isTrue);
      expect(
        isInvalidResetToken(const AppException(AppErrorKind.validation, 'Token expired')),
        isTrue,
      );
      expect(
        isInvalidResetToken(
          const AppException(AppErrorKind.validation, 'x', code: 'INVALID_TOKEN'),
        ),
        isTrue,
      );
    });

    test('password policy errors are not link errors', () {
      expect(
        isInvalidResetToken(const AppException(
          AppErrorKind.validation,
          'Password too weak',
          fieldErrors: {'password': 'Too weak'},
        )),
        isFalse,
      );
      expect(isInvalidResetToken(const AppException(AppErrorKind.server, 'x')), isFalse);
    });
  });

  group('Cooldown', () {
    testWidgets('counts down from Retry-After and clamps tiny values', (tester) async {
      final c = Cooldown();
      c.startFrom(const AppException(
        AppErrorKind.rateLimited,
        'x',
        retryAfter: Duration(seconds: 12),
      ));
      expect(c.active, isTrue);
      expect(c.secondsLeft, 12);
      await tester.pump(const Duration(seconds: 5));
      expect(c.secondsLeft, 7);
      await tester.pump(const Duration(seconds: 7));
      expect(c.active, isFalse);

      c.start(Duration.zero);
      expect(c.secondsLeft, 5);
      c.dispose();
    });

    test('falls back when no Retry-After', () {
      final c = Cooldown(fallback: const Duration(seconds: 30));
      c.startFrom(const AppException(AppErrorKind.rateLimited, 'x'));
      expect(c.secondsLeft, 30);
      c.dispose();
    });

    test('formatCooldown', () {
      expect(formatCooldown(9), '9s');
      expect(formatCooldown(125), '2m 05s');
    });
  });
}
