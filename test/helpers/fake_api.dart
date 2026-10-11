import 'dart:convert';
import 'dart:typed_data';

import 'package:bizzvot/core/api/api_client.dart';
import 'package:dio/dio.dart';

/// A recorded request made through [FakeApi].
class RecordedRequest {
  RecordedRequest(this.method, this.path, this.query, this.body);
  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Object? body;
}

/// Canned response for [FakeApi.on].
class FakeResponse {
  const FakeResponse(this.status, this.body, {this.headers = const {}});

  /// `{ success: true, data: <data> }`
  factory FakeResponse.ok(Object? data) =>
      FakeResponse(200, {'success': true, 'data': data});

  factory FakeResponse.error(int status, String message, {String? code, Map<String, List<String>> headers = const {}}) =>
      FakeResponse(
        status,
        {
          'success': false,
          'error': {
            'message': message,
            // ignore: use_null_aware_elements
            if (code != null) 'code': code,
          },
        },
        headers: headers,
      );

  final int status;
  final Object? body;
  final Map<String, List<String>> headers;
}

/// In-memory HTTP layer for repository tests:
/// ```dart
/// final fake = FakeApi()..on('GET', '/organization/cards', FakeResponse.ok([...]));
/// final repo = CardsRepository(fake.client);
/// ```
class FakeApi implements HttpClientAdapter {
  FakeApi() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'))
      ..httpClientAdapter = this;
    client = ApiClient(dio);
  }

  late final Dio dio;
  late final ApiClient client;
  final requests = <RecordedRequest>[];
  final _routes = <String, FakeResponse Function(RecordedRequest)>{};

  void on(String method, String path, FakeResponse response) =>
      _routes['$method $path'] = (_) => response;

  void onDynamic(String method, String path, FakeResponse Function(RecordedRequest) handler) =>
      _routes['$method $path'] = handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object? body = options.data;
    if (body is String && body.isNotEmpty) {
      try {
        body = jsonDecode(body);
      } catch (_) {}
    }
    final req = RecordedRequest(options.method, options.path, options.queryParameters, body);
    requests.add(req);
    final handler = _routes['${options.method} ${options.path}'];
    final res = handler?.call(req) ??
        FakeResponse.error(404, 'No fake route for ${options.method} ${options.path}');
    return ResponseBody.fromString(
      jsonEncode(res.body),
      res.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...res.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
