import 'package:defensys/utils/defense_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('absolute Manila timestamps preserve seconds and UTC instant', () {
    expect(
      defenseScheduledAt({'scheduled_at': '2024-11-27T10:00:24+08:00'}),
      DateTime.utc(2024, 11, 27, 2, 0, 24),
    );
  });
  test('legacy 12 AM and PM use institutional time', () {
    expect(
      defenseScheduledAt({'date': '2024-11-27', 'startTime': '12:00 AM'}),
      DateTime.utc(2024, 11, 26, 16),
    );
    expect(
      defenseScheduledAt({'date': '2024-11-27', 'start_time': '12:00:59 PM'}),
      DateTime.utc(2024, 11, 27, 4, 0, 59),
    );
    expect(
      defenseScheduledAt({'date': '2024-11-27', 'start_time': '23:59:59'}),
      DateTime.utc(2024, 11, 27, 15, 59, 59),
    );
  });
  test('invalid or absent schedule produces no countdown target', () {
    expect(defenseScheduledAt(null), isNull);
    expect(
      defenseScheduledAt({'date': '2024-11-27', 'start_time': '25:00'}),
      isNull,
    );
  });
  test('countdown clock follows server time and refreshes its anchor', () {
    final clock = DefenseCountdownClock();
    final first = clock.now({'id': 1, 'server_now': '2024-11-20T02:00:00Z'});
    expect(first.difference(DateTime.utc(2024, 11, 20, 2)).inSeconds, 0);
    final refreshed = clock.now({
      'id': 1,
      'server_now': '2024-11-21T02:00:00Z',
    });
    expect(refreshed.difference(DateTime.utc(2024, 11, 21, 2)).inSeconds, 0);
  });
}
