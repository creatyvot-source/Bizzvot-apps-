import '../../../core/utilities/json.dart';
import '../../../shared/models/organization.dart';

/// Owner dashboard view model, mapped from the real backend payloads:
///
/// * `GET /organization/dashboard` →
///   `{ cards, cardsLimit, staff, staffLimit, reviews, averageRating }`
///   (cogcard `app/api/v1/organization/dashboard/route.ts`). There is no
///   organization name/status, trial, active-card split or billing flag.
/// * `GET /organization/profile` → the Organization doc (`name`, `status`,
///   `planExpiry`, …) for the header.
///
/// Fields the backend may add later (`activeCards`, `disabledByBilling`,
/// `trial`, `organization{name,status}`) are read when present.
class DashboardOverview {
  const DashboardOverview({
    required this.organizationName,
    this.organizationStatus,
    this.totalCards = 0,
    this.cardsLimit,
    this.activeCards,
    this.staffCount = 0,
    this.staffLimit,
    this.totalReviews = 0,
    this.averageRating = 0,
    this.disabledByBilling = 0,
    this.trial,
    this.planExpiry,
  });

  final String organizationName;
  final String? organizationStatus;
  final int totalCards;

  /// Card slots on the plan; `null` means unlimited / not reported.
  final int? cardsLimit;

  /// Only when the backend reports it.
  final int? activeCards;
  final int staffCount;
  final int? staffLimit;
  final int totalReviews;
  final double averageRating;
  final int disabledByBilling;
  final TrialInfo? trial;
  final DateTime? planExpiry;

  bool get unlimitedCards => cardsLimit == null || (trial?.active ?? false);
  bool get cardSlotsFull =>
      !unlimitedCards && cardsLimit! > 0 && totalCards >= cardsLimit!;
  bool get staffSlotsFull =>
      staffLimit != null && staffLimit! >= 0 && staffCount >= staffLimit!;

  factory DashboardOverview.fromJson(
    Object? dashboard, {
    OrganizationProfile? profile,
  }) {
    final j = asJson(dashboard);
    final stats = asJson(j['stats']).isEmpty ? j : asJson(j['stats']);
    final org = asJson(j['organization']);
    final trialRaw = j['trial'] ?? org['trial'];
    final raw = profile?.raw ?? const {};

    int? limit(Object? v) {
      final n = intOrNull(v);
      // JSON has no Infinity; null or a negative value means "no limit".
      return (n == null || n < 0) ? null : n;
    }

    return DashboardOverview(
      organizationName:
          str(org['name']) ??
          str(j['organizationName']) ??
          profile?.name ??
          'Your organization',
      organizationStatus: str(org['status']) ?? profile?.status,
      totalCards: intOr(stats['cards'] ?? stats['totalCards']),
      cardsLimit: limit(stats['cardsLimit'] ?? stats['paidSeats']),
      activeCards: intOrNull(stats['activeCards']),
      staffCount: intOr(stats['staff'] ?? stats['staffCount']),
      staffLimit: limit(stats['staffLimit']),
      totalReviews: intOr(stats['reviews'] ?? stats['totalReviews']),
      averageRating: doubleOr(stats['averageRating']),
      disabledByBilling: intOr(
        stats['disabledByBilling'] ?? stats['cardsDisabledByBilling'],
      ),
      trial: trialRaw == null ? null : TrialInfo.fromJson(trialRaw),
      planExpiry: dateOrNull(raw['planExpiry']),
    );
  }
}
