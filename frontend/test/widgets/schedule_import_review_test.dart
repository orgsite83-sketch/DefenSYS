import 'dart:convert';

import 'package:defensys/screens/web/admin/defense_board/components/defense_schedule_bulk_import_view.dart';
import 'package:defensys/screens/web/admin/defense_board/components/schedule_import_review_widgets.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:defensys/utils/import/schedule_import_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _stage = 'Concept Proposal';

class _Scheduler extends DefenseSchedulerNotifier {
  _Scheduler(this.fixture, {this.failedIndex});

  final DefenseSchedulerState fixture;
  final int? failedIndex;
  final imports = <List<Map<String, dynamic>>>[];

  @override
  DefenseSchedulerState build() => fixture;

  @override
  Future<Map<String, dynamic>> importSchedules(
    List<Map<String, dynamic>> payloads,
  ) async {
    imports.add(payloads);
    final successes = [
      for (var i = 0; i < payloads.length; i++)
        if (i != failedIndex) i,
    ];
    return {
      'created': successes.length,
      'imported_indices': successes,
      'errors': failedIndex == null ? <String>[] : ['Row 2: Room unavailable'],
    };
  }
}

class _Stages extends DefenseStagesNotifier {
  @override
  DefenseStagesState build() => DefenseStagesState();

  @override
  Future<Map<String, dynamic>?> fetchStageDetail(
    int stageId, {
    int? semesterId,
  }) async => {
    'grading_config': {
      'panel_rubric_id': 1,
      'adviser_rubric_id': 2,
      'peer_rubric_id': 3,
      'panel_rubric_name': 'CP Panel',
      'adviser_rubric_name': 'CP Adviser',
      'peer_rubric_name': 'CP Peer',
    },
  };
}

({ScheduleImportDraft draft, DefenseSchedulerState state}) _fixture({
  int count = 16,
  bool unknownLastTeam = false,
}) {
  final rows = [
    for (var i = 0; i < count; i++)
      ParsedScheduleImportRow(
        sheetRow: i + 5,
        time:
            '${8 + (i % 4) ~/ 2}:${i.isEven ? '00' : '30'} - ${8 + ((i % 4) + 1) ~/ 2}:${i.isEven ? '30' : '00'}',
        teamName: 'Team ${i + 1}',
        projectTitle: 'Project ${i + 1}',
        adviser: 'Ricardo Fontanilla',
        members: const [],
        chair: 'Maricel Suarez',
        panelMembers: const ['Jonathan Beltran'],
        documenter: 'Cecilia Magbanua',
        room: i < 8 ? 'Room 301' : 'Room 302',
        date: i % 8 < 4 ? '2026-10-20' : '2026-10-21',
        stage: _stage,
        startTime: '${8 + (i % 4) ~/ 2}:${i.isEven ? '00' : '30'}',
        endTime: '${8 + ((i % 4) + 1) ~/ 2}:${i.isEven ? '30' : '00'}',
        slotDuration: 30,
      ),
  ];
  return (
    draft: ScheduleImportDraft(
      parsed: ParsedScheduleImport(stage: _stage, rows: rows),
      scope: 'capstone',
      fileName: 'defense_schedule.xlsx',
      stageId: 10,
      duration: '30',
      date: '2026-10-20',
      panelRubricId: 1,
      adviserRubricId: 2,
      peerRubricId: 3,
      savedAt: DateTime(2026, 10, 20, 0, 53),
    ),
    state: DefenseSchedulerState(
      activeSemester: const {
        'id': 1,
        'display_name': '1st Semester, A.Y. 2026-2027',
      },
      defenseStages: const [
        {'id': 10, 'label': _stage},
      ],
      faculty: const [
        {'id': 101, 'name': 'Maricel Suarez', 'username': 'msuarez'},
        {'id': 102, 'name': 'Jonathan Beltran', 'username': 'jbeltran'},
        {'id': 103, 'name': 'Ricardo Fontanilla', 'username': 'rfontanilla'},
        {'id': 104, 'name': 'Cecilia Magbanua', 'username': 'cmagbanua'},
      ],
      teams: [
        for (var i = 0; i < count - (unknownLastTeam ? 1 : 0); i++)
          {
            'id': i + 1,
            'name': 'Team ${i + 1}',
            'project_title': 'Project ${i + 1}',
            'level': 'Capstone 1',
            'ready_for_stage': _stage,
            'completed_stages': <String>[],
            'scheduled_stages': <String>[],
            'redefense_stages': <String>[],
          },
      ],
    ),
  );
}

