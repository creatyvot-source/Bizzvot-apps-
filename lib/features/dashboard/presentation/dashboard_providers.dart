import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_overview.dart';

/// Owner dashboard overview. Session-scoped: discarded on logout/account
/// switch. Other features invalidate this after changes that affect counts
/// (staff added/removed, profile renamed, seats purchased, cards toggled).
final dashboardSummaryProvider = FutureProvider<DashboardOverview>((ref) async {
  ref.watch(sessionKeyProvider);
  return ref.watch(dashboardRepositoryProvider).fetchOverview();
});
