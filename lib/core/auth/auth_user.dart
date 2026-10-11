import '../utilities/json.dart';

enum UserRole {
  owner,
  staff,
  customer,
  superAdmin,
  unknown;

  static UserRole parse(Object? v) => switch (str(v)?.toLowerCase()) {
        'owner' || 'org_owner' || 'organization_owner' || 'admin' =>
          UserRole.owner,
        'staff' => UserRole.staff,
        'customer' => UserRole.customer,
        'super_admin' || 'superadmin' => UserRole.superAdmin,
        _ => UserRole.unknown,
      };
}

/// Staff permissions. Every flag defaults to `false`; the backend is the
/// authority — these only drive which screens are shown.
class StaffPermissions {
  const StaffPermissions({
    this.editCard = false,
    this.viewReviews = false,
    this.replyReviews = false,
    this.manageLinks = false,
  });

  final bool editCard;
  final bool viewReviews;
  final bool replyReviews;
  final bool manageLinks;

  static const none = StaffPermissions();

  factory StaffPermissions.fromJson(Object? raw) {
    final j = asJson(raw);
    return StaffPermissions(
      editCard: boolOr(j['editCard']),
      viewReviews: boolOr(j['viewReviews']),
      replyReviews: boolOr(j['replyReviews']),
      manageLinks: boolOr(j['manageLinks']),
    );
  }

  Json toJson() => {
        'editCard': editCard,
        'viewReviews': viewReviews,
        'replyReviews': replyReviews,
        'manageLinks': manageLinks,
      };

  StaffPermissions copyWith({
    bool? editCard,
    bool? viewReviews,
    bool? replyReviews,
    bool? manageLinks,
  }) =>
      StaffPermissions(
        editCard: editCard ?? this.editCard,
        viewReviews: viewReviews ?? this.viewReviews,
        replyReviews: replyReviews ?? this.replyReviews,
        manageLinks: manageLinks ?? this.manageLinks,
      );

  @override
  bool operator ==(Object other) =>
      other is StaffPermissions &&
      other.editCard == editCard &&
      other.viewReviews == viewReviews &&
      other.replyReviews == replyReviews &&
      other.manageLinks == manageLinks;

  @override
  int get hashCode => Object.hash(editCard, viewReviews, replyReviews, manageLinks);
}

/// The signed-in principal as returned by `GET /auth/me`.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.role,
    this.name,
    this.organizationId,
    this.organizationName,
    this.cardId,
    this.permissions = StaffPermissions.none,
  });

  final String id;
  final String email;
  final String? name;
  final UserRole role;
  final String? organizationId;
  final String? organizationName;

  /// Staff only: the single card assigned to this user.
  final String? cardId;
  final StaffPermissions permissions;

  bool get isOwner => role == UserRole.owner;
  bool get isStaff => role == UserRole.staff;

  String get displayName => (name?.isNotEmpty ?? false) ? name! : email;

  factory AuthUser.fromJson(Object? raw) {
    var j = asJson(raw);
    // Accept `{ user: {...}, organization: {...} }` or a flat user object.
    final org = asJson(j['organization']);
    if (j['user'] is Map) j = {...j, ...asJson(j['user'])};
    final card = j['card'];
    return AuthUser(
      id: idOf(j),
      email: strOr(j['email']),
      name: str(j['name']) ?? str(j['fullName']),
      role: UserRole.parse(j['role']),
      organizationId: str(j['organizationId']) ?? str(j['orgId']) ??
          (org.isEmpty ? null : idOf(org)),
      organizationName: str(j['organizationName']) ?? str(org['name']),
      cardId: str(j['cardId']) ?? (card is Map ? idOf(asJson(card)) : str(card)),
      permissions: StaffPermissions.fromJson(j['permissions']),
    );
  }

  @override
  String toString() => 'AuthUser($id, $role)';
}
