import 'package:defensys/screens/web/admin/defense_scheduler/models/schedule_session_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  test('a default day session has eight slots and skips lunch', () {
    final draft = ScheduleSessionDraft(
      key: 'day',
      date: TextEditingController(text: '2026-10-05'),
      start: TextEditingController(text: '08:00'),
      duration: TextEditingController(text: '60'),
      room: TextEditingController(text: 'Lab 1'),
    );
    addTearDown(draft.dispose);
    expect(draft.capacity, 8);
    expect(draft.teamIds, isEmpty);
    final slots = arrangeSessionSlots(
      [
        for (int i = 1; i <= 9; i++) {'team_id': i, 'session_key': 'day'},
      ],
      [draft.toPayload()],
    );
    expect(slots.take(8).map((slot) => slot['start_time']), [
      '08:00',
      '09:00',
      '10:00',
      '11:00',
      '13:00',
      '14:00',
      '15:00',
      '16:00',
    ]);
    expect(slots[3]['end_time'], '12:00');
    expect(slots.last['session_key'], isNull);
    expect(slots.last['requested_session_key'], 'day');
  });

  test('a slot never uses leftover minutes across a break', () {
    final intervals = sessionSlotIntervals({
      'slot_duration': 90,
      'time_blocks': [
        {'start_time': '08:00', 'end_time': '10:00'},
        {'start_time': '13:00', 'end_time': '15:00'},
      ],
    });
    expect(intervals, [(480, 570), (780, 870)]);
  });
  final sessions = [
    {
      'key': 'morning',
      'scheduled_date': '2026-10-05',
      'start_time': '08:00',
      'end_time': '10:00',
      'slot_duration': 60,
      'room': 'Lab 1',
    },
    {
      'key': 'next-day',
      'scheduled_date': '2026-10-06',
      'start_time': '13:00',
      'end_time': '14:00',
      'slot_duration': 30,
      'room': 'Lab 2',
    },
  ];

  test(
    'reordering and moves preserve each session date, room and duration',
    () {
      final slots = arrangeSessionSlots([
        {'team_id': 2, 'session_key': 'morning'},
        {'team_id': 3, 'session_key': 'next-day'},
        {'team_id': 1, 'session_key': 'morning'},
        {'team_id': 4, 'session_key': 'next-day'},
      ], sessions);
      expect(slots.map((s) => s['start_time']), [
        '08:00',
        '13:00',
        '09:00',
        '13:30',
      ]);
      expect(slots[3]['scheduled_date'], '2026-10-06');
      expect(slots[3]['room'], 'Lab 2');
      expect(slots[3]['slot_duration'], 30);
    },
  );

  test(
    'full and missing sessions keep teams unassigned without time overflow',
    () {
      final input = [
        for (int i = 0; i < 3; i++) {'team_id': i, 'session_key': 'morning'},
        {'team_id': 9, 'session_key': 'deleted'},
      ];
      final slots = arrangeSessionSlots(input, sessions);
      expect(slots[1]['end_time'], '10:00');
      expect(slots[2]['session_key'], isNull);
      expect(slots[2]['start_time'], isNull);
      expect(slots[3]['session_key'], isNull);
      expect(input[2]['session_key'], 'morning');
    },
  );

  test('removing a team compresses only its session', () {
    final slots = arrangeSessionSlots([
      {'team_id': 1, 'session_key': 'morning', 'start_time': '09:00'},
      {'team_id': 2, 'session_key': 'next-day', 'start_time': '13:00'},
    ], sessions);
    expect(slots[0]['start_time'], '08:00');
    expect(slots[1]['start_time'], '13:00');
    expect(slots[1]['scheduled_date'], '2026-10-06');
  });

  test('time parsing rejects invalid hours and minutes', () {
    expect(scheduleTimeMinutes('24:00'), -1);
    expect(scheduleTimeMinutes('08:60'), -1);
    expect(scheduleTimeMinutes('invalid'), -1);
    expect(scheduleTimeMinutes('08:30'), 510);
  });
}
