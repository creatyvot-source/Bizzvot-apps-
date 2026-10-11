import 'dart:typed_data';

import '../../../shared/models/card.dart';

/// Client-side media checks. They give early feedback only; the server
/// re-validates type, signature, size and count (plan §16 Media).
abstract final class MediaRules {
  static const maxImageBytes = 5 * 1024 * 1024;
  static const maxPdfBytes = 10 * 1024 * 1024;

  static const imageMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};
  static const imageExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  /// How many more items of a kind may be added.
  static int remaining(int current, int limit) =>
      (limit - current).clamp(0, limit);

  static int remainingGallery(CardModel c) =>
      remaining(c.gallery.length, CardLimits.gallery);
  static int remainingPdfs(CardModel c) =>
      remaining(c.pdfs.length, CardLimits.pdfs);
  static int remainingVideos(CardModel c) =>
      remaining(c.videos.length, CardLimits.videos);

  /// Detects the real file type from its leading bytes. Returns a MIME type
  /// or `null` when unknown.
  static String? sniffMime(Uint8List bytes) {
    bool starts(List<int> sig, [int offset = 0]) {
      if (bytes.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (bytes[offset + i] != sig[i]) return false;
      }
      return true;
    }

    if (starts(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (starts(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'image/png';
    }
    if (starts(const [0x52, 0x49, 0x46, 0x46]) &&
        starts(const [0x57, 0x45, 0x42, 0x50], 8)) {
      return 'image/webp';
    }
    if (starts(const [0x25, 0x50, 0x44, 0x46, 0x2D])) return 'application/pdf';
    if (starts(const [0x50, 0x4B, 0x03, 0x04])) return 'application/zip';
    return null;
  }

  /// Returns an error message, or `null` when the image is acceptable.
  static String? validateImage(Uint8List bytes) {
    if (bytes.isEmpty) return 'The selected image is empty.';
    if (bytes.length > maxImageBytes) {
      return 'Images must be 5 MB or smaller.';
    }
    if (!imageMimeTypes.contains(sniffMime(bytes))) {
      return 'Use a JPG, PNG or WebP image.';
    }
    return null;
  }

  /// Returns an error message, or `null` when the PDF is acceptable.
  static String? validatePdf(Uint8List bytes) {
    if (bytes.isEmpty) return 'The selected file is empty.';
    if (bytes.length > maxPdfBytes) return 'PDFs must be 10 MB or smaller.';
    if (sniffMime(bytes) != 'application/pdf') {
      return 'Only PDF documents can be added.';
    }
    return null;
  }

  static final _ytId = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Extracts the 11-character YouTube video id from an https YouTube URL
  /// (`watch?v=`, `youtu.be/`, `shorts/`, `embed/`, `live/`), else `null`.
  static String? youtubeId(String? input) {
    final uri = Uri.tryParse(input?.trim() ?? '');
    if (uri == null || uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    String? id;
    if (host == 'youtu.be') {
      id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    } else if (host == 'youtube.com' ||
        host == 'www.youtube.com' ||
        host == 'm.youtube.com' ||
        host == 'music.youtube.com') {
      final seg = uri.pathSegments;
      if (seg.length == 1 && seg.first == 'watch') {
        id = uri.queryParameters['v'];
      } else if (seg.length >= 2 &&
          const {'shorts', 'embed', 'live', 'v'}.contains(seg.first)) {
        id = seg[1];
      }
    }
    return (id != null && _ytId.hasMatch(id)) ? id : null;
  }

  static String? validateYoutube(String? v) {
    if (v == null || v.trim().isEmpty) return 'Paste a YouTube link';
    return youtubeId(v) == null
        ? 'Enter a valid https:// YouTube video link'
        : null;
  }

  /// Links on a card must use https.
  static bool isHttpsUrl(String? v) {
    final uri = Uri.tryParse(v?.trim() ?? '');
    return uri != null && uri.scheme == 'https' && uri.host.contains('.');
  }

  static String? validateHttpsLink(String? v) {
    if (v == null || v.trim().isEmpty) return 'Link is required';
    return isHttpsUrl(v) ? null : 'Use a secure link starting with https://';
  }

  static String? optionalHttpsLink(String? v) =>
      (v == null || v.trim().isEmpty) ? null : validateHttpsLink(v);
}
