import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_table.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/faculty_requirement_actions.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/faculty_requirements_pane.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/deliverable_file_widgets.dart';
import 'package:defensys/widgets/repository/deliverable_review_navigation.dart';
import 'package:defensys/widgets/repository/document_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

Map<String, dynamic> _group(
  String id, {
  int count = 1,
  String status = 'pending',
}) => {
  'id': id,
  'label': id == 'PAPER' ? 'Concept Papers' : id,
  'type': 'pre',
  'required': true,
  'can_faculty_review': true,
  'file_policy': {'mode': 'slots'},
  'document_slots': [
    for (var i = 1; i <= count; i++)
      {
        'key': 'c$i:paper',
        'label': 'Concept $i · Concept paper',
        'required': true,
      },
  ],
  'submission': {
    'files': [
      for (var i = 1; i <= count; i++)
        {
          'id': i + 10,
          'slot_key': 'c$i:paper',
          'file_name': '$id-$i.pdf',
          'file_url': 'https://example.test/$id-$i.pdf',
          'status': status,
          'revision': 1,
        },
    ],
  },
};

class _Reviews extends CapstoneDeliverablesNotifier {
  bool succeed = true;
  final writes = <(int?, String, String?)>[];
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
    writes.add((fileId, status, feedback));
    state = state.copyWith(isSaving: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    state = state.copyWith(isSaving: false);
    return succeed;
  }
}

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  test(
    'queue entries exclude historical and missing files without hiding rejected uploads',
    () {
      final item = _group('PAPER', count: 2, status: 'rejected');
      ((item['submission'] as Map)['files'] as List)[1]['is_current'] = false;
      final entries = deliverableReviewEntries(item);
      expect((entries[0]['file'] as Map)['status'], 'rejected');
      expect(entries[1]['file'], isNull);
      expect(
        deliverableReviewEntries({
          'uploaded': true,
          'submission': {},
        }).single['file'],
        isNull,
      );
      expect(
        deliverableReviewEntries({
          'uploaded': false,
          'submission': {'file_name': 'revision.pdf', 'status': 'rejected'},
        }).single['file'],
        isNotNull,
      );
    },
  );

  for (final dark in [false, true]) {
    for (final width in [1100.0, 390.0]) {
      testWidgets(
        'Next file crosses requirements and preserves multi-file choices at $width, dark=$dark',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final paper = _group('PAPER', status: 'accepted');
          final missing = _group('MISSING')..['submission'] = {'files': []};
          final deck = _group('DECK', count: 2, status: 'accepted');
          final archive = <String, dynamic>{
            'id': 'ARCHIVE',
            'label': 'Final archive',
            'type': 'post',
            'submission': {
              'file_name': 'archive.pdf',
              'file_url': 'https://example.test/archive.pdf',
              'status': 'accepted',
            },
          };
          const key = ValueKey('focused-review-preview');
          final view = FacultyRequirementsViewState();
          await pumpDefensysWidget(
            tester,
            RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: dark
                    ? AppTheme.mistDarkTheme.scaffoldBackgroundColor
                    : AppTheme.theme.scaffoldBackgroundColor,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('The existing project title'),
                      FacultyRequirementsPane(
                        items: [paper, missing, deck, archive],
                        viewState: view,
                        buildRequirement: (item) =>
                            usesGroupedDocumentCard(item)
                            ? DocumentGroup(
                                key: ValueKey(item['id']),
                                teamId: 8,
                                stageLabel: 'Mini Capstone',
                                item: item,
                                focused: true,
                                concepts: const [
                                  {
                                    'key': 'c1',
                                    'title': 'The existing project title',
                                  },
                                ],
                              )
                            : Text(
                                'Review ${(item['submission'] as Map)['file_name']}',
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            overrides: authTestOverrides(),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          );
          final row = tester.getRect(
            find.byKey(const ValueKey('requirement-row-PAPER')),
          );
          // The padded corner belongs to the row, beyond both the title and action.
          final press = await tester.startGesture(
            row.bottomRight - const Offset(2, 2),
          );
          await tester.pump(const Duration(milliseconds: 100));
          await capturePreview(
            tester,
            find.byKey(key),
            'deliverable-pressed-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await press.up();
          await tester.pumpAndSettle();
          await tester.tap(find.text('All deliverables'));
          await tester.pumpAndSettle();
          expect(view.lastOpened, 'PAPER');
          await capturePreview(
            tester,
            find.byKey(key),
            'deliverable-selected-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await tester.tapAt(
            tester.getCenter(
              find.byKey(const ValueKey('requirement-row-PAPER')),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('PAPER-1.pdf'), findsOneWidget);
          expect(find.text('The existing project title'), findsOneWidget);
          expect(find.byType(ShadTabs<String>), findsNothing);
          expect(find.text('Revision 1'), findsOneWidget);
          expect(find.text('File 1 of 4'), findsOneWidget);
          expect(
            tester
                .widget<ShadButton>(
                  find.widgetWithText(ShadButton, 'Next file'),
                )
                .enabled,
            isTrue,
          );
          await capturePreview(
            tester,
            find.byKey(key),
            'focused-review-${width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await tester.tap(find.text('Next file'));
          await tester.pumpAndSettle();
          expect(find.text('DECK-1.pdf'), findsOneWidget);
          expect(find.byType(ShadTabs<String>), findsOneWidget);
          expect(find.text('File 2 of 4'), findsOneWidget);
          await tester.tap(find.text('Next file'));
          await tester.pumpAndSettle();
          expect(find.text('DECK-2.pdf'), findsOneWidget);
          await tester.tap(find.text('Previous'));
          await tester.pumpAndSettle();
          expect(find.text('DECK-1.pdf'), findsOneWidget);
          await tester.tap(find.text('Next file'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Next file'));
          await tester.pumpAndSettle();
          expect(find.text('Review archive.pdf'), findsOneWidget);
          expect(find.text('File 4 of 4'), findsOneWidget);
          expect(
            tester
                .widget<ShadButton>(
                  find.widgetWithText(ShadButton, 'Next file'),
                )
                .enabled,
            isFalse,
          );
          await tester.tap(find.text('Previous'));
          await tester.pumpAndSettle();
          expect(find.text('DECK-2.pdf'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final succeed in [false, true]) {
    testWidgets(
      'Accept & next crosses deliverables only after save succeeds ($succeed)',
      (tester) async {
        final reviews = _Reviews()..succeed = succeed;
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            child: FacultyRequirementsPane(
              items: [_group('PAPER'), _group('DECK')],
              buildRequirement: (item) => DocumentGroup(
                key: ValueKey(item['id']),
                teamId: 8,
                stageLabel: 'Mini Capstone',
                item: item,
                focused: true,
              ),
            ),
          ),
          overrides: [
            ...authTestOverrides(),
            capstoneDeliverablesProvider.overrideWith(() => reviews),
          ],
        );
        await tester.tap(find.byKey(const ValueKey('requirement-link-PAPER')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Accept & next'));
        await tester.pump();
        expect(
          tester
              .widget<ShadButton>(find.widgetWithText(ShadButton, 'Next file'))
              .enabled,
          isFalse,
        );
        await tester.pumpAndSettle();
        expect(reviews.writes, [(11, 'accepted', '')]);
        expect(
          find.text(succeed ? 'DECK-1.pdf' : 'PAPER-1.pdf'),
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
    'More actions respect review permissions, pending state and archive locks',
    (tester) async {
      final pending = _group('PENDING');
      final accepted = _group('ACCEPTED', status: 'accepted')
        ..['can_faculty_review'] = false;
      final archived = _group('ARCHIVED', status: 'accepted')
        ..['type'] = 'post';
      final missing = _group('MISSING')..['submission'] = {'files': []};
      final rejected = _group('REJECTED', status: 'rejected');
      final legacyFiles = _group('LEGACY', count: 2)..remove('file_policy');
      final revisions = <int>[];
      await tester.binding.setSurfaceSize(const Size(1100, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: FacultyRequirementsPane(
            items: [
              pending,
              accepted,
              archived,
              missing,
              rejected,
              legacyFiles,
            ],
            buildRequirement: (item) => Text('Review ${item['label']}'),
            onRequestRevision: (_, file) => revisions.add(file['id'] as int),
          ),
        ),
        overrides: authTestOverrides(),
      );
      FacultyRequirementActions actions(String id) =>
          tester.widget<FacultyRequirementActions>(
            find.byKey(ValueKey('requirement-actions-$id')),
          );
      expect(actions('PENDING').onReview, isNotNull);
      expect(actions('PENDING').onViewFile, isNotNull);
      expect(actions('PENDING').onRequestRevision, isNotNull);
      for (final id in ['ACCEPTED', 'ARCHIVED', 'MISSING', 'REJECTED']) {
        expect(actions(id).onReview, isNull);
        expect(actions(id).onRequestRevision, isNull);
      }
      expect(actions('MISSING').onViewFile, isNull);
      expect(actions('LEGACY').multipleFiles, isTrue);
      expect(actions('LEGACY').onRequestRevision, isNull);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('requirement-actions-PENDING')),
          matching: find.byIcon(Icons.more_horiz),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('requirement-row-PENDING')),
        findsOneWidget,
      );
      expect(find.text('Review PENDING'), findsNothing);
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('View file'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      await capturePreview(
        tester,
        find.byType(RepaintBoundary).first,
        'faculty-deliverable-actions',
        viewport: true,
      );
      await tester.tap(find.text('Request revision'));
      await tester.pumpAndSettle();
      expect(revisions, [11]);
      await tester.tap(find.byKey(const ValueKey('requirement-link-PENDING')));
      await tester.pumpAndSettle();
      expect(find.text('Review PENDING'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('revision menu requires feedback and targets the selected file', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final reviews = _Reviews();
    final stage = {
      'stage_label': 'Mini Capstone',
      'deliverables_configured': true,
      'pre': [_group('PAPER')],
      'post': <Map<String, dynamic>>[],
    };
    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: DeliverablesTablePane(
          state: CapstoneDeliverablesState(
            scope: 'pit',
            selectedStage: 'Mini Capstone',
            teams: [
              {
                'id': 8,
                'name': 'Team AquaSense',
                'stages': [stage],
              },
            ],
          ),
          isAdviser: false,
          isPitInstructor: true,
          compactFaculty: true,
        ),
      ),
      overrides: [
        ...authTestOverrides(),
        capstoneDeliverablesProvider.overrideWith(() => reviews),
      ],
    );
    await tester.tap(find.byTooltip('Deliverable actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request revision'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Request revision'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byType(TextField).last,
      'Please correct the references.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Request revision'));
    await tester.pumpAndSettle();
    expect(reviews.writes, [
      (11, 'rejected', 'Please correct the references.'),
    ]);
    expect(tester.takeException(), isNull);
  });
}
