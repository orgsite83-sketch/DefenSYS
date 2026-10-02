import 'dart:convert';
import 'dart:typed_data';

import 'package:defensys/screens/web/admin/defense_board/components/defense_schedule_bulk_import_view.dart';
import 'package:defensys/screens/web/admin/defense_board/components/schedule_import_review_widgets.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:defensys/utils/import/schedule_import_draft.dart';
import 'package:defensys/utils/import/schedule_import_workspace.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _stage = 'Concept Proposal';

class _Picker extends FilePicker {
  final results = <FilePickerResult?>[];
  final multiple = <bool>[];
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    multiple.add(allowMultiple);
    return results.removeAt(0);
  }
}

PlatformFile _csv(String name, int team, String time, {String stage = _stage}) {
  final bytes = Uint8List.fromList(
    utf8.encode(
      'Stage,Date,Room,Time,Team Name,Capstone Project,Adviser,Chair,Panel Member 1,Documenter\n'
      '$stage,2026-10-20,Room 301,$time,Team $team,Project $team,Ricardo Fontanilla,Maricel Suarez,Jonathan Beltran,Cecilia Magbanua\n',
    ),
  );
  return PlatformFile(name: name, size: bytes.length, bytes: bytes);
}

class _Scheduler extends DefenseSchedulerNotifier {
  _Scheduler(
    this.fixture, {
    this.failedIndex,
    this.conflictSchedules,
    this.validationFailure = false,
  });

  final DefenseSchedulerState fixture;
  final int? failedIndex;
  final List<Map<String, dynamic>>? conflictSchedules;
  final bool validationFailure;
  var conflictReads = 0;
  final imports = <List<Map<String, dynamic>>>[];

  @override
  DefenseSchedulerState build() => fixture;

