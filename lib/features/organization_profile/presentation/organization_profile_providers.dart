import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/utilities/json.dart';
import '../../../shared/models/organization.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../data/organization_profile_repository.dart';

/// The signed-in owner's organization profile (session-scoped).
class OrganizationProfileNotifier extends AsyncNotifier<OrganizationProfile> {
  @override
  Future<OrganizationProfile> build() {
    ref.watch(sessionKeyProvider);
    return ref.watch(organizationProfileRepositoryProvider).fetch();
  }

  /// PATCHes [changes] and publishes the server's result. The dashboard is
  /// invalidated because it shows the organization name/status.
  Future<OrganizationProfile> save(Json changes) async {
    final repo = ref.read(organizationProfileRepositoryProvider);
    final updated = await repo.update(changes);
    state = AsyncData(updated);
    ref.invalidate(dashboardSummaryProvider);
    return updated;
  }
}

final organizationProfileProvider =
    AsyncNotifierProvider<OrganizationProfileNotifier, OrganizationProfile>(
  OrganizationProfileNotifier.new,
);
