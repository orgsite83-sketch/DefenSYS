import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/navigation/staff_workspaces.dart';
import 'package:defensys/navigation/workspace_access.dart';
import 'package:defensys/navigation/workspace_http_context.dart';
import 'package:defensys/navigation/workspace_preference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
