import 'package:flutter/material.dart';

import '../domain/auth_errors.dart';
import 'widgets/login_form.dart';

/// Owner sign-in (`POST /auth/login`). Staff accounts are guided to staff
/// sign-in; `super_admin` is told to use the admin console; unknown or
/// locked accounts get a generic invalid-credentials message.
class OwnerLoginScreen extends StatelessWidget {
  const OwnerLoginScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const LoginForm(portal: LoginPortal.owner);
}
