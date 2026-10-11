import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Native session credentials. Lives only in Keychain / Keystore-backed
/// storage — never in SharedPreferences, logs or crash reports.
class SessionTokens {
  const SessionTokens({required this.accessToken, this.refreshToken});

  final String accessToken;
  final String? refreshToken;

  @override
  String toString() => 'SessionTokens(<redacted>)';
}

abstract interface class TokenStore {
  Future<SessionTokens?> read();
  Future<void> write(SessionTokens tokens);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  static const _kAccess = 'bv.access';
  static const _kRefresh = 'bv.refresh';

  @override
  Future<SessionTokens?> read() async {
    try {
      final access = await _storage.read(key: _kAccess);
      if (access == null || access.isEmpty) return null;
      final refresh = await _storage.read(key: _kRefresh);
      return SessionTokens(accessToken: access, refreshToken: refresh);
    } catch (_) {
      // Corrupted keystore entries (e.g. after OS restore): treat as signed out.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(SessionTokens tokens) async {
    await _storage.write(key: _kAccess, value: tokens.accessToken);
    if (tokens.refreshToken != null) {
      await _storage.write(key: _kRefresh, value: tokens.refreshToken);
    } else {
      await _storage.delete(key: _kRefresh);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _kAccess);
      await _storage.delete(key: _kRefresh);
    } catch (_) {}
  }
}

/// In-memory store for tests.
class MemoryTokenStore implements TokenStore {
  SessionTokens? _tokens;

  @override
  Future<void> clear() async => _tokens = null;

  @override
  Future<SessionTokens?> read() async => _tokens;

  @override
  Future<void> write(SessionTokens tokens) async => _tokens = tokens;
}
