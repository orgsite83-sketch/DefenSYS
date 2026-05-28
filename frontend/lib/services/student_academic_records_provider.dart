import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'authenticated_client.dart';

final studentAcademicRecordsProvider =
    NotifierProvider<
      StudentAcademicRecordsNotifier,
      StudentAcademicRecordsState
    >(StudentAcademicRecordsNotifier.new);

class StudentAcademicRecordsState {
  final bool isLoading;
  final bool isSaving;
  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>> students;
  final List<Map<String, dynamic>> schoolYears;
  final List<Map<String, dynamic>> rolloverRows;
  final Map<String, dynamic> counts;
  final Map<String, dynamic>? activeSemester;
  final String search;
  final String schoolYear;
  final String semester;
  final String? error;
  final String? message;

  const StudentAcademicRecordsState({
    this.isLoading = false,
    this.isSaving = false,
    this.records = const [],
    this.students = const [],
    this.schoolYears = const [],
    this.rolloverRows = const [],
    this.counts = const {},
    this.activeSemester,
    this.search = '',
    this.schoolYear = '',
    this.semester = '',
    this.error,
    this.message,
  });

  StudentAcademicRecordsState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? records,
    List<Map<String, dynamic>>? students,
    List<Map<String, dynamic>>? schoolYears,
    List<Map<String, dynamic>>? rolloverRows,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? activeSemester,
    String? search,
    String? schoolYear,
    String? semester,
    String? error,
    String? message,
    bool clearError = false,
    bool clearMessage = false,
    bool clearActiveSemester = false,
  }) {
    return StudentAcademicRecordsState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      records: records ?? this.records,
      students: students ?? this.students,
      schoolYears: schoolYears ?? this.schoolYears,
      rolloverRows: rolloverRows ?? this.rolloverRows,
      counts: counts ?? this.counts,
      activeSemester: clearActiveSemester
          ? null
          : activeSemester ?? this.activeSemester,
      search: search ?? this.search,
      schoolYear: schoolYear ?? this.schoolYear,
      semester: semester ?? this.semester,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class StudentAcademicRecordsNotifier
    extends Notifier<StudentAcademicRecordsState> {
  static final String baseUrl = ApiConfig.studentRecordsUrl;

  @override
  StudentAcademicRecordsState build() {
    return const StudentAcademicRecordsState();
  }

  Future<void> fetchRecords({
    String? search,
    String? schoolYear,
    String? semester,
    String? successMessage,
  }) async {
    final nextSearch = search ?? state.search;
    final nextSchoolYear = schoolYear ?? state.schoolYear;
    final nextSemester = semester ?? state.semester;

    state = state.copyWith(
      isLoading: state.records.isEmpty,
      isSaving: false,
      search: nextSearch,
      schoolYear: nextSchoolYear,
      semester: nextSemester,
      clearError: true,
      clearMessage: true,
    );

    try {
      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {
          if (nextSearch.trim().isNotEmpty) 'search': nextSearch.trim(),
          if (nextSchoolYear.isNotEmpty) 'school_year': nextSchoolYear,
          if (nextSemester.isNotEmpty) 'semester': nextSemester,
        },
      );
      final response = await _client.get(uri);

      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        _applyPayload(payload, successMessage: successMessage);
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

  Future<bool> addRecord(Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/'),
        
        body: jsonEncode(payload),
      );

      if (response.statusCode == 201) {
        await fetchRecords(successMessage: 'Academic record created.');
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

  Future<bool> updateRecord(int recordId, Map<String, dynamic> payload) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/$recordId/'),
        
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        await fetchRecords(successMessage: 'Academic record updated.');
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

  Future<bool> deleteRecord(int recordId) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/$recordId/'),
        
      );

      if (response.statusCode == 200) {
        await fetchRecords(successMessage: 'Academic record deleted.');
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

  Future<bool> fetchRolloverPreview() async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/rollover-preview/'),
        
      );

      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        state = state.copyWith(
          isSaving: false,
          rolloverRows: _readMapList(payload['rows']),
          activeSemester: payload['active_semester'] is Map
              ? Map<String, dynamic>.from(payload['active_semester'])
              : state.activeSemester,
          clearError: true,
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

  Future<bool> confirmRollover(List<Map<String, dynamic>> actions) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/rollover/'),
        
        body: jsonEncode({'actions': actions}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        final created = payload['created_count'] ?? 0;
        final skipped = payload['skipped_count'] ?? 0;

        if (created == 0 && skipped > 0) {
          state = state.copyWith(
            isSaving: false,
            error: 'Rollover skipped $skipped records. No new records were created. Please check if the target semester exists.',
          );
          // Refresh records just in case, but return false to show the error toast
          await fetchRecords();
          return false;
        }

        await fetchRecords(
          successMessage:
              'Rollover complete. $created created, $skipped skipped.',
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

  AuthenticatedHttpClient get _client => ref.read(authenticatedHttpClientProvider);


  void _applyPayload(Map<String, dynamic> payload, {String? successMessage}) {
    state = state.copyWith(
      isLoading: false,
      isSaving: false,
      records: _readMapList(payload['records']),
      students: _readMapList(payload['students']),
      schoolYears: _readMapList(payload['school_years']),
      counts: payload['counts'] is Map
          ? Map<String, dynamic>.from(payload['counts'])
          : state.counts,
      activeSemester: payload['active_semester'] is Map
          ? Map<String, dynamic>.from(payload['active_semester'])
          : null,
      clearActiveSemester: payload['active_semester'] == null,
      message: successMessage,
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
