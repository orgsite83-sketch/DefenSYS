import 'package:defensys/screens/app/panelist/panelist_models.dart';
import 'package:defensys/screens/app/panelist/panelist_session.dart';
import 'package:flutter_test/flutter_test.dart';

TeamData assignment(
  String session,
  DateTime date, {
  bool submitted = false,
  bool chair = false,
  bool concepts = false,
  String? verdict,
  String start = '',
  String label = '',
  String windowStart = '',
  String windowEnd = '',
  String legacy = '',
}) => TeamData(
  name: 'Team VaultSync',
  project: 'Cloud File Sync',
  defenseDate: 'Concept Proposal',
  teamId: '10',
  scheduleId: session,
  sessionId: session,
  legacySessionId: legacy,
  startTime: start,
  sessionLabel: label,
  sessionStartTime: windowStart,
  sessionEndTime: windowEnd,
  scope: 'capstone',
  isCapstone: true,
  scheduledDate: date,
  members: [],
  memberDetails: [],
  criteria: [],
  isPosted: submitted,
  isChair: chair,
  verdict: verdict,
  assessmentConcepts: concepts
      ? [
          {'key': 'c1', 'title': 'Concept proposal'},
        ]
      : [],
);

void main() {
  test('partial personal assignments use the configured afternoon window', () {
    final team = assignment(
      'afternoon',
      DateTime(2026, 11, 13),
      start: '17:30',
      label: 'Afternoon',
      windowStart: '13:00',
      windowEnd: '19:00',
    );
    final session = PanelistSession(PanelistSession.teamKey(team), [team]);
    expect(session.timeLabel, 'Afternoon · 1:00 PM–7:00 PM');
    expect(session.startsAt.hour, 17);
  });

  test('legacy full-day sessions do not invent a morning window', () {
    final team = assignment('full-day', DateTime(2026, 11, 13), start: '08:00');
    final session = PanelistSession(PanelistSession.teamKey(team), [team]);
    expect(session.timeLabel, '8:00 AM');
    expect(session.window.isConfigured, isFalse);
  });

  test('saved roster-session preferences resolve to the repaired session', () {
    final date = DateTime(2026, 11, 13);
    final old = assignment('old-roster', date);
    final repaired = assignment('afternoon', date, legacy: 'old-roster');
    final session = PanelistSession(PanelistSession.teamKey(repaired), [
      repaired,
    ]);
    expect(session.matchesKey(PanelistSession.teamKey(old)), isTrue);
    expect(
      session.matchesKey(
        PanelistSession.teamKey(assignment('unrelated', date)),
      ),
      isFalse,
    );
  });

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

  test(
    'a manual concept chair must record the verdict before their day is finished',
    () {
      final team = assignment(
        'earlier',
        DateTime(2026, 10, 9),
        submitted: true,
        chair: true,
        concepts: true,
      );
      final earlier = PanelistSession('earlier', [team]);
      final next = PanelistSession('next', [
        assignment('next', DateTime(2026, 10, 10)),
      ]);
      expect(earlier.isHistory([earlier, next]), isFalse);
      team.verdict = 'for_redefense';
      expect(earlier.isHistory([earlier, next]), isTrue);
    },
  );

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
