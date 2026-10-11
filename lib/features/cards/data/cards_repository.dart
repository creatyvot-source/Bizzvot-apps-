import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utilities/json.dart';
import '../../../shared/models/card.dart';
import '../domain/media_rules.dart';
import '../domain/qr_codes.dart';

final cardsRepositoryProvider = Provider<CardsRepository>(
  (ref) => CardsRepository(ref.watch(apiClientProvider)),
);

/// The only place the cards feature talks to the API.
///
/// Response shapes are parsed defensively: list endpoints may return a bare
/// array or `{cards|items|docs: [...]}`; detail endpoints may return the card
/// or `{card: {...}}`.
class CardsRepository {
  CardsRepository(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------- owner

  /// `GET /organization/cards`
  Future<List<CardModel>> listCards() => _api.get(
        Endpoints.cards,
        parse: (data) => _list(data, const ['cards', 'items', 'docs', 'results'])
            .map(CardModel.fromJson)
            .where((c) => c.id.isNotEmpty)
            .toList(growable: false),
      );

  /// `GET /organization/cards/:id`
  Future<CardModel> getCard(String id) =>
      _api.get(Endpoints.card(id), parse: _card);

  /// `PATCH /organization/cards/:id` with only the changed editable fields.
  /// Falls back to a re-fetch when the response does not echo the card.
  Future<CardModel> updateCard(String id, Json patch) async {
    final updated = await _api.patch(
      Endpoints.card(id),
      body: patch,
      parse: _cardOrNull,
    );
    return updated ?? await getCard(id);
  }

  /// `PATCH /organization/cards/status` — assumed body
  /// `{cardIds: [..], status: 'active'|'disabled'}`.
  /// Activation outside the trial consumes a paid slot; the server answers
  /// 403/409 (or 402) when no eligible slot exists.
  Future<void> setStatus(List<String> cardIds, CardStatus status) => _api.patch(
        Endpoints.cardStatus,
        body: {'cardIds': cardIds, 'status': status.name},
        parse: (_) {},
      );

  /// `DELETE /organization/cards/:id`
  Future<void> deleteCard(String id) =>
      _api.delete(Endpoints.card(id), parse: (_) {});

  /// `GET /organization/cards/qrcodes` — accepts a JSON list (entries with
  /// `url` or `dataUrl`) or a binary ZIP/PNG/PDF.
  Future<QrBundle> allQrCodes() async {
    final bytes = await _api.getBytes(Endpoints.allQrCodes);
    final json = _tryDecodeJson(bytes);
    if (json != _notJson) {
      final data = ApiClient.unwrapEnvelope(json);
      final entries = _list(data, const ['qrcodes', 'qrCodes', 'items', 'cards'])
          .map(QrCodeEntry.fromJson)
          .where((e) => e.hasImage)
          .toList(growable: false);
      return QrEntryList(entries);
    }
    final mime = MediaRules.sniffMime(bytes);
    return switch (mime) {
      'application/zip' =>
        QrArchive(bytes, mimeType: 'application/zip', extension: 'zip'),
      'application/pdf' =>
        QrArchive(bytes, mimeType: 'application/pdf', extension: 'pdf'),
      'image/png' => QrArchive(bytes, mimeType: 'image/png', extension: 'png'),
      _ => throw const AppException(
          AppErrorKind.unknown,
          'QR codes could not be prepared. Please try again.',
        ),
    };
  }

  /// Downloads the image for one entry of [allQrCodes]. Remote URLs are
  /// fetched without credentials so tokens never leave the API host.
  Future<Uint8List?> qrEntryImage(QrCodeEntry entry) async {
    final inline = decodeDataUrl(entry.dataUrl);
    if (inline != null) return inline;
    final url = entry.url;
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return null;
    return _api.getBytes(url, anonymous: true);
  }

  // ------------------------------------------------------- shared (cards/*)

  /// `GET /cards/:id/qrcode` — PNG bytes. Tolerates a JSON body carrying a
  /// data URL (`{qrCode: 'data:image/png;base64,...'}`).
  Future<Uint8List> qrCode(String cardId) async {
    final bytes = await _api.getBytes(Endpoints.cardQr(cardId));
    final json = _tryDecodeJson(bytes);
    if (json == _notJson) return bytes;
    final data = ApiClient.unwrapEnvelope(json);
    final entry = data is String
        ? QrCodeEntry.fromJson({'cardId': cardId, 'url': data})
        : QrCodeEntry.fromJson(data);
    final image = await qrEntryImage(entry);
    if (image == null || image.isEmpty) {
      throw const AppException(AppErrorKind.unknown, 'The QR code could not be loaded.');
    }
    return image;
  }

  /// `GET /cards/:id/vcard` — `text/vcard` bytes.
  Future<Uint8List> vcard(String cardId) async {
    final bytes = await _api.getBytes(Endpoints.cardVcard(cardId));
    final text = utf8.decode(bytes, allowMalformed: true).trimLeft();
    if (!text.toUpperCase().startsWith('BEGIN:VCARD')) {
      // A JSON envelope with an error or an unexpected body.
      final json = _tryDecodeJson(bytes);
      if (json != _notJson) ApiClient.unwrapEnvelope(json);
      throw const AppException(
        AppErrorKind.unknown,
        'The contact file could not be created.',
      );
    }
    return bytes;
  }

  /// `POST /media/upload` (multipart field `file`) → public URL.
  Future<String> uploadImage({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) =>
      _upload(Endpoints.mediaUpload, bytes, filename, mimeType, onProgress, cancelToken);

  /// `POST /cards/:id/media` (multipart field `file`) → URL of the stored
  /// document. Used for PDFs so they are associated with the card library.
  Future<String> uploadCardDocument(
    String cardId, {
    required Uint8List bytes,
    required String filename,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) =>
      _upload(
        Endpoints.cardMedia(cardId),
        bytes,
        filename,
        'application/pdf',
        onProgress,
        cancelToken,
      );

  /// `DELETE /cards/:id/library` with body `{url}`.
  Future<void> removeLibraryFile(String cardId, String url) => _api.delete(
        Endpoints.cardLibrary(cardId),
        body: {'url': url},
        parse: (_) {},
      );

  // ---------------------------------------------------------------- staff

  /// PROPOSED `GET /staff/card`. Returns `null` when no card is assigned
  /// (`data: null`, or 404 while `/auth/me` reports no card).
  Future<CardModel?> staffCard({String? knownCardId}) async {
    try {
      return await _api.get(Endpoints.staffCard, parse: _cardOrNull);
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.notFound && knownCardId == null) return null;
      rethrow;
    }
  }

  /// PROPOSED `PATCH /staff/card` with fields the staff member may edit.
  Future<CardModel> updateStaffCard(Json patch) async {
    final updated = await _api.patch(
      Endpoints.staffCard,
      body: patch,
      parse: _cardOrNull,
    );
    if (updated != null) return updated;
    final fresh = await staffCard();
    if (fresh == null) {
      throw const AppException(AppErrorKind.notFound, 'Your card could not be found.');
    }
    return fresh;
  }

  // -------------------------------------------------------------- helpers

  Future<String> _upload(
    String path,
    Uint8List bytes,
    String filename,
    String mimeType,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  ) =>
      _api.upload(
        path,
        form: FormData.fromMap({
          'file': MultipartFile.fromBytes(
            bytes,
            filename: filename,
            contentType: DioMediaType.parse(mimeType),
          ),
        }),
        onProgress: onProgress,
        cancelToken: cancelToken,
        parse: (data) {
          final url = uploadedUrl(data);
          if (url == null) {
            throw const AppException(
              AppErrorKind.unknown,
              'The upload finished but no file link was returned.',
            );
          }
          return url;
        },
      );

  /// Finds the stored file URL in an upload response: a bare string,
  /// `{url|secure_url|location|path}`, nested under `file|media|data`, or a
  /// card whose `pdfs` list ends with the new document.
  static String? uploadedUrl(Object? data) {
    if (data is String) return data.isEmpty ? null : data;
    final j = asJson(data);
    if (j.isEmpty) return null;
    for (final k in const ['url', 'secure_url', 'secureUrl', 'location', 'fileUrl', 'path']) {
      final v = str(j[k]);
      if (v != null) return v;
    }
    for (final k in const ['file', 'media', 'data', 'document']) {
      final nested = uploadedUrl(j[k]);
      if (nested != null) return nested;
    }
    for (final k in const ['pdfs', 'documents', 'files']) {
      final list = j[k];
      if (list is List && list.isNotEmpty) {
        final last = MediaItem.fromJson(list.last).url;
        if (last.isNotEmpty) return last;
      }
    }
    return null;
  }

  static CardModel _card(Object? data) {
    final c = _cardOrNull(data);
    if (c == null) {
      throw const AppException(AppErrorKind.notFound, 'This card could not be found.');
    }
    return c;
  }

  static CardModel? _cardOrNull(Object? data) {
    final j = asJson(data);
    final inner = j['card'] is Map ? asJson(j['card']) : j;
    if (inner.isEmpty) return null;
    final card = CardModel.fromJson(inner);
    return card.id.isEmpty ? null : card;
  }

  static List<Object?> _list(Object? data, List<String> keys) {
    if (data is List) return data;
    final j = asJson(data);
    for (final k in keys) {
      if (j[k] case final List<Object?> list) return list;
    }
    return const [];
  }

  static const _notJson = Object();

  static Object? _tryDecodeJson(Uint8List bytes) {
    if (bytes.isEmpty) return _notJson;
    final first = bytes.first;
    // `{` or `[` (allowing leading whitespace would accept rare binaries).
    if (first != 0x7B && first != 0x5B) return _notJson;
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return _notJson;
    }
  }
}
