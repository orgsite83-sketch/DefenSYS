import 'package:flutter/foundation.dart' show kIsWeb;

import 'admin_route_paths.dart';

/// Chooses workspaces from server supplied roles. API permissions remain authoritative.
abstract final class WorkspaceAccess {
  static bool canEvaluate(Map<String, dynamic> user) =>
      user['role'] == 'faculty' && user['is_panelist'] == true;

  static bool canUsePhone(Map<String, dynamic> user) =>
      user['role'] == 'student' || canEvaluate(user);

  static bool hasStaffWorkspace(Map<String, dynamic> user) =>
      user['role'] == 'admin' ||
      (user['role'] == 'faculty' &&
          // Older servers omit instructor assignments. Preserve their staff home.
          (user['has_staff_workspace'] != false ||
              user['is_pit_lead'] == true ||
              user['is_adviser'] == true ||
              user['is_documenter'] == true ||
              user['is_uploader'] == true));

  static String home(Map<String, dynamic> user, {bool isWeb = kIsWeb}) {
    final role = user['role'];
    if (role == 'guest_panelist') return AppRoutes.guestDefenses;
    if (role == 'student') return AppRoutes.student;
    if (isWeb) {
      if (role == 'admin') return AdminRoutes.overview;
      if (role == 'faculty') {
        return canEvaluate(user) && !hasStaffWorkspace(user)
            ? AppRoutes.panelist
            : FacultyRoutes.dashboard;
      }
    } else if (canEvaluate(user)) {
      return AppRoutes.panelist;
    }
    return AppRoutes.webWorkspaceOnly;
  }

  static String? redirect(
    Map<String, dynamic> user,
    String location, {
    bool isWeb = kIsWeb,
  }) {
    final destination = home(user, isWeb: isWeb);
    if (user['role'] == 'guest_panelist') {
      return location == AppRoutes.guestDefenses ? null : destination;
    }
    if (location == AppRoutes.login || location == '/') return destination;
    if (location == AppRoutes.terms || location == AppRoutes.guestEntry) {
      return null;
    }
    if (location == AppRoutes.guestDefenses) return AppRoutes.guestEntry;
    final allowed = switch (location) {
      AppRoutes.student => user['role'] == 'student',
      AppRoutes.panelist => canEvaluate(user),
      AppRoutes.settings => canUsePhone(user),
      AppRoutes.webWorkspaceOnly => destination == AppRoutes.webWorkspaceOnly,
      _ when location == '/admin' || location.startsWith('/admin/') =>
        isWeb && user['role'] == 'admin',
      _ when location == '/faculty' || location.startsWith('/faculty/') =>
        isWeb && user['role'] == 'faculty',
      _ => false,
    };
    return allowed ? null : destination;
  }
}
