import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import 'authenticated_client.dart';

final pitInstructorProvider =
    NotifierProvider<PitInstructorNotifier, PitInstructorState>(
      PitInstructorNotifier.new,
    );

class PitInstructorState {
  final bool isLoading;
  final bool isSaving;
  final List<Map<String, dynamic>> assignments;
  final List<Map<String, dynamic>> faculty;
  final String? activeSemester;
  final String? yearLevel;
  final String? error;
  final String? message;

  const PitInstructorState({
    this.isLoading = false,
    this.isSaving = false,
    this.assignments = const [],
    this.faculty = const [],
    this.activeSemester,
    this.yearLevel,
    this.error,
    this.message,
  });

  PitInstructorState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<Map<String, dynamic>>? assignments,
    List<Map<String, dynamic>>? faculty,
    String? activeSemester,
    String? yearLevel,
    String? error,
    String? message,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return PitInstructorState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      assignments: assignments ?? this.assignments,
      faculty: faculty ?? this.faculty,
      activeSemester: activeSemester ?? this.activeSemester,
      yearLevel: yearLevel ?? this.yearLevel,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class PitInstructorNotifier extends Notifier<PitInstructorState> {
  static String get baseUrl => '${ApiConfig.usersUrl}/pit-instructors';

  AuthenticatedHttpClient get _client =>
      ref.read(authenticatedHttpClientProvider);

  @override
  PitInstructorState build() => const PitInstructorState();

  Future<void> fetchAssignments() async {
    state = state.copyWith(
      isLoading: state.assignments.isEmpty,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.get(Uri.parse('$baseUrl/'));
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        state = state.copyWith(
          isLoading: false,
          assignments: _readMapList(payload['assignments']),
          faculty: _readMapList(payload['faculty']),
          activeSemester: payload['active_semester']?.toString(),
          yearLevel: payload['year_level']?.toString(),
          clearError: true,
        );
        return;
      }

      state = state.copyWith(
        isLoading: false,
        error: _errorFromResponse(response),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Connection error: $e');
    }
  }

  Future<bool> assignInstructor({
    required int facultyId,
    required String section,
  }) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/'),
        body: jsonEncode({'faculty_id': facultyId, 'section': section}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchAssignments();
        state = state.copyWith(message: 'PIT Instructor assigned.');
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

  Future<bool> setAssignmentActive(int assignmentId, bool isActive) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
    );

    try {
      final response = await _client.patch(
        Uri.parse('$baseUrl/$assignmentId/'),
        body: jsonEncode({'is_active': isActive}),
      );

      if (response.statusCode == 200) {
        await fetchAssignments();
        state = state.copyWith(
          message: isActive
              ? 'PIT Instructor restored.'
              : 'PIT Instructor deactivated.',
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

  List<Map<String, dynamic>> _readMapList(dynamic value) {
    if (value is! List) {
      return [];
    }
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _errorFromResponse(dynamic response) {
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
