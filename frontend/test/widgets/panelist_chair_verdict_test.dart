import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/app/panelist/panelist_models.dart';
import 'package:defensys/screens/app/panelist/grade_sheet_tab.dart';
import 'package:defensys/screens/app/panelist/assignments_tab.dart';
import 'package:defensys/widgets/tactile_button.dart';
import 'package:defensys/screens/app/panelist/widgets/evaluation_score_picker.dart';

import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

TeamData _chairAssignment({
  bool ready = false,
  bool posted = false,
  bool chair = true,
  String? reason,
}) => TeamData(
  name: 'Team AgriSense',
  project: 'Smart Agriculture',
  defenseDate: 'Concept Proposal',
  teamId: '1',
  scheduleId: '10',
  scope: 'capstone',
  isCapstone: true,
  scheduledDate: TeamData.manilaToday,
  members: const ['Adrian'],
  memberDetails: const [TeamMember(id: '1', name: 'Adrian')],
  criteria: [],
  isPosted: posted,
  isChair: chair,
  serverGradingAvailable: true,
  serverCanIssueVerdict: ready,
  verdictUnavailableReason:
      reason ??
      (ready
          ? ''
          : 'Panel grading must be submitted before issuing a verdict.'),
  panelRubric: {
    'target_type': 'team',
    'criteria': [
      {'id': 1, 'name': 'Clarity', 'max_score': 10},
    ],
  },
);

TactileButton _verdictSubmit(WidgetTester tester) =>
    tester.widget<TactileButton>(
      find.ancestor(
        of: find.text('Submit Verdict'),
        matching: find.byWidgetPredicate((widget) => widget is TactileButton),
      ),
    );

