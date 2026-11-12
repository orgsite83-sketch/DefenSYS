import 'package:flutter/foundation.dart' show kIsWeb;

import 'admin_route_paths.dart';
import 'staff_workspaces.dart';

/// Chooses workspaces from server supplied roles. API permissions remain authoritative.
abstract final class WorkspaceAccess {
  static const phoneBreakpoint = 600.0;

  static bool canUseFaculty(Map<String, dynamic> user) =>
      user['role'] == 'faculty' ||
      (user['role'] == 'admin' &&
          StaffWorkspace.available(user).any(
            (option) => const {
              'adviser',
              'pit_lead',
              'instructor',
              'documenter',
            }.contains(option.key),
          ));

  static bool supportsFacultyRoute(String key, String location) {
    if (location == '/faculty' || location == '/faculty/') return true;
    final section = FacultyRoutes.sectionForLocation(location);
    if (section == 'profile' || section == 'dashboard') return true;
    return switch (key) {
      'adviser' => const {
        'deliverables',
        'weekly_reports',
        'adviser_grading',
        'defense_board',
        'audit_compliance',
        'uploader',
      }.contains(section),
      'instructor' => const {
        'deliverables',
        'student_teams',
        'uploader',
      }.contains(section),
      'pit_lead' => const {
        'pit_events',
        'rubrics',
        'cohort',
        'pit_student_import',
        'pit_instructors',
        'student_teams',
        'defense_scheduler',
        'defense_board',
        'grade_center',
        'curriculum_analytics',
        'project_archive',
        'audit_compliance',
        'uploader',
      }.contains(section),
      'documenter' => const {
        'documenter_records',
        'uploader',
      }.contains(section),
      'faculty' => const {'project_archive', 'uploader'}.contains(section),
      _ => false,
    };
  }

  static bool isPhoneWidth(double? viewportWidth) =>
      viewportWidth != null &&
      viewportWidth > 0 &&
      viewportWidth < phoneBreakpoint;

  static bool canEvaluate(Map<String, dynamic> user) =>
      (user['role'] == 'faculty' || user['role'] == 'admin') &&
      user['is_panelist'] == true;

  static bool canDocument(Map<String, dynamic> user) =>
      (user['role'] == 'faculty' || user['role'] == 'admin') &&
      user['is_documenter'] == true;

  static bool canUsePhone(Map<String, dynamic> user) =>
      user['role'] == 'student' || canEvaluate(user) || canDocument(user);

  static bool hasStaffWorkspace(Map<String, dynamic> user) =>
      user['role'] == 'admin' ||
      (user['role'] == 'faculty' &&
          // Older servers omit instructor assignments. Preserve their staff home.
          (user['has_staff_workspace'] != false ||
              user['is_pit_lead'] == true ||
              user['is_adviser'] == true ||
              user['is_documenter'] == true ||
              user['is_uploader'] == true));

  static String home(
    Map<String, dynamic> user, {
    bool isWeb = kIsWeb,
    double? viewportWidth,
    String? preferredWorkspace,
  }) {
    final role = user['role'];
    if (role == 'guest_panelist') return AppRoutes.guestDefenses;
    if (role == 'student') return AppRoutes.student;
    if (isWeb && preferredWorkspace != null) {
      final preferred = StaffWorkspace.resolve(user, preferredWorkspace);
      final uri = Uri.tryParse(preferredWorkspace);
      if (preferred != null &&
          uri != null &&
          uri.path.startsWith('/faculty') &&
          supportsFacultyRoute(preferred.key, uri.path)) {
        return preferredWorkspace;
      }
    }
    // Remember explicit role-workspace choices in the browser as well as the app.
    if (preferredWorkspace == AppRoutes.documenter && canDocument(user)) {
      return AppRoutes.documenter;
    }
    if (preferredWorkspace == AppRoutes.panelist && canEvaluate(user)) {
      return AppRoutes.panelist;
    }
    if (isWeb && isPhoneWidth(viewportWidth)) {
      final staffHome = role == 'admin'
          ? AdminRoutes.overview
          : FacultyRoutes.dashboard;
      // Keep an explicit switch back to staff available on a phone browser.
      if (preferredWorkspace == staffHome && hasStaffWorkspace(user)) {
        return staffHome;
      }
      if (canEvaluate(user)) return AppRoutes.panelist;
      if (canDocument(user)) return AppRoutes.documenter;
    }
    if (isWeb) {
      if (role == 'admin') return AdminRoutes.overview;
      if (role == 'faculty') {
        return canEvaluate(user) && !hasStaffWorkspace(user)
            ? AppRoutes.panelist
            : FacultyRoutes.dashboard;
      }
    } else {
      if (canEvaluate(user)) return AppRoutes.panelist;
      if (canDocument(user)) return AppRoutes.documenter;
    }
    return AppRoutes.webWorkspaceOnly;
  }

