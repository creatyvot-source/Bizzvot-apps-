import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/qr_codes.dart';

/// Share sheet, clipboard and temp-file plumbing behind an interface so
/// widget tests can verify intent without platform channels.
abstract class ShareService {
  Future<void> shareText(String text, {String? subject, Rect? origin});

  /// Writes [files] to the app's temporary directory and opens the share
  /// sheet with them.
  Future<void> shareFiles(List<ShareableFile> files, {String? text, Rect? origin});

  Future<void> copyText(String text);
}

final shareServiceProvider = Provider<ShareService>((ref) => PlatformShareService());

class PlatformShareService implements ShareService {
  @override
  Future<void> shareText(String text, {String? subject, Rect? origin}) =>
      SharePlus.instance.share(
        ShareParams(text: text, subject: subject, sharePositionOrigin: origin),
      );

  @override
  Future<void> shareFiles(
    List<ShareableFile> files, {
    String? text,
    Rect? origin,
  }) async {
    if (files.isEmpty) return;
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/bizzvot_share');
    if (await dir.exists()) {
      // Previous exports may contain personal data (vCards); clean up.
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    final xfiles = <XFile>[];
    for (final f in files) {
      final file = File('${dir.path}/${f.name}');
      await file.writeAsBytes(f.bytes, flush: true);
      xfiles.add(XFile(file.path, mimeType: f.mimeType, name: f.name));
    }
    await SharePlus.instance.share(
      ShareParams(files: xfiles, text: text, sharePositionOrigin: origin),
    );
  }

  @override
  Future<void> copyText(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}
