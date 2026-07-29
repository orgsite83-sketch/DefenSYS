import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';

int? asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String normalizeName(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String formatScheduleDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

DateTime? parseHumanDate(String text) {
  final cleaned = text.trim().toLowerCase().replaceAll(',', '');
  final months = {
    'january': 1, 'jan': 1,
    'february': 2, 'feb': 2,
    'march': 3, 'mar': 3,
    'april': 4, 'apr': 4,
    'may': 5,
    'june': 6, 'jun': 6,
    'july': 7, 'jul': 7,
    'august': 8, 'aug': 8,
    'september': 9, 'sep': 9, 'sept': 9,
    'october': 10, 'oct': 10,
    'november': 11, 'nov': 11,
    'december': 12, 'dec': 12,
  };

  final match1 = RegExp(r'^([a-z]+)\s+(\d{1,2})\s+(\d{4})$').firstMatch(cleaned);
  if (match1 != null) {
    final monthStr = match1.group(1);
    final day = int.tryParse(match1.group(2) ?? '');
    final year = int.tryParse(match1.group(3) ?? '');
    final month = months[monthStr];
    if (month != null && day != null && year != null) {
      return DateTime(year, month, day);
    }
  }

  final match2 = RegExp(r'^(\d{1,2})\s+([a-z]+)\s+(\d{4})$').firstMatch(cleaned);
  if (match2 != null) {
    final day = int.tryParse(match2.group(1) ?? '');
    final monthStr = match2.group(2);
    final year = int.tryParse(match2.group(3) ?? '');
    final month = months[monthStr];
    if (month != null && day != null && year != null) {
      return DateTime(year, month, day);
    }
  }

  return null;
}

String normalizeImportDate(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(text);
  if (parsed != null) {
    return formatScheduleDate(parsed);
  }
  final humanParsed = parseHumanDate(text);
  if (humanParsed != null) {
    return formatScheduleDate(humanParsed);
  }

  // 1. Check YYYY first: YYYY-MM-DD, YYYY/MM/DD, YYYY.MM.DD
  final yearFirstMatch =
      RegExp(r'^(\d{4})[-/\.](\d{1,2})[-/\.](\d{1,2})$').firstMatch(text);
  if (yearFirstMatch != null) {
    final year =
        int.tryParse(yearFirstMatch.group(1) ?? '') ?? DateTime.now().year;
    final month = int.tryParse(yearFirstMatch.group(2) ?? '') ?? 1;
    final day = int.tryParse(yearFirstMatch.group(3) ?? '') ?? 1;
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return formatScheduleDate(DateTime(year, month, day));
    }
  }

  // 2. Check YYYY last: M/D/YYYY, MM/DD/YYYY, D/M/YYYY, DD/MM/YYYY
  final yearLastMatch =
      RegExp(r'^(\d{1,2})[-/\.](\d{1,2})[-/\.](\d{2,4})$').firstMatch(text);
  if (yearLastMatch != null) {
    final part1 = int.tryParse(yearLastMatch.group(1) ?? '') ?? 1;
    final part2 = int.tryParse(yearLastMatch.group(2) ?? '') ?? 1;
    var year =
        int.tryParse(yearLastMatch.group(3) ?? '') ?? DateTime.now().year;
    if (year < 100) {
      year += 2000;
    }
    int month;
    int day;
    if (part1 > 12 && part2 <= 12) {
      day = part1;
      month = part2;
    } else if (part2 > 12 && part1 <= 12) {
      month = part1;
      day = part2;
    } else {
      month = part1;
      day = part2;
    }
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return formatScheduleDate(DateTime(year, month, day));
    }
  }

  return text;
}

List<Map<String, dynamic>> teamsForScope(
  DefenseSchedulerState state,
  String scope,
) {
  return state.teams.where((team) {
    final level = team['level']?.toString() ?? '';
    return scope == 'pit'
        ? level.contains('PIT')
        : level.contains('Capstone');
  }).toList();
}

class ImportNameMatch {
  const ImportNameMatch({this.id, this.message = ''});

  final int? id;
  final String message;
}

class ScheduleImportPreviewRow {
  const ScheduleImportPreviewRow({
    required this.source,
    required this.scope,
    required this.teamId,
    required this.panelistIds,
    this.documenterId,
    required this.stageId,
    required this.eventName,
    required this.panelRubricId,
    required this.peerRubricId,
    required this.panelWeight,
    required this.peerWeight,
    required this.date,
    required this.room,
    required this.duration,
    required this.issues,
    required this.warnings,
  });

