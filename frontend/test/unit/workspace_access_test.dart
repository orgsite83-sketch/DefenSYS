import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/navigation/workspace_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('documenter can enter phone assignments, editor and settings', () {
    const doc = {'role': 'faculty', 'is_documenter': true};
    expect(WorkspaceAccess.home(doc, isWeb: false), AppRoutes.documenter);
    expect(WorkspaceAccess.canUsePhone(doc), isTrue);
    for (final route in [
      AppRoutes.documenter,
      '/documenter/minutes/42',
      AppRoutes.settings,
    ]) {
      expect(WorkspaceAccess.redirect(doc, route, isWeb: false), isNull);
    }
    expect(
      WorkspaceAccess.redirect(doc, AppRoutes.panelist, isWeb: false),
      AppRoutes.documenter,
    );
  });
  test('remembered workspace is honored only while its role is eligible', () {
    const mixedDoc = {
      'role': 'faculty',
      'is_documenter': true,
      'is_panelist': true,
    };
    expect(
      WorkspaceAccess.home(
        mixedDoc,
        isWeb: false,
        preferredWorkspace: AppRoutes.documenter,
      ),
      AppRoutes.documenter,
    );
    expect(
      WorkspaceAccess.home(
        {...mixedDoc, 'is_documenter': false},
        isWeb: false,
        preferredWorkspace: AppRoutes.documenter,
      ),
      AppRoutes.panelist,
    );
    expect(
      WorkspaceAccess.home(
        mixedDoc,
        isWeb: false,
        preferredWorkspace: '/admin/users',
      ),
      AppRoutes.panelist,
    );
    expect(
      WorkspaceAccess.redirect(
        {'role': 'student'},
        '/documenter/minutes/42',
        isWeb: false,
      ),
      AppRoutes.student,
    );
  });
  const student = {'role': 'student'};
  const panelist = {
    'role': 'faculty',
    'is_panelist': true,
    'has_staff_workspace': false,
  };
  const staff = {
    'role': 'faculty',
    'is_panelist': false,
    'has_staff_workspace': true,
  };
  const mixed = {
    'role': 'faculty',
    'is_panelist': true,
    'has_staff_workspace': true,
  };
  for (final isWeb in [true, false]) {
    test('Student home and allowed routes on web=$isWeb', () {
      expect(WorkspaceAccess.home(student, isWeb: isWeb), AppRoutes.student);
      for (final path in [
        AppRoutes.student,
        AppRoutes.settings,
        AppRoutes.terms,
      ]) {
        expect(WorkspaceAccess.redirect(student, path, isWeb: isWeb), isNull);
      }
      for (final path in [
        AppRoutes.panelist,
        '/admin/users',
        '/faculty/dashboard',
      ]) {
        expect(
          WorkspaceAccess.redirect(student, path, isWeb: isWeb),
          AppRoutes.student,
        );
      }
    });
    test('Eligible regular panelist home on web=$isWeb', () {
      expect(WorkspaceAccess.home(panelist, isWeb: isWeb), AppRoutes.panelist);
      expect(
        WorkspaceAccess.redirect(panelist, AppRoutes.panelist, isWeb: isWeb),
        isNull,
      );
      expect(
        WorkspaceAccess.redirect(panelist, AppRoutes.student, isWeb: isWeb),
        AppRoutes.panelist,
      );
    });
    test(
      'Mixed faculty separates evaluation from staff access on web=$isWeb',
      () {
        expect(
          WorkspaceAccess.home(mixed, isWeb: isWeb),
          isWeb ? FacultyRoutes.dashboard : AppRoutes.panelist,
        );
        expect(
          WorkspaceAccess.redirect(mixed, AppRoutes.panelist, isWeb: isWeb),
          isNull,
        );
        expect(
          WorkspaceAccess.redirect(
            mixed,
            FacultyRoutes.dashboard,
            isWeb: isWeb,
          ),
          isWeb ? null : AppRoutes.panelist,
        );
      },
    );
    test(
      'Faculty without panelist eligibility cannot enter evaluation on web=$isWeb',
      () {
        expect(
          WorkspaceAccess.redirect(staff, AppRoutes.panelist, isWeb: isWeb),
          isWeb ? FacultyRoutes.dashboard : AppRoutes.webWorkspaceOnly,
        );
        expect(
          WorkspaceAccess.redirect(staff, AppRoutes.student, isWeb: isWeb),
          isWeb ? FacultyRoutes.dashboard : AppRoutes.webWorkspaceOnly,
        );
      },
    );
    test(
      'Admin stays web only, including an admin with panelist flag on web=$isWeb',
      () {
        const admin = {'role': 'admin', 'is_panelist': true};
        expect(
          WorkspaceAccess.home(admin, isWeb: isWeb),
          isWeb ? AdminRoutes.overview : AppRoutes.webWorkspaceOnly,
        );
        expect(
          WorkspaceAccess.redirect(admin, AppRoutes.panelist, isWeb: isWeb),
          isWeb ? AdminRoutes.overview : AppRoutes.webWorkspaceOnly,
        );
      },
    );
  }
  test('Guests cannot enter institutional settings or staff routes', () {
    for (final path in [
      AppRoutes.settings,
      AppRoutes.student,
      AppRoutes.panelist,
      '/admin/users',
    ]) {
      expect(
        WorkspaceAccess.redirect({'role': 'guest_panelist'}, path, isWeb: true),
        AppRoutes.guestDefenses,
      );
    }
  });
  test(
    'Older server payload preserves staff default until assignment hint is known',
    () {
      expect(
        WorkspaceAccess.home({
          'role': 'faculty',
          'is_panelist': true,
        }, isWeb: true),
        FacultyRoutes.dashboard,
      );
    },
  );
  test('Profile flags retain management home despite a stale false hint', () {
    for (final flag in [
      'is_pit_lead',
      'is_adviser',
      'is_documenter',
      'is_uploader',
    ]) {
      expect(
        WorkspaceAccess.home({...panelist, flag: true}, isWeb: true),
        FacultyRoutes.dashboard,
      );
    }
  });
}
