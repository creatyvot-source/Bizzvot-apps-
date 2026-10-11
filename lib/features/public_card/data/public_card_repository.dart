import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/providers.dart';
import '../../../shared/models/paged.dart';
import '../domain/public_card.dart';
import '../domain/public_directory.dart';
import '../domain/public_review.dart';

/// Click/tap categories sent to `POST /public/track-click`.
abstract final class TrackType {
  static const phone = 'phone';
  static const companyPhone = 'company_phone';
  static const whatsapp = 'whatsapp';
  static const email = 'email';
  static const website = 'website';
  static const map = 'map';
  static const social = 'social';
  static const custom = 'custom';
  static const vcard = 'vcard';
  static const share = 'share';
  static const googleReview = 'google_review';
  static const pdf = 'pdf';
  static const video = 'video';
}

/// Public (anonymous) endpoints. Every call is sent with `anonymous: true`
/// so no credentials are attached even when a user is signed in.
class PublicCardRepository {
  PublicCardRepository(this._api);

  final ApiClient _api;

  static const reviewsPageSize = 10;
  static const directoryPageSize = 30;

  /// `GET /public/card/:slug`
  Future<PublicCard> fetchCard(String slug) => _api.get(
    Endpoints.publicCard(slug),
    anonymous: true,
    parse: PublicCard.fromJson,
  );

  /// `GET /public/card/:slug/reviews?page=&limit=` — approved reviews only.
  Future<Paged<PublicReview>> fetchReviews(String slug, {int page = 1}) =>
      _api.get(
        Endpoints.publicCardReviews(slug),
        anonymous: true,
        query: {'page': page, 'limit': reviewsPageSize},
        parse: (data) {
          final raw = Paged.parse<Object?>(
            data,
            (r) => r,
            listKeys: const ['reviews', 'items', 'docs', 'results', 'data'],
          );
          return Paged(
            items: raw.items
                .where(PublicReview.isPublishable)
                .map(PublicReview.fromJson)
                .toList(growable: false),
            total: raw.total,
            page: raw.page,
            hasMore: raw.hasMore,
          );
        },
      );

  /// `POST /public/card/:slug/review` `{rating, name, comment}`.
  ///
  /// Throws [AppException] with `conflict` (409, already reviewed) or
  /// `rateLimited` (429, see `retryAfter`).
  Future<ReviewSubmissionResult> submitReview(
    String slug,
    ReviewSubmission review,
  ) => _api.post(
    Endpoints.publicCardReview(slug),
    anonymous: true,
    body: review.toJson(),
    parse: ReviewSubmissionResult.fromJson,
  );

  /// `POST /public/track-click` `{slug, type, target?}` (payload assumed).
  ///
  /// Fire-and-forget: never throws, so analytics can never block a visitor.
  Future<void> trackClick({
    required String slug,
    required String type,
    String? target,
  }) async {
    try {
      await _api.post<void>(
        Endpoints.trackClick,
        anonymous: true,
        body: {
          'slug': slug,
          'type': type,
          if (target != null && target.isNotEmpty) 'target': target,
        },
        parse: (_) {},
      );
    } catch (_) {
      // Intentionally swallowed: tracking failures are not user-facing.
    }
  }

  /// `GET /cards/:id/vcard` raw bytes.
  Future<Uint8List> fetchVcard(String cardId) =>
      _api.getBytes(Endpoints.cardVcard(cardId), anonymous: true);

  /// PROPOSED `GET /public/organizations/:slug/directory?page=&limit=`.
  Future<PublicDirectoryPage> fetchDirectory(String orgSlug, {int page = 1}) =>
      _api.get(
        Endpoints.publicDirectory(orgSlug),
        anonymous: true,
        query: {'page': page, 'limit': directoryPageSize},
        parse: PublicDirectoryPage.fromJson,
      );
}

final publicCardRepositoryProvider = Provider<PublicCardRepository>(
  (ref) => PublicCardRepository(ref.watch(apiClientProvider)),
);
