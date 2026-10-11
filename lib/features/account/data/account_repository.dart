import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/providers.dart';

class AccountRepository {
  AccountRepository(this._api);

  final ApiClient _api;

  /// PROPOSED `DELETE /auth/account` (gap ACC-1). The server must re-verify
  /// the password, cancel subscriptions per policy, and schedule deletion of
  /// the organization's data according to the retention policy.
  Future<void> deleteAccount({required String password, String? reason}) =>
      _api.delete<void>(
        Endpoints.deleteAccount,
        body: {
          'password': password,
          'confirm': 'DELETE',
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        },
        parse: (_) {},
      );
}

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(apiClientProvider)),
);
