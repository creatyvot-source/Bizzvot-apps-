import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../data/analytics_repository.dart';
import '../domain/analytics_models.dart';

Duration? _noRetry(int _, Object _) => null;

typedef AnalyticsQuery = ({String cardId, AnalyticsRange range});

class AnalyticsRangeController extends Notifier<AnalyticsRange> {
  @override
  AnalyticsRange build() => AnalyticsRange.month;

  void select(AnalyticsRange r) => state = r;
}

final analyticsRangeProvider =
    NotifierProvider.autoDispose<AnalyticsRangeController, AnalyticsRange>(
      AnalyticsRangeController.new,
    );

// Each section loads independently so one failing endpoint does not hide the
// others. All are account-scoped and reset on logout.

final viewsStatsProvider = FutureProvider.autoDispose
    .family<ViewsStats, AnalyticsQuery>((ref, q) {
      ref.watch(sessionKeyProvider);
      return ref
          .watch(analyticsRepositoryProvider)
          .fetchViews(q.cardId, q.range);
    }, retry: _noRetry);

final reviewStatsProvider = FutureProvider.autoDispose
    .family<ReviewStats, AnalyticsQuery>((ref, q) {
      ref.watch(sessionKeyProvider);
      return ref
          .watch(analyticsRepositoryProvider)
          .fetchReviews(q.cardId, q.range);
    }, retry: _noRetry);

final linkClicksProvider = FutureProvider.autoDispose
    .family<LinkClicks, AnalyticsQuery>((ref, q) {
      ref.watch(sessionKeyProvider);
      return ref
          .watch(analyticsRepositoryProvider)
          .fetchLinks(q.cardId, q.range);
    }, retry: _noRetry);
