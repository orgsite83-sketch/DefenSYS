import 'package:flutter/material.dart';

import '../screens/login_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

void navigateToLogin({String? sessionMessage}) {
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) return;
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => LoginScreen(sessionMessage: sessionMessage),
    ),
    (_) => false,
  );
}
