import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/providers.dart';
import '../../../core/utilities/json.dart';
import '../../../shared/models/paged.dart';
import '../../../shared/models/review.dart';

/// Which review endpoints to use: organization owner or staff member.
enum ReviewScope { owner, staff }

/// Review moderation for owners (`/organization/reviews`) and staff
/// (`/staff/reviews`). The backend enforces permissions.
class ReviewsRepository {
  ReviewsRepository(this._api);

  final ApiClient _api;

  static const pageSize = 20;

  /// `GET /organization/reviews` or `/staff/reviews`
  /// `?status=pending|approved|hidden&page=&limit=`.
  Future<Paged<Review>> fetch(
    ReviewScope scope, {
    ReviewStatus? status,
    int page = 1,
  }) => _api.get(
    scope == ReviewScope.owner ? Endpoints.orgReviews : Endpoints.staffReviews,
    query: {'status': status?.name, 'page': page, 'limit': pageSize},
    parse: (data) => Paged.parse(
      data,
      Review.fromJson,
      listKeys: const ['reviews', 'items', 'docs', 'results', 'data'],
    ),
  );

  /// `PATCH .../reviews/:id/status` `{status}`. Returns the updated review
  /// when the server echoes it, otherwise `null`.
  Future<Review?> setStatus(
    ReviewScope scope,
    String id,
    ReviewStatus status,
  ) => _api.patch(
    scope == ReviewScope.owner
        ? Endpoints.orgReviewStatus(id)
        : Endpoints.staffReviewStatus(id),
    body: {'status': status.name},
    parse: _reviewOrNull,
  );

  /// `POST .../reviews/:id/reply` `{text}`. Returns the stored reply when
  /// the server echoes it, otherwise `null`.
  Future<ReviewReply?> reply(ReviewScope scope, String id, String text) =>
      _api.post(
        scope == ReviewScope.owner
            ? Endpoints.orgReviewReply(id)
            : Endpoints.staffReviewReply(id),
        body: {'text': text.trim()},
        parse: (data) {
          final j = asJson(data);
          if (j['reply'] != null) return ReviewReply.fromJson(j['reply']);
          final review = asJson(j['review']);
          if (review['reply'] != null)
            return ReviewReply.fromJson(review['reply']);
          return null;
        },
      );

  static Review? _reviewOrNull(Object? data) {
    final j = asJson(data);
    final raw = j['review'] is Map ? asJson(j['review']) : j;
    if (idOf(raw).isEmpty || raw['status'] == null) return null;
    return Review.fromJson(raw);
  }
}

final reviewsRepositoryProvider = Provider<ReviewsRepository>(
  (ref) => ReviewsRepository(ref.watch(apiClientProvider)),
);
