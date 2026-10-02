import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:defensys/utils/string_matching_utils.dart';
import 'package:defensys/utils/import/schedule_import_timing.dart';

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
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sep': 9,
    'sept': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  };

  final match1 = RegExp(
    r'^([a-z]+)\s+(\d{1,2})\s+(\d{4})$',
  ).firstMatch(cleaned);
  if (match1 != null) {
    final monthStr = match1.group(1);
    final day = int.tryParse(match1.group(2) ?? '');
    final year = int.tryParse(match1.group(3) ?? '');
    final month = months[monthStr];
    if (month != null && day != null && year != null) {
      return DateTime(year, month, day);
    }
  }

  final match2 = RegExp(
    r'^(\d{1,2})\s+([a-z]+)\s+(\d{4})$',
  ).firstMatch(cleaned);
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
  final yearFirstMatch = RegExp(
    r'^(\d{4})[-/\.](\d{1,2})[-/\.](\d{1,2})$',
  ).firstMatch(text);
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
  final yearLastMatch = RegExp(
    r'^(\d{1,2})[-/\.](\d{1,2})[-/\.](\d{2,4})$',
  ).firstMatch(text);
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
  String scope, {
  String? yearLevel,
}) {
  return state.teams.where((team) {
    final level = team['level']?.toString() ?? '';
    final isPit = level.toUpperCase().contains('PIT');
    final isCapstone = level.toUpperCase().contains('CAPSTONE');
    if (scope == 'pit') {
      if (!isPit) return false;
      if (yearLevel != null && yearLevel.isNotEmpty && yearLevel != 'all') {
        return level.toLowerCase().contains(yearLevel.toLowerCase());
      }
      return true;
    }
    if (yearLevel != null && yearLevel.isNotEmpty && yearLevel != 'all') {
      return level.toLowerCase().contains(yearLevel.toLowerCase());
    }
    return isCapstone;
  }).toList();
}

/// Returns the stage lifecycle status for a team and milestone:
/// 'completed' (passed/done)
/// 'scheduled' (defense date set)
/// 'ready' (deliverables & endorsement complete, awaiting scheduling)
/// 'pending' (missing deliverables or awaiting instructor/adviser endorsement)
String getTeamStageStatus(Map<String, dynamic> team, String stageLabel) {
  if (stageLabel.isEmpty) return 'pending';

  final completedStages =
      (team['completed_stages'] as List<dynamic>?)
          ?.map((e) => e.toString().trim())
          .toSet() ??
      {};
  final scheduledStages =
      (team['scheduled_stages'] as List<dynamic>?)
          ?.map((e) => e.toString().trim())
          .toSet() ??
      {};
  final stageProgress = (team['stage_progress'] as Map<String, dynamic>?) ?? {};

  final progVal =
      stageProgress[stageLabel]?.toString().toLowerCase().trim() ?? '';
  if (progVal == 'completed' ||
      progVal == 'passed' ||
      progVal == 'archived' ||
      completedStages.contains(stageLabel)) {
    return 'completed';
  }
  if (progVal == 'scheduled' ||
      progVal == 'ongoing' ||
      scheduledStages.contains(stageLabel)) {
    return 'scheduled';
  }
  if (progVal == 'ready' ||
      team['ready_for_stage']?.toString().trim() == stageLabel) {
    if (!completedStages.contains(stageLabel) &&
        !scheduledStages.contains(stageLabel)) {
      return 'ready';
    }
  }
  return 'pending';
}

bool isTeamStageCompleted(Map<String, dynamic> team, String stageLabel) {
  return getTeamStageStatus(team, stageLabel) == 'completed';
}

bool isTeamStageReady(Map<String, dynamic> team, String stageLabel) {
  return getTeamStageStatus(team, stageLabel) == 'ready';
}

bool isTeamStageScheduled(Map<String, dynamic> team, String stageLabel) {
  return getTeamStageStatus(team, stageLabel) == 'scheduled';
}

class ImportNameMatch {
  const ImportNameMatch({this.id, this.message = ''});

  final int? id;
  final String message;
}

enum ScheduleImportRowType {
  initialReady,
  redefenseReady,
  alreadyPassed,
  alreadyScheduled,
  notEndorsed,
  invalid,
}

String addMinutesToTimeString(String time, int minutesToAdd) {
  final start = scheduleTimeMinutes(time, allowOverflow: true);
  return start == null || minutesToAdd <= 0
      ? time.trim()
      : scheduleTimeFromMinutes(start + minutesToAdd);
}

