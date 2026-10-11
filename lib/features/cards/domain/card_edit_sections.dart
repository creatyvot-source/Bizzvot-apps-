import 'dart:convert';

import '../../../core/auth/auth_user.dart';
import '../../../core/utilities/json.dart';
import '../../../shared/models/card.dart';

/// Editor sections and the `PATCH` fields each one owns.
///
/// Only fields of sections the current user may edit are ever sent, so a
/// staff member with `manageLinks` alone can never overwrite contact data.
enum CardEditSection {
  identity('Identity', {'title', 'designation', 'company', 'pronouns', 'bio'}),
  images('Images', {'profilePhoto', 'coverImage', 'logo'}),
  contact('Contact', {
    'phone',
    'companyPhone',
    'whatsapp',
    'email',
    'website',
    'address',
    'mapLink',
  }),
  privateDetails('Private details', {'bloodGroup', 'fatherName', 'motherName'}),
  links('Social & custom links', {'socialLinks', 'customLinks'}),
  media('Gallery, documents & videos', {'gallery', 'pdfs', 'videos'}),
  appearance('Template & layout', {
    'template',
    'brandColor',
    'sectionOrder',
    'displayToggles',
    'vcardEnabled',
    'googleReviewUrl',
  }),
  visibility('Directory visibility', {'visibility'});

  const CardEditSection(this.label, this.fields);
  final String label;
  final Set<String> fields;

  /// Owners edit everything.
  static const ownerSections = {...CardEditSection.values};

  /// Sections a staff member may edit on their own card. The backend is the
  /// authority; this only decides what the editor shows and sends.
  static Set<CardEditSection> forStaff(StaffPermissions p) => {
    if (p.editCard) ...{
      CardEditSection.identity,
      CardEditSection.images,
      CardEditSection.contact,
      CardEditSection.media,
      CardEditSection.appearance,
    },
    if (p.manageLinks) CardEditSection.links,
  };
}

/// Builds the minimal `PATCH` body: only fields that belong to [allowed]
/// sections **and** differ from [original]. Blank strings are sent as `null`
/// (clear the field).
Json buildCardPatch(
  CardModel original,
  CardModel edited,
  Set<CardEditSection> allowed,
) {
  final before = _normalized(original.toUpdateJson());
  final after = _normalized(edited.toUpdateJson());
  final patch = <String, dynamic>{};
  for (final section in allowed) {
    for (final key in section.fields) {
      final a = after[key];
      if (jsonEncode(before[key]) != jsonEncode(a)) patch[key] = a;
    }
  }
  return patch;
}

Json _normalized(Json j) => j.map((k, v) {
  if (v is String) {
    final t = v.trim();
    return MapEntry(k, t.isEmpty ? null : t);
  }
  return MapEntry(k, v);
});
