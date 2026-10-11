import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bizzvot/core/api/api_client.dart';
import 'package:bizzvot/core/api/endpoints.dart';
import 'package:bizzvot/core/errors/app_exception.dart';
import 'package:bizzvot/core/secure_storage/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_api.dart';

/// Adapter that returns 401 until the request carries [validToken].
class _AuthAdapter implements HttpClientAdapter {
  _AuthAdapter(this.validToken);
  String validToken;
  final seenAuth = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final auth = options.headers['Authorization'] as String?;
    seenAuth.add(auth);
    if (auth != 'Bearer $validToken') {
      return ResponseBody.fromString(
        jsonEncode({'success': false, 'error': {'message': 'expired'}}),
        401,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'success': true, 'data': {'ok': true}}),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('envelope', () {
    test('unwraps success data', () async {
      final fake = FakeApi()..on('GET', '/x', FakeResponse.ok({'a': 1}));
      final data = await fake.client.get('/x', parse: (d) => d);
      expect(data, {'a': 1});
    });

    test('maps 409 / 429 / 403 / 410 to kinds with server message', () async {
      final fake = FakeApi()
        ..on('POST', '/dup', FakeResponse.error(409, 'Already reviewed'))
        ..on('POST', '/rl', FakeResponse.error(429, 'Slow down', headers: {
              'retry-after': ['30'],
            }))
        ..on('GET', '/f', FakeResponse.error(403, 'Plan restriction'))
        ..on('POST', '/g', FakeResponse.error(410, 'Retired'));

      Future<AppException> err(Future<void> f) async {
        try {
          await f;
        } on AppException catch (e) {
          return e;
        }
        fail('expected AppException');
      }

      final dup = await err(fake.client.post('/dup', parse: (_) {}));
      expect(dup.kind, AppErrorKind.conflict);
      expect(dup.message, 'Already reviewed');

      final rl = await err(fake.client.post('/rl', parse: (_) {}));
      expect(rl.kind, AppErrorKind.rateLimited);
      expect(rl.retryAfter, const Duration(seconds: 30));

      expect((await err(fake.client.get('/f', parse: (_) {}))).kind,
          AppErrorKind.forbidden);
      expect((await err(fake.client.post('/g', parse: (_) {}))).kind,
          AppErrorKind.gone);
    });

    test('5xx never surfaces server text', () async {
      final fake = FakeApi()
        ..on('GET', '/boom', FakeResponse.error(500, 'MongoError: E11000 at db.cards'));
      try {
        await fake.client.get('/boom', parse: (_) {});
        fail('expected');
      } on AppException catch (e) {
        expect(e.kind, AppErrorKind.server);
        expect(e.message, isNot(contains('Mongo')));
      }
    });

    test('success:false with 200 throws', () async {
      final fake = FakeApi()
        ..on('GET', '/weird', const FakeResponse(200, {
              'success': false,
              'error': {'message': 'Nope', 'code': 'X'},
            }));
      expect(
        () => fake.client.get('/weird', parse: (_) {}),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'X')),
      );
    });
  });

  group('AuthInterceptor', () {
    late MemoryTokenStore store;
    late Dio dio;
    late _AuthAdapter adapter;
    late int refreshCalls;
    late int expiredCalls;

    void build({required Future<SessionTokens?> Function(SessionTokens) refresh}) {
      dio = Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'));
      adapter = _AuthAdapter('new');
      dio.httpClientAdapter = adapter;
      dio.interceptors.add(AuthInterceptor(
        store: store,
        dio: dio,
        refresh: (t) {
          refreshCalls++;
          return refresh(t);
        },
        onSessionExpired: () => expiredCalls++,
      ));
    }

    setUp(() async {
      store = MemoryTokenStore();
      await store.write(const SessionTokens(accessToken: 'old', refreshToken: 'r1'));
      refreshCalls = 0;
      expiredCalls = 0;
    });

    test('concurrent 401s share one refresh and retry once each', () async {
      final gate = Completer<void>();
      build(refresh: (_) async {
        await gate.future;
        return const SessionTokens(accessToken: 'new', refreshToken: 'r2');
      });
      final client = ApiClient(dio);
      final futures = List.generate(3, (_) => client.get('/me', parse: (d) => d));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();
      final results = await Future.wait(futures);

      expect(results, everyElement({'ok': true}));
      expect(refreshCalls, 1);
      expect((await store.read())!.refreshToken, 'r2');
      expect(expiredCalls, 0);
    });

    test('failed refresh clears store, signals expiry, throws unauthenticated', () async {
      build(refresh: (_) async => null);
      final client = ApiClient(dio);
      await expectLater(
        client.get('/me', parse: (d) => d),
        throwsA(isA<AppException>()
            .having((e) => e.kind, 'kind', AppErrorKind.unauthenticated)),
      );
      expect(await store.read(), isNull);
      expect(expiredCalls, 1);
    });

    test('offline refresh keeps the session and reports a network error', () async {
      build(refresh: (t) async => throw DioException(
            requestOptions: RequestOptions(path: '/auth/refresh'),
            type: DioExceptionType.connectionError,
          ));
      final client = ApiClient(dio);
      await expectLater(
        client.get('/me', parse: (d) => d),
        throwsA(isA<AppException>().having((e) => e.kind, 'kind', AppErrorKind.network)),
      );
      expect(await store.read(), isNotNull);
      expect(expiredCalls, 0);
    });

    test('anonymous requests carry no credentials and never refresh', () async {
      build(refresh: (_) async => const SessionTokens(accessToken: 'new'));
      adapter.validToken = 'none';
      final client = ApiClient(dio);
      await expectLater(
        client.get(Endpoints.publicCard('a'), parse: (d) => d, anonymous: true),
        throwsA(isA<AppException>()),
      );
      expect(adapter.seenAuth.single, isNull);
      expect(refreshCalls, 0);
    });

    test('noRefresh (login) 401 does not trigger refresh', () async {
      build(refresh: (_) async => const SessionTokens(accessToken: 'new'));
      final client = ApiClient(dio);
      await expectLater(
        client.post(Endpoints.login, parse: (d) => d, noRefresh: true),
        throwsA(isA<AppException>()),
      );
      expect(refreshCalls, 0);
    });
  });

  test('HttpDateParser parses IMF-fixdate', () {
    expect(
      HttpDateParser.parse('Wed, 21 Oct 2026 07:28:00 GMT'),
      DateTime.utc(2026, 10, 21, 7, 28),
    );
  });

  test('endpoints encode path params', () {
    expect(Endpoints.publicCard('a/b c'), '/public/card/a%2Fb%20c');
  });
}
