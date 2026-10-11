import 'dart:typed_data';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/utilities/json.dart';
import '../../../shared/models/card.dart';
import '../data/cards_repository.dart';
import '../data/media_picker.dart';
import '../domain/media_rules.dart';
import '../domain/qr_codes.dart';

/// Which card a shared screen (editor/share) works on: an owner-selected card
/// id, or the signed-in staff member's own card.
typedef CardRef = ({String? cardId, bool staffMode});

/// `GET /organization/cards` (owner).
final cardsListProvider = FutureProvider.autoDispose<List<CardModel>>((ref) {
  ref.watch(sessionKeyProvider);
  return ref.watch(cardsRepositoryProvider).listCards();
});

/// `GET /organization/cards/:id` (owner).
final cardDetailProvider =
    FutureProvider.autoDispose.family<CardModel, String>((ref, id) {
  ref.watch(sessionKeyProvider);
  return ref.watch(cardsRepositoryProvider).getCard(id);
});

/// The staff member's assigned card, or `null` when none is assigned.
final staffCardProvider = FutureProvider.autoDispose<CardModel?>((ref) {
  ref.watch(sessionKeyProvider);
  final knownId = ref.watch(currentUserProvider.select((u) => u?.cardId));
  return ref.watch(cardsRepositoryProvider).staffCard(knownCardId: knownId);
});

/// Resolves a [CardRef] to a card (owner → detail, staff → own card).
final cardForProvider =
    FutureProvider.autoDispose.family<CardModel?, CardRef>((ref, target) {
  if (target.staffMode) return ref.watch(staffCardProvider.future);
  final id = target.cardId;
  if (id == null || id.isEmpty) return Future.value(null);
  return ref.watch(cardDetailProvider(id).future);
});

/// QR PNG bytes for a card id.
final cardQrProvider =
    FutureProvider.autoDispose.family<Uint8List, String>((ref, cardId) {
  ref.watch(sessionKeyProvider);
  return ref.watch(cardsRepositoryProvider).qrCode(cardId);
});

final cardActionsProvider = Provider<CardActions>(CardActions.new);

/// Card mutations. Each one refreshes the caches it affects.
class CardActions {
  CardActions(this._ref);

  final Ref _ref;

  CardsRepository get _repo => _ref.read(cardsRepositoryProvider);

  Future<CardModel> save(CardRef target, String cardId, Json patch) async {
    final saved = target.staffMode
        ? await _repo.updateStaffCard(patch)
        : await _repo.updateCard(cardId, patch);
    invalidateCard(cardId);
    return saved;
  }

  Future<void> setStatus(String cardId, CardStatus status) async {
    await _repo.setStatus([cardId], status);
    invalidateCard(cardId);
  }

  Future<void> delete(String cardId) async {
    await _repo.deleteCard(cardId);
    _ref.invalidate(cardsListProvider);
  }

  /// Best-effort removal of library files no longer referenced by the card.
  /// Returns how many removals failed.
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

  /// Uploads a validated PDF to the card's media library.
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
    final bytes = await _ref.read(cardQrProvider(card.id).future);
    return ShareableFile(
      bytes: bytes,
      name: 'qr-${safeFileStem(card.slug.isEmpty ? card.displayTitle : card.slug)}.png',
      mimeType: 'image/png',
    );
  }

  /// Downloads every QR code as shareable files. A server archive is
  /// shared as-is; a JSON list is turned into one PNG per card.
  Future<({List<ShareableFile> files, int failed})> allQrFiles() async {
    final bundle = await _repo.allQrCodes();
    switch (bundle) {
      case QrArchive(:final bytes, :final mimeType, :final extension):
        return (
          files: [
            ShareableFile(
              bytes: bytes,
              name: 'bizzvot-qr-codes.$extension',
              mimeType: mimeType,
            ),
          ],
          failed: 0,
        );
      case QrEntryList(:final entries):
        final files = <ShareableFile>[];
        final usedNames = <String>{};
        var failed = 0;
        for (final e in entries) {
          try {
            final bytes = await _repo.qrEntryImage(e);
            if (bytes == null || bytes.isEmpty) {
              failed++;
              continue;
            }
            final base = safeFileStem(e.slug ?? e.name, fallback: 'card');
            var stem = base;
            for (var n = 2; !usedNames.add(stem); n++) {
              stem = '$base-$n';
            }
            files.add(ShareableFile(bytes: bytes, name: 'qr-$stem.png', mimeType: 'image/png'));
          } catch (_) {
            failed++;
          }
        }
        return (files: files, failed: failed);
    }
  }

  void invalidateCard(String cardId) {
    _ref
      ..invalidate(cardsListProvider)
      ..invalidate(cardDetailProvider(cardId))
      ..invalidate(staffCardProvider);
  }
}
