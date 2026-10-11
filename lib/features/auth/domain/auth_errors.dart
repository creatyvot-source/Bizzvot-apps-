import '../../../core/errors/app_exception.dart';

/// Which sign-in form the user submitted.
enum LoginPortal { owner, staff }

enum LoginFailureKind {
  /// Unknown account, wrong password, locked or disabled account. Always the
  /// same generic message so accounts can't be enumerated.
  invalidCredentials,

  /// The account belongs to the other portal (staff on owner sign-in or vice
  /// versa). The UI guides the user without revealing account details.
  wrongPortal,

  /// `super_admin` accounts must use the web admin console.
  adminAccount,

  /// `429` — the form is disabled for [LoginFailure.retryAfter].
  rateLimited,

  /// Offline, server error or native sessions unavailable. Message is safe.
  other,
}

class LoginFailure {
  const LoginFailure(this.kind, this.message, {this.retryAfter, this.exception});

  final LoginFailureKind kind;
  final String message;
  final Duration? retryAfter;
  final AppException? exception;
}

abstract final class AuthMessages {
  static const invalidCredentials =
      'The email or password is incorrect. Check your details and try again.';
  static const adminAccount = 'Use the admin sign-in page';
  static const useStaffLogin =
      'This sign-in is for organization owners. If you were added by your '
      'organization as a team member, use staff sign-in instead.';
  static const useOwnerLogin =
      'This sign-in is for team members. If you manage an organization, use '
      'owner sign-in instead.';
  static const forgotNeutral =
      'If an account exists for this email, we’ve sent a link to reset your '
      'password. Check your inbox and spam folder.';
  static const invalidResetLink =
      'This reset link is invalid or has expired. Request a new one to continue.';
}

final _staffHint = RegExp(r'\bstaff\b', caseSensitive: false);
final _ownerHint =
    RegExp(r'\b(owner|organi[sz]ation (sign[- ]?in|login))\b', caseSensitive: false);
final _adminHint = RegExp(r'admin sign[- ]?in', caseSensitive: false);

const _staffCodes = {
  'STAFF_ACCOUNT',
  'USE_STAFF_LOGIN',
  'STAFF_LOGIN_REQUIRED',
  'IS_STAFF',
};
const _ownerCodes = {
  'OWNER_ACCOUNT',
  'USE_OWNER_LOGIN',
  'OWNER_LOGIN_REQUIRED',
  'NOT_STAFF',
};
const _portalMismatchCodes = {'ROLE_MISMATCH', 'WRONG_PORTAL', 'WRONG_LOGIN'};
const _adminCodes = {'SUPER_ADMIN', 'ADMIN_LOGIN_REQUIRED', 'USE_ADMIN_LOGIN'};

/// Maps a sign-in error to what the UI shows. Pure and unit-tested.
LoginFailure classifyLoginError(Object error, {required LoginPortal portal}) {
  final e = AppException.from(error);
  final code = e.code?.toUpperCase();

  switch (e.kind) {
    case AppErrorKind.rateLimited:
      return LoginFailure(
        LoginFailureKind.rateLimited,
        'Too many sign-in attempts. Please wait and try again.',
        retryAfter: e.retryAfter,
        exception: e,
      );
    case AppErrorKind.network:
    case AppErrorKind.server:
    case AppErrorKind.cancelled:
      return LoginFailure(LoginFailureKind.other, e.message, exception: e);
    default:
      break;
  }

  if (code == 'NATIVE_SESSION_UNSUPPORTED') {
    return LoginFailure(LoginFailureKind.other, e.message, exception: e);
  }

  if ((code != null && _adminCodes.contains(code)) || _adminHint.hasMatch(e.message)) {
    return LoginFailure(
      LoginFailureKind.adminAccount,
      AuthMessages.adminAccount,
      exception: e,
    );
  }

  final otherPortalCodes = portal == LoginPortal.owner ? _staffCodes : _ownerCodes;
  final hint = portal == LoginPortal.owner ? _staffHint : _ownerHint;
  final wrongPortal = (code != null &&
          (otherPortalCodes.contains(code) || _portalMismatchCodes.contains(code))) ||
      hint.hasMatch(e.message);
  if (wrongPortal) {
    return LoginFailure(
      LoginFailureKind.wrongPortal,
      portal == LoginPortal.owner
          ? AuthMessages.useStaffLogin
          : AuthMessages.useOwnerLogin,
      exception: e,
    );
  }

  // 400/401/403/404/423/… and unknown envelopes: never reveal whether the
  // account exists, is locked or disabled.
  return LoginFailure(
    LoginFailureKind.invalidCredentials,
    AuthMessages.invalidCredentials,
    exception: e,
  );
}

/// Whether a reset-password failure means the link itself is unusable.
bool isInvalidResetToken(AppException e) {
  if (e.fieldErrors.containsKey('password') && e.fieldErrors.length == 1) {
    return false;
  }
  switch (e.kind) {
    case AppErrorKind.notFound:
    case AppErrorKind.gone:
    case AppErrorKind.forbidden:
    case AppErrorKind.unauthenticated:
      return true;
    case AppErrorKind.validation:
    case AppErrorKind.unknown:
      final code = e.code?.toUpperCase() ?? '';
      return code.contains('TOKEN') ||
          code.contains('EXPIRED') ||
          e.fieldErrors.containsKey('token') ||
          RegExp(r'token|expired|link', caseSensitive: false).hasMatch(e.message);
    default:
      return false;
  }
}
