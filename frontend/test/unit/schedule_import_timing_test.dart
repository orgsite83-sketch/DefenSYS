import 'package:defensys/screens/web/admin/defense_scheduler/models/schedule_import_models.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:defensys/utils/import/schedule_import_draft.dart';
import 'package:defensys/utils/import/schedule_import_timing.dart';
import 'package:flutter_test/flutter_test.dart';

ParsedScheduleImportRow _row(
  int id,
  String start, {
  String room = 'Room 301',
  String date = '2026-10-20',
  String chair = 'Chair One',
  String documenter = 'Recorder One',
  String adviser = 'Adviser One',
  int originalDuration = 30,
}) => ParsedScheduleImportRow(
  sheetRow: id,
  time: '$start - ${addMinutesToTimeString(start, originalDuration)}',
  teamName: 'Team $id',
  projectTitle: '',
  adviser: adviser,
  members: const [],
  chair: chair,
  panelMembers: const [],
  documenter: documenter,
  room: room,
  date: date,
  stage: '',
  startTime: start,
  endTime: addMinutesToTimeString(start, originalDuration),
  slotDuration: originalDuration,
);

DefenseSchedulerState _state({
  List<Map<String, dynamic>> schedules = const [],
  String scope = 'capstone',
  Map<int, String> advisers = const {},
}) => DefenseSchedulerState(
  defenseStages: const [
    {'id': 10, 'label': 'Concept Proposal'},
  ],
  faculty: const [
    {'id': 101, 'name': 'Chair One'},
    {'id': 102, 'name': 'Recorder One'},
    {'id': 103, 'name': 'Adviser One'},
    {'id': 201, 'name': 'Chair Two'},
    {'id': 202, 'name': 'Recorder Two'},
    {'id': 203, 'name': 'Adviser Two'},
  ],
  teams: [
    for (var i = 1; i <= 12; i++)
      {
        'id': i,
        'name': 'Team $i',
        'level': scope == 'pit' ? 'PIT 1' : 'Capstone 1',
        'ready_for_stage': 'Concept Proposal',
        if (advisers[i] != null) 'adviser_name': advisers[i],
      },
  ],
  schedules: schedules,
);

List<ScheduleImportPreviewRow> _preview(
  List<ParsedScheduleImportRow> rows, {
  int? duration = 60,
  bool reflow = true,
  List<Map<String, dynamic>> schedules = const [],
  String scope = 'capstone',
  Map<int, String> advisers = const {},
}) => buildScheduleImportPreviewRows(
  ParsedScheduleImport(rows: rows),
  _state(schedules: schedules, scope: scope, advisers: advisers),
  scope: scope,
  stageId: 10,
  eventName: scope == 'pit' ? 'PIT Expo' : '',
  date: '2026-10-20',
  room: 'Room 301',
  slotDuration: duration,
  reflowStartTimes: reflow,
  fallbackDuration: 30,
  panelRubricId: 1,
  adviserRubricId: 2,
  peerRubricId: 3,
  panelWeight: 80,
  peerWeight: 20,
);

