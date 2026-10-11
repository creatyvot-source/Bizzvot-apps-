import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/models/card.dart';
import '../../../shared/models/organization.dart';
import '../domain/visibility_rules.dart';

final directoryVisibilityRepositoryProvider =
    Provider<DirectoryVisibilityRepository>(
      (ref) => DirectoryVisibilityRepository(ref.watch(apiClientProvider)),
    );

/// Organization directory setting and per-card visibility. Both fields are
/// PROPOSED additions to the profile/card contracts (plan §7.5).
class DirectoryVisibilityRepository {
  DirectoryVisibilityRepository(this._api);

  final ApiClient _api;

  /// `GET /organization/profile`
  Future<OrganizationProfile> profile() =>
      _api.get(Endpoints.profile, parse: OrganizationProfile.fromJson);

  /// `PATCH /organization/profile` with `{directoryVisibility}` only.
  Future<void> setDirectoryVisibility(DirectoryVisibility value) => _api.patch(
    Endpoints.profile,
    body: {'directoryVisibility': value.wire},
    parse: (_) {},
  );

  /// `PATCH /organization/cards/:id` with `{visibility}` only.
  Future<void> setCardVisibility(String cardId, CardVisibility value) =>
      _api.patch(
        Endpoints.card(cardId),
        body: {'visibility': value.wire},
        parse: (_) {},
      );

  /// Sequential per-card PATCHes (no bulk endpoint exists). Continues past
  /// failures and reports them; stops early on 401 or 429.
  Future<BulkResult> bulkSetVisibility(
    List<String> cardIds,
    CardVisibility value, {
    void Function(int done, int total)? onProgress,
  }) async {
    final ok = <String>[];
    final failed = <String, String>{};
    for (var i = 0; i < cardIds.length; i++) {
      final id = cardIds[i];
      try {
        await setCardVisibility(id, value);
        ok.add(id);
      } catch (e) {
        final ex = AppException.from(e);
        failed[id] = ex.message;
        if (ex.kind == AppErrorKind.unauthenticated ||
            ex.kind == AppErrorKind.rateLimited) {
          for (final rest in cardIds.skip(i + 1)) {
            failed[rest] = ex.message;
          }
          onProgress?.call(cardIds.length, cardIds.length);
          break;
        }
      }
      onProgress?.call(i + 1, cardIds.length);
    }
    return BulkResult(succeeded: ok, failed: failed);
  }
}
