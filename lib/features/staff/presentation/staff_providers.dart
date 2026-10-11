import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/models/organization.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../data/staff_repository.dart';
import '../domain/staff_draft.dart';

/// All staff in the owner's organization (session-scoped).
final staffListProvider = FutureProvider<List<StaffMember>>((ref) async {
  ref.watch(sessionKeyProvider);
  return ref.watch(staffRepositoryProvider).list();
});

/// One staff member. There is no single-item endpoint, so this resolves from
/// the list.
final staffMemberProvider =
    FutureProvider.autoDispose.family<StaffMember, String>((ref, id) async {
  ref.watch(sessionKeyProvider);
  final all = await ref.watch(staffListProvider.future);
  for (final m in all) {
    if (m.id == id) return m;
  }
  throw const AppException(
    AppErrorKind.notFound,
    'This staff member could not be found. They may have been removed.',
  );
});

/// Create / update / delete, then refresh dependent data.
class StaffMutations {
  StaffMutations(this._ref);

  final Ref _ref;

  StaffRepository get _repo => _ref.read(staffRepositoryProvider);

  Future<StaffMember?> create(StaffDraft draft) =>
      _refreshAfter(() => _repo.create(draft.toCreateJson()));

  Future<StaffMember?> update(String id, Map<String, dynamic> changes) =>
      _refreshAfter(() => _repo.update(id, changes));

  Future<void> delete(String id) => _refreshAfter(() => _repo.delete(id));

  /// Refreshes even on failure: a seat error may follow a partial write.
  Future<T> _refreshAfter<T>(Future<T> Function() action) async {
    try {
      return await action();
    } finally {
      _ref.invalidate(staffListProvider);
      _ref.invalidate(dashboardSummaryProvider);
    }
  }
}

final staffMutationsProvider = Provider<StaffMutations>(StaffMutations.new);
