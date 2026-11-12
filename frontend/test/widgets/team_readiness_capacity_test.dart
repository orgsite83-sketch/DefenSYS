import 'package:defensys/screens/web/admin/defense_scheduler/components/team_readiness_tracker.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';

Future<void> pumpReadiness(WidgetTester tester, List<Map<String, dynamic>> teams, {bool dark = false}) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts();
  await tester.pumpWidget(ProviderScope(
    overrides: authTestOverrides(),
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.mistDarkTheme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(body: SingleChildScrollView(
        key: const PageStorageKey('defense-operations-scroll'),
        child: TeamReadinessTracker(
          state: DefenseSchedulerState(teams: teams),
          scope: 'capstone',
          activeStageOrEventName: 'Project Proposal',
          onReviewTeamDeliverables: (_, _) {},
          onSendReminder: (_, _) {},
          isSendingReminder: false,
        ),
      )),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('BSIT-3A'));
  await tester.pumpAndSettle();
}

Map<String, dynamic> team(int id, {Map<String, dynamic>? capacity}) => {
  'id': id, 'name': 'Team $id', 'level': '3rd Year Capstone',
  'section': 'BSIT-3A', 'adviser': id, 'adviser_name': 'Same Name',
  if (capacity != null) 'adviser_capacity': capacity,
};

void main() {
  for (final dark in [false, true]) {
    for (final approved in [false, true]) {
      testWidgets('readiness uses canonical ${approved ? 'approved' : 'standard'} limit (dark: $dark)', (tester) async {
        await pumpReadiness(tester, [team(1, capacity: {
          'active_count': 5, 'effective_limit': approved ? 5 : 4,
          'has_exception': approved, 'is_overloaded': !approved,
        })], dark: dark);
        // Only one team is displayed. The workload still includes all five.
        expect(find.text(approved ? '(5/5)' : '(5/4)'), findsOneWidget);
        expect(find.text(approved ? '5/5 teams' : '5/4 teams'), findsOneWidget);
        // One icon belongs to section readiness; only actual overload adds one.
        expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(approved ? 1 : 2));
        await capturePreview(tester, find.byType(Scaffold), 'readiness-capacity-$approved-$dark', viewport: true);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('missing capacity does not invent a four-team limit', (tester) async {
    await pumpReadiness(tester, [team(1)]);
    expect(find.text('Adviser: Same Name'), findsOneWidget);
    expect(find.textContaining('/4'), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old batch row cannot replace current adviser capacity', (tester) async {
    await pumpReadiness(tester, [team(1, capacity: {
      'active_count': 5, 'effective_limit': 4,
      'has_exception': false, 'is_overloaded': true,
      'operating_capacity': {
        'active_count': 5, 'effective_limit': 6,
        'has_exception': true, 'is_overloaded': false,
      },
    })]);
    expect(find.text('(5/6)'), findsOneWidget);
    expect(find.text('5/4 teams'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adviser filters distinguish identical display names', (tester) async {
    await pumpReadiness(tester, [
      team(1, capacity: {'active_count': 5, 'effective_limit': 5, 'is_overloaded': false}),
      team(2, capacity: {'active_count': 3, 'effective_limit': 4, 'is_overloaded': false}),
    ]);
    expect(find.text('Same Name'), findsNWidgets(2));
    await tester.tap(find.text('Same Name').first);
    await tester.pumpAndSettle();
    expect(find.text('Team 1'), findsOneWidget);
    expect(find.text('Team 2'), findsNothing);
    expect(find.text('5/5 teams'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Team 1'), findsOneWidget);
    expect(find.text('Team 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
