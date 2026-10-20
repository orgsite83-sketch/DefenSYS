import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/concept_workspace.dart';
import 'package:defensys/widgets/repository/shared_concept_review.dart';
import 'package:defensys/widgets/repository/document_policy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _ConceptActions extends CapstoneDeliverablesNotifier {
  Map<String, dynamic>? saved;
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
      'action': action,
      'concepts': concepts,
      'review_token': reviewToken,
    };
    return true;
  }
}

Map<String, dynamic> sharedWorkflow({
  bool selected = true,
  bool editable = false,
}) => {
  'enabled': true,
  'selection_mode': 'shared_module',
  'decision_scope': 'pit',
  'section_project_id': 42,
  'section_selected_key': selected ? 'c2' : '',
  'can_manage_decision': true,
  'can_record_decision': true,
  'can_edit': editable,
  'can_edit_titles': editable,
  'module_review_token': 'current-module-names',
  'round': 1,
  'status': 'scheduled',
  'history': <dynamic>[],
  'concepts': [
    for (var i = 1; i <= 3; i++)
      {
        'key': 'c$i',
        'title': 'Module proposal $i',
        'system_title': 'Section system $i',
        'section_selected': selected && i == 2,
        'decision': '',
        'faculty_confirmed': true,
      },
  ],
};

