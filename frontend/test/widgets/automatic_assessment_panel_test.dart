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

Map<String, dynamic> _sharedRepeat({
  bool recorded = false,
  bool canDecide = true,
}) {
  final grade =
      jsonDecode(jsonEncode(_grade(verdict: 'for_redefense')))
          as Map<String, dynamic>;
  final workflow = grade['workflow'] as Map;
  workflow['redefense_direction'] = {
    'source_round_id': 21,
    'next_round_id': 22,
    'direction': recorded ? 'independent' : '',
    'decided_by': recorded ? 'Chair Rivera' : '',
    'can_decide': canDecide && !recorded,
    'review_token': 'preparation-token',
    'impact': {
      'team': 'Team ThreadAtlas',
      'shared_system': 'HABI: Artisan Heritage & Craft Exchange Platform',
      'module': 'Inventory Management',
      'next_attempt': 2,
      'saved_titles': 1,
      'saved_files': 1,
      'remaining_teams': ['Team Weave'],
    },
  };
  workflow['concept_workflow'] = <String, dynamic>{
    ...workflow['concept_workflow'] as Map,
    'selection_mode': 'shared_module',
    'section_selected_key': 'c2',
  };
  return grade;
}

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  for (final width in [320.0, 390.0, 768.0, 1100.0]) {
    for (final dark in [false, true]) {
      testWidgets('shared next-attempt choices fit $width dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            child: AutomaticAssessmentPanel(
              grade: _sharedRepeat(),
              isChair: true,
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
        );
        await tester.ensureVisible(find.text('Confirm next attempt'));
        expect(find.text('Decision'), findsOneWidget);
        expect(find.text('Save recommendations'), findsNothing);
        expect(
          tester.getTopLeft(find.text('Panel recommendations')).dy,
          lessThan(tester.getTopLeft(find.byType(ShadInput)).dy),
        );
        expect(
          tester.getBottomLeft(find.byType(ShadInput)).dy,
          lessThan(tester.getTopLeft(find.text('Confirm next attempt')).dy),
        );
        expect(find.byType(ShadRadio<String>), findsNWidgets(2));
        expect(find.text('Improve the selected shared module'), findsOneWidget);
        expect(find.text('Propose three independent concepts'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byType(AutomaticAssessmentPanel),
          'shared-next-attempt-${width.toInt()}-${dark ? 'dark' : 'light'}',
          viewport: true,
        );
      });
    }
  }

  testWidgets(
    'chair confirms direction and recommendations together in one request',
    (tester) async {
      registerFallbackValue(Uri.parse('http://localhost'));
      final client = _HttpClient();
      Map<String, dynamic>? sent;
      when(() => client.post(any(), body: any(named: 'body'))).thenAnswer((
        invocation,
      ) async {
        sent =
            jsonDecode(invocation.namedArguments[#body] as String)
                as Map<String, dynamic>;
        final saved = _sharedRepeat(recorded: true);
        saved['verdict_remarks'] = sent!['recommendations'];
        return http.Response(jsonEncode({'grade': saved}), 200);
      });
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: AutomaticAssessmentPanel(
            grade: _sharedRepeat(),
            isChair: true,
          ),
        ),
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      await tester.enterText(
        find.byType(ShadInput),
        'Feedback for the next attempt',
      );
      await tester.ensureVisible(
        find.text('Propose three independent concepts'),
      );
      await tester.tap(find.text('Propose three independent concepts'));
      await tester.pump();
      await tester.ensureVisible(find.text('Confirm next attempt'));
      await tester.tap(find.text('Confirm next attempt'));
      await tester.pumpAndSettle();
      expect(sent, isNull);
      expect(
        find.textContaining('Team ThreadAtlas · Re-defense required'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Remaining shared teams: Team Weave'),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Confirm next attempt'),
      );
      await tester.pumpAndSettle();
      expect(sent, {
        'action': 'redefense_direction',
        'direction': 'independent',
        'source_round_id': 21,
        'review_token': 'preparation-token',
        'recommendations': 'Feedback for the next attempt',
      });
      verify(() => client.post(any(), body: any(named: 'body'))).called(1);
      expect(find.text('Confirmed by Chair Rivera'), findsOneWidget);
      expect(find.text('Confirm next attempt'), findsNothing);
      expect(
        tester.widget<ShadInput>(find.byType(ShadInput)).controller?.text,
        'Feedback for the next attempt',
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('confirmation uses the preparation token the chair reviewed', (
    tester,
  ) async {
    registerFallbackValue(Uri.parse('http://localhost'));
    final client = _HttpClient();
    Map<String, dynamic>? sent;
    when(() => client.post(any(), body: any(named: 'body'))).thenAnswer((
      invocation,
    ) async {
      sent =
          jsonDecode(invocation.namedArguments[#body] as String)
              as Map<String, dynamic>;
      return http.Response(
        '{"detail":"Preparation changed. Refresh and review again."}',
        400,
      );
    });
    final current = ValueNotifier(_sharedRepeat());
    addTearDown(current.dispose);
    await pumpDefensysWidget(
      tester,
      ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: current,
        builder: (context, grade, _) => SingleChildScrollView(
          child: AutomaticAssessmentPanel(grade: grade, isChair: true),
        ),
      ),
      overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
    );
    await tester.ensureVisible(find.text('Confirm next attempt'));
    await tester.enterText(
      find.byType(ShadInput),
      'Keep this draft after a failed save.',
    );
    await tester.tap(find.text('Confirm next attempt'));
    await tester.pumpAndSettle();
    final changed = _sharedRepeat();
    changed['workflow']['redefense_direction']['review_token'] =
        'changed-preparation';
    current.value = changed;
    await tester.pump();
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Confirm next attempt'),
    );
    await tester.pumpAndSettle();
    expect(sent?['review_token'], 'preparation-token');
    expect(sent?['recommendations'], 'Keep this draft after a failed save.');
    expect(
      tester.widget<ShadInput>(find.byType(ShadInput)).controller?.text,
      'Keep this draft after a failed save.',
    );
    expect(find.text('Confirmed by Chair Rivera'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared next-attempt choices wrap with enlarged text', (
    tester,
  ) async {
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
            child: AutomaticAssessmentPanel(
              grade: _sharedRepeat(),
              isChair: true,
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Confirm next attempt'));
    expect(tester.takeException(), isNull);
    expect(find.text('Save recommendations'), findsNothing);
  });

  testWidgets('nonchair and ineligible attempts cannot confirm a route', (
    tester,
  ) async {
    for (final chair in [false, true]) {
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: AutomaticAssessmentPanel(
            grade: _sharedRepeat(canDecide: false),
            isChair: chair,
          ),
        ),
      );
      if (chair) {
        expect(find.text('Confirm next attempt'), findsNothing);
        expect(find.text('Save recommendations'), findsOneWidget);
        expect(
          tester
              .widget<ShadRadioGroup<String>>(
                find.byType(ShadRadioGroup<String>),
              )
              .enabled,
          isFalse,
        );
      } else {
        expect(find.text('Confirm next attempt'), findsNothing);
        expect(find.byType(ShadRadio<String>), findsNothing);
      }
    }
  });

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
          expect(find.text('Save recommendations'), findsNothing);
          expect(
            tester.getBottomLeft(find.byType(ShadInput)).dy,
            lessThan(
              tester.getTopLeft(find.text('Confirm concept selection')).dy,
            ),
          );
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
      expect(find.text('Save recommendations'), findsNothing);
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
    'chair selection submits concept identity, recommendations and current token',
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
      await tester.enterText(
        find.byType(ShadInput),
        'Strengthen the prototype evidence.',
      );
      await tester.ensureVisible(find.text('Confirm concept selection'));
      await tester.tap(find.text('Confirm concept selection'));
      await tester.pumpAndSettle();
      expect(sent, {
        'action': 'select_concept',
        'concept_key': 'c2',
        'review_token': 'current-assessment',
        'recommendations': 'Strengthen the prototype evidence.',
      });
      verify(() => client.post(any(), body: any(named: 'body'))).called(1);
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
