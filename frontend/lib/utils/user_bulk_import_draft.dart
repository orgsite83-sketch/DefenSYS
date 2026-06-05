import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _draftKeyPrefix = 'user_bulk_import_draft';

class UserBulkImportDraft {
  const UserBulkImportDraft({
    required this.csv,
    required this.importType,
    required this.studentPeriodSource,
    required this.targetSemesterId,
    required this.batchYearLevel,
    required this.savedAt,
    this.rowCount = 0,
    this.warningCount = 0,
  });

  final String csv;
  final String importType;
  final String studentPeriodSource;
  final String targetSemesterId;
  final String batchYearLevel;
  final DateTime savedAt;
  final int rowCount;
  final int warningCount;

  Map<String, dynamic> toJson() => {
    'csv': csv,
    'import_type': importType,
    'student_period_source': studentPeriodSource,
    'target_semester_id': targetSemesterId,
    'batch_year_level': batchYearLevel,
    'saved_at': savedAt.toIso8601String(),
    'row_count': rowCount,
    'warning_count': warningCount,
  };

  factory UserBulkImportDraft.fromJson(Map<String, dynamic> json) {
    return UserBulkImportDraft(
      csv: json['csv']?.toString() ?? '',
      importType: json['import_type']?.toString() ?? 'student',
      studentPeriodSource:
          json['student_period_source']?.toString() ?? 'explicit',
      targetSemesterId: json['target_semester_id']?.toString() ?? '',
      batchYearLevel: json['batch_year_level']?.toString() ?? '',
      savedAt:
          DateTime.tryParse(json['saved_at']?.toString() ?? '') ??
          DateTime.now(),
      rowCount: json['row_count'] is int
          ? json['row_count'] as int
          : int.tryParse(json['row_count']?.toString() ?? '') ?? 0,
      warningCount: json['warning_count'] is int
          ? json['warning_count'] as int
          : int.tryParse(json['warning_count']?.toString() ?? '') ?? 0,
    );
  }
}

Future<String> _draftStorageKey() async {
  final prefs = await SharedPreferences.getInstance();
  final userDataRaw = prefs.getString('user_data');
  if (userDataRaw != null && userDataRaw.isNotEmpty) {
    try {
      final userData = jsonDecode(userDataRaw);
      if (userData is Map) {
        final userId =
            userData['id']?.toString() ?? userData['username']?.toString();
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

Future<UserBulkImportDraft?> loadUserBulkImportDraft() async {
  final prefs = await SharedPreferences.getInstance();
  final key = await _draftStorageKey();
  final raw = prefs.getString(key);
  if (raw == null || raw.isEmpty) {
    return null;
  }
  try {
    final json = jsonDecode(raw);
    if (json is! Map) {
      return null;
    }
    final draft = UserBulkImportDraft.fromJson(Map<String, dynamic>.from(json));
    if (draft.csv.trim().isEmpty) {
      return null;
    }
    return draft;
  } catch (_) {
    return null;
  }
}

Future<void> saveUserBulkImportDraft(UserBulkImportDraft draft) async {
  final prefs = await SharedPreferences.getInstance();
  final key = await _draftStorageKey();
  await prefs.setString(key, jsonEncode(draft.toJson()));
}

Future<void> clearUserBulkImportDraft() async {
  final prefs = await SharedPreferences.getInstance();
  final key = await _draftStorageKey();
  await prefs.remove(key);
}
