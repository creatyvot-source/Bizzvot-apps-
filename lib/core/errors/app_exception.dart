import 'package:dio/dio.dart';

/// Categorised failure the UI can react to without parsing free-form text.
enum AppErrorKind {
  /// 400/422 — invalid input; [AppException.fieldErrors] may be populated.
  validation,

  /// 401 after a failed refresh — the session is gone.
  unauthenticated,

  /// 403 — role, plan or publication restriction.
  forbidden,

  /// 404 — missing or removed resource.
  notFound,

  /// 409 — duplicate review, conflicting state, already-processed order.
  conflict,

  /// 410 — retired feature (e.g. contact exchange).
  gone,

  /// 429 — rate limited; see [AppException.retryAfter].
  rateLimited,

  /// 5xx.
  server,

  /// No connectivity, DNS, TLS or timeout.
  network,

  /// Request was cancelled by the app.
  cancelled,

  unknown,
}

class AppException implements Exception {
  const AppException(
    this.kind,
    this.message, {
    this.statusCode,
    this.code,
    this.retryAfter,
    this.fieldErrors = const {},
  });

  final AppErrorKind kind;

  /// Safe, user-presentable message.
  final String message;
  final int? statusCode;

  /// Stable machine-readable error code from the API envelope, if any.
  final String? code;
  final Duration? retryAfter;
  final Map<String, String> fieldErrors;

  /// Maps any thrown object to an [AppException]. Never leaks raw server
  /// bodies or stack traces into [message].
  factory AppException.from(Object error) {
    if (error is AppException) return error;
    if (error is DioException) return _fromDio(error);
    return const AppException(
      AppErrorKind.unknown,
      'Something went wrong. Please try again.',
    );
  }

  static AppException _fromDio(DioException e) {
    // Errors raised by our own interceptors are carried in `error`.
    if (e.error is AppException) return e.error! as AppException;

    switch (e.type) {
      case DioExceptionType.cancel:
        return const AppException(AppErrorKind.cancelled, 'Request cancelled.');
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return const AppException(
          AppErrorKind.network,
          'You appear to be offline. Check your connection and try again.',
        );
      case DioExceptionType.badCertificate:
        return const AppException(
          AppErrorKind.network,
          'A secure connection could not be established.',
        );
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        break;
    }

    final response = e.response;
    final status = response?.statusCode;
    if (response == null || status == null) {
      return const AppException(
        AppErrorKind.network,
        'You appear to be offline. Check your connection and try again.',
      );
    }

    final parsed = _parseErrorBody(response.data);
    final retryAfter = _parseRetryAfter(response.headers.value('retry-after'));

    final (kind, fallback) = switch (status) {
      400 || 422 => (AppErrorKind.validation, 'Please check the details and try again.'),
      401 => (AppErrorKind.unauthenticated, 'Your session has ended. Please sign in again.'),
      403 => (AppErrorKind.forbidden, 'You do not have access to this.'),
      404 => (AppErrorKind.notFound, 'This item could not be found.'),
      409 => (AppErrorKind.conflict, 'This action conflicts with the current state.'),
      410 => (AppErrorKind.gone, 'This feature is no longer available.'),
      429 => (AppErrorKind.rateLimited, 'Too many attempts. Please wait and try again.'),
      >= 500 => (AppErrorKind.server, 'The server had a problem. Please try again shortly.'),
      _ => (AppErrorKind.unknown, 'Something went wrong. Please try again.'),
    };

    // Server messages are only shown for client errors (4xx) where they are
    // written for end users; 5xx messages may contain internals.
    final message = (status < 500 && parsed.message != null)
        ? parsed.message!
        : fallback;

    return AppException(
      kind,
      message,
      statusCode: status,
      code: parsed.code,
      retryAfter: retryAfter,
      fieldErrors: parsed.fields,
    );
  }

  static ({String? message, String? code, Map<String, String> fields})
      _parseErrorBody(Object? data) {
    String? message;
    String? code;
    final fields = <String, String>{};
    if (data is Map) {
      final error = data['error'];
      if (error is Map) {
        message = _str(error['message']);
        code = _str(error['code']);
        final details = error['fields'] ?? error['details'];
        if (details is Map) {
          details.forEach((k, v) {
            final s = _str(v);
            if (s != null) fields['$k'] = s;
          });
        }
      } else if (error is String) {
        message = error;
      }
      message ??= _str(data['message']);
    }
    if (message != null && message.length > 300) {
      message = message.substring(0, 300);
    }
    return (message: message, code: code, fields: fields);
  }

  static String? _str(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;

  static Duration? _parseRetryAfter(String? header) {
    if (header == null) return null;
    final seconds = int.tryParse(header.trim());
    if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
    try {
      final date = HttpDateParser.parse(header);
      final diff = date.difference(DateTime.now().toUtc());
      return diff.isNegative ? Duration.zero : diff;
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'AppException($kind, $statusCode, $code)';
}

/// Minimal RFC 7231 IMF-fixdate parser (e.g. `Wed, 21 Oct 2026 07:28:00 GMT`).
abstract final class HttpDateParser {
  static const _months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };

  static DateTime parse(String input) {
    final parts = input.trim().split(RegExp(r'\s+'));
    if (parts.length != 6) throw const FormatException('bad http-date');
    final day = int.parse(parts[1]);
    final month = _months[parts[2]] ?? (throw const FormatException('month'));
    final year = int.parse(parts[3]);
    final t = parts[4].split(':').map(int.parse).toList();
    if (t.length != 3) throw const FormatException('time');
    return DateTime.utc(year, month, day, t[0], t[1], t[2]);
  }
}
