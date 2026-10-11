import '../../../core/auth/auth_user.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utilities/json.dart';
import '../../../shared/models/organization.dart';

/// Staff editor form values (trimmed).
class StaffDraft {
  const StaffDraft({
    required this.name,
    required this.email,
    this.phone = '',
    this.designation = '',
    this.password = '',
    this.permissions = StaffPermissions.none,
  });

  final String name;

  /// Login email for staff sign-in.
  final String email;
  final String phone;
  final String designation;

  /// Initial password — create only, never sent on update.
  final String password;
  final StaffPermissions permissions;

  factory StaffDraft.fromMember(StaffMember m) => StaffDraft(
        name: m.name.trim(),
        email: m.email.trim(),
        phone: m.phone?.trim() ?? '',
        designation: m.designation?.trim() ?? '',
        permissions: m.permissions,
      );

  String get _normalizedEmail => email.trim().toLowerCase();

  /// `POST /organization/staff` body. The server also creates the staff
  /// member's assigned card.
  Json toCreateJson() => compact({
        'name': name,
        'email': _normalizedEmail,
        'password': password,
        'phone': phone.isEmpty ? null : phone,
        'designation': designation.isEmpty ? null : designation,
        'permissions': permissions.toJson(),
      });

  /// `PATCH /organization/staff/:id` body with changed fields only. Cleared
  /// optional fields are sent as `null`; permissions are sent as a whole.
  Json changesFrom(StaffMember original) {
    final before = StaffDraft.fromMember(original);
    final out = <String, dynamic>{};
    void put(String key, String now, String was) {
      if (now != was) out[key] = now.isEmpty ? null : now;
    }

    put('name', name, before.name);
    if (_normalizedEmail != before._normalizedEmail) out['email'] = _normalizedEmail;
    put('phone', phone, before.phone);
    put('designation', designation, before.designation);
    if (permissions != before.permissions) {
      out['permissions'] = permissions.toJson();
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

  static StaffCardState of(StaffMember m) {
    final card = m.card;
    if (card == null) return StaffCardState.none;
    if (card.disabledByBilling) return StaffCardState.disabledByBilling;
    return card.isActive ? StaffCardState.active : StaffCardState.disabled;
  }
}

/// How a failed staff create/update should be explained.
enum StaffSaveProblem {
  /// No paid card slot available (403/409 seat / quota / plan restriction).
  noSeat,

  /// Login email already in use.
  duplicateEmail,
  other,
}

final _seatPattern =
    RegExp(r'seat|slot|quota|limit|plan|billing|subscription', caseSensitive: false);
final _duplicatePattern = RegExp(
  r'email|already (exists|registered|in use|taken)|duplicate',
  caseSensitive: false,
);

/// Classifies a staff save error. 403/409 are treated as "no paid slot"
/// unless they clearly describe a duplicate login email.
StaffSaveProblem classifyStaffSaveError(AppException e) {
  if (e.kind != AppErrorKind.forbidden && e.kind != AppErrorKind.conflict) {
    return StaffSaveProblem.other;
  }
  final text = '${e.code ?? ''} ${e.message}';
  if (_seatPattern.hasMatch(text)) return StaffSaveProblem.noSeat;
  if (e.kind == AppErrorKind.conflict &&
      (_duplicatePattern.hasMatch(text) || e.fieldErrors.containsKey('email'))) {
    return StaffSaveProblem.duplicateEmail;
  }
  return StaffSaveProblem.noSeat;
}
