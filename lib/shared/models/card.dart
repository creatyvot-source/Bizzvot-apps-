import '../../core/utilities/json.dart';

enum CardTemplate {
  minimal('minimal', 'Minimal'),
  corporate('corporate', 'Corporate'),
  modernDark('modern_dark', 'Modern dark'),
  profileHub('profile_hub', 'Profile hub'),
  coverCard('cover_card', 'Cover card'),
  reviewCard('review_card', 'Review card');

  const CardTemplate(this.wire, this.label);
  final String wire;
  final String label;

  static CardTemplate parse(Object? v) => CardTemplate.values
      .firstWhere((t) => t.wire == str(v), orElse: () => CardTemplate.minimal);
}

enum CardStatus {
  active,
  disabled;

  static CardStatus parse(Object? v) =>
      str(v) == 'active' ? CardStatus.active : CardStatus.disabled;
}

/// Per-card directory visibility (PROPOSED field, see API gap register).
enum CardVisibility {
  inherit('inherit', 'Inherit organization setting'),
  public('public', 'Public'),
  private('private', 'Private');

  const CardVisibility(this.wire, this.label);
  final String wire;
  final String label;

  static CardVisibility parse(Object? v) => CardVisibility.values
      .firstWhere((t) => t.wire == str(v), orElse: () => CardVisibility.inherit);
}

/// Media limits from the product spec. The server re-validates.
abstract final class CardLimits {
  static const gallery = 5;
  static const pdfs = 10;
  static const videos = 5;
}

class CardLink {
  const CardLink({required this.type, required this.url, this.label, this.id});

  /// e.g. `instagram`, `linkedin`, `facebook`, `x`, `youtube`, `custom`.
  final String type;
  final String url;
  final String? label;
  final String? id;

  factory CardLink.fromJson(Object? raw) {
    final j = asJson(raw);
    return CardLink(
      id: str(j['_id']) ?? str(j['id']),
      type: strOr(j['type'] ?? j['platform'], 'custom'),
      url: strOr(j['url']),
      label: str(j['label']) ?? str(j['title']),
    );
  }

  Json toJson() => compact({'type': type, 'url': url, 'label': label, '_id': id});
}

class MediaItem {
  const MediaItem({required this.url, this.id, this.name, this.kind});

  final String url;
  final String? id;
  final String? name;

  /// `image`, `pdf` or `youtube`.
  final String? kind;

  factory MediaItem.fromJson(Object? raw) {
    if (raw is String) return MediaItem(url: raw);
    final j = asJson(raw);
    return MediaItem(
      url: strOr(j['url'] ?? j['src']),
      id: str(j['_id']) ?? str(j['id']),
      name: str(j['name']) ?? str(j['title']),
      kind: str(j['kind']) ?? str(j['type']),
    );
  }

  Json toJson() => compact({'url': url, '_id': id, 'name': name, 'kind': kind});
}

/// Organization-side card model (owner/staff). Includes private details.
/// Public visitors use [PublicCard] in the public_card feature, which is a
/// separate DTO by construction.
class CardModel {
  const CardModel({
    required this.id,
    required this.slug,
    this.staffUserId,
    this.staffName,
    this.title,
    this.designation,
    this.company,
    this.pronouns,
    this.bio,
    this.profilePhoto,
    this.coverImage,
    this.logo,
    this.phone,
    this.companyPhone,
    this.whatsapp,
    this.email,
    this.website,
    this.address,
    this.mapLink,
    this.bloodGroup,
    this.fatherName,
    this.motherName,
    this.socialLinks = const [],
    this.customLinks = const [],
    this.gallery = const [],
    this.pdfs = const [],
    this.videos = const [],
    this.template = CardTemplate.minimal,
    this.brandColor,
    this.sectionOrder = const [],
    this.displayToggles = const {},
    this.vcardEnabled = true,
    this.status = CardStatus.disabled,
    this.disabledByBilling = false,
    this.visibility = CardVisibility.inherit,
    this.googleReviewUrl,
    this.viewCount,
    this.reviewCount,
    this.averageRating,
    this.updatedAt,
  });

  final String id;
  final String slug;
  final String? staffUserId;
  final String? staffName;

  // Identity
  final String? title;
  final String? designation;
  final String? company;
  final String? pronouns;
  final String? bio;

  // Images
  final String? profilePhoto;
  final String? coverImage;
  final String? logo;

  // Contact
  final String? phone;
  final String? companyPhone;
  final String? whatsapp;
  final String? email;
  final String? website;
  final String? address;
  final String? mapLink;

