import 'dart:ui' show PointerDeviceKind;

import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_table.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/faculty_requirements_pane.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/repository/document_group.dart';
import 'package:defensys/widgets/repository/requirement_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

Map<String, dynamic> _requirement({String id = 'PITCH', int count = 3}) => {
  'id': id,
  'label': id == 'PITCH' ? 'Pitch Deck' : 'Requirement $id',
  'type': 'pre',
  'required': true,
  'can_faculty_review': true,
  'file_policy': {'mode': 'slots'},
  'document_slots': [
    for (var i = 1; i <= count; i++)
      {'key': 'slot$i', 'label': 'Deck $i', 'required': true},
  ],
  'submission': {
    'files': [
      for (var i = 1; i <= count; i++)
        {
          'id': i + 10,
          'slot_key': 'slot$i',
          'file_name': 'pitch_$i.pdf',
          'status': 'pending',
          'revision': 1,
        },
    ],
  },
};

class _Reviews extends CapstoneDeliverablesNotifier {
  bool succeed = true;
  final reviewed = <int?>[];
  final names = <Map<String, dynamic>>[];
  @override
  Future<bool> confirmConceptTitle(
    int teamId,
    String stageLabel, {
    required String conceptKey,
    required int roundId,
    required String reviewToken,
    String? title,
  }) async {
    names.add({
      'team_id': teamId,
      'action': 'confirm_title',
      'concept_key': conceptKey,
      'round_id': roundId,
      'review_token': reviewToken,
      'title': title,
    });
    return succeed;
  }

  @override
  CapstoneDeliverablesState build() => const CapstoneDeliverablesState();
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
    reviewed.add(fileId);
    return succeed;
  }

  @override
  Future<bool> conceptAction(
    int teamId,
    String stageLabel,
    String action, {
    List<Map<String, dynamic>>? concepts,
    String? reason,
    String? reviewToken,
  }) async {
    names.add({
      'team_id': teamId,
      'action': action,
      'concepts': concepts,
      'review_token': reviewToken,
    });
    return succeed;
  }
}

