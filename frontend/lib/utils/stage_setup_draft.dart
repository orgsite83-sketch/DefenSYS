import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Work in progress is separate from a saved, unpublished defense stage.
class StageSetupDraft {
  StageSetupDraft({required Map<String, dynamic> fields, required this.tab})
    : fields = Map<String, dynamic>.from(_withoutControllers(fields) as Map);

  final Map<String, dynamic> fields;
  final int tab;

  String get label => fields['label']?.toString().trim() ?? '';

  Map<String, dynamic> toJson() => {
    'version': 1,
    'fields': _withoutControllers(fields),
    'tab': tab.clamp(0, 2),
  };
}

dynamic _withoutControllers(dynamic value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (!entry.key.toString().startsWith('_'))
          entry.key.toString(): _withoutControllers(entry.value),
    };
  }
  if (value is List) return value.map(_withoutControllers).toList();
  return value;
}

/// Each browser draft belongs to one account, semester, and stage (or new stage).
class StageSetupDraftStore {
  StageSetupDraftStore({
    required String userId,
    required int? semesterId,
    int? stageId,
  }) : _userId = userId,
       _semesterId = semesterId,
       key =
           'defense_stage_setup_draft_v1_${Uri.encodeComponent(userId)}'
           '_term_${semesterId ?? 'none'}_stage_${stageId ?? 'new'}';

  final String key;
  final String _userId;
  final int? _semesterId;

  StageSetupDraftStore forStage(int? stageId) => StageSetupDraftStore(
    userId: _userId,
    semesterId: _semesterId,
    stageId: stageId,
  );

  Future<StageSetupDraft?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['fields'] is! Map) {
        return null;
      }
      return StageSetupDraft(
        fields: Map<String, dynamic>.from(decoded['fields'] as Map),
        tab: (decoded['tab'] is int ? decoded['tab'] as int : 0).clamp(0, 2),
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> save(StageSetupDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, jsonEncode(draft.toJson()))) {
      throw StateError('Stage setup draft could not be saved.');
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(key)) {
      throw StateError('Stage setup draft could not be removed.');
    }
  }
}
