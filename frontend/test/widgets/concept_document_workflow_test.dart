import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/widgets/repository/concept_workspace.dart';
import 'package:defensys/widgets/repository/document_group.dart';
import 'package:defensys/widgets/repository/document_policy_editor.dart';
import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/screens/web/shared/team_deliverables/deliverables_view_types.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _DocumentsNotifier extends CapstoneDeliverablesNotifier {
  Map<String, dynamic>? action;
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
    this.action = {
      'action': action,
      'concepts': concepts,
      'reason': reason,
      'review_token': reviewToken,
    };
    return true;
  }

  @override
  Future<bool> reviewDeliverable({
    required int teamId,
    required String stageLabel,
    required String deliverableId,
    required String status,
    String? feedback,
    bool clearDefenseRevisions = false,
    int? fileId,
  }) async {
    action = {'file_id': fileId, 'status': status, 'feedback': feedback};
    return true;
  }
}

Map<String, dynamic> _workflow() => {
  'enabled': true,
  'round': 2,
  'status': 'replacement_concepts_needed',
  'can_edit': true,
  'review_required': true,
  'clearance_valid': false,
  'next_step': 'Submit replacement concepts using the panel feedback.',
  'concepts': [
    for (var i = 1; i <= 3; i++) {'key': 'c$i', 'title': ''},
  ],
  'history': [],
};

Map<String, dynamic> _item() => {
  'id': 'CONCEPTS',
  'label': 'Concept papers',
  'type': 'pre',
  'required': true,
  'can_upload': true,
  'can_faculty_review': true,
  'file_policy': {'mode': 'concepts'},
  'document_slots': [
    for (var i = 1; i <= 3; i++)
      {'key': 'c$i:paper', 'label': 'Concept $i · Paper', 'required': true},
  ],
  'submission': {
    'files': [
      {
        'id': 11,
        'slot_key': 'c1:paper',
        'file_name': 'attendance.pdf',
        'revision': 1,
        'status': 'accepted',
      },
      {
        'id': 12,
        'slot_key': 'c2:paper',
        'file_name': 'inventory.pdf',
        'revision': 2,
        'status': 'pending',
      },
    ],
  },
};

