import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'admin_route_paths.dart';
import 'app_router.dart';
import '../services/terms_acceptance.dart';

/// Mobile post-auth: terms gate on first acceptance per device, else dashboard.
Future<void> navigateToHomeAfterAuth(
  BuildContext context, {
  required String role,
  required Map<String, dynamic> userData,
}) async {
  if (await TermsAcceptance.hasAcceptedCurrentTerms()) {
    if (!context.mounted) return;
    context.go(homeRouteForRoleLabel(role));
    return;
  }

  if (!context.mounted) return;
  context.go(
    AppRoutes.terms,
    extra: {'role': role, 'userData': userData},
  );
}
