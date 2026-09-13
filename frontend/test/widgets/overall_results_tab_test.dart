import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/app/panelist/overall_results_tab.dart';

import '../helpers/pump_app.dart';

void main() {
  group('OverallResultsTab UI/UX Tests', () {
    final mockResults = [
      {
        'teamName': 'Team EcoSense',
        'projectTitle': 'Smart Classroom Climate Monitor',
        'percentage': 85.0,
        'total': 93.5,
        'max': 110.0,
        'teamStatus': 'Approved',
        'level': '1st Year',
        'stage': 'Proposal Defense',
        'criteria': [
          {
            'criteriaName': 'Problem Identification & Clarity',
            'score': 9.0,
            'max': 10.0,
            'student_name': null,
          },
          {
            'criteriaName': 'Technical Feasibility & Scope',
            'score': 8.0,
            'max': 10.0,
            'student_name': 'Marcus Villar',
          },
          {
            'criteriaName': 'Technical Feasibility & Scope',
            'score': 9.0,
            'max': 10.0,
            'student_name': 'Patricia Ong',
          },
        ],
        'memberGrades': [
          {
            'name': 'Marcus Villar',
            'isLeader': true,
            'panelContrib': 68.0,
            'peerScore': 85.0,
            'peerMax': 100.0,
            'finalGrade': 84.5,
          },
          {
            'name': 'Patricia Ong',
            'isLeader': false,
            'panelContrib': 72.0,
            'peerScore': 90.0,
            'peerMax': 100.0,
            'finalGrade': 88.0,
          },
        ],
        'weights': {'panel': 80, 'peer': 20},
      },
      {
        'teamName': 'Team SolarWatch',
        'projectTitle': 'IoT Solar Cell Optimization',
        'percentage': 78.0,
        'total': 85.8,
        'max': 110.0,
        'teamStatus': 'Approved',
        'level': '1st Year',
        'stage': 'Final Defense',
        'criteria': [
          {
            'criteriaName': 'Technical Quality',
            'score': 8.0,
            'max': 10.0,
            'student_name': null,
          },
        ],
        'memberGrades': [],
        'weights': {'panel': 80, 'peer': 20},
      },
    ];

    testWidgets('renders executive KPI summary strip and team card ranking', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpDefensysWidget(
        tester,
        OverallResultsTab(results: mockResults),
      );

      // Verify KPI Metrics
      expect(find.text('Class Avg'), findsOneWidget);
      expect(find.text('81.5%'), findsOneWidget); // (85 + 78) / 2 = 81.5%
      expect(find.text('Top Score'), findsOneWidget);
      expect(find.text('85.0%'), findsNWidgets(2)); // KPI Top Score and Team EcoSense score pill
      expect(find.text('Pass Rate'), findsOneWidget);
      expect(find.text('100%'), findsWidgets);

      // Verify Team Names & Podium
      expect(find.text('Team EcoSense'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('Team SolarWatch'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
    });

    testWidgets('groups individual student criteria under student names and separates shared criteria', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpDefensysWidget(
        tester,
        OverallResultsTab(results: mockResults),
      );

      // Team 0 is expanded by default
      expect(find.text('Shared Team Criteria'), findsOneWidget);
      expect(find.text('Problem Identification & Clarity'), findsOneWidget);

      expect(find.text('Individual Member Criteria'), findsOneWidget);
      expect(find.text('Marcus Villar'), findsWidgets);
      expect(find.text('Patricia Ong'), findsWidgets);
    });

    testWidgets('progressive disclosure toggles detailed breakdown open and closed', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpDefensysWidget(
        tester,
        OverallResultsTab(results: mockResults),
      );

      // Initially expanded for #1
      expect(find.text('Hide Detailed Breakdown'), findsOneWidget);

      // Tap to collapse
      await tester.tap(find.text('Hide Detailed Breakdown'));
      await tester.pumpAndSettle();

      // Should now be collapsed
      expect(find.text('View Criteria & Member Breakdown (3 items)'), findsOneWidget);
      expect(find.text('Shared Team Criteria'), findsNothing);

      // Tap to expand again
      await tester.tap(find.text('View Criteria & Member Breakdown (3 items)'));
      await tester.pumpAndSettle();

      expect(find.text('Hide Detailed Breakdown'), findsOneWidget);
      expect(find.text('Shared Team Criteria'), findsOneWidget);
    });

    testWidgets('stage filter chips filter results', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await pumpDefensysWidget(
        tester,
        OverallResultsTab(results: mockResults),
      );

      expect(find.text('All Stages (2)'), findsOneWidget);
      expect(find.text('Proposal Defense (1)'), findsOneWidget);
      expect(find.text('Final Defense (1)'), findsOneWidget);

      // Filter by Proposal Defense
      await tester.tap(find.text('Proposal Defense (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Team EcoSense'), findsOneWidget);
      expect(find.text('Team SolarWatch'), findsNothing);
    });
  });
}
