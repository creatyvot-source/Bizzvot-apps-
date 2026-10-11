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
  });

  final String slug;
  final String name;
  final String? designation;
  final String? company;
  final String? photo;

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
    );
  }
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
