import '../../core/auth/auth_user.dart';
import '../../core/utilities/json.dart';
import 'card.dart';

/// Organization-wide people directory setting (PROPOSED field).
enum DirectoryVisibility {
  public('public'),
  private('private');

  const DirectoryVisibility(this.wire);
  final String wire;

  static DirectoryVisibility parse(Object? v) =>
      str(v) == 'private' ? DirectoryVisibility.private : DirectoryVisibility.public;
}

class TrialInfo {
  const TrialInfo({required this.active, this.endsAt, this.daysRemaining});

  final bool active;
  final DateTime? endsAt;
  final int? daysRemaining;

  factory TrialInfo.fromJson(Object? raw) {
    if (raw is bool) return TrialInfo(active: raw);
    final j = asJson(raw);
    final endsAt = dateOrNull(j['endsAt'] ?? j['endDate'] ?? j['trialEndsAt']);
    return TrialInfo(
      active: boolOrNull(j['active'] ?? j['isActive'] ?? j['onTrial']) ??
          (endsAt?.isAfter(DateTime.now()) ?? false),
      endsAt: endsAt,
      daysRemaining: intOrNull(j['daysRemaining'] ?? j['daysLeft']),
    );
  }
}

/// `GET /organization/profile`. Unknown fields are preserved in [raw] so the
/// profile editor can round-trip backend fields this model does not know.
class OrganizationProfile {
  const OrganizationProfile({
    required this.id,
    required this.name,
    this.slug,
    this.status,
    this.email,
    this.phone,
    this.website,
    this.address,
    this.description,
    this.logo,
    this.industry,
    this.directoryVisibility = DirectoryVisibility.public,
    this.raw = const {},
  });

  final String id;
  final String name;
  final String? slug;
  final String? status;
  final String? email;
  final String? phone;
  final String? website;
  final String? address;
  final String? description;
  final String? logo;
  final String? industry;
  final DirectoryVisibility directoryVisibility;
  final Json raw;

  factory OrganizationProfile.fromJson(Object? data) {
    var j = asJson(data);
    if (j['organization'] is Map) j = asJson(j['organization']);
    return OrganizationProfile(
      id: idOf(j),
      name: strOr(j['name'], 'My organization'),
      slug: str(j['slug']),
      status: str(j['status']),
      email: str(j['email']),
      phone: str(j['phone']),
      website: str(j['website']),
      address: str(j['address']),
      description: str(j['description']) ?? str(j['about']),
      logo: str(j['logo']),
      industry: str(j['industry']),
      directoryVisibility: DirectoryVisibility.parse(j['directoryVisibility']),
      raw: j,
    );
  }
}

/// `GET /organization/dashboard`.
class DashboardSummary {
  const DashboardSummary({
    required this.organizationName,
    this.organizationStatus,
    this.trial,
    this.activeCards = 0,
    this.paidSeats = 0,
    this.totalCards = 0,
    this.totalReviews = 0,
    this.averageRating = 0,
    this.disabledByBilling = 0,
    this.unlimitedSeats = false,
  });

  final String organizationName;
  final String? organizationStatus;
  final TrialInfo? trial;
  final int activeCards;
  final int paidSeats;
  final int totalCards;
  final int totalReviews;
  final double averageRating;
  final int disabledByBilling;

  /// Trial seat capacity is unlimited per product rules.
  final bool unlimitedSeats;

  factory DashboardSummary.fromJson(Object? data) {
    final j = asJson(data);
    final org = asJson(j['organization']);
    final seats = asJson(j['seats']);
    final stats = asJson(j['stats']).isEmpty ? j : asJson(j['stats']);
    final trial = j['trial'] ?? org['trial'];
    final trialInfo = trial == null ? null : TrialInfo.fromJson(trial);
    return DashboardSummary(
      organizationName: strOr(org['name'] ?? j['organizationName'], 'My organization'),
      organizationStatus: str(org['status'] ?? j['status']),
      trial: trialInfo,
      activeCards: intOr(stats['activeCards'] ?? seats['used']),
      paidSeats: intOr(stats['paidSeats'] ?? seats['paid'] ?? seats['total']),
      totalCards: intOr(stats['totalCards']),
      totalReviews: intOr(stats['totalReviews']),
      averageRating: doubleOr(stats['averageRating']),
      disabledByBilling: intOr(
        stats['disabledByBilling'] ?? stats['cardsDisabledByBilling'],
      ),
      unlimitedSeats:
          boolOrNull(seats['unlimited'] ?? j['unlimitedSeats']) ?? (trialInfo?.active ?? false),
    );
  }
}

/// Row of `GET /organization/staff`.
class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.designation,
    this.permissions = StaffPermissions.none,
    this.card,
    this.status,
    this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? designation;
  final StaffPermissions permissions;
  final CardModel? card;
  final String? status;
  final DateTime? createdAt;

  factory StaffMember.fromJson(Object? raw) {
    final j = asJson(raw);
    final card = j['card'];
    return StaffMember(
      id: idOf(j),
      name: strOr(j['name'], 'Unnamed'),
      email: strOr(j['email'] ?? j['loginEmail']),
      phone: str(j['phone']),
      designation: str(j['designation']),
      permissions: StaffPermissions.fromJson(j['permissions']),
      card: card is Map ? CardModel.fromJson(card) : null,
      status: str(j['status']),
      createdAt: dateOrNull(j['createdAt']),
    );
  }
}
