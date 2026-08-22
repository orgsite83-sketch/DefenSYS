import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/login_screen.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';

void main() {
  testWidgets('LoginScreen shows DefenSYS branding and sign-in controls', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      const LoginScreen(),
      overrides: authTestOverrides(),
    );

    expect(find.text('DefenSYS'), findsWidgets);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);

    // Open Forgot Password dialog
    final forgotPasswordBtn = find.text('Forgot password?');
    expect(forgotPasswordBtn, findsOneWidget);
    await tester.tap(forgotPasswordBtn);
    await tester.pumpAndSettle();

    // Verify Step 1: Verification Dialog with 6-digit OTP prompt
    expect(find.text('Reset Password'), findsOneWidget);
    expect(find.text('Step 1 of 3: Verification'), findsOneWidget);
    expect(find.text('Send Code'), findsOneWidget);
  });
}

