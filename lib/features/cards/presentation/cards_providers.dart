import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/utilities/json.dart';
import '../../../shared/models/card.dart';
import '../data/cards_repository.dart';

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

  void invalidateCard(String cardId) {
    _ref
      ..invalidate(cardsListProvider)
      ..invalidate(cardDetailProvider(cardId))
      ..invalidate(staffCardProvider);
  }
}
