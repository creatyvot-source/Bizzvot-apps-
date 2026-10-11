import '../../../core/utilities/json.dart';
import '../../../shared/models/organization.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/formatting.dart';

/// Banner shown on the billing screen, derived from server state only.
enum BillingAlert {
  paymentFailed,
  gracePeriod,
  expired,
  trialEnding,
  trialEnded,
  cardsDisabled,
}

/// `GET /organization/billing`. The shape is not finalised, so every field
/// is read defensively and unknown shapes degrade to "not available".
class BillingSummary {
  const BillingSummary({
    this.planId,
    this.planName,
    this.planFeatures = const [],
    this.billingPeriod,
    this.trial,
    this.paidSeats,
    this.activeCards,
    this.availableSeats,
    this.unlimitedSeats = false,
    this.disabledByBilling = 0,
    this.subscriptionId,
    this.subscriptionStatus = SubscriptionStatus.unknown,
    this.subscriptionStatusRaw,
    this.nextRenewalAt,
    this.graceUntil,
    this.cancelAtPeriodEnd = false,
    this.paymentFailed = false,
    this.lastPaymentStatus,
    this.plans = const [],
    this.hasSubscription = false,
    this.purchaseChannels,
  });

  final String? planId;
  final String? planName;
  final List<String> planFeatures;
  final String? billingPeriod;
  final TrialInfo? trial;
  final int? paidSeats;
  final int? activeCards;
  final int? availableSeats;
  final bool unlimitedSeats;
  final int disabledByBilling;
  final String? subscriptionId;
  final SubscriptionStatus subscriptionStatus;
  final String? subscriptionStatusRaw;
  final DateTime? nextRenewalAt;
  final DateTime? graceUntil;
  final bool cancelAtPeriodEnd;
  final bool paymentFailed;
  final PaymentStatus? lastPaymentStatus;

  /// Plans offered inline by the billing route (fallback for the catalogue).
  final List<Plan> plans;
  final bool hasSubscription;

  /// Server per-platform override for buying seats in-app.
  final PurchaseChannels? purchaseChannels;

  /// v1 default: seats are digital entitlements → status only, no purchase.
  bool get seatPurchaseAllowed =>
      PaymentPolicy.inAppDigital.allowsCheckout(purchaseChannels);

  bool get onTrial =>
      trial?.active ?? subscriptionStatus == SubscriptionStatus.trialing;

  String get subscriptionStatusLabel =>
      subscriptionStatus == SubscriptionStatus.unknown
      ? humanize(
          subscriptionStatusRaw,
          fallback: hasSubscription ? 'Unknown' : 'No subscription',
        )
      : subscriptionStatus.label;

  /// Alerts in priority order.
  List<BillingAlert> alerts({DateTime? now}) {
    final t = now ?? DateTime.now();
    final out = <BillingAlert>[];
    if (paymentFailed || subscriptionStatus == SubscriptionStatus.pastDue) {
      out.add(BillingAlert.paymentFailed);
    }
    if (subscriptionStatus == SubscriptionStatus.gracePeriod) {
      out.add(BillingAlert.gracePeriod);
    }
    if (subscriptionStatus == SubscriptionStatus.expired) {
      out.add(BillingAlert.expired);
    }
    final tr = trial;
    if (tr != null) {
      final ends = tr.endsAt;
      if (tr.active) {
        final days = tr.daysRemaining ?? ends?.difference(t).inDays;
        if (days != null && days <= 7) out.add(BillingAlert.trialEnding);
      } else if (ends != null && ends.isBefore(t) && !hasActivePaidPlan) {
        out.add(BillingAlert.trialEnded);
      }
    }
    if (disabledByBilling > 0) out.add(BillingAlert.cardsDisabled);
    return out;
  }

  bool get hasActivePaidPlan => switch (subscriptionStatus) {
    SubscriptionStatus.active ||
    SubscriptionStatus.pastDue ||
    SubscriptionStatus.gracePeriod => true,
    _ => false,
  };

