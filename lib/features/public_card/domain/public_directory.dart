import '../../../core/utilities/json.dart';
import '../../../shared/models/paged.dart';

/// One person in a public organization directory. Public allow-list only.
class DirectoryEntry {
  const DirectoryEntry({
    required this.slug,
    required this.name,
    this.designation,
    this.company,
    this.photo,
    this.phone,
    this.whatsapp,
    this.email,
    this.badge,
  });

  final String slug;
  final String name;
  final String? designation;
  final String? company;
  final String? photo;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? badge;

  factory DirectoryEntry.fromJson(Object? raw) {
    final j = asJson(raw);
    final card = j['card'] is Map ? asJson(j['card']) : j;
    return DirectoryEntry(
      slug: strOr(card['slug'] ?? j['slug']),
      name:
          str(card['title']) ??
          str(card['name']) ??
          str(j['name']) ??
          'Team member',
      designation: str(card['designation']) ?? str(j['designation']),
      company: str(card['company']),
      photo:
          str(card['profilePhoto']) ??
          str(card['photo']) ??
          str(j['profilePhoto']),
      phone: str(card['phone'] ?? j['phone'] ?? card['mobile']),
      whatsapp: str(card['whatsapp'] ?? j['whatsapp']),
      email: str(card['email'] ?? j['email']),
      badge: str(card['badge'] ?? j['badge']),
    );
  }

  static const defaultEntries = [
    DirectoryEntry(
      slug: 'muhammed-kc',
      name: 'Muhammed KC',
      designation: 'Founder & CEO',
      company: 'Bizzvot Technologies',
      photo: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400&auto=format&fit=crop&q=80',
      phone: '+91 89215 04090',
      whatsapp: '+91 89215 04090',
      email: 'muhammed@bizzvot.com',
      badge: 'Owner / Executive',
    ),
    DirectoryEntry(
      slug: 'sarah-jenkins',
      name: 'Sarah Jenkins',
      designation: 'Head of Business Development',
      company: 'Bizzvot Technologies',
      photo: 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=400&auto=format&fit=crop&q=80',
      phone: '+91 89215 04090',
      whatsapp: '+91 89215 04090',
      email: 'sarah@bizzvot.com',
      badge: 'Staff Card',
    ),
    DirectoryEntry(
      slug: 'alex-rivera',
      name: 'Alex Rivera',
      designation: 'Principal Solutions Architect',
      company: 'Apex Cloud Systems',
      photo: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&auto=format&fit=crop&q=80',
      phone: '+91 99613 03300',
      whatsapp: '+91 99613 03300',
      email: 'alex@apexcloud.io',
      badge: 'Verified Member',
    ),
    DirectoryEntry(
      slug: 'priya-sharma',
      name: 'Priya Sharma',
      designation: 'Chief Marketing Officer',
      company: 'Lumina Retail Group',
      photo: 'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=400&auto=format&fit=crop&q=80',
      phone: '+91 89215 04090',
      whatsapp: '+91 89215 04090',
      email: 'priya@luminagroup.in',
      badge: 'Enterprise Partner',
    ),
    DirectoryEntry(
      slug: 'rohit-menon',
      name: 'Rohit Menon',
      designation: 'Regional Reseller Director',
      company: 'BizzVcard South Network',
      photo: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400&auto=format&fit=crop&q=80',
      phone: '+91 89215 04090',
      whatsapp: '+91 89215 04090',
      email: 'rohit@bizzvcard.com',
      badge: '30% Reseller Lead',
    ),
  ];
}

/// `GET /public/organizations/:slug/directory` (PROPOSED).
///
/// The server is responsible for filtering out private entries; the app
/// renders exactly what it receives (entries without a slug are skipped
/// only because they cannot be opened).
class PublicDirectoryPage {
  const PublicDirectoryPage({
    required this.entries,
    this.organizationName,
    this.organizationLogo,
    this.page = 1,
    this.hasMore = false,
  });

  final String? organizationName;
  final String? organizationLogo;
  final List<DirectoryEntry> entries;
  final int page;
  final bool hasMore;

  factory PublicDirectoryPage.fromJson(Object? data) {
    final j = asJson(data);
    final org = asJson(j['organization'] ?? j['org']);
    final paged = Paged.parse(
      data,
      DirectoryEntry.fromJson,
      listKeys: const [
        'items',
        'entries',
        'people',
        'members',
        'cards',
        'docs',
        'results',
        'data',
      ],
    );
    return PublicDirectoryPage(
      organizationName: str(org['name']) ?? str(j['organizationName']),
      organizationLogo: str(org['logo']) ?? str(j['organizationLogo']),
      entries: paged.items
          .where((e) => e.slug.isNotEmpty)
          .toList(growable: false),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }
}
