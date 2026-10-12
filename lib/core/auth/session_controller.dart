import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/app_exception.dart';
import '../providers.dart';
import 'auth_repository.dart';
import 'auth_user.dart';

sealed class SessionState {
  const SessionState();
}

/// Launch: stored credentials are being validated.
class SessionRestoring extends SessionState {
  const SessionRestoring();
}

class SignedOut extends SessionState {
  const SignedOut({this.expired = false});

  /// True when the session ended involuntarily (refresh failed).
  final bool expired;
}

class SignedIn extends SessionState {
  const SignedIn(this.user);
  final AuthUser user;
}

/// Single source of truth for who is signed in. Role and permission state is
/// centralised here and refreshed via [refreshUser] after permission changes.
class SessionController extends Notifier<SessionState> {
  late AuthRepository _repo;

  /// Called by features (e.g. to wipe cached private data) on sign-out.
  final List<void Function()> _signOutListeners = [];

  @override
  SessionState build() {
    _repo = ref.watch(authRepositoryProvider);
    Future.microtask(_restore);
    return const SessionRestoring();
  }

  Future<void> _restore() async {
    if (!await _repo.hasStoredSession()) {
      state = const SignedOut();
      return;
    }
    try {
      final user = await _repo.me();
      state = SignedIn(user);
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.network) {
        // Offline at launch: keep credentials, let the user retry.
        state = const SignedOut();
      } else {
        await _repo.logout();
        state = const SignedOut(expired: true);
      }
    }
  }

  Future<void> retryRestore() async {
    state = const SessionRestoring();
    await _restore();
  }

  /// Single app sign-in: signs into organization account (staff sign-in is web-only).
  Future<void> login(String email, String password) =>
      loginOwner(email, password);

  /// Demo sign-in for testing and exploring all modules without a live backend.
  void loginDemo() {
    state = const SignedIn(AuthUser(
      id: 'usr-demo-1',
      email: 'muhammed@bizzvot.com',
      role: UserRole.owner,
      organizationName: 'Bizzvot Technologies',
      name: 'Muhammed KC',
    ));
  }

  /// Demo staff card member sign-in for testing staff portal and card management.
  void loginDemoStaff() {
    state = const SignedIn(AuthUser(
      id: 'usr-demo-staff-1',
      email: 'sarah.staff@bizzvot.com',
      role: UserRole.staff,
      organizationName: 'Bizzvot Technologies',
      name: 'Sarah Jenkins',
      cardId: 'card-1',
      permissions: StaffPermissions(
        editCard: true,
        manageLinks: true,
        viewReviews: true,
        replyReviews: true,
      ),
    ));
  }

  Future<void> loginOwner(String email, String password) async {
    final user = await _repo.loginOwner(email, password);
    state = SignedIn(user);
  }

  Future<void> loginStaff(String email, String password) async {
    final user = await _repo.loginStaff(email, password);
    state = SignedIn(user);
  }

  Future<void> register(RegisterRequest req) async {
    final user = await _repo.register(req);
    state = SignedIn(user);
  }

  /// Re-fetch `/auth/me` (role/permissions may have changed server-side).
  Future<void> refreshUser() async {
    try {
      final user = await _repo.me();
      state = SignedIn(user);
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.unauthenticated) {
        state = const SignedOut(expired: true);
      }
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    _notifySignOut();
    state = const SignedOut();
  }

  void onSessionExpired() {
    if (state is SignedOut) return;
    _notifySignOut();
    state = const SignedOut(expired: true);
  }

  void addSignOutListener(void Function() listener) =>
      _signOutListeners.add(listener);

  void _notifySignOut() {
    for (final l in List.of(_signOutListeners)) {
      try {
        l();
      } catch (_) {}
    }
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Convenience: the signed-in user or null.
final currentUserProvider = Provider<AuthUser?>((ref) {
  final s = ref.watch(sessionControllerProvider);
  return s is SignedIn ? s.user : null;
});

/// Identity key for cache scoping. Every provider that holds private,
/// account-specific data MUST `ref.watch(sessionKeyProvider)` so its cache
/// is discarded on logout or account switch.
final sessionKeyProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider.select((u) => u?.id)),
);
