/// Defensive JSON readers. The API is consumed by several clients, so models
/// must tolerate missing or loosely typed fields instead of crashing.
typedef Json = Map<String, dynamic>;

Json asJson(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, value) => MapEntry('$k', value));
  return const {};
}

List<Json> asJsonList(Object? v) {
  if (v is List) return v.map(asJson).toList(growable: false);
  return const [];
}

String? str(Object? v) {
  if (v == null) return null;
  if (v is String) return v.isEmpty ? null : v;
  if (v is num || v is bool) return '$v';
  return null;
}

String strOr(Object? v, [String fallback = '']) => str(v) ?? fallback;

int? intOrNull(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt();
  return null;
}

int intOr(Object? v, [int fallback = 0]) => intOrNull(v) ?? fallback;

double? doubleOrNull(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

double doubleOr(Object? v, [double fallback = 0]) => doubleOrNull(v) ?? fallback;

bool? boolOrNull(Object? v) {
  if (v is bool) return v;
  if (v is String) {
    if (v == 'true') return true;
    if (v == 'false') return false;
  }
  if (v is num) return v != 0;
  return null;
}

bool boolOr(Object? v, [bool fallback = false]) => boolOrNull(v) ?? fallback;

DateTime? dateOrNull(Object? v) {
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v).toLocal();
  return null;
}

List<String> strList(Object? v) {
  if (v is List) return v.map(str).whereType<String>().toList(growable: false);
  return const [];
}

/// MongoDB documents may expose `_id` or `id`.
String idOf(Json j) => strOr(j['id'] ?? j['_id']);

/// Removes null values so PATCH bodies only carry intended changes.
Json compact(Json j) => Map.of(j)..removeWhere((_, v) => v == null);
