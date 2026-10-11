import 'package:flutter/material.dart';

import 'widgets/login_form.dart';

/// Normal sign-in: unified for both owner and staff accounts.
/// Permissions and roles are automatically handled on session establishment.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) => const LoginForm();
}
