import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/providers.dart';
import '../domain/analytics_models.dart';

/// Card analytics. Owners may query any card in their organization; staff
/// only their assigned card (enforced by the backend).
class AnalyticsRepository {
  AnalyticsRepository(this._api, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ApiClient _api;
  final DateTime Function() _clock;

  /// `GET /analytics/card/:id/views?range=&from=&to=`
  Future<ViewsStats> fetchViews(String cardId, AnalyticsRange range) =>
      _api.get(
        Endpoints.analyticsViews(cardId),
        query: range.toQuery(_clock()),
        parse: ViewsStats.fromJson,
      );

  /// `GET /analytics/card/:id/reviews?range=&from=&to=`
  Future<ReviewStats> fetchReviews(String cardId, AnalyticsRange range) =>
      _api.get(
        Endpoints.analyticsReviews(cardId),
        query: range.toQuery(_clock()),
        parse: ReviewStats.fromJson,
      );

  /// `GET /analytics/card/:id/links?range=&from=&to=`
  Future<LinkClicks> fetchLinks(String cardId, AnalyticsRange range) =>
      _api.get(
        Endpoints.analyticsLinks(cardId),
        query: range.toQuery(_clock()),
        parse: LinkClicks.fromJson,
      );
}

final analyticsRepositoryProvider = Provider<AnalyticsRepository>(
  (ref) => AnalyticsRepository(ref.watch(apiClientProvider)),
);
