import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../shared/models/card.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../data/staff_repository.dart';
import '../domain/staff_draft.dart';

/// All staff in the owner's organization (session-scoped).
final staffListProvider = FutureProvider<List<StaffEntry>>((ref) async {
  ref.watch(sessionKeyProvider);
  return ref.watch(staffRepositoryProvider).list();
});

/// One staff member (`GET /organization/staff/:id`).
final staffMemberProvider =
    FutureProvider.autoDispose.family<StaffEntry, String>((ref, id) async {
  ref.watch(sessionKeyProvider);
  return ref.watch(staffRepositoryProvider).get(id);
});

/// Organization cards for the "assign existing card" picker.
final staffAssignableCardsProvider =
    FutureProvider.autoDispose<List<CardModel>>((ref) async {
  ref.watch(sessionKeyProvider);
  return ref.watch(staffRepositoryProvider).listCards();
});

/// Result of adding a staff member, including the card step.
class StaffCreateResult {
  const StaffCreateResult(this.staff, {this.card, this.cardError});

  final StaffEntry staff;
  final CardModel? card;

  /// Set when the staff member was added but their card could not be
  /// created or assigned (e.g. no card slot available).
  final Object? cardError;
}

/// Create / update / delete, then refresh dependent data.
class StaffMutations {
  StaffMutations(this._ref);

  final Ref _ref;

  StaffRepository get _repo => _ref.read(staffRepositoryProvider);

  /// Adds the staff member, then (optionally) creates their card and
  /// assigns it. A card failure does not undo the staff member.
  Future<StaffCreateResult> create(StaffDraft draft) => _refreshAfter(() async {
        final staff = await _repo.create(draft);
        if (!draft.createCard) return StaffCreateResult(staff);
        try {
          final result = await _createAndAssignCard(staff, draft.toCardJson());
          return StaffCreateResult(result.$1, card: result.$2);
        } catch (e) {
          return StaffCreateResult(staff, cardError: e);
        }
      });

  /// Creates a card for an existing staff member and assigns it.
  Future<(StaffEntry, CardModel)> createCardFor(
    StaffEntry staff, {
    String designation = '',
  }) =>
      _refreshAfter(() => _createAndAssignCard(
            staff,
            cardJsonFor(
              name: staff.name,
              designation: designation,
              email: staff.email,
              phone: staff.phone,
            ),
          ));

  Future<(StaffEntry, CardModel)> _createAndAssignCard(
    StaffEntry staff,
    Map<String, dynamic> body,
  ) async {
    final card = await _repo.createCard(body);
    // The backend may already have auto-assigned it (first org card).
    final ids = {...staff.assignedCardIds, card.id}.toList();
    final updated = await _repo.update(staff.id, {'assignedCardIds': ids});
    final entry = (updated ?? staff).copyWith(
      name: staff.name,
      email: staff.email,
      cards: [...staff.cards, card],
    );
    return (entry, card);
  }

  Future<StaffEntry?> update(String id, Map<String, dynamic> changes) =>
      _refreshAfter(() => _repo.update(id, changes));

  Future<void> delete(String id) => _refreshAfter(() => _repo.delete(id));

  /// Refreshes even on failure: an error may follow a partial write.
  Future<T> _refreshAfter<T>(Future<T> Function() action) async {
    try {
      return await action();
    } finally {
      _ref.invalidate(staffListProvider);
      _ref.invalidate(staffAssignableCardsProvider);
      _ref.invalidate(dashboardSummaryProvider);
    }
  }
}

final staffMutationsProvider = Provider<StaffMutations>(StaffMutations.new);
