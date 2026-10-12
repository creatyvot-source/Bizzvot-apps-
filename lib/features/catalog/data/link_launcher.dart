import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utilities/validators.dart';
import '../domain/commerce_models.dart';

/// Opens external links for commerce flows. Behind a provider so widget tests
/// can substitute a fake (platform channels are unavailable there).
class LinkLauncher {
  const LinkLauncher();

  /// Opens a hosted checkout page in the external browser. Only absolute
  /// `https` URLs are accepted; anything else returns false unopened.
  Future<bool> openCheckout(String? url) => _openHttps(url);

  /// Opens an invoice PDF or other document (https only).
  Future<bool> openDocument(String? url) => _openHttps(url);

  /// Opens an http(s) informational link (terms, support pages).
  Future<bool> openWeb(String? url) async {
    if (url == null || !Validators.isSafeWebUrl(url)) return false;
    return _launch(Uri.parse(url));
  }

  Future<bool> email(String address, {String? subject}) {
    if (Validators.email(address) != null) return Future.value(false);
    return _launch(
      Uri(
        scheme: 'mailto',
        path: address.trim(),
        query: subject == null
            ? null
            : 'subject=${Uri.encodeComponent(subject)}',
      ),
    );
  }

  Future<bool> call(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.length < 5) return Future.value(false);
    return _launch(Uri(scheme: 'tel', path: cleaned));
  }

  Future<bool> whatsapp(String phone, {String? text}) {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.length < 5) return Future.value(false);
    final uri = Uri.parse(
      'https://wa.me/$cleaned${text != null && text.isNotEmpty ? '?text=${Uri.encodeComponent(text)}' : ''}',
    );
    return _launch(uri);
  }

  Future<void> shareText(String text, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }

  Future<bool> _openHttps(String? url) {
    final uri = safeHttpsUri(url);
    if (uri == null) return Future.value(false);
    return _launch(uri);
  }

  Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

final linkLauncherProvider = Provider<LinkLauncher>(
  (ref) => const LinkLauncher(),
);
