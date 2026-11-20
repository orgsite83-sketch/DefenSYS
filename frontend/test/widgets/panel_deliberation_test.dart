import 'dart:convert';

import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/grading/panel_deliberation_panel.dart';
import 'package:defensys/widgets/defense/re_demo_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _Client extends Mock implements AuthenticatedHttpClient {}

Map<String, dynamic> grade({bool chair = true, bool concept = false}) => {
  'id': 1,
  'schedule_id': 10,
  'updated_at': '2026-11-20T10:00:00Z',
  'workflow': {
    'deliberation': {
      'enabled': true,
      'can_confirm': chair,
      'revision_areas': concept
          ? [
              {'id': 'concept', 'label': 'Concept', 'allows_demo': false},
            ]
          : [
              {'id': 'system', 'label': 'System', 'allows_demo': true},
              {'id': 'manuscript', 'label': 'Manuscript', 'allows_demo': false},
            ],
    },
    'outcome_rule': {
      'panel_complete': true,
      'outcome': 'approved',
      'qualifying_score': 75,
      'allowed_verdicts': [
        'approved',
        'approved_with_revisions',
        'for_redefense',
      ],
      'review_token': 'reviewed-assessment',
      'per_concept': concept,
      'assessments': [
        {'key': 'c1', 'title': 'Inventory concept', 'qualifies': true},
      ],
    },
  },
};

Widget host(Map<String, dynamic> data, {bool chair = true}) =>
    SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: PanelDeliberationPanel(grade: data, isChair: chair),
      ),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
  });

  testWidgets(
    'ordinary members see the decision notice without verdict controls',
    (tester) async {
      await pumpDefensysWidget(tester, host(grade(chair: false), chair: false));
      expect(find.byType(ShadRadioGroup<String>), findsNothing);
      expect(find.text('Confirm panel decision'), findsNothing);
      expect(find.textContaining('in-person deliberation'), findsOneWidget);
    },
  );

  testWidgets(
    'concept configuration supplies one applicable area and a qualifying choice',
    (tester) async {
      await pumpDefensysWidget(tester, host(grade(concept: true)));
      expect(find.text('Concept'), findsOneWidget);
      expect(find.text('System'), findsNothing);
      expect(find.text('Manuscript'), findsNothing);
      expect(find.text('Inventory concept'), findsOneWidget);
      expect(find.text('Re-demo required'), findsNothing);
    },
  );

  testWidgets(
    'panel-directed re-defense sends honest decision metadata through one confirmation',
    (tester) async {
      final client = _Client();
      Map? sent;
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((call) async {
        sent = jsonDecode(call.namedArguments[#body] as String) as Map;
        expect(
          (call.positionalArguments.single as Uri).path,
          endsWith('/panel-decision/'),
        );
        return http.Response(jsonEncode({'grade': grade()}), 200);
      });
      await pumpDefensysWidget(
        tester,
        host(grade()),
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      await tester.tap(find.text('For Re-defense'));
      await tester.pumpAndSettle();
      expect(
        find.text('Reason for re-defense despite the qualifying score'),
        findsOneWidget,
      );
      final inputs = find.byType(ShadInput);
      await tester.enterText(
        inputs.at(0),
        'Panel requires a complete demonstration.',
      );
      await tester.enterText(
        inputs.at(1),
        'Complete the missing workflow before re-defense.',
      );
      await tester.ensureVisible(find.text('Confirm panel decision'));
      await tester.tap(find.text('Confirm panel decision'));
      await tester.pumpAndSettle();
      expect(sent?['verdict'], 'for_redefense');
      expect(sent?['review_token'], 'reviewed-assessment');
      expect(sent?.containsKey('panel_score'), false);
      expect(sent?['re_demo_required'], false);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final dark in [false, true]) {
      testWidgets('chair form remains readable at $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await loadPreviewFonts(force: true);
        await pumpDefensysWidget(
          tester,
          host(grade()),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        );
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(Scaffold),
          'panel-decision-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
      });
    }
  }

  testWidgets(
    're-demo verification records requirement results without a grading form',
    (tester) async {
      final client = _Client();
      final appointment = {
        'id': 7,
        'source_schedule_id': 10,
        'team_name': 'Team Inventory',
        'stage_label': 'Final Defense',
        'scheduled_date': '2026-11-20',
        'start_time': '10:00',
        'room': 'Lab 1',
        'chair_name': 'Panel Chair',
        'status': 'scheduled',
        'operation_state': 'normal',
        'verification_result': 'pending',
        'can_verify': true,
        'review_token': 'demo-review',
        'outcome': {'verdict': 'approved_with_revisions'},
        'requirements': [
          {'id': 'export', 'text': 'Demonstrate report export.'},
        ],
        'results': [],
      };
      when(() => client.get(any())).thenAnswer(
        (_) async => http.Response(
          jsonEncode({
            'appointments': [appointment],
            'eligible': [],
            'panelist_options': [],
            'can_manage': false,
            'total': 1,
          }),
          200,
        ),
      );
      Map? sent;
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((call) async {
        sent = jsonDecode(call.namedArguments[#body] as String) as Map;
        expect(
          (call.positionalArguments.single as Uri).path,
          endsWith('/7/verify/'),
        );
        return http.Response(jsonEncode({'appointment': appointment}), 200);
      });
      await pumpDefensysWidget(
        tester,
        const ReDemoWorkspaceScreen(),
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      await tester.tap(find.text('Open verification'));
      await tester.pumpAndSettle();
      expect(find.text('Demonstrate report export.'), findsOneWidget);
      expect(find.text('Submit grades'), findsNothing);
      await tester.tap(find.text('Not checked'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Satisfied').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm verification'));
      await tester.pumpAndSettle();
      expect(sent?['results'], [
        {'requirement_id': 'export', 'status': 'satisfied'},
      ]);
      expect(sent?.keys, isNot(contains('verdict')));
      expect(sent?.keys, isNot(contains('scores')));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );
}