class ScheduleImportPreviewRow {
  const ScheduleImportPreviewRow({
    required this.source,
    required this.scope,
    required this.teamId,
    required this.panelistIds,
    this.chairPanelistId,
    required this.documenterId,
    required this.stageId,
    required this.eventName,
    required this.panelRubricId,
    required this.peerRubricId,
    required this.panelWeight,
    required this.peerWeight,
    required this.date,
    required this.room,
    required this.duration,
    this.scheduledStartTime,
    this.adviserId,
    this.adviserName,
    this.stageIssues = const <String>[],
    this.teamIssues = const <String>[],
    this.slotIssues = const <String>[],
    this.issues = const <String>[],
    required this.warnings,
    this.rowType = ScheduleImportRowType.invalid,
  });

  final ParsedScheduleImportRow source;
  final String scope;
  final int? teamId;
  final List<int> panelistIds;
  final int? chairPanelistId;
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
  final String? scheduledStartTime;
  final int? adviserId;
  final String? adviserName;
  final List<String> stageIssues;
  final List<String> teamIssues;
  final List<String> slotIssues;
  final List<String> issues;
  final List<String> warnings;
  final ScheduleImportRowType rowType;

  bool get hasStageIssue => stageIssues.isNotEmpty;
  bool get hasTeamIssue => teamIssues.isNotEmpty;
  bool get hasSlotIssue => slotIssues.isNotEmpty;

  bool get ready =>
      issues.isEmpty &&
      (rowType == ScheduleImportRowType.initialReady ||
          rowType == ScheduleImportRowType.redefenseReady);
  bool get isPit => scope == 'pit';
  bool get isRedefense => rowType == ScheduleImportRowType.redefenseReady;
  bool get isAlreadyPassed => rowType == ScheduleImportRowType.alreadyPassed;
  bool get isAlreadyScheduled =>
      rowType == ScheduleImportRowType.alreadyScheduled;
  bool get isNotEndorsed => rowType == ScheduleImportRowType.notEndorsed;

  String get effectiveStartTime {
    final value = scheduledStartTime ?? source.startTime;
    final minutes = scheduleTimeMinutes(value, allowOverflow: true);
    return minutes == null ? value : scheduleTimeFromMinutes(minutes);
  }

  bool get startTimeChanged =>
      scheduleTimeMinutes(effectiveStartTime, allowOverflow: true) !=
      scheduleTimeMinutes(source.startTime, allowOverflow: true);

  Set<int> get attendanceIds => {
    ...panelistIds,
    if (documenterId != null) documenterId!,
    if (adviserId != null) adviserId!,
  };

  String get effectiveEndTime {
    if (effectiveStartTime.isEmpty) return source.endTime;
    if (duration > 0) {
      return addMinutesToTimeString(effectiveStartTime, duration);
    }
    return source.endTime;
  }

  String get timeLabel {
    if (effectiveStartTime.isEmpty) {
      return source.time.isEmpty ? '-' : source.time;
    }
    final end = effectiveEndTime;
    if (end.isEmpty) {
      return effectiveStartTime;
    }
    return '$effectiveStartTime - $end';
  }

  String get teamLabel => source.teamName.isEmpty ? '-' : source.teamName;
  String get projectLabel =>
      source.projectTitle.isEmpty ? '-' : source.projectTitle;
  String get chairLabel => source.chair.isEmpty ? '-' : source.chair;
  String get panelLabel =>
      source.panelMembers.isEmpty ? '-' : source.panelMembers.join(', ');
  String get documenterLabel =>
      (!isPit && source.documenter.isNotEmpty) ? source.documenter : '-';
  String get adviserLabel => adviserName ?? source.adviser;

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
        'start_time': effectiveStartTime,
        'slot_duration': duration,
        'room': room,
        'panelist_ids': panelistIds,
        if (chairPanelistId != null) 'chair_panelist_id': chairPanelistId,
      };
    }
    return {
      'scope': 'capstone',
      'team_id': teamId,
      'defense_stage_id': stageId,
      'event_name': '',
      'rubric_id': panelRubricId,
      'scheduled_date': date,
      'start_time': effectiveStartTime,
      'slot_duration': duration,
      'room': room,
      'panelist_ids': panelistIds,
      if (chairPanelistId != null) 'chair_panelist_id': chairPanelistId,
      if (documenterId != null) 'documenter_id': documenterId,
    };
  }
}

