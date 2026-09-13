import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:defensys/screens/web/admin/student_teams_screen.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/student_teams_provider.dart';

import '../helpers/pump_app.dart';

class _FakeStudentTeamsNotifier extends StudentTeamsNotifier {
  _FakeStudentTeamsNotifier(this.initial);

  final StudentTeamsState initial;

  @override
  StudentTeamsState build() => initial;

  @override
  Future<void> fetchTeams({
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
  }) async {}
}

class _FakeAdminDashboardNotifier extends DashboardNotifier {
  _FakeAdminDashboardNotifier() : super('admin');

  @override
  DashboardState build() {
    return DashboardState(
      data: {'active_semester': '2026-2027'},
    );
  }

  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

class _FakeFacultyPitLeadDashboardNotifier extends DashboardNotifier {
  _FakeFacultyPitLeadDashboardNotifier() : super('faculty');

  @override
  DashboardState build() {
    return DashboardState(
      data: {
        'pit_lead_year': '3rd Year',
        'roles': {
          'pit_lead': true,
          'pit_lead_year': '3rd Year',
        },
      },
    );
  }

  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

void main() {
  Future<void> pumpTeamsScreen(
    WidgetTester tester, {
    required TeamListMode mode,
    required List<Override> overrides,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await pumpDefensysWidget(
      tester,
      StudentTeamsScreen(mode: mode),
      overrides: overrides,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('capstone admin mode shows Details column without delete icon', (
    tester,
  ) async {
    await pumpTeamsScreen(
      tester,
      mode: TeamListMode.capstoneAdmin,
      overrides: [
        studentTeamsProvider.overrideWith(
          () => _FakeStudentTeamsNotifier(
            const StudentTeamsState(
              teams: [
                {
                  'id': 1,
                  'name': 'Team CodeLearners',
                  'project_title': 'Smart Campus Navigator',
                  'year_level': '3rd Year',
                  'status': 'Pending',
                  'leader_name': 'Carlos Reyes',
                  'adviser_name': 'Ricardo Fontanilla',
                  'member_count': 4,
                },
              ],
              level: 'Capstone',
            ),
          ),
        ),
        dashboardProvider('admin').overrideWith(_FakeAdminDashboardNotifier.new),
        dashboardProvider('faculty').overrideWith(
          _FakeFacultyPitLeadDashboardNotifier.new,
        ),
      ],
    );

    expect(find.text('Student Teams'), findsOneWidget);
    expect(
      find.text(
        'Manage capstone project teams, assign advisers, and review defense context.',
      ),
      findsOneWidget,
    );
    expect(find.text('Capstone Teams'), findsOneWidget);
    await tester.tap(find.text('Unassigned Section'));
    await tester.pumpAndSettle();
    expect(find.text('DETAILS'), findsWidgets);
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    expect(find.byIcon(Icons.delete_rounded), findsNothing);
  });

  testWidgets('capstone admin shows closed dialog when window is closed', (
    tester,
  ) async {
    await pumpTeamsScreen(
      tester,
      mode: TeamListMode.capstoneAdmin,
      overrides: [
        studentTeamsProvider.overrideWith(
          () => _FakeStudentTeamsNotifier(
            const StudentTeamsState(
              level: 'Capstone',
              canCreateCapstoneTeams: false,
              capstoneModeMessage:
                  'Capstone team creation is not open for this term.',
            ),
          ),
        ),
        dashboardProvider('admin').overrideWith(_FakeAdminDashboardNotifier.new),
      ],
    );

    await tester.tap(find.text('Create New Team'));
    await tester.pumpAndSettle();

    expect(find.text('Capstone team creation closed'), findsOneWidget);
  });

  testWidgets('PIT lead mode uses PIT copy and hides capstone filter', (
    tester,
  ) async {
    await pumpTeamsScreen(
      tester,
      mode: TeamListMode.pitLead,
      overrides: [
        studentTeamsProvider.overrideWith(
          () => _FakeStudentTeamsNotifier(
            const StudentTeamsState(
              teams: [
                {
                  'id': 2,
                  'name': 'Team CodeLearners',
                  'project_title': 'Smart Campus Navigator',
                  'year_level': '3rd Year',
                  'level': '3rd Year PIT',
                  'status': 'Pending',
                  'leader_name': 'Carlos Reyes',
                  'member_count': 4,
                },
              ],
            ),
          ),
        ),
        dashboardProvider('faculty').overrideWith(
          _FakeFacultyPitLeadDashboardNotifier.new,
        ),
        dashboardProvider('admin').overrideWith(_FakeAdminDashboardNotifier.new),
      ],
    );

    expect(
      find.text(
        'Manage PIT teams and PIT events setup for your assigned year level.',
      ),
      findsOneWidget,
    );
    expect(find.text('Capstone Teams'), findsNothing);
    expect(find.text('Adviser Review'), findsNothing);
    await tester.tap(find.text('Unassigned Section'));
    await tester.pumpAndSettle();
    expect(find.text('PIT EVENT'), findsOneWidget);
  });

  testWidgets(
    'PIT lead mode opens create flow even when capstone window is closed',
    (tester) async {
      await pumpTeamsScreen(
        tester,
        mode: TeamListMode.pitLead,
        overrides: [
          studentTeamsProvider.overrideWith(
            () => _FakeStudentTeamsNotifier(
              const StudentTeamsState(
                canCreateCapstoneTeams: false,
                capstoneModeMessage:
                    'Capstone team creation is not open for this term.',
              ),
            ),
          ),
          dashboardProvider('faculty').overrideWith(
            _FakeFacultyPitLeadDashboardNotifier.new,
          ),
          dashboardProvider('admin').overrideWith(
            _FakeAdminDashboardNotifier.new,
          ),
        ],
      );

      await tester.tap(find.text('Create New Team'));
      await tester.pumpAndSettle();

      expect(find.text('Capstone team creation closed'), findsNothing);
      expect(find.text('Create New Team'), findsWidgets);
    },
  );

  testWidgets(
    'Admin in PIT mode displays Year Level and PIT Event dropdown filters and event badge',
    (tester) async {
      await pumpTeamsScreen(
        tester,
        mode: TeamListMode.capstoneAdmin,
        overrides: [
          studentTeamsProvider.overrideWith(
            () => _FakeStudentTeamsNotifier(
              const StudentTeamsState(
                level: 'PIT',
                yearLevel: '1st Year',
                eventName: '1st Year Concept Pitch',
                pitEvents: [
                  {
                    'event_name': '1st Year Concept Pitch',
                    'year_level': '1st Year',
                  },
                  {
                    'event_name': '2nd Year Innovation Expo',
                    'year_level': '2nd Year',
                  },
                ],
                teams: [
                  {
                    'id': 101,
                    'name': 'Team Alpha',
                    'project_title': 'Alpha Project',
                    'level': '1st Year PIT',
                    'year_level': '1st Year',
                    'section': 'CS-1A',
                    'leader_id': 1,
                    'leader_name': 'Juan Cruz',
                    'members': [{'id': 1, 'name': 'Juan Cruz', 'is_enrolled': true}],
                    'member_count': 1,
                    'pit_event_name': '1st Year Concept Pitch',
                    'current_defense_stage': '1st Year Concept Pitch',
                    'status': 'Pending',
                  },
                ],
              ),
            ),
          ),
          dashboardProvider('faculty').overrideWith(
            _FakeFacultyPitLeadDashboardNotifier.new,
          ),
          dashboardProvider('admin').overrideWith(
            _FakeAdminDashboardNotifier.new,
          ),
        ],
      );

      // Verify filters are rendered
      expect(find.text('1st Year'), findsWidgets);
      expect(find.text('1st Year Concept Pitch'), findsWidgets);

      // Expand section to view table
      await tester.tap(find.text('CS-1A'));
      await tester.pumpAndSettle();

      expect(find.text('PIT EVENT'), findsOneWidget);
      expect(find.text('Team Alpha'), findsOneWidget);
      // The event name should be displayed
      expect(find.text('1st Year Concept Pitch'), findsWidgets);
    },
  );

  testWidgets(
    'admin student teams scopes to Capstone initially even if state contains PIT teams',
    (tester) async {
      await pumpTeamsScreen(
        tester,
        mode: TeamListMode.capstoneAdmin,
        overrides: [
          studentTeamsProvider.overrideWith(
            () => _FakeStudentTeamsNotifier(
              const StudentTeamsState(
                teams: [
                  {
                    'id': 1,
                    'name': 'PIT 1 Team',
                    'section': 'BSIT-1A',
                    'level': '1st Year PIT',
                    'year_level': '1st Year',
                    'status': 'Pending',
                  },
                  {
                    'id': 2,
                    'name': 'PIT 2 Team',
                    'section': 'BSIT-2A',
                    'level': '2nd Year PIT',
                    'year_level': '2nd Year',
                    'status': 'Pending',
                  },
                  {
                    'id': 3,
                    'name': 'Capstone 4 Team',
                    'section': 'BSIT-4A',
                    'level': '4th Year Capstone',
                    'year_level': '4th Year',
                    'status': 'Pending',
                  },
                ],
                counts: {'all': 3, 'pending': 3, 'approved': 0, 'failed': 0},
              ),
            ),
          ),
          dashboardProvider('faculty').overrideWith(
            _FakeFacultyPitLeadDashboardNotifier.new,
          ),
          dashboardProvider('admin').overrideWith(
            _FakeAdminDashboardNotifier.new,
          ),
        ],
      );

      // Verify that Capstone Teams is selected
      expect(find.text('Capstone Teams'), findsOneWidget);

      // Verify only Capstone section (BSIT-4A) is displayed
      expect(find.text('BSIT-4A'), findsOneWidget);
      expect(find.text('BSIT-1A'), findsNothing);
      expect(find.text('BSIT-2A'), findsNothing);

      // Verify footer says Showing 1 of 1 teams
      expect(find.text('Showing 1 of 1 teams'), findsOneWidget);
    },
  );
}
