import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/utils/defense_schedule_import_parser.dart';
import 'package:defensys/utils/string_matching_utils.dart';

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

  final completedStages = (team['completed_stages'] as List<dynamic>?)
          ?.map((e) => e.toString().trim())
          .toSet() ??
      {};
  final scheduledStages = (team['scheduled_stages'] as List<dynamic>?)
          ?.map((e) => e.toString().trim())
          .toSet() ??
      {};
  final stageProgress =
      (team['stage_progress'] as Map<String, dynamic>?) ?? {};

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
  String compact(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
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

ImportNameMatch matchPanelist(String rawName, DefenseSchedulerState state) {
  final name = normalizeName(rawName);
  if (name.isEmpty) {
    return const ImportNameMatch(message: 'Panelist name is missing.');
  }
  final pool = state.faculty.isNotEmpty ? state.faculty : state.panelists;

  // 1. Exact full name / username
  final exact = pool.where((panelist) {
    return normalizeName(panelist['name']?.toString() ?? '') == name ||
        normalizeName(panelist['username']?.toString() ?? '') == name;
  }).toList();
  if (exact.length == 1) {
    return ImportNameMatch(id: asInt(exact.first['id']));
  }
  if (exact.length > 1) {
    return ImportNameMatch(message: 'Panelist "$rawName" is ambiguous.');
  }

  // 2. Exact Last Name
  final lastNameMatches = pool.where((panelist) {
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

  // 3. Fuzzy Typo Match on Full Name or Last Name
  final fuzzyMatches = <Map<String, dynamic>>[];
  for (final panelist in pool) {
    final display = panelist['name']?.toString() ?? '';
    final parts = display.trim().split(RegExp(r'\s+'));
    final last = parts.isEmpty ? '' : parts.last;
    final simFull = stringSimilarity(rawName, display);
    final simLast = stringSimilarity(rawName, last);
    if (simFull >= 0.85 || simLast >= 0.85) {
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

  // 1. Exact full name / username
  final exact = pool.where((doc) {
    return normalizeName(doc['name']?.toString() ?? '') == name ||
        normalizeName(doc['username']?.toString() ?? '') == name;
  }).toList();
  if (exact.length == 1) {
    return ImportNameMatch(id: asInt(exact.first['id']));
  }
  if (exact.length > 1) {
    return ImportNameMatch(message: 'Documenter "$rawName" is ambiguous.');
  }

  // 2. Exact Last Name
  final lastNameMatches = pool.where((doc) {
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
  required int fallbackDuration,
  required int? panelRubricId,
  required int? adviserRubricId,
  required int? peerRubricId,
  required int panelWeight,
  required int peerWeight,
}) {
  final isPit = scope == 'pit';
  return parsed.rows.map((source) {
    final stageIssues = <String>[];
    final teamIssues = <String>[];
    final slotIssues = <String>[];
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
        slotIssues.add(docMatch.message);
      } else {
        documenterId = docMatch.id;
      }
    }

    if (isPit) {
      if (eventName.trim().isEmpty) {
        stageIssues.add('Select a PIT event.');
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
    if (source.startTime.isEmpty) {
      slotIssues.add('Time could not be parsed.');
    }
    if (duration < 15) {
      slotIssues.add('Slot duration must be at least 15 minutes.');
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

        final completedStages = (team['completed_stages'] as List?)
                ?.map((e) => e.toString().toLowerCase())
                .toList() ??
            [];
        final scheduledStages = (team['scheduled_stages'] as List?)
                ?.map((e) => e.toString().toLowerCase())
                .toList() ??
            [];
        final redefenseStages = (team['redefense_stages'] as List?)
                ?.map((e) => e.toString().toLowerCase())
                .toList() ??
            [];
        final readyForStage =
            (team['ready_for_stage']?.toString() ?? '').toLowerCase();

        final isCompleted = completedStages.contains(stageLower);
        final isScheduled = scheduledStages.contains(stageLower) ||
            state.schedules.any((s) =>
                asInt(s['team_id'] ?? s['team']?['id']) == teamMatch.id &&
                asInt(s['defense_stage_id'] ?? s['defense_stage']?['id']) == stageId &&
                s['status'] == 'scheduled');
        final isRedefense = redefenseStages.contains(stageLower) ||
            (team['stage_progress'] is Map &&
                team['stage_progress'][stageLabel] == 'for_redefense');
        final isEndorsed = readyForStage == stageLower ||
            (team['stage_progress'] is Map &&
                team['stage_progress'][stageLabel] == 'ready');

        if (isCompleted) {
          rowType = ScheduleImportRowType.alreadyPassed;
          teamIssues.add('$teamName has already completed and passed "$stageLabel".');
        } else if (isScheduled) {
          rowType = ScheduleImportRowType.alreadyScheduled;
          teamIssues.add('$teamName already has an active scheduled slot for "$stageLabel".');
        } else if (isRedefense) {
          rowType = ScheduleImportRowType.redefenseReady;
        } else if (isEndorsed) {
          rowType = ScheduleImportRowType.initialReady;
        } else {
          rowType = ScheduleImportRowType.notEndorsed;
          teamIssues.add('$teamName is not endorsed for "$stageLabel".');
        }
      } else {
        final isCompleted = state.schedules.any((s) =>
            asInt(s['team_id'] ?? s['team']?['id']) == teamMatch.id &&
            (s['event_name']?.toString() ?? '').toLowerCase() ==
                eventName.toLowerCase() &&
            s['status'] == 'done');
        final isScheduled = state.schedules.any((s) =>
            asInt(s['team_id'] ?? s['team']?['id']) == teamMatch.id &&
            (s['event_name']?.toString() ?? '').toLowerCase() ==
                eventName.toLowerCase() &&
            s['status'] == 'scheduled');

        if (isCompleted) {
          rowType = ScheduleImportRowType.alreadyPassed;
          teamIssues.add('$teamName has already completed "$eventName".');
        } else if (isScheduled) {
          rowType = ScheduleImportRowType.alreadyScheduled;
          teamIssues.add('$teamName already has an active scheduled slot for "$eventName".');
        } else {
          final readyFor =
              (team['ready_for_stage']?.toString() ?? '').toLowerCase();
          final pitConfig = state.pitEvents.firstWhere(
            (e) =>
                (e['event_name']?.toString() ?? '').toLowerCase() ==
                eventName.toLowerCase(),
            orElse: () => <String, dynamic>{},
          );
          final hasPre = (pitConfig['deliverables'] as List?)
                  ?.any((d) => d['deliverable_type'] == 'pre') ??
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
      stageIssues: stageIssues,
      teamIssues: teamIssues,
      slotIssues: slotIssues,
      issues: allIssues,
      warnings: warnings,
      rowType: rowType,
    );
  }).toList();
}