ImportNameMatch matchTeam(
  ParsedScheduleImportRow row,
  DefenseSchedulerState state, {
  String scope = 'capstone',
}) {
  final rawTeamName = row.teamName.trim();
  final name = normalizeName(rawTeamName);
  final project = normalizeName(row.projectTitle);
  final teams = teamsForScope(state, scope);

  // 1. Exact Name Match
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

  // 2. Project Title Match
  if (project.isNotEmpty) {
    final byProject = teams.where((team) {
      return normalizeName(team['project_title']?.toString() ?? '') == project;
    }).toList();
    if (byProject.length == 1) {
      return ImportNameMatch(
        id: asInt(byProject.first['id']),
        message: 'Matched by project title because team name was not found.',
      );
    }
  }

  // 3. Compact / Whitespace-stripped match (e.g. "Nova Path" <-> "NovaPath", "Byte-Force" <-> "ByteForce")
  String compact(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final compactName = compact(rawTeamName);
  if (compactName.isNotEmpty) {
    final byCompact = teams.where((team) {
      return compact(team['name']?.toString() ?? '') == compactName;
    }).toList();
    if (byCompact.length == 1) {
      final matchedName = byCompact.first['name']?.toString() ?? '';
      return ImportNameMatch(
        id: asInt(byCompact.first['id']),
        message: 'Matched to "$matchedName" (spacing/punctuation difference).',
      );
    }
  }

  // 4. Fuzzy Typo Match (e.g. "DigiSlove" <-> "DigiSolve")
  if (rawTeamName.isNotEmpty) {
    final fuzzyMatches = <Map<String, dynamic>>[];
    for (final team in teams) {
      final teamName = team['name']?.toString() ?? '';
      final sim = stringSimilarity(rawTeamName, teamName);
      if (sim >= 0.82) {
        fuzzyMatches.add(team);
      }
    }
    if (fuzzyMatches.length == 1) {
      final matched = fuzzyMatches.first;
      final matchedName = matched['name']?.toString() ?? '';
      return ImportNameMatch(
        id: asInt(matched['id']),
        message: 'Matched to "$matchedName" (typo in file: "$rawTeamName").',
      );
    }
  }

  return ImportNameMatch(message: 'Team "${row.teamName}" was not found.');
}

final _prefixRegExp = RegExp(
  r"^(?:associate\s+professor|assistant\s+professor|assoc\.?\s*prof\.?|asst\.?\s*prof\.?|prof(?:essor)?\.?|dr\.?|doctor|engr\.?|engineer|atty\.?|attorney|arch(?:itect)?\.?|dean|chair(?:person)?|inst(?:ructor)?\.?|lect(?:urer)?\.?|hon(?:orable)?\.?|rev(?:erend)?\.?|pastor|pst\.?|fr\.?|father|mr\.?|mrs\.?|ms\.?|mx\.?|sir|ma['\u2019]?am|mam)\b[\s\.]*",
  caseSensitive: false,
);

final _suffixRegExp = RegExp(
  r'(?:[\s,\.]+|\b)(?:ph\.?d\.?|d\.?eng\.?|d\.?i\.?t\.?|d\.?b\.?a\.?|ed\.?d\.?|m\.?d\.?|j\.?d\.?|sc\.?d\.?|m\.?sc\.?|m\.?s\.?|m\.?a\.?|m\.?eng\.?|m\.?i\.?t\.?|m\.?s\.?i\.?t\.?|m\.?b\.?a\.?|m\.?p\.?a\.?|m\.?ed\.?|b\.?sc\.?|b\.?s\.?|b\.?a\.?|b\.?s\.?i\.?t\.?|p\.?e\.?|c\.?p\.?a\.?|rce|ece|ree|rme|pmp|cisa|cissp|jr\.?|sr\.?|ii|iii|iv|v)\.?$',
  caseSensitive: false,
);

String cleanPersonName(String value) {
  var s = value.trim();
  String? prev;
  while (s != prev) {
    prev = s;
    s = s.replaceAll(_suffixRegExp, '').trim();
    s = s.replaceAll(_prefixRegExp, '').trim();
  }
  if (s.contains(',')) {
    final parts = s
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length == 2) {
      final last = parts[0].replaceAll(_prefixRegExp, '').trim();
      final first = parts[1].replaceAll(_prefixRegExp, '').trim();
      return '$first $last'.trim();
    }
  }
  return s;
}

