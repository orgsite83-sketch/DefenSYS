import 'dart:convert';

import 'package:defensys/screens/web/admin/grade_center/stage_failure_closure_dialog.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/grading/automatic_assessment_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _HttpClient extends Mock implements AuthenticatedHttpClient {}

Map<String, dynamic> _grade({
  bool complete = true,
  String verdict = '',
  bool single = false,
}) => {
  'id': 11,
  'status': 'pending',
  'verdict': verdict,
  'verdict_remarks': '',
  'outcome_metadata': {'source': 'automatic'},
  'workflow': {
    'outcome_rule': {
      'automatic': true,
      'panel_complete': complete,
      'per_concept': true,
      'outcome': complete
          ? (verdict == 'for_redefense' ? 'for_redefense' : 'approved')
          : 'pending',
      'qualifying_score': 75,
      'review_token': 'current-assessment',
      'assessments': [
        for (var i = 1; i <= 3; i++)
          {
            'key': 'c$i',
            'title': [
              'Soil Sensor and Dynamic Drip Irrigation',
              'Smart Campus Landscape Irrigation',
              'Floodwater and Drainage Monitoring',
            ][i - 1],
            'score': i == 3 || (single && i == 1) || verdict == 'for_redefense'
                ? 68
                : 82,
            'qualifies':
                complete &&
                i != 3 &&
                (!single || i == 2) &&
                verdict != 'for_redefense',
          },
      ],
    },
    'concept_workflow': {
      'hearing_concepts': [
        for (var i = 1; i <= 3; i++)
          {
            'key': 'c$i',
            'title': 'Proposal $i',
            'decision': verdict == 'approved' && i == 2 ? 'approved' : '',
          },
      ],
    },
  },
};

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  for (final width in [320.0, 390.0, 768.0, 1100.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'automatic outcome fits $width dark=$dark without manual verdict controls',
        (tester) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await pumpDefensysWidget(
            tester,
            SingleChildScrollView(
              child: RepaintBoundary(
                key: const ValueKey('automatic-panel-preview'),
                child: AutomaticAssessmentPanel(grade: _grade(), isChair: true),
              ),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
          );
          expect(find.text('Choose the official concept'), findsOneWidget);
          expect(find.text('Submit Verdict'), findsNothing);
          expect(find.text('Failed'), findsNothing);
          expect(find.text('Save recommendations'), findsOneWidget);
          final radios = tester
              .widgetList<Radio<String>>(find.byType(Radio<String>))
              .toList();
          expect(radios.length, 3);
          expect(radios.last.enabled, isFalse);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('automatic-panel-preview')),
            'automatic-panel-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
        },
      );
    }
  }

  testWidgets(
    'large text keeps concept choices and actions readable on a compact phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDefensysWidget(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: SingleChildScrollView(
              child: AutomaticAssessmentPanel(grade: _grade(), isChair: true),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Confirm concept selection'));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Save recommendations'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending evaluations display provisional scores without failure labels',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: AutomaticAssessmentPanel(
            grade: _grade(complete: false),
            isChair: true,
          ),
        ),
      );
      expect(find.text('Awaiting panel evaluations'), findsOneWidget);
      expect(find.text('Provisional'), findsNWidgets(3));
      expect(find.text('Below qualifying score'), findsNothing);
      expect(find.text('Confirm concept selection'), findsNothing);
    },
  );

  testWidgets(
    'chair selection submits only concept identity and current assessment token',
    (tester) async {
      Map<String, dynamic>? sent;
      registerFallbackValue(Uri.parse('http://localhost'));
      final client = _HttpClient();
      when(() => client.post(any(), body: any(named: 'body'))).thenAnswer((
        invocation,
      ) async {
        expect(
          (invocation.positionalArguments.first as Uri).path,
          '/api/grading/grades/11/assessment/',
        );
        sent =
            jsonDecode(invocation.namedArguments[#body] as String)
                as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'grade': _grade(single: true, verdict: 'approved')}),
          200,
        );
      });
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: AutomaticAssessmentPanel(grade: _grade(), isChair: true),
        ),
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.ensureVisible(find.text('Confirm concept selection'));
      await tester.tap(find.text('Confirm concept selection'));
      await tester.pumpAndSettle();
      expect(sent, {
        'action': 'select_concept',
        'concept_key': 'c2',
        'review_token': 'current-assessment',
      });
      expect(find.text('Official concept'), findsOneWidget);
      expect(find.text('Confirm concept selection'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'automatic re-defense does not require a verdict or next-action selectors',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: AutomaticAssessmentPanel(
            grade: _grade(verdict: 'for_redefense'),
            isChair: true,
          ),
        ),
      );
      expect(find.text('Re-defense required'), findsOneWidget);
      expect(find.byType(Radio<String>), findsNothing);
      expect(find.text('Save recommendations'), findsOneWidget);
      expect(find.text('Submit Verdict'), findsNothing);
    },
  );

  for (final width in [320.0, 390.0, 768.0, 1100.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'admin closure acknowledgement and confirmation fits $width dark=$dark',
        (tester) async {
          tester.view.physicalSize = Size(width, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          String? saved;
          await pumpDefensysWidget(
            tester,
            Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await showDialog<String>(
                    context: context,
                    builder: (_) => const StageFailureClosureDialog(
                      stageLabel: 'Concept Proposal',
                      teams: [
                        {'grade_id': 11, 'team_name': 'Team AgriPulse'},
                      ],
                    ),
                  );
                },
                child: const Text('Review closure'),
              ),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
          );
          await tester.tap(find.text('Review closure'));
          await tester.pumpAndSettle();
          await capturePreview(
            tester,
            find.byType(StageFailureClosureDialog),
            'automatic-closure-${width.toInt()}-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
          expect(saved, isNull);
          expect(
            tester
                .widget<ShadButton>(
                  find.ancestor(
                    of: find.text('Review final decision'),
                    matching: find.byType(ShadButton),
                  ),
                )
                .onPressed,
            isNull,
          );
          await tester.ensureVisible(find.byType(ShadCheckbox));
          await tester.tap(find.byType(ShadCheckbox));
          await tester.enterText(
            find.byType(ShadInput),
            'The authorized assessment window has closed.',
          );
          await tester.pump();
          await tester.ensureVisible(find.text('Review final decision'));
          await tester.tap(find.text('Review final decision'));
          await tester.pumpAndSettle();
          expect(saved, isNull);
          expect(find.text('Team AgriPulse'), findsOneWidget);
          await tester.ensureVisible(find.text('Complete stage'));
          await tester.tap(find.text('Complete stage'));
          await tester.pumpAndSettle();
          expect(saved, 'The authorized assessment window has closed.');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
