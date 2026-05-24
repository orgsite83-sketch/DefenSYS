import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../navigation/admin_route_paths.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Mobile logout/session expiry: use GoRouter only (no imperative Login route).
void navigateToLogin({String? sessionMessage}) {
  final context = rootNavigatorKey.currentContext;
  if (context == null) return;
  context.go(AppRoutes.login);
}