void main() {
  test('whitespace fallbacks and room names share one timing lane', () {
    final rows = _preview([
      _row(1, '08:00', room: 'Room   301', date: '  '),
      _row(2, '08:30'),
    ]);
    expect(rows.last.effectiveStartTime, '09:00');
    expect(rows.every((row) => row.ready), isTrue);
  });

  test(
    'availability uses the assigned adviser when a spreadsheet is outdated',
    () {
      final rows = _preview(
        [
          _row(1, '08:00'),
          _row(
            2,
            '08:00',
            room: 'Room 302',
            chair: 'Chair Two',
            documenter: 'Recorder Two',
            adviser: 'Adviser Two',
          ),
        ],
        advisers: {2: 'Adviser One'},
      );
      expect(rows.last.adviserLabel, 'Adviser One');
      expect(rows.last.adviserId, 103);
      expect(rows.every((row) => !row.ready), isTrue);
      expect(
        rows.first.slotIssues.single,
        contains('Adviser One double-booked'),
      );
    },
  );

  test('longer slots shift later sessions and payloads match the preview', () {
    final source = [
      for (var i = 0; i < 8; i++)
        _row(
          i + 1,
          scheduleTimeFromMinutes(480 + i * 30),
          chair: i < 4 ? 'Chair One' : 'Chair Two',
        ),
    ];
    final rows = _preview(source);
    expect(rows.map((row) => row.effectiveStartTime), [
      '08:00',
      '09:00',
      '10:00',
      '11:00',
      '12:00',
      '13:00',
      '14:00',
      '15:00',
    ]);
    expect(rows.last.effectiveEndTime, '16:00');
    expect(rows.every((row) => row.ready), isTrue);
    for (var i = 0; i < rows.length; i++) {
      expect(rows[i].toPayload()['start_time'], rows[i].effectiveStartTime);
      expect(rows[i].toPayload()['slot_duration'], 60);
      expect(identical(rows[i].source, source[i]), isTrue);
    }
    expect(source[1].startTime, '08:30');
  });

  test(
    'shorter slots preserve original breaks and repeated edits have no drift',
    () {
      final source = [_row(1, '08:00'), _row(2, '08:30'), _row(3, '10:00')];
      expect(_preview(source, duration: 60).map((r) => r.effectiveStartTime), [
        '08:00',
        '09:00',
        '11:00',
      ]);
      expect(_preview(source, duration: 15).map((r) => r.effectiveStartTime), [
        '08:00',
        '08:15',
        '09:30',
      ]);
      expect(_preview(source, duration: 30).map((r) => r.effectiveStartTime), [
        '08:00',
        '08:30',
        '10:00',
      ]);
      expect(source[2].startTime, '10:00');
    },
  );

  test(
    'room and day lanes are independent and original chronological order wins',
    () {
      final source = [
        _row(2, '08:30'),
        _row(1, '08:00'),
        _row(
          3,
          '08:00',
          room: 'Room 302',
          chair: 'Chair Two',
          documenter: 'Recorder Two',
          adviser: 'Adviser Two',
        ),
        _row(
          4,
          '08:30',
          room: 'room 302',
          chair: 'Chair Two',
          documenter: 'Recorder Two',
          adviser: 'Adviser Two',
        ),
        _row(5, '08:00', date: '2026-10-21'),
        _row(6, '08:30', date: '2026-10-21'),
      ];
      final rows = _preview(source);
      expect(rows.map((r) => r.effectiveStartTime), [
        '09:00',
        '08:00',
        '08:00',
        '09:00',
        '08:00',
        '09:00',
      ]);
      expect(rows.every((r) => r.ready), isTrue);
    },
  );

  test(
    'fixed starts flag both overlapping rows instead of reporting Ready',
    () {
      final rows = _preview([
        _row(1, '08:00'),
        _row(2, '08:30'),
      ], reflow: false);
      expect(rows.map((r) => r.timeLabel), ['08:00 - 09:00', '08:30 - 09:30']);
      expect(rows.every((r) => !r.ready), isTrue);
      expect(rows[0].slotIssues.single, contains('Time overlap with Team 2'));
      expect(rows[1].slotIssues.single, contains('Time overlap with Team 1'));
      expect(rows[0].issues.single, contains('room already occupied'));
    },
  );

  test('adjacent slots and appointments on separate dates do not conflict', () {
    final rows = _preview([
      _row(1, '08:00'),
      _row(2, '09:00'),
      _row(3, '08:00', date: '2026-10-21'),
    ], reflow: false);
    expect(rows.every((r) => r.ready), isTrue);
  });

  for (final role in ['chair', 'documenter', 'adviser', 'cross-role']) {
    test('detects shared $role across simultaneous rooms', () {
      final rows = _preview([
        _row(1, '08:00'),
        _row(
          2,
          '08:00',
          room: 'Room 302',
          chair: role == 'chair'
              ? 'Chair One'
              : role == 'cross-role'
              ? 'Recorder One'
              : 'Chair Two',
          documenter: role == 'documenter' ? 'Recorder One' : 'Recorder Two',
          adviser: role == 'adviser' ? 'Adviser One' : 'Adviser Two',
        ),
      ]);
      expect(rows.every((r) => !r.ready), isTrue);
      expect(rows[0].slotIssues.single, contains('double-booked'));
      expect(
        rows[0].slotIssues.single,
        isNot(contains('room already occupied')),
      );
    });
  }

  test(
    'checks existing active schedules using API time and faculty fields',
    () {
      final rows = _preview(
        [_row(1, '08:00')],
        schedules: [
          {
            'status': 'scheduled',
            'scheduled_date': '2026-10-20',
            'start_time': '08:30:00',
            'slot_duration': 30,
            'room': 'room 301',
            'team_id': 99,
            'team_name': 'Published Team',
            'panelists': [
              {'id': 101},
            ],
            'documenter': 102,
            'adviser_id': 103,
          },
        ],
      );
      expect(rows.single.ready, isFalse);
      expect(
        rows.single.slotIssues.single,
        contains('scheduled Published Team'),
      );
      expect(rows.single.slotIssues.single, contains('room already occupied'));
      expect(rows.single.slotIssues.single, contains('Chair One'));
    },
  );

  test('cancelled, completed and adjacent existing schedules do not block', () {
    final rows = _preview(
      [_row(1, '08:00')],
      schedules: [
        for (final status in ['cancelled', 'done'])
          {
            'status': status,
            'scheduled_date': '2026-10-20',
            'start_time': '08:00:00',
            'slot_duration': 60,
            'room': 'Room 301',
          },
        {
          'status': 'scheduled',
          'scheduled_date': '2026-10-20',
          'start_time': '09:00:00',
          'slot_duration': 60,
          'room': 'Room 301',
        },
      ],
    );
    expect(rows.single.ready, isTrue);
  });

  test(
    'midnight overflow stays visible and blocks import instead of wrapping',
    () {
      final rows = _preview([
        _row(1, '23:30'),
        _row(2, '23:45', originalDuration: 15),
      ]);
      expect(rows.first.effectiveEndTime, '24:30');
      expect(rows.last.effectiveStartTime, '24:30');
      expect(rows.last.effectiveEndTime, '25:30');
      expect(rows.every((r) => !r.ready), isTrue);
      expect(rows.first.slotIssues, contains(contains('past midnight')));
    },
  );

  test('invalid times and durations are rejected', () {
    for (final duration in [0, 14, 241]) {
      final row = _preview([_row(1, '08:00')], duration: duration).single;
      expect(row.ready, isFalse);
      expect(row.slotIssues, contains(contains('between 15 and 240')));
    }
    final row = _preview([_row(1, '08:99')]).single;
    expect(row.ready, isFalse);
    expect(row.slotIssues, contains('Time could not be parsed.'));
  });

  test('PIT payloads also use adjusted start times', () {
    final rows = _preview([_row(1, '08:00'), _row(2, '08:30')], scope: 'pit');
    expect(rows.last.toPayload()['start_time'], '09:00');
    expect(rows.last.toPayload()['scope'], 'pit');
    expect(rows.every((r) => r.ready), isTrue);
  });

  test(
    'timing mode survives draft serialization and old drafts reflow safely',
    () {
      final draft = ScheduleImportDraft(
        parsed: ParsedScheduleImport(rows: [_row(1, '08:00')]),
        scope: 'capstone',
        savedAt: DateTime(2026),
        reflowStartTimes: false,
      );
      expect(
        ScheduleImportDraft.fromJson(draft.toJson()).reflowStartTimes,
        isFalse,
      );
      final legacy = draft.toJson()..remove('reflow_start_times');
      expect(ScheduleImportDraft.fromJson(legacy).reflowStartTimes, isTrue);
    },
  );
}
