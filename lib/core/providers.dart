import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/env.dart';
import 'api/api_client.dart';
import 'auth/auth_repository.dart';
import 'auth/session_controller.dart';
import 'secure_storage/token_store.dart';

/// Root providers. Feature repositories depend on [apiClientProvider] and
/// must never construct their own Dio.
final envProvider = Provider<Env>((ref) => Env.current);

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  final env = ref.watch(envProvider);
  final store = ref.watch(tokenStoreProvider);
  final dio = buildDio(env.apiBaseUrl);
  dio.interceptors.insert(
    0,
    AuthInterceptor(
      store: store,
      dio: dio,
      refresh: buildRefresh(env.apiBaseUrl),
      onSessionExpired: () =>
          ref.read(sessionControllerProvider.notifier).onSessionExpired(),
    ),
  );
  ref.onDispose(dio.close);
  return ApiClient(dio);
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStoreProvider),
  ),
);
