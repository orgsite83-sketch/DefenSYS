import 'package:defensys/utils/import/student_rollover_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automatic section is displayed but recomputed on confirmation', () {
    final action = buildStudentRolloverAction({
      'record': {'id': 1, 'student_username': 'S001'},
      'promote_result': {
        'year_level': '4th Year',
        'section': 'BSIT-4A',
        'section_automatic': true,
        'target_semester_id': 2,
      },
    }, 'promote');
    expect(action.containsKey('section'), isFalse);
    expect(action['year_level'], '4th Year');
    expect(action['target_semester_id'], 2);
  });

  test(
    'explicit section and PIT rollover still submit the reviewed section',
    () {
      for (final result in [
        {'section': 'BSIT-4B', 'section_automatic': false},
        {'section': 'BSIT-2A'},
      ]) {
        final action = buildStudentRolloverAction({
          'record': {'id': 1},
          'promote_result': result,
        }, 'promote');
        expect(action['section'], result['section']);
      }
    },
  );
}
