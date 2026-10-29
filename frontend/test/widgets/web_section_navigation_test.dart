import 'dart:convert';
import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/utils/import/schedule_import_draft.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/services/network/connectivity_provider.dart';
import 'package:defensys/navigation/app_router.dart';
import 'package:defensys/notifications/notification_request_screen.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/screens/web/admin/user_management/user_management_screen.dart';
import 'package:defensys/screens/web/admin/user_management/access_control/access_control_view.dart';
import 'package:http/http.dart' as http;
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/screens/web/admin/grade_center_team_detail_screen.dart';
import 'package:defensys/screens/web/admin/defense_board_screen.dart';
import 'package:defensys/screens/web/admin/defense_board/components/defense_schedule_bulk_import_view.dart';
import 'package:defensys/screens/web/admin/student_teams_screen.dart';
import 'package:defensys/screens/web/admin/team_detail_page.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/services/defense_board_provider.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/grade_center_provider.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/services/team_detail_provider.dart';
import 'package:defensys/services/unsaved_changes_provider.dart';
import 'package:defensys/services/app/data_refresh_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/capture_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:defensys/screens/web/faculty/team_roster_screen.dart';
import 'package:defensys/screens/web/faculty/pit_lead/pit_lead_cohort_screen.dart';
import 'package:defensys/services/academic/team_roster_service.dart';
import 'package:defensys/services/academic/student_academic_records_provider.dart';
import 'package:defensys/services/pit_lead_cohort_provider.dart';
import 'package:defensys/services/pit_instructor_provider.dart';
import 'package:defensys/services/user_management_provider.dart';

class _PitRoster extends Fake implements TeamRosterService {
  bool sectionsAvailable = false;
  int loads = 0;
  @override
  Future<Map<String, dynamic>> load(Map<String, dynamic> scope) async {
    loads++;
    return {
      'semester': '1st Semester, A.Y. 2026-2027',
      'year_level': '3rd Year',
      'section': sectionsAvailable ? 'BSIT-3A' : null,
      'scope_options': sectionsAvailable
          ? [
              {'year_level': '3rd Year', 'section': 'BSIT-3A'},
            ]
          : [],
      'can_import_sections': true,
      'can_generate': false,
      'rosters': sectionsAvailable
          ? [
              {
                'id': null,
                'name': 'Current roster',
                'status': 'Default for upcoming events',
                'teams': [],
                'team_count': 0,
                'student_count': 0,
                'ready_count': 0,
              },
            ]
          : [],
    };
  }
}

class _PitCohort extends PitLeadCohortNotifier {
  @override
  PitLeadCohortState build() => PitLeadCohortState(pitLeadYear: '3rd Year');
  @override
  Future<void> fetchCohort({
    String? search,
    String? teamStatusFilter,
    String? scope,
  }) async {}
}

class _PitInstructors extends PitInstructorNotifier {
  @override
  PitInstructorState build() => const PitInstructorState(yearLevel: '3rd Year');
  @override
  Future<void> fetchAssignments() async {}
}

class _Records extends StudentAcademicRecordsNotifier {
  @override
  StudentAcademicRecordsState build() => const StudentAcademicRecordsState();
  @override
  Future<void> fetchRecords({
    String? search,
    String? schoolYear,
    String? semester,
    String? successMessage,
  }) async {}
}

class _Users extends UserManagementNotifier {
  @override
  UserManagementState build() => const UserManagementState();
  @override
  Future<void> fetchUsers({
    String? search,
    String? role,
    String? successMessage,
  }) async {}
}

class _Board extends DefenseBoardNotifier {
  int loads = 0;

  @override
  Future<void> fetchBoard({
    String? search,
    String? stage,
    String? status,
    String? scope,
    String? adviser,
    String? section,
    String? successMessage,
  }) async {
    loads++;
  }
}

