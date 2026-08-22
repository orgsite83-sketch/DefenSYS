import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/csv_file_io.dart';

class StudentBatchDraftState {
  final List<PickedTabularFile> freshStagedFiles;
  final List<Map<String, dynamic>> freshParsedStudents;
  final String freshSectionFilter;

  final List<PickedTabularFile> rolloverStagedFiles;
  final Map<String, String> rolloverActions;
  final String rolloverSectionFilter;
  final String rolloverYearFilter;
  final bool hasRolloverCsv;

  const StudentBatchDraftState({
    this.freshStagedFiles = const [],
    this.freshParsedStudents = const [],
    this.freshSectionFilter = 'ALL',
    this.rolloverStagedFiles = const [],
    this.rolloverActions = const {},
    this.rolloverSectionFilter = 'ALL',
    this.rolloverYearFilter = 'ALL',
    this.hasRolloverCsv = false,
  });

  bool get hasFreshDraft =>
      freshParsedStudents.isNotEmpty || freshStagedFiles.isNotEmpty;

  bool get hasRolloverDraft =>
      rolloverStagedFiles.isNotEmpty ||
      rolloverActions.isNotEmpty ||
      hasRolloverCsv;

  StudentBatchDraftState copyWith({
    List<PickedTabularFile>? freshStagedFiles,
    List<Map<String, dynamic>>? freshParsedStudents,
    String? freshSectionFilter,
    List<PickedTabularFile>? rolloverStagedFiles,
    Map<String, String>? rolloverActions,
    String? rolloverSectionFilter,
    String? rolloverYearFilter,
    bool? hasRolloverCsv,
  }) {
    return StudentBatchDraftState(
      freshStagedFiles: freshStagedFiles ?? this.freshStagedFiles,
      freshParsedStudents: freshParsedStudents ?? this.freshParsedStudents,
      freshSectionFilter: freshSectionFilter ?? this.freshSectionFilter,
      rolloverStagedFiles: rolloverStagedFiles ?? this.rolloverStagedFiles,
      rolloverActions: rolloverActions ?? this.rolloverActions,
      rolloverSectionFilter:
          rolloverSectionFilter ?? this.rolloverSectionFilter,
      rolloverYearFilter: rolloverYearFilter ?? this.rolloverYearFilter,
      hasRolloverCsv: hasRolloverCsv ?? this.hasRolloverCsv,
    );
  }
}

final studentBatchDraftProvider =
    NotifierProvider<StudentBatchDraftNotifier, StudentBatchDraftState>(
  StudentBatchDraftNotifier.new,
);

class StudentBatchDraftNotifier extends Notifier<StudentBatchDraftState> {
  static const _draftKey = 'student_batch_enrollment_draft_v1';

  @override
  StudentBatchDraftState build() {
    _loadFromStorage();
    return const StudentBatchDraftState();
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;

      final freshFilesRaw = json['fresh_files'] as List? ?? [];
      final freshFiles = freshFilesRaw.map((f) {
        return PickedTabularFile(
          name: f['name']?.toString() ?? '',
          extension: f['extension']?.toString() ?? 'csv',
          bytes: base64Decode(f['bytes_b64']?.toString() ?? ''),
          text: f['text']?.toString(),
        );
      }).toList();

      final freshStudentsRaw = (json['fresh_students'] as List? ?? [])
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();

      final rolloverFilesRaw = json['rollover_files'] as List? ?? [];
      final rolloverFiles = rolloverFilesRaw.map((f) {
        return PickedTabularFile(
          name: f['name']?.toString() ?? '',
          extension: f['extension']?.toString() ?? 'csv',
          bytes: base64Decode(f['bytes_b64']?.toString() ?? ''),
          text: f['text']?.toString(),
        );
      }).toList();

      final rolloverActionsRaw = (json['rollover_actions'] as Map? ?? {})
          .map((k, v) => MapEntry(k.toString(), v.toString()));

      state = StudentBatchDraftState(
        freshStagedFiles: freshFiles,
        freshParsedStudents: freshStudentsRaw,
        freshSectionFilter:
            json['fresh_section_filter']?.toString() ?? 'ALL',
        rolloverStagedFiles: rolloverFiles,
        rolloverActions: rolloverActionsRaw,
        rolloverSectionFilter:
            json['rollover_section_filter']?.toString() ?? 'ALL',
        rolloverYearFilter:
            json['rollover_year_filter']?.toString() ?? 'ALL',
        hasRolloverCsv: json['has_rollover_csv'] as bool? ?? false,
      );
    } catch (_) {
      // Ignore corrupt draft
    }
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final freshFilesJson = state.freshStagedFiles
          .map((f) => {
                'name': f.name,
                'extension': f.extension,
                'bytes_b64': base64Encode(f.bytes),
                'text': f.text,
              })
          .toList();

      final rolloverFilesJson = state.rolloverStagedFiles
          .map((f) => {
                'name': f.name,
                'extension': f.extension,
                'bytes_b64': base64Encode(f.bytes),
                'text': f.text,
              })
          .toList();

      final data = {
        'fresh_files': freshFilesJson,
        'fresh_students': state.freshParsedStudents,
        'fresh_section_filter': state.freshSectionFilter,
        'rollover_files': rolloverFilesJson,
        'rollover_actions': state.rolloverActions,
        'rollover_section_filter': state.rolloverSectionFilter,
        'rollover_year_filter': state.rolloverYearFilter,
        'has_rollover_csv': state.hasRolloverCsv,
      };

      await prefs.setString(_draftKey, jsonEncode(data));
    } catch (_) {}
  }

  void saveFreshDraft({
    required List<PickedTabularFile> stagedFiles,
    required List<Map<String, dynamic>> parsedStudents,
    String? sectionFilter,
  }) {
    state = state.copyWith(
      freshStagedFiles: List.from(stagedFiles),
      freshParsedStudents: List.from(parsedStudents),
      freshSectionFilter: sectionFilter ?? state.freshSectionFilter,
    );
    _saveToStorage();
  }

  void saveRolloverDraft({
    required List<PickedTabularFile> stagedFiles,
    required Map<String, String> actions,
    String? sectionFilter,
    String? yearFilter,
    bool? hasRolloverCsv,
  }) {
    state = state.copyWith(
      rolloverStagedFiles: List.from(stagedFiles),
      rolloverActions: Map.from(actions),
      rolloverSectionFilter: sectionFilter ?? state.rolloverSectionFilter,
      rolloverYearFilter: yearFilter ?? state.rolloverYearFilter,
      hasRolloverCsv: hasRolloverCsv ?? state.hasRolloverCsv,
    );
    _saveToStorage();
  }

  void clearFreshDraft() {
    state = state.copyWith(
      freshStagedFiles: [],
      freshParsedStudents: [],
      freshSectionFilter: 'ALL',
    );
    _saveToStorage();
  }

  void clearRolloverDraft() {
    state = state.copyWith(
      rolloverStagedFiles: [],
      rolloverActions: {},
      rolloverSectionFilter: 'ALL',
      rolloverYearFilter: 'ALL',
      hasRolloverCsv: false,
    );
    _saveToStorage();
  }

  void clearAll() {
    state = const StudentBatchDraftState();
    _saveToStorage();
  }
}
