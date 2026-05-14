import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: DefenSYSApp()));
}

class DefenSYSApp extends StatelessWidget {
  const DefenSYSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DefenSYS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const LoginScreen(),
    );
  }
}
