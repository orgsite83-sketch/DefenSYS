import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/screens/app/student_dashboard.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/academic/student_team_tasks_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/app/data_refresh_provider.dart';
import 'package:defensys/services/network/connectivity_provider.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/widgets/repository/team_concept_title_editor.dart';
import 'package:defensys/screens/app/student/section_integration_tab.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/widgets/repository/section_concept_workspace.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _Leader extends AuthNotifier {
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: const {'id': 10, 'role': 'student', 'username': 'leader'},
  );
}

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

Map<String, dynamic> _workflow({bool complete = false}) => {
  'enabled': true,
  'status': 'concepts_needed',
  'can_edit': true,
  'can_edit_titles': true,
  'module_review_token': 'latest-token',
  'concepts': [
    {'key': 'c1', 'title': 'Imported project'},
    {'key': 'c2', 'title': complete ? 'Additional proposal' : ''},
  ],
};

class _Dashboard extends DashboardNotifier {
  _Dashboard() : super('student');
  @override
  DashboardState build() => DashboardState(
    data: {
      'student': {'id': 10, 'name': 'Ana', 'is_leader': true},
      'team': {
        'id': 5,
        'name': 'Team AgriPulse',
        'isCapstone': true,
        'projectTitle': 'Imported project',
        'currentStage': 'Concept Proposal',
      },
      'stage_options': ['Concept Proposal'],
      'stages': [
        {'stage_label': 'Concept Proposal', 'concept_workflow': _workflow()},
      ],
    },
  );
  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

class _Deliverables extends CapstoneDeliverablesNotifier {
  @override
  CapstoneDeliverablesState build() => const CapstoneDeliverablesState(
    stageOptions: ['Concept Proposal'],
    selectedStage: 'Concept Proposal',
  );
  @override
  Future<void> fetchDeliverables({
    String? workspace,
    String? search,
    String? selectedStage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
}

class _CompletedDashboard extends _Dashboard {
  @override
  DashboardState build() => DashboardState(
    data: {
      ...super.build().data!,
      'stages': [
        {
          'stage_label': 'Concept Proposal',
          'concept_workflow': _workflow(complete: true),
        },
      ],
    },
  );
}

class _Inbox extends NotificationsNotifier {
  _Inbox(super.workspace);
  @override
  NotificationsState build() => const NotificationsState();
  @override
  Future<void> fetchNotifications({
    bool? unreadOnly,
    bool loadMore = false,
  }) async {}
}

class _SectionTeams extends StudentTeamsNotifier {
  @override
  StudentTeamsState build() => const StudentTeamsState();
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
  }) async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(resetApiHttpClientForTesting);

