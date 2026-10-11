import '../../../core/auth/auth_user.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utilities/json.dart';
import '../../../shared/models/card.dart';

/// Staff sign-in status (`Staff.status`).
enum StaffStatus {
  active('active'),
  suspended('suspended');

  const StaffStatus(this.wire);
  final String wire;

  static StaffStatus parse(Object? v) =>
      str(v) == 'suspended' ? StaffStatus.suspended : StaffStatus.active;
}

/// One staff member as returned by `GET /organization/staff[/:id]`:
/// a `Staff` document with the person populated under `userId`
/// (`{ _id, userId: {_id, name, email, phone, status}, permissions,
/// assignedCardIds: [...], status }`). Flat rows are accepted too.
///
/// [cards] is filled by the repository from `GET /organization/cards`
/// because the staff payload only carries card ids.
class StaffEntry {
  const StaffEntry({
    required this.id,
    required this.name,
    required this.email,
    this.userId,
    this.phone,
    this.status = StaffStatus.active,
    this.permissions = StaffPermissions.none,
    this.assignedCardIds = const [],
    this.cards = const [],
    this.createdAt,
  });

  /// `Staff._id` — used in `/organization/staff/:id`.
  final String id;
  final String? userId;
  final String name;
  final String email;
  final String? phone;
  final StaffStatus status;
  final StaffPermissions permissions;
  final List<String> assignedCardIds;

  /// Resolved assigned cards (those of [assignedCardIds] that were found).
  final List<CardModel> cards;
  final DateTime? createdAt;

  bool get isSuspended => status == StaffStatus.suspended;

  /// The card to show first: an active one if any.
  CardModel? get primaryCard {
    for (final c in cards) {
      if (c.isActive) return c;
    }
    return cards.isEmpty ? null : cards.first;
  }

  factory StaffEntry.fromJson(Object? raw) {
    final j = asJson(raw);
    final userRaw = j['userId'] ?? j['user'];
    final user = asJson(userRaw);
    final ids = <String>[];
    final embedded = <CardModel>[];
    final list = j['assignedCardIds'] ?? j['cards'];
    for (final c in list is List ? list : const []) {
      if (c is Map) {
        final card = CardModel.fromJson(c);
        if (card.id.isNotEmpty) {
          ids.add(card.id);
          embedded.add(card);
        }
      } else {
        final id = str(c);
        if (id != null) ids.add(id);
      }
    }
    return StaffEntry(
      id: idOf(j),
      userId: user.isEmpty ? str(userRaw) : idOf(user),
      name: strOr(user['name'] ?? j['name'], 'Unnamed'),
      email: strOr(user['email'] ?? j['email']),
      phone: str(user['phone'] ?? j['phone']),
      status: StaffStatus.parse(j['status']),
      permissions: StaffPermissions.fromJson(j['permissions']),
      assignedCardIds: ids,
      cards: embedded,
      createdAt: dateOrNull(j['createdAt']),
    );
  }

  StaffEntry copyWith({List<CardModel>? cards, String? name, String? email}) =>
      StaffEntry(
        id: id,
        userId: userId,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone,
        status: status,
        permissions: permissions,
        assignedCardIds: assignedCardIds,
        cards: cards ?? this.cards,
        createdAt: createdAt,
      );
}

/// Add-staff form values (trimmed).
class StaffDraft {
  const StaffDraft({
    required this.name,
    required this.email,
    this.phone = '',
    this.designation = '',
    this.password = '',
    this.permissions = StaffPermissions.none,
    this.createCard = true,
  });

  final String name;

  /// Login email for staff sign-in.
  final String email;
  final String phone;

  /// Stored on the staff member's card (the staff record has no title).
  final String designation;

  /// Initial password.
  final String password;
  final StaffPermissions permissions;

  /// Create and assign a card right after the staff member is added.
  final bool createCard;

  String get normalizedEmail => email.trim().toLowerCase();

  /// `POST /organization/staff`. Permissions are always sent explicitly —
  /// the backend's defaults when omitted are permissive.
  Json toCreateJson() => compact({
        'name': name,
        'email': normalizedEmail,
        'password': password,
        'phone': phone.isEmpty ? null : phone,
        'permissions': permissions.toJson(),
      });

