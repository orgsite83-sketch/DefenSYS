import 'dart:convert';
import 'package:flutter/material.dart';
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
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/widgets/repository/team_concept_title_editor.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';

class _Leader extends AuthNotifier {
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: const {'id': 10, 'role': 'student', 'username': 'leader'},
  );
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(resetApiHttpClientForTesting);

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
