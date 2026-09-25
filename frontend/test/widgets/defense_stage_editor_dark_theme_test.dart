import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/pipeline_position_selector.dart';
import 'package:defensys/widgets/repository/repository_archive_naming_panel.dart';

void main() {
  final sampleStages = [
    {
      'id': 1,
      'label': 'Concept Proposal',
      'display_order': 1,
      'is_locked': true,
      'status': 'locked',
    },
    {
      'id': 2,
      'label': 'Project Proposal',
      'display_order': 2,
      'is_locked': false,
      'status': 'draft',
    },
    {
      'id': 3,
      'label': 'Exhibit',
      'display_order': 3,
      'is_locked': false,
      'status': 'draft',
    },
  ];

  testWidgets('PipelinePositionSelector renders with Mist Dark tokens in dark mode', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    int currentPos = 2;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.mistDarkTheme,
        home: Scaffold(
          backgroundColor: DefensysTokens.mistBackground,
          body: PipelinePositionSelector(
            selectedPosition: currentPos,
            totalSlots: 3,
            existingStages: sampleStages,
            currentStageName: 'Project Proposal',
            editing: true,
            initialOrder: 2,
            isLocked: false,
            minPosition: 2,
            onPositionChanged: (pos) => currentPos = pos,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Active Stage'), findsOneWidget);
    expect(find.text('Project Proposal'), findsWidgets);
    expect(find.text('Locked (Completed)'), findsOneWidget);
    expect(find.text('Live Pipeline Flow:'), findsOneWidget);
  });

  testWidgets('RepositoryArchiveNamingPanel renders with dark mode tokens and supports expansion', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final templateController = TextEditingController(text: '{project}_{deliverable}');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.mistDarkTheme,
        home: Scaffold(
          backgroundColor: DefensysTokens.mistBackground,
          body: SingleChildScrollView(
            child: RepositoryArchiveNamingPanel(
              templateController: templateController,
              deliverableLabel: 'Concept Paper',
              fileFormat: 'pdf',
              isLocked: false,
              isPit: false,
              stageOrEventLabel: 'Defense Stage 1',
              siblingDeliverables: const [],
              currentIndex: 0,
              onChanged: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Repository Archiving & Naming'), findsOneWidget);
    expect(find.text('⚡ Auto-Renamed by System'), findsOneWidget);
    expect(find.text('Primary Manuscript'), findsOneWidget);
    expect(find.text('Configure Format'), findsOneWidget);

    // Tap to expand options
    await tester.tap(find.text('Configure Format'));
    await tester.pumpAndSettle();

    expect(find.text('Hide Options'), findsOneWidget);
    expect(find.text('Naming Pattern Presets'), findsOneWidget);
    expect(find.text('Project + Deliverable'), findsOneWidget);
    expect(find.text('⚙️ Custom Token Builder'), findsOneWidget);

    // Tap Custom Token Builder
    await tester.tap(find.text('⚙️ Custom Token Builder'));
    await tester.pumpAndSettle();

    expect(find.text('Visual Token Builder'), findsOneWidget);
    expect(find.text('Active Pattern: '), findsOneWidget);
    expect(find.text('+ Project Title'), findsOneWidget);
  });
}