Map<String, dynamic> sharedProject({bool selected = true}) => {
  'scope': 'pit',
  'section': 'BSIT-3A',
  'stage_label': 'System Concept Pitching',
  'selected_key': selected ? 'c2' : '',
  'systems': [
    for (var i = 1; i <= 3; i++) {'key': 'c$i', 'title': 'Section system $i'},
  ],
  'teams': [
    for (var i = 1; i <= 3; i++)
      {
        'id': i,
        'name': ['AgriPulse', 'CropLink', 'FieldLedger'][i - 1],
        'leader_name': ['Joaquin Panganiban', 'Ana Cruz', 'Paolo Reyes'][i - 1],
        'schedule_id': i * 10,
        'can_record_decision': i == 2,
        'can_clear_concept_revisions': i == 3,
        'module_review_status': i == 1
            ? 'approved'
            : i == 3
            ? 'revisions_pending'
            : 'awaiting_review',
        'concepts': [
          for (var j = 1; j <= 3; j++)
            {
              'key': 'c$j',
              'title': j == 2
                  ? [
                      'Soil monitoring',
                      'Crop health analytics',
                      'Grower reporting',
                    ][i - 1]
                  : 'Alternative $j for team $i',
              'system_title': 'Section system $j',
              'documents_status': i == 3 && j == 2
                  ? 'corrections_requested'
                  : 'accepted',
            },
        ],
      },
  ],
};

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  testWidgets(
    'shared team waits for one section decision without a generic chooser',
    (tester) async {
      int? opened;
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: ConceptWorkspace(
            teamId: 5,
            stageLabel: 'System Concept Pitching',
            stage: {'concept_workflow': sharedWorkflow(selected: false)},
            onOpenSharedReview: (id) => opened = id,
          ),
        ),
        overrides: authTestOverrides(),
      );
      expect(find.byType(PitConceptDecisionPanel), findsNothing);
      expect(find.byType(ConceptVerdictFields), findsNothing);
      expect(
        find.textContaining('selected once for all participating teams'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open section systems'));
      expect(opened, 42);
    },
  );

  for (final pit in [true, false]) {
    testWidgets(
      'selected shared ${pit ? 'PIT' : 'Capstone'} team shows only its linked module',
      (tester) async {
        final workflow = sharedWorkflow();
        if (!pit) workflow.remove('decision_scope');
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            child: ConceptWorkspace(
              teamId: 5,
              stageLabel: 'System Concept Pitching',
              stage: {'concept_workflow': workflow},
              onOpenSharedReview: (_) {},
            ),
          ),
          overrides: authTestOverrides(),
        );
        expect(find.text('Section system 2'), findsOneWidget);
        expect(find.text('Module proposal 2'), findsOneWidget);
        expect(find.text('Module proposal 1'), findsNothing);
        expect(find.text('Module proposal 3'), findsNothing);
        expect(find.byType(ConceptVerdictFields), findsNothing);
        expect(find.text('Save concept decision'), findsNothing);
        expect(find.text('Open module reviews'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'module name review edits only the linked proposal and preserves other names',
    (tester) async {
      final notifier = _ConceptActions();
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: ConceptWorkspace(
            teamId: 5,
            stageLabel: 'System Concept Pitching',
            stage: {'concept_workflow': sharedWorkflow(editable: true)},
            onOpenSharedReview: (_) {},
          ),
        ),
        overrides: [
          ...authTestOverrides(),
          capstoneDeliverablesProvider.overrideWith(() => notifier),
        ],
      );
      await tester.ensureVisible(find.text('Review & confirm modules'));
      await tester.tap(find.text('Review & confirm modules'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField),
        'Revised linked module',
      );
      await tester.tap(find.text('Confirm module names & connections'));
      await tester.pumpAndSettle();
      final saved = notifier.saved?['concepts'] as List;
      expect(saved[0]['title'], 'Module proposal 1');
      expect(saved[1]['title'], 'Revised linked module');
      expect(saved[2]['title'], 'Module proposal 3');
    },
  );

  testWidgets(
    'shared Capstone fields review one module and normalize unrelated choices',
    (tester) async {
      List<Map<String, dynamic>>? saved;
      final proposals = conceptRows(sharedWorkflow()['concepts']);
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConceptVerdictFields(
              concepts: proposals,
              onChanged: (value) => saved = value,
            ),
          ),
        ),
      );
      expect(find.text('Linked module review'), findsOneWidget);
      expect(find.textContaining('Module proposal 1'), findsNothing);
      expect(find.byType(WorkflowChoice), findsOneWidget);
      await tester.tap(find.text('Choose module outcome'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approved module').last);
      await tester.pumpAndSettle();
      expect(saved!.map((c) => c['decision']), [
        'not_selected',
        'approved',
        'not_selected',
      ]);
      expect(conceptDecisionError(saved!, 'approved'), isNull);
    },
  );

  testWidgets('shared module fields wait for the section selection', (
    tester,
  ) async {
    await pumpDefensysWidget(
      tester,
      ConceptVerdictFields(
        concepts: conceptRows(sharedWorkflow(selected: false)['concepts']),
        onChanged: (_) {},
      ),
    );
    expect(find.byType(WorkflowChoice), findsNothing);
    expect(find.textContaining('Select the section system'), findsOneWidget);
  });

  testWidgets(
    'review table keeps module and clearance actions attached to their team',
    (tester) async {
      int? reviewed;
      int? cleared;
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: SharedModuleReviewTable(
            project: sharedProject(),
            onReview: (team) => reviewed = team['id'] as int,
            onConfirmNames: (_) {},
            onClearRevisions: (team) => cleared = team['id'] as int,
          ),
        ),
      );
      expect(find.text('Alternative 1 for team 1'), findsNothing);
      await tester.ensureVisible(find.text('Review module'));
      await tester.tap(find.text('Review module'));
      expect(reviewed, 2);
      await tester.ensureVisible(find.text('Clear module revisions'));
      await tester.tap(find.text('Clear module revisions'));
      expect(cleared, 3);
    },
  );

  testWidgets(
    'shared proposals have no module review action before system selection',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: SharedModuleReviewTable(
            project: sharedProject(selected: false),
            onReview: (_) => fail('No section system was selected'),
            onConfirmNames: (_) {},
            onClearRevisions: (_) => fail('No selected module can be cleared'),
          ),
        ),
      );
      expect(find.text('Review module'), findsNothing);
      expect(find.text('Clear module revisions'), findsNothing);
      expect(find.text('Waiting for section selection'), findsNWidgets(3));
    },
  );

  for (final width in [390.0, 1100.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'shared selection and module reviews fit $width ${dark ? 'dark' : 'light'}',
        (tester) async {
          tester.view.physicalSize = Size(width, 1400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final theme = dark ? AppTheme.mistDarkTheme : AppTheme.theme;
          final project = sharedProject();
          await pumpDefensysWidget(
            tester,
            RepaintBoundary(
              key: const ValueKey('shared-selection-preview'),
              child: ColoredBox(
                color: theme.scaffoldBackgroundColor,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Section system review',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text('BSIT-3A · System Concept Pitching'),
                      const SizedBox(height: 24),
                      SharedSystemSelectionBanner(project: project),
                      const SizedBox(height: 24),
                      SharedModuleReviewTable(
                        project: project,
                        onReview: (_) {},
                        onConfirmNames: (_) {},
                        onClearRevisions: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
            theme: theme,
          );
          await capturePreview(
            tester,
            find.byKey(const ValueKey('shared-selection-preview')),
            'shared-selection-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