  // Private details — never shown on public surfaces.
  final String? bloodGroup;
  final String? fatherName;
  final String? motherName;

  final List<CardLink> socialLinks;
  final List<CardLink> customLinks;
  final List<MediaItem> gallery;
  final List<MediaItem> pdfs;
  final List<MediaItem> videos;

  final CardTemplate template;

  /// Hex color, e.g. `#1A73E8`.
  final String? brandColor;
  final List<String> sectionOrder;
  final Map<String, bool> displayToggles;
  final bool vcardEnabled;
  final CardStatus status;
  final bool disabledByBilling;
  final CardVisibility visibility;
  final String? googleReviewUrl;

  // Summary stats if the list endpoint returns them.
  final int? viewCount;
  final int? reviewCount;
  final double? averageRating;
  final DateTime? updatedAt;

  bool get isActive => status == CardStatus.active;
  String get displayTitle => title ?? staffName ?? 'Untitled card';

  factory CardModel.fromJson(Object? raw) {
    final j = asJson(raw);
    final staff = asJson(j['staff'] ?? j['staffUser']);
    final media = asJson(j['media']);
    final toggles = asJson(j['displayToggles'] ?? j['display']);
    final privateDetails = asJson(j['privateDetails']);
    return CardModel(
      id: idOf(j),
      slug: strOr(j['slug']),
      staffUserId: str(j['staffUserId']) ?? (staff.isEmpty ? null : idOf(staff)),
      staffName: str(j['staffName']) ?? str(staff['name']),
      title: str(j['title']) ?? str(j['name']),
      designation: str(j['designation']),
      company: str(j['company']),
      pronouns: str(j['pronouns']),
      bio: str(j['bio']),
      profilePhoto: str(j['profilePhoto']) ?? str(media['profilePhoto']),
      coverImage: str(j['coverImage']) ?? str(media['coverImage']),
      logo: str(j['logo']) ?? str(media['logo']),
      phone: str(j['phone']),
      companyPhone: str(j['companyPhone']),
      whatsapp: str(j['whatsapp']),
      email: str(j['email']),
      website: str(j['website']),
      address: str(j['address']),
      mapLink: str(j['mapLink']),
      bloodGroup: str(j['bloodGroup']) ?? str(privateDetails['bloodGroup']),
      fatherName: str(j['fatherName']) ?? str(privateDetails['fatherName']),
      motherName: str(j['motherName']) ?? str(privateDetails['motherName']),
      socialLinks: asJsonList(j['socialLinks']).map(CardLink.fromJson).toList(),
      customLinks: asJsonList(j['customLinks']).map(CardLink.fromJson).toList(),
      gallery: _media(j['gallery'] ?? media['gallery']),
      pdfs: _media(j['pdfs'] ?? j['documents'] ?? media['pdfs']),
      videos: _media(j['videos'] ?? j['youtubeVideos'] ?? media['videos']),
      template: CardTemplate.parse(j['template']),
      brandColor: str(j['brandColor']) ?? str(j['color']),
      sectionOrder: strList(j['sectionOrder']),
      displayToggles: toggles.map((k, v) => MapEntry(k, boolOr(v, true))),
      vcardEnabled: boolOrNull(j['vcardEnabled']) ?? true,
      status: CardStatus.parse(j['status']),
      disabledByBilling: boolOr(j['disabledByBilling']),
      visibility: CardVisibility.parse(j['visibility']),
      googleReviewUrl: str(j['googleReviewUrl']) ?? str(j['googleReviewLink']),
      viewCount: intOrNull(j['viewCount'] ?? j['views']),
      reviewCount: intOrNull(j['reviewCount']),
      averageRating: doubleOrNull(j['averageRating']),
      updatedAt: dateOrNull(j['updatedAt']),
    );
  }

  static List<MediaItem> _media(Object? v) {
    if (v is List) return v.map(MediaItem.fromJson).where((m) => m.url.isNotEmpty).toList();
    return const [];
  }