  /// `POST /organization/cards` body for the staff member's own card.
  /// Blank optional fields are omitted (never `null`).
  Json toCardJson() => cardJsonFor(
        name: name,
        designation: designation,
        email: normalizedEmail,
        phone: phone,
      );
}

/// Card body for a staff member's own card.
Json cardJsonFor({
  required String name,
  String designation = '',
  String email = '',
  String? phone,
}) =>
    compact({
      'title': name,
      'designation': designation.isEmpty ? null : designation,
      'email': email.isEmpty ? null : email,
      'phone': (phone == null || phone.isEmpty) ? null : phone,
    });

/// Editable settings of an existing staff member. The backend's PATCH only
/// accepts `permissions`, `status` and `assignedCardIds`.
class StaffSettings {
  const StaffSettings({
    required this.permissions,
    required this.status,
    required this.assignedCardIds,
  });

  final StaffPermissions permissions;
  final StaffStatus status;
  final List<String> assignedCardIds;

  factory StaffSettings.of(StaffEntry e) => StaffSettings(
        permissions: e.permissions,
        status: e.status,
        assignedCardIds: e.assignedCardIds,
      );

  StaffSettings copyWith({
    StaffPermissions? permissions,
    StaffStatus? status,
    List<String>? assignedCardIds,
  }) =>
      StaffSettings(
        permissions: permissions ?? this.permissions,
        status: status ?? this.status,
        assignedCardIds: assignedCardIds ?? this.assignedCardIds,
      );

  /// `PATCH /organization/staff/:id` body with changed keys only.
  Json changesFrom(StaffEntry original) {
    final out = <String, dynamic>{};
    if (permissions != original.permissions) {
      out['permissions'] = permissions.toJson();
    }
    if (status != original.status) out['status'] = status.wire;
    final a = {...assignedCardIds};
    final b = {...original.assignedCardIds};
    if (a.length != b.length || !a.containsAll(b)) {
      out['assignedCardIds'] = assignedCardIds;
    }
    return out;
  }
}

/// Card status shown on staff rows.
enum StaffCardState {
  active('Active'),
  disabled('Disabled'),
  disabledByBilling('Disabled by billing'),
  none('No card');

  const StaffCardState(this.label);
  final String label;

  static StaffCardState ofCard(CardModel? card) {
    if (card == null) return StaffCardState.none;
    if (card.disabledByBilling) return StaffCardState.disabledByBilling;
    return card.isActive ? StaffCardState.active : StaffCardState.disabled;
  }

  /// State of the primary assigned card; `null` when cards are assigned but
  /// could not be resolved (status unknown).
  static StaffCardState? of(StaffEntry e) {
    final card = e.primaryCard;
    if (card != null) return ofCard(card);
    return e.assignedCardIds.isEmpty ? StaffCardState.none : null;
  }
}

/// How a failed staff / card save should be explained.
enum StaffSaveProblem {
  /// No card slot available (`Card limit reached: max N card(s)`).
  noSeat,

  /// The plan's staff limit is reached (`Staff limit reached: max N staff`).
  staffLimit,

  /// Login email already in use (409 `Email already in use`).
  duplicateEmail,
  other,
}

final _staffLimit = RegExp(r'staff limit', caseSensitive: false);
final _duplicate = RegExp(
  r'email|already (exists|registered|in use|taken)|duplicate',
  caseSensitive: false,
);

/// Classifies a staff/card save error. Backend errors carry no codes, so
/// the message is inspected; other 403/409s default to "no paid slot".
StaffSaveProblem classifyStaffSaveError(AppException e) {
  if (e.kind != AppErrorKind.forbidden && e.kind != AppErrorKind.conflict) {
    return StaffSaveProblem.other;
  }
  final text = '${e.code ?? ''} ${e.message}';
  if (_staffLimit.hasMatch(text)) return StaffSaveProblem.staffLimit;
  if (e.kind == AppErrorKind.conflict &&
      (_duplicate.hasMatch(text) || e.fieldErrors.containsKey('email'))) {
    return StaffSaveProblem.duplicateEmail;
  }
  return StaffSaveProblem.noSeat;
}