Future<_Scheduler> _pumpReview(
  WidgetTester tester, {
  int count = 16,
  bool unknownLastTeam = false,
  int? failedIndex,
  Size size = const Size(1600, 1000),
  bool dark = false,
  VoidCallback? onBack,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fixture = _fixture(count: count, unknownLastTeam: unknownLastTeam);
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({
    'defense_schedule_import_draft_capstone': jsonEncode(
      fixture.draft.toJson(),
    ),
  });
  final scheduler = _Scheduler(fixture.state, failedIndex: failedIndex);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        defenseSchedulerProvider.overrideWith(() => scheduler),
        defenseStagesProvider.overrideWith(_Stages.new),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
        home: Scaffold(
          body: DefenseScheduleBulkImportView(
            scope: 'capstone',
            initialStageId: 10,
            onBack: onBack ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return scheduler;
}

void main() {
  testWidgets(
    'restored review keeps actions visible while scrolling and uses counted filters',
    (tester) async {
      await _pumpReview(tester);
      expect(find.text('Replace file'), findsOneWidget);
      expect(find.text('View format guide'), findsOneWidget);
      expect(find.text('All (16)'), findsOneWidget);
      expect(find.text('Needs attention (0)'), findsOneWidget);
      expect(find.text('All fields verified'), findsNothing);
      expect(find.text('Import 16 slots'), findsOneWidget);
      expect(find.text('View Sheet Layout Blueprint'), findsNothing);
      final importButton = find.text('Import 16 slots');
      final position = tester.getCenter(importButton);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      expect(tester.getCenter(importButton), position);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('filters preserve overall import counts and can be reset', (
    tester,
  ) async {
    await _pumpReview(tester, count: 3, unknownLastTeam: true);
    expect(find.text('Needs attention (1)'), findsOneWidget);
    await tester.tap(find.text('Needs attention (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Team 3'), findsOneWidget);
    expect(find.text('Team 1'), findsNothing);
    expect(find.text('Import 2 slots'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Team 1'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'no such team');
    await tester.pumpAndSettle();
    expect(find.text('No matching schedule slots'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Team 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'sessions collapse and date/room changes are persisted for every session row',
    (tester) async {
      await _pumpReview(tester, count: 3);
      await tester.tap(find.text('Collapse all'));
      await tester.pumpAndSettle();
      expect(find.text('Team 1'), findsNothing);
      await tester.tap(find.byTooltip('Expand session 1'));
      await tester.pumpAndSettle();
      expect(find.text('Team 1'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Team 1');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit session'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextFormField, 'Session date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('22').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Room / venue'),
        'Auditorium',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final draft = await loadScheduleImportDraft(scope: 'capstone');
      expect(
        draft!.parsed.rows.every((row) => row.room == 'Auditorium'),
        isTrue,
      );
      expect(
        draft.parsed.rows.every((row) => row.date == '2026-10-22'),
        isTrue,
      );
      expect(find.textContaining('Auditorium ·'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'partial import retains excluded rows and does not reimport successful slots',
    (tester) async {
      var returnedToBoard = false;
      final scheduler = await _pumpReview(
        tester,
        count: 3,
        unknownLastTeam: true,
        onBack: () => returnedToBoard = true,
      );
      await tester.tap(find.text('Import 2 slots'));
      await tester.pumpAndSettle();
      expect(find.text('Import 2 ready slots?'), findsOneWidget);
      expect(scheduler.imports, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(scheduler.imports, isEmpty);
      await tester.tap(find.text('Import 2 slots'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import 2 slots').last);
      await tester.pumpAndSettle();
      expect(scheduler.imports.single, hasLength(2));
      expect(returnedToBoard, isFalse);
      final draft = await loadScheduleImportDraft(scope: 'capstone');
      expect(draft!.parsed.rows.map((row) => row.teamName), ['Team 3']);
      expect(
        find.text('Imported 2 slots. 1 slot remains in your draft.'),
        findsOneWidget,
      );
      expect(find.text('Import 0 slots'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('server failures retain only failed rows for a safe retry', (
    tester,
  ) async {
    final scheduler = await _pumpReview(tester, count: 3, failedIndex: 1);
    await tester.tap(find.text('Import 3 slots'));
    await tester.pumpAndSettle();
    expect(scheduler.imports.single, hasLength(3));
    final draft = await loadScheduleImportDraft(scope: 'capstone');
    expect(draft!.parsed.rows.map((row) => row.teamName), ['Team 2']);
    expect(find.text('Import 1 slot'), findsOneWidget);
    expect(find.text('Row 2: Room unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('complete import clears its draft and returns to the board', (
    tester,
  ) async {
    var returnedToBoard = false;
    await _pumpReview(tester, count: 3, onBack: () => returnedToBoard = true);
    await tester.tap(find.text('Import 3 slots'));
    await tester.pumpAndSettle();
    expect(returnedToBoard, isTrue);
    expect(await loadScheduleImportDraft(scope: 'capstone'), isNull);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'date and room filters combine and reset without changing import counts',
    (tester) async {
      await _pumpReview(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oct 21, 2026').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Room 302').last);
      await tester.pumpAndSettle();
      expect(find.text('Team 13'), findsOneWidget);
      expect(find.text('Team 1'), findsNothing);
      expect(find.text('Import 16 slots'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('All dates'), findsOneWidget);
      expect(find.text('All rooms'), findsOneWidget);
      expect(find.text('Team 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('narrow review and editor fit without overflow', (tester) async {
    await _pumpReview(tester, count: 3, size: const Size(600, 900));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Edit session'));
    await tester.tap(find.text('Edit session'));
    await tester.pumpAndSettle();
    expect(find.text('Room / venue'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'dark review uses theme surfaces and dismissing recovery keeps the draft',
    (tester) async {
      await _pumpReview(tester, count: 3, dark: true);
      expect(find.byType(ScheduleImportSessionCard), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss draft notification'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Draft restored.'), findsNothing);
      expect(await loadScheduleImportDraft(scope: 'capstone'), isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('partial import confirmation uses readable dark theme text', (
    tester,
  ) async {
    await _pumpReview(tester, count: 3, unknownLastTeam: true, dark: true);
    await tester.tap(find.text('Import 2 slots'));
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('Import 2 ready slots?'));
    expect(title.style!.color, DefensysTokens.mistTextPrimary);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
