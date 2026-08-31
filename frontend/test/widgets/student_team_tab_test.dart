import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/app/student/team_tab.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('TeamTab displays unified top roster, academic stages, defense status, and results', (
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
    };

    int? selectedTab;

    await pumpDefensysWidget(
      tester,
      SizedBox(
        width: 400,
        height: 900,
        child: TeamTab(
          studentData: mockStudentData,
          onSelectTab: (index) => selectedTab = index,
        ),
      ),
    );

    // 1. Verify Top Unified Team & Project Card (with Roster & Peer Eval)
    expect(find.text('Hi, Maria'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsWidgets);
    expect(find.text('Colloquium'), findsWidgets);
    expect(find.text('Members (2):'), findsOneWidget);
    expect(find.text('Peer Eval ✓'), findsOneWidget);

    // 2. Verify Capstone Defense Stages Stepper
    expect(find.text('Capstone Defense Stages'), findsOneWidget);
    expect(find.text('Project Proposal'), findsWidgets);
    expect(find.text('Passed'), findsWidgets);
    expect(find.text('Current'), findsWidgets);

    // 3. Verify Active Defense Status Overview
    expect(find.text('Active Defense Status'), findsOneWidget);
    expect(find.text('DEFENSE COUNTDOWN:'), findsOneWidget);
    expect(find.text('Room 402'), findsOneWidget);
    expect(find.text('Stage Deliverables'), findsOneWidget);
    expect(find.text('Manuscript Draft'), findsOneWidget);
    expect(find.text('Slide Deck'), findsOneWidget);
    expect(find.text('Adviser: Dr. Alan Turing'), findsOneWidget);

    // 4. Verify Past Defense Results & Grades
    expect(find.text('Past Defense Results & Grades'), findsOneWidget);
    expect(find.text('Score: 94.5 (Passed)'), findsOneWidget);

    // 5. Verify Tapping Peer Evaluation triggers navigation
    await tester.tap(find.text('Peer Eval ✓'));
    expect(selectedTab, equals(1));

    await tester.pump(const Duration(seconds: 1));
  });
}
