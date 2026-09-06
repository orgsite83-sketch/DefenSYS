import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/app/panelist/panelist_models.dart';
import 'package:defensys/screens/app/panelist/grade_sheet_tab.dart';
import 'package:defensys/screens/app/panelist/assignments_tab.dart';

import '../helpers/pump_app.dart';

void main() {
  group('Panelist Chair Verdict & Assignments Tests', () {
    testWidgets('AssignmentsTab shows CHAIR badge for chair assignments and VERDICT badge when present', (
      tester,
    ) async {
      final teamChair = TeamData(
        name: 'Team SkyLedger',
        project: 'Alumni Career Tracker',
        defenseDate: 'Colloquium - 2026-09-15 10:00',
        teamId: '1',
        scheduleId: '10',
        scope: 'capstone',
        isCapstone: true,
        members: ['Marcus Villar', 'Patricia Ong'],
        memberDetails: [
          const TeamMember(id: '1', name: 'Marcus Villar'),
          const TeamMember(id: '2', name: 'Patricia Ong'),
        ],
        criteria: [],
        isPosted: false,
        isChair: true,
        verdict: 'for_redefense',
      );

      final teamMember = TeamData(
        name: 'Team Horizon',
        project: 'Smart Inventory',
        defenseDate: 'Colloquium - 2026-09-15 11:00',
        teamId: '2',
        scheduleId: '11',
        scope: 'capstone',
        isCapstone: true,
        members: ['Ethan Salazar'],
        memberDetails: [
          const TeamMember(id: '3', name: 'Ethan Salazar'),
        ],
        criteria: [],
        isPosted: false,
        isChair: false,
      );

      await pumpDefensysWidget(
        tester,
        AssignmentsTab(
          teams: [teamChair, teamMember],
          onOpenGradeSheet: (_) {},
        ),
      );

      expect(find.text('Team SkyLedger'), findsOneWidget);
      expect(find.text('CHAIR'), findsOneWidget);
      expect(find.text('RE-DEFENSE'), findsOneWidget);

      expect(find.text('Team Horizon'), findsOneWidget);
    });

    testWidgets('GradeSheetTab displays Panel Chair Verdict Card and radio options when user is Chair', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final team = TeamData(
        name: 'Team SkyLedger',
        project: 'Alumni Career Tracker',
        defenseDate: 'Colloquium - 2026-09-15 10:00',
        teamId: '1',
        scheduleId: '10',
        scope: 'capstone',
        isCapstone: true,
        members: ['Marcus Villar', 'Patricia Ong'],
        memberDetails: [
          const TeamMember(id: '1', name: 'Marcus Villar'),
          const TeamMember(id: '2', name: 'Patricia Ong'),
        ],
        criteria: [Criterion('Clarity', 10, id: 1)],
        isPosted: true,
        isChair: true,
        panelRubric: {
          'target_type': 'team',
          'criteria': [
            {'id': 1, 'name': 'Clarity', 'max_score': 10},
          ],
        },
      );

      await pumpDefensysWidget(
        tester,
        GradeSheetTab(
          teams: [team],
          selectedTeamIndex: 0,
          onTeamChanged: (_) {},
        ),
      );

      // Verify Chair presiding banner
      expect(
        find.text('You are presiding as the Panel Chair for this defense hearing.'),
        findsOneWidget,
      );

      // Verify Chair Verdict section
      expect(find.text('Panel Chair Official Verdict'), findsOneWidget);
      expect(find.text('OFFICIAL STAGE VERDICT'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Approved with Revisions'), findsOneWidget);
      expect(find.text('For Re-defense'), findsOneWidget);
      expect(find.text('Submit Official Verdict'), findsOneWidget);

      // Tap on For Re-defense option
      await tester.tap(find.text('For Re-defense'));
      await tester.pumpAndSettle();
      expect(find.text('For Re-defense'), findsOneWidget);
    });

    testWidgets('GradeSheetTab displays read-only verdict notice when user is NOT Chair', (
      tester,
    ) async {
      final team = TeamData(
        name: 'Team SkyLedger',
        project: 'Alumni Career Tracker',
        defenseDate: 'Colloquium - 2026-09-15 10:00',
        teamId: '1',
        scheduleId: '10',
        scope: 'capstone',
        isCapstone: true,
        members: ['Marcus Villar'],
        memberDetails: [const TeamMember(id: '1', name: 'Marcus Villar')],
        criteria: [Criterion('Clarity', 10, id: 1)],
        isPosted: true,
        isChair: false,
        verdict: 'approved_with_revisions',
        verdictByName: 'Prof. Daga-ang',
        verdictRemarks: 'Submit chapter 4 manuscript update',
        panelRubric: {
          'target_type': 'team',
          'criteria': [
            {'id': 1, 'name': 'Clarity', 'max_score': 10},
          ],
        },
      );

      await pumpDefensysWidget(
        tester,
        GradeSheetTab(
          teams: [team],
          selectedTeamIndex: 0,
          onTeamChanged: (_) {},
        ),
      );

      // Should NOT have presiding banner
      expect(
        find.text('You are presiding as the Panel Chair for this defense hearing.'),
        findsNothing,
      );

      // Should have read-only verdict card
      expect(find.text('Official Stage Verdict'), findsOneWidget);
      expect(find.text('APPROVED W/ REVISIONS'), findsOneWidget);
      expect(find.text('Issued by Panel Chair: Prof. Daga-ang'), findsOneWidget);
      expect(find.text('Submit chapter 4 manuscript update'), findsOneWidget);
    });
  });
}