  /// Editable fields for `PATCH /organization/cards/:id`. Status and
  /// billing flags are excluded — they go through the status endpoint.
  Json toUpdateJson() => {
        'title': title,
        'designation': designation,
        'company': company,
        'pronouns': pronouns,
        'bio': bio,
        'profilePhoto': profilePhoto,
        'coverImage': coverImage,
        'logo': logo,
        'phone': phone,
        'companyPhone': companyPhone,
        'whatsapp': whatsapp,
        'email': email,
        'website': website,
        'address': address,
        'mapLink': mapLink,
        'bloodGroup': bloodGroup,
        'fatherName': fatherName,
        'motherName': motherName,
        'socialLinks': socialLinks.map((l) => l.toJson()).toList(),
        'customLinks': customLinks.map((l) => l.toJson()).toList(),
        'gallery': gallery.map((m) => m.toJson()).toList(),
        'pdfs': pdfs.map((m) => m.toJson()).toList(),
        'videos': videos.map((m) => m.toJson()).toList(),
        'template': template.wire,
        'brandColor': brandColor,
        'sectionOrder': sectionOrder,
        'displayToggles': displayToggles,
        'vcardEnabled': vcardEnabled,
        'visibility': visibility.wire,
        'googleReviewUrl': googleReviewUrl,
      };

  CardModel copyWith({
    String? title,
    String? designation,
    String? company,
    String? pronouns,
    String? bio,
    String? profilePhoto,
    String? coverImage,
    String? logo,
    String? phone,
    String? companyPhone,
    String? whatsapp,
    String? email,
    String? website,
    String? address,
    String? mapLink,
    String? bloodGroup,
    String? fatherName,
    String? motherName,
    List<CardLink>? socialLinks,
    List<CardLink>? customLinks,
    List<MediaItem>? gallery,
    List<MediaItem>? pdfs,
    List<MediaItem>? videos,
    CardTemplate? template,
    String? brandColor,
    List<String>? sectionOrder,
    Map<String, bool>? displayToggles,
    bool? vcardEnabled,
    CardStatus? status,
    bool? disabledByBilling,
    CardVisibility? visibility,
    String? googleReviewUrl,
    Set<String> clear = const {},
  }) {
    // Keys in [clear] (the `toUpdateJson` field names) are reset to null,
    // which plain `??` copy semantics cannot express.
    T? pick<T>(String key, T? next, T? current) =>
        clear.contains(key) ? null : (next ?? current);
    return CardModel(
        id: id,
        slug: slug,
        staffUserId: staffUserId,
        staffName: staffName,
        title: pick('title', title, this.title),
        designation: pick('designation', designation, this.designation),
        company: pick('company', company, this.company),
        pronouns: pick('pronouns', pronouns, this.pronouns),
        bio: pick('bio', bio, this.bio),
        profilePhoto: pick('profilePhoto', profilePhoto, this.profilePhoto),
        coverImage: pick('coverImage', coverImage, this.coverImage),
        logo: pick('logo', logo, this.logo),
        phone: pick('phone', phone, this.phone),
        companyPhone: pick('companyPhone', companyPhone, this.companyPhone),
        whatsapp: pick('whatsapp', whatsapp, this.whatsapp),
        email: pick('email', email, this.email),
        website: pick('website', website, this.website),
        address: pick('address', address, this.address),
        mapLink: pick('mapLink', mapLink, this.mapLink),
        bloodGroup: pick('bloodGroup', bloodGroup, this.bloodGroup),
        fatherName: pick('fatherName', fatherName, this.fatherName),
        motherName: pick('motherName', motherName, this.motherName),
        socialLinks: socialLinks ?? this.socialLinks,
        customLinks: customLinks ?? this.customLinks,
        gallery: gallery ?? this.gallery,
        pdfs: pdfs ?? this.pdfs,
        videos: videos ?? this.videos,
        template: template ?? this.template,
        brandColor: pick('brandColor', brandColor, this.brandColor),
        sectionOrder: sectionOrder ?? this.sectionOrder,
        displayToggles: displayToggles ?? this.displayToggles,
        vcardEnabled: vcardEnabled ?? this.vcardEnabled,
        status: status ?? this.status,
        disabledByBilling: disabledByBilling ?? this.disabledByBilling,
        visibility: visibility ?? this.visibility,
        googleReviewUrl: pick('googleReviewUrl', googleReviewUrl, this.googleReviewUrl),
        viewCount: viewCount,
        reviewCount: reviewCount,
        averageRating: averageRating,
        updatedAt: updatedAt,
      );
  }

  /// Nullable scalar fields that [copyWith] can clear via `clear:`.
  static const clearableFields = {
    'title', 'designation', 'company', 'pronouns', 'bio',
    'profilePhoto', 'coverImage', 'logo',
    'phone', 'companyPhone', 'whatsapp', 'email', 'website', 'address',
    'mapLink', 'bloodGroup', 'fatherName', 'motherName', 'brandColor',
    'googleReviewUrl',
  };

  /// True when any private detail (blood group, parents' names) is set.
  /// Private details must never be rendered on public surfaces.
  bool get hasPrivateDetails =>
      bloodGroup != null || fatherName != null || motherName != null;
}