  factory BillingSummary.fromJson(Object? data) {
    var j = asJson(data);
    if (j['billing'] is Map) j = {...j, ...asJson(j['billing'])};
    final org = asJson(j['organization']);
    final sub = asJson(j['subscription']);
    final planRaw = j['plan'] ?? j['currentPlan'] ?? sub['plan'];
    final plan = asJson(planRaw);
    final seats = asJson(j['seats']);
    final trialRaw = j['trial'] ?? org['trial'];
    final lastPayment = asJson(j['lastPayment'] ?? j['latestPayment']);
    final statusRaw = str(
      sub['status'] ??
          j['subscriptionStatus'] ??
          (j['plan'] is Map ? null : j['status']),
    );
    final lastPayStatus = str(lastPayment['status'] ?? j['paymentStatus']);
    final payStatus = lastPayStatus == null
        ? null
        : PaymentStatus.parse(lastPayStatus);
    return BillingSummary(
      planId:
          str(j['planId'] ?? sub['planId']) ??
          (planRaw is Map ? (idOf(plan).isEmpty ? null : idOf(plan)) : null),
      planName:
          str(j['planName']) ??
          (planRaw is Map ? str(plan['name']) : str(planRaw)),
      planFeatures: strList(plan['features'] ?? j['features']),
      billingPeriod: str(
        plan['billingPeriod'] ?? sub['billingPeriod'] ?? j['billingPeriod'],
      ),
      trial: trialRaw == null ? null : TrialInfo.fromJson(trialRaw),
      paidSeats: intOrNull(
        seats['paid'] ??
            seats['purchased'] ??
            seats['total'] ??
            j['paidSeats'] ??
            j['seatQuantity'] ??
            sub['quantity'],
      ),
      activeCards: intOrNull(
        seats['used'] ?? seats['active'] ?? j['activeCards'],
      ),
      availableSeats: intOrNull(
        seats['available'] ?? seats['remaining'] ?? j['availableSeats'],
      ),
      unlimitedSeats: boolOr(seats['unlimited'] ?? j['unlimitedSeats']),
      disabledByBilling: intOr(
        j['disabledByBilling'] ?? j['cardsDisabledByBilling'],
      ),
      subscriptionId:
          str(j['subscriptionId']) ?? (sub.isEmpty ? null : str(idOf(sub))),
      subscriptionStatus: SubscriptionStatus.parse(statusRaw),
      subscriptionStatusRaw: statusRaw,
      nextRenewalAt: dateOrNull(
        sub['nextRenewalAt'] ??
            sub['currentPeriodEnd'] ??
            j['nextRenewalAt'] ??
            j['renewalDate'] ??
            j['currentPeriodEnd'],
      ),
      graceUntil: dateOrNull(sub['graceUntil'] ?? j['graceUntil']),
      cancelAtPeriodEnd: boolOr(
        sub['cancelAtPeriodEnd'] ?? j['cancelAtPeriodEnd'],
      ),
      paymentFailed:
          boolOr(j['paymentFailed']) || payStatus == PaymentStatus.failed,
      lastPaymentStatus: payStatus,
      plans: asJsonList(j['plans'] ?? j['availablePlans'])
          .map(Plan.fromJson)
          .where((p) => p.id.isNotEmpty)
          .toList(growable: false),
      hasSubscription: sub.isNotEmpty || statusRaw != null,
      purchaseChannels: PurchaseChannels.tryParse(j['purchaseChannels']),
    );
  }
}

/// Outcome of confirming a seat purchase against the server.
enum SeatConfirmation { confirmed, failed, stillProcessing }

/// Decides from two server snapshots whether a seat purchase has been
/// verified. Never inferred from the checkout page.
SeatConfirmation? evaluateSeatPurchase(
  BillingSummary before,
  BillingSummary now,
) {
  final seatsAdded =
      now.paidSeats != null &&
      (before.paidSeats == null || now.paidSeats! > before.paidSeats!);
  final activated =
      now.subscriptionStatus == SubscriptionStatus.active &&
      before.subscriptionStatus != SubscriptionStatus.active;
  if (seatsAdded || activated) return SeatConfirmation.confirmed;
  final newlyFailed =
      now.lastPaymentStatus == PaymentStatus.failed &&
      before.lastPaymentStatus != PaymentStatus.failed;
  if (newlyFailed) return SeatConfirmation.failed;
  return null;
}
