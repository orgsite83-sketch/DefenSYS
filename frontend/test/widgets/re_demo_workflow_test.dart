import 'dart:convert';

import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/defense/re_demo_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _Client extends Mock implements AuthenticatedHttpClient {}

Map<String, dynamic> appointment({bool chair = true}) => {
  'id': 7,
  'source_schedule_id': 10,
  'team_name': 'Team Inventory',
  'stage_label': 'Final Defense',
  'scheduled_date': '2026-11-20',
  'start_time': '10:00',
  'room': 'IT Laboratory',
  'chair_id': 3,
  'chair_name': 'Panel Chair',
  'status': 'scheduled',
  'operation_state': 'normal',
  'verification_result': 'pending',
  'can_verify': chair,
  'review_token': 'review',
  'outcome': {
    'verdict': 'approved_with_revisions',
    'instructions': 'Demonstrate the corrected access restrictions.',
  },
  'requirements': [
    {'id': 'access', 'text': 'Demonstrate role access restrictions.'},
  ],
  'results': [],
};

void _mockList(_Client client, Map<String, dynamic> payload) {
  when(
    () => client.get(any()),
  ).thenAnswer((_) async => http.Response(jsonEncode(payload), 200));
}

void main() {
  setUpAll(() => registerFallbackValue(Uri()));

  testWidgets('admin can schedule a team directly without adviser approval', (
    tester,
  ) async {
    final client = _Client();
    final source = {
      'outcome_id': 4,
      'source_revision': 1,
      'source_schedule_id': 10,
      'team_name': 'Team Inventory',
      'stage_label': 'Final Defense',
      'room': 'IT Laboratory',
      'chair_id': 3,
      'panelist_ids': [3],
      'requirements': [
        {'id': 'access', 'text': 'Demonstrate role access restrictions.'},
      ],
    };
    _mockList(client, {
      'appointments': [],
      'eligible': [source],
      'total': 0,
      'can_manage': true,
      'panelist_options': [
        {'id': 3, 'name': 'Panel Chair'},
      ],
    });
    Map? sent;
    when(
      () => client.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((call) async {
      sent = jsonDecode(call.namedArguments[#body] as String) as Map;
      _mockList(client, {
        'appointments': [appointment()],
        'eligible': [],
        'total': 1,
        'can_manage': true,
      });
      return http.Response(jsonEncode({'appointment': appointment()}), 201);
    });
    await pumpDefensysWidget(
      tester,
      const ReDemoWorkspaceScreen(sourceScheduleId: 10, scheduleNow: true),
      overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
    );
    expect(find.textContaining('No new adviser approval'), findsOneWidget);
    expect(
      find.textContaining('Demonstrate role access restrictions.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Confirm appointment'));
    await tester.pumpAndSettle();
    expect(sent?['outcome_id'], 4);
    expect(sent?['source_revision'], 1);
    expect(sent?['panelist_ids'], [3]);
    expect(sent?['chair_id'], 3);
    expect(sent?.containsKey('adviser_approved'), false);
    expect(find.text('Re-demo schedule & history'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('chair checks every feature and explains remaining corrections', (
    tester,
  ) async {
    final client = _Client();
    _mockList(client, {
      'appointments': [appointment()],
      'eligible': [],
      'total': 1,
    });
    Map? sent;
    when(
      () => client.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((call) async {
      sent = jsonDecode(call.namedArguments[#body] as String) as Map;
      return http.Response(jsonEncode({'appointment': appointment()}), 200);
    });
    await pumpDefensysWidget(
      tester,
      const ReDemoWorkspaceScreen(sourceScheduleId: 10),
      overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
    );
    await tester.tap(find.text('Open verification'));
    await tester.pumpAndSettle();
    ShadButton confirm() => tester.widget<ShadButton>(
      find.widgetWithText(ShadButton, 'Confirm verification'),
    );
    expect(confirm().enabled, false);
    expect(find.text('0/1 checked · 0 satisfied'), findsOneWidget);
    await tester.tap(find.text('Not checked'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Needs work').last);
    await tester.pumpAndSettle();
    expect(confirm().enabled, false);
    expect(find.text('1/1 checked · 0 satisfied'), findsOneWidget);
    await tester.enterText(
      find.byType(ShadInput),
      'A student can still open the admin report.',
    );
    await tester.pumpAndSettle();
    expect(confirm().enabled, true);
    await tester.tap(find.text('Confirm verification'));
    await tester.pumpAndSettle();
    expect(sent?['results'], [
      {'requirement_id': 'access', 'status': 'needs_work'},
    ]);
    expect(sent?['remarks'], 'A student can still open the admin report.');
    expect(sent?.keys, isNot(contains('scores')));
    expect(sent?.keys, isNot(contains('verdict')));
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
    'ordinary panel members see requirements without verification controls',
    (tester) async {
      final client = _Client();
      _mockList(client, {
        'appointments': [appointment(chair: false)],
        'eligible': [],
        'total': 1,
      });
      await pumpDefensysWidget(
        tester,
        const ReDemoWorkspaceScreen(),
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      await tester.tap(find.text('View record'));
      await tester.pumpAndSettle();
      expect(
        find.text('Demonstrate role access restrictions.'),
        findsOneWidget,
      );
      expect(find.text('Confirm verification'), findsNothing);
      expect(find.byType(ShadSelect<String>), findsNothing);
      expect(find.byType(ShadInput), findsNothing);
    },
  );

  testWidgets('empty and failed loads explain the actual state', (
    tester,
  ) async {
    final client = _Client();
    _mockList(client, {
      'appointments': [],
      'eligible': [],
      'total': 0,
      'can_manage': true,
    });
    await pumpDefensysWidget(
      tester,
      const ReDemoWorkspaceScreen(),
      overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
    );
    expect(find.text('No re-demo required'), findsOneWidget);
    expect(
      find.textContaining('directly from their defense status'),
      findsOneWidget,
    );
    when(() => client.get(any())).thenAnswer(
      (_) async =>
          http.Response(jsonEncode({'detail': 'Connection failed.'}), 500),
    );
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No re-demo required'), findsNothing);
  });

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final dark in [false, true]) {
      testWidgets('re-demo checklist fits $width dark=$dark', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts(force: true);
        final client = _Client();
        _mockList(client, {
          'appointments': [appointment()],
          'eligible': [],
          'total': 1,
        });
        await pumpDefensysWidget(
          tester,
          const ReDemoWorkspaceScreen(),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          overrides: [
            authenticatedHttpClientProvider.overrideWithValue(client),
          ],
        );
        await tester.tap(find.text('Open verification'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(Scaffold).first,
          're-demo-checklist-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
      });
    }
  }
}
