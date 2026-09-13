import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/app/student/team_tab.dart';
import 'package:defensys/screens/app/student/student_events_tab.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';

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
    state = state.copyWith(
      selectedStage: selectedStage ?? state.selectedStage,
    );
  }
}

void main() {
  testWidgets('TeamTab displays unified top roster, defense roadmap access, and past results', (
    tester,
  ) async {
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
        {'id': 10, 'name': 'Maria Santos', 'username': 'student_10', 'isLeader': true},
        {'id': 11, 'name': 'Carlos Reyes', 'username': 'student_11', 'isLeader': false},
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

    // 1. Verify Top Unified Team & Project Card (with Roster & Peer Eval)
    expect(find.text('Hi, Maria'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsWidgets);
    expect(find.text('Colloquium'), findsWidgets);
    expect(find.text('Members (2):'), findsOneWidget);
    expect(find.text('Peer Eval ✓'), findsOneWidget);

    // 2. Verify Milestone Roadmap Shortcut Card
    expect(find.text('Capstone Defense Roadmap'), findsOneWidget);
    expect(find.text('Current: Colloquium · Stage 2 of 3'), findsOneWidget);
    expect(find.text('Defense Scheduled: 2026-10-24 · Room 402'), findsOneWidget);
    expect(find.text('Open Defense Roadmap & Stages →'), findsOneWidget);

    // 3. Verify Past Defense Results & Grades
    expect(find.text('Past Defense Results & Grades'), findsOneWidget);
    expect(find.text('Score: 94.5 (Passed)'), findsOneWidget);

    // 4. Interactive Test: Tap "Open Defense Roadmap & Stages →" to navigate to Stages tab (index 1)
    await tester.tap(find.text('Open Defense Roadmap & Stages →'));
    expect(selectedTab, equals(1));

    // 5. Verify Tapping Peer Evaluation shortcut also navigates
    selectedTab = null;
    await tester.tap(find.text('Peer Eval ✓'));
    expect(selectedTab, equals(1));

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('TeamTab displays single configured stage dynamically without hardcoded defaults', (
    tester,
  ) async {
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
        {'id': 10, 'name': 'Marcus Villar', 'username': 'student_10', 'isLeader': true},
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
        child: TeamTab(
          studentData: mockSingleStageData,
        ),
      ),
    );

    // Verify single configured stage progress
    expect(find.text('Current: Concept Proposal · Stage 1 of 1'), findsOneWidget);
    expect(find.text('Open Defense Roadmap & Stages →'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('StudentEventsTab displays Capstone Defense Stages stepper, handles stage selection, and updates subtabs', (
    tester,
  ) async {
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
        {'id': 10, 'name': 'Maria Santos', 'username': 'student_10', 'isLeader': true},
        {'id': 11, 'name': 'Carlos Reyes', 'username': 'student_11', 'isLeader': false},
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
        {
          'stage_label': 'Final Defense',
          'is_officially_complete': false,
        },
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
        capstoneDeliverablesProvider.overrideWith(_TestDeliverablesNotifier.new),
      ],
    );

    // 1. Verify Top Capstone Defense Stages Stepper
    expect(find.text('Capstone Defense Stages'), findsOneWidget);
    expect(find.text('Stage 2 of 3'), findsOneWidget);
    expect(find.text('Project Proposal'), findsWidgets);
    expect(find.text('Colloquium'), findsWidgets);
    expect(find.text('Final Defense'), findsWidgets);

    // 2. Verify 3 Subtabs are visible
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Deliverables'), findsOneWidget);
    expect(find.text('Peer Eval'), findsOneWidget);

    // 3. Verify Schedule tab displays active stage details (Colloquium)
    expect(find.text('Defense Status for Colloquium'), findsOneWidget);
    expect(find.text('Room 402'), findsWidgets);
    expect(find.text('DEFENSE COUNTDOWN:'), findsOneWidget);
    expect(find.text('Prof. John von Neumann, Dr. Ada Lovelace'), findsOneWidget);
    expect(find.text('Adviser: Dr. Alan Turing'), findsOneWidget);

    // 4. Interactive Test: Tap "Project Proposal" in the stepper to inspect past records
    await tester.tap(find.text('Project Proposal').first);
    await tester.pumpAndSettle();

    // Context banner appears
    expect(find.text('Viewing past milestone archive for "Project Proposal"'), findsOneWidget);
    expect(find.text('Deliberation Result: PASSED'), findsOneWidget);
    expect(find.text('Official Grade: 94.5 • Completed'), findsOneWidget);
    expect(find.text('Panel Feedback: "Outstanding system design and rigorous methodology."'), findsOneWidget);

    // 5. Tap "Current (Colloquium) →" to jump back to current active stage
    await tester.tap(find.text('Current (Colloquium) →'));
    await tester.pumpAndSettle();

    expect(find.text('Defense Status for Colloquium'), findsOneWidget);
    expect(find.text('DEFENSE COUNTDOWN:'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
  });
}
