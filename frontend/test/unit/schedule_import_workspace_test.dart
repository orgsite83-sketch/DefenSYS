import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:defensys/utils/import/schedule_import_draft.dart';
import 'package:defensys/utils/import/schedule_import_workspace.dart';
import 'package:defensys/screens/web/admin/defense_board/components/schedule_import_review_widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ParsedScheduleImportRow _row(
  int index,
  String start, {
  String date = '',
  String room = '',
  int? duration = 30,
}) => ParsedScheduleImportRow(
  sheetRow: index + 6,
  time: '$start - next',
  teamName: 'Team $index',
  projectTitle: 'Project $index',
  adviser: 'Adviser $index',
  members: ['$index'],
  chair: 'Chair',
  panelMembers: const ['Panel'],
  documenter: 'Documenter',
  startTime: start,
  endTime: '',
  slotDuration: duration,
  date: date,
  room: room,
  stage: '',
);

ScheduleImportSourceFile _file(String id, List<ParsedScheduleImportRow> rows) =>
    attachScheduleImportSource(
      ParsedScheduleImport(
        rows: rows,
        stage: 'Concept Proposal',
        date: '2026-10-20',
        room: 'Room 301',
      ),
      id,
      '$id.xlsx',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'morning and afternoon preview uses the first session duration and retains odd teams',
    () {
      final rows = _file('a', [
        for (var i = 0; i < 5; i++) _row(i, '08:00', duration: i < 3 ? 90 : 30),
      ]).parsed.rows;
      final plans = morningAfternoonSessionPlans(rows, fallbackDuration: 60);
      expect(plans.map((plan) => plan.count), [3, 2]);
      expect(plans.first.duration, 90);
      expect(plans.last.duration, 30);
      expect(
        plans.last.start,
        '13:00',
      ); // Morning finishes at 12:30, then a break.
      final applied = applyScheduleImportSessionPlans(
        rows,
        rows.map((row) => row.importRowId).toList(),
        plans,
        sessionPrefix: 'preset',
      );
      expect(applied[2].endTime, '12:30');
      expect(applied[3].startTime, plans.last.start);
      expect(applied.last.endTime, '14:00');
      expect(applied.map((row) => row.importRowId).toSet().length, 5);
      expect(
        morningAfternoonSessionPlans(
          rows.take(1).toList(),
          fallbackDuration: 60,
        ),
        isEmpty,
      );
    },
  );
  test('typed session dates reject impossible calendar days', () {
    expect(scheduleImportDateIsValid('2026-02-31'), isFalse);
    expect(scheduleImportDateIsValid('2026-02-28'), isTrue);
    expect(scheduleImportDateIsValid('2026-13-01'), isFalse);
    expect(scheduleImportDateIsValid('10/20/2026'), isFalse);
  });
  test(
    'joining files keeps header defaults and repeated sheet rows distinct',
    () {
      final a = _file('a', [_row(0, '08:00')]),
          b = _file('b', [_row(0, '13:00', room: 'Room 302')]);
      final rows = combineScheduleImportSources([a, b]).rows;
      expect(rows.map((row) => row.importRowId).toSet(), {'a:0', 'b:0'});
      expect(rows.map((row) => row.sheetRow), [6, 6]);
      expect(rows.map((row) => row.sourceFileName), ['a.xlsx', 'b.xlsx']);
      expect(rows.map((row) => row.room), ['Room 301', 'Room 302']);
      expect(
        rows.every(
          (row) => row.date == '2026-10-20' && row.stage == 'Concept Proposal',
        ),
        isTrue,
      );
      expect(
        ScheduleImportSourceFile.fromJson(
          b.toJson(),
        ).parsed.rows.single.importRowId,
        'b:0',
      );
    },
  );

  test('uneven sessions retain every row and its faculty exactly once', () {
    final files = [
      _file('a', [for (var i = 0; i < 8; i++) _row(i, '08:00')]),
      _file('b', [for (var i = 8; i < 16; i++) _row(i, '13:00')]),
    ];
    final rows = combineScheduleImportSources(files).rows;
    final planned = applyScheduleImportSessionPlans(
      rows,
      rows.map((row) => row.importRowId).toList(),
      const [
        ScheduleImportSessionPlan(
          count: 5,
          start: '08:00',
          duration: 30,
          date: '2026-10-20',
          room: 'Room 301',
        ),
        ScheduleImportSessionPlan(
          count: 11,
          start: '13:00',
          duration: 30,
          date: '2026-10-20',
          room: 'Room 301',
        ),
      ],
      sessionPrefix: 'test',
    );
    expect(
      scheduleImportSessionGroups(planned).map((session) => session.length),
      [5, 11],
    );
    expect(planned[4].endTime, '10:30');
    expect(planned[5].startTime, '13:00');
    expect(planned.last.endTime, '18:30');
    expect(planned.map((row) => row.importRowId).toSet().length, 16);
    for (var i = 0; i < rows.length; i++) {
      expect(planned[i].adviser, rows[i].adviser);
      expect(planned[i].members, rows[i].members);
      expect(planned[i].panelMembers, rows[i].panelMembers);
      expect(planned[i].sourceFileName, rows[i].sourceFileName);
    }
    final edited = updateScheduleImportValues(
      planned,
      planned.take(5).map((row) => row.importRowId).toSet(),
      duration: 45,
    );
    expect(edited[4].endTime, '11:45');
    expect(edited[5].startTime, '13:00');
  });

  test('file scope preserves other rows inside a combined session', () {
    final rows = combineScheduleImportSources([
      _file('a', [_row(0, '08:00')]),
      _file('b', [_row(1, '08:30')]),
    ]).rows;
    final planned = applyScheduleImportSessionPlans(
      rows,
      rows.map((row) => row.importRowId).toList(),
      const [
        ScheduleImportSessionPlan(
          count: 2,
          start: '08:00',
          duration: 30,
          date: '2026-10-20',
          room: 'Room 301',
        ),
      ],
      sessionPrefix: 'combined',
    );
    final edited = updateScheduleImportValues(
      planned,
      {'a:0'},
      duration: 60,
      room: 'Hall',
    );
    expect(edited.first.endTime, '09:00');
    expect(edited.first.room, 'Hall');
    expect(identical(edited[1], planned[1]), isTrue);
    expect(edited[1].startTime, '08:30');
    expect(edited[1].room, 'Room 301');
  });

  test(
    'session plans reject missing teams, duplicate IDs, and midnight overflow',
    () {
      final rows = _file('a', [_row(0, '08:00'), _row(1, '08:30')]).parsed.rows;
      List<ParsedScheduleImportRow> apply(
        List<String> ids,
        int count,
        String start,
      ) => applyScheduleImportSessionPlans(rows, ids, [
        ScheduleImportSessionPlan(
          count: count,
          start: start,
          duration: 30,
          date: '2026-10-20',
          room: 'Room 301',
        ),
      ], sessionPrefix: 'x');
      expect(() => apply(['a:0', 'a:1'], 1, '08:00'), throwsFormatException);
      expect(() => apply(['a:0', 'a:0'], 2, '08:00'), throwsFormatException);
      expect(() => apply(['a:0', 'a:1'], 2, '23:30'), throwsFormatException);
      expect(rows.last.startTime, '08:30');
    },
  );

  test('duration updates preserve spreadsheet breaks and session anchors', () {
    final rows = _file('a', [
      _row(0, '08:00'),
      _row(1, '08:30'),
      _row(2, '13:00'),
      _row(3, '13:30'),
    ]).parsed.rows;
    final changed = updateScheduleImportValues(
      rows,
      rows.map((row) => row.importRowId).toSet(),
      duration: 45,
    );
    expect(changed.map((row) => row.startTime), [
      '08:00',
      '08:45',
      '13:00',
      '13:45',
    ]);
    final repeated = updateScheduleImportValues(
      changed,
      changed.map((row) => row.importRowId).toSet(),
      duration: 30,
    );
    expect(repeated.map((row) => row.startTime), [
      '08:00',
      '08:30',
      '13:00',
      '13:30',
    ]);
  });

  test(
    'duration updates cascade later groups in same room and date to prevent collisions',
    () {
      final rows = _file('a', [
        _row(0, '08:00'),
        _row(1, '08:30'),
        _row(2, '10:00'),
        _row(3, '10:30'),
      ]).parsed.rows;
      final changed = updateScheduleImportValues(
        rows,
        rows.map((row) => row.importRowId).toSet(),
        duration: 90,
      );
      // Group 0: 08:00 -> 09:30 (ends 11:00)
      // Group 1 originally at 10:00 would collide (10:00 < 11:00)
      // It cascades to 11:00!
      expect(changed[0].startTime, '08:00');
      expect(changed[0].endTime, '09:30');
      expect(changed[1].startTime, '09:30');
      expect(changed[1].endTime, '11:00');
      expect(changed[2].startTime, '11:00');
      expect(changed[2].endTime, '12:30');
      expect(changed[3].startTime, '12:30');
      expect(changed[3].endTime, '14:00');
    },
  );

  test('time ranges display adjacent intervals and both periods at noon', () {
    expect(scheduleReviewTimeRange('08:00', '08:30'), '8:00–8:30 AM');
    expect(scheduleReviewTimeRange('08:30', '09:00'), '8:30–9:00 AM');
    expect(scheduleReviewTimeRange('11:30', '12:00'), '11:30 AM–12:00 PM');
    expect(scheduleReviewTimeRange('13:00', '13:30'), '1:00–1:30 PM');
  });

  test('term matching accepts equivalent labels and rejects other terms', () {
    expect(
      scheduleImportSemesterMatches(
        'First Sem AY 2026-2027',
        '1st Semester, A.Y. 2026-2027',
      ),
      isTrue,
    );
    expect(
      scheduleImportSemesterMatches(
        '2nd Semester AY 2026-2027',
        '1st Semester, A.Y. 2026-2027',
      ),
      isFalse,
    );
    expect(
      scheduleImportSemesterMatches(
        '1st Semester AY 2025-2026',
        '1st Semester, A.Y. 2026-2027',
      ),
      isFalse,
    );
    expect(
      scheduleImportSemesterMatches(null, '1st Semester, A.Y. 2026-2027'),
      isTrue,
    );
  });

  test(
    'drafts are isolated by term and restore source and session identities',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final file = _file('a', [_row(0, '08:00')]);
      ScheduleImportDraft draft(int term) => ScheduleImportDraft(
        parsed: file.parsed,
        files: [file],
        scope: 'capstone',
        semesterId: term,
        savedAt: DateTime(2026),
        selectedFileId: 'a',
      );
      await saveScheduleImportDraft(draft(1));
      expect(
        await loadScheduleImportDraft(scope: 'capstone', semesterId: 2),
        isNull,
      );
      await saveScheduleImportDraft(draft(2));
      final restored = await loadScheduleImportDraft(
        scope: 'capstone',
        semesterId: 1,
      );
      expect(restored!.files.single.id, 'a');
      expect(restored.parsed.rows.single.importRowId, 'a:0');
      expect(restored.selectedFileId, 'a');
      await clearScheduleImportDraft(scope: 'capstone', semesterId: 1);
      expect(
        await loadScheduleImportDraft(scope: 'capstone', semesterId: 1),
        isNull,
      );
      expect(
        (await loadScheduleImportDraft(
          scope: 'capstone',
          semesterId: 2,
        ))!.semesterId,
        2,
      );
    },
  );
}
