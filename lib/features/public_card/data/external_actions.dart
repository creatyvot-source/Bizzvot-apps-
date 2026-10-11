import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/contact_links.dart';

/// Platform side effects (launch a link, open the share sheet). Kept behind
/// a provider so widget tests can substitute a fake.
abstract class ExternalActions {
  /// Opens [uri] in the appropriate external app. Returns false when the
  /// scheme is not allowed or nothing can handle it.
  Future<bool> open(Uri uri);

  Future<void> shareText(String text, {String? subject, Rect? origin});

  /// Writes [bytes] to a temporary file and opens the share sheet for it.
  Future<void> shareFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? subject,
    Rect? origin,
  });
}

class PlatformExternalActions implements ExternalActions {
  const PlatformExternalActions();

  @override
  Future<bool> open(Uri uri) async {
    // Defense in depth: only http(s), tel and mailto are ever launched.
    if (!ContactLinks.isAllowed(uri)) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) async {
    await SharePlus.instance.share(
      ShareParams(text: text, subject: subject, sharePositionOrigin: origin),
    );
  }

  @override
  Future<void> shareFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? subject,
    Rect? origin,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: fileName)],
        subject: subject,
        sharePositionOrigin: origin,
      ),
    );
  }
}

final externalActionsProvider = Provider<ExternalActions>(
  (ref) => const PlatformExternalActions(),
);

/// Safe file name for a downloaded vCard, e.g. `Jane_Doe.vcf`.
String vcardFileName(String? name) {
  final base = (name ?? '')
      .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_');
  final safe = base.isEmpty
      ? 'contact'
      : (base.length > 40 ? base.substring(0, 40) : base);
  return '$safe.vcf';
}