  static String? redirect(
    Map<String, dynamic> user,
    String location, {
    bool isWeb = kIsWeb,
    double? viewportWidth,
    String? preferredWorkspace,
  }) {
    final requested = Uri.parse(location);
    location = requested.path;
    final destination = home(
      user,
      isWeb: isWeb,
      viewportWidth: viewportWidth,
      preferredWorkspace: preferredWorkspace,
    );
    if (user['role'] == 'guest_panelist') {
      return location == AppRoutes.guestDefenses ? null : destination;
    }
    if (location == AppRoutes.login || location == '/') return destination;
    if (location == AppRoutes.terms || location == AppRoutes.guestEntry) {
      return null;
    }
    if (location == AppRoutes.guestDefenses) return AppRoutes.guestEntry;
    // Adapt only staff landing pages on resize; leave open forms and deep links
    // in place so changing the window size cannot interrupt work.
    if (isWeb &&
        isPhoneWidth(viewportWidth) &&
        (destination == AppRoutes.panelist ||
            destination == AppRoutes.documenter) &&
        const {
          '/admin',
          '/admin/',
          AdminRoutes.overview,
          '/faculty',
          '/faculty/',
          FacultyRoutes.dashboard,
        }.contains(location)) {
      return destination;
    }
    final canManageDefenses =
        user['is_pit_lead'] == true || user['is_superuser'] == true;
    if (location.startsWith('/faculty')) {
      final key = requested.queryParameters['workspace'];
      if (key != null &&
          (StaffWorkspace.resolve(user, requested.toString()) == null ||
              !supportsFacultyRoute(key, location))) {
        return home(user, isWeb: isWeb, viewportWidth: viewportWidth);
      }
      if (user['role'] == 'admin' &&
          key == null &&
          location != FacultyRoutes.documenterRecords) {
        final preferred = preferredWorkspace == null
            ? null
            : StaffWorkspace.resolve(user, preferredWorkspace);
        final options = [
          if (preferred != null) preferred,
          ...StaffWorkspace.available(user),
        ];
        for (final option in options) {
          if (const {
                'adviser',
                'pit_lead',
                'instructor',
                'documenter',
              }.contains(option.key) &&
              supportsFacultyRoute(option.key, location)) {
            return option.at(location, parameters: requested.queryParameters);
          }
        }
        return destination;
      }
    }
    final allowed = switch (location) {
      AppRoutes.student => user['role'] == 'student',
      _ when location.startsWith('${AppRoutes.student}/') =>
        user['role'] == 'student',
      AppRoutes.panelist => canEvaluate(user),
      AppRoutes.documenter => canDocument(user),
      _ when RegExp(r'^/documenter/minutes/\d+$').hasMatch(location) =>
        canDocument(user),
      AppRoutes.settings => canUsePhone(user),
      AppRoutes.webWorkspaceOnly => destination == AppRoutes.webWorkspaceOnly,
      _ when location == '/admin' || location.startsWith('/admin/') =>
        isWeb && user['role'] == 'admin',
      FacultyRoutes.documenterRecords => isWeb && canDocument(user),
      _
          when location == FacultyRoutes.curriculumAnalytics ||
              location.startsWith('${FacultyRoutes.curriculumAnalytics}/') =>
        isWeb &&
            canUseFaculty(user) &&
            user['is_pit_lead'] == true &&
            const {
              '1st Year',
              '2nd Year',
              '3rd Year',
            }.contains(user['pit_lead_year']),
      _
          when location == FacultyRoutes.defenseScheduleBulkImport ||
              location == FacultyRoutes.defenseScheduler ||
              location.startsWith('${FacultyRoutes.defenseScheduler}/') =>
        isWeb && canUseFaculty(user) && canManageDefenses,
      _
          when location == FacultyRoutes.defenseBoard ||
              location.startsWith('${FacultyRoutes.defenseBoard}/') =>
        isWeb &&
            canUseFaculty(user) &&
            (canManageDefenses || user['is_adviser'] == true),
      _ when location == '/faculty' || location.startsWith('/faculty/') =>
        isWeb && canUseFaculty(user),
      _ => false,
    };
    return allowed ? null : destination;
  }
}
