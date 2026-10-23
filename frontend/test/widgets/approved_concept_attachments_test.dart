import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/document_group.dart';
import 'package:defensys/widgets/repository/document_policy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _Reviews extends CapstoneDeliverablesNotifier {
  int? reviewedFile;
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
    reviewedFile = fileId;
    return true;
  }
}

void main() {
  testWidgets('approved concept mode and limits survive setup reconciliation', (
    tester,
  ) async {
    final items = <Map<String, dynamic>>[
      {
        'deliverable_id': 'FINAL',
        'label': 'Approved Concept Paper',
        'deliverable_type': 'post',
        'file_policy': {'mode': 'single', 'purpose': 'approved_concept'},
      },
    ];
    await pumpDefensysWidget(
      tester,
      StatefulBuilder(
        builder: (_, setState) {
          return DocumentPolicyEditor(
            value: Map<String, dynamic>.from(items.first['file_policy'] as Map),
            allowConcepts: true,
            onChanged: (value) => setState(() {
              items.first['file_policy'] = value;
              ensureConceptPapers(items, {'enabled': true});
            }),
          );
        },
      ),
    );
    await tester.tap(find.byType(ShadSelect<String>));
    await tester.pumpAndSettle();
    expect(find.text('Documents for each concept'), findsNothing);
    await tester.tap(find.text('Multiple attachments').last);
    await tester.pumpAndSettle();
    expect(items.first['file_policy'], {
      'mode': 'multiple',
      'purpose': 'approved_concept',
      'min_files': 1,
      'max_files': 10,
    });
    expect(find.text('(Single uploaded file)'), findsNothing);
    await tester.tap(find.byTooltip('More files').first);
    await tester.pumpAndSettle();
    expect((items.first['file_policy'] as Map)['min_files'], 2);
    expect((items.first['file_policy'] as Map)['purpose'], 'approved_concept');
    await tester.tap(find.byType(ShadSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('One file').last);
    await tester.pumpAndSettle();
    expect(items.first['file_policy'], {
      'mode': 'single',
      'purpose': 'approved_concept',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selected concept attachments keep individual review targets and pending group status',
    (tester) async {
      final reviews = _Reviews();
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: DocumentGroup(
            teamId: 8,
            stageLabel: 'Concept Proposal',
            item: {
              'id': 'FINAL',
              'label': 'Approved Concept Paper',
              'type': 'post',
              'required': true,
              'can_upload': false,
              'can_faculty_review': true,
              'file_policy': {
                'mode': 'multiple',
                'purpose': 'approved_concept',
                'min_files': 1,
                'max_files': 3,
              },
              'document_slots': [],
              'submission': {
                'status': 'pending',
                'files': [
                  {
                    'id': 11,
                    'slot_key': 'main',
                    'file_name': 'paper.pdf',
                    'status': 'accepted',
                  },
                  {
                    'id': 12,
                    'slot_key': 'appendix',
                    'file_name': 'appendix.pdf',
                    'status': 'pending',
                  },
                ],
              },
            },
          ),
        ),
        overrides: [
          ...authTestOverrides(),
          capstoneDeliverablesProvider.overrideWith(() => reviews),
        ],
      );
      expect(find.text('Under Review'), findsOneWidget);
      expect(find.text('paper.pdf'), findsOneWidget);
      expect(find.text('appendix.pdf'), findsOneWidget);
      expect(find.textContaining('Concept 1'), findsNothing);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(reviews.reviewedFile, 12);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'approved concept attachment setup fits narrow ${dark ? 'dark' : 'light'} screens',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await loadPreviewFonts();
        await pumpDefensysWidget(
          tester,
          RepaintBoundary(
            key: const ValueKey('approved-attachments'),
            child: ColoredBox(
              color: (dark ? AppTheme.mistDarkTheme : AppTheme.theme)
                  .scaffoldBackgroundColor,
              child: const SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Approved Concept Paper'),
                      DocumentPolicyEditor(
                        value: {
                          'mode': 'multiple',
                          'purpose': 'approved_concept',
                          'min_files': 2,
                          'max_files': 5,
                        },
                        onChanged: _ignorePolicy,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        );
        expect(find.text('Multiple attachments'), findsOneWidget);
        expect(find.text('At least'), findsOneWidget);
        expect(find.text('(Single uploaded file)'), findsNothing);
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('approved-attachments')),
          'approved-concept-attachments-${dark ? 'dark' : 'light'}',
        );
      },
    );
  }
}

void _ignorePolicy(Map<String, dynamic> _) {}