void main() {
  setUpAll(loadPreviewFonts);
  group('Panelist Chair Verdict & Assignments Tests', () {
    test('chair identity and server verdict permission are separate', () {
      expect(_chairAssignment().isChair, isTrue);
      expect(_chairAssignment().canIssueVerdict, isFalse);
      expect(_chairAssignment(ready: true).canIssueVerdict, isTrue);
      expect(
        _chairAssignment(ready: true, chair: false).canIssueVerdict,
        isFalse,
      );
      expect(_chairAssignment(posted: true).canIssueVerdict, isFalse);
    });

    for (final width in [390.0, 800.0]) {
      testWidgets(
        'chair keeps the verdict section while grading is pending at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final team = _chairAssignment();
          Future<void> show(TeamData assignment) => pumpDefensysWidget(
            tester,
            RepaintBoundary(
              key: const ValueKey('chair-verdict-preview'),
              child: GradeSheetTab(
                teams: [assignment],
                selectedTeamIndex: 0,
                onTeamChanged: (_) {},
              ),
            ),
          );
          await show(team);
          expect(find.text('Panel Chair'), findsWidgets);
          expect(find.text('Panel Chair Official Verdict'), findsOneWidget);
          expect(
            find.text(
              'The official defense stage verdict will be rendered by the Panel Chair.',
            ),
            findsNothing,
          );
          expect(
            find.text(
              'Panel grading must be submitted before issuing a verdict.',
            ),
            findsOneWidget,
          );
          expect(_verdictSubmit(tester).onPressed, isNull);
          await tester.ensureVisible(
            find.byKey(const ValueKey('chair-verdict-unavailable')),
          );
          await tester.pumpAndSettle();
          await capturePreview(
            tester,
            find.byKey(const ValueKey('chair-verdict-preview')),
            'chair-verdict-locked-${width.toInt()}',
          );
          for (final radio in tester.widgetList<Radio<String>>(
            find.byType(Radio<String>),
          )) {
            expect(radio.enabled, isFalse);
          }
          // A locally completed score still needs backend submission before a verdict is available.
          await tester.ensureVisible(
            find.byKey(const ValueKey('start-team-evaluation')),
          );
          await tester.tap(find.byKey(const ValueKey('start-team-evaluation')));
          await tester.pumpAndSettle();
          final score = find.descendant(
            of: find.byType(EvaluationScorePicker),
            matching: find.byKey(const ValueKey('score-value-8')),
          );
          await tester.ensureVisible(score);
          await tester.tap(score);
          await tester.pumpAndSettle();
          expect(_verdictSubmit(tester).onPressed, isNull);
          await show(_chairAssignment(ready: true, posted: true));
          expect(
            find.byKey(const ValueKey('chair-verdict-unavailable')),
            findsNothing,
          );
          await tester.ensureVisible(find.text('Approved'));
          await tester.tap(find.text('Approved'));
          await tester.pumpAndSettle();
          expect(_verdictSubmit(tester).onPressed, isNotNull);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('chair sees the backend reason when the defense is paused', (
      tester,
    ) async {
      const reason =
          'This defense is paused. An administrator must resume it before grading.';
      await pumpDefensysWidget(
        tester,
        GradeSheetTab(
          teams: [_chairAssignment(ready: false, posted: true, reason: reason)],
          selectedTeamIndex: 0,
          onTeamChanged: (_) {},
        ),
      );
      expect(find.text('Panel Chair Official Verdict'), findsOneWidget);
      expect(find.text(reason), findsOneWidget);
      expect(_verdictSubmit(tester).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'AssignmentsTab shows CHAIR badge for chair assignments and VERDICT badge when present',
      (tester) async {
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
          memberDetails: [const TeamMember(id: '3', name: 'Ethan Salazar')],
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
      },
    );

    testWidgets(
      'GradeSheetTab displays Panel Chair Verdict Card and radio options when user is Chair',
      (tester) async {
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

        expect(find.text('Team details & presenting members'), findsOneWidget);
        expect(find.text('Panel Chair'), findsWidgets);

        // Verify Chair Verdict section
        expect(find.text('Panel Chair Official Verdict'), findsOneWidget);
        expect(find.text('OFFICIAL STAGE VERDICT'), findsOneWidget);
        expect(find.text('Approved'), findsOneWidget);
        expect(find.text('Approved with Revisions'), findsOneWidget);
        expect(find.text('For Re-defense'), findsOneWidget);
        expect(find.text('Failed'), findsOneWidget);
        expect(find.text('Project Rejected'), findsOneWidget);
        expect(find.text('Submit Verdict'), findsOneWidget);

        // Tap on For Re-defense option
        await tester.ensureVisible(find.text('For Re-defense'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('For Re-defense'));
        await tester.pumpAndSettle();
        expect(find.text('For Re-defense'), findsOneWidget);
        expect(find.text('Require adviser verification of corrections'), findsOneWidget);
        expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isFalse);
      },
    );

    testWidgets(
      'GradeSheetTab displays read-only verdict notice when user is NOT Chair',
      (tester) async {
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

        expect(find.text('Panel Chair'), findsNothing);

        // Should have read-only verdict card
        expect(find.text('Official Stage Verdict'), findsOneWidget);
        expect(find.text('APPROVED W/ REVISIONS'), findsOneWidget);
        expect(
          find.text('Issued by Panel Chair: Prof. Daga-ang'),
          findsOneWidget,
        );
        expect(find.text('Submit chapter 4 manuscript update'), findsOneWidget);
      },
    );

    testWidgets(
      'AssignmentsTab filters retain completed defenses under Submitted',
      (tester) async {
        int? openedIndex;

        final teamA = TeamData(
          name: 'Team Alpha',
          project: 'Automated Hydroponics',
          defenseDate: 'Concept Pitch - 2026-10-20 09:00',
          scheduledDate: DateTime(2000, 1, 1),
          stageName: 'Concept Pitch',
          eventName: 'PIT Expo 2026',
          startTime: '09:00',
          room: 'Lab 1',
          teamId: '101',
          scope: 'pit',
          isCapstone: false,
          members: ['Alice Santos'],
          memberDetails: [const TeamMember(id: '1', name: 'Alice Santos')],
          criteria: [],
          isPosted: false,
        );

        final teamB = TeamData(
          name: 'Team Beta',
          project: 'Solar Forecasting',
          defenseDate: 'Title Defense - 2026-10-21 13:30',
          stageName: 'Title Defense',
          eventName: 'Capstone Defense 2026',
          startTime: '13:30',
          room: 'Room 302',
          teamId: '102',
          scheduleStatus: 'done',
          scheduledDate: TeamData.manilaToday,
          verdict: 'approved',
          scope: 'capstone',
          isCapstone: true,
          members: ['Bob Cruz'],
          memberDetails: [const TeamMember(id: '2', name: 'Bob Cruz')],
          criteria: [],
          isPosted: true,
        );

        await pumpDefensysWidget(
          tester,
          AssignmentsTab(
            teams: [teamA, teamB],
            onOpenGradeSheet: (idx) => openedIndex = idx,
          ),
        );

        // Verify header and workload counters
        expect(find.text('My Panel Assignments'), findsOneWidget);
        expect(find.text('2 defense teams assigned to you'), findsOneWidget);
        expect(find.text('Needs Grading'), findsWidgets);
        expect(find.text('Submitted'), findsWidgets);

        // Both teams initially visible
        expect(find.text('Team Alpha'), findsOneWidget);
        expect(find.text('Team Beta'), findsOneWidget);

        // Filter by "Needs Grading"
        await tester.tap(find.text('Needs Grading').first);
        await tester.pumpAndSettle();

        expect(find.text('Team Alpha'), findsOneWidget);
        expect(find.text('Team Beta'), findsNothing);

        // Completed defenses remain in Submitted with their verdict and review action.
        await tester.tap(find.text('Submitted').first);
        await tester.pumpAndSettle();

        expect(find.text('Team Alpha'), findsNothing);
        expect(find.text('Team Beta'), findsOneWidget);
        expect(find.text('APPROVED'), findsOneWidget);
        expect(find.text('Grade Team'), findsNothing);
        await tester.ensureVisible(find.text('View Grades'));
        await tester.tap(find.text('View Grades'));
        await tester.pumpAndSettle();
        expect(openedIndex, equals(1));

        // Reset to "All Teams"
        await tester.tap(find.text('All Teams'));
        await tester.pumpAndSettle();

        expect(find.text('Team Alpha'), findsOneWidget);
        expect(find.text('Team Beta'), findsOneWidget);

        // Test search query
        await tester.enterText(find.byType(TextField), 'hydroponics');
        await tester.pumpAndSettle();

        expect(find.text('Team Alpha'), findsOneWidget);
        expect(find.text('Team Beta'), findsNothing);

        // Test "Grade Team" action opens with correct original index 0
        await tester.tap(find.text('Grade Team'));
        await tester.pumpAndSettle();

        expect(openedIndex, equals(0));
      },
    );
  });
}
