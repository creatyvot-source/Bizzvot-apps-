import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../errors/app_exception.dart';
import '../secure_storage/token_store.dart';
import '../utilities/json.dart';
import 'auth_user.dart';

/// Native session contract (pending backend confirmation, see
/// `docs/API_GAP_REGISTER.md` §AUTH-1): login/refresh return
/// `{ accessToken, refreshToken }` in `data` (also accepted under
/// `data.tokens`). Without tokens a native session cannot be established.
SessionTokens? parseTokens(Object? data) {
  final j = asJson(data);
  final t = j['tokens'] is Map ? asJson(j['tokens']) : j;
  final access = str(t['accessToken']) ?? str(t['access_token']) ?? str(t['token']);
  if (access == null) return null;
  return SessionTokens(
    accessToken: access,
    refreshToken: str(t['refreshToken']) ?? str(t['refresh_token']),
  );
}

class RegisterRequest {
  const RegisterRequest({
    required this.organizationName,
    required this.name,
    required this.email,
    required this.password,
    this.phone,
    this.industry,
  });

  final String organizationName;
  final String name;
  final String email;
  final String password;
  final String? phone;
  final String? industry;

  /// Coglink requires `role`; the mobile app registers organizations only.
  Json toJson() => compact({
        'role': 'organization',
        'organizationName': organizationName,
        'industry': industry,
        'name': name,
        'email': email.trim().toLowerCase(),
        'password': password,
        'phone': phone,
      });
}

class AuthRepository {
  AuthRepository(this._api, this._store);

  final ApiClient _api;
  final TokenStore _store;

  static const _nativeHeaders = {'x-bizzvot-client': 'mobile'};

  Future<AuthUser> loginOwner(String email, String password) =>
      _login(Endpoints.login, email, password);

  Future<AuthUser> loginStaff(String email, String password) =>
      _login(Endpoints.staffLogin, email, password);

  Future<AuthUser> register(RegisterRequest req) async {
    final data = await _api.post<Object?>(
      Endpoints.register,
      body: req.toJson(),
      parse: (d) => d,
      anonymous: true,
      noRefresh: true,
      headers: _nativeHeaders,
    );
    return _establish(data);
  }

  Future<AuthUser> _login(String path, String email, String password) async {
    final data = await _api.post<Object?>(
      path,
      body: {'email': email.trim().toLowerCase(), 'password': password},
      parse: (d) => d,
      anonymous: true,
      noRefresh: true,
      headers: _nativeHeaders,
    );
    return _establish(data);
  }

  Future<AuthUser> _establish(Object? data) async {
    final tokens = parseTokens(data);
    if (tokens == null) {
      throw const AppException(
        AppErrorKind.server,
        'Sign-in is not available on mobile yet. Please try again later.',
        code: 'NATIVE_SESSION_UNSUPPORTED',
      );
    }
    await _store.write(tokens);
    final user = await me();
    if (user.role == UserRole.superAdmin) {
      await _store.clear();
      throw const AppException(
        AppErrorKind.forbidden,
        'Use the admin sign-in page',
        statusCode: 403,
      );
    }
    return user;
  }

  Future<AuthUser> me() =>
      _api.get(Endpoints.me, parse: AuthUser.fromJson);

  Future<bool> hasStoredSession() async => (await _store.read()) != null;

  /// Server-side revoke, then local wipe. Local wipe always happens.
  Future<void> logout() async {
    try {
      final tokens = await _store.read();
      if (tokens != null) {
        await _api.post<void>(
          Endpoints.logout,
          body: {
            if (tokens.refreshToken != null) 'refreshToken': tokens.refreshToken,
          },
          parse: (_) {},
          noRefresh: true,
        );
      }
    } catch (_) {
      // Best effort: a failed revoke must never keep the user signed in.
    } finally {
      await _store.clear();
    }
  }

  Future<void> forgotPassword(String email) => _api.post<void>(
        Endpoints.forgotPassword,
        body: {'email': email.trim().toLowerCase()},
        parse: (_) {},
        anonymous: true,
        noRefresh: true,
      );

  Future<void> resetPassword({
    required String token,
    required String password,
  }) =>
      _api.post<void>(
        Endpoints.resetPassword,
        body: {'token': token, 'newPassword': password},
        parse: (_) {},
        anonymous: true,
        noRefresh: true,
      );

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _api.post<void>(
        Endpoints.changePassword,
        body: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
        parse: (_) {},
      );
}

/// Refresh call used by [AuthInterceptor]. Uses a bare Dio so it does not
/// recurse through the auth interceptor.
RefreshFn buildRefresh(String baseUrl) {
  final bare = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json', ...AuthRepository._nativeHeaders},
    ),
  );
  return (current) async {
    final token = current.refreshToken;
    if (token == null) return null;
    final res = await bare.post<Object?>(
      Endpoints.refresh,
      data: {'refreshToken': token},
    );
    final tokens = parseTokens(ApiClient.unwrapEnvelope(res.data));
    if (tokens == null) return null;
    // Servers that do not rotate keep the old refresh credential.
    return SessionTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken ?? token,
    );
  };
}
