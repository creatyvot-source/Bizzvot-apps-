import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/providers.dart';
import '../../../shared/models/organization.dart';

/// Owner dashboard data (`GET /organization/dashboard`).
class DashboardRepository {
  DashboardRepository(this._api);

  final ApiClient _api;

  Future<DashboardSummary> fetchSummary() =>
      _api.get(Endpoints.dashboard, parse: DashboardSummary.fromJson);
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(apiClientProvider)),
);
