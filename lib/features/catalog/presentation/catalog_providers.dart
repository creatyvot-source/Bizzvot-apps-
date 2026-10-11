import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../shared/models/paged.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog_models.dart';
import 'common/paged_list.dart';

/// Catalogue data is account-scoped (eligibility, org pricing), so every
/// provider watches the session key.
final catalogCategoriesProvider =
    FutureProvider.autoDispose<List<CatalogCategory>>((ref) {
  ref.watch(sessionKeyProvider);
  return ref.watch(catalogRepositoryProvider).categories();
});

class CatalogListController extends PagedNotifier<CatalogItem> {
  CatalogListController(this.query);

  final CatalogQuery query;

  @override
  Future<Paged<CatalogItem>> fetchPage(int page) =>
      ref.read(catalogRepositoryProvider).items(query, page: page);
}

final catalogListProvider = AsyncNotifierProvider.autoDispose
    .family<CatalogListController, PagedList<CatalogItem>, CatalogQuery>(
  CatalogListController.new,
);

typedef CatalogItemKey = ({CatalogItemType type, String id});

final catalogItemProvider =
    FutureProvider.autoDispose.family<CatalogItem, CatalogItemKey>((ref, key) {
  ref.watch(sessionKeyProvider);
  return ref.watch(catalogRepositoryProvider).item(key.type, key.id);
});
