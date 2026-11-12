import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/navigation/staff_workspaces.dart';
import 'package:defensys/navigation/workspace_access.dart';
import 'package:defensys/navigation/workspace_http_context.dart';
import 'package:defensys/navigation/workspace_preference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'documenter-only accounts have one workspace without a staff fallback',
    () {
      for (final hint in [null, false, true]) {
        final user = {
          'role': 'faculty',
          'is_documenter': true,
          if (hint != null) 'has_staff_workspace': hint,
        };
        expect(StaffWorkspace.available(user).map((option) => option.key), [
          'documenter',
        ]);
      }
      expect(
        StaffWorkspace.available({
          'role': 'faculty',
          'is_documenter': true,
          'is_pit_lead': true,
          'pit_lead_year': '1st Year',
        }).map((option) => option.key),
        ['pit_lead', 'documenter'],
      );
      // Older faculty/uploader accounts still need their existing web home.
      for (final user in [
        {'role': 'faculty'},
        {'role': 'faculty', 'is_uploader': true},
      ]) {
        expect(StaffWorkspace.available(user).map((option) => option.key), [
          'faculty',
        ]);
      }
    },
  );

  test(
    'documenter destinations preserve platform and enforce role context',
    () {
      const documenter = StaffWorkspace('documenter', 'Documenter');
      const web = '/faculty/dashboard?workspace=documenter';
      expect(documenter.locationFor(isWeb: true), web);
      expect(documenter.locationFor(isWeb: false), AppRoutes.documenter);
      for (final role in ['faculty', 'admin']) {
        final user = {'role': role, 'is_documenter': true};
        expect(StaffWorkspace.resolve(user, web)?.key, 'documenter');
        expect(
          StaffWorkspace.resolve(user, AppRoutes.documenter)?.key,
          'documenter',
        );
        for (final path in [
          web,
          '/faculty/documenter-records?workspace=documenter',
          '/faculty/profile?workspace=documenter',
        ]) {
          expect(WorkspaceAccess.redirect(user, path, isWeb: true), isNull);
        }
        expect(
          WorkspaceAccess.home(user, isWeb: true, preferredWorkspace: web),
          web,
        );
        expect(
          WorkspaceAccess.redirect(
            user,
            AppRoutes.documenter,
            isWeb: true,
            viewportWidth: 1440,
          ),
          isNull,
        );
        expect(
          WorkspaceAccess.redirect(
            user,
            '/documenter/minutes/42',
            isWeb: true,
            viewportWidth: 1440,
          ),
          isNull,
        );
        for (final isWeb in [true, false]) {
          expect(
            WorkspaceAccess.redirect(
              user,
              AppRoutes.documenter,
              isWeb: isWeb,
              viewportWidth: 390,
            ),
            isNull,
          );
        }
        final revoked = {...user, 'is_documenter': false};
        expect(StaffWorkspace.resolve(revoked, web), isNull);
        expect(
          WorkspaceAccess.redirect(revoked, web, isWeb: true),
          role == 'admin' ? AdminRoutes.overview : FacultyRoutes.dashboard,
        );
      }
    },
  );

  const admin = {'role': 'admin', 'is_adviser': true};
  test('admin adviser has distinct admin and adviser destinations', () {
    final options = StaffWorkspace.available(admin);
    expect(options.map((o) => o.key), ['admin', 'adviser']);
    final adviser = options.last.location;
    expect(WorkspaceAccess.redirect(admin, adviser, isWeb: true), isNull);
    expect(
      WorkspaceAccess.home(admin, isWeb: true, preferredWorkspace: adviser),
      adviser,
    );
    expect(
      WorkspaceAccess.redirect(admin, FacultyRoutes.deliverables, isWeb: true),
      '/faculty/deliverables?workspace=adviser',
    );
    expect(
      WorkspaceAccess.redirect(
        admin,
        FacultyRoutes.defenseScheduler,
        isWeb: true,
      ),
      AdminRoutes.overview,
    );
    expect(
      WorkspaceAccess.redirect(admin, AdminRoutes.users, isWeb: true),
      isNull,
    );
  });
  test('revoked or forged choices do not open a faculty workspace', () {
    const plain = {'role': 'admin'};
    for (final location in [
      '/faculty/dashboard?workspace=adviser',
      '/faculty/dashboard?workspace=unknown',
      '/faculty/grade-center?workspace=adviser',
    ]) {
      expect(
        WorkspaceAccess.redirect(plain, location, isWeb: true),
        AdminRoutes.overview,
      );
    }
    expect(
      WorkspaceAccess.redirect(
        admin,
        '/faculty/grade-center?workspace=adviser',
        isWeb: true,
      ),
      AdminRoutes.overview,
    );
    expect(
      WorkspaceAccess.home(
        plain,
        isWeb: true,
        preferredWorkspace: '/faculty/dashboard?workspace=adviser',
      ),
      AdminRoutes.overview,
    );
    expect(
      WorkspaceAccess.home(
        admin,
        isWeb: false,
        preferredWorkspace: '/faculty/dashboard?workspace=adviser',
      ),
      AppRoutes.webWorkspaceOnly,
    );
  });
  test(
    'PIT destinations preserve year and section, without a Capstone instructor workspace',
    () {
      final user = {
        ...admin,
        'is_pit_lead': true,
        'pit_lead_year': '2nd Year',
        'staff_workspaces': {
          'pit_instructor_sections': [
            {'year_level': '1st Year', 'section': 'BSIT-1A'},
            {'year_level': '1st Year', 'section': 'BSIT-1B'},
          ],
          'capstone_instructor': true,
        },
      };
      final options = StaffWorkspace.available(user);
      expect(options.map((o) => o.key), [
        'admin',
        'adviser',
        'pit_lead',
        'instructor',
        'instructor',
      ]);
      for (final option in options.skip(1)) {
        expect(
          StaffWorkspace.resolve(user, option.location)?.location,
          option.location,
        );
        expect(
          WorkspaceAccess.redirect(user, option.location, isWeb: true),
          isNull,
        );
      }
      expect(
        WorkspaceAccess.redirect(
          user,
          '/faculty/dashboard?workspace=instructor&workspaceYear=1st%20Year&workspaceSection=BSIT-1C',
          isWeb: true,
        ),
        AdminRoutes.overview,
      );
    },
  );
  test(
    'request context narrows legacy operations without changing analytics response flags',
    () {
      final route = Uri.parse(
        '/faculty/dashboard?workspace=pit_lead&workspaceYear=2nd%20Year',
      );
      final api = Uri.parse(
        'https://example.test/api/grading/grades/?workspace=operations&scope=pit',
      );
      final headers = workspaceHeadersForRoute(route, api);
      expect(headers['X-Defensys-Workspace'], 'pit_lead');
      expect(workspaceRequestUri(api, headers).queryParameters, {
        'workspace': 'pit_lead',
        'scope': 'pit',
      });
      final analytics = Uri.parse(
        'https://example.test/api/curriculum-analytics/explorer/?workspace=true',
      );
      expect(workspaceRequestUri(analytics, headers), analytics);
      expect(
        workspaceHeadersForRoute(Uri.parse('/admin/overview'), api),
        isEmpty,
      );
      expect(workspaceHeadersForRoute(route, Uri.parse('/api/me/')), isEmpty);
    },
  );
  test(
    'preference reader accepts versioned and legacy values and rejects malformed data',
    () async {
      SharedPreferences.setMockInitialValues({
        'app.workspace.1': '/panelist',
        'app.workspace.2':
            '{"version":1,"location":"/faculty/dashboard?workspace=adviser"}',
        'app.workspace.3': '{bad',
      });
      expect(await readRememberedWorkspace(1), '/panelist');
      expect(
        await readRememberedWorkspace(2),
        '/faculty/dashboard?workspace=adviser',
      );
      expect(await readRememberedWorkspace(3), isNull);
    },
  );
}
