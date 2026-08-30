import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_storage_keys.dart';
import '../../services/session/session_storage.dart';
import 'defense_schedule_import_parser.dart';

const _draftKeyPrefix = 'defense_schedule_import_draft';

class ScheduleImportDraft {
  const ScheduleImportDraft({
    required this.parsed,
    required this.scope,
    required this.savedAt,
    this.fileName,
    this.stageId,
    this.eventName = '',
    this.date = '',
    this.room = '',
    this.duration = '60',
    this.panelRubricId,
    this.adviserRubricId,
    this.peerRubricId,
    this.panelWeight = 80,
    this.peerWeight = 20,
    this.rowCount = 0,
    this.readyCount = 0,
    this.issueCount = 0,
    this.isOpen = true,
  });

  final ParsedScheduleImport parsed;
  final String scope;
  final String? fileName;
  final int? stageId;
  final String eventName;
  final String date;
  final String room;
  final String duration;
  final int? panelRubricId;
  final int? adviserRubricId;
  final int? peerRubricId;
  final int panelWeight;
  final int peerWeight;
  final DateTime savedAt;
  final int rowCount;
  final int readyCount;
  final int issueCount;
  final bool isOpen;

  Map<String, dynamic> toJson() => {
        'parsed': parsed.toJson(),
        'scope': scope,
        'file_name': fileName,
        'stage_id': stageId,
        'event_name': eventName,
        'date': date,
        'room': room,
        'duration': duration,
        'panel_rubric_id': panelRubricId,
        'adviser_rubric_id': adviserRubricId,
        'peer_rubric_id': peerRubricId,
        'panel_weight': panelWeight,
        'peer_weight': peerWeight,
        'saved_at': savedAt.toIso8601String(),
        'row_count': rowCount,
        'ready_count': readyCount,
        'issue_count': issueCount,
        'is_open': isOpen,
      };

  factory ScheduleImportDraft.fromJson(Map<String, dynamic> json) {
    final parsedMap = json['parsed'] is Map
        ? Map<String, dynamic>.from(json['parsed'] as Map)
        : <String, dynamic>{};
    return ScheduleImportDraft(
      parsed: ParsedScheduleImport.fromJson(parsedMap),
      scope: json['scope']?.toString() ?? 'capstone',
      fileName: json['file_name']?.toString(),
      stageId: json['stage_id'] is int
          ? json['stage_id'] as int
          : int.tryParse(json['stage_id']?.toString() ?? ''),
      eventName: json['event_name']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      room: json['room']?.toString() ?? '',
      duration: json['duration']?.toString() ?? '60',
      panelRubricId: json['panel_rubric_id'] is int
          ? json['panel_rubric_id'] as int
          : int.tryParse(json['panel_rubric_id']?.toString() ?? ''),
      adviserRubricId: json['adviser_rubric_id'] is int
          ? json['adviser_rubric_id'] as int
          : int.tryParse(json['adviser_rubric_id']?.toString() ?? ''),
      peerRubricId: json['peer_rubric_id'] is int
          ? json['peer_rubric_id'] as int
          : int.tryParse(json['peer_rubric_id']?.toString() ?? ''),
      panelWeight: json['panel_weight'] is int
          ? json['panel_weight'] as int
          : int.tryParse(json['panel_weight']?.toString() ?? '') ?? 80,
      peerWeight: json['peer_weight'] is int
          ? json['peer_weight'] as int
          : int.tryParse(json['peer_weight']?.toString() ?? '') ?? 20,
      savedAt: DateTime.tryParse(json['saved_at']?.toString() ?? '') ??
          DateTime.now(),
      rowCount: json['row_count'] is int
          ? json['row_count'] as int
          : int.tryParse(json['row_count']?.toString() ?? '') ?? 0,
      readyCount: json['ready_count'] is int
          ? json['ready_count'] as int
          : int.tryParse(json['ready_count']?.toString() ?? '') ?? 0,
      issueCount: json['issue_count'] is int
          ? json['issue_count'] as int
          : int.tryParse(json['issue_count']?.toString() ?? '') ?? 0,
      isOpen: json['is_open'] != false,
    );
  }
}

Future<String> _draftStorageKey({String? scope}) async {
  final scopeSuffix = (scope != null && scope.isNotEmpty) ? '_$scope' : '';
  try {
    final storage = await SessionStorage.createForRestore() ??
        await SessionStorage.create(rememberMe: false);
    final userDataRaw = await storage.readUserJson();
    if (userDataRaw != null && userDataRaw.isNotEmpty) {
      final userData = jsonDecode(userDataRaw);
      if (userData is Map) {
        final userId =
            userData['id']?.toString() ?? userData['username']?.toString();
        if (userId != null && userId.isNotEmpty) {
          return '${_draftKeyPrefix}_$userId$scopeSuffix';
        }
      }
    }
  } catch (_) {}

  try {
    final prefs = await SharedPreferences.getInstance();
    final userDataRaw =
        prefs.getString(AuthStorageKeys.user) ??
        prefs.getString(AuthStorageKeys.legacyUserData);
    if (userDataRaw != null && userDataRaw.isNotEmpty) {
      final userData = jsonDecode(userDataRaw);
      if (userData is Map) {
        final userId =
            userData['id']?.toString() ?? userData['username']?.toString();
        if (userId != null && userId.isNotEmpty) {
          return '${_draftKeyPrefix}_$userId$scopeSuffix';
        }
      }
    }
  } catch (_) {}

  return '$_draftKeyPrefix$scopeSuffix';
}

Future<ScheduleImportDraft?> loadScheduleImportDraft({String? scope}) async {
  final prefs = await SharedPreferences.getInstance();
  final key = await _draftStorageKey(scope: scope);
  var raw = prefs.getString(key);
  if (raw == null || raw.isEmpty) {
    final fallbackKey = '$_draftKeyPrefix${scope != null ? '_$scope' : ''}';
    if (key != fallbackKey) {
      raw = prefs.getString(fallbackKey);
    }
  }
  if (raw == null || raw.isEmpty) {
    return null;
  }
  try {
    final json = jsonDecode(raw);
    if (json is! Map) {
      return null;
    }
    final draft =
        ScheduleImportDraft.fromJson(Map<String, dynamic>.from(json));
    if (draft.parsed.rows.isEmpty) {
      return null;
    }
    return draft;
  } catch (_) {
    return null;
  }
}

Future<void> saveScheduleImportDraft(ScheduleImportDraft draft) async {
  final prefs = await SharedPreferences.getInstance();
  final key = await _draftStorageKey(scope: draft.scope);
  await prefs.setString(key, jsonEncode(draft.toJson()));
}

Future<void> clearScheduleImportDraft({String? scope}) async {
  final prefs = await SharedPreferences.getInstance();
  final key = await _draftStorageKey(scope: scope);
  await prefs.remove(key);
  final fallbackKey = '$_draftKeyPrefix${scope != null ? '_$scope' : ''}';
  if (key != fallbackKey) {
    await prefs.remove(fallbackKey);
  }
}
