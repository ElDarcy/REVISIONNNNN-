import 'package:flutter/material.dart';
import 'location_setup_screen.dart';

/// Register Step 2 — delivery location onboarding.
///
/// Delegates to the shared [LocationSetupScreen] (register mode) so email
/// registrations and Google/manual customers get the exact same rich location
/// experience. No business logic lives here.
class RegisterStep2LocationScreen extends StatelessWidget {
  final String name;
  final String email;
  final String password;
  final String phone;

  const RegisterStep2LocationScreen({
    super.key,
    required this.name,
    required this.email,
    required this.password,
    required this.phone,
  });

  @override
  Widget build(BuildContext context) {
    return LocationSetupScreen(
      registerName: name,
      registerEmail: email,
      registerPassword: password,
      registerPhone: phone,
    );
  }
}