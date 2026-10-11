import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/providers.dart';
import '../../../core/utilities/json.dart';
import '../../../shared/models/organization.dart';
import '../../../shared/models/paged.dart';

/// Owner staff management (`/organization/staff`).
class StaffRepository {
  StaffRepository(this._api);

  final ApiClient _api;

  /// `GET /organization/staff`. Accepts a bare list or `{ staff | items | … }`.
  Future<List<StaffMember>> list() => _api.get(
        Endpoints.staff,
        parse: (data) => Paged.parse(
          data,
          StaffMember.fromJson,
          listKeys: const ['staff', 'items', 'docs', 'results', 'members', 'data'],
        ).items.where((m) => m.id.isNotEmpty).toList(),
      );

  /// `POST /organization/staff`. Returns the created member when the
  /// response includes it.
  Future<StaffMember?> create(Json body) =>
      _api.post(Endpoints.staff, body: body, parse: parseStaffMutation);

  /// `PATCH /organization/staff/:id`.
  Future<StaffMember?> update(String id, Json changes) =>
      _api.patch(Endpoints.staffMember(id), body: changes, parse: parseStaffMutation);

  /// `DELETE /organization/staff/:id`.
  Future<void> delete(String id) =>
      _api.delete<void>(Endpoints.staffMember(id), parse: (_) {});

  /// Accepts `{ staff | user: {...}, card: {...} }` or a flat staff object.
  static StaffMember? parseStaffMutation(Object? data) {
    final j = asJson(data);
    final nested = j['staff'] is Map
        ? asJson(j['staff'])
        : j['user'] is Map
            ? asJson(j['user'])
            : null;
    final member = nested == null
        ? j
        : {
            ...nested,
            if (nested['card'] is! Map && j['card'] is Map) 'card': j['card'],
          };
    if (idOf(member).isEmpty) return null;
    return StaffMember.fromJson(member);
  }
}

final staffRepositoryProvider = Provider<StaffRepository>(
  (ref) => StaffRepository(ref.watch(apiClientProvider)),
);
