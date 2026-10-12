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

  static const dummyOverview = DashboardOverview(
    organizationName: 'Bizzvot Technologies',
    organizationStatus: 'active',
    totalCards: 4,
    cardsLimit: 10,
    activeCards: 4,
    staffCount: 3,
    staffLimit: 10,
    totalReviews: 48,
    averageRating: 4.95,
    disabledByBilling: 0,
  );

  Future<DashboardOverview> fetchOverview() async {
    try {
      final results = await Future.wait<Object?>([
        _api.get<Object?>(Endpoints.dashboard, parse: (d) => d),
        _profileOrNull(),
      ]);
      final overview = DashboardOverview.fromJson(
        results[0],
        profile: results[1] as OrganizationProfile?,
      );
      return overview;
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.network) {
        return dummyOverview;
      }
      rethrow;
    }
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
