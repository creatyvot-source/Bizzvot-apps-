import '../../../app/routes.dart';
import '../../../core/utilities/json.dart';
import '../../catalog/domain/formatting.dart';

/// In-app notification (PROPOSED `GET /notifications`, plan §13.12).
/// Named `AppNotification` to avoid clashing with Flutter's `Notification`.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.payload = const {},
    this.readAt,
    this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final String? body;
  final Json payload;
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get isRead => readAt != null;

  AppNotification markedRead(DateTime at) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        payload: payload,
        readAt: readAt ?? at,
        createdAt: createdAt,
      );

  factory AppNotification.fromJson(Object? raw) {
    final j = asJson(raw);
    final payload = asJson(j['payload'] ?? j['data']);
    final type = strOr(j['type'] ?? payload['type'], 'general');
    return AppNotification(
      id: idOf(j),
      type: type,
      title: strOr(j['title'] ?? payload['title'], _defaultTitle(type)),
      body: str(j['body'] ?? j['message'] ?? payload['message']),
      payload: payload,
      readAt: dateOrNull(j['readAt']) ??
          (boolOr(j['read'] ?? j['isRead']) ? DateTime.fromMillisecondsSinceEpoch(0) : null),
      createdAt: dateOrNull(j['createdAt']),
    );
  }

  static String _defaultTitle(String type) => humanize(type, fallback: 'Notification');

  /// Category used for the icon and the deep link.
  NotificationKind get kind => NotificationKind.of(type);

  /// In-app route for known types with a valid id; null otherwise. Only
  /// [Routes] helpers are used — payload strings are never navigated to.
  String? get route {
    String? id(List<String> keys) {
      for (final k in keys) {
        final v = str(payload[k]);
        if (v != null && _safeId.hasMatch(v)) return v;
      }
      return null;
    }

    switch (kind) {
      case NotificationKind.order:
        final o = id(const ['orderId', 'order', 'id']);
        return o == null ? Routes.ownerOrders : Routes.ownerOrder(o);
      case NotificationKind.payment:
        final o = id(const ['orderId', 'order']);
        return o == null ? Routes.ownerOrders : Routes.ownerOrder(o);
      case NotificationKind.invoice:
        final i = id(const ['invoiceId', 'invoice', 'id']);
        return i == null ? Routes.ownerInvoices : Routes.ownerInvoice(i);
      case NotificationKind.subscription:
        final s = id(const ['subscriptionId', 'subscription', 'id']);
        return s == null ? Routes.ownerSubscriptions : Routes.ownerSubscription(s);
      case NotificationKind.billing:
        return Routes.ownerBilling;
      case NotificationKind.review:
        return Routes.ownerReviews;
      case NotificationKind.card:
        final c = id(const ['cardId', 'card', 'id']);
        return c == null ? Routes.ownerCards : Routes.ownerCard(c);
      case NotificationKind.other:
        return null;
    }
  }

  static final _safeId = RegExp(r'^[A-Za-z0-9_\-]{1,64}$');
}

enum NotificationKind {
  order,
  payment,
  invoice,
  subscription,
  billing,
  review,
  card,
  other;

  /// Types are dotted or snake-case: `order.paid`, `subscription_renewal_due`,
  /// `payment_failed`, `review.new`, `card.disabled`.
  static NotificationKind of(String type) {
    final t = wireKey(type);
    String head(String prefix) => t.startsWith(prefix) ? prefix : '';
    if (head('order') != '') return NotificationKind.order;
    if (head('payment') != '') return NotificationKind.payment;
    if (head('invoice') != '') return NotificationKind.invoice;
    if (head('subscription') != '' || head('renewal') != '' || head('trial') != '') {
      return t.startsWith('trial') ? NotificationKind.billing : NotificationKind.subscription;
    }
    if (head('billing') != '' || head('seat') != '') return NotificationKind.billing;
    if (head('review') != '') return NotificationKind.review;
    if (head('card') != '') return NotificationKind.card;
    return NotificationKind.other;
  }
}
