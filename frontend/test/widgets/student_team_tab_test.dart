import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/app/student/team_tab.dart';
import 'package:defensys/screens/app/student/student_events_tab.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/defense/team_defense_provider.dart';

import '../helpers/pump_app.dart';

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
      expect(find.text('Shared system concepts'), findsNothing);
      expect(find.text('AI Defense Evaluation System'), findsOneWidget);
      expect(find.text('Colloquium'), findsWidgets);
      expect(find.text('Team Members (2)'), findsOneWidget);
      expect(find.text('Current Defense Stage'), findsOneWidget);
      expect(find.text('View Details'), findsOneWidget);
      expect(find.textContaining('Score: 94.5'), findsOneWidget);
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
