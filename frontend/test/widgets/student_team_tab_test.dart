import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/app/student/team_tab.dart';
import 'package:defensys/screens/app/student/student_events_tab.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/defense/team_defense_provider.dart';
import 'package:defensys/screens/app/student/peer_eval_tab.dart';

import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';
import 'package:defensys/theme/app_theme.dart';

class _TestDeliverablesNotifier extends CapstoneDeliverablesNotifier {
  @override
  CapstoneDeliverablesState build() {
    return const CapstoneDeliverablesState(
      stageOptions: ['Project Proposal', 'Colloquium', 'Final Defense'],
      selectedStage: 'Colloquium',
    );
  }

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
  }) async {
    state = state.copyWith(selectedStage: selectedStage ?? state.selectedStage);
  }
}

class _TestDefenses extends TeamDefenseNotifier {
  @override
  TeamDefenseState build() => const TeamDefenseState(
    schedules: [
      {
        'id': 1,
        'team_id': 1,
        'scope': 'capstone',
        'stage_label': 'Colloquium',
        'status': 'scheduled',
        'scheduled_date': '2099-10-24',
        'room': 'Room 402',
        'panelists': [
          {'name': 'Prof. John von Neumann'},
          {'name': 'Dr. Ada Lovelace'},
        ],
      },
      {
        'id': 2,
        'team_id': 1,
        'scope': 'capstone',
        'stage_label': 'Project Proposal',
        'status': 'done',
        'display_status': 'completed',
        'scheduled_date': '2099-09-24',
        'room': 'Room 101',
        'assessment': {'verdict': 'approved', 'is_completed': true},
      },
    ],
  );
  @override
  Future<void> fetch({String? workspace}) async {}
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('shared imports use module labels before the PM opens a shared round ${dark ? 'dark' : 'light'}', (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadPreviewFonts(force: true);
      int? selectedTab;
      await pumpDefensysWidget(tester, TeamTab(studentData: {
        'student': {'id': 10, 'is_leader': true},
        'team': {'id': 1, 'isCapstone': true, 'name': 'Team AgriPulse',
          'projectTitle': 'Imported soil sensor module', 'currentStage': 'Colloquium'},
        'stage_options': ['Colloquium'],
        'stages': [{'stage_label': 'Colloquium', 'concept_workflow': {
          'enabled': true, 'status': 'concepts_needed', 'shared_import_pending': true,
          'concepts': [for (var i = 1; i <= 3; i++) {
            'key': 'c$i',
            'title': i == 1 ? 'Autonomous Soil Sensor & Dynamic Drip Irrigation Module' : '',
            'system_title': i == 1 ? 'Smart Agro-Industrial IoT & Sustainable Supply Platform' : '',
          }],
        }}],
      }, onSelectTab: (tab, {subTabIndex}) { selectedTab = tab; }), theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
        overrides: [capstoneDeliverablesProvider.overrideWith(_TestDeliverablesNotifier.new)]);
      expect(find.text('Proposed Modules'), findsOneWidget);
      expect(find.text('Modules needed'), findsOneWidget);
      expect(find.text('System A'), findsOneWidget);
      expect(find.text('System C'), findsOneWidget);
      expect(find.text('Smart Agro-Industrial IoT & Sustainable Supply Platform'), findsOneWidget);
      expect(find.text('System name not yet provided'), findsNWidgets(2));
      expect(find.text('Module title not yet proposed'), findsNWidgets(2));
      expect(find.text('Edit module titles'), findsOneWidget);
      expect(find.text('1 of 3 module titles provided'), findsOneWidget);
      expect(find.text('Proposed Concepts'), findsNothing);
      expect(find.text('View deliverables'), findsNothing);
      await tester.ensureVisible(find.text('Integration →'));
      await tester.tap(find.text('Integration →'));
      expect(selectedTab, 3);
      final editButton = tester.widget<FilledButton>(find.byKey(const ValueKey('edit-team-concepts')));
      expect((editButton.style!.shape!.resolve({}) as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(8));
      await capturePreview(tester, find.byType(TeamTab),
        'shared-module-team-${dark ? 'dark' : 'light'}', viewport: true);
      expect(tester.takeException(), isNull);
    });
  }