  final ParsedScheduleImportRow source;
  final String scope;
  final int? teamId;
  final List<int> panelistIds;
  final int? documenterId;
  final int? stageId;
  final String eventName;
  final int? panelRubricId;
  final int? peerRubricId;
  final int panelWeight;
  final int peerWeight;
  final String date;
  final String room;
  final int duration;
  final List<String> issues;
  final List<String> warnings;

  bool get ready => issues.isEmpty;
  bool get isPit => scope == 'pit';

  String get timeLabel {
    if (source.startTime.isEmpty) {
      return source.time.isEmpty ? '-' : source.time;
    }
    if (source.endTime.isEmpty) {
      return source.startTime;
    }
    return '${source.startTime} - ${source.endTime}';
  }

  String get teamLabel => source.teamName.isEmpty ? '-' : source.teamName;
  String get projectLabel =>
      source.projectTitle.isEmpty ? '-' : source.projectTitle;
  String get chairLabel => source.chair.isEmpty ? '-' : source.chair;
  String get panelLabel =>
      source.panelMembers.isEmpty ? '-' : source.panelMembers.join(', ');
  String get documenterLabel =>
      (!isPit && source.documenter.isNotEmpty) ? source.documenter : '-';

  Map<String, dynamic> toPayload() {
    if (scope == 'pit') {
      return {
        'scope': 'pit',
        'team_id': teamId,
        'event_name': eventName,
        'rubric_id': panelRubricId,
        'peer_rubric_id': peerRubricId,
        'panel_weight': panelWeight,
        'peer_weight': peerWeight,
        'scheduled_date': date,
        'start_time': source.startTime,
        'slot_duration': duration,
        'room': room,
        'panelist_ids': panelistIds,
      };
    }
    return {
      'scope': 'capstone',
      'team_id': teamId,
      'defense_stage_id': stageId,
      'event_name': '',
      'rubric_id': panelRubricId,
      'scheduled_date': date,
      'start_time': source.startTime,
      'slot_duration': duration,
      'room': room,
      'panelist_ids': panelistIds,
      if (documenterId != null) 'documenter_id': documenterId,
    };
  }
}

ImportNameMatch matchTeam(
  ParsedScheduleImportRow row,
  DefenseSchedulerState state, {
  String scope = 'capstone',
}) {
  final name = normalizeName(row.teamName);
  final project = normalizeName(row.projectTitle);
  final teams = teamsForScope(state, scope);
  final byName = teams.where((team) {
    return normalizeName(team['name']?.toString() ?? '') == name;
  }).toList();
  if (byName.length == 1) {
    final storedProject = byName.first['project_title']?.toString() ?? '';
    if (project.isNotEmpty && normalizeName(storedProject) != project) {
      return ImportNameMatch(
        id: asInt(byName.first['id']),
        message: 'Project title differs from the stored team project.',
      );
    }
    return ImportNameMatch(id: asInt(byName.first['id']));
  }
  if (byName.length > 1) {
    return const ImportNameMatch(message: 'Multiple teams match this name.');
  }
  if (project.isNotEmpty) {
    final byProject = teams.where((team) {
      return normalizeName(team['project_title']?.toString() ?? '') ==
          project;
    }).toList();
    if (byProject.length == 1) {
      return ImportNameMatch(
        id: asInt(byProject.first['id']),
        message: 'Matched by project title because team name was not found.',
      );
    }
  }
  return ImportNameMatch(message: 'Team "${row.teamName}" was not found.');
}

ImportNameMatch matchPanelist(String rawName, DefenseSchedulerState state) {
  final name = normalizeName(rawName);
  if (name.isEmpty) {
    return const ImportNameMatch(message: 'Panelist name is missing.');
  }
  final exact = state.panelists.where((panelist) {
    return normalizeName(panelist['name']?.toString() ?? '') == name ||
        normalizeName(panelist['username']?.toString() ?? '') == name;
  }).toList();
  if (exact.length == 1) {
    return ImportNameMatch(id: asInt(exact.first['id']));
  }
  if (exact.length > 1) {
    return ImportNameMatch(message: 'Panelist "$rawName" is ambiguous.');
  }

  final lastNameMatches = state.panelists.where((panelist) {
    final display = panelist['name']?.toString() ?? '';
    final parts = display.trim().split(RegExp(r'\s+'));
    final last = parts.isEmpty ? '' : parts.last;
    return normalizeName(last) == name;
  }).toList();
  if (lastNameMatches.length == 1) {
    return ImportNameMatch(id: asInt(lastNameMatches.first['id']));
  }
  if (lastNameMatches.length > 1) {
    return ImportNameMatch(
      message: 'Panelist "$rawName" matches multiple faculty.',
    );
  }
  return ImportNameMatch(message: 'Panelist "$rawName" was not found.');
}

