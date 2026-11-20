import 'package:defensys/screens/web/admin/defense_scheduler/components/team_readiness_tracker.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';

const stage = 'Project Proposal';

List<Map<String, dynamic>> statusTeams() => [
  for (final entry in [
    (1, 'Requirements team', 'pending', 'awaiting_files'),
    (2, 'Endorsement team', 'pending', 'awaiting_endorsement'),
    (3, 'Ready team', 'ready', 'endorsed'),
    (4, 'Repeat team', 'scheduled', ''),
    (5, 'Demo team', 're_demo_scheduled', ''),
    (6, 'Completed team', 'completed', ''),
    (7, 'Post-defense team', 'pending_post_defense', ''),
  ])
    {
      'id': entry.$1,
      'name': entry.$2,
      'project_title': 'Project ${entry.$1}',
      'level': '3rd Year Capstone',
      'section': 'BSIT-3A',
      'adviser_name': 'Maria Santos',
      'adviser': 1,
      'eligible_stages': [if (entry.$1 == 3) stage],
      'stage_progress': {stage: entry.$3},
      'stage_status_details': {
        stage: {
          'requirements_status': entry.$4,
          'attempt_count': entry.$1 == 4 ? 2 : 1,
        },
      },
      'stage_verdicts': {if (entry.$1 == 5) stage: 'approved_with_revisions'},
      if (entry.$1 == 5)
        're_demo_stages': {
          stage: {'source_schedule_id': 50, 'can_schedule': false},
        },
    },
];

Widget workspace({
  bool dark = false,
  double textScale = 1,
  String selectedStage = stage,
  void Function(Map<String, dynamic>, String)? onReview,
}) => ProviderScope(
  overrides: authTestOverrides(),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.mistDarkTheme,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        key: const PageStorageKey('team-status-workspace-scroll'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TeamReadinessTracker(
            state: DefenseSchedulerState(teams: statusTeams()),
            scope: 'capstone',
            activeStageOrEventName: selectedStage,
            onReviewTeamDeliverables: onReview ?? (_, _) {},
            onSendReminder: (_, _) {},
            isSendingReminder: false,
          ),
        ),
      ),
    ),
  ),
);

Finder count(String group, int value) => find.descendant(
  of: find.byKey(ValueKey('team-status-group-$group')),
  matching: find.text('$value'),
);

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets('team status fits $width dark=$dark', (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts(force: true);
        await tester.pumpWidget(
          workspace(dark: dark, textScale: width == 320 ? 1.3 : 1),
        );
        await tester.pumpAndSettle();
        expect(count('all', 7), findsOneWidget);
        expect(count('beforeScheduling', 3), findsOneWidget);
        expect(count('scheduled', 2), findsOneWidget);
        expect(count('followUp', 1), findsOneWidget);
        expect(count('completed', 1), findsOneWidget);
        await tester.tap(find.text('BSIT-3A'));
        await tester.pumpAndSettle();
        expect(find.text('Awaiting requirements'), findsOneWidget);
        expect(find.text('Awaiting endorsement'), findsOneWidget);
        expect(find.text('Re-defense scheduled'), findsOneWidget);
        expect(find.text('Re-demo scheduled'), findsOneWidget);
        expect(find.text('Approved with Revisions'), findsOneWidget);
        expect(find.text('NEXT STEP'), findsOneWidget);
        expect(find.text('Team to submit the required files.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(Scaffold),
          'team-status-$width-$dark',
          viewport: true,
        );
      });
    }
  }

  testWidgets('group, exact-status and search filters agree with rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(workspace());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('team-status-group-followUp')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BSIT-3A'));
    await tester.pumpAndSettle();
    expect(find.text('Demo team'), findsNothing);
    expect(find.text('Post-defense team'), findsOneWidget);
    expect(find.text('Requirements team'), findsNothing);
    await tester.tap(find.text('All statuses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Awaiting requirements').last);
    await tester.pumpAndSettle();
    expect(find.text('Requirements team'), findsOneWidget);
    expect(find.text('Demo team'), findsNothing);
    await tester.enterText(find.byType(EditableText).first, 'Project 5');
    await tester.pumpAndSettle();
    expect(find.text('No matching teams'), findsOneWidget);
    expect(count('all', 1), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(count('all', 7), findsOneWidget);
    expect(find.text('No matching teams'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing stage resets filters and keeps completion scoped', (
    tester,
  ) async {
    await tester.pumpWidget(workspace());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('team-status-group-completed')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(workspace(selectedStage: 'Final Defense'));
    await tester.pumpAndSettle();
    expect(count('completed', 0), findsOneWidget);
    expect(find.text('No matching teams'), findsNothing);
    await tester.tap(find.text('BSIT-3A'));
    await tester.pumpAndSettle();
    expect(find.text('Completed team'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
