import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Email carried from one sign-in form to the other when the user is guided
/// to the correct portal, so they don't have to retype it. Signed-out only;
/// cleared once consumed. Holds no credentials.
class LoginEmailHint extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? email) => state = email;

  /// Returns the hint and clears it.
  String? take() {
    final v = state;
    state = null;
    return v;
  }
}

final loginEmailHintProvider =
    NotifierProvider<LoginEmailHint, String?>(LoginEmailHint.new);
