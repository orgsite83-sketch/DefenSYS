import 'dart:convert';

import 'package:intl/intl.dart';

import '../../../utils/scheduler/session_period.dart';
import 'panelist_models.dart';

class PanelistSession {
  final String key;
  final List<TeamData> teams;

  PanelistSession(this.key, this.teams);

  static String teamKey(TeamData team) => json.encode([
    team.sessionId.isNotEmpty
        ? team.sessionId
        : '${team.semesterId}|${team.room}',
    team.scheduledDate?.toIso8601String().split('T').first ?? '',
  ]);

  DateTime get startsAt {
    final starts = teams.map((team) {
      final date = team.scheduledDate ?? DateTime(2000);
      final parts = team.startTime.split(':');
      return DateTime(
        date.year,
        date.month,
        date.day,
        int.tryParse(parts.firstOrNull ?? '') ?? 0,
        int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0,
      );
    }).toList()..sort();
    return starts.first;
  }

  bool get finished => teams.every((team) => team.panelWorkFinished);

  DateTime get day => DateTime(startsAt.year, startsAt.month, startsAt.day);

  bool isHistory(List<PanelistSession> sessions) =>
      sessions
          .where((session) => session.day == day)
          .every((session) => session.finished) &&
      sessions.any((session) => session.day.isAfter(day));

  DefenseSessionWindow get window => DefenseSessionWindow(
    label: teams.first.sessionLabel,
    start: teams.first.sessionStartTime,
    end: teams.first.sessionEndTime,
  );

  /// Accept retained preferences saved before the roster-split repair.
  bool matchesKey(String? candidate) =>
      candidate != null &&
      (candidate == key ||
          teams.any(
            (team) =>
                team.legacySessionId.isNotEmpty &&
                json.encode([
                      team.legacySessionId,
                      team.scheduledDate?.toIso8601String().split('T').first ??
                          '',
                    ]) ==
                    candidate,
          ));

  String get timeLabel => window.isConfigured
      ? '${window.label} · ${window.timeRange}'
      : DateFormat('h:mm a').format(startsAt);

  String get label =>
      '${DateFormat('MMM d, yyyy').format(startsAt)} · $timeLabel · ${teams.first.room}';
}