class _ActionClient implements AuthenticatedHttpClient {
  _ActionClient({this.lead = false});
  final bool lead;
  bool requested = false, eligible = false;
  int nominations = 0;
  final calls = <Uri>[];
  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) async {
    calls.add(uri);
    if (uri.path == '/api/users/panelist-pool/') {
      return http.Response(
        jsonEncode({
          'faculty': [
            {
              'id': 1,
              'name': 'Requested Faculty',
              'username': 'FAC-1',
              'is_panelist': eligible,
            },
            {
              'id': 2,
              'name': 'Other Faculty',
              'username': 'FAC-2',
              'is_panelist': true,
            },
          ],
          'panelist_requests': requested && !eligible
              ? [
                  {'id': 42, 'faculty_id': 1, 'status': 'pending'},
                ]
              : [],
          'can_approve_panelists': !lead,
        }),
        200,
      );
    }
    if (uri.path == '/api/users/panelist-requests/') {
      return http.Response(
        jsonEncode({
          'panelist_requests':
              requested &&
                  !eligible &&
                  uri.queryParameters['status'] == 'pending'
              ? [
                  {
                    'id': 42,
                    'faculty_id': 1,
                    'faculty_name': 'Requested Faculty',
                    'status': 'pending',
                    'requested_by_name': 'PIT Lead',
                    'pit_year': '3rd Year',
                  },
                ]
              : [],
          'pending_count': requested && !eligible ? 1 : 0,
        }),
        200,
      );
    }
    if (uri.path == '/api/users/1/') {
      return http.Response(
        '{"user":{"id":1,"name":"Requested Faculty","role":"faculty","is_panelist":true,"is_adviser":true,"is_pit_lead":false,"is_documenter":false}}',
        200,
      );
    }
    return http.Response(
      '{"request":{"id":42,"faculty_id":1,"faculty_name":"Requested Faculty","status":"${requested && !eligible ? 'pending' : 'approved'}","requested_by_name":"PIT Lead","reviewed_by_name":"Administrator"},"can_review":${!lead}}',
      200,
    );
  }

  @override
  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    calls.add(uri);
    nominations++;
    requested = true;
    return http.Response('{"request":{"id":42}}', 201);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Schedules extends DefenseSchedulerNotifier {
  @override
  Future<void> refreshPanelistPool() async {}
  @override
  Future<List<Map<String, dynamic>>> fetchImportConflictSchedules() async => [];
  @override
  Future<void> fetchSchedules({
    String? search,
    String? scope,
    String? status,
    String? successMessage,
  }) async {}
}

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _ImportSchedules extends DefenseSchedulerNotifier {
  @override
  Future<void> fetchSchedules({
    String? search,
    String? scope,
    String? status,
    String? successMessage,
  }) async {}
  @override
  Future<List<Map<String, dynamic>>> fetchImportConflictSchedules() async => [];
  @override
  Future<Map<String, dynamic>?> fetchPitEventConfig({
    required String eventName,
    int? semesterId,
  }) async => {'panel_rubric_id': 10, 'peer_rubric_id': 20};
  @override
  DefenseSchedulerState build() => const DefenseSchedulerState(
    requiresPanelistApproval: true,
    activeSemester: {'id': 1},
    faculty: [
      {'id': 1, 'name': 'Requested Faculty', 'is_panelist': false},
      {'id': 2, 'name': 'Other Faculty', 'is_panelist': true},
    ],
    pitEvents: [
      {
        'event_name': 'PIT 1',
        'year_level': '3rd Year',
        'requires_endorsement': false,
      },
    ],
    teams: [
      {
        'id': 99,
        'name': 'Team Aurora',
        'project_title': 'Prototype',
        'level': '3rd Year PIT',
        'year_level': '3rd Year',
      },
    ],
  );
}

class _Auth extends AuthNotifier {
  _Auth(this.faculty);
  final bool faculty;

  @override
  AuthState build() => AuthState(
    token: 'test-token',
    user: {
      'id': 1,
      'username': 'tester',
      'role': faculty ? 'faculty' : 'admin',
      'is_superuser': !faculty,
      'is_pit_lead': faculty,
      'pit_lead_year': '3rd Year',
    },
  );
}

class _Dashboard extends DashboardNotifier {
  _Dashboard(super.role);

  @override
  DashboardState build() => DashboardState(
    data: {
      'active_semester': '2026-2027',
      'faculty': {'name': 'Test Faculty'},
      'pit_lead_year': '3rd Year',
      'roles': {'pit_lead': true, 'pit_lead_year': '3rd Year'},
    },
  );

  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

class _Periods extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() => const AcademicPeriodState();

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

class _Notifications extends NotificationsNotifier {
  _Notifications([super.workspace = 'admin']);
  @override
  NotificationsState build() => const NotificationsState();

  @override
  Future<void> fetchNotifications({
    bool? unreadOnly,
    bool loadMore = false,
  }) async {}
}

class _Stages extends DefenseStagesNotifier {
  @override
  Future<void> fetchStages({String? scope,
    String? intake,
    String? phase,
    String? stage,
    String? successMessage,}) async {}
}

class _Teams extends StudentTeamsNotifier {
  int loads = 0;

  void emitUpdate() => state = state.copyWith(counts: {'total': 20});

