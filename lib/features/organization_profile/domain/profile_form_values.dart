import '../../../core/utilities/json.dart';
import '../../../shared/models/organization.dart';

/// Editable organization profile fields as entered in the form (trimmed).
///
/// The backend PATCH allow-list is `name, logo, industry, address,
/// gstNumber` (cogcard `organization/profile/route.ts`); anything else is
/// silently ignored. `directoryVisibility` is a PROPOSED field and is sent
/// so it works once the backend adds it — the screen detects when it was
/// dropped.
class ProfileFormValues {
  const ProfileFormValues({
    required this.name,
    this.industry = '',
    this.address = '',
    this.gstNumber = '',
    this.directoryVisibility = DirectoryVisibility.public,
  });

  final String name;
  final String industry;
  final String address;
  final String gstNumber;
  final DirectoryVisibility directoryVisibility;

  factory ProfileFormValues.fromProfile(OrganizationProfile p) =>
      ProfileFormValues(
        name: p.name.trim(),
        industry: p.industry?.trim() ?? '',
        address: p.address?.trim() ?? '',
        gstNumber: str(p.raw['gstNumber'])?.trim() ?? '',
        directoryVisibility: p.directoryVisibility,
      );

  /// Changed fields only, never `null`: a cleared optional field is sent as
  /// `''` (the backend returns 500 for `name: null`). An empty name is never
  /// sent — the form requires it.
  Json changesFrom(OrganizationProfile original) {
    final before = ProfileFormValues.fromProfile(original);
    final out = <String, dynamic>{};
    if (name.isNotEmpty && name != before.name) out['name'] = name;
    if (industry != before.industry) out['industry'] = industry;
    if (address != before.address) out['address'] = address;
    if (gstNumber.toUpperCase() != before.gstNumber.toUpperCase()) {
      out['gstNumber'] = gstNumber.toUpperCase();
    }
    if (directoryVisibility != before.directoryVisibility) {
      out['directoryVisibility'] = directoryVisibility.wire;
    }
    return out;
  }
}

/// True when [changes] asked for a directory change that the saved profile
/// does not reflect (the backend ignored the unsupported field).
bool directoryChangeDropped(Json changes, OrganizationProfile saved) {
  final wanted = changes['directoryVisibility'];
  if (wanted == null) return false;
  return !saved.raw.containsKey('directoryVisibility') ||
      saved.directoryVisibility.wire != wanted;
}
