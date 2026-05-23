import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user/screens/login_screen.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('LoginScreen shows DefenSYS branding and sign-in controls', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      const LoginScreen(),
    );

    expect(find.text('DefenSYS'), findsWidgets);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
  });
}
