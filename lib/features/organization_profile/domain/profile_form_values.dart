import '../../../core/utilities/json.dart';
import '../../../shared/models/organization.dart';

/// Editable organization profile fields as entered in the form (trimmed).
/// [changesFrom] produces a PATCH body with only the fields that changed,
/// limited to fields the backend profile schema is known to accept.
class ProfileFormValues {
  const ProfileFormValues({
    required this.name,
    this.email = '',
    this.phone = '',
    this.website = '',
    this.address = '',
    this.description = '',
    this.industry = '',
    this.directoryVisibility = DirectoryVisibility.public,
  });

  final String name;
  final String email;
  final String phone;
  final String website;
  final String address;
  final String description;
  final String industry;
  final DirectoryVisibility directoryVisibility;

  factory ProfileFormValues.fromProfile(OrganizationProfile p) => ProfileFormValues(
        name: p.name.trim(),
        email: p.email?.trim() ?? '',
        phone: p.phone?.trim() ?? '',
        website: p.website?.trim() ?? '',
        address: p.address?.trim() ?? '',
        description: p.description?.trim() ?? '',
        industry: p.industry?.trim() ?? '',
        directoryVisibility: p.directoryVisibility,
      );

  /// Changed fields only. Cleared optional fields are sent as `null`.
  /// `directoryVisibility` is a PROPOSED field (API gap register).
  Json changesFrom(OrganizationProfile original) {
    final before = ProfileFormValues.fromProfile(original);
    final out = <String, dynamic>{};
    void put(String key, String now, String was) {
      if (now != was) out[key] = now.isEmpty ? null : now;
    }

    // Keep the backend's own key for the description field.
    final raw = original.raw;
    final descriptionKey =
        !raw.containsKey('description') && raw.containsKey('about') ? 'about' : 'description';

    put('name', name, before.name);
    put('email', email.toLowerCase(), before.email.toLowerCase());
    put('phone', phone, before.phone);
    put('website', website, before.website);
    put('address', address, before.address);
    put(descriptionKey, description, before.description);
    put('industry', industry, before.industry);
    if (directoryVisibility != before.directoryVisibility) {
      out['directoryVisibility'] = directoryVisibility.wire;
    }
    return out;
  }
}
