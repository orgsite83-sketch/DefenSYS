import 'package:defensys/models/documenter_assignment.dart';
import 'package:flutter_test/flutter_test.dart';

DocumenterAssignment assignment({
  String date = '2026-10-09',
  String status = 'scheduled',
  String? minutes = 'draft',
  bool comments = false,
}) => DocumenterAssignment({
  'id': 1,
  'scheduled_date': date,
  'status': status,
  'minutes_status': minutes,
  'minutes_has_comments': comments,
});

void main() {
  final today = DateTime(2026, 10, 9, 10);
  test('opening a blank draft still shows start minutes', () {
    expect(assignment().actionLabel, 'Start minutes');
    expect(assignment(comments: true).actionLabel, 'Continue minutes');
    expect(assignment(comments: true).statusLabel, 'Minutes in progress');
  });
  test('needs action excludes future, signed and locked defenses', () {
    expect(
      assignment(
        date: '2026-10-08',
      ).matches(DocumenterFilter.needsAction, today),
      isTrue,
    );
    expect(
      assignment(status: 'done').matches(DocumenterFilter.needsAction, today),
      isTrue,
    );
    for (final row in [
      assignment(date: '2026-10-10'),
      assignment(minutes: 'submitted'),
      assignment(status: 'cancelled', date: '2026-10-08'),
      assignment(status: 'archived', date: '2026-10-08'),
    ]) {
      expect(row.matches(DocumenterFilter.needsAction, today), isFalse);
    }
  });
  test('records include signature progress and retained cancelled minutes', () {
    expect(
      assignment(
        minutes: 'adviser_signed',
      ).matches(DocumenterFilter.records, today),
      isTrue,
    );
    expect(
      assignment(status: 'cancelled').matches(DocumenterFilter.records, today),
      isTrue,
    );
    expect(
      assignment(
        status: 'cancelled',
        minutes: null,
      ).matches(DocumenterFilter.records, today),
      isFalse,
    );
    expect(assignment(minutes: 'completed').actionLabel, 'View signed PDF');
  });
  test('today and upcoming use dates independently of the time of day', () {
    expect(assignment().matches(DocumenterFilter.today, today), isTrue);
    expect(
      assignment(date: '2026-10-10').matches(DocumenterFilter.upcoming, today),
      isTrue,
    );
    expect(
      assignment(date: '2026-10-08').matches(DocumenterFilter.upcoming, today),
      isFalse,
    );
  });
}
