import '../../../core/utilities/json.dart';
import '../../../shared/models/review.dart';

/// Approved review as shown to public visitors. Separate DTO by
/// construction: it has no reviewer email, IP, status or card internals.
class PublicReview {
  const PublicReview({
    required this.id,
    required this.reviewerName,
    required this.rating,
    this.comment,
    this.createdAt,
    this.reply,
  });

  final String id;
  final String reviewerName;
  final int rating;
  final String? comment;
  final DateTime? createdAt;

  /// Business reply, if any.
  final ReviewReply? reply;

  factory PublicReview.fromJson(Object? raw) {
    final j = asJson(raw);
    return PublicReview(
      id: idOf(j),
      reviewerName: str(j['reviewerName']) ?? str(j['name']) ?? 'Anonymous',
      rating: intOr(j['rating']).clamp(0, 5),
      comment: str(j['comment']),
      createdAt: dateOrNull(j['createdAt']),
      reply: ReviewReply.fromJson(j['reply']),
    );
  }

  /// Public lists must only ever contain approved reviews. The server is
  /// responsible for this; the client additionally drops anything that is
  /// explicitly marked otherwise.
  static bool isPublishable(Object? raw) {
    final status = str(asJson(raw)['status']);
    return status == null || status == 'approved';
  }
}

/// Body for `POST /public/card/:slug/review`.
class ReviewSubmission {
  const ReviewSubmission({required this.rating, required this.name, this.comment});

  final int rating;
  final String name;
  final String? comment;

  Json toJson() => compact({
        'rating': rating,
        'name': name.trim(),
        'comment': (comment?.trim().isEmpty ?? true) ? null : comment!.trim(),
      });
}

enum SubmittedReviewStatus { pending, approved }

/// Outcome of a review submission. Unknown or missing status is treated as
/// `pending` so we never promise immediate publication.
class ReviewSubmissionResult {
  const ReviewSubmissionResult(this.status);

  final SubmittedReviewStatus status;

  bool get isApproved => status == SubmittedReviewStatus.approved;

  factory ReviewSubmissionResult.fromJson(Object? data) {
    final j = asJson(data);
    final status = str(j['status']) ?? str(asJson(j['review'])['status']);
    return ReviewSubmissionResult(
      status == 'approved'
          ? SubmittedReviewStatus.approved
          : SubmittedReviewStatus.pending,
    );
  }
}