  @override
  StudentTeamsState build() => StudentTeamsState(
    level: 'Capstone',
    teams: List.generate(
      20,
      (index) => {
        'id': index + 1,
        'name': index == 0 ? 'Team AgriSense' : 'Team ${index + 1}',
        'project_title': 'Smart Agriculture',
        'section': 'BSIT-4A',
        'year_level': '4th Year',
        'status': 'Approved',
      },
    ),
  );

  @override
  Future<void> fetchTeams({
    String? historyIntake,
    String? historyPhase,
    String? historyStage,
    String? workspace,
    String? search,
    String? level,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? eventName,
    bool clearEventName = false,
    bool clearYearLevel = false,
    String? successMessage,
  }) async {
    loads++;
  }
}

class _Team extends TeamDetailNotifier {
  _Team() : super(1);
  int loads = 0;

  @override
  TeamDetailState build() => const TeamDetailState(
    team: {
      'id': 1,
      'name': 'Team AgriSense',
      'project_title': 'Smart Agriculture',
      'level': 'Capstone',
      'status': 'Approved',
      'member_ids': <int>[],
    },
    grades: [
      {
        'id': 6,
        'team_name': 'Team AgriSense',
        'scope': 'capstone',
        'stage_label': 'Concept Proposal',
        'status': 'published',
        'is_officially_complete': true,
        'final_grade': '89.25',
      },
    ],
  );

  @override
  Future<void> load() async {
    loads++;
  }
}

class _Grades extends GradeCenterNotifier {
  int loads = 0;
  int detailLoads = 0;

  @override
  GradeCenterState build() => const GradeCenterState(
    scope: 'capstone',
    grades: [
      {
        'id': 6,
        'team_name': 'Team AgriSense',
        'project_title': 'Smart Agriculture',
        'scope': 'capstone',
        'stage_label': 'Concept Proposal',
        'status': 'published',
        'breakdowns': <Map<String, dynamic>>[],
      },
    ],
  );

  @override
  Future<void> fetchGrades({
    String? historySemester,
    String? search,
    String? yearLevel,
    String? status,
    String? scope,
    String? successMessage,
  }) async {
    loads++;
  }

