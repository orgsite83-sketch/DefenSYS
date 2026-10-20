import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/concept_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _Decisions extends CapstoneDeliverablesNotifier {
  Map<String, dynamic>? saved;
  bool succeeds = true;
  @override
  CapstoneDeliverablesState build() => const CapstoneDeliverablesState();
  @override
  Future<bool> conceptAction(
    int teamId,
    String stageLabel,
    String action, {
    List<Map<String, dynamic>>? concepts,
    String? reason,
    String? reviewToken,
  }) async {
    saved = {
      'team_id': teamId,
      'stage_label': stageLabel,
      'action': action,
      'concepts': concepts,
      'reason': reason,
      'review_token': reviewToken,
    };
    return succeeds;
  }
}

Map<String, dynamic> _workflow({
  bool ready = true,
  bool manager = true,
  bool recorded = false,
}) => {
  'decision_scope': 'pit',
  'round': 1,
  'decision_review_token': 'current-paper-versions',
  'can_manage_decision': manager,
  'can_record_decision': ready && manager && !recorded,
  'decision_unavailable_reason':
      'Every required panel evaluation must be submitted before choosing a concept.',
  'decision': recorded ? 'approved' : '',
  'selected_title': recorded ? 'AgriPulse soil monitoring' : '',
  'decided_by_name': recorded ? 'Florencia Dela Torre' : '',
  'concepts': [
    {'key': 'c1', 'title': 'AgriPulse soil monitoring', 'decision': 'approved'},
    {
      'key': 'c2',
      'title': 'Crop disease reporting',
      'decision': 'not_selected',
    },
    {
      'key': 'c3',
      'title': 'Community harvest exchange',
      'decision': 'not_selected',
    },
  ],
};

Future<void> _show(
  WidgetTester tester,
  Map<String, dynamic> workflow,
  _Decisions notifier, {
  bool dark = false,
}) => pumpDefensysWidget(
  tester,
  RepaintBoundary(
    key: const ValueKey('pit-concept-preview'),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Team Deliverables',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text('AgriPulse · System Concept Pitching'),
          const SizedBox(height: 24),
          PitConceptDecisionPanel(
            teamId: 8,
            stageLabel: 'System Concept Pitching',
            workflow: workflow,
          ),
        ],
      ),
    ),
  ),
  theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
  overrides: [
    ...authTestOverrides(),
    capstoneDeliverablesProvider.overrideWith(() => notifier),
  ],
);

void main() {
  setUpAll(loadPreviewFonts);

  testWidgets(
    'lead saves a concept decision with the reviewed token and no grade verdict',
    (tester) async {
      final notifier = _Decisions();
      await _show(tester, _workflow(), notifier);
      await tester.ensureVisible(find.text('Save concept decision'));
      await tester.tap(find.text('Save concept decision'));
      await tester.pumpAndSettle();
      expect(find.text('Save concept decision?'), findsOneWidget);
      await tester.tap(find.text('Save decision'));
      await tester.pumpAndSettle();
      expect(notifier.saved?['action'], 'pit_decision');
      expect(notifier.saved?['review_token'], 'current-paper-versions');
      expect(notifier.saved?.containsKey('verdict'), isFalse);
      expect(
        (notifier.saved?['concepts'] as List)
            .where((c) => c['decision'] == 'approved')
            .length,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending panel evaluations lock the lead decision', (
    tester,
  ) async {
    await _show(tester, _workflow(ready: false), _Decisions());
    final button = tester.widget<ShadButton>(
      find.widgetWithText(ShadButton, 'Save concept decision'),
    );
    expect(button.enabled, isFalse);
    expect(
      find.textContaining('Every required panel evaluation'),
      findsOneWidget,
    );
  });

  testWidgets(
    'other roles see the lead responsibility without editable decision fields',
    (tester) async {
      await _show(tester, _workflow(manager: false), _Decisions());
      expect(find.byType(ConceptVerdictFields), findsNothing);
      expect(find.text('Save concept decision'), findsNothing);
      expect(
        find.textContaining('The assigned PIT Lead records'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'recorded decision shows official title and the responsible lead',
    (tester) async {
      await _show(tester, _workflow(recorded: true), _Decisions());
      expect(find.text('AgriPulse soil monitoring'), findsOneWidget);
      expect(find.text('Recorded by Florencia Dela Torre'), findsOneWidget);
      expect(find.text('Save concept decision'), findsNothing);
    },
  );

  testWidgets(
    'server failure leaves the decision available with an inline error',
    (tester) async {
      final notifier = _Decisions()..succeeds = false;
      await _show(tester, _workflow(), notifier);
      await tester.ensureVisible(find.text('Save concept decision'));
      await tester.tap(find.text('Save concept decision'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save decision'));
      await tester.pumpAndSettle();
      expect(find.text('Could not save the concept decision.'), findsOneWidget);
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Save concept decision'),
            )
            .enabled,
        isTrue,
      );
    },
  );

  testWidgets('multiple selected concepts cannot reach confirmation', (
    tester,
  ) async {
    final workflow = _workflow();
    (workflow['concepts'] as List)[1]['decision'] = 'approved';
    final notifier = _Decisions();
    await _show(tester, workflow, notifier);
    await tester.ensureVisible(find.text('Save concept decision'));
    await tester.tap(find.text('Save concept decision'));
    await tester.pumpAndSettle();
    expect(find.text('Select exactly one concept.'), findsOneWidget);
    expect(notifier.saved, isNull);
  });

  testWidgets(
    'revision clearance needs fresh notes and uses the separate PIT action',
    (tester) async {
      final workflow = _workflow(recorded: true)
        ..['decision'] = 'approved_with_revisions'
        ..['decision_remarks'] = 'Clarify the module boundaries.'
        ..['can_clear_concept_revisions'] = true;
      final notifier = _Decisions();
      await _show(tester, workflow, notifier);
      await tester.ensureVisible(find.text('Clear concept revisions'));
      await tester.tap(find.text('Clear concept revisions'));
      await tester.pumpAndSettle();
      expect(notifier.saved, isNull);
      expect(
        find.textContaining('Describe the required changes'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(ShadInput),
        'Reviewed and accepted the revised concept paper.',
      );
      await tester.tap(find.text('Clear concept revisions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear revisions'));
      await tester.pumpAndSettle();
      expect(notifier.saved?['action'], 'clear_pit_revisions');
      expect(notifier.saved?['review_token'], 'current-paper-versions');
      expect(notifier.saved?['concepts'], isNull);
    },
  );

  for (final width in [390.0, 1100.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'concept selection fits $width in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
          tester.view.physicalSize = Size(width, 1400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await _show(tester, _workflow(), _Decisions(), dark: dark);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('pit-concept-preview')),
            'pit-concept-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