ImportNameMatch matchPanelist(String rawName, DefenseSchedulerState state) {
  final name = normalizeName(rawName);
  if (name.isEmpty) {
    return const ImportNameMatch(message: 'Panelist name is missing.');
  }
  final pool = state.faculty.isNotEmpty ? state.faculty : state.panelists;
  final cleanInput = normalizeName(cleanPersonName(rawName));

  // 1. Exact full name / username / title-cleaned name
  final exact = pool.where((panelist) {
    final pName = panelist['name']?.toString() ?? '';
    final pUser = panelist['username']?.toString() ?? '';
    final normPName = normalizeName(pName);
    final normPUser = normalizeName(pUser);
    if (normPName == name || normPUser == name) return true;
    if (cleanInput.isNotEmpty) {
      final cleanPName = normalizeName(cleanPersonName(pName));
      if (cleanPName == cleanInput || normPName == cleanInput) return true;
    }
    return false;
  }).toList();
  if (exact.length == 1) {
    return ImportNameMatch(id: asInt(exact.first['id']));
  }
  if (exact.length > 1) {
    return ImportNameMatch(message: 'Panelist "$rawName" is ambiguous.');
  }

  // 2. Exact Last Name (checking raw and cleaned)
  final cleanLastInput = cleanInput.split(RegExp(r'\s+')).last;
  final lastNameMatches = pool.where((panelist) {
    final display = panelist['name']?.toString() ?? '';
    final parts = display.trim().split(RegExp(r'\s+'));
    final last = parts.isEmpty ? '' : parts.last;
    final normLast = normalizeName(last);
    final cleanLast = normalizeName(cleanPersonName(last));
    return normLast == name ||
        normLast == cleanInput ||
        (cleanLastInput.isNotEmpty &&
            cleanLast == cleanLastInput &&
            cleanInput.split(RegExp(r'\s+')).length == 1);
  }).toList();
  if (lastNameMatches.length == 1) {
    return ImportNameMatch(id: asInt(lastNameMatches.first['id']));
  }
  if (lastNameMatches.length > 1) {
    return ImportNameMatch(
      message: 'Panelist "$rawName" matches multiple faculty.',
    );
  }

  // 3. Fuzzy Typo Match on Full Name or Last Name
  final fuzzyMatches = <Map<String, dynamic>>[];
  for (final panelist in pool) {
    final display = panelist['name']?.toString() ?? '';
    final parts = display.trim().split(RegExp(r'\s+'));
    final last = parts.isEmpty ? '' : parts.last;
    final simFull = stringSimilarity(rawName, display);
    final simLast = stringSimilarity(rawName, last);
    final simClean = cleanInput.isNotEmpty
        ? stringSimilarity(cleanInput, normalizeName(cleanPersonName(display)))
        : 0.0;
    if (simFull >= 0.85 || simLast >= 0.85 || simClean >= 0.85) {
      fuzzyMatches.add(panelist);
    }
  }
  if (fuzzyMatches.length == 1) {
    final matched = fuzzyMatches.first;
    final matchedName = matched['name']?.toString() ?? '';
    return ImportNameMatch(
      id: asInt(matched['id']),
      message: 'Matched to "$matchedName" (typo in file: "$rawName").',
    );
  }

  return ImportNameMatch(message: 'Panelist "$rawName" was not found.');
}