ImportNameMatch matchDocumenter(String rawName, DefenseSchedulerState state) {
  final name = normalizeName(rawName);
  if (name.isEmpty) {
    return const ImportNameMatch();
  }
  final exact = state.documenters.where((doc) {
    return normalizeName(doc['name']?.toString() ?? '') == name ||
        normalizeName(doc['username']?.toString() ?? '') == name;
  }).toList();
  if (exact.length == 1) {
    return ImportNameMatch(id: asInt(exact.first['id']));
  }
  if (exact.length > 1) {
    return ImportNameMatch(message: 'Documenter "$rawName" is ambiguous.');
  }

  final lastNameMatches = state.documenters.where((doc) {
    final display = doc['name']?.toString() ?? '';
    final parts = display.trim().split(RegExp(r'\s+'));
    final last = parts.isEmpty ? '' : parts.last;
    return normalizeName(last) == name;
  }).toList();
  if (lastNameMatches.length == 1) {
    return ImportNameMatch(id: asInt(lastNameMatches.first['id']));
  }
  if (lastNameMatches.length > 1) {
    return ImportNameMatch(
      message: 'Documenter "$rawName" matches multiple documenters.',
    );
  }
  return ImportNameMatch(message: 'Documenter "$rawName" was not found.');
}

List<ScheduleImportPreviewRow> buildScheduleImportPreviewRows(
  ParsedScheduleImport parsed,
  DefenseSchedulerState state, {
  required String scope,
  required int? stageId,
  required String eventName,
  required String date,
  required String room,
  required int fallbackDuration,
  required int? panelRubricId,
  required int? adviserRubricId,
  required int? peerRubricId,
  required int panelWeight,
  required int peerWeight,
}) {
  final isPit = scope == 'pit';
  return parsed.rows.map((source) {
    final issues = <String>[];
    final warnings = <String>[];
    final rowDate = normalizeImportDate(source.date).isNotEmpty
        ? normalizeImportDate(source.date)
        : normalizeImportDate(date);
    final rowRoom = source.room.trim().isNotEmpty
        ? source.room.trim()
        : room.trim();
    final duration = source.slotDuration ?? fallbackDuration;
    final teamMatch = matchTeam(source, state, scope: scope);
    final panelistMatches = <ImportNameMatch>[];

    final chairMatch = matchPanelist(source.chair, state);
    if (source.chair.trim().isNotEmpty) {
      panelistMatches.add(chairMatch);
    }
    for (final name in source.panelMembers) {
      panelistMatches.add(matchPanelist(name, state));
    }

    int? documenterId;
    if (!isPit && source.documenter.trim().isNotEmpty) {
      final docMatch = matchDocumenter(source.documenter, state);
      if (docMatch.id == null) {
        issues.add(docMatch.message);
      } else {
        documenterId = docMatch.id;
      }
    }

    if (isPit) {
      if (eventName.trim().isEmpty) {
        issues.add('Select a PIT event.');
      }
      if (panelRubricId == null) {
        issues.add('Panel rubric is missing.');
      }
      if (peerRubricId == null) {
        issues.add('Peer rubric is missing.');
      }
    } else {
      if (stageId == null) {
        issues.add('Select a defense stage.');
      }
      if (panelRubricId == null ||
          adviserRubricId == null ||
          peerRubricId == null) {
        issues.add('Stage grading rubrics are incomplete.');
      }
    }
    if (rowDate.isEmpty) {
      issues.add('Date is missing.');
    }
    if (rowRoom.isEmpty) {
      issues.add('Room is missing.');
    }
    if (source.startTime.isEmpty) {
      issues.add('Time could not be parsed.');
    }
    if (duration < 15) {
      issues.add('Slot duration must be at least 15 minutes.');
    }
    if (teamMatch.id == null) {
      issues.add(teamMatch.message);
    } else if (teamMatch.message.isNotEmpty) {
      warnings.add(teamMatch.message);
    }
    final panelistIds = <int>[];
    for (final match in panelistMatches) {
      if (match.id == null) {
        issues.add(match.message);
      } else if (!panelistIds.contains(match.id)) {
        panelistIds.add(match.id!);
      }
    }
    if (panelistIds.isEmpty) {
      issues.add('At least one chair or panel member is required.');
    }

    return ScheduleImportPreviewRow(
      source: source,
      scope: scope,
      teamId: teamMatch.id,
      panelistIds: panelistIds,
      documenterId: documenterId,
      stageId: stageId,
      eventName: eventName,
      panelRubricId: panelRubricId,
      peerRubricId: peerRubricId,
      panelWeight: panelWeight,
      peerWeight: peerWeight,
      date: rowDate,
      room: rowRoom,
      duration: duration,
      issues: issues,
      warnings: warnings,
    );
  }).toList();
}