  testWidgets(
    'PM title action opens Integration details and its dot clears on refresh',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    await loadPreviewFonts(force: true);
      var needsAction = true;
      setApiHttpClientForTesting(
        MockClient(
          (request) async => http.Response(
            jsonEncode({
              'id': 17,
              'section': 'BSIT-3B',
              'stage_label': 'Concept Proposal',
              'round': 1,
              'systems': <Map<String, dynamic>>[],
              'teams': <Map<String, dynamic>>[],
              'shared_contexts': <Map<String, dynamic>>[],
            }),
            200,
          ),
        ),
      );
      await pumpDefensysWidget(
        tester,
        const StudentDashboard(),
        overrides: [
          connectivityProvider.overrideWith(_Online.new),
          authProvider.overrideWith(_Leader.new),
          dashboardProvider('student').overrideWith(_CompletedDashboard.new),
          capstoneDeliverablesProvider.overrideWith(_Deliverables.new),
          studentTeamsProvider.overrideWith(_SectionTeams.new),
          notificationsProvider.overrideWith2(_Inbox.new),
          studentTeamTasksProvider.overrideWith((ref) async {
            ref.watch(dataRefreshProvider);
            return {
              'section_tasks': [
                {
                  'project_id': 17,
                  'stage_label': 'Concept Proposal',
                  'role': 'project_manager',
                  'needs_title': needsAction,
                  'needs_files': false,
                  'requires_action': needsAction,
                  'status': needsAction
                      ? 'papers_missing'
                      : 'awaiting_faculty_review',
                },
              ],
            };
          }),
        ],
      );
      expect(find.text('Your Section & Team Tasks'), findsNothing);
      expect(
        (tester
                    .widget<NavigationDestination>(
                      find.byType(NavigationDestination).first,
                    )
                    .icon
                as Badge)
            .isLabelVisible,
        isFalse,
      );
      final destination = tester.widget<NavigationDestination>(
        find.byType(NavigationDestination).at(3),
      );
      expect((destination.icon as Badge).isLabelVisible, isTrue);
      expect((destination.selectedIcon as Badge).isLabelVisible, isTrue);
      await capturePreview(
        tester,
        find.byType(StudentDashboard),
        'integration-pm-task-dot',
        viewport: true,
      );
      await tester.tap(find.text('Integration'));
      await tester.pumpAndSettle();
      final integration = tester.widget<SectionIntegrationTab>(
        find.byType(SectionIntegrationTab),
      );
      expect(integration.projectId, 17);
      expect(integration.openDeliverables, isFalse);
      needsAction = false;
      ProviderScope.containerOf(
        tester.element(find.byType(StudentDashboard)),
        listen: false,
      ).read(dataRefreshProvider.notifier).markChanged(const [DataArea.teams]);
      await tester.pumpAndSettle();
      final cleared = tester.widget<NavigationDestination>(
        find.byType(NavigationDestination).at(3),
      );
      expect((cleared.icon as Badge).isLabelVisible, isFalse);
      expect((cleared.selectedIcon as Badge).isLabelVisible, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'section task selects Integration with its exact project and stage',
    (tester) async {
      final reads = <String>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          reads.add(request.url.path);
          return http.Response(
            jsonEncode({
              'id': 17,
              'section': 'BSIT-3B',
              'stage_label': 'Concept Proposal',
              'round': 1,
              'systems': <Map<String, dynamic>>[],
              'teams': <Map<String, dynamic>>[],
              'shared_contexts': <Map<String, dynamic>>[],
            }),
            200,
          );
        }),
      );
      await pumpDefensysWidget(
        tester,
        const StudentDashboard(),
        overrides: [
          authProvider.overrideWith(_Leader.new),
          dashboardProvider('student').overrideWith(_CompletedDashboard.new),
          capstoneDeliverablesProvider.overrideWith(_Deliverables.new),
          studentTeamsProvider.overrideWith(_SectionTeams.new),
          studentTeamTasksProvider.overrideWith(
            (ref) async => {
              'section_tasks': [
                {
                  'project_id': 17,
                  'role': 'project_manager',
                  'requires_action': true,
                  'needs_files': true,
                  'needs_title': false,
                  'stage_label': 'Concept Proposal',
                  'section': 'BSIT-3B',
                  'title': 'Submit shared post-defense documents',
                  'status': 'final_paper_pending',
                  'status_label': 'Final paper pending',
                },
              ],
            },
          ),
          notificationsProvider.overrideWith2(_Inbox.new),
        ],
      );
      expect(find.text('Your Section & Team Tasks'), findsNothing);
      expect(find.text('Submit shared post-defense documents'), findsNothing);
      expect(
        (tester
                    .widget<NavigationDestination>(
                      find.byType(NavigationDestination).first,
                    )
                    .icon
                as Badge)
            .isLabelVisible,
        isFalse,
      );
      expect(
        tester
            .widget<Badge>(find.byKey(const ValueKey('integration-task-badge')))
            .isLabelVisible,
        isTrue,
      );
      await tester.tap(find.text('Integration'));
      await tester.pumpAndSettle();
      final integration = tester.widget<SectionIntegrationTab>(
        find.byType(SectionIntegrationTab),
      );
      expect(integration.projectId, 17);
      expect(integration.initialStage, 'Concept Proposal');
      expect(integration.openDeliverables, isTrue);
      expect(
        find.text('No shared deliverables are configured for this stage.'),
        findsOneWidget,
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
      expect(reads, ['/api/repository/section-concepts/17/']);
      expect(find.text('Section BSIT-3B'), findsOneWidget);
      expect(find.byType(SectionConceptWorkspace), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Team tab edits titles in place, hides duplicate prompt, and clears its red dot',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      setApiHttpClientForTesting(
        MockClient(
          (request) async => http.Response(
            jsonEncode({
              'concept_workflow': _workflow(complete: request.method == 'POST'),
            }),
            200,
          ),
        ),
      );
      final setup = {
        'teams': [
          {
            'id': 5,
            'name': 'Team AgriPulse',
            'needs_name': false,
            'concept_tasks': [
              {'required_count': 2, 'stage_label': 'Concept Proposal'},
            ],
          },
        ],
      };
      await pumpDefensysWidget(
        tester,
        const StudentDashboard(),
        overrides: [
          authProvider.overrideWith(_Leader.new),
          dashboardProvider('student').overrideWith(_Dashboard.new),
          capstoneDeliverablesProvider.overrideWith(_Deliverables.new),
          studentTeamTasksProvider.overrideWith((ref) async => setup),
          notificationsProvider.overrideWith2(_Inbox.new),
        ],
      );
      expect(find.text('Action Required: Complete Team Setup'), findsNothing);
      expect(find.textContaining('Submit 2 concepts'), findsNothing);
      final nav = tester.widget<NavigationDestination>(
        find.byType(NavigationDestination).first,
      );
      expect((nav.icon as Badge).isLabelVisible, isTrue);
      expect((nav.selectedIcon as Badge).isLabelVisible, isTrue);
      await tester.ensureVisible(
        find.byKey(const ValueKey('edit-team-concepts')),
      );
      await tester.tap(find.byKey(const ValueKey('edit-team-concepts')));
      await tester.pumpAndSettle();
      expect(find.byType(TeamConceptTitleEditor), findsOneWidget);
      final input = find.descendant(
        of: find.byKey(const ValueKey('concept-title-c2')),
        matching: find.byType(EditableText),
      );
      await tester.enterText(input, 'Additional proposal');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save concept titles'));
      await tester.pumpAndSettle();
      expect(find.byType(TeamConceptTitleEditor), findsNothing);
      expect(find.text('2 of 2 concept titles provided'), findsOneWidget);
      final refreshed = tester.widget<NavigationDestination>(
        find.byType(NavigationDestination).first,
      );
      expect((refreshed.icon as Badge).isLabelVisible, isFalse);
      expect((refreshed.selectedIcon as Badge).isLabelVisible, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
