import 'dart:typed_data';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/utilities/json.dart';
import '../../../shared/models/card.dart';
import '../data/cards_repository.dart';
import '../data/media_picker.dart';
import '../domain/card_capabilities.dart';
import '../domain/media_rules.dart';
import '../domain/qr_codes.dart';

/// Which card a shared screen (editor/share) works on: an owner-selected card
/// id, or the signed-in staff member's own card.
typedef CardRef = ({String? cardId, bool staffMode});

/// QR source: the card id plus its stored `qrCodeUrl` (data URL), if any.
typedef QrKey = ({String cardId, String? stored});

QrKey qrKeyOf(CardModel c) => (cardId: c.id, stored: c.qrCodeUrl);

/// `GET /organization/cards` (owner, all pages).
final cardsListProvider = FutureProvider.autoDispose<List<CardModel>>((ref) {
  ref.watch(sessionKeyProvider);
  return ref.watch(cardsRepositoryProvider).listCards();
});

/// `GET /organization/cards/:id` (owner).
final cardDetailProvider = FutureProvider.autoDispose.family<CardModel, String>(
  (ref, id) {
    ref.watch(sessionKeyProvider);
    return ref.watch(cardsRepositoryProvider).getCard(id);
  },
);

/// The staff member's assigned card (`GET /staff/cards`), or `null`.
final staffCardProvider = FutureProvider.autoDispose<CardModel?>((ref) {
  ref.watch(sessionKeyProvider);
  final preferred = ref.watch(currentUserProvider.select((u) => u?.cardId));
  return ref.watch(cardsRepositoryProvider).staffCard(preferredId: preferred);
});

/// Resolves a [CardRef] to a card (owner → detail, staff → own card).
final cardForProvider = FutureProvider.autoDispose.family<CardModel?, CardRef>(
  (ref, target) {
    if (target.staffMode) return ref.watch(staffCardProvider.future);
    final id = target.cardId;
    if (id == null || id.isEmpty) return Future.value(null);
    return ref.watch(cardDetailProvider(id).future);
  },
);

/// QR PNG bytes: the stored `qrCodeUrl` when present (no write, works for
/// staff without `editCard`), else `POST /cards/:id/qrcode`.
final cardQrProvider = FutureProvider.autoDispose.family<Uint8List, QrKey>((
  ref,
  key,
) async {
  ref.watch(sessionKeyProvider);
  final stored = decodeDataUrl(key.stored);
  if (stored != null && stored.isNotEmpty) return stored;
  return ref.watch(cardsRepositoryProvider).qrCode(key.cardId);
});

final cardActionsProvider = Provider<CardActions>(CardActions.new);

/// Card mutations. Each one refreshes the caches it affects.
class CardActions {
  CardActions(this._ref);

  final Ref _ref;

  CardsRepository get _repo => _ref.read(cardsRepositoryProvider);

  /// Saves an app-level [patch] (see `buildCardPatch`). The wire body is
  /// produced by [CardWire]; returns [edited] unchanged when nothing the
  /// backend stores was changed.
  Future<CardModel> save(CardRef target, CardModel edited, Json patch) async {
    final body = CardWire.encodePatch(
      patch,
      edited,
      staff: target.staffMode,
      enabled: _ref.read(cardCapabilitiesProvider).enabledFields,
    );
    if (body.isEmpty) return edited;
    final saved = target.staffMode
        ? await _repo.updateStaffCard(edited.id, body)
        : await _repo.updateCard(edited.id, body);
    invalidateCard(edited.id);
    return saved;
  }

  Future<CardModel> create({required String title, String? designation}) async {
    final card = await _repo.createCard(title: title, designation: designation);
    _ref.invalidate(cardsListProvider);
    return card;
  }

  Future<void> setStatus(String cardId, CardStatus status) async {
    await _repo.setStatus(cardId, status);
    invalidateCard(cardId);
  }

  Future<void> delete(String cardId) async {
    await _repo.deleteCard(cardId);
    _ref.invalidate(cardsListProvider);
  }

  /// Best-effort removal of library files no longer referenced by the card.
  /// Returns how many removals failed. Only used when documents are enabled.
  Future<int> removeLibraryFiles(String cardId, Iterable<String> urls) async {
    var failed = 0;
    for (final url in urls) {
      try {
        await _repo.removeLibraryFile(cardId, url);
      } catch (_) {
        failed++;
      }
    }
    return failed;
  }

  /// Uploads a validated image (see [MediaRules.validateImage]) and returns
  /// its URL.
  Future<String> uploadImage(
    PickedFile file, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) {
    final mime = MediaRules.sniffMime(file.bytes) ?? 'image/jpeg';
    final ext = switch (mime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    return _repo.uploadImage(
      bytes: file.bytes,
      filename: '${safeFileStem(_stem(file.name), fallback: 'image')}.$ext',
      mimeType: mime,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// Uploads a validated PDF to the card's media library (PROPOSED route).
  Future<String> uploadDocument(
    String cardId,
    PickedFile file, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) =>
      _repo.uploadCardDocument(
        cardId,
        bytes: file.bytes,
        filename: '${safeFileStem(_stem(file.name), fallback: 'document')}.pdf',
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

  static String _stem(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// The card's contact file (`GET /cards/:id/vcard`) ready to share.
  Future<ShareableFile> vcardFile(CardModel card) async {
    final bytes = await _repo.vcard(card.id);
    return ShareableFile(
      bytes: bytes,
      name: '${safeFileStem(card.displayTitle, fallback: 'contact')}.vcf',
      mimeType: 'text/vcard',
    );
  }

  /// The card's QR PNG, reusing the cached image when already loaded.
  Future<ShareableFile> qrFile(CardModel card) async {
    final bytes = await _ref.read(cardQrProvider(qrKeyOf(card)).future);
    return _qrShareable(card, bytes);
  }

  /// Every card's QR code as PNG files. There is no bulk endpoint, so each
  /// card's stored `qrCodeUrl` is used, falling back to generating it.
  Future<({List<ShareableFile> files, int failed})> allQrFiles() async {
    final cards = await _repo.listCards();
    final files = <ShareableFile>[];
    final usedNames = <String>{};
    var failed = 0;
    for (final card in cards) {
      try {
        final bytes =
            decodeDataUrl(card.qrCodeUrl) ?? await _repo.qrCode(card.id);
        if (bytes.isEmpty) {
          failed++;
          continue;
        }
        final base = _qrShareable(card, bytes).name;
        var name = base;
        for (var n = 2; !usedNames.add(name); n++) {
          name = base.replaceFirst('.png', '-$n.png');
        }
        files.add(
          ShareableFile(bytes: bytes, name: name, mimeType: 'image/png'),
        );
      } catch (_) {
        failed++;
      }
    }
    return (files: files, failed: failed);
  }

  static ShareableFile _qrShareable(CardModel card, Uint8List bytes) =>
      ShareableFile(
        bytes: bytes,
        name:
            'qr-${safeFileStem(card.slug.isEmpty ? card.displayTitle : card.slug)}.png',
        mimeType: 'image/png',
      );

  void invalidateCard(String cardId) {
    _ref
      ..invalidate(cardsListProvider)
      ..invalidate(cardDetailProvider(cardId))
      ..invalidate(staffCardProvider);
  }
}
