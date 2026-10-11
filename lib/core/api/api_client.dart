import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../errors/app_exception.dart';
import '../secure_storage/token_store.dart';
import '../utilities/json.dart';
import 'endpoints.dart';

/// Request `extra` flags understood by [AuthInterceptor].
abstract final class ApiFlags {
  /// Do not attach credentials (public endpoints).
  static const anonymous = 'bv.anonymous';

  /// Do not attempt a refresh on 401 (login, refresh, logout).
  static const noRefresh = 'bv.noRefresh';

  static const _retried = 'bv.retried';
}

/// Parses the `data` value of a success envelope into a typed result.
typedef Parser<T> = T Function(Object? data);

/// Thin, typed wrapper over Dio. Every call:
/// * unwraps the `{ success, data }` envelope,
/// * converts failures to [AppException],
/// * never logs bodies or headers (tokens and personal data).
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Dio get dio => _dio;

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    required Parser<T> parse,
    bool anonymous = false,
    CancelToken? cancelToken,
  }) =>
      _send(
        () => _dio.get<Object?>(
          path,
          queryParameters: query == null ? null : compact(query),
          options: _opts(anonymous: anonymous),
          cancelToken: cancelToken,
        ),
        parse,
      );

  Future<T> post<T>(
    String path, {
    Object? body,
    required Parser<T> parse,
    bool anonymous = false,
    bool noRefresh = false,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) =>
      _send(
        () => _dio.post<Object?>(
          path,
          data: body,
          options: _opts(
            anonymous: anonymous,
            noRefresh: noRefresh,
            headers: headers,
          ),
          cancelToken: cancelToken,
        ),
        parse,
      );

  Future<T> patch<T>(
    String path, {
    Object? body,
    required Parser<T> parse,
    CancelToken? cancelToken,
  }) =>
      _send(
        () => _dio.patch<Object?>(
          path,
          data: body,
          options: _opts(),
          cancelToken: cancelToken,
        ),
        parse,
      );

  Future<T> delete<T>(
    String path, {
    Object? body,
    required Parser<T> parse,
    CancelToken? cancelToken,
  }) =>
      _send(
        () => _dio.delete<Object?>(
          path,
          data: body,
          options: _opts(),
          cancelToken: cancelToken,
        ),
        parse,
      );

  /// Raw bytes (QR PNG, vCard file, invoice PDF). Not envelope-wrapped.
  Future<Uint8List> getBytes(
    String path, {
    bool anonymous = false,
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await _dio.get<List<int>>(
        path,
        options: _opts(anonymous: anonymous).copyWith(
          responseType: ResponseType.bytes,
        ),
        cancelToken: cancelToken,
      );
      return Uint8List.fromList(res.data ?? const []);
    } catch (e) {
      throw AppException.from(e);
    }
  }

  /// Multipart upload with progress (0.0–1.0).
  Future<T> upload<T>(
    String path, {
    required FormData form,
    required Parser<T> parse,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) =>
      _send(
        () => _dio.post<Object?>(
          path,
          data: form,
          options: _opts(),
          cancelToken: cancelToken,
          onSendProgress: onProgress == null
              ? null
              : (sent, total) {
                  if (total > 0) onProgress(sent / total);
                },
        ),
        parse,
      );

  Options _opts({
    bool anonymous = false,
    bool noRefresh = false,
    Map<String, String>? headers,
  }) =>
      Options(
        headers: headers,
        extra: {
          if (anonymous) ApiFlags.anonymous: true,
          if (noRefresh) ApiFlags.noRefresh: true,
        },
      );

  Future<T> _send<T>(
    Future<Response<Object?>> Function() request,
    Parser<T> parse,
  ) async {
    try {
      final res = await request();
      return parse(unwrapEnvelope(res.data));
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException.from(e);
    }
  }

  /// Returns `data` from `{ success: true, data }`. Bodies without an
  /// envelope (204, legacy routes) are returned as-is.
  static Object? unwrapEnvelope(Object? body) {
    if (body is Map && body.containsKey('success')) {
      if (body['success'] == true) return body['data'];
      final err = body['error'];
      final msg = err is Map ? str(err['message']) : str(err);
      throw AppException(
        AppErrorKind.unknown,
        msg ?? 'Something went wrong. Please try again.',
        code: err is Map ? str(err['code']) : null,
      );
    }
    return body;
  }
}

/// Signature for the refresh call used by [AuthInterceptor].
typedef RefreshFn = Future<SessionTokens?> Function(SessionTokens current);

/// Attaches the bearer token and performs **one coordinated** refresh on 401.
///
/// Concurrent 401s share a single in-flight refresh; each original request
/// is retried at most once. When refresh fails the store is cleared and
/// [onSessionExpired] fires exactly once per failure.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.store,
    required this.dio,
    required this.refresh,
    required this.onSessionExpired,
  });

  final TokenStore store;
  final Dio dio;
  final RefreshFn refresh;
  final VoidCallback onSessionExpired;

  Future<SessionTokens?>? _inFlight;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[ApiFlags.anonymous] != true) {
      final tokens = await store.read();
      if (tokens != null) {
        options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
        options.headers['x-bizzvot-session'] = 'org';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final opts = err.requestOptions;
    final eligible = err.response?.statusCode == 401 &&
        opts.extra[ApiFlags.anonymous] != true &&
        opts.extra[ApiFlags.noRefresh] != true &&
        opts.extra[ApiFlags._retried] != true &&
        opts.path != Endpoints.refresh;
    if (!eligible) return handler.next(err);

    final current = await store.read();
    if (current == null || current.refreshToken == null) {
      await _expire();
      return handler.next(err);
    }

    final fresh = await _refreshOnce(current);
    if (fresh == null) {
      return handler.reject(
        DioException(
          requestOptions: opts,
          response: err.response,
          type: DioExceptionType.badResponse,
          error: const AppException(
            AppErrorKind.unauthenticated,
            'Your session has ended. Please sign in again.',
            statusCode: 401,
          ),
        ),
      );
    }

    try {
      opts.extra[ApiFlags._retried] = true;
      opts.headers['Authorization'] = 'Bearer ${fresh.accessToken}';
      final retry = await dio.fetch<Object?>(opts);
      handler.resolve(retry);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<SessionTokens?> _refreshOnce(SessionTokens current) {
    return _inFlight ??= () async {
      try {
        final fresh = await refresh(current);
        if (fresh == null) {
          await _expire();
          return null;
        }
        await store.write(fresh);
        return fresh;
      } catch (_) {
        await _expire();
        return null;
      } finally {
        // Allow a future refresh once this one has settled.
        scheduleMicrotask(() => _inFlight = null);
      }
    }();
  }

  Future<void> _expire() async {
    await store.clear();
    onSessionExpired();
  }
}

/// Builds the configured Dio instance. Logging is debug-only and redacted.
Dio buildDio(String baseUrl) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
      headers: {'Accept': 'application/json'},
      contentType: Headers.jsonContentType,
    ),
  );
  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        request: false,
        requestHeader: false,
        requestBody: false,
        responseHeader: false,
        responseBody: false,
        logPrint: (o) => debugPrint('[api] $o'),
      ),
    );
  }
  return dio;
}