void main() {
  setUpAll(() => loadPreviewFonts(force: true));
  test(
    'concept membership follows structure and preserves every configured slot',
    () {
      expect(
        isConceptRequirement({
          'label': 'Pitch Deck',
          'file_policy': {'mode': 'concepts'},
        }),
        isTrue,
      );
      expect(
        isConceptRequirement({
          'file_format': 'pptx',
          'file_policy': {'mode': 'concepts'},
        }),
        isTrue,
      );
      final item = <String, dynamic>{
        'id': 'CONCEPTS',
        'label': 'Concept Papers',
        'file_policy': {
          'mode': 'concepts',
          'slots': [
            {'key': 'paper', 'file_format': 'pdf'},
            {'key': 'deck', 'file_format': 'pptx'},
          ],
        },
        'document_slots': [
          {'key': 'c1:paper'},
          {'key': 'c1:deck'},
          {'key': 'c2:paper'},
        ],
        'submission': {
          'files': [
            {'id': 1, 'slot_key': 'c1:paper'},
            {'id': 2, 'slot_key': 'c1:deck'},
          ],
        },
      };
      expect(isConceptRequirement(item), isTrue);
      final papers = conceptRequirementForKey(item, 'c1');
      expect(papers['id'], 'CONCEPTS');
      expect((papers['document_slots'] as List).length, 2);
      expect((papers['submission'] as Map)['files'], [
        {'id': 1, 'slot_key': 'c1:paper'},
        {'id': 2, 'slot_key': 'c1:deck'},
      ]);
      expect((item['submission'] as Map)['files'].length, 2);
    },
  );
  test(
    'required slots count actual keys; optional files and history cannot fill gaps',
    () {
      final item = _requirement();
      (item['document_slots'] as List).add({
        'key': 'optional',
        'required': false,
      });
      (item['submission'] as Map)['files'] = [
        {'id': 11, 'slot_key': 'slot1', 'status': 'accepted'},
        {'id': 12, 'slot_key': 'slot2', 'status': 'rejected'},
        {'id': 13, 'slot_key': 'optional', 'status': 'accepted'},
        {
          'id': 14,
          'slot_key': 'slot3',
          'status': 'accepted',
          'is_current': false,
        },
      ];
      final summary = RequirementSummary(item);
      expect(summary.uploaded, 2);
      expect(summary.required, 3);
      expect(summary.missing, 1);
      expect(summary.pending, 0);
      expect(summary.corrections, 1);
      expect(summary.status, '2/3 Uploaded');
      expect(summary.needsAttention, isTrue);
    },
  );

  test(
    'upload completeness never grants acceptance; pre-defense review and archive keep their rules',
    () {
      final item = _requirement(count: 2);
      expect(RequirementSummary(item).status, 'Under Review');
      expect(RequirementSummary(item).uploaded, 2);
      item['requirement_timing'] = 'defense';
      expect(RequirementSummary(item).status, 'Under Review');
      expect(RequirementSummary(item).pending, 2);
      item['type'] = 'post';
      for (final file in (item['submission'] as Map)['files']) {
        file['status'] = 'accepted';
      }
      expect(RequirementSummary(item).status, 'Archived');
      expect(RequirementSummary(item).tone, WorkflowStatusTone.success);
    },
  );

  test(
    'empty submission is missing rather than awaiting review; waivers need no attention',
    () {
      final item = _requirement();
      item['submission'] = {'files': <Map<String, dynamic>>[]};
      expect(RequirementSummary(item).pending, 0);
      expect(RequirementSummary(item).missing, 3);
      expect(RequirementSummary(item).detail, '3 missing');
      item['is_waived'] = true;
      expect(RequirementSummary(item).needsAttention, isFalse);
      expect(RequirementSummary(item).status, 'Waived');
    },
  );

  for (final succeed in [true, false]) {
    testWidgets(
      'focused review advances only after a successful save ($succeed)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final reviews = _Reviews()..succeed = succeed;
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            child: DocumentGroup(
              teamId: 8,
              stageLabel: 'Mini Capstone',
              item: _requirement(),
              focused: true,
            ),
          ),
          overrides: [
            ...authTestOverrides(),
            capstoneDeliverablesProvider.overrideWith(() => reviews),
          ],
        );
        expect(find.text('pitch_1.pdf'), findsOneWidget);
        expect(find.text('pitch_2.pdf'), findsNothing);
        await tester.tap(find.text('Accept & next'));
        await tester.pumpAndSettle();
        expect(reviews.reviewed, [11]);
        expect(
          find.text(succeed ? 'pitch_2.pdf' : 'pitch_1.pdf'),
          findsOneWidget,
        );
        if (!succeed) {
          expect(find.text('The action could not be saved.'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'pre-defense and archive rows appear together and the status filter survives focused review',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final view = FacultyRequirementsViewState();
      final items = [
        for (var i = 0; i < 10; i++) _requirement(id: '$i', count: 1),
      ];
      items[1]['requirement_timing'] = 'defense';
      items[9]['type'] = 'post';
      items[9]['submission'] = {'files': <Map<String, dynamic>>[]};
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: FacultyRequirementsPane(
            items: items,
            viewState: view,
            buildRequirement: (item) => Text('Focused ${item['label']}'),
          ),
        ),
      );
      expect(find.text('Requirement 0'), findsOneWidget);
      expect(find.text('Requirement 8'), findsOneWidget);
      expect(find.text('Requirement 9'), findsOneWidget);
      expect(find.text('Before defense'), findsNothing);
      expect(find.text('Post-defense archive'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(find.byType(ShadTabs<String>), findsNothing);
      await tester.tap(find.byType(ShadSelect<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Missing files (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Requirement 9'), findsOneWidget);
      expect(find.text('Requirement 0'), findsNothing);
      await tester.tap(find.text('Requirement 9'));
      await tester.pumpAndSettle();
      expect(find.text('Focused Requirement 9'), findsOneWidget);
      await tester.tap(find.text('All deliverables'));
      await tester.pumpAndSettle();
      expect(find.text('Requirement 9'), findsOneWidget);
      expect(view.filter, 'missing');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'concept requirement opens locally in By team and returns to its list',
    (tester) async {
      final item = _requirement()..['file_policy'] = {'mode': 'concepts'};
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: FacultyRequirementsPane(
            items: [item],
            buildRequirement: (_) => const Text('Local concept papers'),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('requirement-link-PITCH')));
      await tester.pumpAndSettle();
      expect(find.text('Local concept papers'), findsOneWidget);
      await tester.tap(find.text('All deliverables'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Deliverable actions'), findsOneWidget);
      await capturePreview(
        tester,
        find.byType(FacultyRequirementsPane),
        'requirement-list-returned',
        viewport: true,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('requirement-row-PITCH'))),
      );
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byType(FacultyRequirementsPane),
        'requirement-list-hover',
        viewport: true,
      );
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final shared in [false, true]) {
    testWidgets(
      'concept workspace shows configured documents and confirms names in context (shared=$shared)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1500, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final reviews = _Reviews();
        var openedTeam = false;
        final count = shared ? 3 : 5;
        final paper = <String, dynamic>{
          ..._requirement(id: 'PAPER'),
          'label': 'Concept Papers',
          'file_policy': {'mode': 'concepts'},
          'document_slots': [
            for (var i = 1; i <= count; i++)
              {'key': 'c$i:paper', 'label': 'Concept $i', 'required': true},
          ],
          'submission': {
            'files': [
              for (var i = 1; i <= count; i++)
                {
                  'id': i,
                  'slot_key': 'c$i:paper',
                  'file_name': 'concept_$i.pdf',
                  'status': 'pending',
                },
            ],
          },
        };
        final workflow = <String, dynamic>{
          'enabled': true,
          'can_edit': true,
          'can_edit_titles': true,
          'round': 2,
          'clearance_valid': true,
          'module_review_token': 'current-module-content',
          'round_id': 12,
          'can_confirm_titles': shared,
          if (shared) 'section_project_id': 7,
          'concepts': [
            for (var i = 1; i <= count; i++)
              {
                'key': 'c$i',
                'title': 'Project concept $i',
                if (shared) 'system_title': 'Section system $i',
              },
          ],
        };
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            child: RepaintBoundary(
              key: const ValueKey('concept-workspace-preview'),
              child: DeliverablesTablePane(
                state: CapstoneDeliverablesState(
                  scope: 'pit',
                  selectedStage: 'Mini Capstone',
                  teams: [
                    {
                      'id': 8,
                      'name': 'AgroTrade',
                      'section': 'BSIT-3A',
                      'members': [],
                      'stages': [
                        {
                          'stage_label': 'Mini Capstone',
                          'pre': [
                            paper,
                            {
                              ..._requirement(),
                              'file_policy': {'mode': 'concepts'},
                              'document_slots': [
                                for (var i = 1; i <= count; i++)
                                  {
                                    'key': 'c$i:deck',
                                    'label': 'Concept $i · Deck',
                                  },
                              ],
                            },
                          ],
                          'concept_workflow': workflow,
                        },
                      ],
                    },
                  ],
                ),
                isAdviser: false,
                isPitInstructor: true,
                compactFaculty: true,
                conceptReview: true,
                onReturnToTeam: () => openedTeam = true,
              ),
            ),
          ),
          overrides: [
            ...authTestOverrides(),
            capstoneDeliverablesProvider.overrideWith(() => reviews),
          ],
        );
        expect(find.text('Pitch Deck'), findsOneWidget);
        expect(find.text('All deliverables'), findsNothing);
        expect(find.text('concept_1.pdf'), findsOneWidget);
        expect(find.text('Project concept 1'), findsOneWidget);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('concept-workspace-preview')),
          'concept-workspace-${shared ? 'shared' : 'independent'}',
        );
        await tester.tap(
          find.text(shared ? 'Edit name' : 'Edit concept names'),
        );
        await tester.pumpAndSettle();
        expect(find.text('concept_1.pdf'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        await tester.enterText(
          find.byType(EditableText).first,
          'Confirmed project name',
        );
        reviews.succeed = false;
        await tester.tap(
          find.text(shared ? 'Save and confirm name' : 'Confirm names'),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(shared ? 'Save and confirm name' : 'Back to papers'),
          findsOneWidget,
        );
        reviews.succeed = true;
        await tester.tap(
          find.text(shared ? 'Save and confirm name' : 'Confirm names'),
        );
        await tester.pumpAndSettle();
        expect(find.text('concept_1.pdf'), findsOneWidget);
        if (shared) {
          expect(reviews.names.last['concept_key'], 'c1');
          expect(reviews.names.last['round_id'], 12);
          expect(reviews.names.last['title'], 'Confirmed project name');
          expect(reviews.names.last.containsKey('concepts'), isFalse);
        } else {
          expect(reviews.names.last['concepts'].length, count);
          expect(
            reviews.names.last['concepts'][0]['title'],
            'Confirmed project name',
          );
        }
        expect(
          reviews.names.last['review_token'],
          shared ? 'current-module-content' : null,
        );
        await tester.tap(find.text('Open team workspace'));
        expect(openedTeam, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'By team opens the selected concept without duplicate review controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final reviews = _Reviews();
      final requirement = <String, dynamic>{
        ..._requirement(id: 'CONCEPTS'),
        'label': 'Concept Papers',
        'file_policy': {'mode': 'concepts'},
        'document_slots': [
          for (var i = 1; i <= 3; i++)
            {'key': 'c$i:paper', 'label': 'Concept $i', 'required': true},
        ],
        'submission': {
          'files': [
            for (var i = 1; i <= 3; i++)
              {
                'id': i,
                'slot_key': 'c$i:paper',
                'file_name': 'concept_$i.pdf',
                'status': 'pending',
              },
          ],
        },
      };
      final stage = <String, dynamic>{
        'stage_label': 'Mini Capstone',
        'pre': [requirement],
        'post': [],
        'deliverables_configured': true,
        'can_faculty_review': true,
        'concept_workflow': {
          'enabled': true,
          'can_edit': true,
          'round': 1,
          'round_id': 12,
          'section_project_id': 7,
          'can_confirm_titles': true,
          'module_review_token': 'module-content',
          'shared_review': {
            'project_id': 7,
            'status': 'cleared',
            'status_label': 'Shared papers cleared for hearing',
            'cleared': true,
            'review_progress': {
              'documents_required': 3,
              'documents_accepted': 3,
            },
          },
          'concepts': [
            for (var i = 1; i <= 3; i++)
              {
                'key': 'c$i',
                'title': 'Module proposal $i',
                'system_title': 'Shared system $i',
                'faculty_confirmed': false,
              },
          ],
        },
      };
      var conceptView = false;
      String? fileKey;
      String? requirementId;
      int? openedShared;
      await pumpDefensysWidget(
        tester,
        StatefulBuilder(
          builder: (context, setView) => SingleChildScrollView(
            child: DeliverablesTablePane(
              state: CapstoneDeliverablesState(
                scope: 'pit',
                selectedStage: 'Mini Capstone',
                teams: [
                  {
                    'id': 8,
                    'name': 'AgroTrade',
                    'members': [],
                    'stages': [stage],
                  },
                  {
                    'id': 9,
                    'name': 'New module team',
                    'members': [],
                    'stages': [stage],
                  },
                ],
              ),
              isAdviser: false,
              isPitInstructor: true,
              compactFaculty: true,
              conceptReview: conceptView,
              initialConceptRequirementId: requirementId,
              initialConceptFileKey: fileKey,
              onOpenConceptReview: (id, label, requirement, key) {
                expect(id, 8);
                expect(label, 'Mini Capstone');
                setView(() {
                  conceptView = true;
                  requirementId = requirement;
                  fileKey = key;
                });
              },
              onReturnToTeam: () => setView(() => conceptView = false),
              onOpenSharedReview: (id) => openedShared = id,
            ),
          ),
        ),
        overrides: [
          ...authTestOverrides(),
          capstoneDeliverablesProvider.overrideWith(() => reviews),
        ],
      );
      expect(find.text('Shared documents: 3/3 accepted'), findsNothing);
      expect(find.text('Shared papers cleared for hearing'), findsNothing);
      await tester.tap(find.text('Open shared review'));
      expect(openedShared, 7);
      await tester.tap(find.text('Concept Papers').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Concept 3').first);
      await tester.pumpAndSettle();
      expect(find.text('concept_3.pdf'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Accept & next'), findsNothing);
      expect(find.text('Request revision'), findsOneWidget);
      await tester.tap(find.text('Review title'));
      await tester.pumpAndSettle();
      expect(fileKey, 'c3:paper');
      expect(requirementId, 'CONCEPTS');
      expect(find.text('Module proposal 3'), findsOneWidget);
      expect(find.text('concept_3.pdf'), findsOneWidget);
      expect(find.text('Confirm module name'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Request revision'), findsNothing);
      await tester.tap(find.text('Confirm module name'));
      await tester.pumpAndSettle();
      expect(reviews.names.single['concept_key'], 'c3');
      expect(reviews.names.single['round_id'], 12);
      expect(reviews.reviewed, isEmpty);
      await tester.tap(find.text('Open team workspace'));
      await tester.pumpAndSettle();
      expect(conceptView, isFalse);
      expect(find.text('concept_3.pdf'), findsOneWidget);
      // Returning from one team's title review must not open that same
      // deliverable when choosing a different team.
      await tester.tap(find.byKey(const ValueKey('faculty-team-choice-t9')));
      await tester.pumpAndSettle();
      expect(find.text('All deliverables'), findsNothing);
      expect(find.text('concept_3.pdf'), findsNothing);
      expect(
        find.byKey(const ValueKey('requirement-row-CONCEPTS')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final scope in ['pit', 'capstone']) {
    testWidgets('$scope post-defense rows follow completed assessment evidence', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1500, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final stage = ValueNotifier(<String, dynamic>{
        'stage_label': 'Assessment',
        'deliverables_configured': true,
        'required_total': 1,
        'required_uploaded': 0,
        'endorsed': true,
        'has_active_schedule': true,
        'has_done_schedule': true,
        'is_defense_done': true,
        // An upload override or a legacy completion flag is not assessment evidence.
        'archive_unlocked': true,
        'post_defense_ready': false,
        'pre': [
          {
            'id': 'PRE',
            'label': 'Concept paper',
            'type': 'pre',
            'required': true,
            'uploaded': false,
          },
        ],
        'post': [
          {
            'id': 'POST',
            'label': 'Final manuscript',
            'type': 'post',
            'required': true,
            'uploaded': false,
          },
        ],
      });
      addTearDown(stage.dispose);
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: ValueListenableBuilder<Map<String, dynamic>>(
            valueListenable: stage,
            builder: (context, selectedStage, _) => DeliverablesTablePane(
              state: CapstoneDeliverablesState(
                scope: scope,
                selectedStage: 'Assessment',
                teams: [
                  {
                    'id': 8,
                    'name': 'Assessment team',
                    'members': [],
                    'stages': [selectedStage],
                  },
                ],
              ),
              isAdviser: scope == 'capstone',
              isPitInstructor: scope == 'pit',
              compactFaculty: true,
            ),
          ),
        ),
        overrides: authTestOverrides(),
      );

      expect(find.text('Concept paper'), findsOneWidget);
      expect(find.text('Final manuscript'), findsNothing);
      expect(find.text('Post-defense archive'), findsNothing);
      expect(find.text('1 deliverables'), findsOneWidget);
      await tester.tap(find.byType(ShadSelect<String>).last);
      await tester.pumpAndSettle();
      expect(find.text('Missing files (1)'), findsOneWidget);
      await tester.tap(find.text('Missing files (1)'));
      await tester.pumpAndSettle();

      stage.value = {...stage.value, 'post_defense_ready': true};
      await tester.pumpAndSettle();
      expect(find.text('Final manuscript'), findsOneWidget);
      expect(find.text('Post-defense archive'), findsOneWidget);
      expect(find.text('2 deliverables'), findsOneWidget);
      expect(find.text('Missing files (2)'), findsOneWidget);

      await tester.tap(find.text('Final manuscript'));
      await tester.pumpAndSettle();
      expect(find.text('All deliverables'), findsOneWidget);
      // Reopening an assessment also removes an already opened archive detail.
      stage.value = {...stage.value, 'post_defense_ready': false};
      await tester.pumpAndSettle();
      expect(find.text('Final manuscript'), findsNothing);
      expect(find.text('All deliverables'), findsNothing);
      expect(find.text('Missing files (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [1500.0, 720.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets('compact faculty workspace fits $width, dark=$dark', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final stage = <String, dynamic>{
          'stage_label': 'Mini Capstone',
          'deliverables_configured': true,
          'post_defense_ready': true,
          'required_total': 1,
          'required_uploaded': 0,
          'pre': [
            {..._requirement(id: 'PAPER', count: 1), 'label': 'Concept paper'},
            {..._requirement(), 'requirement_timing': 'defense'},
          ],
          'post': [
            {
              ..._requirement(id: 'ARCHIVE', count: 1),
              'label': 'Final manuscript',
              'type': 'post',
              'can_upload': false,
            },
          ],
          if (width == 720)
            'concept_workflow': {
              'enabled': true,
              'section_project_id': 7,
              'section_selected_key': '',
              'concepts': [
                {'key': 'c1', 'title': 'Proposed title'},
              ],
            },
        };
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            child: RepaintBoundary(
              key: const ValueKey('faculty-workspace-capture'),
              child: DeliverablesTablePane(
                state: CapstoneDeliverablesState(
                  scope: 'pit',
                  selectedStage: 'Mini Capstone',
                  teams: [
                    {
                      'id': 8,
                      'name': 'AgroTrade',
                      'section': 'BSIT-3A',
                      'project_title': width == 390 ? '' : 'Selected project',
                      'members': [
                        {
                          'id': 1,
                          'name': 'Rochelle Valencia',
                          'role': 'leader',
                        },
                      ],
                      'stages': [stage],
                    },
                    {
                      'id': 9,
                      'name': 'Team ResQPoint',
                      'section': 'BSIT-3A',
                      'project_title': width == 390 ? '' : 'Selected project',
                      'members': [],
                      'stages': [stage],
                    },
                  ],
                ),
                isAdviser: false,
                isPitInstructor: true,
                compactFaculty: true,
              ),
            ),
          ),
          overrides: authTestOverrides(),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        );
        expect(
          find.text('Selected project'),
          width == 1500 ? findsOneWidget : findsNothing,
        );
        expect(find.text('Proposed title'), findsNothing);
        expect(find.text('Team details'), findsOneWidget);
        expect(find.text('More'), findsNothing);
        expect(find.byTooltip('Deliverable actions'), findsNWidgets(3));
        expect(find.text('Concept paper'), findsOneWidget);
        expect(find.text('Pitch Deck'), findsOneWidget);
        expect(find.text('Final manuscript'), findsOneWidget);
        expect(find.text('5/5 files uploaded'), findsOneWidget);
        expect(find.text('Before endorsement'), findsNWidgets(2));
        expect(find.text('Before defense'), findsNothing);
        expect(find.text('Post-defense archive'), findsOneWidget);
        expect(find.text('pitch_1.pdf'), findsNothing);
        expect(tester.takeException(), isNull);
        final name = find.text('AgroTrade').last;
        expect(
          tester.widget<Text>(name).style?.color,
          DefensysTokens.textPrimaryOf(tester.element(name)),
        );
        if (width == 1500) {
          final first = find.byKey(const ValueKey('faculty-team-choice-t8'));
          final second = find.byKey(const ValueKey('faculty-team-choice-t9'));
          expect(
            tester.widget<ShadButton>(first).backgroundColor,
            DefensysTokens.maroonOf(tester.element(first)),
          );
          expect(
            tester.widget<ShadButton>(first).foregroundColor,
            Colors.white,
          );
          await tester.tap(second);
          await tester.pumpAndSettle();
          expect(
            tester.widget<ShadButton>(second).backgroundColor,
            DefensysTokens.maroonOf(tester.element(second)),
          );
          expect(
            tester.widget<ShadButton>(first).backgroundColor,
            Colors.transparent,
          );
          expect(tester.takeException(), isNull);
        }
        await capturePreview(
          tester,
          find.byKey(const ValueKey('faculty-workspace-capture')),
          'faculty-workspace-${width.toInt()}-${dark ? 'dark' : 'light'}',
        );
      });
    }
  }
}
