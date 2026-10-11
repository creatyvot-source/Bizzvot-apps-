import 'package:flutter/material.dart';

import '../domain/auth_errors.dart';
import 'widgets/login_form.dart';

/// Staff sign-in (`POST /auth/staff-login`).
class StaffLoginScreen extends StatelessWidget {
  const StaffLoginScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const LoginForm(portal: LoginPortal.staff);
}
