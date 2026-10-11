import '../../../core/utilities/validators.dart';

/// Builds launchable URIs for public card actions. Every builder returns
/// `null` for input that is empty or would produce an unsafe link, so the
/// UI can simply hide the action.
abstract final class ContactLinks {
  static Uri? tel(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 3 || digits.length > 20) return null;
    return Uri(
      scheme: 'tel',
      path: trimmed.startsWith('+') ? '+$digits' : digits,
    );
  }

  /// `https://wa.me/<digits>` — WhatsApp expects the international number
  /// without `+`, spaces or punctuation.
  static Uri? whatsapp(String? raw) {
    if (raw == null) return null;
    final existing = web(raw);
    if (existing != null &&
        (existing.host == 'wa.me' || existing.host == 'api.whatsapp.com')) {
      return existing;
    }
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return Uri.https('wa.me', '/$digits');
  }

  static Uri? mailto(String? raw) {
    if (raw == null) return null;
    final email = raw.trim();
    if (Validators.email(email) != null) return null;
    return Uri(scheme: 'mailto', path: email);
  }

  /// http(s) only. A bare host such as `example.com` is upgraded to https.
  static Uri? web(String? raw) {
    if (raw == null) return null;
    var v = raw.trim();
    if (v.isEmpty || v.contains(RegExp(r'\s'))) return null;
    if (!v.contains('://') && !v.contains(':')) v = 'https://$v';
    if (!Validators.isSafeWebUrl(v)) return null;
    return Uri.parse(v);
  }

  /// Uses the card's map link when it is a safe web URL, otherwise a Google
  /// Maps search for the address.
  static Uri? map({String? mapLink, String? address}) {
    final link = web(mapLink);
    if (link != null) return link;
    final a = address?.trim();
    if (a == null || a.isEmpty) return null;
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': a,
    });
  }

  /// Schemes the app is ever allowed to open.
  static bool isAllowed(Uri uri) => switch (uri.scheme) {
    'http' || 'https' => uri.host.isNotEmpty,
    'tel' || 'mailto' => uri.path.isNotEmpty,
    _ => false,
  };
}
