import 'package:defensys/screens/app/panelist/panelist_models.dart';
import 'package:defensys/screens/app/panelist/panelist_session.dart';
import 'package:flutter_test/flutter_test.dart';

TeamData assignment(
  String session,
  DateTime date, {
  bool submitted = false,
  bool chair = false,
  String? verdict,
}) => TeamData(
  name: 'Team VaultSync',
  project: 'Cloud File Sync',
  defenseDate: 'Concept Proposal',
  teamId: '10',
  scheduleId: session,
  sessionId: session,
  scope: 'capstone',
  isCapstone: true,
  scheduledDate: date,
  members: [],
  memberDetails: [],
  criteria: [],
  isPosted: submitted,
  isChair: chair,
  verdict: verdict,
);

void main() {
  test('finished scores stay visible until a new day is assigned', () {
    final team = assignment(
      'session-one',
      DateTime(2026, 10, 9),
      submitted: true,
    );
    final session = PanelistSession('session-one', [team]);
    expect(session.isHistory([session]), isFalse);
    final next = PanelistSession('session-two', [
      assignment('session-two', DateTime(2026, 10, 10)),
    ]);
    expect(session.isHistory([session, next]), isTrue);
    expect(next.isHistory([session, next]), isFalse);
  });

  test(
    'every session for the day must finish before that day moves to History',
    () {
      final morning = PanelistSession('morning', [
        assignment('morning', DateTime(2026, 10, 9), submitted: true),
      ]);
      final afternoonTeam = assignment('afternoon', DateTime(2026, 10, 9));
      final afternoon = PanelistSession('afternoon', [afternoonTeam]);
      final nextDay = PanelistSession('next-day', [
        assignment('next-day', DateTime(2026, 10, 10)),
      ]);
      final sessions = [morning, afternoon, nextDay];
      expect(morning.isHistory(sessions), isFalse);
      expect(afternoon.isHistory(sessions), isFalse);
      afternoonTeam.isPosted = true;
      expect(morning.isHistory(sessions), isTrue);
      expect(afternoon.isHistory(sessions), isTrue);
    },
  );

  test('a chair must record the verdict before their day is finished', () {
    final team = assignment(
      'earlier',
      DateTime(2026, 10, 9),
      submitted: true,
      chair: true,
    );
    final earlier = PanelistSession('earlier', [team]);
    final next = PanelistSession('next', [
      assignment('next', DateTime(2026, 10, 10)),
    ]);
    expect(earlier.isHistory([earlier, next]), isFalse);
    team.verdict = 'for_redefense';
    expect(earlier.isHistory([earlier, next]), isTrue);
  });

  test('an elapsed date never hides unsubmitted grades', () {
    final earlier = PanelistSession('earlier', [
      assignment('earlier', DateTime(2026, 10, 1)),
    ]);
    final next = PanelistSession('next', [
      assignment('next', DateTime(2026, 10, 10)),
    ]);
    expect(earlier.isHistory([earlier, next]), isFalse);
  });
}
