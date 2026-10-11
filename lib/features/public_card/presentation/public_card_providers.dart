import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/public_card_repository.dart';
import '../domain/public_card.dart';
import '../domain/public_directory.dart';
import '../domain/public_review.dart';

// Public providers deliberately do NOT watch `sessionKeyProvider`: the data
// is public and identical for signed-in and signed-out visitors.

/// Errors are surfaced immediately; the user retries explicitly.
Duration? _noRetry(int _, Object _) => null;

final publicCardProvider = FutureProvider.autoDispose.family<PublicCard, String>(
  (ref, slug) => ref.watch(publicCardRepositoryProvider).fetchCard(slug),
  retry: _noRetry,
);

/// Accumulated pages of a public list.
class PagedList<T> {
  const PagedList({
    this.items = const [],
    this.page = 1,
    this.hasMore = false,
    this.total,
    this.loadingMore = false,
  });

  final List<T> items;
  final int page;
  final bool hasMore;
  final int? total;
  final bool loadingMore;

  PagedList<T> copyWith({
    List<T>? items,
    int? page,
    bool? hasMore,
    int? total,
    bool? loadingMore,
  }) =>
      PagedList(
        items: items ?? this.items,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        total: total ?? this.total,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

class PublicReviewsController extends AsyncNotifier<PagedList<PublicReview>> {
  PublicReviewsController(this.slug);

  final String slug;

  @override
  Future<PagedList<PublicReview>> build() async {
    final page = await ref.watch(publicCardRepositoryProvider).fetchReviews(slug);
    return PagedList(
      items: page.items,
      page: page.page,
      hasMore: page.hasMore,
      total: page.total,
    );
  }

  /// Loads the next page. Throws on failure (the caller shows the error).
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await ref
          .read(publicCardRepositoryProvider)
          .fetchReviews(slug, page: current.page + 1);
      if (!ref.mounted) return;
      final seen = current.items.map((r) => r.id).toSet();
      state = AsyncData(
        current.copyWith(
          items: [
            ...current.items,
            ...next.items.where((r) => r.id.isEmpty || !seen.contains(r.id)),
          ],
          page: next.page <= current.page ? current.page + 1 : next.page,
          hasMore: next.hasMore,
          total: next.total,
          loadingMore: false,
        ),
      );
    } catch (_) {
      if (ref.mounted) state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }
}

final publicReviewsProvider = AsyncNotifierProvider.autoDispose
    .family<PublicReviewsController, PagedList<PublicReview>, String>(
  PublicReviewsController.new,
  retry: _noRetry,
);

class PublicDirectoryState {
  const PublicDirectoryState({this.organizationName, this.organizationLogo, required this.list});

  final String? organizationName;
  final String? organizationLogo;
  final PagedList<DirectoryEntry> list;
}

class PublicDirectoryController extends AsyncNotifier<PublicDirectoryState> {
  PublicDirectoryController(this.orgSlug);

  final String orgSlug;

  @override
  Future<PublicDirectoryState> build() async {
    final page = await ref.watch(publicCardRepositoryProvider).fetchDirectory(orgSlug);
    return PublicDirectoryState(
      organizationName: page.organizationName,
      organizationLogo: page.organizationLogo,
      list: PagedList(items: page.entries, page: page.page, hasMore: page.hasMore),
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.list.loadingMore || !current.list.hasMore) return;
    PublicDirectoryState withList(PagedList<DirectoryEntry> l) => PublicDirectoryState(
          organizationName: current.organizationName,
          organizationLogo: current.organizationLogo,
          list: l,
        );
    state = AsyncData(withList(current.list.copyWith(loadingMore: true)));
    try {
      final next = await ref
          .read(publicCardRepositoryProvider)
          .fetchDirectory(orgSlug, page: current.list.page + 1);
      if (!ref.mounted) return;
      final seen = current.list.items.map((e) => e.slug).toSet();
      state = AsyncData(
        withList(
          current.list.copyWith(
            items: [
              ...current.list.items,
              ...next.entries.where((e) => !seen.contains(e.slug)),
            ],
            page: next.page <= current.list.page ? current.list.page + 1 : next.page,
            hasMore: next.hasMore,
            loadingMore: false,
          ),
        ),
      );
    } catch (_) {
      if (ref.mounted) state = AsyncData(withList(current.list.copyWith(loadingMore: false)));
      rethrow;
    }
  }
}

final publicDirectoryProvider = AsyncNotifierProvider.autoDispose
    .family<PublicDirectoryController, PublicDirectoryState, String>(
  PublicDirectoryController.new,
  retry: _noRetry,
);
