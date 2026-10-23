import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/concept_workspace.dart';
import 'package:defensys/widgets/repository/document_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

List<Map<String, dynamic>> decisions() => [
  for (var i = 1; i <= 3; i++)
    {
      'key': 'c$i',
      'title': 'Proposal $i',
      'decision': 'rejected',
      'remarks': 'Panel instructions $i',
    },
];

void main() {
  testWidgets(
    'ordinary hearing history reuses the existing history component',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        const ConceptWorkspace(
          teamId: 8,
          stageLabel: 'Custom defense',
          stage: {
            'hearing_history': [
              {
                'round': 1,
                'verdict': 'for_redefense',
                'concepts': [],
                'documents': [
                  {
                    'files': [
                      {
                        'file_name': 'original_presentation.pdf',
                        'revision': 1,
                        'status': 'accepted',
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ),
        overrides: authTestOverrides(),
      );
      await tester.tap(find.textContaining('Attempt 1'));
      await tester.pumpAndSettle();
      expect(find.text('original_presentation.pdf'), findsOneWidget);
      expect(find.textContaining('Faculty accepted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('rejection alone does not create a replacement request', () {
    final rejected = decisions();
    expect(
      conceptDecisionError(rejected, 'for_redefense', requirePlan: true),
      contains('at least one'),
    );
    rejected[1]['next_action'] = 'revise';
    rejected[2]['next_action'] = 'replace';
    expect(
      conceptDecisionError(rejected, 'for_redefense', requirePlan: true),
      isNull,
    );
    final payload = conceptDecisionsForOutcome(rejected, 'for_redefense');
    expect(payload.map((c) => c['next_action']), ['omit', 'revise', 'replace']);
    expect(payload.map((c) => c['key']), ['c1', 'c2', 'c3']);
  });

  testWidgets(
    'chair can request two concepts using the existing choice control',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var current = decisions();
      await pumpDefensysWidget(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: ConceptVerdictFields(
              concepts: current,
              forRedefense: true,
              onChanged: (value) => setState(() => current = value),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('c2-next-hearing')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revise and present again').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('c3-next-hearing')));
      await tester.tap(find.byKey(const ValueKey('c3-next-hearing')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit a replacement concept').last);
      await tester.pumpAndSettle();
      expect(current[1]['next_action'], 'revise');
      expect(current[2]['next_action'], 'replace');
      expect(
        conceptDecisionError(current, 'for_redefense', requirePlan: true),
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    for (final width in [390.0, 1100.0]) {
      testWidgets(
        'repeat documents and history keep current style $width $dark',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1200));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await loadPreviewFonts();
          await pumpDefensysWidget(
            tester,
            RepaintBoundary(
              key: const ValueKey('repeat-documents-preview'),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ConceptWorkspace(
                      teamId: 8,
                      stageLabel: 'Concept Proposal',
                      stage: {
                        'concept_workflow': {
                          'enabled': true,
                          'round': 2,
                          'can_edit': true,
                          'status': 'concept_review_pending',
                          'config': {
                            'required_count': 1,
                            'concept_keys': ['c2'],
                          },
                          'concepts': [
                            {
                              'key': 'c2',
                              'title': 'Student service queues',
                              'requested_action': 'revise',
                              'panel_feedback': 'Clarify queue prioritization.',
                            },
                          ],
                          'history': [
                            {
                              'round': 1,
                              'verdict': 'for_redefense',
                              'concepts': [
                                {
                                  'key': 'c1',
                                  'title': 'Earlier inventory proposal',
                                  'decision': 'rejected',
                                  'remarks': 'Scope overlaps existing work.',
                                  'next_action': 'omit',
                                  'panel_score': 65,
                                },
                              ],
                              'documents': [
                                {
                                  'files': [
                                    {
                                      'file_name': 'original_inventory.pdf',
                                      'revision': 1,
                                      'status': 'accepted',
                                    },
                                  ],
                                },
                              ],
                            },
                          ],
                        },
                      },
                    ),
                    DocumentGroup(
                      teamId: 8,
                      stageLabel: 'Concept Proposal',
                      item: {
                        'id': 'CONCEPTS',
                        'label': 'Concept documents',
                        'type': 'pre',
                        'required': true,
                        'can_upload': true,
                        'can_faculty_review': false,
                        'file_policy': {'mode': 'concepts'},
                        'document_slots': [
                          {
                            'key': 'c2:paper',
                            'label': 'Concept 2 · Paper',
                            'required': true,
                          },
                          {
                            'key': 'c2:scope',
                            'label': 'Concept 2 · Scope sheet',
                            'required': true,
                          },
                        ],
                        'submission': {
                          'files': [],
                          'status': 'pending',
                          'file_history': [
                            {
                              'id': 11,
                              'slot_key': 'c2:paper',
                              'file_name': 'old_queue.pdf',
                              'revision': 1,
                              'status': 'accepted',
                            },
                          ],
                        },
                      },
                    ),
                  ],
                ),
              ),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
            overrides: authTestOverrides(),
          );
          expect(
            find.textContaining('Clarify queue prioritization.'),
            findsOneWidget,
          );
          expect(find.text('Concept 2 · Paper'), findsWidgets);
          expect(find.text('Concept 1 · Paper'), findsNothing);
          await tester.ensureVisible(find.textContaining('Attempt 1'));
          await tester.tap(find.textContaining('Attempt 1'));
          await tester.pumpAndSettle();
          expect(find.text('original_inventory.pdf'), findsOneWidget);
          expect(find.textContaining('Faculty accepted'), findsOneWidget);
          expect(find.textContaining('Panel: 65%'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('repeat-documents-preview')),
            'phase4-repeat-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
        },
      );
    }
  }
}
