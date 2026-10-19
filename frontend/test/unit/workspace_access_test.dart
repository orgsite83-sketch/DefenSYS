import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/navigation/workspace_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('curriculum analytics route belongs to an assigned PIT Lead', () {
    const lead = {'role': 'faculty', 'is_pit_lead': true, 'pit_lead_year': '2nd Year'};
    expect(WorkspaceAccess.redirect(lead, FacultyRoutes.curriculumAnalytics, isWeb: true), isNull);
    for (final user in [
      {'role': 'faculty', 'is_adviser': true},
      {...lead, 'is_pit_lead': false},
      {...lead, 'pit_lead_year': ''},
      {...lead, 'pit_lead_year': '4th Year'},
    ]) {
      expect(WorkspaceAccess.redirect(user, FacultyRoutes.curriculumAnalytics, isWeb: true), FacultyRoutes.dashboard);
    }
    expect(FacultyRoutes.sectionForLocation(FacultyRoutes.curriculumAnalytics), 'curriculum_analytics');
    expect(FacultyRoutes.pathForSection('curriculum_analytics'), FacultyRoutes.curriculumAnalytics);
  });
  test('documenter web routes exclude defense management', () {
    const doc = {'role': 'faculty', 'is_documenter': true};
    for (final route in [
      FacultyRoutes.dashboard,
      FacultyRoutes.documenterRecords,
      FacultyRoutes.profile,
    ]) {
      expect(WorkspaceAccess.redirect(doc, route, isWeb: true), isNull);
    }
    for (final route in [
      FacultyRoutes.defenseBoard,
      FacultyRoutes.defenseScheduleBulkImport,
      FacultyRoutes.defenseScheduler,
      '${FacultyRoutes.defenseBoard}/requests/external/12',
    ]) {
      expect(
        WorkspaceAccess.redirect(doc, route, isWeb: true),
        FacultyRoutes.dashboard,
      );
      expect(
        WorkspaceAccess.redirect(
          {...doc, 'is_pit_lead': true}, route, isWeb: true,
        ),
        isNull,
      );
    }
    expect(
      WorkspaceAccess.redirect(
        {'role': 'faculty'}, FacultyRoutes.documenterRecords, isWeb: true,
      ),
      FacultyRoutes.dashboard,
    );
    expect(
      WorkspaceAccess.redirect(
        {...doc, 'is_documenter': false, 'is_pit_lead': true},
        FacultyRoutes.documenterRecords, isWeb: true,
      ),
      FacultyRoutes.dashboard,
    );
    expect(
      WorkspaceAccess.redirect(
        {...doc, 'is_adviser': true}, FacultyRoutes.defenseBoard, isWeb: true,
      ),
      isNull,
    );
    expect(
      FacultyRoutes.sectionForLocation(FacultyRoutes.documenterRecords),
      'documenter_records',
    );
    expect(
      FacultyRoutes.pathForSection('documenter_records'),
      FacultyRoutes.documenterRecords,
    );
  });
  test(
    'browser restores an eligible role workspace and rejects a revoked role',
    () {
      const faculty = {
        'role': 'faculty',
        'is_documenter': true,
        'is_panelist': true,
        'has_staff_workspace': true,
      };
      for (final route in [AppRoutes.documenter, AppRoutes.panelist]) {
        expect(
          WorkspaceAccess.home(faculty, isWeb: true, preferredWorkspace: route),
          route,
        );
        expect(
          WorkspaceAccess.redirect(
            faculty,
            FacultyRoutes.dashboard,
            isWeb: true,
            preferredWorkspace: route,
          ),
          isNull,
        );
      }
      expect(
        WorkspaceAccess.home(
          {...faculty, 'is_documenter': false},
          isWeb: true,
          preferredWorkspace: AppRoutes.documenter,
        ),
        FacultyRoutes.dashboard,
      );
      expect(
        WorkspaceAccess.home(
          faculty,
          isWeb: false,
          preferredWorkspace: FacultyRoutes.dashboard,
        ),
        AppRoutes.panelist,
      );
    },
  );
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
      'Admin without panelist eligibility cannot enter evaluation on web=$isWeb',
      () {
        const plainAdmin = {'role': 'admin', 'is_panelist': false};
        expect(
          WorkspaceAccess.home(plainAdmin, isWeb: isWeb),
          isWeb ? AdminRoutes.overview : AppRoutes.webWorkspaceOnly,
        );
        expect(
          WorkspaceAccess.redirect(plainAdmin, AppRoutes.panelist, isWeb: isWeb),
          isWeb ? AdminRoutes.overview : AppRoutes.webWorkspaceOnly,
        );
      },
    );
    test(
      'Admin with panelist eligibility can evaluate on web=$isWeb',
      () {
        const panelistAdmin = {'role': 'admin', 'is_panelist': true};
        expect(WorkspaceAccess.canEvaluate(panelistAdmin), isTrue);
        expect(
          WorkspaceAccess.home(panelistAdmin, isWeb: isWeb),
          isWeb ? AdminRoutes.overview : AppRoutes.panelist,
        );
        expect(
          WorkspaceAccess.redirect(panelistAdmin, AppRoutes.panelist, isWeb: isWeb),
          isNull,
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