  @override
  Future<List<Map<String, dynamic>>> fetchImportConflictSchedules() async {
    conflictReads++;
    if (validationFailure) throw Exception('Network unavailable');
    return [...(conflictSchedules ?? fixture.schedules)];
  }

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
        adviser: i < 8 ? 'Ricardo Fontanilla' : 'Andrea Santos',
        members: const [],
        chair: i < 8 ? 'Maricel Suarez' : 'Renato Villanueva',
        panelMembers: i < 8
            ? const ['Jonathan Beltran']
            : const ['Analiza Corpuz'],
        documenter: i < 8 ? 'Cecilia Magbanua' : 'Maria Reyes',
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
        {'id': 105, 'name': 'Renato Villanueva', 'username': 'rvillanueva'},
        {'id': 106, 'name': 'Analiza Corpuz', 'username': 'acorpuz'},
        {'id': 107, 'name': 'Maria Reyes', 'username': 'mreyes'},
        {'id': 108, 'name': 'Andrea Santos', 'username': 'asantos'},
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
  List<Map<String, dynamic>>? conflictSchedules,
  bool validationFailure = false,
  Size size = const Size(1600, 1000),
  bool dark = false,
  VoidCallback? onBack,
  bool seedDraft = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fixture = _fixture(count: count, unknownLastTeam: unknownLastTeam);
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({
    if (seedDraft)
      'defense_schedule_import_draft_capstone': jsonEncode(
        fixture.draft.toJson(),
      ),
  });
  final scheduler = _Scheduler(
    fixture.state,
    failedIndex: failedIndex,
    conflictSchedules: conflictSchedules,
    validationFailure: validationFailure,
  );
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

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openSettings(WidgetTester tester) async {
  await _tap(tester, find.text('Settings'));
  await tester.pumpAndSettle();
}

Future<void> _allDuration(
  WidgetTester tester,
  String value, {
  bool save = true,
}) async {
  await _openSettings(tester);
  await _tap(tester, find.byKey(const ValueKey('stage_schedule_scope')));
  await tester.pumpAndSettle();
  await _tap(tester, find.textContaining('All slots ·').last);
  await tester.pumpAndSettle();
  await _tap(tester, find.byKey(const ValueKey('set_duration')));
  await tester.enterText(
    find.byKey(const ValueKey('schedule_duration')),
    value,
  );
  if (save) await _tap(tester, find.text('Save settings'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'session count previews regrouping, closes without saving, and applies once',
    (tester) async {
      await _pumpReview(tester, count: 16);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final original = (await loadScheduleImportDraft(
        scope: 'capstone',
      ))!.parsed.toJson();
      await _openSettings(tester);
      await _tap(tester, find.byKey(const ValueKey('settings_sessions_tab')));
      expect(find.text('16 teams · 30 minutes per team'), findsOneWidget);
      expect(find.text('4 teams in each session'), findsOneWidget);
      expect(find.text('Update sessions'), findsNothing);
      expect(find.text('Auto-sequence'), findsNothing);
      expect(find.text('Teams / slots'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('session_count')));
      await _tap(tester, find.text('3').last);
      expect(find.text('6 + 5 + 5 teams across 3 sessions'), findsOneWidget);
      expect(
        (await loadScheduleImportDraft(scope: 'capstone'))!.parsed.toJson(),
        original,
      );
      await _tap(tester, find.byTooltip('Close settings'));
      expect(
        (await loadScheduleImportDraft(scope: 'capstone'))!.parsed.toJson(),
        original,
      );
      await _openSettings(tester);
      await _tap(tester, find.byKey(const ValueKey('settings_sessions_tab')));
      await _tap(tester, find.byKey(const ValueKey('session_count')));
      await _tap(tester, find.text('3').last);
      await _tap(tester, find.text('Apply session plan'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final draft = (await loadScheduleImportDraft(scope: 'capstone'))!;
      expect(
        scheduleImportSessionGroups(
          draft.parsed.rows,
        ).map((group) => group.length),
        [6, 5, 5],
      );
      expect(
        draft.parsed.rows.map((row) => row.importRowId).toSet().length,
        16,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a single team has one session and no two-session preset', (
    tester,
  ) async {
    await _pumpReview(tester, count: 1);
    await _openSettings(tester);
    await _tap(tester, find.byKey(const ValueKey('settings_sessions_tab')));
    expect(find.text('1 team in each session'), findsOneWidget);
    expect(find.text('Quick setup'), findsNothing);
    expect(find.text('Use these two sessions'), findsNothing);
    expect(
      tester
          .widget<DropdownButton<int>>(
            find.byKey(const ValueKey('session_count')),
          )
          .items,
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
    await _tap(tester, find.byTooltip('Close settings'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'multiple files combine and replacement preserves other source edits',
    (tester) async {
      final picker = _Picker();
      FilePicker.platform = picker;
      picker.results.add(
        FilePickerResult([
          _csv('morning.csv', 1, '8:00AM-8:30AM'),
          _csv('afternoon.csv', 2, '1:00PM-1:30PM'),
        ]),
      );
      await _pumpReview(tester, count: 6, seedDraft: false);
      await _tap(tester, find.textContaining('Click to choose timetable'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      var draft = (await loadScheduleImportDraft(scope: 'capstone'))!;
      expect(draft.files.map((file) => file.name), [
        'morning.csv',
        'afternoon.csv',
      ]);
      expect(find.text('Import 2 slots'), findsOneWidget);
      expect(picker.multiple, [true]);
      await _openSettings(tester);
      await _tap(tester, find.byKey(const ValueKey('stage_schedule_scope')));
      await _tap(tester, find.text('afternoon.csv · 1 slots').last);
      await _tap(tester, find.byKey(const ValueKey('set_room')));
      await tester.enterText(
        find.byKey(const ValueKey('schedule_room')),
        'Afternoon hall',
      );
      await _tap(tester, find.text('Save settings'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      draft = (await loadScheduleImportDraft(scope: 'capstone'))!;
      final afternoon = draft.files.last.toJson();
      expect(draft.files.last.parsed.rows.single.room, 'Afternoon hall');
      expect(draft.files.first.parsed.rows.single.room, 'Room 301');
      picker.results.add(
        FilePickerResult([_csv('new-morning.csv', 3, '9:00AM-9:30AM')]),
      );
      await _tap(tester, find.text('Replace').first);
      await _tap(tester, find.text('Choose replacement'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      draft = (await loadScheduleImportDraft(scope: 'capstone'))!;
      expect(draft.files.first.name, 'new-morning.csv');
      expect(draft.files.first.parsed.rows.single.teamName, 'Team 3');
      expect(draft.files.last.toJson(), afternoon);
      expect(picker.multiple, [true, false]);
      // Cancelling replacement leaves the full combined draft untouched.
      final snapshot = draft.parsed.toJson();
      picker.results.add(null);
      await _tap(tester, find.text('Replace all'));
      await _tap(tester, find.text('Choose replacement'));
      expect(
        (await loadScheduleImportDraft(scope: 'capstone'))!.parsed.toJson(),
        snapshot,
      );
      picker.results.add(
        FilePickerResult([_csv('replacement.csv', 4, '2:00PM-2:30PM')]),
      );
      await _tap(tester, find.text('Replace all'));
      await _tap(tester, find.text('Choose replacement'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      draft = (await loadScheduleImportDraft(scope: 'capstone'))!;
      expect(draft.files.single.name, 'replacement.csv');
      expect(draft.parsed.rows.single.teamName, 'Team 4');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'adding a file preserves edits and duplicate teams block import',
    (tester) async {
      final picker = _Picker();
      FilePicker.platform = picker;
      await _pumpReview(tester, count: 2);
      await _allDuration(tester, '45');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final original = (await loadScheduleImportDraft(
        scope: 'capstone',
      ))!.parsed.rows.map((row) => row.toJson()).toList();
      // Malformed batches preserve the draft and do not append valid siblings.
      picker.results.add(
        FilePickerResult([
          _csv('valid.csv', 2, '1:00PM-1:30PM'),
          PlatformFile(name: 'unreadable.csv', size: 10),
        ]),
      );
      await _tap(tester, find.text('Add files'));
      expect(
        (await loadScheduleImportDraft(
          scope: 'capstone',
        ))!.parsed.rows.map((row) => row.toJson()).toList(),
        original,
      );
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      picker.results.add(
        FilePickerResult([_csv('duplicate.csv', 1, '1:00PM-1:30PM')]),
      );
      await _tap(tester, find.text('Add files'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final draft = (await loadScheduleImportDraft(scope: 'capstone'))!;
      expect(
        draft.parsed.rows.take(2).map((row) => row.toJson()).toList(),
        original,
      );
      expect(find.text('Needs attention (2)'), findsOneWidget);
      expect(find.text('Import 1 slot'), findsOneWidget);
      expect(find.textContaining('Duplicate team in this draft'), findsWidgets);
      await _tap(tester, find.byTooltip('Remove duplicate.csv'));
      await _tap(tester, find.text('Remove file'));
      expect(
        (await loadScheduleImportDraft(scope: 'capstone'))!.files.single.name,
        'defense_schedule.xlsx',
      );
      expect(find.text('Import 2 slots'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'uneven morning and afternoon sessions preserve all imported teams',
    (tester) async {
      await _pumpReview(tester, count: 16);
      await _openSettings(tester);
      await _tap(tester, find.byKey(const ValueKey('settings_sessions_tab')));
      await _tap(tester, find.text('Use these two sessions'));
      await _tap(tester, find.byKey(const ValueKey('session_0_card')));
      await _tap(tester, find.byKey(const ValueKey('session_1_card')));
      await tester.enterText(
        find.byKey(const ValueKey('session_0_teams')),
        '5',
      );
      await tester.pumpAndSettle();
      expect(find.text('3 teams still need a session.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('session_1_teams')),
        '11',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Apply session plan'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final draft = (await loadScheduleImportDraft(scope: 'capstone'))!;
      expect(draft.parsed.rows[4].endTime, '10:30');
      expect(draft.parsed.rows[5].startTime, '13:00');
      expect(draft.parsed.rows.last.endTime, '18:30');
      expect(draft.parsed.rows.map((row) => row.teamName).toSet().length, 16);
      expect(find.byType(ScheduleImportSessionCard), findsNWidgets(2));
      expect(
        find.text('Committee varies by team · See assignments below'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'appointments added during review are checked before any import writes',
    (tester) async {
      final appointments = <Map<String, dynamic>>[];
      final scheduler = await _pumpReview(
        tester,
        count: 1,
        conflictSchedules: appointments,
      );
      appointments.add({
        'status': 'scheduled',
        'scheduled_date': '2026-10-20',
        'start_time': '08:00:00',
        'slot_duration': 30,
        'room': 'Room 301',
        'team_name': 'New Appointment',
      });
      await _tap(tester, find.text('Import 1 slot'));
      await tester.pumpAndSettle();
      expect(scheduler.imports, isEmpty);
      expect(scheduler.conflictReads, 2);
      expect(find.text('Import 0 slots'), findsOneWidget);
      expect(
        find.textContaining('The schedule changed during review.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'centralized duration edits are scoped, cancellable, and persisted',
    (tester) async {
      await _pumpReview(tester, count: 4);
      await _allDuration(tester, '60', save: false);
      await _tap(tester, find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('8:30–9:00 AM'), findsOneWidget);
      await _allDuration(tester, '60');
      expect(find.text('9:00–10:00 AM'), findsOneWidget);
      expect(find.text('11:00 AM–12:00 PM'), findsOneWidget);
      expect(find.text('Needs attention (0)'), findsOneWidget);
      expect(find.text('Issues / notices'), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final draft = await loadScheduleImportDraft(scope: 'capstone');
      expect(draft!.reflowStartTimes, isFalse);
      expect(draft.parsed.rows[1].startTime, '09:00');
      expect(draft.parsed.rows[1].slotDuration, 60);
      expect(draft.files.single.parsed.rows[1].startTime, '09:00');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'invalid duration and overlapping session plans cannot be applied',
    (tester) async {
      await _pumpReview(tester, count: 8);
      await _allDuration(tester, '241');
      expect(find.text('Enter 15 to 240 minutes'), findsOneWidget);
      await _tap(tester, find.text('Cancel'));
      await tester.pumpAndSettle();
      await _openSettings(tester);
      await _tap(tester, find.byKey(const ValueKey('settings_sessions_tab')));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('session_1_card')));
      await tester.enterText(
        find.byKey(const ValueKey('session_1_date')),
        '2026-10-20',
      );
      await tester.enterText(
        find.byKey(const ValueKey('session_1_start')),
        '09:00',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Session 2 starts before Session 1 ends.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Apply session plan'),
            )
            .onPressed,
        isNull,
      );
      await _tap(tester, find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      expect(find.text('Needs attention (0)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('failed imports retain adjusted times for a safe retry', (
    tester,
  ) async {
    final scheduler = await _pumpReview(tester, count: 3, failedIndex: 1);
    await _allDuration(tester, '60');
    await _tap(tester, find.text('Import 3 slots'));
    await tester.pumpAndSettle();
    expect(scheduler.imports.single[1]['start_time'], '09:00');
    final draft = await loadScheduleImportDraft(scope: 'capstone');
    expect(draft!.parsed.rows.single.startTime, '09:00');
    expect(draft.parsed.rows.single.endTime, '10:00');
    expect(draft.reflowStartTimes, isFalse);
    expect(find.text('9:00–10:00 AM'), findsOneWidget);
    await _tap(tester, find.text('Import 1 slot'));
    await tester.pumpAndSettle();
    expect(scheduler.imports.last.single['start_time'], '09:00');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('validation checks appointments hidden by board filters', (
    tester,
  ) async {
    await _pumpReview(
      tester,
      count: 1,
      conflictSchedules: [
        {
          'status': 'scheduled',
          'scheduled_date': '2026-10-20',
          'start_time': '08:00:00',
          'slot_duration': 30,
          'room': 'Room 301',
          'team_id': 99,
          'team_name': 'Published Team',
        },
      ],
    );
    expect(find.text('Import 0 slots'), findsOneWidget);
    expect(find.textContaining('scheduled Published Team'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed availability checks disable import and offer retry', (
    tester,
  ) async {
    final scheduler = await _pumpReview(
      tester,
      count: 1,
      validationFailure: true,
    );
    expect(find.text('Schedule validation unavailable'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find
          .ancestor(
            of: find.text('Import 1 slot'),
            matching: find.byWidgetPredicate(
              (widget) => widget is ElevatedButton,
            ),
          )
          .first,
    );
    expect(button.onPressed, isNull);
    await _tap(tester, find.text('Retry validation'));
    await tester.pumpAndSettle();
    expect(scheduler.conflictReads, 2);
    expect(scheduler.imports, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'specification and upload remain above the stage review on the same page',
    (tester) async {
      await _pumpReview(tester);
      expect(find.text('Replace'), findsOneWidget);
      expect(
        find.text('Official Capstone Timetable Specification'),
        findsOneWidget,
      );
      expect(find.text('Upload Defense Spreadsheet'), findsOneWidget);
      expect(find.text('All (16)'), findsOneWidget);
      expect(find.text('Needs attention (0)'), findsOneWidget);
      expect(find.text('All fields verified'), findsNothing);
      expect(find.text('Import 16 slots'), findsOneWidget);
      expect(find.text('View Sheet Layout Blueprint'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Edit session'), findsNothing);
      expect(find.text('Review & Resolve'), findsNothing);
      final importButton = find.text('Import 16 slots');
      final position = tester.getCenter(importButton);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      expect(tester.getCenter(importButton).dy, lessThan(position.dy));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('filters preserve overall import counts and can be reset', (
    tester,
  ) async {
    await _pumpReview(tester, count: 3, unknownLastTeam: true);
    expect(find.text('Needs attention (1)'), findsOneWidget);
    await _tap(tester, find.text('Needs attention (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Team 3'), findsOneWidget);
    expect(find.text('Team 1'), findsNothing);
    expect(find.text('Import 2 slots'), findsOneWidget);
    await _tap(tester, find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Team 1'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'no such team');
    await tester.pumpAndSettle();
    expect(find.text('No matching schedule slots'), findsOneWidget);
    await _tap(tester, find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Team 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'sessions collapse and date/room changes are persisted for every session row',
    (tester) async {
      await _pumpReview(tester, count: 3);
      await _tap(tester, find.text('Collapse all'));
      await tester.pumpAndSettle();
      expect(find.text('Team 1'), findsNothing);
      await _tap(tester, find.byTooltip('Expand session 1'));
      await tester.pumpAndSettle();
      expect(find.text('Team 1'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Team 1');
      await tester.pumpAndSettle();
      await _openSettings(tester);
      await _tap(tester, find.byKey(const ValueKey('settings_sessions_tab')));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('session_0_card')));
      await tester.enterText(
        find.byKey(const ValueKey('session_0_date')),
        '2026-10-22',
      );
      await tester.enterText(
        find.byKey(const ValueKey('session_0_room')),
        'Auditorium',
      );
      await _tap(tester, find.text('Apply session plan'));
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
      await _tap(tester, find.text('Import 2 slots'));
      await tester.pumpAndSettle();
      expect(find.text('Import 2 ready slots?'), findsOneWidget);
      expect(scheduler.imports, isEmpty);
      await _tap(tester, find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(scheduler.imports, isEmpty);
      await _tap(tester, find.text('Import 2 slots'));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Import 2 slots').last);
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
    await _tap(tester, find.text('Import 3 slots'));
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
    await _tap(tester, find.text('Import 3 slots'));
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
      await _tap(tester, find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Oct 21, 2026').last);
      await tester.pumpAndSettle();
      await _tap(tester, find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Room 302').last);
      await tester.pumpAndSettle();
      expect(find.text('Team 13'), findsOneWidget);
      expect(find.text('Team 1'), findsNothing);
      expect(find.text('Import 16 slots'), findsOneWidget);
      await _tap(tester, find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('All dates'), findsOneWidget);
      expect(find.text('All rooms'), findsOneWidget);
      expect(find.text('Team 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [600.0, 375.0, 320.0]) {
    testWidgets('review and settings fit at width $width without overflow', (
      tester,
    ) async {
      await _pumpReview(tester, count: 3, size: Size(width, 900));
      expect(tester.takeException(), isNull);
      await _openSettings(tester);
      expect(find.text('Set room / venue'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('settings_sessions_tab')));
      await tester.pumpAndSettle();
      expect(find.text('How many sessions?'), findsOneWidget);
      expect(find.text('Teams / slots'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('session_0_card')));
      expect(find.text('Teams / slots'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'dark review uses theme surfaces and dismissing recovery keeps the draft',
    (tester) async {
      await _pumpReview(tester, count: 3, dark: true);
      expect(find.byType(ScheduleImportSessionCard), findsOneWidget);
      await _tap(tester, find.byTooltip('Dismiss draft notice'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved draft restored.'), findsNothing);
      expect(await loadScheduleImportDraft(scope: 'capstone'), isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('partial import confirmation uses readable dark theme text', (
    tester,
  ) async {
    await _pumpReview(tester, count: 3, unknownLastTeam: true, dark: true);
    await _tap(tester, find.text('Import 2 slots'));
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('Import 2 ready slots?'));
    expect(title.style!.color, DefensysTokens.mistTextPrimary);
    await _tap(tester, find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'settings pre-fills imported values and session overlap offers a specific fix',
    (tester) async {
      await _pumpReview(tester, count: 16);
      await _openSettings(tester);

      // Verify date and room controllers have pre-filled grayed text
      final dateField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('schedule_date')),
      );
      expect(dateField.controller?.text, '2026-10-20');
      final roomField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('schedule_room')),
      );
      expect(roomField.controller?.text, 'Room 301');

      // Switch to sessions and create 2 sessions
      await _tap(tester, find.byKey(const ValueKey('settings_sessions_tab')));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Use these two sessions'));
      await _tap(tester, find.byKey(const ValueKey('session_0_card')));
      await _tap(tester, find.byKey(const ValueKey('session_1_card')));
      await tester.pumpAndSettle();

      // Create an intentional overlap in Room 301 on 2026-10-20
      await tester.enterText(
        find.byKey(const ValueKey('session_1_room')),
        'Room 301',
      );
      await tester.enterText(
        find.byKey(const ValueKey('session_1_date')),
        '2026-10-20',
      );
      await tester.enterText(
        find.byKey(const ValueKey('session_1_start')),
        '08:30',
      );
      await tester.pumpAndSettle();

      // Verify quick fix banner and overlap indicators appear
      expect(
        find.text('Session 2 starts before Session 1 ends.'),
        findsOneWidget,
      );
      expect(find.text('Start Session 2 at 12:00 PM'), findsOneWidget);
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Apply session plan'),
            )
            .onPressed,
        isNull,
      );

      // The specific timing adjustment resolves the overlap
      await _tap(tester, find.text('Start Session 2 at 12:00 PM'));
      await tester.pumpAndSettle();

      expect(
        find.text('Session 2 starts before Session 1 ends.'),
        findsNothing,
      );
      expect(find.text('No overlapping session times'), findsOneWidget);
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Apply session plan'),
            )
            .onPressed,
        isNotNull,
      );

      await _tap(tester, find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
