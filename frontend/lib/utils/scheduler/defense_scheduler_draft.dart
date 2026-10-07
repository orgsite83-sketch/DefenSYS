import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_storage_keys.dart';
import '../../services/session/session_storage.dart';
import '../../screens/web/admin/defense_scheduler/models/schedule_session_draft.dart';

const _schedulerDraftKeyPrefix = 'defense_scheduler_draft';

class DefenseSchedulerDraft {
  const DefenseSchedulerDraft({
    required this.scope,
    required this.savedAt,
    this.semesterId,
    this.stageId,
    this.eventName = '',
    this.rubricId,
    this.adviserRubricId,
    this.capstonePeerRubricId,
    this.peerRubricId,
    this.panelWeight = '80',
    this.peerWeight = '20',
    this.pitTemplate = '',
    this.documenterId,
    this.selectedPanelistIds = const [],
    this.selectedChairId,
    this.externalIds = const [],
    this.sessions = const [],
    this.planSlots = const [],
    this.showFinalPreview = false,
  });

  final String scope;
  final DateTime savedAt;
  final int? semesterId;
  final int? stageId;
  final String eventName;
  final int? rubricId;
  final int? adviserRubricId;
  final int? capstonePeerRubricId;
  final int? peerRubricId;
  final String panelWeight;
  final String peerWeight;
  final String pitTemplate;
  final int? documenterId;
  final List<int> selectedPanelistIds;
  final int? selectedChairId;
  final List<int> externalIds;
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> planSlots;
  final bool showFinalPreview;

