import 'package:defensys/screens/web/admin/grade_center/grade_center_shared.dart';
import 'package:defensys/services/grade_center_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';

final _teams = [
  for (final name in [
    'AgriSense',
    'BioPulse',
    'CodeLearners',
    'CyberGuard',
    'EcoRoute',
    'EduTrack',
    'MedBilling',
    'MedInventory',
    'MedLab',
    'MedPharma',
    'MedRecord',
    'MedSchedule',
    'MedTriage',
    'MedWards',
    'SafeCity',
    'SkyLedger',
  ])
    {
      'team_name': 'Team $name',
      'missing_components': ['panel', 'peer', 'adviser'],
      'evaluators_done': 0,
      'evaluators_total': 4,
      'submitted': 0,
      'required': 12,
    },
];

Future<void> _openDialog(
  WidgetTester tester, {
  bool dark = false,
  List<Map<String, dynamic>>? teams,
  double textScale = 1,
  GradeGroupCompletionReadiness? completion,
  ValueChanged<bool>? onCompletionResult,
  bool isPit = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
      builder: (context, child) => RepaintBoundary(
        key: const ValueKey('readiness-preview'),
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              if (completion != null) {
                final result = await reviewGradeGroupCompletion(
                  context,
                  stageLabel: 'Concept Proposal',
                  checkCompletion: () async => completion,
                  isPit: isPit,
                );
                onCompletionResult?.call(result);
              } else {
                await showIncompleteGradingTeamsDialog(
                  context,
                  teams: teams ?? _teams,
                );
              }
            },
            child: const Text('Open readiness'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open readiness'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  for (final dark in [false, true]) {
    for (final size in [const Size(1100, 844), const Size(390, 640)]) {
      testWidgets(
        'unresolved re-defense and revisions block completion at $size ($dark)',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          bool? result;
          await _openDialog(
            tester,
            dark: dark,
            onCompletionResult: (value) => result = value,
            completion: const GradeGroupCompletionReadiness(
              totalTeams: 2,
              readyTeams: 2,
              canComplete: true,
              redefenseTeams: [
                {'team_name': 'Team Retry'},
              ],
              revisionTeams: [
                {'team_name': 'Team Revise'},
              ],
            ),
          );
          expect(find.text('Grading not ready'), findsOneWidget);
          expect(find.text('Re-defense required: 1 missing'), findsOneWidget);
          expect(find.text('Revision clearance: 1 missing'), findsOneWidget);
          expect(find.text('Mark Complete'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.tap(find.widgetWithText(OutlinedButton, 'Close'));
          await tester.pumpAndSettle();
          expect(result, isFalse);
        },
      );
    }
  }

  testWidgets('cleared teams can confirm stage completion', (tester) async {
    bool? result;
    await _openDialog(
      tester,
      onCompletionResult: (value) => result = value,
      completion: const GradeGroupCompletionReadiness(
        totalTeams: 1,
        readyTeams: 1,
        canComplete: true,
      ),
    );
    expect(find.text('Mark Complete'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Mark Complete'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  for (final dark in [false, true]) {
    for (final size in [
      const Size(1100, 840),
      const Size(390, 844),
      const Size(390, 640),
      const Size(800, 420),
    ]) {
      testWidgets(
        '16 teams fit and scroll at $size (${dark ? 'dark' : 'light'})',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await _openDialog(tester, dark: dark);

          expect(tester.takeException(), isNull);
          expect(find.text('16 teams need attention'), findsOneWidget);
          expect(find.text('Panel: 16 missing'), findsOneWidget);
          expect(find.text('Adviser: 16 missing'), findsOneWidget);
          expect(find.text('Peer: 16 missing'), findsOneWidget);
          expect(find.text('Team AgriSense'), findsOneWidget);
          expect(find.text('0/4 evaluators'), findsWidgets);
          expect(find.text('0/12 submissions'), findsWidgets);
          final closePosition = tester.getRect(
            find.widgetWithText(OutlinedButton, 'Close'),
          );
          final titlePosition = tester.getRect(find.text('Grading not ready'));
          expect(closePosition.bottom, lessThan(size.height));
          expect(closePosition.right, lessThan(size.width));
          expect(titlePosition.top, greaterThan(0));

          if (size.height > 800) {
            await capturePreview(
              tester,
              find.byKey(const ValueKey('readiness-preview')),
              'grading-readiness-${size.width.toInt()}-${dark ? 'dark' : 'light'}',
            );
          }
          final list = find.byKey(
            const ValueKey('incomplete-grading-teams-list'),
          );
          await tester.scrollUntilVisible(
            find.text('Team SkyLedger'),
            160,
            scrollable: find.descendant(
              of: list,
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Team SkyLedger').hitTestable(), findsOneWidget);
          expect(tester.getRect(find.text('Grading not ready')), titlePosition);
          expect(
            tester.getRect(find.widgetWithText(OutlinedButton, 'Close')),
            closePosition,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('team search keeps blocker totals and supports clearing', (
    tester,
  ) async {
    await _openDialog(tester);
    await tester.enterText(find.byType(TextField), '  BIOpulse  ');
    await tester.pumpAndSettle();
    expect(find.text('Team BioPulse'), findsOneWidget);
    expect(find.text('Team AgriSense'), findsNothing);
    expect(find.text('Showing 1 of 16 teams'), findsOneWidget);
    expect(find.text('16 teams need attention'), findsOneWidget);
    expect(find.text('Panel: 16 missing'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'No matching team');
    await tester.pumpAndSettle();
    expect(find.text('No teams match your search.'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Team AgriSense'), findsOneWidget);
    expect(find.text('Showing 16 of 16 teams'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Grading not ready'), findsNothing);
  });

  testWidgets(
    'only missing components are flagged and peer progress is preserved',
    (tester) async {
      await _openDialog(
        tester,
        teams: [
          {
            'team_name': 'Team BioPulse',
            'missing_components': ['peer'],
            'evaluators_done': 3,
            'evaluators_total': 4,
            'submitted': 9,
            'required': 12,
          },
        ],
      );
      expect(find.text('1 team needs attention'), findsOneWidget);
      expect(find.text('Peer: 1 missing'), findsOneWidget);
      expect(find.text('Panel: 1 missing'), findsNothing);
      expect(find.text('Adviser: 1 missing'), findsNothing);
      expect(find.text('Ready'), findsNWidgets(2));
      expect(find.text('3/4 evaluators'), findsOneWidget);
      expect(find.text('9/12 submissions'), findsOneWidget);
    },
  );

  testWidgets('large text fits on a phone and retains a visible close action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openDialog(tester, textScale: 1.4);
    expect(tester.takeException(), isNull);
    expect(
      find.widgetWithText(OutlinedButton, 'Close').hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Grading not ready'), findsNothing);
  });

  testWidgets(
    'smart tab switches to deliverables tab when only post-defense is missing',
    (tester) async {
      await _openDialog(
        tester,
        teams: [
          {
            'team_name': 'Team CyberGuard',
            'missing_components': ['post_defense'],
            'panel_complete': true,
            'adviser_complete': true,
            'peer_complete': true,
            'post_defense_complete': false,
          },
        ],
      );
      expect(find.text('Post-defense deliverables: 1 missing'), findsOneWidget);
      // Auto-selected Tab 1: Deliverables & Clearance
      expect(find.text('Post-defense deliverable'), findsOneWidget);
      expect(find.text('Verdict & clearance'), findsOneWidget);
      expect(find.text('Awaiting Adviser Approval'), findsOneWidget);
      expect(find.text('Cleared'), findsOneWidget);

      // Tap Tab 0: Evaluator Grades
      await tester.tap(find.byKey(const ValueKey('tab-evaluator-grades')));
      await tester.pumpAndSettle();

      expect(find.text('Panel'), findsOneWidget);
      expect(find.text('Adviser'), findsOneWidget);
      expect(find.text('Peer evaluation'), findsOneWidget);
      expect(find.text('Ready'), findsNWidgets(3));

      // Tap Tab 1: Deliverables & Clearance
      await tester.tap(find.byKey(const ValueKey('tab-deliverables-clearance')));
      await tester.pumpAndSettle();
      expect(find.text('Awaiting Adviser Approval'), findsOneWidget);
    },
  );

  testWidgets(
    'confirmation dialog displays evaluator grades and deliverables readiness breakdown',
    (tester) async {
      await _openDialog(
        tester,
        completion: const GradeGroupCompletionReadiness(
          totalTeams: 16,
          readyTeams: 16,
          canComplete: true,
          panelCompleteCount: 16,
          adviserCompleteCount: 16,
          adviserEnabled: true,
          peerCompleteCount: 16,
          peerEnabled: true,
          verdictCompleteCount: 16,
          postDeliverablesCompleteCount: 16,
        ),
      );

      expect(find.text('Mark Concept Proposal Complete?'), findsOneWidget);
      expect(find.text('All 16 teams are ready'), findsOneWidget);
      expect(find.text('Evaluator Grades'), findsOneWidget);
      expect(find.text('Deliverables & Clearance'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Mark Complete'), findsOneWidget);
      expect(find.text('Ready'), findsWidgets);
    },
  );

  testWidgets(
    'confirmation dialog handles PIT scope with disabled adviser',
    (tester) async {
      await _openDialog(
        tester,
        isPit: true,
        completion: const GradeGroupCompletionReadiness(
          totalTeams: 8,
          readyTeams: 8,
          canComplete: true,
          panelCompleteCount: 8,
          peerCompleteCount: 8,
          peerEnabled: true,
          postDeliverablesCompleteCount: 8,
        ),
      );

      expect(find.text('Mark Concept Proposal Complete?'), findsOneWidget);
      expect(find.text('All 8 teams are ready'), findsOneWidget);
      expect(find.text('Evaluator Grades'), findsOneWidget);
      expect(find.text('Adviser'), findsNothing);
      expect(find.text('Deliverables & Clearance'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Mark Complete'), findsOneWidget);
    },
  );
}

