import '../../core/utilities/json.dart';

/// Simple paginated wrapper. Accepts `{ items, total, page }`, `{ docs }`,
/// `{ reviews }` style payloads or a bare list.
class Paged<T> {
  const Paged({required this.items, this.total, this.page = 1, this.hasMore = false});

  final List<T> items;
  final int? total;
  final int page;
  final bool hasMore;

  static Paged<T> parse<T>(
    Object? data,
    T Function(Object? raw) item, {
    List<String> listKeys = const ['items', 'docs', 'results', 'data'],
  }) {
    if (data is List) return Paged(items: data.map(item).toList());
    final j = asJson(data);
    Object? list;
    for (final k in listKeys) {
      if (j[k] is List) {
        list = j[k];
        break;
      }
    }
    list ??= j.values.whereType<List>().firstOrNull;
    final items = (list as List?)?.map(item).toList() ?? <T>[];
    final total = intOrNull(j['total'] ?? j['totalDocs'] ?? j['count']);
    final page = intOr(j['page'], 1);
    final pages = intOrNull(j['pages'] ?? j['totalPages']);
    return Paged(
      items: items,
      total: total,
      page: page,
      hasMore: boolOrNull(j['hasMore'] ?? j['hasNextPage']) ??
          (pages != null ? page < pages : false),
    );
  }
}
