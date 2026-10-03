import 'dart:io';
import 'dart:ui' as ui;

import 'package:defensys/screens/web/admin/defense_scheduler/components/schedule_run_container.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/scheduler_toolbar.dart';
import 'package:defensys/services/admin/external_evaluator_provider.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const _faculty = [
  {
    'id': 101,
    'name': 'Jonathan Beltran',
    'username': 'FAC-101',
    'is_panelist': true,
  },
  {
    'id': 102,
    'name': 'Teresita Buenaventura',
    'username': 'FAC-102',
    'is_panelist': true,
  },
  {
    'id': 103,
    'name': 'Cecilia Magbanua',
    'username': 'FAC-103',
    'is_panelist': false,
  },
];

class _Scheduler extends DefenseSchedulerNotifier {
  _Scheduler(this.initial);
  final DefenseSchedulerState initial;
  Map<String, dynamic>? payload;
  @override
  DefenseSchedulerState build() => initial;
  @override
  Future<bool> generatePlan(Map<String, dynamic> data) async {
    payload = data;
    return false;
  }
}

class _Evaluators extends ExternalEvaluatorNotifier {
  @override
  ExternalEvaluatorState build() => const ExternalEvaluatorState(
    canApprove: true,
    evaluators: [
      {
        'id': 101,
        'name': 'Dr. Lina Santos',
        'institution': 'Partner University',
        'status': 'approved',
        'is_active': true,
      },
      {'id': 104, 'name': 'Alex Reyes', 'status': 'pending', 'is_active': true},
    ],
  );
  @override
  Future<bool> fetch() async => true;
}

class _Fixture {
  _Fixture({bool largePool = false, bool admin = true}) {
    state = DefenseSchedulerState(
      canApprovePanelists: admin,
      requiresPanelistApproval: !admin,
      defenseStages: const [
        {'id': 1, 'label': 'Concept Proposal'},
      ],
      activeSemester: const {'display_name': '2026-2027 / First semester'},
      faculty: [
        ..._faculty,
        if (largePool)
          for (int i = 0; i < 60; i++)
            {
              'id': 200 + i,
              'name': 'Faculty member $i',
              'username': 'FAC-${200 + i}',
            },
      ],
      panelists: [_faculty[0], _faculty[1]],
      documenters: [_faculty[2], _faculty[0]],
      teams: const [
        {
          'id': 1,
          'name': 'Team SkyLedger',
          'level': 'Capstone',
          'ready_for_stage': 'Concept Proposal',
          'is_endorsed': true,
        },
      ],
      rubrics: const [
        {
          'id': 10,
          'scope': 'capstone',
          'defense_stage_id': 1,
          'evaluation_type': 'panel',
        },
        {
          'id': 11,
          'scope': 'capstone',
          'defense_stage_id': 1,
          'evaluation_type': 'adviser',
        },
        {
          'id': 12,
          'scope': 'capstone',
          'defense_stage_id': 1,
          'evaluation_type': 'peer',
        },
      ],
    );
    scheduler = _Scheduler(state);
  }
  late final DefenseSchedulerState state;
  late final _Scheduler scheduler;
  Set<int> panelists = {};
  int? documenter;
}

