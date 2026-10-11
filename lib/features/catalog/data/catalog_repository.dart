import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/providers.dart';
import '../../../core/utilities/json.dart';
import '../../../shared/models/paged.dart';
import '../domain/catalog_models.dart';

/// Filter for catalogue listings. Records compare by value, so this is a
/// stable provider family key.
typedef CatalogQuery = ({
  CatalogItemType type,
  String? category,
  String? search,
});

/// PROPOSED commerce catalogue endpoints (plan §12.5).
class CatalogRepository {
  CatalogRepository(this._api);

  final ApiClient _api;

  static const pageSize = 20;

  Future<List<CatalogCategory>> categories() => _api.get(
    Endpoints.catalogCategories,
    parse: (d) => Paged.parse(
      d,
      CatalogCategory.fromJson,
      listKeys: const ['categories', 'items', 'data'],
    ).items.where((c) => c.id.isNotEmpty).toList(growable: false),
  );

  /// `GET /catalog/services|products` with `category`, `q`, `page`, `limit`.
  Future<Paged<CatalogItem>> items(CatalogQuery q, {int page = 1}) {
    final path = switch (q.type) {
      CatalogItemType.product => Endpoints.catalogProducts,
      CatalogItemType.plan => Endpoints.catalogPlans,
      _ => Endpoints.catalogServices,
    };
    return _api.get(
      path,
      query: {
        'category': q.category,
        'q': (q.search?.trim().isEmpty ?? true) ? null : q.search!.trim(),
        'page': page,
        'limit': pageSize,
      },
      parse: (d) => q.type == CatalogItemType.plan
          ? _plansAsItems(d)
          : Paged.parse(
              d,
              (raw) => CatalogItem.fromJson(raw, type: q.type),
              listKeys: const [
                'items',
                'services',
                'products',
                'docs',
                'results',
                'data',
              ],
            ),
    );
  }

  /// `GET /catalog/plans`.
  Future<List<Plan>> plans() => _api.get(
    Endpoints.catalogPlans,
    parse: (d) => Paged.parse(
      d,
      Plan.fromJson,
      listKeys: const ['plans', 'items', 'data'],
    ).items.where((p) => p.id.isNotEmpty).toList(growable: false),
  );

  /// `GET /catalog/:type/:id`.
  Future<CatalogItem> item(CatalogItemType type, String id) => _api.get(
    Endpoints.catalogItem(type.wire, id),
    parse: (d) {
      if (type == CatalogItemType.plan) {
        final j = asJson(d);
        final plan = Plan.fromJson(j['plan'] is Map ? j['plan'] : j);
        final base = CatalogItem.fromJson(
          j['plan'] is Map ? j['plan'] : j,
          type: CatalogItemType.plan,
        );
        return base.price == null && plan.price != null
            ? CatalogItem.fromPlan(plan)
            : base;
      }
      return CatalogItem.fromJson(d, type: type);
    },
  );

  static Paged<CatalogItem> _plansAsItems(Object? d) {
    final paged = Paged.parse(
      d,
      Plan.fromJson,
      listKeys: const ['plans', 'items', 'data'],
    );
    return Paged(
      items: paged.items
          .where((p) => p.id.isNotEmpty)
          .map(CatalogItem.fromPlan)
          .toList(growable: false),
      total: paged.total,
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(apiClientProvider)),
);
