import '../../../shared/models/card.dart';

/// Public-card section order (`theme.sectionOrder`) and show/hide switches
/// (`displayOptions`), using the backend keys from [CardWire].
abstract final class DisplaySections {
  static const defaults = CardWire.sectionKeys;

  static const _labels = {
    'bio': 'Bio',
    'contacts': 'Contact details',
    'socials': 'Social links',
    'customLinks': 'Custom links',
  };

  static const optionLabels = {
    'showBio': 'Bio',
    'showSocials': 'Social links',
    'showAddress': 'Address',
    'showWhatsapp': 'WhatsApp button',
    'showCustomLinks': 'Custom links',
    'showReviews': 'Reviews',
  };

  static String label(String key) {
    final known = _labels[key] ?? optionLabels[key];
    if (known != null) return known;
    if (key.isEmpty) return key;
    return key[0].toUpperCase() + key.substring(1).replaceAll('_', ' ');
  }

  /// Known server order first (duplicates and unknown keys removed), then
  /// any missing defaults.
  static List<String> merge(List<String> serverOrder) {
    final seen = <String>{};
    final result = <String>[];
    for (final k in [...serverOrder, ...defaults]) {
      if (defaults.contains(k) && seen.add(k)) result.add(k);
    }
    return result;
  }

  /// A display option is on unless explicitly switched off.
  static bool isVisible(Map<String, bool> toggles, String key) =>
      toggles[key] ?? true;
}
