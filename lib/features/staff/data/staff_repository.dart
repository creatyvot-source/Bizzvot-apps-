import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/auth/auth_user.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utilities/json.dart';
import '../../../shared/models/card.dart';
import '../../../shared/models/paged.dart';
import '../../cards/data/cards_repository.dart';
import '../domain/staff_draft.dart';

/// Owner staff management (`/organization/staff`) plus the card calls the
/// staff screens need (`/organization/cards`).
class StaffRepository {
  StaffRepository(this._api);

  final ApiClient _api;

  /// Safety cap on card pages fetched to resolve card status (100 each).
  static const _maxCardPages = 10;

  static final dummyStaff = <StaffEntry>[
    StaffEntry(
      id: 'staff-1',
      name: 'Dr. Sarah Khan',
      email: 'sarah.khan@bizzvot.com',
      phone: '+91 94471 22334',
      status: StaffStatus.active,
      permissions: const StaffPermissions(
        editCard: true,
        manageLinks: true,
        viewReviews: true,
        replyReviews: true,
      ),
      assignedCardIds: const ['card-2'],
      cards: [CardsRepository.dummyCards[1]],
    ),
    StaffEntry(
      id: 'staff-2',
      name: 'Rahul Varma',
      email: 'rahul.v@bizzvot.com',
      phone: '+91 91234 56789',
      status: StaffStatus.active,
      permissions: const StaffPermissions(
        editCard: true,
        manageLinks: true,
        viewReviews: true,
        replyReviews: false,
      ),
      assignedCardIds: const ['card-3'],
      cards: [CardsRepository.dummyCards[2]],
    ),
    const StaffEntry(
      id: 'staff-3',
      name: 'Ananya Nair',
      email: 'ananya.nair@bizzvot.com',
      phone: '+91 98460 11223',
      status: StaffStatus.active,
      permissions: StaffPermissions(
        editCard: false,
        manageLinks: false,
        viewReviews: true,
        replyReviews: false,
      ),
      assignedCardIds: [],
      cards: [],
    ),
  ];

  /// All staff, each with its assigned cards resolved.
  Future<List<StaffEntry>> list() async {
    try {
      final results = await Future.wait([
        _api.get(Endpoints.staff, parse: parseStaffList),
        listCards(),
      ]);
      final staff = results[0] as List<StaffEntry>;
      final cards = results[1] as List<CardModel>;
      return staff.map((s) => resolveCards(s, cards)).toList();
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.network) {
        return dummyStaff;
      }
      rethrow;
    }
  }

  /// `GET /organization/staff/:id`, with assigned cards resolved.
  Future<StaffEntry> get(String id) async {
    try {
      final results = await Future.wait([
        _api.get(Endpoints.staffMember(id), parse: StaffEntry.fromJson),
        listCards(),
      ]);
      final entry = results[0] as StaffEntry;
      if (entry.id.isEmpty) {
        throw const AppException(
          AppErrorKind.notFound,
          'This staff member could not be found. They may have been removed.',
        );
      }
      return resolveCards(entry, results[1] as List<CardModel>);
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.network) {
        return dummyStaff.firstWhere((s) => s.id == id, orElse: () => dummyStaff.first);
      }
      rethrow;
    }
  }

  /// Every organization card (paged). Failures resolve to an empty list so
  /// the staff list still renders (card status then shows as unknown).
  Future<List<CardModel>> listCards() async {
    final all = <CardModel>[];
    try {
      for (var page = 1; page <= _maxCardPages; page++) {
        final p = await _api.get(
          Endpoints.cards,
          query: {'page': page, 'limit': 100},
          parse: (d) => Paged.parse(d, CardModel.fromJson),
        );
        all.addAll(p.items.where((c) => c.id.isNotEmpty));
        if (!p.hasMore || p.items.isEmpty) break;
      }
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.unauthenticated) rethrow;
    }
    return all;
  }

  /// `POST /organization/staff`.
  Future<StaffEntry> create(StaffDraft draft) async {
    final created = await _api.post(
      Endpoints.staff,
      body: draft.toCreateJson(),
      parse: parseStaffMutation,
    );
    if (created == null || created.id.isEmpty) {
      throw const AppException(
        AppErrorKind.server,
        'The staff member may have been added, but the response was incomplete. Refresh the list to check.',
      );
    }
    // `staff` has no name/email; fall back to what was entered.
    return created.copyWith(
      name: created.name == 'Unnamed' ? draft.name : created.name,
      email: created.email.isEmpty ? draft.normalizedEmail : created.email,
    );
  }

  /// `POST /organization/cards` → the created card.
  Future<CardModel> createCard(Json body) =>
      _api.post(Endpoints.cards, body: body, parse: CardModel.fromJson);

  /// `PATCH /organization/staff/:id`.
  Future<StaffEntry?> update(String id, Json changes) => _api.patch(
    Endpoints.staffMember(id),
    body: changes,
    parse: (d) {
      final e = StaffEntry.fromJson(d);
      return e.id.isEmpty ? null : e;
    },
  );

  /// `DELETE /organization/staff/:id`.
  Future<void> delete(String id) =>
      _api.delete<void>(Endpoints.staffMember(id), parse: (_) {});

  /// Bare array, or `{ staff | items | … }`.
  static List<StaffEntry> parseStaffList(Object? data) => Paged.parse(
    data,
    StaffEntry.fromJson,
    listKeys: const ['staff', 'items', 'docs', 'results', 'members', 'data'],
  ).items.where((m) => m.id.isNotEmpty).toList();

  /// `{ staff: {...}, user: {id, email, name} }` or a flat staff doc.
  static StaffEntry? parseStaffMutation(Object? data) {
    final j = asJson(data);
    final staff = j['staff'] is Map ? asJson(j['staff']) : j;
    final user = asJson(j['user']);
    final merged = {
      ...staff,
      if (staff['userId'] is! Map && user.isNotEmpty)
        'userId': {...user, '_id': staff['userId'] ?? idOf(user)},
    };
    if (idOf(merged).isEmpty) return null;
    return StaffEntry.fromJson(merged);
  }

  static StaffEntry resolveCards(StaffEntry e, List<CardModel> cards) {
    if (e.assignedCardIds.isEmpty || cards.isEmpty) return e;
    final byId = {for (final c in cards) c.id: c};
    final resolved = [
      for (final id in e.assignedCardIds)
        if (byId[id] != null) byId[id]!,
    ];
    return resolved.isEmpty ? e : e.copyWith(cards: resolved);
  }
}

final staffRepositoryProvider = Provider<StaffRepository>(
  (ref) => StaffRepository(ref.watch(apiClientProvider)),
);