  bool get hasContent {
    if (planSlots.isNotEmpty) return true;
    for (final s in sessions) {
      final teamIds = (s['team_ids'] as List?) ?? [];
      final room = s['room']?.toString().trim() ?? '';
      if (teamIds.isNotEmpty || room.isNotEmpty) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'scope': scope,
    'saved_at': savedAt.toIso8601String(),
    'semester_id': semesterId,
    'stage_id': stageId,
    'event_name': eventName,
    'rubric_id': rubricId,
    'adviser_rubric_id': adviserRubricId,
    'capstone_peer_rubric_id': capstonePeerRubricId,
    'peer_rubric_id': peerRubricId,
    'panel_weight': panelWeight,
    'peer_weight': peerWeight,
    'pit_template': pitTemplate,
    'documenter_id': documenterId,
    'selected_panelist_ids': selectedPanelistIds,
    'selected_chair_id': selectedChairId,
    'external_ids': externalIds,
    'sessions': sessions,
    'plan_slots': planSlots,
    'show_final_preview': showFinalPreview,
  };

  factory DefenseSchedulerDraft.fromJson(Map<String, dynamic> json) {
    return DefenseSchedulerDraft(
      scope: json['scope']?.toString() ?? 'capstone',
      savedAt: DateTime.tryParse(json['saved_at']?.toString() ?? '') ?? DateTime.now(),
      semesterId: json['semester_id'] is int ? json['semester_id'] as int : int.tryParse(json['semester_id']?.toString() ?? ''),
      stageId: json['stage_id'] is int ? json['stage_id'] as int : int.tryParse(json['stage_id']?.toString() ?? ''),
      eventName: json['event_name']?.toString() ?? '',
      rubricId: json['rubric_id'] is int ? json['rubric_id'] as int : int.tryParse(json['rubric_id']?.toString() ?? ''),
      adviserRubricId: json['adviser_rubric_id'] is int ? json['adviser_rubric_id'] as int : int.tryParse(json['adviser_rubric_id']?.toString() ?? ''),
      capstonePeerRubricId: json['capstone_peer_rubric_id'] is int ? json['capstone_peer_rubric_id'] as int : int.tryParse(json['capstone_peer_rubric_id']?.toString() ?? ''),
      peerRubricId: json['peer_rubric_id'] is int ? json['peer_rubric_id'] as int : int.tryParse(json['peer_rubric_id']?.toString() ?? ''),
      panelWeight: json['panel_weight']?.toString() ?? '80',
      peerWeight: json['peer_weight']?.toString() ?? '20',
      pitTemplate: json['pit_template']?.toString() ?? '',
      documenterId: json['documenter_id'] is int ? json['documenter_id'] as int : int.tryParse(json['documenter_id']?.toString() ?? ''),
      selectedPanelistIds: (json['selected_panelist_ids'] as List?)
              ?.map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toList() ??
          const [],
      selectedChairId: json['selected_chair_id'] is int ? json['selected_chair_id'] as int : int.tryParse(json['selected_chair_id']?.toString() ?? ''),
      externalIds: (json['external_ids'] as List?)
              ?.map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toList() ??
          const [],
      sessions: (json['sessions'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      planSlots: (json['plan_slots'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      showFinalPreview: json['show_final_preview'] == true,
    );
  }
}

Future<String> _schedulerDraftStorageKey({String? scope}) async {
  final scopeSuffix = (scope != null && scope.isNotEmpty) ? '_$scope' : '';
  try {
    final storage =
        await SessionStorage.createForRestore() ??
        await SessionStorage.create(rememberMe: false);
    final userDataRaw = await storage.readUserJson();
    if (userDataRaw != null && userDataRaw.isNotEmpty) {
      final userData = jsonDecode(userDataRaw);
      if (userData is Map) {
        final userId =
            userData['id']?.toString() ?? userData['username']?.toString();
        if (userId != null && userId.isNotEmpty) {
          return '${_schedulerDraftKeyPrefix}_$userId$scopeSuffix';
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
          return '${_schedulerDraftKeyPrefix}_$userId$scopeSuffix';
        }
      }
    }
  } catch (_) {}

  return '$_schedulerDraftKeyPrefix$scopeSuffix';
}

Future<DefenseSchedulerDraft?> loadDefenseSchedulerDraft({
  String? scope,
  int? semesterId,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final key = await _schedulerDraftStorageKey(scope: scope);
  var raw = semesterId == null
      ? null
      : prefs.getString('${key}_term_$semesterId');
  raw ??= prefs.getString(key);
  if (raw == null || raw.isEmpty) {
    final fallbackKey = '$_schedulerDraftKeyPrefix${scope != null ? '_$scope' : ''}';
    if (key != fallbackKey) {
      raw = prefs.getString(fallbackKey);
    }
  }
  if (raw == null || raw.isEmpty) {
    return null;
  }
  try {
    final json = jsonDecode(raw);
    if (json is! Map) return null;
    final draft = DefenseSchedulerDraft.fromJson(Map<String, dynamic>.from(json));
    if (!draft.hasContent) return null;
    if (semesterId != null && draft.semesterId != null && draft.semesterId != semesterId) {
      return null;
    }
    return draft;
  } catch (_) {
    return null;
  }
}

Future<void> saveDefenseSchedulerDraft(DefenseSchedulerDraft draft) async {
  final prefs = await SharedPreferences.getInstance();
  final key = await _schedulerDraftStorageKey(scope: draft.scope);
  final encoded = jsonEncode(draft.toJson());
  if (draft.semesterId != null) {
    await prefs.setString('${key}_term_${draft.semesterId}', encoded);
  }
  await prefs.setString(key, encoded);
}

Future<void> clearDefenseSchedulerDraft({String? scope, int? semesterId}) async {
  final prefs = await SharedPreferences.getInstance();
  final key = await _schedulerDraftStorageKey(scope: scope);
  final fallbackKey = '$_schedulerDraftKeyPrefix${scope != null ? '_$scope' : ''}';
  if (semesterId != null) {
    await prefs.remove('${key}_term_$semesterId');
  }
  for (final candidate in {key, fallbackKey}) {
    await prefs.remove(candidate);
  }
}

/// Helpers to serialize/deserialize ScheduleSessionDraft to/from maps.
Map<String, dynamic> serializeSessionDraft(ScheduleSessionDraft draft) {
  return {
    'key': draft.key,
    'date': draft.date.text,
    'start': draft.start.text,
    'end': draft.end.text,
    'duration': draft.duration.text,
    'room': draft.room.text,
    'blocks': draft.blocks
        .map((b) => {'start_time': b.start.text, 'end_time': b.end.text})
        .toList(),
    'team_ids': draft.teamIds.toList(),
    'custom_staff': draft.customStaff,
    'panelists': draft.panelists.toList(),
    'externals': draft.externals.toList(),
    'chair': draft.chair,
    'documenter': draft.documenter,
  };
}

ScheduleSessionDraft deserializeSessionDraft(
  Map<String, dynamic> map, {
  TextEditingController? sharedDate,
  TextEditingController? sharedStart,
  TextEditingController? sharedDuration,
  TextEditingController? sharedRoom,
  bool ownsFields = true,
}) {
  final key = map['key']?.toString() ?? 'session-1';
  final date = ownsFields
      ? TextEditingController(text: map['date']?.toString() ?? '')
      : (sharedDate ?? TextEditingController(text: map['date']?.toString() ?? ''));
  final start = ownsFields
      ? TextEditingController(text: map['start']?.toString() ?? '08:00')
      : (sharedStart ?? TextEditingController(text: map['start']?.toString() ?? '08:00'));
  final duration = ownsFields
      ? TextEditingController(text: map['duration']?.toString() ?? '60')
      : (sharedDuration ?? TextEditingController(text: map['duration']?.toString() ?? '60'));
  final room = ownsFields
      ? TextEditingController(text: map['room']?.toString() ?? '')
      : (sharedRoom ?? TextEditingController(text: map['room']?.toString() ?? ''));
  final end = map['end']?.toString() ?? '12:00';

  if (!ownsFields) {
    final roomVal = map['room']?.toString() ?? '';
    if (roomVal.isNotEmpty && sharedRoom != null && sharedRoom.text.isEmpty) {
      sharedRoom.text = roomVal;
    }
    final dateVal = map['date']?.toString() ?? '';
    if (dateVal.isNotEmpty && sharedDate != null && (sharedDate.text.isEmpty || sharedDate.text == DateTime.now().toIso8601String().substring(0, 10))) {
      sharedDate.text = dateVal;
    }
    final startVal = map['start']?.toString() ?? '';
    if (startVal.isNotEmpty && sharedStart != null && sharedStart.text.isEmpty) {
      sharedStart.text = startVal;
    }
    final durationVal = map['duration']?.toString() ?? '';
    if (durationVal.isNotEmpty && sharedDuration != null && sharedDuration.text.isEmpty) {
      sharedDuration.text = durationVal;
    }
  }

  final session = ScheduleSessionDraft(
    key: key,
    date: date,
    start: start,
    duration: duration,
    room: room,
    end: end,
    ownsFields: ownsFields,
  );

  final blocksList = map['blocks'] as List?;
  if (blocksList != null && blocksList.isNotEmpty) {
    for (final b in session.blocks.skip(1)) {
      b.dispose();
    }
    session.blocks.clear();
    for (final blockMap in blocksList) {
      if (blockMap is Map) {
        session.blocks.add(
          ScheduleSessionBlock(
            start: TextEditingController(text: blockMap['start_time']?.toString() ?? '08:00'),
            end: TextEditingController(text: blockMap['end_time']?.toString() ?? '12:00'),
          ),
        );
      }
    }
    if (session.blocks.isEmpty) {
      session.blocks.add(ScheduleSessionBlock(start: start, end: session.end));
    }
  }

  session.teamIds = (map['team_ids'] as List?)
          ?.map((e) => int.tryParse(e.toString()))
          .whereType<int>()
          .toSet() ??
      {};
  session.customStaff = map['custom_staff'] == true;
  session.panelists = (map['panelists'] as List?)
          ?.map((e) => int.tryParse(e.toString()))
          .whereType<int>()
          .toSet() ??
      {};
  session.externals = (map['externals'] as List?)
          ?.map((e) => int.tryParse(e.toString()))
          .whereType<int>()
          .toSet() ??
      {};
  session.chair = map['chair'] is int
      ? map['chair'] as int
      : int.tryParse(map['chair']?.toString() ?? '');
  session.documenter = map['documenter'] is int
      ? map['documenter'] as int
      : int.tryParse(map['documenter']?.toString() ?? '');

  return session;
}
