import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/models/schedule_import_models.dart';

void main() {
  test('PIT readiness follows explicit ownership even for neutral or misleading names', () {
    final team = <String, dynamic>{'year_level': '2nd Year'};
    expect(isPitTeamReadyToSchedule(team, 'System Concept Pitching', {
      'year_level': '1st Year',
    }), isFalse);
    expect(isPitTeamReadyToSchedule(team, 'System Concept Pitching', {
      'year_level': '2nd Year',
    }), isTrue);
    expect(isPitTeamReadyToSchedule(team, '1st Year in Review', {
      'year_level': '2nd Year',
    }), isTrue);
  });

  test('Unclassified and completed events cannot make teams ready to schedule', () {
    final team = <String, dynamic>{'year_level': '2nd Year'};
    expect(isPitTeamReadyToSchedule(team, 'Expo', {}), isFalse);
    expect(isPitTeamReadyToSchedule(team, 'Expo', {
      'year_level': '2nd Year', 'is_officially_complete': true,
    }), isFalse);
  });
}
