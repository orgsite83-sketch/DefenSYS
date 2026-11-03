import 'package:defensys/screens/app/panelist/assignments_tab.dart';
import 'package:defensys/screens/app/panelist/panelist_models.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

TeamData _team({
  String name = 'Team ClayCircuit',
  bool shared = false,
  bool chair = true,
  bool complete = true,
  bool permitted = true,
  bool finished = false,
  String verdict = '',
}) => TeamData(
  name: name,
  project: 'Community craft platform',
  defenseDate: '2026-11-02',
  teamId: name,
  scheduleId: name,
  scope: 'capstone',
  isCapstone: true,
  isChair: chair,
  isPosted: true,
  isCompleted: finished,
  verdict: verdict,
  stageName: 'Concept Proposal',
  startTime: '08:00:00',
  room: 'Smart Room',
  members: const ['Andrea Cruz'],
  memberDetails: const [],
  criteria: const [],
  assessmentConcepts: const [
    {'key': 'c1', 'title': 'Craft platform'},
    {'key': 'c2', 'title': 'Inventory platform'},
  ],
  gradingWorkspace: {
    if (shared)
      'shared_review': {
        'id': 8,
        'verdict': '',
        'selected_key': '',
        'can_decide': chair && permitted,
      },
  },
  workflowGrade: {
    'status': finished ? 'published' : 'pending',
    'verdict': verdict,
    'workflow': {
      'can_save_recommendations': chair && permitted,
      'concept_workflow': {
        'enabled': true,
        if (shared) 'section_project_id': 8,
      },
      'outcome_rule': {
        'automatic': true,
        'per_concept': true,
        'panel_complete': complete,
        'outcome': shared || !complete ? 'pending' : 'approved',
        'assessments': const [
          {'key': 'c1', 'qualifies': true},
          {'key': 'c2', 'qualifies': true},
        ],
      },
    },
  },
);

void main() {
  test(
    'submitted scores do not finish a chair assignment needing concept selection',
    () {
      final chair = _team();
      expect(chair.evaluationStatus, 'Submitted');
      expect(chair.teamOutcomeStatus?.label, 'Choose team concept');
      expect(chair.needsChairDecision, isTrue);
      expect(chair.panelWorkFinished, isFalse);
      chair.verdict = 'approved';
      expect(chair.teamOutcomeStatus, isNull);
      expect(chair.needsChairDecision, isFalse);
      expect(chair.panelWorkFinished, isTrue);
    },
  );

  test(
    'waiting evaluations and ordinary panelists are not told to make chair decisions',
    () {
      final waiting = _team(complete: false);
      expect(waiting.teamOutcomeStatus?.label, 'Outcome: awaiting panel');
      expect(waiting.needsChairDecision, isFalse);
      final panelist = _team(chair: false);
      expect(
        panelist.teamOutcomeStatus?.label,
        'Awaiting chair concept selection',
      );
      expect(panelist.needsChairDecision, isFalse);
      final blocked = _team(permitted: false);
      expect(
        blocked.teamOutcomeStatus?.label,
        'Awaiting chair concept selection',
      );
      expect(blocked.needsChairDecision, isFalse);
      expect(_team(finished: true).needsChairDecision, isFalse);
    },
  );

  test(
    'shared selection is a separate duty and can precede complete team evaluations',
    () {
      final team = _team(shared: true, complete: false);
      expect(team.teamOutcomeStatus?.label, 'Outcome: awaiting panel');
      expect(team.sharedDecisionStatus?.label, 'Shared decision needed');
      expect(team.needsChairDecision, isTrue);
      expect(team.panelWorkFinished, isFalse);
      final review = team.gradingWorkspace['shared_review'] as Map;
      review.addAll(<String, Object>{
        'verdict': 'approved',
        'selected_key': 'c1',
        'can_decide': false,
      });
      expect(team.sharedDecisionStatus?.label, 'Shared system selected');
      expect(team.needsChairDecision, isFalse);
      expect(
        _team(shared: true, chair: false).sharedDecisionStatus?.label,
        'Shared decision pending',
      );
    },
  );

  test(
    'shared team outcome waits for the shared decision after panel completion',
    () {
      final team = _team(shared: true);
      expect(
        team.teamOutcomeStatus?.label,
        'Outcome: awaiting shared decision',
      );
      expect(team.sharedDecisionStatus?.label, 'Shared decision needed');
      expect(team.needsChairDecision, isTrue);
      final review = team.gradingWorkspace['shared_review'] as Map;
      review.addAll(<String, Object>{
        'verdict': 'for_redefense',
        'can_decide': false,
      });
      expect(team.sharedDecisionStatus?.label, 'Shared re-defense required');
      expect(team.teamOutcomeStatus?.label, 'Team outcome pending');
      expect(team.needsChairDecision, isFalse);
    },
  );

  test(
    'recorded re-defense still leaves the next-attempt chair decision outstanding',
    () {
      final team = _team(verdict: 'for_redefense');
      final workflow = team.workflowGrade!['workflow'] as Map;
      workflow['redefense_direction'] = {'direction': '', 'can_decide': true};
      expect(team.teamOutcomeStatus?.label, 'Next attempt decision needed');
      expect(team.needsChairDecision, isTrue);
      expect(team.panelWorkFinished, isFalse);
      (workflow['redefense_direction'] as Map).addAll(<String, Object>{
        'direction': 'independent',
        'can_decide': false,
      });
      expect(team.teamOutcomeStatus, isNull);
      expect(team.needsChairDecision, isFalse);
      expect(team.panelWorkFinished, isTrue);
    },
  );

  testWidgets(
    'Needs Decision retains submitted chair work and the original team index',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadPreviewFonts(force: true);
      int? opened;
      await pumpDefensysWidget(
        tester,
        AssignmentsTab(
          teams: [
            _team(name: 'Waiting for panel', complete: false),
            _team(name: 'Chair must choose'),
          ],
          onOpenGradeSheet: (index) => opened = index,
          showGroupHeaders: false,
        ),
      );
      await tester.tap(find.text('Needs Decision'));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for panel'), findsNothing);
      expect(find.text('Chair must choose'), findsOneWidget);
      expect(find.text('Choose team concept'), findsOneWidget);
      await tester.tap(find.text('View Grades'));
      expect(opened, 1);
      await tester.tap(find.text('Submitted').first);
      await tester.pumpAndSettle();
      expect(find.text('Waiting for panel'), findsOneWidget);
      expect(find.text('Chair must choose'), findsOneWidget);
    },
  );

  for (final dark in [false, true]) {
    for (final width in [390.0, 800.0, 1280.0]) {
      testWidgets('panel decision badges fit $width, dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts(force: true);
        final shared = _team(shared: true, name: 'Team ThreadAtlas');
        await pumpDefensysWidget(
          tester,
          AssignmentsTab(
            teams: [_team(), shared],
            onOpenGradeSheet: (_) {},
            showGroupHeaders: false,
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        );
        expect(find.text('Choose team concept'), findsOneWidget);
        expect(find.text('Shared decision needed'), findsOneWidget);
        expect(find.text('Outcome: awaiting shared decision'), findsOneWidget);
        expect(find.text('Submitted'), findsWidgets);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(AssignmentsTab),
          'panel-decisions-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
      });
    }
  }
}
