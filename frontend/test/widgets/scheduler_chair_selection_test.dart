import 'dart:io';
import 'dart:ui' as ui;

import 'package:defensys/screens/web/admin/defense_scheduler/components/schedule_run_container.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/scheduler_session_editor.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/models/schedule_session_draft.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/scheduler_toolbar.dart';
import 'package:defensys/services/admin/external_evaluator_provider.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/toasts/feedback_toast.dart';
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
  Map<String, dynamic>? confirmation;
  String? confirmationError;
  List<Map<String, dynamic>> generated = [];
  int generationCalls = 0;
  @override
  DefenseSchedulerState build() => initial;
  @override
  Future<bool> generatePlan(Map<String, dynamic> data) async {
    generationCalls++;
    payload = data;
    if (generated.isEmpty) return false;
    state = state.copyWith(generatedSlots: generated);
    return true;
  }

  @override
  Future<bool> confirmPlan(Map<String, dynamic> data) async {
    confirmation = data;
    state = state.copyWith(error: confirmationError);
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
  _Fixture({
    bool largePool = false,
    bool admin = true,
    bool conflictingAdvisers = false,
    DefenseSchedulerState? initialState,
  }) {
    final original =
        initialState ??
        DefenseSchedulerState(
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
              'adviser': 101,
              'adviser_name': 'Jonathan Beltran',
            },
            {
              'id': 2,
              'name': 'Team MirrorSync',
              'level': 'Capstone',
              'ready_for_stage': 'Concept Proposal',
              'adviser': 101,
              'adviser_name': 'Jonathan Beltran',
            },
            {
              'id': 3,
              'name': 'Team EcoTrack',
              'level': 'Capstone',
              'ready_for_stage': 'Concept Proposal',
              'adviser': 102,
              'adviser_name': 'Teresita Buenaventura',
            },
            {
              'id': 4,
              'name': 'Team Pending',
              'level': 'Capstone',
              'ready_for_stage': '',
              'adviser': 101,
              'adviser_name': 'Jonathan Beltran',
            },
            {
              'id': 5,
              'name': 'Team Scheduled',
              'level': 'Capstone',
              'ready_for_stage': 'Concept Proposal',
              'scheduled_stages': ['Concept Proposal'],
              'adviser': 101,
              'adviser_name': 'Jonathan Beltran',
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
    state = initialState != null || conflictingAdvisers
        ? original
        : original.copyWith(
            teams: [
              for (final team in original.teams)
                {
                  ...team,
                  'adviser': team['adviser'] == 101 ? 201 : 202,
                  'adviser_name': team['adviser'] == 101
                      ? 'Marina Alonzo'
                      : 'Eduardo Reyes',
                },
            ],
          );
    scheduler = _Scheduler(state);
  }
  late final DefenseSchedulerState state;
  late final _Scheduler scheduler;
  Set<int> panelists = {};
  int? documenter;
  List<Map<String, dynamic>> slots = [];
  bool preview = false;
  int? step;
  List<Map<String, dynamic>>? savedSessions;
  Set<int>? savedTeamIds;
}

Future<void> _pump(
  WidgetTester tester,
  _Fixture fixture, {
  double width = 1280,
  bool dark = false,
  String scope = 'capstone',
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controllers = [
    TextEditingController(text: scope == 'pit' ? 'Design Expo' : ''),
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
                      SchedulerStepProgress(
                        currentStep: fixture.slots.isEmpty
                            ? 1
                            : (fixture.preview ? 3 : 2),
                      ),
                      const SizedBox(height: 24),
                      ScheduleRunContainer(
                        currentStep: fixture.step,
                        onStepChanged: (step) {
                          if (fixture.step != null) {
                            setState(() => fixture.step = step);
                          }
                        },
                        initialSessions: fixture.savedSessions,
                        initialSelectedTeamIds: fixture.savedTeamIds,
                        state: fixture.state,
                        scope: scope,
                        stageId: scope == 'capstone' ? 1 : null,
                        rubricId: 10,
                        adviserRubricId: 11,
                        capstonePeerRubricId: 12,
                        peerRubricId: scope == 'pit' ? 20 : null,
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
                        planSlots: fixture.slots,
                        showFinalPreview: fixture.preview,
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
                        onPlanSlotsChanged: (slots) =>
                            setState(() => fixture.slots = slots),
                        onShowFinalPreviewChanged: (preview) =>
                            setState(() => fixture.preview = preview),
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

Future<void> _captureSessions(WidgetTester tester, String name) async {
  if (Platform.environment['DEFENSYS_CAPTURE_PREVIEW'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('scheduler-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../.tmp/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Map<String, dynamic> _sessionSlot(int id, String? session) => {
  'team_id': id,
  'team_name': 'Team $id',
  'stage_label': 'Concept Proposal',
  'session_key': session,
};

ScheduleSessionDraft _draft(WidgetTester tester, [int index = 0]) => tester
    .widget<SchedulerSessionEditor>(
      find.byType(SchedulerSessionEditor).at(index),
    )
    .draft;

void main() {
  setUp(dismissFeedbackToasts);
  tearDown(dismissFeedbackToasts);
  setUpAll(() async {
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
  });

  testWidgets(
    'rejected publish keeps its error and the arranged draft visible',
    (tester) async {
      final fixture = _Fixture()..panelists = {101};
      const error =
          'Team UniConnectClinic needs its required shared system deliverables.';
      fixture.scheduler.confirmationError = error;
      fixture.scheduler.generated = [_sessionSlot(1, 'session-1')];
      await _pump(tester, fixture);
      _draft(tester).teamIds = {1};
      await _open(tester, find.text('Generate plan'));
      await _open(tester, find.text('Proceed to Final Preview'));
      await _open(tester, find.text('Publish & Save Schedule'));
      expect(find.text(error), findsOneWidget);
      expect(fixture.slots, hasLength(1));
      expect(fixture.preview, isTrue);
      expect(find.text('Publish & Save Schedule'), findsOneWidget);
      dismissFeedbackToasts();
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      '16 teams fill two sessions and capacity changes keep the pool at $width',
      (tester) async {
        final base = _Fixture().state;
        final fixture = _Fixture(
          initialState: base.copyWith(
            teams: [
              for (int id = 1; id <= 16; id++)
                {
                  'id': id,
                  'name': 'Team $id',
                  'level': 'Capstone',
                  'ready_for_stage': 'Concept Proposal',
                  'is_endorsed': true,
                },
            ],
          ),
        )..panelists = {101};
        await _pump(tester, fixture, width: width);
        await _open(
          tester,
          find.byKey(const ValueKey('choose-schedule-teams')),
        );
        await tester.tap(
          find.byKey(const ValueKey('session-select-shown-teams')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('apply-session-teams')));
        await tester.pumpAndSettle();
        expect(
          find.text('16 selected · 0 assigned · 16 unassigned'),
          findsWidgets,
        );
        await _open(
          tester,
          find.byKey(const ValueKey('fill-schedule-sessions')),
        );
        expect(_draft(tester).teamIds.length, 8);
        expect(
          find.text('16 selected · 8 assigned · 8 unassigned'),
          findsWidgets,
        );
        await _open(tester, find.byKey(const ValueKey('add-schedule-session')));
        expect(_draft(tester, 1).teamIds, isEmpty);
        await _open(
          tester,
          find.byKey(const ValueKey('fill-schedule-sessions')),
        );
        expect(_draft(tester, 1).teamIds.length, 8);
        expect(
          find.text('16 selected · 16 assigned · 0 unassigned'),
          findsWidgets,
        );
        await _captureSessions(tester, 'scheduler-team-pool-${width.toInt()}');
        await _open(
          tester,
          find.byKey(const ValueKey('edit-time-blocks-session-1')),
        );
        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('session-slot-duration-session-1')),
            matching: find.byType(EditableText),
          ),
          '90',
        );
        await tester.pumpAndSettle();
        expect(_draft(tester).capacity, 8);
        expect(
          find.text('Saving returns 4 teams to Unassigned.'),
          findsOneWidget,
        );
        await _open(
          tester,
          find.byKey(const ValueKey('save-time-blocks-session-1')),
        );
        expect(_draft(tester).capacity, 4);
        expect(
          find.text('16 selected · 12 assigned · 4 unassigned'),
          findsWidgets,
        );
        await tester.ensureVisible(find.byTooltip('Remove session 2'));
        await tester.tap(find.byTooltip('Remove session 2'));
        await tester.pumpAndSettle();
        expect(
          find.text('16 selected · 4 assigned · 12 unassigned'),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('admin chooses individual and adviser teams at $width', (
      tester,
    ) async {
      final fixture = _Fixture(conflictingAdvisers: true)..panelists = {103};
      await _pump(tester, fixture, width: width, dark: width == 390);
      expect(_draft(tester).capacity, 8);
      expect(_draft(tester).teamIds, isEmpty);
      final chooseFirst = find.byKey(const ValueKey('choose-schedule-teams'));
      await _open(tester, chooseFirst);
      expect(find.text('Team Pending'), findsNothing);
      expect(find.text('Team Scheduled'), findsNothing);
      await _open(tester, find.byKey(const ValueKey('session-team-adviser-0')));
      await _choose(tester, 'Jonathan Beltran');
      await tester.tap(find.text('Select adviser’s teams'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('session-team-1')),
            )
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('session-team-2')),
            )
            .value,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('session-team-2')));
      await _open(
        tester,
        find.byKey(const ValueKey('session-team-adviser-101')),
      );
      await _choose(tester, 'All advisers');
      await tester.tap(find.byKey(const ValueKey('session-team-3')));
      await tester.tap(find.byKey(const ValueKey('apply-session-teams')));
      await tester.pumpAndSettle();
      expect(_draft(tester).teamIds, isEmpty);
      await tester.ensureVisible(
        find.byKey(const ValueKey('fill-schedule-sessions')),
      );
      await tester.tap(find.byKey(const ValueKey('fill-schedule-sessions')));
      await tester.pumpAndSettle();
      expect(_draft(tester).teamIds, {1, 3});
      await tester.ensureVisible(find.text('Add session'));
      await tester.tap(find.text('Add session'));
      await tester.pumpAndSettle();
      expect(_draft(tester, 1).teamIds, isEmpty);
      expect(
        _draft(tester, 1).blocks.map((block) => block.toPayload()),
        _draft(tester).blocks.map((block) => block.toPayload()),
      );
      await _open(tester, find.byKey(const ValueKey('choose-schedule-teams')));
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('session-team-1')),
            )
            .onChanged,
        isNotNull,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('session-team-3')),
            )
            .onChanged,
        isNotNull,
      );
      await tester.tap(find.text('Select shown teams'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apply-session-teams')));
      await tester.pumpAndSettle();
      await _open(
        tester,
        find.byKey(const ValueKey('manage-session-teams-session-2')),
      );
      await _open(
        tester,
        find.byKey(const ValueKey('assign-unassigned-team-session-2-2')),
      );
      await _choose(tester, 'Team MirrorSync');
      expect(_draft(tester, 1).teamIds, {2});
      await tester.ensureVisible(find.text('Generate plan'));
      await tester.tap(find.text('Generate plan'));
      await tester.pumpAndSettle();
      final sessions = fixture.scheduler.payload!['sessions'] as List;
      expect(sessions.first['team_ids'], [1, 3]);
      expect(sessions.last['team_ids'], [2]);
      expect(sessions.first['time_blocks'], [
        {'start_time': '08:00', 'end_time': '12:00'},
        {'start_time': '13:00', 'end_time': '17:00'},
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'restoring a legacy overfilled session keeps overflow in the pool',
    (tester) async {
      final fixture = _Fixture()
        ..savedSessions = [
          {
            'key': 'session-1',
            'date': '2026-10-03',
            'start': '08:00',
            'end': '12:00',
            'duration': '60',
            'room': 'Lab 3',
            'team_ids': [for (int id = 1; id <= 16; id++) id],
          },
        ];
      await _pump(tester, fixture);
      expect(_draft(tester).teamIds.length, 8);
      expect(
        find.text('16 selected · 8 assigned · 8 unassigned'),
        findsWidgets,
      );
      await _open(tester, find.byKey(const ValueKey('add-schedule-session')));
      await _open(tester, find.byKey(const ValueKey('fill-schedule-sessions')));
      expect(_draft(tester, 1).teamIds.length, 8);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving setup changes invalidates stale slots and preserves assignments',
    (tester) async {
      final fixture = _Fixture()
        ..panelists = {101}
        ..step = 1;
      fixture.scheduler.generated = [
        for (int id = 1; id <= 3; id++) _sessionSlot(id, 'session-1'),
      ];
      await _pump(tester, fixture);
      _draft(tester).teamIds = {1, 2, 3};
      await _open(tester, find.text('Generate plan'));
      expect(fixture.scheduler.generationCalls, 1);
      await _open(tester, find.text('Back to Step 1'));
      await _open(
        tester,
        find.byKey(const ValueKey('edit-time-blocks-session-1')),
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('session-slot-duration-session-1')),
          matching: find.byType(EditableText),
        ),
        '90',
      );
      await tester.pumpAndSettle();
      await _open(
        tester,
        find.byKey(const ValueKey('save-time-blocks-session-1')),
      );
      expect(fixture.slots, isEmpty);
      expect(_draft(tester).teamIds, {1, 2, 3});
      await _open(tester, find.text('Generate plan'));
      expect(fixture.scheduler.generationCalls, 2);
      dismissFeedbackToasts();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('generating requires an admin selection', (tester) async {
    final fixture = _Fixture()..panelists = {101};
    await _pump(tester, fixture);
    await tester.ensureVisible(find.text('Generate plan'));
    await tester.tap(find.text('Generate plan'));
    await tester.pumpAndSettle();
    expect(fixture.scheduler.payload, isNull);
    expect(
      find.text('Choose at least one team for your sessions.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'generation warns and blocks an adviser as chair or panel member',
    (tester) async {
      final fixture = _Fixture(conflictingAdvisers: true)
        ..panelists = {101, 102};
      await _pump(tester, fixture);
      _draft(tester).teamIds = {1};
      await tester.ensureVisible(find.text('Generate plan'));
      await tester.tap(find.text('Generate plan'));
      await tester.pumpAndSettle();
      expect(fixture.scheduler.payload, isNull);
      expect(
        find.textContaining('Team SkyLedger — the team adviser cannot'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PIT team selection excludes scheduled and completed events without prerequisites',
    (tester) async {
      final fixture = _Fixture(
        initialState: const DefenseSchedulerState(
          faculty: _faculty,
          panelists: _faculty,
          pitEvents: [
            {
              'event_name': 'Design Expo',
              'year_level': '1st Year',
              'deliverables': [],
            },
          ],
          rubrics: [
            {'id': 10, 'scope': 'pit'},
          ],
          peerRubrics: [
            {'id': 20, 'scope': 'pit'},
          ],
          teams: [
            {
              'id': 1,
              'name': 'PIT Ready',
              'level': 'PIT',
              'year_level': '1st Year',
              'ready_for_stage': '',
            },
            {
              'id': 2,
              'name': 'PIT Done',
              'level': 'PIT',
              'year_level': '1st Year',
              'completed_stages': ['Design Expo'],
            },
            {
              'id': 3,
              'name': 'PIT Scheduled',
              'level': 'PIT',
              'year_level': '1st Year',
            },
            {'id': 4, 'name': 'Capstone Team', 'level': 'Capstone'},
          ],
          schedules: [
            {'team_id': 2, 'event_name': 'Design Expo', 'status': 'done'},
            {'team_id': 3, 'event_name': 'Design Expo', 'status': 'scheduled'},
          ],
        ),
      )..panelists = {101};
      await _pump(tester, fixture, scope: 'pit');
      await _open(tester, find.byKey(const ValueKey('choose-schedule-teams')));
      expect(find.text('PIT Ready'), findsOneWidget);
      expect(find.text('PIT Done'), findsNothing);
      expect(find.text('PIT Scheduled'), findsNothing);
      expect(find.text('Capstone Team'), findsNothing);
      await tester.tap(find.text('Select shown teams'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apply-session-teams')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('fill-schedule-sessions')),
      );
      await tester.tap(find.byKey(const ValueKey('fill-schedule-sessions')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Generate plan'));
      await tester.tap(find.text('Generate plan'));
      await tester.pumpAndSettle();
      expect(fixture.scheduler.payload!['scope'], 'pit');
      expect(fixture.scheduler.payload!['event_name'], 'Design Expo');
      expect(
        (fixture.scheduler.payload!['sessions'] as List).single['team_ids'],
        [1],
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    for (final width in [390.0, 1280.0]) {
      testWidgets(
        'multi-day allocation, moving and confirmation at $width ${dark ? 'dark' : 'light'}',
        (tester) async {
          final fixture = _Fixture()..panelists = {101, 102};
          fixture.scheduler.generated = [
            _sessionSlot(1, 'session-1'),
            _sessionSlot(2, 'session-2'),
            {..._sessionSlot(3, null), 'requested_session_key': 'session-1'},
          ];
          await _pump(tester, fixture, width: width, dark: dark);
          final first = _draft(tester)..teamIds = {1, 3};
          first.end.text = '09:00';
          await _open(
            tester,
            find.byKey(const ValueKey('edit-time-blocks-session-1')),
          );
          await tester.ensureVisible(find.text('Remove'));
          await tester.tap(find.text('Remove'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('save-time-blocks-session-1')),
          );
          await tester.tap(
            find.byKey(const ValueKey('save-time-blocks-session-1')),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Add session'));
          await tester.tap(find.text('Add session'));
          await tester.pumpAndSettle();
          expect(find.byType(SchedulerSessionEditor), findsNWidgets(2));
          _draft(tester, 1).teamIds = {2};
          // Simulate a server response that leaves a requested team unassigned.
          first.teamIds = {1, 3};
          expect(
            tester
                .widget<SchedulerSessionEditor>(
                  find.byType(SchedulerSessionEditor).last,
                )
                .draft
                .date
                .text,
            '2026-10-04',
          );
          await tester.ensureVisible(find.text('Generate plan'));
          await tester.tap(find.text('Generate plan'));
          await tester.pumpAndSettle();
          expect(find.text('Unassigned teams'), findsOneWidget);
          expect(find.text('2 assigned · 1 remaining'), findsOneWidget);
          expect(
            tester
                .widget<ElevatedButton>(
                  find.ancestor(
                    of: find.text('Proceed to Final Preview'),
                    matching: find.byWidgetPredicate(
                      (widget) => widget is ElevatedButton,
                    ),
                  ),
                )
                .onPressed,
            isNull,
          );
          await _captureSessions(
            tester,
            'sessions-arrange-${dark ? 'dark' : 'light'}-${width.toInt()}',
          );
          final removeSecond = find.byTooltip('Remove slot').at(1);
          await tester.ensureVisible(removeSecond);
          await tester.tap(removeSecond);
          await tester.pumpAndSettle();
          final move = find.byKey(const ValueKey('move-team-3'));
          await tester.ensureVisible(move);
          await tester.tap(move);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Session 2 · 2026-10-04 · 08:00'));
          await tester.pumpAndSettle();
          expect(find.text('Unassigned teams'), findsNothing);
          expect(fixture.slots.last['scheduled_date'], '2026-10-04');
          expect(fixture.slots.last['start_time'], '08:00');
          await tester.ensureVisible(find.text('Proceed to Final Preview'));
          await tester.tap(find.text('Proceed to Final Preview'));
          await tester.pumpAndSettle();
          expect(find.text('Step 3: Final Schedule Preview'), findsOneWidget);
          await _captureSessions(
            tester,
            'sessions-review-${dark ? 'dark' : 'light'}-${width.toInt()}',
          );
          await tester.ensureVisible(find.text('Publish & Save Schedule'));
          await tester.tap(find.text('Publish & Save Schedule'));
          await tester.pumpAndSettle();
          final payload = fixture.scheduler.confirmation!;
          expect((payload['sessions'] as List).length, 2);
          expect((payload['sessions'] as List).first['team_ids'], [1]);
          expect((payload['sessions'] as List).last['team_ids'], [3]);
          final slots = payload['slots'] as List;
          expect(slots.map((s) => s['session_key']), [
            'session-1',
            'session-2',
          ]);
          expect(slots.last['scheduled_date'], '2026-10-04');
          expect(slots.last['start_time'], fixture.slots.last['start_time']);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('dragging reorders only teams within their own session', (
    tester,
  ) async {
    final fixture = _Fixture()..panelists = {101};
    fixture.scheduler.generated = [
      _sessionSlot(1, 'session-1'),
      _sessionSlot(2, 'session-1'),
      _sessionSlot(3, 'session-2'),
    ];
    await _pump(tester, fixture);
    _draft(tester).teamIds = {1, 2};
    await tester.ensureVisible(find.text('Add session'));
    await tester.tap(find.text('Add session'));
    await tester.pumpAndSettle();
    _draft(tester, 1).teamIds = {3};
    await tester.ensureVisible(find.text('Generate plan'));
    await tester.tap(find.text('Generate plan'));
    await tester.pumpAndSettle();
    final handle = find.byTooltip('Drag to reorder team').first;
    await tester.ensureVisible(handle);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 160));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fixture.slots.map((slot) => slot['team_id']), [2, 1, 3]);
    expect(fixture.slots[0]['start_time'], '08:00');
    expect(fixture.slots[1]['start_time'], '09:00');
    expect(fixture.slots[2]['scheduled_date'], '2026-10-04');
    expect(fixture.slots[2]['start_time'], '08:00');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('session staff overrides remain distinct from shared defaults', (
    tester,
  ) async {
    final fixture = _Fixture()..panelists = {101, 102};
    await _pump(tester, fixture);
    _draft(tester).teamIds = {1};
    await tester.ensureVisible(find.text('Add session'));
    await tester.tap(find.text('Add session'));
    await tester.pumpAndSettle();
    final editor = find.byType(SchedulerSessionEditor).last;
    final customize = find.descendant(
      of: editor,
      matching: find.text('Customize staff for this session'),
    );
    await tester.ensureVisible(customize);
    await tester.tap(customize);
    await tester.pumpAndSettle();
    final remove = find
        .descendant(
          of: editor,
          matching: find.byTooltip('Remove Teresita Buenaventura'),
        )
        .first;
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Generate plan'));
    await tester.tap(find.text('Generate plan'));
    await tester.pumpAndSettle();
    final payload = fixture.scheduler.payload!;
    expect(payload['panelist_ids'], [101, 102]);
    final sessions = payload['sessions'] as List;
    expect(sessions.first.containsKey('panelist_ids'), isFalse);
    expect(sessions.last['panelist_ids'], [101]);
    expect(sessions.last['chair_panelist_id'], 101);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search, chair changes and removal preserve schedule payload', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _pump(tester, fixture);
    _draft(tester).teamIds = {1};
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
    final base = _Fixture().state;
    final fixture = _Fixture(
      initialState: base.copyWith(
        defenseStages: [
          {...base.defenseStages.single, 'minutes_required': true},
        ],
      ),
    );
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
      _draft(tester).teamIds = {1};
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