  @override
  Future<bool> refreshGrade(int gradeId) async {
    detailLoads++;
    return true;
  }
}

void main() {
  Future<ProviderContainer> pumpWorkspace(
    WidgetTester tester,
    String location, {
    bool faculty = false,
    double width = 1600,
    AuthenticatedHttpClient? client,
    List<Override> overrides = const [],
    Map<String, Object> preferences = const {},
    bool dark = false,
    DefenseSchedulerNotifier? scheduler,
  }) async {
    await loadPreviewFonts(force: true);
    SharedPreferences.setMockInitialValues(preferences);
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        if (client != null)
          authenticatedHttpClientProvider.overrideWithValue(client),
        authProvider.overrideWith(() => _Auth(faculty)),
        connectivityProvider.overrideWith(_Online.new),
        dashboardProvider('admin').overrideWith(() => _Dashboard('admin')),
        dashboardProvider('faculty').overrideWith(() => _Dashboard('faculty')),
        academicPeriodProvider.overrideWith(_Periods.new),
        notificationsProvider.overrideWith2(_Notifications.new),
        defenseStagesProvider.overrideWith(_Stages.new),
        defenseBoardProvider.overrideWith(_Board.new),
        defenseSchedulerProvider.overrideWith(() => scheduler ?? _Schedules()),
        studentTeamsProvider.overrideWith(_Teams.new),
        teamDetailProvider(1).overrideWith(_Team.new),
        gradeCenterProvider.overrideWith(_Grades.new),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    addTearDown(router.dispose);
    router.go(location);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'PIT Assign instructors opens the managed tab and leaves sidebar navigation usable',
    (tester) async {
      final roster = _PitRoster();
      final container = await pumpWorkspace(
        tester,
        '/faculty/student-teams',
        faculty: true,
        overrides: [
          teamRosterServiceProvider.overrideWithValue(roster),
          pitLeadCohortProvider.overrideWith(_PitCohort.new),
          pitInstructorProvider.overrideWith(_PitInstructors.new),
          studentAcademicRecordsProvider.overrideWith(_Records.new),
          userManagementProvider.overrideWith(_Users.new),
        ],
      );
      final router = container.read(appRouterProvider);
      await tester.tap(find.text('Team roster'));
      await tester.pumpAndSettle();
      final rosterState = tester.state(find.byType(TeamRosterScreen));
      expect(find.text('Assign instructors'), findsOneWidget);
      for (var visit = 0; visit < 2; visit++) {
        await tester.tap(find.text('Assign instructors'));
        await tester.pumpAndSettle();
        expect(find.byType(PitLeadCohortScreen), findsOneWidget);
        expect(router.state.uri.path, '/faculty/cohort');
        expect(router.state.uri.queryParameters['tab'], 'instructors');
        expect(find.text('Batch Enrollment'), findsNothing);
        await tester.tap(find.text('Students & Enrollment'));
        await tester.pumpAndSettle();
        expect(find.text('Batch Enrollment'), findsOneWidget);
        expect(router.state.uri.queryParameters['tab'], 'students');
        // Browser history sends route information for the previous/next URL.
        await router.routeInformationProvider.didPushRouteInformation(
          RouteInformation(uri: Uri.parse('/faculty/cohort?tab=instructors')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Batch Enrollment'), findsNothing);
        await router.routeInformationProvider.didPushRouteInformation(
          RouteInformation(uri: Uri.parse('/faculty/cohort?tab=students')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Batch Enrollment'), findsOneWidget);
        await tester.tap(find.text('Section Instructors'));
        await tester.pumpAndSettle();
        expect(router.state.uri.queryParameters['tab'], 'instructors');
        expect(find.text('Batch Enrollment'), findsNothing);
        await tester.tap(find.text('Student Teams').first);
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '/faculty/student-teams/roster');
        expect(tester.state(find.byType(TeamRosterScreen)), same(rosterState));
        expect(router.state.uri.queryParameters['year'], '3rd Year');
      }
      roster.sectionsAvailable = true;
      await tester.tap(find.text('Assign instructors'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Student Teams').first);
      await tester.pumpAndSettle();
      expect(find.text('Import teams or assign instructors'), findsNothing);
      expect(find.text('BSIT-3A · 3rd Year'), findsOneWidget);
      expect(find.text('Import teams'), findsOneWidget);
      expect(roster.loads, greaterThanOrEqualTo(4));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('request deep link opens its record in the actual admin router', (
    tester,
  ) async {
    final client = _ActionClient();
    final container = await pumpWorkspace(
      tester,
      '/admin/defense-board/requests/panelist/42',
      client: client,
    );
    expect(find.byType(NotificationRequestScreen), findsOneWidget);
    expect(find.byType(UserManagementScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('panelist-request-sheet')),
      findsOneWidget,
    );
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/admin/users',
    );
    expect(find.text('Requested Faculty'), findsOneWidget);
    expect(
      find.text('This request has already been reviewed.'),
      findsOneWidget,
    );
    expect(
      client.calls.any((u) => u.path == '/api/users/panelist-requests/42/'),
      isTrue,
    );
    container.read(appRouterProvider).go('/admin/academic-periods');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('panelist-request-sheet')), findsNothing);
    container
        .read(appRouterProvider)
        .go('/admin/defense-board/requests/panelist/42');
    await tester.pumpAndSettle();
    expect(find.byType(NotificationRequestScreen), findsOneWidget);
    await tester.tap(find.text('Open role editor'));
    await tester.pumpAndSettle();
    expect(find.byType(AccessControlView), findsOneWidget);
    expect(find.byKey(const ValueKey('panelist-request-sheet')), findsNothing);
  });

  testWidgets(
    'PIT import issue opens the affected faculty and returns to a refreshed draft',
    (tester) async {
      final client = _ActionClient(lead: true);
      final draft = ScheduleImportDraft(
        parsed: ParsedScheduleImport(
          stage: 'PIT 1',
          rows: const [
            ParsedScheduleImportRow(
              sheetRow: 7,
              time: '08:00 - 09:00',
              startTime: '08:00',
              endTime: '09:00',
              teamName: 'Team Aurora',
              projectTitle: 'Prototype',
              adviser: '',
              members: [],
              chair: 'Requested Faculty',
              panelMembers: ['Other Faculty'],
              documenter: '',
              room: 'Lab 1',
              date: '2026-11-27',
              stage: 'PIT 1',
              slotDuration: 60,
            ),
          ],
        ),
        scope: 'pit',
        eventName: 'PIT 1',
        semesterId: 1,
        panelRubricId: 10,
        peerRubricId: 20,
        savedAt: DateTime(2026, 10, 25),
      );
      final container = await pumpWorkspace(
        tester,
        '/faculty/defense-board/import',
        faculty: true,
        client: client,
        scheduler: _ImportSchedules(),
        preferences: {
          'defense_schedule_import_draft_pit': jsonEncode(draft.toJson()),
        },
        overrides: [
          pitLeadCohortProvider.overrideWith(_PitCohort.new),
          pitInstructorProvider.overrideWith(_PitInstructors.new),
          studentAcademicRecordsProvider.overrideWith(_Records.new),
          userManagementProvider.overrideWith(_Users.new),
        ],
      );
      final router = container.read(appRouterProvider);
      final warning = find.byTooltip('View panelist eligibility and requests');
      final importState = tester.state(
        find.byType(DefenseScheduleBulkImportView),
      );
      expect(warning, findsOneWidget);
      await tester.ensureVisible(warning);
      await tester.tap(warning);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/faculty/cohort');
      expect(router.state.uri.queryParameters['tab'], 'panelists');
      expect(router.state.uri.queryParameters['faculty'], '1');
      expect(find.text('Requested Faculty'), findsOneWidget);
      expect(find.text('Other Faculty'), findsNothing);
      expect(find.text('Back to schedule import'), findsOneWidget);
      final saved = await loadScheduleImportDraft(scope: 'pit', semesterId: 1);
      expect(saved!.parsed.rows.single.chair, 'Requested Faculty');
      expect(saved.parsed.rows.single.date, '2026-11-27');
      await tester.tap(find.text('Request eligibility'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit request'));
      await tester.pumpAndSettle();
      expect(client.nominations, 1);
      expect(find.text('Request pending'), findsOneWidget);
      // Simulate the administrator approving from a separate session.
      client.eligible = true;
      await tester.tap(find.text('Back to schedule import'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/faculty/defense-board/import');
      expect(find.byType(DefenseScheduleBulkImportView), findsOneWidget);
      expect(
        tester.state(find.byType(DefenseScheduleBulkImportView)),
        same(importState),
      );
      expect(
        find.byTooltip('View panelist eligibility and requests'),
        findsNothing,
      );
      expect(find.text('Team Aurora'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'PIT panelist requests work without a schedule at width $width',
      (tester) async {
        final client = _ActionClient(lead: true);
        final container = await pumpWorkspace(
          tester,
          '/faculty/cohort?tab=panelists',
          faculty: true,
          client: client,
          width: width,
          dark: width == 390,
          overrides: [
            pitLeadCohortProvider.overrideWith(_PitCohort.new),
            pitInstructorProvider.overrideWith(_PitInstructors.new),
            studentAcademicRecordsProvider.overrideWith(_Records.new),
            userManagementProvider.overrideWith(_Users.new),
          ],
        );
        expect(find.text('Approval needed'), findsOneWidget);
        expect(find.text('Eligible panelist'), findsOneWidget);
        expect(find.text('Assign Section Instructor'), findsNothing);
        await capturePreview(
          tester,
          find.byType(PitLeadCohortScreen),
          'pit-panelists-${width.toInt()}',
          viewport: true,
        );
        await tester.ensureVisible(find.text('Request eligibility'));
        await tester.tap(find.text('Request eligibility'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Submit request'));
        await tester.pumpAndSettle();
        expect(client.nominations, 1);
        expect(find.text('Request pending'), findsOneWidget);
        final requestsTab = find.text(
          width < 600 ? 'Requests' : 'My requests (1)',
        );
        await tester.ensureVisible(requestsTab);
        await tester.tap(requestsTab);
        await tester.pumpAndSettle();
        expect(
          container
              .read(appRouterProvider)
              .state
              .uri
              .queryParameters['section'],
          'requests',
        );
        expect(find.text('Awaiting approval'), findsOneWidget);
        expect(find.text('Declined'), findsNothing);
        expect(find.text('View request'), findsOneWidget);
        expect(
          client.calls.any((uri) => uri.path.startsWith('/api/defense/')),
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'legacy faculty request link opens its sheet in the existing workspace',
    (tester) async {
      final client = _ActionClient(lead: true);
      final container = await pumpWorkspace(
        tester,
        '/faculty/defense-board/requests/panelist/42',
        faculty: true,
        client: client,
        overrides: [
          pitLeadCohortProvider.overrideWith(_PitCohort.new),
          pitInstructorProvider.overrideWith(_PitInstructors.new),
          studentAcademicRecordsProvider.overrideWith(_Records.new),
          userManagementProvider.overrideWith(_Users.new),
        ],
      );
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/faculty/cohort',
      );
      expect(
        find.byKey(const ValueKey('panelist-request-sheet')),
        findsOneWidget,
      );
      expect(find.text('Requested Faculty'), findsOneWidget);
      await tester.tap(find.text('Close request'));
      await tester.pumpAndSettle();
      expect(find.byType(PitLeadCohortScreen), findsOneWidget);
      container
          .read(appRouterProvider)
          .go('/faculty/defense-board?panelistRequest=42');
      await tester.pumpAndSettle();
      expect(
        container.read(appRouterProvider).state.uri.path,
        '/faculty/cohort',
      );
      expect(
        find.byKey(const ValueKey('panelist-request-sheet')),
        findsOneWidget,
      );
      await tester.tap(find.text('Close request'));
      await tester.pumpAndSettle();
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .queryParameters
            .containsKey('request'),
        false,
      );
    },
  );

  testWidgets('deliverable deep link opens the specified team and inner tab', (
    tester,
  ) async {
    await pumpWorkspace(
      tester,
      '/admin/student-teams/1?tab=deliverables&stage=Concept%20Proposal',
    );
    final detail = tester.widget<TeamDetailPage>(find.byType(TeamDetailPage));
    expect(detail.initialDeliverableStage, 'Concept Proposal');
    final context = tester.element(find.byType(TabBar).first);
    expect(DefaultTabController.of(context).index, 2);
    expect(
      find.text(
        'No capstone deliverable record for this team (non-capstone or not loaded).',
      ),
      findsOneWidget,
    );
  });

  testWidgets('admin Teams restores detail, inner tab and list state lazily', (
    tester,
  ) async {
    final container = await pumpWorkspace(tester, '/admin/student-teams');
    final router = container.read(appRouterProvider);
    final teams = container.read(studentTeamsProvider.notifier) as _Teams;
    final grades = container.read(gradeCenterProvider.notifier) as _Grades;
    expect(teams.loads, 1);
    expect(grades.loads, 0); // Unvisited sections have no initial API calls.

    final listState = tester.state(find.byType(StudentTeamsScreen));
    await tester.tap(find.text('BSIT-4A'));
    await tester.pumpAndSettle();
    expect(find.text('View'), findsWidgets);
    final listScroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(StudentTeamsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    listScroll.position.jumpTo(120);
    await tester.pumpAndSettle();
    final listOffset = listScroll.position.pixels;
    expect(listOffset, greaterThan(0));
    await tester.tap(find.text('View').first);
    await tester.pumpAndSettle();
    final detailState = tester.state(find.byType(TeamDetailPage));
    await tester.tap(find.text('Weekly Reports'));
    await tester.pumpAndSettle();
    expect(
      find.text('No weekly progress reports submitted yet.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Academic Periods'));
    await tester.pumpAndSettle();
    expect(
      TickerMode.of(
        tester.element(find.byType(TeamDetailPage, skipOffstage: false)),
      ),
      isFalse,
    );
    // A retained hidden page must not overwrite another page's dirty guard.
    container.read(unsavedChangesProvider.notifier).setDirty(true);
    teams.emitUpdate();
    await tester.pumpAndSettle();
    expect(container.read(unsavedChangesProvider), isTrue);
    container.read(unsavedChangesProvider.notifier).setDirty(false);
    await tester.tap(find.text('Student Teams').first);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/admin/student-teams/1');
    expect(tester.state(find.byType(TeamDetailPage)), same(detailState));
    expect(
      find.text('No weekly progress reports submitted yet.'),
      findsOneWidget,
    );
    expect(
      teams.loads,
      2,
    ); // Revalidate quick returns while retaining the page.
    expect((container.read(teamDetailProvider(1).notifier) as _Team).loads, 1);

    router.pop();
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(StudentTeamsScreen)), same(listState));
    expect(find.text('View'), findsWidgets); // The expanded section survived.
    expect(listScroll.position.pixels, listOffset);
  });

  for (final faculty in [false, true]) {
    for (final collapsed in [false, true]) {
      testWidgets(
        '${faculty ? 'faculty' : 'admin'} ${collapsed ? 'collapsed' : 'expanded'} sidebar clears pressed highlights when switching sections',
        (tester) async {
          final prefix = faculty ? '/faculty' : '/admin';
          final container = await pumpWorkspace(
            tester,
            '$prefix/grade-center/grades/6?locked=1',
            faculty: faculty,
          );
          final router = container.read(appRouterProvider);
          if (collapsed) {
            await tester.tap(find.byTooltip('Collapse sidebar'));
            await tester.pumpAndSettle();
          }

          Finder navIcon(IconData icon) => find.byIcon(icon).first;

          Color? navBackground(IconData icon) {
            final item = find
                .ancestor(
                  of: navIcon(icon),
                  matching: find.byType(GestureDetector),
                )
                .first;
            final background = tester.widget<Container>(
              find.descendant(of: item, matching: find.byType(Container)).first,
            );
            return (background.decoration! as BoxDecoration).color;
          }

          void expectSelection(IconData selected, IconData unselected) {
            expect(navBackground(selected), const Color(0xFF7A110A));
            expect(navBackground(unselected), isNot(const Color(0xFF7A110A)));
          }

          const grades = Icons.grade_rounded;
          const board = Icons.view_agenda_rounded;
          // Re-clicking the current section used to leave its pressed state set.
          await tester.tap(navIcon(grades));
          await tester.pumpAndSettle();
          await tester.tap(navIcon(board));
          await tester.pumpAndSettle();
          expect(router.state.uri.path, '$prefix/defense-board');
          expectSelection(board, grades);

          await tester.tap(navIcon(board));
          await tester.pumpAndSettle();
          await tester.tap(navIcon(grades));
          await tester.pumpAndSettle();
          expect(
            router.state.uri.toString(),
            '$prefix/grade-center/grades/6?locked=1',
          );
          expectSelection(grades, board);

          // The highlight also follows navigation that bypasses a sidebar tap.
          router.go('$prefix/defense-board');
          await tester.pumpAndSettle();
          expectSelection(board, grades);
        },
      );
    }

    testWidgets(
      '${faculty ? 'faculty' : 'admin'} team evaluation links preserve section navigation and return state',
      (tester) async {
        final prefix = faculty ? '/faculty' : '/admin';
        final container = await pumpWorkspace(
          tester,
          '$prefix/student-teams/1',
          faculty: faculty,
        );
        final router = container.read(appRouterProvider);
        final teamState = tester.state(find.byType(TeamDetailPage));
        final team = container.read(teamDetailProvider(1).notifier) as _Team;
        expect(team.loads, 1);

        await tester.ensureVisible(find.text('View evaluation details'));
        await tester.tap(find.text('View evaluation details'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '$prefix/grade-center/grades/6');
        expect(router.state.uri.queryParameters, {
          'locked': '1',
          'fromTeam': '1',
        });
        final evaluationState = tester.state(
          find.byType(GradeCenterTeamDetailScreen),
        );
        expect(
          tester
              .widget<GradeCenterTeamDetailScreen>(
                find.byType(GradeCenterTeamDetailScreen),
              )
              .isLocked,
          isTrue,
        );
        expect(find.text('Back to Team AgriSense'), findsOneWidget);
        expect(find.text('Update Verdict'), findsNothing);
        await tester.tap(find.text('Individual Rubric Breakdown'));
        await tester.pumpAndSettle();
        expect(find.text('Master Student Grade Sheet'), findsNothing);

        await tester.tap(
          find.text(faculty ? 'Dashboard' : 'Academic Periods').first,
        );
        await tester.pumpAndSettle();
        expect(
          router.state.uri.path,
          faculty ? '/faculty/dashboard' : '/admin/academic-periods',
        );
        await tester.tap(find.text('Student Teams').first);
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '$prefix/student-teams/1');
        expect(tester.state(find.byType(TeamDetailPage)), same(teamState));
        expect(team.loads, 2); // Refresh the summary after viewing evaluations.

        await tester.tap(find.text('Evaluation & Grades').first);
        await tester.pumpAndSettle();
        expect(
          tester.state(find.byType(GradeCenterTeamDetailScreen)),
          same(evaluationState),
        );
        expect(find.text('Master Student Grade Sheet'), findsNothing);
        // Later corrections also refresh the retained team on its next visit.
        container.read(dataRefreshProvider.notifier).markChanged([
          DataArea.teams,
        ]);
        await tester.tap(find.text('Back to Team AgriSense'));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '$prefix/student-teams/1');
        expect(tester.state(find.byType(TeamDetailPage)), same(teamState));
        expect(team.loads, 3);
      },
    );

    testWidgets(
      '${faculty ? 'faculty' : 'admin'} direct evaluation links retain the team return destination',
      (tester) async {
        final prefix = faculty ? '/faculty' : '/admin';
        final container = await pumpWorkspace(
          tester,
          '$prefix/grade-center/grades/6?locked=1&fromTeam=1',
          faculty: faculty,
        );
        await tester.tap(find.text('Back to Team AgriSense'));
        await tester.pumpAndSettle();
        expect(
          container.read(appRouterProvider).state.uri.path,
          '$prefix/student-teams/1',
        );
        expect(find.byType(TeamDetailPage), findsOneWidget);
      },
    );

    testWidgets(
      '${faculty ? 'faculty' : 'admin'} Cancel preserves a section and Discard resets only its own history',
      (tester) async {
        final prefix = faculty ? '/faculty' : '/admin';
        final container = await pumpWorkspace(
          tester,
          '$prefix/grade-center/grades/6?locked=1',
          faculty: faculty,
        );
        final router = container.read(appRouterProvider);
        final gradeState = tester.state(
          find.byType(GradeCenterTeamDetailScreen),
        );
        await tester.tap(find.text('Individual Rubric Breakdown'));
        await tester.pumpAndSettle();
        router.go('$prefix/student-teams/1');
        await tester.pumpAndSettle();
        final teamState = tester.state(find.byType(TeamDetailPage));
        container.read(unsavedChangesProvider.notifier).setDirty(true);

        await tester.tap(find.text('Evaluation & Grades').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '$prefix/student-teams/1');
        expect(tester.state(find.byType(TeamDetailPage)), same(teamState));

        await tester.tap(find.text('Evaluation & Grades').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard').last);
        await tester.pumpAndSettle();
        expect(
          tester.state(find.byType(GradeCenterTeamDetailScreen)),
          same(gradeState),
        );
        expect(find.text('Master Student Grade Sheet'), findsNothing);
        expect(container.read(unsavedChangesProvider), isFalse);

        await tester.tap(find.text('Student Teams').first);
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '$prefix/student-teams');
        expect(find.byType(TeamDetailPage), findsNothing);
        expect(find.byType(StudentTeamsScreen), findsOneWidget);
      },
    );
    testWidgets(
      '${faculty ? 'faculty' : 'admin'} board import uses one retained workspace',
      (tester) async {
        final prefix = faculty ? '/faculty' : '/admin';
        final container = await pumpWorkspace(
          tester,
          '$prefix/defense-board/import',
          faculty: faculty,
          width: 1920,
        );
        final router = container.read(appRouterProvider);
        final board = container.read(defenseBoardProvider.notifier) as _Board;
        expect(
          find.byType(DefenseBoardScreen, skipOffstage: false),
          findsOneWidget,
        );
        expect(board.loads, 1);
        final boardState = tester.state(find.byType(DefenseBoardScreen));
        final importState = tester.state(
          find.byType(DefenseScheduleBulkImportView),
        );

        await tester.tap(
          find.text(faculty ? 'Dashboard' : 'Academic Periods').first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Defense Operations').first);
        await tester.pumpAndSettle();
        expect(router.state.uri.path, '$prefix/defense-board/import');
        expect(
          tester.state(find.byType(DefenseScheduleBulkImportView)),
          same(importState),
        );
        expect(board.loads, 2);

        router.go('$prefix/defense-board');
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(DefenseBoardScreen)), same(boardState));
        expect(find.byType(DefenseScheduleBulkImportView), findsNothing);
        expect(board.loads, 2);
        container.read(dataRefreshProvider.notifier).markChanged(const [
          DataArea.defenseBoard,
        ]);
        await tester.pumpAndSettle();
        expect(
          board.loads,
          3,
        ); // Visible retained branches consume changes now.
        expect(tester.state(find.byType(DefenseBoardScreen)), same(boardState));
      },
    );
    testWidgets(
      '${faculty ? 'faculty' : 'admin'} grades restores detail, query and inner view',
      (tester) async {
        final prefix = faculty ? '/faculty' : '/admin';
        final container = await pumpWorkspace(
          tester,
          '$prefix/grade-center/grades/6?locked=1',
          faculty: faculty,
        );
        final router = container.read(appRouterProvider);
        final detailState = tester.state(
          find.byType(GradeCenterTeamDetailScreen),
        );
        final widget = tester.widget<GradeCenterTeamDetailScreen>(
          find.byType(GradeCenterTeamDetailScreen),
        );
        expect(widget.isLocked, isTrue);
        await tester.tap(find.text('Individual Rubric Breakdown'));
        await tester.pumpAndSettle();

        if (faculty) {
          await tester.tap(find.text('Dashboard').first);
        } else {
          await tester.tap(find.text('Academic Periods'));
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('Evaluation & Grades').first);
        await tester.pumpAndSettle();
        expect(
          router.state.uri.toString(),
          '$prefix/grade-center/grades/6?locked=1',
        );
        expect(
          tester.state(find.byType(GradeCenterTeamDetailScreen)),
          same(detailState),
        );
        final grades = container.read(gradeCenterProvider.notifier) as _Grades;
        expect(grades.detailLoads, 1);
        expect(
          grades.loads,
          2,
        ); // Refresh the retained list without remounting detail.
        // Detail uses its own segmented control, so verify that the master table
        // content is absent while the individual rubric view is still displayed.
        expect(find.text('Master Student Grade Sheet'), findsNothing);
        expect(
          find.text('Select a student to view rubric evaluation'),
          findsOneWidget,
        );
      },
    );
  }
}
