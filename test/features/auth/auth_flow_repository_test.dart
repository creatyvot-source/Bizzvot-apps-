import 'package:bizzvot/core/auth/auth_repository.dart';
import 'package:bizzvot/core/auth/auth_user.dart';
import 'package:bizzvot/core/auth/session_controller.dart';
import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/core/providers.dart';
import 'package:bizzvot/core/secure_storage/token_store.dart';
import 'package:bizzvot/features/auth/data/auth_flow_repository.dart';
import 'package:bizzvot/features/auth/domain/auth_errors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_api.dart';

void main() {
  late FakeApi fake;
  late MemoryTokenStore store;
  late ProviderContainer container;

  setUp(() {
    fake = FakeApi();
    store = MemoryTokenStore();
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        apiClientProvider.overrideWithValue(fake.client),
        tokenStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
  });

  AuthFlowRepository repo() => container.read(authFlowRepositoryProvider);

  group('owner login', () {
    test('stores tokens and signs in with the /auth/me user', () async {
      fake
        ..on('POST', '/auth/login',
            FakeResponse.ok({'accessToken': 'a1', 'refreshToken': 'r1'}))
        ..on('GET', '/auth/me', FakeResponse.ok({
          'user': {'_id': 'u1', 'email': 'o@x.com', 'role': 'owner', 'name': 'Olive'},
          'organization': {'_id': 'org1', 'name': 'Acme'},
        }));

      await repo().loginOwner('  O@X.com ', 'secret123');

      final login = fake.requests.firstWhere((r) => r.path == '/auth/login');
      expect(login.body, {'email': 'o@x.com', 'password': 'secret123'});
      expect((await store.read())?.accessToken, 'a1');
      final state = container.read(sessionControllerProvider);
      expect(state, isA<SignedIn>());
      expect((state as SignedIn).user.role, UserRole.owner);
      expect(state.user.organizationName, 'Acme');
    });

    test('super_admin is rejected and credentials are wiped', () async {
      fake
        ..on('POST', '/auth/login', FakeResponse.ok({'accessToken': 'a1'}))
        ..on('GET', '/auth/me',
            FakeResponse.ok({'id': 'sa', 'email': 'a@x.com', 'role': 'super_admin'}));

      await expectLater(
        repo().loginOwner('a@x.com', 'secret123'),
        throwsA(isA<AppException>()
            .having((e) => e.kind, 'kind', AppErrorKind.forbidden)
            .having((e) => e.message, 'message', 'Use the admin sign-in page')),
      );
      expect(await store.read(), isNull);
    });

    test('server 403 for staff accounts maps to staff guidance', () async {
      fake.on('POST', '/auth/login',
          FakeResponse.error(403, 'Staff accounts must use staff login'));
      try {
        await repo().loginOwner('s@x.com', 'secret123');
        fail('expected an error');
      } catch (e) {
        final f = classifyLoginError(e, portal: LoginPortal.owner);
        expect(f.kind, LoginFailureKind.wrongPortal);
        expect(f.message, AuthMessages.useStaffLogin);
        // No account details leak into the guidance.
        expect(f.message, isNot(contains('s@x.com')));
      }
    });

    test('429 carries Retry-After for the cooldown', () async {
      fake.on(
        'POST',
        '/auth/login',
        FakeResponse.error(429, 'Too many', headers: {
          'retry-after': ['42'],
        }),
      );
      try {
        await repo().loginOwner('o@x.com', 'secret123');
        fail('expected an error');
      } catch (e) {
        final f = classifyLoginError(e, portal: LoginPortal.owner);
        expect(f.kind, LoginFailureKind.rateLimited);
        expect(f.retryAfter, const Duration(seconds: 42));
      }
    });

    test('missing tokens surface the native-session message', () async {
      fake.on('POST', '/auth/login', FakeResponse.ok({'user': {'id': 'u1'}}));
      try {
        await repo().loginOwner('o@x.com', 'secret123');
        fail('expected an error');
      } catch (e) {
        final f = classifyLoginError(e, portal: LoginPortal.owner);
        expect(f.kind, LoginFailureKind.other);
        expect(f.message, contains('not available on mobile'));
      }
    });
  });

  test('staff login uses /auth/staff-login', () async {
    fake
      ..on('POST', '/auth/staff-login', FakeResponse.ok({'tokens': {'accessToken': 'a2'}}))
      ..on('GET', '/auth/me', FakeResponse.ok({
        'id': 's1',
        'email': 's@x.com',
        'role': 'staff',
        'cardId': 'c1',
        'permissions': {'viewReviews': true},
      }));

    await repo().loginStaff('s@x.com', 'secret123');

    final state = container.read(sessionControllerProvider) as SignedIn;
    expect(state.user.isStaff, isTrue);
    expect(state.user.cardId, 'c1');
    expect(state.user.permissions.viewReviews, isTrue);
    expect(state.user.permissions.editCard, isFalse);
  });

  test('register posts the RegisterRequest body', () async {
    fake
      ..on('POST', '/auth/register', FakeResponse.ok({'accessToken': 'a3'}))
      ..on('GET', '/auth/me',
          FakeResponse.ok({'id': 'o1', 'email': 'new@x.com', 'role': 'owner'}));

    await repo().register(const RegisterRequest(
      organizationName: 'Acme',
      name: 'Olive',
      email: 'New@X.com',
      password: 'secret123',
    ));

    final req = fake.requests.firstWhere((r) => r.path == '/auth/register');
    final body = req.body as Map;
    expect(body, containsPair('organizationName', 'Acme'));
    expect(body, containsPair('name', 'Olive'));
    expect(body, containsPair('email', 'new@x.com'));
    expect(body, containsPair('password', 'secret123'));
    expect(body.containsKey('phone'), isFalse);
    expect(container.read(sessionControllerProvider), isA<SignedIn>());
  });

  test('forgot / reset / change password send the expected bodies', () async {
    fake
      ..on('POST', '/auth/forgot-password', FakeResponse.ok(null))
      ..on('POST', '/auth/reset-password', FakeResponse.ok(null))
      ..on('POST', '/auth/change-password', FakeResponse.ok(null));

    await repo().forgotPassword(' Me@X.com');
    await repo().resetPassword(token: 'tok', password: 'newpass12');
    await repo().changePassword(currentPassword: 'old', newPassword: 'newpass12');

    Object? bodyOf(String path) =>
        fake.requests.firstWhere((r) => r.path == path).body;
    expect(bodyOf('/auth/forgot-password'), {'email': 'me@x.com'});
    final reset = bodyOf('/auth/reset-password') as Map;
    expect(reset, containsPair('token', 'tok'));
    expect(reset.values, contains('newpass12'));
    final change = bodyOf('/auth/change-password') as Map;
    expect(change, containsPair('currentPassword', 'old'));
    expect(change, containsPair('newPassword', 'newpass12'));
  });
}