ImportNameMatch matchDocumenter(String rawName, DefenseSchedulerState state) {
  final name = normalizeName(rawName);
  if (name.isEmpty) {
    return const ImportNameMatch();
  }
  final pool = state.faculty.isNotEmpty ? state.faculty : state.documenters;
  final cleanInput = normalizeName(cleanPersonName(rawName));

  // 1. Exact full name / username / title-cleaned name
  final exact = pool.where((doc) {
    final dName = doc['name']?.toString() ?? '';
    final dUser = doc['username']?.toString() ?? '';
    final normDName = normalizeName(dName);
    final normDUser = normalizeName(dUser);
    if (normDName == name || normDUser == name) return true;
    if (cleanInput.isNotEmpty) {
      final cleanDName = normalizeName(cleanPersonName(dName));
      if (cleanDName == cleanInput || normDName == cleanInput) return true;
    }
    return false;
  }).toList();
  if (exact.length == 1) {
    return ImportNameMatch(id: asInt(exact.first['id']));
  }
  if (exact.length > 1) {
    return ImportNameMatch(message: 'Documenter "$rawName" is ambiguous.');
  }

  // 2. Exact Last Name (checking raw and cleaned)
  final cleanLastInput = cleanInput.split(RegExp(r'\s+')).last;
  final lastNameMatches = pool.where((doc) {
    final display = doc['name']?.toString() ?? '';
    final parts = display.trim().split(RegExp(r'\s+'));
    final last = parts.isEmpty ? '' : parts.last;
    final normLast = normalizeName(last);
    final cleanLast = normalizeName(cleanPersonName(last));
    return normLast == name ||
        normLast == cleanInput ||
        (cleanLastInput.isNotEmpty &&
            cleanLast == cleanLastInput &&
            cleanInput.split(RegExp(r'\s+')).length == 1);
  }).toList();
  if (lastNameMatches.length == 1) {
    return ImportNameMatch(id: asInt(lastNameMatches.first['id']));
  }
  if (lastNameMatches.length > 1) {
    return ImportNameMatch(
      message: 'Documenter "$rawName" matches multiple documenters.',
    );
  }

  // 3. Fuzzy Typo Match on Full Name or Last Name
  final fuzzyMatches = <Map<String, dynamic>>[];
  for (final doc in pool) {
    final display = doc['name']?.toString() ?? '';
    final parts = display.trim().split(RegExp(r'\s+'));
    final last = parts.isEmpty ? '' : parts.last;
    final simFull = stringSimilarity(rawName, display);
    final simLast = stringSimilarity(rawName, last);
    if (simFull >= 0.85 || simLast >= 0.85) {
      fuzzyMatches.add(doc);
    }
  }
  if (fuzzyMatches.length == 1) {
    final matched = fuzzyMatches.first;
    final matchedName = matched['name']?.toString() ?? '';
    return ImportNameMatch(
      id: asInt(matched['id']),
      message: 'Matched to "$matchedName" (typo in file: "$rawName").',
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
  int? slotDuration,
  bool reflowStartTimes = true,
  required int fallbackDuration,
  required int? panelRubricId,
  required int? adviserRubricId,
  required int? peerRubricId,
  required int panelWeight,
  required int peerWeight,
}) {
  final isPit = scope == 'pit';
  final effectiveSlotDuration = slotDuration;
  final starts = <int, String>{};
  if (reflowStartTimes &&
      slotDuration != null &&
      slotDuration >= 15 &&
      slotDuration <= 240) {
    final timingInputs = <ScheduleTimingInput>[];
    for (var i = 0; i < parsed.rows.length; i++) {
      final source = parsed.rows[i];
      final start = scheduleTimeMinutes(source.startTime);
      if (start == null) continue;
      final end = scheduleTimeMinutes(source.endTime, allowOverflow: true);
      timingInputs.add(
        ScheduleTimingInput(
          index: i,
          date: normalizeImportDate(
            source.date.trim().isEmpty ? date : source.date,
          ),
          room: source.room.trim().isEmpty ? room : source.room,
          start: start,
          originalDuration: end != null && end > start
              ? end - start
              : source.slotDuration ?? fallbackDuration,
        ),
      );
    }
    starts.addAll(reflowScheduleStarts(timingInputs, slotDuration));
  }
  final rows = parsed.rows.asMap().entries.map((entry) {
    final source = entry.value;
    final startTime = starts[entry.key] ?? source.startTime;
    final stageIssues = <String>[];
    final teamIssues = <String>[];
    final slotIssues = <String>[...source.parseIssues];
    final warnings = <String>[];
    final rowDate = normalizeImportDate(source.date).isNotEmpty
        ? normalizeImportDate(source.date)
        : normalizeImportDate(date);
    final rowRoom = source.room.trim().isNotEmpty
        ? source.room.trim()
        : room.trim();
    final duration =
        effectiveSlotDuration ?? (source.slotDuration ?? fallbackDuration);
    final teamMatch = matchTeam(source, state, scope: scope);
    final matchedTeam = state.teams
        .where((team) => asInt(team['id']) == teamMatch.id)
        .firstOrNull;
    // The imported schedule uses the team's assigned adviser, which may differ
    // from an outdated spreadsheet. Validate that person's availability.
    final storedAdviser = matchedTeam?['adviser_name']?.toString().trim() ?? '';
    final adviserName = storedAdviser.isEmpty ? source.adviser : storedAdviser;
    final panelistMatches = <ImportNameMatch>[];

    final chairMatch = matchPanelist(source.chair, state);
    if (source.chair.trim().isNotEmpty) {
      panelistMatches.add(chairMatch);
    } else {
      slotIssues.add(
        'Chair is missing. Check the Chair / Panel Chair / Chair Panel header and cell.',
      );
    }
    for (final name in source.panelMembers) {
      panelistMatches.add(matchPanelist(name, state));
    }

    int? documenterId;
    if (!isPit && source.documenter.trim().isNotEmpty) {
      final docMatch = matchDocumenter(source.documenter, state);
      if (docMatch.id == null) {
        slotIssues.add(docMatch.message);
      } else {
        documenterId = docMatch.id;
      }
    }

    if (isPit) {
      if (eventName.trim().isEmpty) {
        stageIssues.add('Select a PIT event.');
      } else if (source.stage.trim().isNotEmpty) {
        final eventMatch = findBestMatch<Map<String, dynamic>>(
          source: source.stage,
          items: state.pitEvents,
          labelGetter: (e) => e['event_name']?.toString() ?? '',
        );
        if (eventMatch.isMatched) {
          if (eventMatch.label.trim().toLowerCase() !=
              eventName.trim().toLowerCase()) {
            stageIssues.add(
              'Spreadsheet event "${source.stage}" matches "${eventMatch.label}", not active event "$eventName".',
            );
          }
        } else {
          stageIssues.add(
            'Spreadsheet event "${source.stage}" does not match active event "$eventName".',
          );
        }
      }
      if (panelRubricId == null) {
        stageIssues.add('Panel rubric is missing.');
      }
      if (peerRubricId == null) {
        stageIssues.add('Peer rubric is missing.');
      }
    } else {
      if (stageId == null) {
        stageIssues.add('Select a defense stage.');
      } else {
        final stageObj = state.defenseStages.firstWhere(
          (s) => asInt(s['id']) == stageId,
          orElse: () => <String, dynamic>{},
        );
        final targetStageLabel = stageObj['label']?.toString() ?? '';
        if (targetStageLabel.isNotEmpty && source.stage.trim().isNotEmpty) {
          final stageMatch = findBestMatch<Map<String, dynamic>>(
            source: source.stage,
            items: state.defenseStages,
            labelGetter: (s) => s['label']?.toString() ?? '',
          );
          if (stageMatch.isMatched) {
            final matchedId = asInt(stageMatch.item?['id']);
            if (matchedId != stageId) {
              stageIssues.add(
                'Spreadsheet stage "${source.stage}" matches "${stageMatch.label}", not active stage "$targetStageLabel".',
              );
            }
          } else {
            stageIssues.add(
              'Spreadsheet stage "${source.stage}" does not match active stage "$targetStageLabel".',
            );
          }
        }
      }
      if (panelRubricId == null ||
          adviserRubricId == null ||
          peerRubricId == null) {
        stageIssues.add('Stage grading rubrics are incomplete.');
      }
    }
    if (rowDate.isEmpty) {
      slotIssues.add('Date is missing.');
    }
    if (rowRoom.isEmpty) {
      slotIssues.add('Room is missing.');
    }
    final startMinutes = scheduleTimeMinutes(startTime, allowOverflow: true);
    if (startMinutes == null) {
      slotIssues.add('Time could not be parsed.');
    } else if (startMinutes >= 1440 || startMinutes + duration > 1440) {
      slotIssues.add(
        'Slot extends past midnight. Shorten the duration or move this session to another date.',
      );
    }
    if (duration < 15 || duration > 240) {
      slotIssues.add('Slot duration must be between 15 and 240 minutes.');
    }
    var rowType = ScheduleImportRowType.invalid;

    if (teamMatch.id == null) {
      teamIssues.add(teamMatch.message);
      rowType = ScheduleImportRowType.invalid;
    } else {
      if (teamMatch.message.isNotEmpty) {
        warnings.add(teamMatch.message);
      }
      final team = state.teams.firstWhere(
        (t) => asInt(t['id']) == teamMatch.id,
        orElse: () => <String, dynamic>{},
      );
      final teamName = team['name']?.toString() ?? source.teamName;

      if (!isPit) {
        final stageObj = state.defenseStages.firstWhere(
          (s) => asInt(s['id']) == stageId,
          orElse: () => <String, dynamic>{},
        );
        final stageLabel = stageObj['label']?.toString() ?? '';
        final stageLower = stageLabel.toLowerCase();

        final completedStages =
            (team['completed_stages'] as List?)
                ?.map((e) => e.toString().toLowerCase())
                .toList() ??
            [];
        final scheduledStages =
            (team['scheduled_stages'] as List?)
                ?.map((e) => e.toString().toLowerCase())
                .toList() ??
            [];
        final redefenseStages =
            (team['redefense_stages'] as List?)
                ?.map((e) => e.toString().toLowerCase())
                .toList() ??
            [];
        final readyForStage = (team['ready_for_stage']?.toString() ?? '')
            .toLowerCase();

        final isCompleted = completedStages.contains(stageLower);
        final isScheduled =
            scheduledStages.contains(stageLower) ||
            state.schedules.any(
              (s) =>
                  asInt(s['team_id'] ?? s['team']?['id']) == teamMatch.id &&
                  asInt(s['defense_stage_id'] ?? s['defense_stage']?['id']) ==
                      stageId &&
                  s['status'] == 'scheduled',
            );
        final isRedefense =
            redefenseStages.contains(stageLower) ||
            (team['stage_progress'] is Map &&
                team['stage_progress'][stageLabel] == 'for_redefense');
        final isEndorsed =
            readyForStage == stageLower ||
            (team['stage_progress'] is Map &&
                team['stage_progress'][stageLabel] == 'ready');

        if (isCompleted) {
          rowType = ScheduleImportRowType.alreadyPassed;
          teamIssues.add(
            '$teamName has already completed and passed "$stageLabel".',
          );
        } else if (isScheduled) {
          rowType = ScheduleImportRowType.alreadyScheduled;
          teamIssues.add(
            '$teamName already has an active scheduled slot for "$stageLabel".',
          );
        } else if (isRedefense) {
          rowType = ScheduleImportRowType.redefenseReady;
        } else if (isEndorsed) {
          rowType = ScheduleImportRowType.initialReady;
        } else {
          rowType = ScheduleImportRowType.notEndorsed;
          teamIssues.add('$teamName is not endorsed for "$stageLabel".');
        }
      } else {
        final isCompleted = state.schedules.any(
          (s) =>
              asInt(s['team_id'] ?? s['team']?['id']) == teamMatch.id &&
              (s['event_name']?.toString() ?? '').toLowerCase() ==
                  eventName.toLowerCase() &&
              s['status'] == 'done',
        );
        final isScheduled = state.schedules.any(
          (s) =>
              asInt(s['team_id'] ?? s['team']?['id']) == teamMatch.id &&
              (s['event_name']?.toString() ?? '').toLowerCase() ==
                  eventName.toLowerCase() &&
              s['status'] == 'scheduled',
        );

        if (isCompleted) {
          rowType = ScheduleImportRowType.alreadyPassed;
          teamIssues.add('$teamName has already completed "$eventName".');
        } else if (isScheduled) {
          rowType = ScheduleImportRowType.alreadyScheduled;
          teamIssues.add(
            '$teamName already has an active scheduled slot for "$eventName".',
          );
        } else {
          final readyFor = (team['ready_for_stage']?.toString() ?? '')
              .toLowerCase();
          final pitConfig = state.pitEvents.firstWhere(
            (e) =>
                (e['event_name']?.toString() ?? '').toLowerCase() ==
                eventName.toLowerCase(),
            orElse: () => <String, dynamic>{},
          );
          final hasPre =
              (pitConfig['deliverables'] as List?)?.any(
                (d) => d['deliverable_type'] == 'pre',
              ) ??
              false;

          if (hasPre && readyFor != eventName.toLowerCase()) {
            rowType = ScheduleImportRowType.notEndorsed;
            teamIssues.add('$teamName is not endorsed for "$eventName".');
          } else {
            rowType = ScheduleImportRowType.initialReady;
          }
        }
      }
    }

    final panelistIds = <int>[];
    for (final match in panelistMatches) {
      if (match.id == null) {
        slotIssues.add(match.message);
      } else if (!panelistIds.contains(match.id)) {
        panelistIds.add(match.id!);
      }
    }
    if (panelistIds.isEmpty) {
      slotIssues.add('At least one chair or panel member is required.');
    }

    final allIssues = <String>[...stageIssues, ...teamIssues, ...slotIssues];

    return ScheduleImportPreviewRow(
      source: source,
      scope: scope,
      teamId: teamMatch.id,
      panelistIds: panelistIds,
      chairPanelistId: chairMatch.id,
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
      scheduledStartTime: startTime,
      adviserName: adviserName,
      adviserId: adviserName.trim().isEmpty
          ? null
          : asInt(matchedTeam?['adviser_id']) ??
                matchPanelist(adviserName, state).id,
      stageIssues: stageIssues,
      teamIssues: teamIssues,
      slotIssues: slotIssues,
      issues: allIssues,
      warnings: warnings,
      rowType: rowType,
    );
  }).toList();
  final byTeam = <int, List<ScheduleImportPreviewRow>>{};
  for (final row in rows) {
    if (row.teamId != null) (byTeam[row.teamId!] ??= []).add(row);
  }
  for (final duplicates in byTeam.values.where((group) => group.length > 1)) {
    for (final row in duplicates) {
      final sources = duplicates
          .where((other) => !identical(other, row))
          .map(
            (other) =>
                '${other.source.sourceFileName.isEmpty ? 'Spreadsheet' : other.source.sourceFileName} row ${other.source.sheetRow}',
          )
          .join(', ');
      final issue =
          'Duplicate team in this draft: $sources. Keep one schedule for this team.';
      row.teamIssues.add(issue);
      row.issues.add(issue);
    }
  }
  _validatePreviewTimeConflicts(rows, state);
  return rows;
}

/// Only the newly built preview lists are amended. The parsed spreadsheet and
/// scheduler state remain untouched while the user tries different durations.
void _validatePreviewTimeConflicts(
  List<ScheduleImportPreviewRow> rows,
  DefenseSchedulerState state,
) {
  void addIssue(ScheduleImportPreviewRow row, String issue) {
    if (!row.slotIssues.contains(issue)) {
      row.slotIssues.add(issue);
      row.issues.add(issue);
    }
  }

  String resourceDescription(
    ScheduleImportPreviewRow row,
    String otherRoom,
    Set<int> otherStaff,
    int? otherTeam,
  ) {
    final resources = <String>[];
    if (row.room.trim().isNotEmpty &&
        normalizeName(row.room) == normalizeName(otherRoom)) {
      resources.add('room already occupied');
    }
    final shared = row.attendanceIds.intersection(otherStaff);
    if (shared.isNotEmpty) {
      final pool = state.faculty.isEmpty ? state.panelists : state.faculty;
      final names = shared
          .map(
            (id) =>
                pool
                    .where((person) => asInt(person['id']) == id)
                    .map(
                      (person) => person['name']?.toString() ?? 'Faculty #$id',
                    )
                    .firstOrNull ??
                'Faculty #$id',
          )
          .join(', ');
      resources.add('$names double-booked');
    }
    if (row.teamId != null && row.teamId == otherTeam) {
      resources.add('team already occupied');
    }
    return resources.join('; ');
  }

  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final start = scheduleTimeMinutes(row.effectiveStartTime);
    if (start == null ||
        row.duration < 15 ||
        row.duration > 240 ||
        row.date.isEmpty) {
      continue;
    }
    final end = start + row.duration;
    for (var j = i + 1; j < rows.length; j++) {
      final other = rows[j];
      final otherStart = scheduleTimeMinutes(other.effectiveStartTime);
      if (otherStart == null ||
          other.date != row.date ||
          other.duration < 15 ||
          other.duration > 240 ||
          !scheduleIntervalsOverlap(
            start,
            end,
            otherStart,
            otherStart + other.duration,
          )) {
        continue;
      }
      final resource = resourceDescription(
        row,
        other.room,
        other.attendanceIds,
        other.teamId,
      );
      if (resource.isEmpty) continue;
      addIssue(
        row,
        'Time overlap with ${other.teamLabel} (${other.timeLabel}, ${other.room}): $resource.',
      );
      addIssue(
        other,
        'Time overlap with ${row.teamLabel} (${row.timeLabel}, ${row.room}): $resource.',
      );
    }
    for (final existing in state.schedules) {
      if (existing['status'] != 'scheduled' ||
          normalizeImportDate(existing['scheduled_date']?.toString()) !=
              row.date) {
        continue;
      }
      final otherStart = scheduleTimeMinutes(
        existing['start_time']?.toString() ?? '',
      );
      final otherDuration = asInt(existing['slot_duration']) ?? 60;
      if (otherStart == null ||
          !scheduleIntervalsOverlap(
            start,
            end,
            otherStart,
            otherStart + otherDuration,
          )) {
        continue;
      }
      final staff = <int>{
        for (final person in (existing['panelists'] as List? ?? []))
          if (person is Map && asInt(person['id']) != null)
            asInt(person['id'])!,
        if (asInt(existing['documenter']) != null)
          asInt(existing['documenter'])!,
        if (asInt(existing['adviser_id']) != null)
          asInt(existing['adviser_id'])!,
      };
      final otherRoom = existing['room']?.toString() ?? '';
      final resource = resourceDescription(
        row,
        otherRoom,
        staff,
        asInt(existing['team_id']),
      );
      if (resource.isEmpty) continue;
      final label = existing['team_name']?.toString() ?? 'an existing defense';
      final interval =
          '${scheduleTimeFromMinutes(otherStart)} - ${scheduleTimeFromMinutes(otherStart + otherDuration)}';
      addIssue(
        row,
        'Time overlap with scheduled $label ($interval, $otherRoom): $resource.',
      );
    }
  }
}
