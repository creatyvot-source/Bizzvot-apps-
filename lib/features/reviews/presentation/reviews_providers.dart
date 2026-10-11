import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../shared/models/review.dart';
import '../data/reviews_repository.dart';

Duration? _noRetry(int _, Object _) => null;

enum ReviewFilter {
  all('All', null),
  pending('Pending', ReviewStatus.pending),
  approved('Approved', ReviewStatus.approved),
  hidden('Hidden', ReviewStatus.hidden);

  const ReviewFilter(this.label, this.status);
  final String label;
  final ReviewStatus? status;

  bool matches(Review r) => status == null || r.status == status;
}

extension ReviewCopy on Review {
  Review copyWith({ReviewStatus? status, ReviewReply? reply, bool clearReply = false}) => Review(
        id: id,
        rating: rating,
        status: status ?? this.status,
        cardId: cardId,
        cardTitle: cardTitle,
        reviewerName: reviewerName,
        comment: comment,
        reply: clearReply ? null : (reply ?? this.reply),
        createdAt: createdAt,
      );
}

class ReviewFilterController extends Notifier<ReviewFilter> {
  ReviewFilterController(this.scope);

  final ReviewScope scope;

  @override
  ReviewFilter build() => ReviewFilter.all;

  void select(ReviewFilter f) => state = f;
}

/// Selected filter chip, per scope.
final reviewFilterProvider =
    NotifierProvider.autoDispose.family<ReviewFilterController, ReviewFilter, ReviewScope>(
  ReviewFilterController.new,
);

class ReviewsState {
  const ReviewsState({
    required this.filter,
    this.items = const [],
    this.page = 1,
    this.hasMore = false,
    this.loadingMore = false,
    this.busyIds = const {},
  });

  /// Filter the items were fetched with.
  final ReviewFilter filter;
  final List<Review> items;
  final int page;
  final bool hasMore;
  final bool loadingMore;

  /// Reviews with an in-flight status/reply request.
  final Set<String> busyIds;

  /// Items matching [f] — the server filters too; this is defensive and
  /// makes optimistic status changes move items out of a filtered view.
  List<Review> visible(ReviewFilter f) => items.where(f.matches).toList(growable: false);

  ReviewsState copyWith({
    List<Review>? items,
    int? page,
    bool? hasMore,
    bool? loadingMore,
    Set<String>? busyIds,
  }) =>
      ReviewsState(
        filter: filter,
        items: items ?? this.items,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
        busyIds: busyIds ?? this.busyIds,
      );
}

class ReviewsController extends AsyncNotifier<ReviewsState> {
  ReviewsController(this.scope);

  final ReviewScope scope;

  ReviewsRepository get _repo => ref.read(reviewsRepositoryProvider);

  @override
  Future<ReviewsState> build() async {
    // Private, account-scoped data: reset on logout / account switch.
    ref.watch(sessionKeyProvider);
    final filter = ref.watch(reviewFilterProvider(scope));
    final page = await ref
        .watch(reviewsRepositoryProvider)
        .fetch(scope, status: filter.status);
    return ReviewsState(
      filter: filter,
      items: page.items,
      page: page.page,
      hasMore: page.hasMore,
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await _repo.fetch(
        scope,
        status: current.filter.status,
        page: current.page + 1,
      );
      if (!ref.mounted) return;
      final latest = state.value ?? current;
      final seen = latest.items.map((r) => r.id).toSet();
      state = AsyncData(
        latest.copyWith(
          items: [...latest.items, ...next.items.where((r) => !seen.contains(r.id))],
          page: next.page <= current.page ? current.page + 1 : next.page,
          hasMore: next.hasMore,
          loadingMore: false,
        ),
      );
    } catch (_) {
      if (ref.mounted) {
        state = AsyncData((state.value ?? current).copyWith(loadingMore: false));
      }
      rethrow;
    }
  }

  /// Optimistically changes the status; rolls back and rethrows on failure.
  Future<void> setStatus(String id, ReviewStatus status) => _mutate(
        id,
        (r) => r.copyWith(status: status),
        () async {
          final server = await _repo.setStatus(scope, id, status);
          return (Review r) => server ?? r;
        },
      );

  /// Optimistically sets the reply; rolls back and rethrows on failure.
  Future<void> reply(String id, String text) => _mutate(
        id,
        (r) => r.copyWith(reply: ReviewReply(text: text.trim(), createdAt: DateTime.now())),
        () async {
          final server = await _repo.reply(scope, id, text);
          return (Review r) => server == null ? r : r.copyWith(reply: server);
        },
      );

  Future<void> _mutate(
    String id,
    Review Function(Review) optimistic,
    Future<Review Function(Review)> Function() request,
  ) async {
    final current = state.value;
    if (current == null || current.busyIds.contains(id)) return;
    final index = current.items.indexWhere((r) => r.id == id);
    if (index < 0) return;
    final original = current.items[index];

    _replace(id, optimistic(original), busy: true);
    try {
      final finalize = await request();
      if (!ref.mounted) return;
      final now = _find(id);
      if (now != null) _replace(id, finalize(now), busy: false);
    } catch (_) {
      if (ref.mounted) _replace(id, original, busy: false);
      rethrow;
    }
  }

  Review? _find(String id) {
    for (final r in state.value?.items ?? const <Review>[]) {
      if (r.id == id) return r;
    }
    return null;
  }

  void _replace(String id, Review review, {required bool busy}) {
    final s = state.value;
    if (s == null) return;
    final busyIds = {...s.busyIds};
    busy ? busyIds.add(id) : busyIds.remove(id);
    state = AsyncData(
      s.copyWith(
        items: [for (final r in s.items) r.id == id ? review : r],
        busyIds: busyIds,
      ),
    );
  }
}

final reviewsControllerProvider =
    AsyncNotifierProvider.autoDispose.family<ReviewsController, ReviewsState, ReviewScope>(
  ReviewsController.new,
  retry: _noRetry,
);
