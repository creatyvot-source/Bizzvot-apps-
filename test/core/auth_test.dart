import 'package:bizzvot/core/api/endpoints.dart';
import 'package:bizzvot/core/auth/auth_repository.dart';
import 'package:bizzvot/core/auth/auth_user.dart';
import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/core/secure_storage/token_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_api.dart';

void main() {
  test('parseTokens accepts flat and nested shapes', () {
    expect(parseTokens({'accessToken': 'a', 'refreshToken': 'r'})!.refreshToken, 'r');
    expect(parseTokens({'tokens': {'accessToken': 'a'}})!.accessToken, 'a');
    expect(parseTokens({'user': {}}), isNull);
  });

  test('SessionTokens.toString never prints secrets', () {
    expect(const SessionTokens(accessToken: 'secret').toString(), isNot(contains('secret')));
  });

  test('AuthUser parses nested user + organization + permissions', () {
    final u = AuthUser.fromJson({
      'user': {
        '_id': 'u1',
        'email': 'a@b.co',
        'role': 'staff',
        'cardId': 'c1',
        'permissions': {'editCard': true},
      },
      'organization': {'_id': 'o1', 'name': 'Acme'},
    });
    expect(u.id, 'u1');
    expect(u.isStaff, isTrue);
    expect(u.organizationId, 'o1');
    expect(u.organizationName, 'Acme');
    expect(u.cardId, 'c1');
    expect(u.permissions.editCard, isTrue);
    expect(u.permissions.viewReviews, isFalse);
  });

  group('AuthRepository', () {
    late FakeApi fake;
    late MemoryTokenStore store;
    late AuthRepository repo;

    setUp(() {
      fake = FakeApi();
      store = MemoryTokenStore();
      repo = AuthRepository(fake.client, store);
    });

    test('owner login stores tokens and loads /auth/me', () async {
      fake
        ..on('POST', Endpoints.login, FakeResponse.ok({'accessToken': 'a', 'refreshToken': 'r'}))
        ..on('GET', Endpoints.me, FakeResponse.ok({'id': 'u', 'email': 'o@x.co', 'role': 'owner'}));
      final user = await repo.loginOwner(' O@X.co ', 'pw123456');
      expect(user.isOwner, isTrue);
      expect((await store.read())!.accessToken, 'a');
      expect((fake.requests.first.body as Map)['email'], 'o@x.co');
    });

    test('super_admin is rejected and credentials wiped', () async {
      fake
        ..on('POST', Endpoints.login, FakeResponse.ok({'accessToken': 'a'}))
        ..on('GET', Endpoints.me, FakeResponse.ok({'id': 'u', 'email': 's@x.co', 'role': 'super_admin'}));
      await expectLater(
        repo.loginOwner('s@x.co', 'pw'),
        throwsA(isA<AppException>()
            .having((e) => e.message, 'message', 'Use the admin sign-in page')),
      );
      expect(await store.read(), isNull);
    });

    test('cookie-only login (no tokens) fails clearly', () async {
      fake.on('POST', Endpoints.login, FakeResponse.ok({'user': {'id': 'u'}}));
      await expectLater(
        repo.loginOwner('a@b.co', 'pw'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'NATIVE_SESSION_UNSUPPORTED')),
      );
    });

    test('logout wipes local tokens even when server revoke fails', () async {
      await store.write(const SessionTokens(accessToken: 'a', refreshToken: 'r'));
      fake.on('POST', Endpoints.logout, FakeResponse.error(500, 'down'));
      await repo.logout();
      expect(await store.read(), isNull);
    });
  });
}
