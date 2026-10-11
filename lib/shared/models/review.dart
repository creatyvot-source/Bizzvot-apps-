import '../../core/utilities/json.dart';

enum ReviewStatus {
  pending,
  approved,
  hidden;

  static ReviewStatus parse(Object? v) => ReviewStatus.values
      .firstWhere((s) => s.name == str(v), orElse: () => ReviewStatus.pending);
}

class ReviewReply {
  const ReviewReply({required this.text, this.createdAt, this.authorName});

  final String text;
  final DateTime? createdAt;
  final String? authorName;

  static ReviewReply? fromJson(Object? raw) {
    if (raw is String) return raw.isEmpty ? null : ReviewReply(text: raw);
    final j = asJson(raw);
    final text = str(j['text']);
    if (text == null) return null;
    return ReviewReply(
      text: text,
      createdAt: dateOrNull(j['createdAt'] ?? j['repliedAt']),
      authorName: str(j['authorName']) ?? str(j['by']),
    );
  }
}

/// Review as seen by organization users. Deliberately has no reviewer email
/// or IP fields: the app never displays them even if the API sends them.
class Review {
  const Review({
    required this.id,
    required this.rating,
    required this.status,
    this.cardId,
    this.cardTitle,
    this.reviewerName,
    this.comment,
    this.reply,
    this.createdAt,
  });

  final String id;
  final String? cardId;
  final String? cardTitle;
  final String? reviewerName;
  final int rating;
  final String? comment;
  final ReviewStatus status;
  final ReviewReply? reply;
  final DateTime? createdAt;

  factory Review.fromJson(Object? raw) {
    final j = asJson(raw);
    final card = j['card'];
    return Review(
      id: idOf(j),
      cardId: str(j['cardId']) ?? (card is Map ? idOf(asJson(card)) : str(card)),
      cardTitle: str(j['cardTitle']) ??
          (card is Map ? str(card['title']) ?? str(card['name']) : null),
      reviewerName: str(j['reviewerName']) ?? str(j['name']),
      rating: intOr(j['rating']).clamp(0, 5),
      comment: str(j['comment']),
      status: ReviewStatus.parse(j['status']),
      reply: ReviewReply.fromJson(j['reply']),
      createdAt: dateOrNull(j['createdAt']),
    );
  }
}
