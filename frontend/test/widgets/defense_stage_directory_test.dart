import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/defense_stage_directory.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_setup_confirmation.dart';

const stages = <Map<String, dynamic>>[
  {
    'id': 1,
    'label': 'Concept Proposal',
    'code': 'concept-proposal',
    'is_active': true,
    'is_locked': true,
    'is_officially_complete': false,
    'lock_reason': 'This stage has scheduled defenses for the active semester.',
    'setup_readiness': {
      'ready': true,
      'issues': [],
      'required_rubric_roles': ['panel'],
    },
    'rubric_info': {'count': 1, 'panel_rubric_name': 'Concept evaluation'},
    'deliverables': [
      {
        'label': 'Proposal manuscript',
        'deliverable_type': 'pre',
        'required': true,
        'file_format': 'pdf',
      },
      {
        'label': 'Final revisions',
        'deliverable_type': 'post',
        'required': true,
        'verdict_condition': 'revisions_only',
      },
    ],
    'system_deliverables': [
      {
        'label': 'Signed Minutes - Concept Proposal',
        'required': true,
        'deliverable_type': 'system',
      },
    ],
  },
  {
    'id': 2,
    'label': 'Project Proposal',
    'code': 'project-proposal',
    'is_active': false,
    'is_locked': false,
    'previous_stage_label': 'Concept Proposal',
    'setup_readiness': {
      'ready': false,
      'issues': ['Attach a panel evaluation rubric.'],
      'required_rubric_roles': ['panel'],
    },
    'rubric_info': {'count': 0},
    'is_presentation_only': true,
  },
];

