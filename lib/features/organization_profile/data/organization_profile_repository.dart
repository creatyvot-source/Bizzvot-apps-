import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/providers.dart';
import '../../../core/utilities/json.dart';
import '../../../shared/models/organization.dart';

/// `GET` / `PATCH /organization/profile`.
class OrganizationProfileRepository {
  OrganizationProfileRepository(this._api);

  final ApiClient _api;

  Future<OrganizationProfile> fetch() =>
      _api.get(Endpoints.profile, parse: OrganizationProfile.fromJson);

  /// Sends only [changes]. If the response does not carry the updated
  /// profile, it is re-fetched so the UI never shows stale values.
  Future<OrganizationProfile> update(Json changes) async {
    final updated = await _api.patch<OrganizationProfile?>(
      Endpoints.profile,
      body: changes,
      parse: parseUpdatedProfile,
    );
    return updated ?? await fetch();
  }

  /// Accepts `{ organization: {...} }` or a flat profile; `null` when the
  /// body is empty or only an acknowledgement.
  static OrganizationProfile? parseUpdatedProfile(Object? data) {
    var j = asJson(data);
    if (j['organization'] is Map) j = asJson(j['organization']);
    if (str(j['name']) == null) return null;
    return OrganizationProfile.fromJson(j);
  }
}

final organizationProfileRepositoryProvider =
    Provider<OrganizationProfileRepository>(
  (ref) => OrganizationProfileRepository(ref.watch(apiClientProvider)),
);
