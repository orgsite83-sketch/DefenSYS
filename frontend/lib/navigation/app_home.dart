import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../screens/web/admin/admin_dashboard.dart';
import '../screens/web/faculty/faculty_dashboard.dart';
import '../screens/login_screen.dart';
import '../services/auth_provider.dart';

/// Root [MaterialApp.home] from auth state (web: dashboard when signed in).
Widget homeForAuth(AuthState auth) {
  if (auth.isRestoring) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }

  if (kIsWeb && auth.token != null && auth.user != null) {
    final dashboard = webDashboardForUser(auth.user!);
    if (dashboard != null) return dashboard;
  }

  return LoginScreen(sessionMessage: auth.sessionExpiredMessage);
}

/// Web dashboard for admin/faculty; null if user must stay on login (e.g. student).
Widget? webDashboardForUser(Map<String, dynamic> user) {
  final role = user['role'];
  if (role == 'admin') return AdminDashboard(userData: user);
  if (role == 'faculty') return FacultyDashboard(userData: user);
  return null;
}
