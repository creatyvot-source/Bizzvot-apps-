import 'dart:convert';
import 'dart:typed_data';

import '../../../core/utilities/json.dart';

/// A QR image reference: the `POST /cards/:id/qrcode` response
/// `{qrCodeUrl: 'data:image/png;base64,…', publicUrl}`, or a card's stored
/// `qrCodeUrl`. A remote https `url` is tolerated for forward compatibility.
class QrCodeEntry {
  const QrCodeEntry({
    required this.cardId,
    this.name,
    this.slug,
    this.url,
    this.dataUrl,
    this.publicUrl,
  });

  final String cardId;
  final String? name;
  final String? slug;

  /// Remote https image URL.
  final String? url;

  /// `data:image/png;base64,...`
  final String? dataUrl;

  /// The card URL encoded in the QR (server `NEXT_PUBLIC_APP_URL` based).
  final String? publicUrl;

  factory QrCodeEntry.fromJson(Object? raw) {
    final j = asJson(raw);
    final card = asJson(j['card']);
    String? url = str(j['url']) ?? str(j['qrCodeUrl']) ?? str(j['image']);
    String? dataUrl = str(j['dataUrl']) ?? str(j['qrCode']) ?? str(j['qr']);
    // Some APIs put a data URL in `url` or a remote URL in `qrCode`.
    if (url != null && url.startsWith('data:')) {
      dataUrl ??= url;
      url = null;
    }
    if (dataUrl != null && !dataUrl.startsWith('data:')) {
      url ??= dataUrl;
      dataUrl = null;
    }
    return QrCodeEntry(
      cardId: str(j['cardId']) ?? (card.isEmpty ? idOf(j) : idOf(card)),
      name: str(j['name']) ?? str(j['title']) ?? str(card['title']),
      slug: str(j['slug']) ?? str(card['slug']),
      url: url,
      dataUrl: dataUrl,
      publicUrl: str(j['publicUrl']),
    );
  }

  bool get hasImage => url != null || dataUrl != null;
}

/// Decodes a base64 `data:` URL. Returns `null` when malformed.
Uint8List? decodeDataUrl(String? dataUrl) {
  if (dataUrl == null || !dataUrl.startsWith('data:')) return null;
  final comma = dataUrl.indexOf(',');
  if (comma < 0 || !dataUrl.substring(0, comma).contains(';base64')) {
    return null;
  }
  try {
    return base64Decode(dataUrl.substring(comma + 1).trim());
  } on FormatException {
    return null;
  }
}

/// A ready-to-share file (QR PNG, vCard, archive).
class ShareableFile {
  const ShareableFile({
    required this.bytes,
    required this.name,
    required this.mimeType,
  });
  final Uint8List bytes;
  final String name;
  final String mimeType;
}

/// File-name safe slug for exported files.
String safeFileStem(String? input, {String fallback = 'card'}) {
  final s = (input ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (s.isEmpty) return fallback;
  return s.length > 60 ? s.substring(0, 60) : s;
}
