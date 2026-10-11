import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../shared/models/paged.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../../shared/widgets/ui_kit.dart';

/// Accumulated pages of a server list.
class PagedList<T> {
  const PagedList({
    required this.items,
    required this.page,
    required this.hasMore,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<T> items;
  final int page;
  final bool hasMore;
  final bool loadingMore;
  final Object? loadMoreError;

  PagedList<T> copyWith({
    List<T>? items,
    bool? loadingMore,
    Object? loadMoreError,
    bool clearError = false,
  }) => PagedList(
    items: items ?? this.items,
    page: page,
    hasMore: hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
  );
}

/// Base notifier for paginated, session-scoped lists.
abstract class PagedNotifier<T> extends AsyncNotifier<PagedList<T>> {
  /// Fetches one page (1-based).
  Future<Paged<T>> fetchPage(int page);

  @override
  Future<PagedList<T>> build() async {
    ref.watch(sessionKeyProvider);
    final p = await fetchPage(1);
    return PagedList(
      items: p.items,
      page: 1,
      hasMore: p.hasMore && p.items.isNotEmpty,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> loadMore() async {
    final cur = state.value;
    if (cur == null || !cur.hasMore || cur.loadingMore || state.isLoading)
      return;
    state = AsyncData(cur.copyWith(loadingMore: true, clearError: true));
    try {
      final next = await fetchPage(cur.page + 1);
      if (!ref.mounted) return;
      state = AsyncData(
        PagedList(
          items: [...cur.items, ...next.items],
          page: cur.page + 1,
          hasMore: next.hasMore && next.items.isNotEmpty,
        ),
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = AsyncData(cur.copyWith(loadingMore: false, loadMoreError: e));
    }
  }

  /// Replaces one item in place (e.g. after marking a notification read).
  void replaceWhere(bool Function(T) test, T Function(T) update) {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncData(
      cur.copyWith(items: [for (final i in cur.items) test(i) ? update(i) : i]),
    );
  }
}

/// Pull-to-refresh list with shared loading/empty/error states and
/// automatic "load more" when the end is reached.
class PagedListView<T> extends StatelessWidget {
  const PagedListView({
    super.key,
    required this.value,
    required this.itemBuilder,
    required this.onRefresh,
    required this.onLoadMore,
    required this.empty,
    this.header,
    this.separated = true,
    this.columns = 1,
    this.padding = EdgeInsets.zero,
  });

  final AsyncValue<PagedList<T>> value;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final Widget empty;
  final Widget? header;
  final bool separated;

  /// >1 lays items out in rows of equal-height cards (grid look that still
  /// grows with text size).
  final int columns;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: value.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => header == null
            ? const SkeletonList()
            : _Scrollable(header: header, child: const LoadingView()),
        error: (e, _) => _Scrollable(
          header: header,
          child: ErrorView(error: e, onRetry: onRefresh),
        ),
        data: (page) {
          if (page.items.isEmpty)
            return _Scrollable(header: header, child: empty);
          final hasHeader = header != null;
          final cols = columns < 1 ? 1 : columns;
          final rows = (page.items.length + cols - 1) ~/ cols;
          final count = rows + (hasHeader ? 1 : 0) + (page.hasMore ? 1 : 0);
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            itemCount: count,
            itemBuilder: (context, index) {
              if (hasHeader && index == 0) return header!;
              final r = index - (hasHeader ? 1 : 0);
              if (r >= rows) {
                return _LoadMoreFooter(page: page, onLoadMore: onLoadMore);
              }
              if (cols > 1) {
                final start = r * cols;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var c = 0; c < cols; c++) ...[
                          if (c > 0) const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: start + c < page.items.length
                                ? itemBuilder(context, page.items[start + c])
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }
              final child = itemBuilder(context, page.items[r]);
              return separated && r > 0
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [const Divider(height: 1), child],
                    )
                  : child;
            },
          );
        },
      ),
    );
  }
}

class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child, this.header});
  final Widget child;
  final Widget? header;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        ?header,
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight * 0.6),
          child: Center(child: child),
        ),
      ],
    ),
  );
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.page, required this.onLoadMore});
  final PagedList<Object?> page;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (page.loadMoreError != null) {
      return Padding(
        padding: AppSpacing.page,
        child: Center(
          child: OutlinedButton.icon(
            onPressed: onLoadMore,
            icon: const Icon(Icons.refresh),
            label: const Text('Couldn’t load more. Try again'),
          ),
        ),
      );
    }
    if (!page.loadingMore) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onLoadMore());
    }
    return Padding(
      padding: AppSpacing.page,
      child: Center(
        child: Semantics(
          label: 'Loading more',
          child: const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}