void main() {
  Future<void> pumpDirectory(
    WidgetTester tester, {
    double width = 1440,
    bool dark = false,
    DefenseStagesState state = const DefenseStagesState(stages: stages),
    ValueChanged<Map<String, dynamic>>? configure,
    Future<void> Function()? refresh,
    StageMutation? publish,
  }) async {
    tester.view.physicalSize = Size(width, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('directory-preview'),
            child: ColoredBox(
              color: dark
                  ? DefensysTokens.mistBackground
                  : DefensysTokens.background,
              child: DefenseStageDirectory(
                state: state,
                onRefresh: refresh ?? () async {},
                onAdd: () async {},
                onConfigure: configure ?? (_) {},
                onPublish: publish ?? (_) async {},
                onDelete: (_) async {},
                onMove: (_, _, _) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('publication and readiness are independent of edit locks', () {
    expect(stagePublished(stages.first), isTrue);
    expect(stageSetupLocked(stages.first), isTrue);
    expect(stageSetupIssues(stages.first), isEmpty);
    expect(
      stageSetupIssues({'is_active': true, 'is_locked': true}),
      isNotEmpty,
    );
    expect(
      stagePublished({'is_active': false, 'status': 'published'}),
      isFalse,
    );
  });

  testWidgets(
    'scheduled stage remains Published with an explicit lock reason',
    (tester) async {
      Map<String, dynamic>? configured;
      await pumpDirectory(tester, configure: (stage) => configured = stage);
      expect(find.text('Completed'), findsNothing);
      expect(find.text('Completed Stages'), findsNothing);
      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('Setup ready'), findsOneWidget);
      expect(find.textContaining('Configuration locked'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stage-configure-1')));
      expect(configured?['id'], 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expanded requirements include rubric names and documenter minutes',
    (tester) async {
      await pumpDirectory(tester);
      expect(find.text('Proposal manuscript'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('stage-requirements-1')));
      await tester.pumpAndSettle();
      expect(find.text('Proposal manuscript'), findsOneWidget);
      expect(find.text('Concept evaluation'), findsOneWidget);
      expect(find.text('Signed Minutes - Concept Proposal'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stage-requirements-1')));
      await tester.pumpAndSettle();
      expect(find.text('Proposal manuscript'), findsNothing);
    },
  );

  testWidgets(
    'incomplete draft cannot publish or move across locked preceding stage',
    (tester) async {
      await pumpDirectory(tester);
      await tester.tap(find.byKey(const ValueKey('stage-menu-2')));
      await tester.pumpAndSettle();
      final publish = tester.widget<ShadButton>(
        find
            .ancestor(
              of: find.text('Publish stage'),
              matching: find.byType(ShadButton),
            )
            .first,
      );
      final earlier = tester.widget<ShadButton>(
        find
            .ancestor(
              of: find.text('Move earlier'),
              matching: find.byType(ShadButton),
            )
            .first,
      );
      expect(publish.enabled, isFalse);
      expect(earlier.enabled, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ready draft can publish and locked stage cannot delete', (
    tester,
  ) async {
    Map<String, dynamic>? published;
    final readyDraft = {
      ...stages[1],
      'setup_readiness': {'ready': true, 'issues': []},
    };
    await pumpDirectory(
      tester,
      state: DefenseStagesState(stages: [stages.first, readyDraft]),
      publish: (stage) async => published = stage,
    );
    await tester.tap(find.byKey(const ValueKey('stage-menu-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish stage'));
    await tester.pumpAndSettle();
    expect(published?['id'], 2);
    await tester.tap(find.byKey(const ValueKey('stage-menu-1')));
    await tester.pumpAndSettle();
    final delete = tester.widget<ShadButton>(
      find
          .ancestor(
            of: find.text('Delete stage'),
            matching: find.byType(ShadButton),
          )
          .first,
    );
    expect(delete.enabled, isFalse);
  });

  for (final width in [420.0, 800.0, 1100.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'sequence and table fit width $width in ${dark ? 'dark' : 'light'} theme',
        (tester) async {
          final longName = {
            ...stages.first,
            'label':
                'Concept Proposal and Research Methodology Review With an Extended Academic Stage Name',
          };
          await pumpDirectory(
            tester,
            width: width,
            dark: dark,
            state: DefenseStagesState(stages: [longName, stages[1]]),
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Table'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Sequence'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('stage-requirements-1')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('empty, loading, failed load and retry are distinct', (
    tester,
  ) async {
    await pumpDirectory(tester, state: const DefenseStagesState());
    expect(find.text('Build your defense sequence'), findsOneWidget);
    await pumpDirectory(
      tester,
      state: const DefenseStagesState(isLoading: true),
    );
    expect(find.text('Build your defense sequence'), findsNothing);
    var retried = false;
    await pumpDirectory(
      tester,
      state: const DefenseStagesState(error: 'Connection unavailable'),
      refresh: () async => retried = true,
    );
    expect(find.text('Build your defense sequence'), findsNothing);
    expect(find.text('Total stages'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(retried, isTrue);
  });

  testWidgets('render preview of both themes', (tester) async {
    for (final dark in [false, true]) {
      final loader = FontLoader('Inter');
      loader.addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
      loader.addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
      await tester.runAsync(() async {
        await loader.load();
        final icons = FontLoader('packages/lucide_icons_flutter/Lucide');
        icons.addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        );
        await icons.load();
      });
      await pumpDirectory(tester, dark: dark);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('directory-preview')),
        );
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('../.tmp/stage-redesign').create(recursive: true);
        await File(
          '../.tmp/stage-redesign/${dark ? 'dark' : 'light'}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
  for (final width in [420.0, 1440.0]) {
    testWidgets(
      'confirmation allows cancellation and approval at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        bool? confirmed;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.mistDarkTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async =>
                      confirmed = await showStageSetupConfirmation(
                        context,
                        title: 'Delete defense stage?',
                        description: 'Delete the selected stage?',
                        confirmLabel: 'Delete stage',
                        destructive: true,
                      ),
                  child: const Text('Open confirmation'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open confirmation'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(confirmed, isFalse);
        await tester.tap(find.text('Open confirmation'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete stage'));
        await tester.pumpAndSettle();
        expect(confirmed, isTrue);
      },
    );
  }
}
