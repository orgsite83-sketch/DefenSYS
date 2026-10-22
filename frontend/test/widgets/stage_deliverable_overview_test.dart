import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_deliverable_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';

void main() {
  testWidgets(
    'groups pre-defense files together and opens only the selected editor',
    (tester) async {
      final items = <Map<String, dynamic>>[
        {
          'label': 'Adviser Acceptance Form',
          'deliverable_type': 'pre',
          'requirement_timing': 'scheduling',
          'file_format': 'pdf',
          'required': true,
        },
        {
          'label': 'Pitch Deck',
          'deliverable_type': 'pre',
          'requirement_timing': 'defense',
          'deadline_hours_before': 24,
          'file_format': 'presentation',
          'required': true,
          'is_defense_material': true,
        },
      ];
      Map<String, dynamic>? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => StageDeliverableOverview(
                items: items,
                isPost: false,
                selectedItem: selected,
                onSelect: (item) => update(() => selected = item),
                buildEditor: (item, _) =>
                    TextField(key: ValueKey('editor-${item['label']}')),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Pre-defense files (2)'), findsOneWidget);
      expect(find.text('Before scheduled defense (1)'), findsNothing);
      expect(
        find.text('Slides · Required · Panelist material'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Pitch Deck'));
      await tester.pump();
      expect(find.byKey(const ValueKey('editor-Pitch Deck')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('editor-Adviser Acceptance Form')),
        findsNothing,
      );

      await tester.tap(find.text('Done editing'));
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('presentation-only confirmation explains the removal', (
    tester,
  ) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answer = await confirmRemoveStageDeliverables(context, 2);
              },
              child: const Text('Choose mode'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Choose mode'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('remove 2 configured deliverables'),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep requirements'));
    await tester.pumpAndSettle();
    expect(answer, false);
  });

  testWidgets('six requirements stay scannable without opening editors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await loadPreviewFonts();

    final items = <Map<String, dynamic>>[
      for (final name in [
        'Adviser Acceptance Form',
        'Nomination of Panel Members',
        'Proposal Manuscript',
        'Similarity Report',
      ])
        {
          'label': name,
          'deliverable_type': 'pre',
          'requirement_timing': 'scheduling',
          'file_format': 'pdf',
          'required': true,
        },
      {
        'label': 'Pitch Deck',
        'deliverable_type': 'pre',
        'requirement_timing': 'defense',
        'deadline_hours_before': 24,
        'file_format': 'presentation',
        'required': true,
        'is_defense_material': true,
      },
      {
        'label': 'Final Manuscript',
        'deliverable_type': 'post',
        'file_format': 'pdf',
        'required': true,
      },
    ];
    final pre = items
        .where((item) => item['deliverable_type'] == 'pre')
        .toList();
    final post = items
        .where((item) => item['deliverable_type'] == 'post')
        .toList();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: const ValueKey('compact-requirements-preview'),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StageDeliverableCounts(
                      deliverables: items,
                      minutesRequired: true,
                    ),
                    StageDeliverableOverview(
                      items: pre,
                      isPost: false,
                      selectedItem: null,
                      onSelect: (_) {},
                      buildEditor: (_, __) => const SizedBox.shrink(),
                    ),
                    StageDeliverableOverview(
                      items: post,
                      isPost: true,
                      selectedItem: null,
                      onSelect: (_) {},
                      buildEditor: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Pre-defense: 5'), findsOneWidget);
    expect(find.text('Before defense: 1'), findsNothing);
    expect(find.text('Post-defense: 1'), findsOneWidget);
    expect(find.text('Final Manuscript'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
    await capturePreview(
      tester,
      find.byKey(const ValueKey('compact-requirements-preview')),
      'stage-deliverables-compact-six',
    );
  });
}
