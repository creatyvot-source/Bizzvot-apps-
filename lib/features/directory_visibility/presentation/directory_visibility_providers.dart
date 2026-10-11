import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../shared/models/card.dart';
import '../../../shared/models/organization.dart';
import '../../../core/config/app_config.dart';
import '../../cards/domain/card_capabilities.dart';
import '../../cards/presentation/cards_providers.dart';
import '../data/directory_visibility_repository.dart';
import '../domain/visibility_rules.dart';

/// True only when the backend stores directory/card visibility (capability
/// flag) and the directory feature is not switched off remotely.
final directoryAvailableProvider = Provider<bool>(
  (ref) =>
      ref.watch(cardCapabilitiesProvider).visibility &&
      ref.watch(currentConfigProvider).isEnabled(Flags.directory),
);

/// Organization profile (for `directoryVisibility` and `slug`).
final directoryProfileProvider =
    FutureProvider.autoDispose<OrganizationProfile>((ref) {
      ref.watch(sessionKeyProvider);
      return ref.watch(directoryVisibilityRepositoryProvider).profile();
    });

final directoryActionsProvider = Provider<DirectoryActions>(
  DirectoryActions.new,
);

class DirectoryActions {
  DirectoryActions(this._ref);

  final Ref _ref;

  DirectoryVisibilityRepository get _repo =>
      _ref.read(directoryVisibilityRepositoryProvider);

  Future<void> setDirectoryVisibility(DirectoryVisibility value) async {
    await _repo.setDirectoryVisibility(value);
    _ref.invalidate(directoryProfileProvider);
  }

  Future<void> setCardVisibility(String cardId, CardVisibility value) async {
    await _repo.setCardVisibility(cardId, value);
    _ref.read(cardActionsProvider).invalidateCard(cardId);
  }

  Future<BulkResult> bulkSetVisibility(
    List<String> cardIds,
    CardVisibility value, {
    void Function(int done, int total)? onProgress,
  }) async {
    final result = await _repo.bulkSetVisibility(
      cardIds,
      value,
      onProgress: onProgress,
    );
    final cards = _ref.read(cardActionsProvider);
    for (final id in result.succeeded) {
      cards.invalidateCard(id);
    }
    return result;
  }
}
