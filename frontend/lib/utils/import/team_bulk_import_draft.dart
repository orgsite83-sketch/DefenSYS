import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_storage_keys.dart';

const _draftKeyPrefix = 'team_bulk_import_draft';

class TeamBulkImportDraft {
  const TeamBulkImportDraft({
    required this.rows,
    required this.adviserFilter,
    required this.savedAt,
    this.preview,
    this.issueCount = 0,
    this.isOpen = true,
  });

  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic>? preview;
  final String adviserFilter;
  final DateTime savedAt;
  final int issueCount;
  final bool isOpen;

  Map<String, dynamic> toJson() => {
        'rows': rows,
        'preview': preview,
        'adviser_filter': adviserFilter,
        'saved_at': savedAt.toIso8601String(),
        'issue_count': issueCount,
        'is_open': isOpen,
      };

  factory TeamBulkImportDraft.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'] as List? ?? const [];
    return TeamBulkImportDraft(
      rows: rawRows
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      preview: json['preview'] is Map
          ? Map<String, dynamic>.from(json['preview'] as Map)
          : null,
      adviserFilter: json['adviser_filter']?.toString() ?? 'all',
      savedAt: DateTime.tryParse(json['saved_at']?.toString() ?? '') ??
          DateTime.now(),
      issueCount: json['issue_count'] is int
          ? json['issue_count'] as int
          : int.tryParse(json['issue_count']?.toString() ?? '') ?? 0,
      isOpen: json['is_open'] != false,
    );
  }
}

Future<String> _draftStorageKey() async {
  final prefs = await SharedPreferences.getInstance();
  final userDataRaw =
      prefs.getString(AuthStorageKeys.user) ??
      prefs.getString(AuthStorageKeys.legacyUserData);
  if (userDataRaw != null && userDataRaw.isNotEmpty) {
    try {
      final userData = jsonDecode(userDataRaw);
      if (userData is Map) {
        final userId = userData['id']?.toString() ?? userData['username']?.toString();
        if (userId != null && userId.isNotEmpty) {
          return '${_draftKeyPrefix}_$userId';
        }
      }
    } catch (_) {
      // Fall through to shared key.
    }
  }
  return _draftKeyPrefix;
}

Future<TeamBulkImportDraft?> loadTeamBulkImportDraft() async {
  final prefs = await SharedPreferences.getInstance();
  final key = await _draftStorageKey();
  if (key == _draftKeyPrefix) {
    // Purge legacy unscoped draft so it doesn't bleed across user sessions.
    await prefs.remove(_draftKeyPrefix);
    return null;
  }
  final raw = prefs.getString(key);
  if (raw == null || raw.isEmpty) {
    return null;
  }
  try {
    final json = jsonDecode(raw);
    if (json is! Map) {
      return null;
    }
    final draft = TeamBulkImportDraft.fromJson(Map<String, dynamic>.from(json));
    if (draft.rows.isEmpty) {
      return null;
    }
    return draft;
  } catch (_) {
    return null;
  }
}

Future<void> saveTeamBulkImportDraft(TeamBulkImportDraft draft) async {
  final prefs = await SharedPreferences.getInstance();
  final key = await _draftStorageKey();
  if (key == _draftKeyPrefix) {
    return;
  }
  await prefs.setString(key, jsonEncode(draft.toJson()));
}

Future<void> clearTeamBulkImportDraft() async {
  final prefs = await SharedPreferences.getInstance();
  final key = await _draftStorageKey();
  if (key != _draftKeyPrefix) {
    await prefs.remove(key);
  }
  await prefs.remove(_draftKeyPrefix);
}

int countPreviewIssues(Map<String, dynamic>? preview) {
  if (preview == null) {
    return 0;
  }
  final rows = preview['rows'] as List? ?? const [];
  var count = 0;
  for (final item in rows) {
    if (item is Map && item['ready'] != true) {
      count += 1;
    }
  }
  return count;
}

