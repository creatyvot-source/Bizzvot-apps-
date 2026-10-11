import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/models/organization.dart';
import '../domain/dashboard_overview.dart';

/// Owner dashboard data: `GET /organization/dashboard` for the counts and
/// `GET /organization/profile` for the organization name and status.
class DashboardRepository {
  DashboardRepository(this._api);

  final ApiClient _api;

  Future<DashboardOverview> fetchOverview() async {
    final results = await Future.wait<Object?>([
      _api.get<Object?>(Endpoints.dashboard, parse: (d) => d),
      _profileOrNull(),
    ]);
    return DashboardOverview.fromJson(
      results[0],
      profile: results[1] as OrganizationProfile?,
    );
  }

  /// The header is nice-to-have; a profile failure must not hide the counts.
  Future<OrganizationProfile?> _profileOrNull() async {
    try {
      return await _api.get(
        Endpoints.profile,
        parse: OrganizationProfile.fromJson,
      );
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.unauthenticated) rethrow;
      return null;
    }
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(apiClientProvider)),
);