Future<void> _pump(
  WidgetTester tester,
  _Fixture fixture, {
  double width = 1280,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controllers = [
    TextEditingController(),
    TextEditingController(text: '80'),
    TextEditingController(text: '20'),
    TextEditingController(text: '2026-10-03'),
    TextEditingController(text: '08:00'),
    TextEditingController(text: '60'),
    TextEditingController(text: 'Lab 3'),
    TextEditingController(),
  ];
  addTearDown(() {
    for (final controller in controllers) {
      controller.dispose();
    }
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        defenseSchedulerProvider.overrideWith(() => fixture.scheduler),
        externalEvaluatorProvider.overrideWith(_Evaluators.new),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        home: RepaintBoundary(
          key: const ValueKey('scheduler-preview'),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(width < 640 ? 16 : 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SchedulerToolbar(state: fixture.state, onBack: () {}),
                      const SizedBox(height: 24),
                      const SchedulerStepProgress(currentStep: 1),
                      const SizedBox(height: 24),
                      ScheduleRunContainer(
                        state: fixture.state,
                        scope: 'capstone',
                        stageId: 1,
                        rubricId: 10,
                        adviserRubricId: 11,
                        capstonePeerRubricId: 12,
                        peerRubricId: null,
                        documenterId: fixture.documenter,
                        selectedPanelistIds: fixture.panelists,
                        eventController: controllers[0],
                        panelWeightController: controllers[1],
                        peerWeightController: controllers[2],
                        dateController: controllers[3],
                        timeController: controllers[4],
                        durationController: controllers[5],
                        roomController: controllers[6],
                        pitTemplateController: controllers[7],
                        planSlots: const [],
                        showFinalPreview: false,
                        canScheduleScope: (_, _) => true,
                        scheduleNoticeMessage: (_) => '',
                        onScopeChanged: (_) {},
                        onStageChanged: (_) {},
                        onRubricChanged: (_) {},
                        onAdviserRubricChanged: (_) {},
                        onCapstonePeerRubricChanged: (_) {},
                        onPeerRubricChanged: (_) {},
                        onDocumenterChanged: (id) =>
                            setState(() => fixture.documenter = id),
                        onPanelistsChanged: (ids) =>
                            setState(() => fixture.panelists = ids),
                        onPlanSlotsChanged: (_) {},
                        onShowFinalPreviewChanged: (_) {},
                        onPrefillCapstoneStageRubrics: () async {},
                        onPrefillPitEventConfig: () async {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _picker(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(ShadSelect<int>),
);

Future<void> _open(WidgetTester tester, Finder select) async {
  await tester.ensureVisible(select);
  await tester.tap(select);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(
      of: find.byType(ShadOption<int>),
      matching: find.text(name),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (Platform.environment['DEFENSYS_CAPTURE_PREVIEW'] == '1') {
      final regular = FontLoader('Inter')
        ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'));
      await regular.load();
      final material = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await material.load();
      final lucide = FontLoader('packages/lucide_icons_flutter/Lucide')
        ..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        );
      await lucide.load();
    }
  });

  testWidgets('search, chair changes and removal preserve schedule payload', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _pump(tester, fixture);
    expect(find.text('Presiding panel chair'), findsNothing);
    expect(find.text('Jonathan Beltran'), findsNothing);
    await _open(tester, _picker('faculty-panelist-picker'));
    await tester.enterText(find.byType(EditableText).last, 'FAC-101');
    await tester.pumpAndSettle();
    expect(find.text('Teresita Buenaventura'), findsNothing);
    await _choose(tester, 'Jonathan Beltran');
    await tester.enterText(find.byType(EditableText).last, 'Teresita');
    await tester.pumpAndSettle();
    await _choose(tester, 'Teresita Buenaventura');
    await _close(tester);
    expect(fixture.panelists, {101, 102});
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('presiding-panel-chair')),
        matching: find.text('Jonathan Beltran'),
      ),
      findsOneWidget,
    );
    await _open(tester, find.byKey(const ValueKey('presiding-panel-chair')));
    await _choose(tester, 'Teresita Buenaventura');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('presiding-panel-chair')),
        matching: find.text('Teresita Buenaventura'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Remove Teresita Buenaventura'));
    await tester.pumpAndSettle();
    expect(fixture.panelists, {101});
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('presiding-panel-chair')),
        matching: find.text('Jonathan Beltran'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Generate plan'));
    await tester.tap(find.text('Generate plan'));
    await tester.pumpAndSettle();
    expect(fixture.scheduler.payload?['panelist_ids'], [101]);
    expect(fixture.scheduler.payload?['chair_panelist_id'], 101);
    expect(fixture.scheduler.payload?['scheduled_date'], '2026-10-03');
    expect(fixture.scheduler.payload?['room'], 'Lab 3');
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding a documenter as a panelist clears the documenter role', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _pump(tester, fixture);
    await _open(tester, _picker('documenter-picker'));
    await _choose(tester, 'Cecilia Magbanua');
    expect(fixture.documenter, 103);
    await _open(tester, _picker('faculty-panelist-picker'));
    expect(find.text('Approval included on confirmation'), findsOneWidget);
    await _choose(tester, 'Cecilia Magbanua');
    await _close(tester);
    expect(fixture.documenter, isNull);
    expect(find.text('Choose a documenter'), findsOneWidget);
    await _open(tester, _picker('documenter-picker'));
    expect(
      find.descendant(
        of: find.byType(ShadOption<int>),
        matching: find.text('Cecilia Magbanua'),
      ),
      findsNothing,
    );
    await _close(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PIT lead picker exposes only eligible faculty', (tester) async {
    await _pump(tester, _Fixture(admin: false));
    await _open(tester, _picker('faculty-panelist-picker'));
    expect(find.text('Cecilia Magbanua'), findsNothing);
    expect(find.text('Jonathan Beltran'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'external selection stays separate from faculty IDs and filters pending evaluators',
    (tester) async {
      final fixture = _Fixture()..panelists = {101};
      await _pump(tester, fixture);
      await _open(tester, _picker('external-evaluator-picker'));
      expect(find.text('Alex Reyes'), findsNothing);
      await _choose(tester, 'Dr. Lina Santos');
      await _close(tester);
      expect(fixture.panelists, {101});
      expect(find.text('Keep a faculty panel chair assigned.'), findsOneWidget);
      await tester.ensureVisible(find.text('Generate plan'));
      await tester.tap(find.text('Generate plan'));
      await tester.pumpAndSettle();
      expect(fixture.scheduler.payload?['panelist_ids'], [101]);
      expect(fixture.scheduler.payload?['external_evaluator_ids'], [101]);
      expect(fixture.scheduler.payload?['chair_panelist_id'], 101);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    for (final width in [390.0, 1280.0]) {
      testWidgets(
        'large faculty directory fits $width in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
          final fixture = _Fixture(largePool: true)..panelists = {101, 102};
          await _pump(tester, fixture, width: width, dark: dark);
          expect(find.byType(FilterChip), findsNothing);
          expect(find.text('Faculty member 59'), findsNothing);
          expect(tester.takeException(), isNull);
          if (Platform.environment['DEFENSYS_CAPTURE_PREVIEW'] == '1') {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('scheduler-preview')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '../.tmp/scheduler-${dark ? 'dark' : 'light'}-${width.toInt()}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await _open(tester, _picker('faculty-panelist-picker'));
          await tester.enterText(find.byType(EditableText).last, 'FAC-259');
          await tester.pumpAndSettle();
          expect(find.text('Faculty member 59'), findsOneWidget);
          await _choose(tester, 'Faculty member 59');
          await _close(tester);
          expect(fixture.panelists, {101, 102, 259});
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
