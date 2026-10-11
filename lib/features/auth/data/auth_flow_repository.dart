import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/providers.dart';

/// Entry point for the auth screens.
///
/// Sign-in and registration go through [SessionController] so the session
/// state remains the single source of truth (the router redirects on
/// `SignedIn`). Password flows call the core [AuthRepository], which owns all
/// `/auth/*` HTTP calls. Screens depend on this class only, so widget tests
/// can override [authFlowRepositoryProvider] with a fake.
class AuthFlowRepository {
  AuthFlowRepository(this._ref);

  final Ref _ref;

  AuthRepository get _auth => _ref.read(authRepositoryProvider);
  SessionController get _session =>
      _ref.read(sessionControllerProvider.notifier);

  /// `POST /auth/login`, then `GET /auth/me`.
  Future<void> loginOwner(String email, String password) =>
      _session.loginOwner(email, password);

  /// `POST /auth/staff-login`, then `GET /auth/me`.
  Future<void> loginStaff(String email, String password) =>
      _session.loginStaff(email, password);

  /// `POST /auth/register` (signs the new owner in on success).
  Future<void> register(RegisterRequest request) => _session.register(request);

  /// `POST /auth/forgot-password`.
  Future<void> forgotPassword(String email) => _auth.forgotPassword(email);

  /// `POST /auth/reset-password`.
  Future<void> resetPassword({
    required String token,
    required String password,
  }) => _auth.resetPassword(token: token, password: password);

  /// `POST /auth/change-password`.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _auth.changePassword(
    currentPassword: currentPassword,
    newPassword: newPassword,
  );
}

final authFlowRepositoryProvider = Provider<AuthFlowRepository>(
  AuthFlowRepository.new,
);
