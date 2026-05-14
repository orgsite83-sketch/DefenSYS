import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

final repositoryAuditProvider =
    NotifierProvider<RepositoryAuditNotifier, RepositoryAuditState>(
      RepositoryAuditNotifier.new,
    );

class RepositoryAuditState {
  final bool isLoading;
  final bool isSaving;
  final List<Map<String, dynamic>> entries;
  final Map<String, dynamic> counts;
  final Map<String, dynamic> options;
  final Map<String, dynamic> scope;
  final String search;
  final String type;
  final String yearLevel;
  final String academicYear;
  final String status;
  final String semester;
  final String teamId;
  final String stage;
  final String? error;
  final String? message;

  const RepositoryAuditState({
    this.isLoading = false,
    this.isSaving = false,
    this.entries = const [],
    this.counts = const {},
    this.options = const {},
    this.scope = const {},
    this.search = '',
    this.type = '',
    this.yearLevel = '',
    this.academicYear = '',
    this.status = '',
    this.semester = '',
    this.teamId = '',
    this.stage = '',
    this.error,
    this.message,
  });

  RepositoryAuditState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? entries,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? options,
    Map<String, dynamic>? scope,
    String? search,
    String? type,
    String? yearLevel,
    String? academicYear,
    String? status,
    String? semester,
    String? teamId,
    String? stage,
    String? error,
    String? message,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return RepositoryAuditState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      entries: entries ?? this.entries,
      counts: counts ?? this.counts,
      options: options ?? this.options,
      scope: scope ?? this.scope,
      search: search ?? this.search,
      type: type ?? this.type,
      yearLevel: yearLevel ?? this.yearLevel,
      academicYear: academicYear ?? this.academicYear,
      status: status ?? this.status,
      semester: semester ?? this.semester,
      teamId: teamId ?? this.teamId,
      stage: stage ?? this.stage,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class RepositoryAuditNotifier extends Notifier<RepositoryAuditState> {
    static String get baseUrl => ApiConfig.repositoryAuditUrl;

  @override
  RepositoryAuditState build() {
    return const RepositoryAuditState();
  }

  Future<void> fetchEntries({
    String? search,
    String? type,
    String? yearLevel,
    String? academicYear,
    String? status,
    String? semester,
    String? teamId,
    String? stage,
    String? successMessage,
  }) async {
    final nextSearch = search ?? state.search;
    final nextType = type ?? state.type;
    final nextYearLevel = yearLevel ?? state.yearLevel;
    final nextAcademicYear = academicYear ?? state.academicYear;
    final nextStatus = status ?? state.status;
    final nextSemester = semester ?? state.semester;
    final nextTeamId = teamId ?? state.teamId;
    final nextStage = stage ?? state.stage;

    state = state.copyWith(
      isLoading: state.entries.isEmpty,
      isSaving: false,
      search: nextSearch,
      type: nextType,
      yearLevel: nextYearLevel,
      academicYear: nextAcademicYear,
      status: nextStatus,
      semester: nextSemester,
      teamId: nextTeamId,
      stage: nextStage,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await http.get(
        _uri(
          '',
          search: nextSearch,
          type: nextType,
          yearLevel: nextYearLevel,
          academicYear: nextAcademicYear,
          status: nextStatus,
          semester: nextSemester,
          teamId: nextTeamId,
          stage: nextStage,
        ),
        headers: await _headers(),
      );

      if (response.statusCode == 200) {
        _applyPayload(
          Map<String, dynamic>.from(jsonDecode(response.body)),
          successMessage: successMessage,
        );
        return;
      }

      state = state.copyWith(
        isLoading: false,
        isSaving: false,
        error: _errorFromResponse(response),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isSaving: false,
        error: 'Connection error: $e',
      );
    }
  }

  Future<bool> uploadPit({
    required List<String> fileNames,
    String? yearLevel,
    String? academicYear,
  }) {
    return _postAction('upload-pit', {
      'file_names': fileNames,
      if ((yearLevel ?? '').isNotEmpty) 'year_level': yearLevel,
      if ((academicYear ?? '').isNotEmpty) 'academic_year': academicYear,
    }, successMessage: 'PIT upload metadata saved.');
  }

  Future<bool> classify(String entryId) {
    return _postAction('classify', {
      'entry_id': entryId,
    }, successMessage: 'PIT file classified as approved.');
  }

  Future<bool> overrideStatus(String entryId, String status) {
    return _postAction('override-status', {
      'entry_id': entryId,
      'status': status,
    }, successMessage: 'PIT status overridden.');
  }

  Future<String?> exportCsv() async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );
    try {
      final response = await http.get(
        _uri(
          'export',
          search: state.search,
          type: state.type,
          yearLevel: state.yearLevel,
          academicYear: state.academicYear,
          status: state.status,
          semester: state.semester,
          teamId: state.teamId,
          stage: state.stage,
        ),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        state = state.copyWith(
          isSaving: false,
          message: 'CSV export generated.',
          clearError: true,
        );
        return response.body;
      }
      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
    }
    return null;
  }

  Future<bool> _postAction(
    String action,
    Map<String, dynamic> payload, {
    required String successMessage,
  }) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/$action/'),
        headers: await _headers(),
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        _applyPayload(
          Map<String, dynamic>.from(jsonDecode(response.body)),
          successMessage: successMessage,
        );
        return true;
      }

      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }

  Uri _uri(
    String path, {
    required String search,
    required String type,
    required String yearLevel,
    required String academicYear,
    required String status,
    required String semester,
    required String teamId,
    required String stage,
  }) {
    return Uri.parse(path.isEmpty ? baseUrl : '$baseUrl/$path/').replace(
      queryParameters: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (type.isNotEmpty) 'type': type,
        if (yearLevel.isNotEmpty) 'year_level': yearLevel,
        if (academicYear.isNotEmpty) 'academic_year': academicYear,
        if (status.isNotEmpty) 'status': status,
        if (semester.isNotEmpty) 'semester': semester,
        if (teamId.isNotEmpty) 'team_id': teamId,
        if (stage.isNotEmpty) 'stage': stage,
      },
    );
  }

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) {
      throw Exception('No authentication token found.');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  void _applyPayload(Map<String, dynamic> payload, {String? successMessage}) {
    final skipped = _readMapList(payload['skipped']);
    final suffix = skipped.isEmpty ? '' : ' ${skipped.length} skipped.';
    state = state.copyWith(
      isLoading: false,
      isSaving: false,
      entries: _readMapList(payload['entries']),
      counts: payload['counts'] is Map
          ? Map<String, dynamic>.from(payload['counts'])
          : const {},
      options: payload['options'] is Map
          ? Map<String, dynamic>.from(payload['options'])
          : const {},
      scope: payload['scope'] is Map
          ? Map<String, dynamic>.from(payload['scope'])
          : const {},
      message: successMessage == null ? null : '$successMessage$suffix',
      clearError: true,
    );
  }

  List<Map<String, dynamic>> _readMapList(dynamic value) {
    if (value is! List) {
      return [];
    }
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _errorFromResponse(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map) {
        if (data['detail'] != null) {
          return data['detail'].toString();
        }
        if (data.isNotEmpty) {
          final firstValue = data.values.first;
          if (firstValue is List && firstValue.isNotEmpty) {
            return firstValue.first.toString();
          }
          return firstValue.toString();
        }
      }
    } catch (_) {
      return 'Request failed. Status: ${response.statusCode}';
    }
    return 'Request failed. Status: ${response.statusCode}';
  }
}
