import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/src/framework.dart' show Override;
import 'package:user/screens/web/admin/student_teams_screen.dart';
import 'package:user/services/dashboard_provider.dart';
import 'package:user/services/student_teams_provider.dart';

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
  Future<void> fetchDashboardData() async {}
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
  Future<void> fetchDashboardData() async {}
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
    expect(find.text('Details'), findsWidgets);
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
        'Manage PIT teams and PIT events for your assigned year level.',
      ),
      findsOneWidget,
    );
    expect(find.text('Capstone Teams'), findsNothing);
    expect(find.text('Adviser Review'), findsNothing);
    expect(find.text('PIT Event'), findsOneWidget);
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
}
