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
import '../domain/qr_codes.dart';

final cardsRepositoryProvider = Provider<CardsRepository>(
  (ref) => CardsRepository(ref.watch(apiClientProvider)),
);

/// The only place the cards feature talks to the API. Request/response
/// field names are translated by [CardWire]; this class only knows paths.
class CardsRepository {
  CardsRepository(this._api);

  final ApiClient _api;

  static const _pageSize = 100;
  static const _maxPages = 50;

  // ---------------------------------------------------------------- owner

  /// `GET /organization/cards?page&limit` — follows `hasMore` so large
  /// organizations are not truncated at the default page size of 20.
  Future<List<CardModel>> listCards() async {
    final all = <CardModel>[];
    for (var page = 1; page <= _maxPages; page++) {
      final (items, hasMore) = await _api.get(
        Endpoints.cards,
        query: {'page': page, 'limit': _pageSize},
        parse: (data) {
          final items = _list(data, const ['items', 'cards', 'docs', 'results'])
              .map(CardModel.fromJson)
              .where((c) => c.id.isNotEmpty)
              .toList(growable: false);
          return (items, boolOr(asJson(data)['hasMore']));
        },
      );
      all.addAll(items);
      if (!hasMore || items.isEmpty) break;
    }
    return all;
  }

  /// `GET /organization/cards/:id`
  Future<CardModel> getCard(String id) =>
      _api.get(Endpoints.card(id), parse: _card);

  /// `POST /organization/cards` — the only way a card is created (staff
  /// creation does not create one). 403 when the plan's card limit is hit.
  Future<CardModel> createCard({
    required String title,
    String? designation,
    bool assignToAllStaff = false,
  }) =>
      _api.post(
        Endpoints.cards,
        body: CardWire.encodeCreate(
          title: title,
          designation: designation,
          assignToAllStaff: assignToAllStaff,
        ),
        parse: _card,
      );

  /// `PATCH /organization/cards/:id` with a backend body built by
  /// [CardWire.encodePatch]. Re-fetches when the card is not echoed.
  Future<CardModel> updateCard(String id, Json body) async {
    final updated = await _api.patch(
      Endpoints.card(id),
      body: body,
      parse: _cardOrNull,
    );
    return updated ?? await getCard(id);
  }

  /// Activate/disable via `PATCH /organization/cards/:id {status}` (there is
  /// no bulk status route yet).
  Future<void> setStatus(String cardId, CardStatus status) => _api.patch(
        Endpoints.card(cardId),
        body: {'status': status.name},
        parse: (_) {},
      );

  /// `DELETE /organization/cards/:id`
  Future<void> deleteCard(String id) =>
      _api.delete(Endpoints.card(id), parse: (_) {});

  // ------------------------------------------------------- shared (cards/*)

  /// `POST /cards/:id/qrcode` → PNG bytes decoded from `data.qrCodeUrl`.
  Future<Uint8List> qrCode(String cardId) async {
    final entry = await _api.post(
      Endpoints.cardQr(cardId),
      parse: (data) => data is String
          ? QrCodeEntry.fromJson({'cardId': cardId, 'url': data})
          : QrCodeEntry.fromJson({'cardId': cardId, ...asJson(data)}),
    );
    final image = await qrEntryImage(entry);
    if (image == null || image.isEmpty) {
      throw const AppException(
        AppErrorKind.unknown,
        'The QR code could not be loaded.',
      );
    }
    return image;
  }

  /// Image bytes for a QR reference. Remote URLs are fetched without
  /// credentials (tokens never leave the API host) and must be https.
  Future<Uint8List?> qrEntryImage(QrCodeEntry entry) async {
    final inline = decodeDataUrl(entry.dataUrl);
    if (inline != null) return inline;
    final url = entry.url;
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return null;
    return _api.getBytes(url, anonymous: true);
  }

  /// `GET /cards/:id/vcard` — raw `text/vcard` (404 JSON when disabled).
  Future<Uint8List> vcard(String cardId) async {
    final bytes = await _api.getBytes(Endpoints.cardVcard(cardId));
    final text = utf8.decode(bytes, allowMalformed: true).trimLeft();
    if (!text.toUpperCase().startsWith('BEGIN:VCARD')) {
      final json = _tryDecodeJson(bytes);
      if (json != _notJson) ApiClient.unwrapEnvelope(json);
      throw const AppException(
        AppErrorKind.unknown,
        'The contact file could not be created.',
      );
    }
    return bytes;
  }

  /// `POST /media/upload` (multipart field `file`; images only, ≤ 5 MB,
  /// 413 when the per-user quota is exceeded) → `data.url`.
  Future<String> uploadImage({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) =>
      _upload(
        Endpoints.mediaUpload,
        bytes,
        filename,
        mimeType,
        onProgress,
        cancelToken,
      );

  /// PROPOSED `POST /cards/:id/media` (PDF). Not in the backend yet — only
  /// reachable when `CardCapabilities.documents` is on.
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

  /// PROPOSED `DELETE /cards/:id/library {url}` (gated like documents).
  Future<void> removeLibraryFile(String cardId, String url) => _api.delete(
        Endpoints.cardLibrary(cardId),
        body: {'url': url},
        parse: (_) {},
      );

  // ---------------------------------------------------------------- staff

  /// `GET /staff/cards` — bare array of the staff member's assigned cards.
  Future<List<CardModel>> staffCards() => _api.get(
        Endpoints.staffCards,
        parse: (data) => _list(data, const ['items', 'cards'])
            .map(CardModel.fromJson)
            .where((c) => c.id.isNotEmpty)
            .toList(growable: false),
      );

  /// The staff member's card: the one matching [preferredId] (from
  /// `/auth/me`, once the backend provides it) or the first assigned card.
  /// `null` when none is assigned.
  Future<CardModel?> staffCard({String? preferredId}) async {
    final cards = await staffCards();
    if (cards.isEmpty) return null;
    return cards.firstWhere(
      (c) => c.id == preferredId,
      orElse: () => cards.first,
    );
  }

  /// `PATCH /staff/cards/:id` — body must use only backend-known keys
  /// (strict schema) and never `status`; see [CardWire.encodePatch].
  Future<CardModel> updateStaffCard(String cardId, Json body) async {
    final updated = await _api.patch(
      Endpoints.staffCardById(cardId),
      body: body,
      parse: _cardOrNull,
    );
    if (updated != null) return updated;
    final fresh = await staffCard(preferredId: cardId);
    if (fresh == null) {
      throw const AppException(
        AppErrorKind.notFound,
        'Your card could not be found.',
      );
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
    for (final k in const [
      'url',
      'secure_url',
      'secureUrl',
      'location',
      'fileUrl',
      'path',
    ]) {
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
      throw const AppException(
        AppErrorKind.notFound,
        'This card could not be found.',
      );
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
    if (first != 0x7B && first != 0x5B) return _notJson;
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return _notJson;
    }
  }
}
