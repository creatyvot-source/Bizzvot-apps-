/// Public-card content sections that can be reordered and toggled.
///
/// The keys are written to `sectionOrder` / `displayToggles` (assumed
/// contract — confirm with backend). Unknown keys from the server are kept.
abstract final class DisplaySections {
  static const defaults = <String>[
    'contact',
    'social',
    'links',
    'gallery',
    'videos',
    'documents',
    'reviews',
  ];

  static const _labels = {
    'contact': 'Contact actions',
    'social': 'Social links',
    'links': 'Custom links',
    'gallery': 'Gallery',
    'videos': 'Videos',
    'documents': 'Documents (PDF)',
    'reviews': 'Reviews',
    'about': 'About / bio',
  };

  static String label(String key) {
    final known = _labels[key];
    if (known != null) return known;
    if (key.isEmpty) return key;
    return key[0].toUpperCase() + key.substring(1).replaceAll('_', ' ');
  }

  /// Server order first (duplicates removed), then any missing defaults.
  static List<String> merge(List<String> serverOrder) {
    final seen = <String>{};
    final result = <String>[];
    for (final k in [...serverOrder, ...defaults]) {
      if (k.isNotEmpty && seen.add(k)) result.add(k);
    }
    return result;
  }

  /// A section is shown unless explicitly toggled off.
  static bool isVisible(Map<String, bool> toggles, String key) =>
      toggles[key] ?? true;
}
