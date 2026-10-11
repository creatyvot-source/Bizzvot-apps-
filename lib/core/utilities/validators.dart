/// Form validators. Server validation is authoritative; these only give
/// early feedback.
abstract final class Validators {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final _phone = RegExp(r'^\+?[0-9 ()-]{7,20}$');

  static String? required(String? v, [String field = 'This field']) =>
      (v == null || v.trim().isEmpty) ? '$field is required' : null;

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    return _email.hasMatch(v.trim()) ? null : 'Enter a valid email address';
  }

  static String? optionalEmail(String? v) =>
      (v == null || v.trim().isEmpty) ? null : email(v);

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Use at least 8 characters';
    return null;
  }

  static String? optionalPhone(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return _phone.hasMatch(v.trim()) ? null : 'Enter a valid phone number';
  }

  /// http/https only — rejects `javascript:`, `data:`, `file:` etc.
  static String? optionalUrl(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return isSafeWebUrl(v.trim()) ? null : 'Enter a valid https:// link';
  }

  static bool isSafeWebUrl(String v) {
    final uri = Uri.tryParse(v);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  static String? hexColor(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return RegExp(r'^#([0-9a-fA-F]{6})$').hasMatch(v.trim())
        ? null
        : 'Use a hex color like #1F4FD8';
  }
}