  for (final dark in [false, true]) {
    testWidgets('imported title shows actual configured progress on phone ${dark ? 'dark' : 'light'}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await loadPreviewFonts();
      int? selectedTab;
      int? selectedSubTab;
      await pumpDefensysWidget(tester, RepaintBoundary(
        key: const ValueKey('configured-concepts-phone'),
        child: TeamTab(studentData: {
          'student': {'id': 10, 'is_leader': true},
          'team': {'id': 1, 'isCapstone': true, 'name': 'Team AgriPulse', 'projectTitle': 'Imported soil sensor concept',
            'currentStage': 'Colloquium', 'section': 'BSIT-3A', 'adviserName': 'Eduardo Padilla'},
          'stage_options': ['Colloquium'],
          'stages': [{'stage_label': 'Colloquium', 'concept_workflow': {
            'enabled': true, 'status': 'concepts_needed', 'required_count': 4,
            'concepts': [for (var i = 1; i <= 4; i++) {'key': 'c$i', 'title': i == 1 ? 'Imported soil sensor concept' : ''}],
          }}],
        }, onSelectTab: (tab, {subTabIndex}) { selectedTab = tab; selectedSubTab = subTabIndex; }),
      ), theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
      overrides: [capstoneDeliverablesProvider.overrideWith(_TestDeliverablesNotifier.new)]);
      await tester.pumpAndSettle();
      expect(find.text('1 of 4 concept titles provided'), findsOneWidget);
      expect(find.text('Concept 4'), findsOneWidget);
      expect(find.text('3 Concept Proposals Submitted'), findsNothing);
      expect(find.text('Edit concept titles'), findsOneWidget);
      await tester.ensureVisible(find.text('View deliverables'));
      await tester.tap(find.text('View deliverables'));
      expect(selectedTab, 1);
      expect(selectedSubTab, 1);
      expect(find.text('Integration →'), findsNothing);
      await capturePreview(tester, find.byKey(const ValueKey('configured-concepts-phone')), 'configured-concepts-phone-${dark ? 'dark' : 'light'}');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('PIT event resolves its own membership without changing the current team', (tester) async {
    final data = <String, dynamic>{
      'student': {'id': 10},
      'team': {'id': 1, 'name': 'Current team', 'currentStage': 'Current event'},
      'current_stage': 'Current event',
      'stage_options': ['Earlier event', 'Current event'],
      'members': [{'id': 11, 'name': 'Current teammate'}],
      'stages': [
        {
          'stage_label': 'Earlier event',
          'team_id': 2,
          'team': {'id': 2, 'name': 'Earlier team', 'members': [
            {'id': 10, 'name': 'Student'}, {'id': 12, 'name': 'Earlier teammate'},
          ]},
          'peer_eval_allowed': false,
        },
        {'stage_label': 'Current event', 'team_id': 1},
      ],
    };
    await pumpDefensysWidget(tester, StudentEventsTab(
      isCapstone: false, studentData: data, initialStage: 'Earlier event', isActive: false,
    ), overrides: [
      capstoneDeliverablesProvider.overrideWith(_TestDeliverablesNotifier.new),
    ]);
    await tester.ensureVisible(find.text('Peer Eval').last);
    await tester.tap(find.text('Peer Eval').last);
    await tester.pumpAndSettle();
    final peer = tester.widget<PeerEvalTab>(find.byType(PeerEvalTab));
    expect(peer.teamId, '2');
    expect(peer.members.any((m) => m['id'] == 12), isTrue);
    expect(data['team']['id'], 1);
    expect(find.byKey(const ValueKey('student-team-1')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'TeamTab displays project details, roster, and defense shortcuts',
    (tester) async {
      final mockStudentData = {
        'student': {
          'id': 10,
          'name': 'Maria Santos',
          'email': 'maria@example.com',
          'is_project_manager': false,
        },
        'team': {
          'id': 1,
          'name': 'Team Innovators',
          'projectTitle': 'AI Defense Evaluation System',
          'systemName': 'DefenSYS Mobile',
          'level': '3rd Year Capstone',
          'status': 'Approved',
          'isCapstone': true,
          'ready_for_stage': 'Colloquium',
          'current_stage': 'Colloquium',
          'adviserName': 'Dr. Alan Turing',
          'semester': '2nd Semester',
          'schoolYear': '2026-2027',
        },
        'schedule': {
          'date': '2026-10-24',
          'startTime': '10:00 AM',
          'room': 'Room 402',
          'stage': 'Colloquium',
        },
        'members': [
          {
            'id': 10,
            'name': 'Maria Santos',
            'username': 'student_10',
            'isLeader': true,
          },
          {
            'id': 11,
            'name': 'Carlos Reyes',
            'username': 'student_11',
            'isLeader': false,
          },
        ],
        'grades': {
          'status': 'published',
          'stage': 'Project Proposal',
          'result': 'PASSED',
          'final_grade': 94.5,
          'is_published': true,
          'has_panel_evaluated': true,
          'has_adviser_graded': true,
          'has_peer_completed': true,
        },
        'deliverables': [
          {'name': 'Manuscript Draft', 'status': 'Approved'},
          {'name': 'Slide Deck', 'status': 'Submitted'},
        ],
        'myPeerEvalComplete': true,
        'peerEvalComplete': true,
        'peerEvalEnabled': true,
        'stage_options': ['Project Proposal', 'Colloquium', 'Final Defense'],
      };

      mockStudentData['team_options'] = [
        {'id': 1, 'name': 'Current team'},
        {'id': 2, 'name': 'Historical team'},
      ];
      int? selectedTab;

      await pumpDefensysWidget(
        tester,
        SizedBox(
          width: 400,
          height: 900,
          child: TeamTab(
            studentData: mockStudentData,
            onSelectTab: (index, {subTabIndex}) => selectedTab = index,
          ),
        ),
      );

      // The team overview keeps project details and navigation together.
      expect(find.text('Team Innovators'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(find.text('Your team'), findsNothing);
      expect(find.text('Shared system concepts'), findsNothing);
      expect(find.text('AI Defense Evaluation System'), findsOneWidget);
      expect(find.text('Colloquium'), findsWidgets);
      expect(find.text('Team Members (2)'), findsOneWidget);
      expect(find.text('Current Defense Stage'), findsOneWidget);
      expect(find.text('View Details'), findsOneWidget);
      expect(find.textContaining('Score: 94.5'), findsNothing);
      await tester.ensureVisible(find.text('View Details'));
      await tester.tap(find.text('View Details'));
      expect(selectedTab, equals(1));

      selectedTab = null;
      await tester.ensureVisible(find.text('Peer Eval'));
      await tester.tap(find.text('Peer Eval'));
      expect(selectedTab, equals(1));

      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'TeamTab displays single configured stage dynamically without hardcoded defaults',
    (tester) async {
      final mockSingleStageData = {
        'student': {
          'id': 10,
          'name': 'Marcus Villar',
          'email': 'marcus@example.com',
        },
        'team': {
          'id': 1,
          'name': 'Team SkyLedger',
          'projectTitle': 'Alumni Career Tracker',
          'systemName': 'SkyLedger',
          'level': '4th Year Capstone',
          'status': 'Approved',
          'isCapstone': true,
          'ready_for_stage': 'Concept Proposal',
          'current_stage': 'Concept Proposal',
          'adviserName': 'Analiza Corpuz',
          'semester': '1st Semester',
          'schoolYear': '2024-2025',
        },
        'members': [
          {
            'id': 10,
            'name': 'Marcus Villar',
            'username': 'student_10',
            'isLeader': true,
          },
        ],
        'stage_options': ['Concept Proposal'],
        'stages': [
          {'stage_label': 'Concept Proposal', 'deliverables': []},
        ],
        'current_stage': 'Concept Proposal',
      };

      await pumpDefensysWidget(
        tester,
        SizedBox(
          width: 400,
          height: 900,
          child: TeamTab(studentData: mockSingleStageData),
        ),
      );

      expect(find.text('Concept Proposal'), findsOneWidget);
      expect(find.text('Current Defense Stage'), findsOneWidget);
      expect(find.text('View Details'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'StudentEventsTab displays Capstone Defense Stages stepper, handles stage selection, and updates subtabs',
    (tester) async {
      final mockStudentData = {
        'student': {
          'id': 10,
          'name': 'Maria Santos',
          'email': 'maria@example.com',
        },
        'team': {
          'id': 1,
          'name': 'Team Innovators',
          'projectTitle': 'AI Defense Evaluation System',
          'isCapstone': true,
          'ready_for_stage': 'Colloquium',
          'current_stage': 'Colloquium',
          'adviserName': 'Dr. Alan Turing',
        },
        'schedule': {
          'date': '2026-10-24',
          'startTime': '10:00 AM',
          'room': 'Room 402',
          'stage': 'Colloquium',
          'panelists': [
            {'name': 'Prof. John von Neumann'},
            {'name': 'Dr. Ada Lovelace'},
          ],
        },
        'members': [
          {
            'id': 10,
            'name': 'Maria Santos',
            'username': 'student_10',
            'isLeader': true,
          },
          {
            'id': 11,
            'name': 'Carlos Reyes',
            'username': 'student_11',
            'isLeader': false,
          },
        ],
        'grades': {
          'status': 'published',
          'stage': 'Project Proposal',
          'result': 'PASSED',
          'final_grade': 94.5,
          'presentation': 28.5,
          'technical': 47.0,
          'qna': 19.0,
          'remarks': 'Outstanding system design and rigorous methodology.',
          'is_published': true,
        },
        'stage_options': ['Project Proposal', 'Colloquium', 'Final Defense'],
        'stages': [
          {
            'stage_label': 'Project Proposal',
            'is_officially_complete': true,
            'grade': {
              'final_grade': 94.5,
              'result': 'PASSED',
              'presentation': 28.5,
              'technical': 47.0,
              'qna': 19.0,
              'remarks': 'Outstanding system design and rigorous methodology.',
            },
          },
          {
            'stage_label': 'Colloquium',
            'is_officially_complete': false,
            'schedule': {
              'date': '2026-10-24',
              'startTime': '10:00 AM',
              'room': 'Room 402',
            },
          },
          {'stage_label': 'Final Defense', 'is_officially_complete': false},
        ],
      };

      await pumpDefensysWidget(
        tester,
        SizedBox(
          width: 400,
          height: 900,
          child: StudentEventsTab(
            isCapstone: true,
            studentData: mockStudentData,
          ),
        ),
        overrides: [
          capstoneDeliverablesProvider.overrideWith(
            _TestDeliverablesNotifier.new,
          ),
          teamDefenseProvider.overrideWith(_TestDefenses.new),
        ],
      );

      // 1. Verify Top Capstone Defense Stages Stepper
      expect(find.text('Capstone Defense Stages'), findsOneWidget);
      expect(find.text('Stage 2 of 3'), findsOneWidget);
      expect(find.text('Project Proposal'), findsWidgets);
      expect(find.text('Colloquium'), findsWidgets);
      expect(find.text('Final Defense'), findsWidgets);

      // 2. Verify 3 Subtabs are visible
      expect(find.text('Defense'), findsOneWidget);
      expect(find.text('Deliverables'), findsOneWidget);
      expect(find.text('Peer Eval'), findsOneWidget);

      // The Defense tab uses schedule records for the selected stage.
      expect(find.text('Room 402'), findsWidgets);
      expect(find.textContaining('Prof. John von Neumann'), findsOneWidget);

      // 4. Interactive Test: Tap "Project Proposal" in the stepper to inspect past records
      await tester.tap(find.text('Project Proposal').first);
      await tester.pumpAndSettle();

      // Context banner appears
      expect(
        find.text('Viewing past milestone archive for "Project Proposal"'),
        findsOneWidget,
      );
      expect(find.text('Room 101'), findsOneWidget);
      expect(find.text('Room 402'), findsNothing);

      // 5. Tap "Current (Colloquium) →" to jump back to current active stage
      await tester.tap(find.text('Current (Colloquium) →'));
      await tester.pumpAndSettle();

      expect(find.text('Room 402'), findsOneWidget);
      expect(find.text('Room 101'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
    },
  );
}
