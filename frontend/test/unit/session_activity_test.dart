import 'package:defensys/utils/scheduler/session_activity.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 10, 20);
Map<String, dynamic> defense(
  String date, {
  String status = 'scheduled',
  String? display,
  String? operation,
}) => {
  'scheduled_date': date,
  'start_time': '08:00:00',
  'status': status,
  if (display != null) 'display_status': display,
  if (operation != null) 'operation_state': operation,
};

void main() {
  test(
    'active work precedes upcoming and final sessions regardless of stage',
    () {
      final sessions = [
        [defense('2026-10-04', status: 'done', display: 'completed')],
        [defense('2026-10-20')],
        [defense('2026-10-08', display: 'awaiting_evaluation')],
        [defense('2026-10-11')],
        [defense('2026-10-10', display: 'evaluating')],
        [defense('2026-10-09', status: 'done', display: 'completed')],
      ];
      sessions.sort((a, b) => compareSessionActivity(a, b, now: now));
      expect(sessions.map((s) => s.first['scheduled_date']), [
        '2026-10-10',
        '2026-10-08',
        '2026-10-11',
        '2026-10-20',
        '2026-10-09',
        '2026-10-04',
      ]);
    },
  );

  test(
    'elapsed time and done storage status do not hide unfinished grading',
    () {
      for (final display in [
        'awaiting_evaluation',
        'awaiting_verdict',
        'grading_incomplete',
        'awaiting_completion',
        'revisions_pending',
      ]) {
        expect(
          sessionActivity([
            defense('2026-10-04', status: 'done', display: display),
          ], now: now),
          SessionActivity.active,
        );
      }
      expect(
        sessionActivity([defense('2026-10-10')], now: now),
        SessionActivity.active,
      );
    },
  );

  test('mixed sessions follow their unfinished teams and relevant date', () {
    final mixed = [
      defense('2026-10-04', status: 'done', display: 'completed'),
      defense('2026-10-20'),
    ];
    final upcoming = [defense('2026-10-11')];
    expect(sessionActivity(mixed, now: now), SessionActivity.upcoming);
    expect(compareSessionActivity(mixed, upcoming, now: now), greaterThan(0));
    mixed.add(defense('2026-10-09', display: 'evaluating'));
    expect(sessionActivity(mixed, now: now), SessionActivity.active);
  });

  test(
    'interrupted work stays visible; terminal schedules stay in history',
    () {
      for (final operation in ['paused', 'postponed', 'no_show']) {
        expect(
          sessionActivity([
            defense('2026-10-20', operation: operation),
          ], now: now),
          SessionActivity.active,
        );
      }
      for (final status in ['cancelled', 'archived']) {
        expect(
          sessionActivity([
            defense('2026-10-20', status: status, display: 'evaluating'),
          ], now: now),
          SessionActivity.past,
        );
      }
    },
  );

  test('undated work remains visible after dated sessions', () {
    final undated = [defense('TBD')];
    expect(sessionActivity(undated, now: now), SessionActivity.active);
    expect(
      compareSessionActivity(undated, [defense('2026-10-10')], now: now),
      greaterThan(0),
    );
  });
}