void main() {
  testWidgets(
    'assigned project hides the duplicate review card and endorsement action',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        ConceptWorkspace(
          teamId: 8,
          stageLabel: 'Concept Proposal',
          stage: {
            'concept_workflow': {
              ..._workflow(),
              'assigned': true,
              'config': {
                'mode': 'assigned',
                'assigned_title': 'School assigned project',
              },
              'concepts': [
                {'key': 'c1', 'title': 'School assigned project'},
              ],
            },
          },
        ),
        overrides: authTestOverrides(),
      );
      expect(find.text('Assigned concept review'), findsNothing);
      expect(find.text('Endorse concept set'), findsNothing);
      expect(find.text('School assigned project'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'module task exposes editable confirmation independently of file acceptance',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final notifier = _DocumentsNotifier();
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: ConceptWorkspace(
            teamId: 8,
            stageLabel: 'Concept Proposal',
            stage: {
              'required_complete': false,
              'concept_workflow': {
                ..._workflow(),
                'section_project_id': 7,
                'module_review_token': 'current-module-version',
                'concepts': [
                  for (var i = 1; i <= 3; i++)
                    {
                      'key': 'c$i',
                      'title': 'Module $i',
                      'system_title': 'Shared system $i',
                      'faculty_confirmed': false,
                    },
                ],
              },
            },
          ),
        ),
        overrides: [
          ...authTestOverrides(),
          capstoneDeliverablesProvider.overrideWith(() => notifier),
        ],
      );
      expect(
        find.text('Module confirmation required · 0/3 confirmed'),
        findsOneWidget,
      );
      expect(find.text('Needs confirmation'), findsNWidgets(3));
      expect(find.text('Endorse concept set'), findsNothing);
      await tester.tap(find.text('Review & confirm modules'));
      await tester.pumpAndSettle();
      expect(find.text('System A · Shared system 1'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Revised module name',
      );
      await tester.tap(find.text('Confirm module names & connections'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(notifier.action?['action'], 'save_titles');
      expect(
        (notifier.action?['concepts'] as List).first['title'],
        'Revised module name',
      );
      expect(notifier.action?['review_token'], 'current-module-version');
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'confirmed module task has an edit action in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await loadPreviewFonts();
        await pumpDefensysWidget(
          tester,
          RepaintBoundary(
            key: const ValueKey('phase-one-modules'),
            child: SingleChildScrollView(
              child: ConceptWorkspace(
                teamId: 8,
                stageLabel: 'Concept Proposal',
                stage: {
                  'concept_workflow': {
                    ..._workflow(),
                    'section_project_id': 7,
                    'concepts': [
                      for (var i = 1; i <= 3; i++)
                        {
                          'key': 'c$i',
                          'title': 'Confirmed module $i',
                          'system_title': 'Shared system $i',
                          'faculty_confirmed': true,
                        },
                    ],
                  },
                },
              ),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          overrides: authTestOverrides(),
        );
        expect(
          find.text('Module names confirmed · 3/3 confirmed'),
          findsOneWidget,
        );
        expect(find.text('Edit module names'), findsOneWidget);
        expect(
          tester.getTopRight(find.text('Clearance exception')).dx,
          greaterThan(900),
        );
        expect(find.text('Endorse concept set'), findsNothing);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('phase-one-modules')),
          'phase-one-modules-${dark ? 'dark' : 'light'}',
        );
      },
    );
  }

  testWidgets(
    'concept settings use shadcn controls and preserve configuration',
    (tester) async {
      var config = <String, dynamic>{};
      await pumpDefensysWidget(
        tester,
        StatefulBuilder(
          builder: (_, setState) => SingleChildScrollView(
            child: ConceptSettings(
              value: config,
              onChanged: (value) => setState(() => config = value),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Concept selection'));
      await tester.pumpAndSettle();
      expect(config['enabled'], isTrue);
      expect(find.text('Adviser clearance before re-defense'), findsOneWidget);
      expect(find.text('Require fresh assessments'), findsOneWidget);
      expect(find.byType(ShadSelect<String>), findsNWidgets(3));
      await tester.tap(find.byType(ShadSelect<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom count…').last);
      await tester.pumpAndSettle();
      expect(config['required_count'], 4);
      await tester.tap(find.byTooltip('More concepts'));
      await tester.pumpAndSettle();
      expect(config['required_count'], 5);
      expect(find.text('5 concepts (custom)'), findsOneWidget);
      await tester.tap(find.byType(ShadSelect<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Not required unless the panel requests it').last,
      );
      await tester.pumpAndSettle();
      expect(config['review_policy'], 'panel_requested');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving replacement titles sends all concepts without assigning a project',
    (tester) async {
      final notifier = _DocumentsNotifier();
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: ConceptWorkspace(
            teamId: 8,
            stageLabel: 'Concept Proposal',
            stage: {
              'concept_workflow': _workflow(),
              'required_complete': false,
            },
          ),
        ),
        overrides: [
          ...authTestOverrides(),
          capstoneDeliverablesProvider.overrideWith(() => notifier),
        ],
      );
      final inputs = find.byType(EditableText);
      for (var i = 0; i < 3; i++) {
        await tester.enterText(inputs.at(i), 'Replacement project ${i + 1}');
      }
      await tester.tap(find.text('Save concept titles'));
      await tester.pumpAndSettle();
      expect(notifier.action?['action'], 'save_titles');
      expect((notifier.action?['concepts'] as List).length, 3);
      expect(notifier.action!.containsKey('project_title'), isFalse);
    },
  );

  testWidgets(
    'review targets one document and accepted sibling remains visible',
    (tester) async {
      final notifier = _DocumentsNotifier();
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: DocumentGroup(
            teamId: 8,
            stageLabel: 'Concept Proposal',
            item: _item(),
          ),
        ),
        overrides: [
          ...authTestOverrides(),
          capstoneDeliverablesProvider.overrideWith(() => notifier),
        ],
      );
      expect(find.text('Accepted for presentation'), findsOneWidget);
      expect(find.textContaining('Missing'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(notifier.action, containsPair('file_id', 12));
      expect(notifier.action, containsPair('status', 'accepted'));
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'concept workspace fits narrow ${dark ? 'dark' : 'light'} surfaces',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await loadPreviewFonts();
        await pumpDefensysWidget(
          tester,
          RepaintBoundary(
            key: const ValueKey('concept-preview'),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ConceptWorkspace(
                    teamId: 8,
                    stageLabel: 'Concept Proposal',
                    stage: {'concept_workflow': _workflow()},
                  ),
                  DocumentGroup(
                    teamId: 8,
                    stageLabel: 'Concept Proposal',
                    item: _item(),
                  ),
                ],
              ),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          overrides: [
            ...authTestOverrides(),
            capstoneDeliverablesProvider.overrideWith(_DocumentsNotifier.new),
          ],
        );
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('concept-preview')),
          'concept-workflow-${dark ? 'dark' : 'light'}',
        );
      },
    );
  }

  test(
    'replacement-concept guidance takes priority over the earlier hearing verdict',
    () {
      final stage = {
        'concept_workflow': _workflow(),
        'assessment_progress': {'display_status': 'redefense_required'},
      };
      expect(
        TeamWorkflowStatus.fromStage(stage).code,
        'replacement_concepts_needed',
      );
      final team = {
        'selected_stage': stage,
        'stages': [stage],
      };
      expect(
        DeliverablesTriageHelper.matchesFilter(
          team,
          TeamTriageFilter.replacementConcepts,
        ),
        isTrue,
      );
    },
  );
}
