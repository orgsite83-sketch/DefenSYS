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
    'per-concept decks stay out of project papers and mixed slots keep only papers',
    () {
      expect(
        isConceptRequirement({
          'label': 'Pitch Deck',
          'file_policy': {'mode': 'concepts'},
        }),
        isFalse,
      );
      expect(
        isConceptRequirement({
          'file_format': 'pptx',
          'file_policy': {'mode': 'concepts'},
        }),
        isFalse,
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
      final papers = conceptPaperRequirement(item);
      expect(papers['id'], 'CONCEPTS');
      expect((papers['document_slots'] as List).length, 2);
      expect((papers['submission'] as Map)['files'], [
        {'id': 1, 'slot_key': 'c1:paper'},
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
    'upload completeness never grants acceptance; defense and archive keep their rules',
    () {
      final item = _requirement(count: 2);
      expect(RequirementSummary(item).status, 'Under Review');
      expect(RequirementSummary(item).uploaded, 2);
      item['requirement_timing'] = 'defense';
      expect(RequirementSummary(item).status, 'Uploaded');
      expect(RequirementSummary(item).pending, 0);
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
    'requirement list paginates and retains its view when returning',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final view = FacultyRequirementsViewState();
      final items = [
        for (var i = 0; i < 10; i++) _requirement(id: '$i', count: 1),
      ];
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
      expect(find.text('Requirement 8'), findsNothing);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Requirement 8'), findsOneWidget);
      expect(find.text('Requirement 0'), findsNothing);
      await tester.tap(find.text('Open').first);
      await tester.pumpAndSettle();
      expect(find.text('Focused Requirement 8'), findsOneWidget);
      await tester.tap(find.text('All deliverables'));
      await tester.pumpAndSettle();
      expect(find.text('Requirement 8'), findsOneWidget);
      expect(view.page, 1);
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
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Local concept papers'), findsOneWidget);
      await tester.tap(find.text('All deliverables'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final shared in [false, true]) {
    testWidgets(
      'concept workspace shows papers only and confirms names inline (shared=$shared)',
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
        expect(find.text('Pitch Deck'), findsNothing);
        expect(find.text('All deliverables'), findsNothing);
        expect(find.text('concept_1.pdf'), findsOneWidget);
        expect(find.text('Project concept 1'), findsOneWidget);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('concept-workspace-preview')),
          'concept-workspace-${shared ? 'shared' : 'independent'}',
        );
        await tester.tap(
          find.text(shared ? 'Confirm module names' : 'Edit concept names'),
        );
        await tester.pumpAndSettle();
        expect(find.text('concept_1.pdf'), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        await tester.enterText(
          find.byType(EditableText).first,
          'Confirmed project name',
        );
        reviews.succeed = false;
        await tester.tap(find.text('Confirm names'));
        await tester.pumpAndSettle();
        expect(find.text('Back to papers'), findsOneWidget);
        reviews.succeed = true;
        await tester.tap(find.text('Confirm names'));
        await tester.pumpAndSettle();
        expect(find.text('concept_1.pdf'), findsOneWidget);
        expect(reviews.names.last['concepts'].length, count);
        expect(
          reviews.names.last['concepts'][0]['title'],
          'Confirmed project name',
        );
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
          'required_total': 1,
          'required_uploaded': 0,
          'pre': [_requirement()],
          'post': <Map<String, dynamic>>[],
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
        expect(find.text('Open'), findsOneWidget);
        expect(tester.widget<Text>(find.text('Open')).maxLines, 1);
        expect(find.text('pitch_1.pdf'), findsNothing);
        expect(tester.takeException(), isNull);
        final name = find.text('AgroTrade').last;
        expect(
          tester.widget<Text>(name).style?.color,
          DefensysTokens.textPrimaryOf(tester.element(name)),
        );
        await capturePreview(
          tester,
          find.byKey(const ValueKey('faculty-workspace-capture')),
          'faculty-workspace-${width.toInt()}-${dark ? 'dark' : 'light'}',
        );
      });
    }
  }
}
