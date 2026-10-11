import '../../../core/utilities/json.dart';
import '../../../shared/models/card.dart';

/// Normalises section / toggle keys so `showPhone`, `show_phone` and
/// `phone` all compare equal.
String normalizeCardKey(String raw) {
  var k = raw.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  if (k.startsWith('show') && k.length > 4) k = k.substring(4);
  return k;
}

/// Sections a public card can render, in default order.
enum PublicSection {
  contact(['contact', 'contacts', 'contactinfo', 'info']),
  about(['about', 'bio']),
  social(['social', 'sociallinks', 'socials']),
  links(['links', 'customlinks', 'custom']),
  gallery(['gallery', 'images', 'photos']),
  videos(['videos', 'youtube', 'youtubevideos']),
  pdfs(['pdfs', 'documents', 'docs', 'files']),
  reviews(['reviews', 'ratings']);

  const PublicSection(this.aliases);

  /// Normalised keys that identify this section in `sectionOrder` and
  /// `displayToggles`.
  final List<String> aliases;

  static PublicSection? parse(String raw) {
    final k = normalizeCardKey(raw);
    for (final s in values) {
      if (s.aliases.contains(k)) return s;
    }
    return null;
  }
}

/// Keys that must never be carried by a public DTO, even as toggle names.
const _privateKeys = {'bloodgroup', 'fathername', 'mothername', 'privatedetails'};

/// Public card as rendered to anonymous visitors.
///
/// This is a **separate DTO by construction**: it is built from an
/// allow-list of public fields only. It has no fields for private details
/// (blood group, parents' names), reviewer emails or IPs, and unknown
/// payload keys are dropped, so private data can never reach a public
/// surface even if the API sends it.
class PublicCard {
  const PublicCard({
    required this.slug,
    this.id,
    this.name,
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
    this.googleReviewUrl,
    this.organizationName,
    this.organizationLogo,
    this.averageRating,
    this.reviewCount,
  });

  /// Card id, used only to fetch the vCard. May be absent.
  final String? id;
  final String slug;

  // Identity
  final String? name;
  final String? designation;
  final String? company;
  final String? pronouns;
  final String? bio;

  // Images
  final String? profilePhoto;
  final String? coverImage;
  final String? logo;

  // Public contact
  final String? phone;
  final String? companyPhone;
  final String? whatsapp;
  final String? email;
  final String? website;
  final String? address;
  final String? mapLink;

  final List<CardLink> socialLinks;
  final List<CardLink> customLinks;
  final List<MediaItem> gallery;
  final List<MediaItem> pdfs;
  final List<MediaItem> videos;

  final CardTemplate template;
  final String? brandColor;

  /// Known sections only, in display order (missing ones appended).
  final List<PublicSection> sectionOrder;

  /// Normalised keys (see [normalizeCardKey]) → visible.
  final Map<String, bool> displayToggles;
  final bool vcardEnabled;
  final String? googleReviewUrl;

  final String? organizationName;
  final String? organizationLogo;
  final double? averageRating;
  final int? reviewCount;

  String get displayName => name ?? organizationName ?? 'Digital card';

  /// True unless a display toggle for any of [keys] is explicitly `false`.
  bool shows(List<String> keys) =>
      keys.every((k) => displayToggles[normalizeCardKey(k)] ?? true);

  bool showsSection(PublicSection s) => shows(s.aliases);

  /// vCard is offered only when enabled, not toggled off and an id exists.
  bool get canSaveContact =>
      vcardEnabled && (id?.isNotEmpty ?? false) && shows(const ['vcard', 'savecontact']);

  factory PublicCard.fromJson(Object? data) {
    final root = asJson(data);
    // Accept `{ card: {...}, organization: {...} }` or a flat card.
    final j = root['card'] is Map ? asJson(root['card']) : root;
    final org = asJson(root['organization'] ?? j['organization'] ?? j['org']);
    final media = asJson(j['media']);
    final stats = asJson(root['stats'] ?? j['stats'] ?? root['reviewSummary']);

    final toggles = <String, bool>{};
    asJson(j['displayToggles'] ?? j['display']).forEach((k, v) {
      final key = normalizeCardKey(k);
      final b = boolOrNull(v);
      if (b != null && !_privateKeys.contains(key)) toggles[key] = b;
    });

    final order = <PublicSection>[];
    for (final raw in strList(j['sectionOrder'])) {
      final s = PublicSection.parse(raw);
      if (s != null && !order.contains(s)) order.add(s);
    }
    for (final s in PublicSection.values) {
      if (!order.contains(s)) order.add(s);
    }

    final id = str(j['id']) ?? str(j['_id']) ?? str(j['cardId']);
    return PublicCard(
      id: id,
      slug: strOr(j['slug']),
      name: str(j['title']) ?? str(j['name']) ?? str(j['fullName']),
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
      socialLinks: _links(j['socialLinks']),
      customLinks: _links(j['customLinks']),
      gallery: _media(j['gallery'] ?? media['gallery']),
      pdfs: _media(j['pdfs'] ?? j['documents'] ?? media['pdfs']),
      videos: _media(j['videos'] ?? j['youtubeVideos'] ?? media['videos']),
      template: CardTemplate.parse(j['template']),
      brandColor: str(j['brandColor']) ?? str(j['color']),
      sectionOrder: List.unmodifiable(order),
      displayToggles: Map.unmodifiable(toggles),
      vcardEnabled: boolOrNull(j['vcardEnabled']) ?? true,
      googleReviewUrl: str(j['googleReviewUrl']) ?? str(j['googleReviewLink']),
      organizationName: str(org['name']) ?? str(j['organizationName']),
      organizationLogo: str(org['logo']) ?? str(j['organizationLogo']),
      averageRating: doubleOrNull(
        j['averageRating'] ?? stats['averageRating'] ?? stats['average'],
      ),
      reviewCount: intOrNull(
        j['reviewCount'] ?? j['totalReviews'] ?? stats['reviewCount'] ?? stats['total'],
      ),
    );
  }

  static List<CardLink> _links(Object? v) => asJsonList(v)
      .map(CardLink.fromJson)
      .where((l) => l.url.isNotEmpty)
      .map((l) => CardLink(type: l.type, url: l.url, label: l.label))
      .toList(growable: false);

  static List<MediaItem> _media(Object? v) {
    if (v is! List) return const [];
    return v
        .map(MediaItem.fromJson)
        .where((m) => m.url.isNotEmpty)
        .map((m) => MediaItem(url: m.url, name: m.name, kind: m.kind))
        .toList(growable: false);
  }

  /// Every field this DTO holds. Used by tests to prove nothing private is
  /// carried; keep in sync when adding fields.
  Json toPublicJson() => {
        'id': id,
        'slug': slug,
        'name': name,
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
        'socialLinks': socialLinks.map((l) => l.toJson()).toList(),
        'customLinks': customLinks.map((l) => l.toJson()).toList(),
        'gallery': gallery.map((m) => m.toJson()).toList(),
        'pdfs': pdfs.map((m) => m.toJson()).toList(),
        'videos': videos.map((m) => m.toJson()).toList(),
        'template': template.wire,
        'brandColor': brandColor,
        'sectionOrder': sectionOrder.map((s) => s.name).toList(),
        'displayToggles': displayToggles,
        'vcardEnabled': vcardEnabled,
        'googleReviewUrl': googleReviewUrl,
        'organizationName': organizationName,
        'organizationLogo': organizationLogo,
        'averageRating': averageRating,
        'reviewCount': reviewCount,
      };
}
