import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'authenticated_client.dart';

final documenterProvider =
    NotifierProvider<DocumenterNotifier, DocumenterState>(
      DocumenterNotifier.new,
    );

class DocumenterState {
  final bool isLoading;
  final List<Map<String, dynamic>> assignments;
  final Map<String, dynamic>? activeMinutes;
  final String? error;
  final String? message;
  /// Tracks whether auto-save is in progress.
  final bool isSavingAuto;
  /// Timestamp of the last successful auto-save.
  final DateTime? lastAutoSavedAt;

  const DocumenterState({
    this.isLoading = false,
    this.assignments = const [],
    this.activeMinutes,
    this.error,
    this.message,
    this.isSavingAuto = false,
    this.lastAutoSavedAt,
  });

  DocumenterState copyWith({
    bool? isLoading,
    List<Map<String, dynamic>>? assignments,
    Map<String, dynamic>? activeMinutes,
    String? error,
    String? message,
    bool? isSavingAuto,
    DateTime? lastAutoSavedAt,
    bool clearActiveMinutes = false,
    bool clearError = false,
    bool clearMessage = false,
    bool clearAutoSavedAt = false,
  }) {
    return DocumenterState(
      isLoading: isLoading ?? this.isLoading,
      assignments: assignments ?? this.assignments,
      activeMinutes: clearActiveMinutes ? null : (activeMinutes ?? this.activeMinutes),
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
      isSavingAuto: isSavingAuto ?? this.isSavingAuto,
      lastAutoSavedAt: clearAutoSavedAt ? null : (lastAutoSavedAt ?? this.lastAutoSavedAt),
    );
  }
}

class DocumenterNotifier extends Notifier<DocumenterState> {
  static String get minutesUrl => ApiConfig.defenseMinutesUrl;

  /// HTTP request timeout – prevents the UI from hanging indefinitely.
  static const _requestTimeout = Duration(seconds: 30);

  @override
  DocumenterState build() {
    return const DocumenterState();
  }

  AuthenticatedHttpClient get _client => ref.read(authenticatedHttpClientProvider);

  Future<void> fetchAssignments() async {
    state = state.copyWith(isLoading: true, clearError: true, clearMessage: true);
    try {
      final response = await _client.get(
        Uri.parse('$minutesUrl/my-assignments/'),
      ).timeout(_requestTimeout);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          isLoading: false,
          assignments: data.map((item) => Map<String, dynamic>.from(item)).toList(),
          clearError: true,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: _errorFromResponse(response),
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to fetch assignments: $e',
      );
    }
  }

  Future<void> fetchMinutesDetail(int scheduleId) async {
    final currentMinutes = state.activeMinutes;
    final currentSchedId = currentMinutes != null
        ? ((currentMinutes['schedule'] as Map<String, dynamic>?)?['id'] as int?)
        : null;
    final isSameSchedule = currentSchedId == scheduleId;

    state = state.copyWith(
      isLoading: true,
      clearActiveMinutes: !isSameSchedule,
      clearError: true,
      clearMessage: true,
      clearAutoSavedAt: true,
    );
    try {
      final response = await _client.get(
        Uri.parse('$minutesUrl/$scheduleId/'),
      ).timeout(_requestTimeout);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          isLoading: false,
          activeMinutes: data,
          clearError: true,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: _errorFromResponse(response),
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to fetch minutes details: $e',
      );
    }
  }

  /// Refreshes the active minutes without clearing the existing data first,
  /// so the UI doesn't flash a loading spinner.
  Future<void> refreshMinutesDetail(int scheduleId) async {
    try {
      final response = await _client.get(
        Uri.parse('$minutesUrl/$scheduleId/'),
      ).timeout(_requestTimeout);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          activeMinutes: data,
          clearError: true,
        );
      }
    } catch (_) {
      // Silent refresh – don't clobber existing data on failure.
    }
  }

  Future<bool> saveComments(int scheduleId, List<Map<String, dynamic>> comments) async {
    state = state.copyWith(isLoading: true, clearError: true, clearMessage: true);
    try {
      final response = await _client.patch(
        Uri.parse('$minutesUrl/$scheduleId/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'comments': comments}),
      ).timeout(_requestTimeout);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          isLoading: false,
          activeMinutes: data,
          message: 'Draft comments saved.',
          clearError: true,
        );
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: _errorFromResponse(response),
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to save draft comments: $e',
      );
      return false;
    }
  }

  /// Auto-save variant – does NOT set global isLoading, uses its own flag
  /// so the UI can show a subtle indicator instead of a full overlay.
  Future<bool> autoSaveComments(int scheduleId, List<Map<String, dynamic>> comments) async {
    state = state.copyWith(isSavingAuto: true);
    try {
      final response = await _client.patch(
        Uri.parse('$minutesUrl/$scheduleId/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'comments': comments}),
      ).timeout(_requestTimeout);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          isSavingAuto: false,
          activeMinutes: data,
          lastAutoSavedAt: DateTime.now(),
          clearError: true,
        );
        return true;
      } else {
        state = state.copyWith(isSavingAuto: false);
        return false;
      }
    } catch (_) {
      state = state.copyWith(isSavingAuto: false);
      return false;
    }
  }

  Future<bool> submitMinutes(int scheduleId) async {
    state = state.copyWith(isLoading: true, clearError: true, clearMessage: true);
    try {
      final response = await _client.post(
        Uri.parse('$minutesUrl/$scheduleId/submit/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(_requestTimeout);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          isLoading: false,
          activeMinutes: data,
          message: 'Minutes submitted successfully.',
          clearError: true,
        );
        await fetchAssignments(); // refresh dashboard assignments list status
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: _errorFromResponse(response),
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to submit minutes: $e',
      );
      return false;
    }
  }

  Future<bool> adviserSign(int scheduleId) async {
    state = state.copyWith(isLoading: true, clearError: true, clearMessage: true);
    try {
      final response = await _client.post(
        Uri.parse('$minutesUrl/$scheduleId/sign-adviser/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(_requestTimeout);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          isLoading: false,
          activeMinutes: data,
          message: 'Signed as Adviser successfully.',
          clearError: true,
        );
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: _errorFromResponse(response),
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to sign as adviser: $e',
      );
      return false;
    }
  }

  Future<bool> chairmanSign(int scheduleId) async {
    state = state.copyWith(isLoading: true, clearError: true, clearMessage: true);
    try {
      final response = await _client.post(
        Uri.parse('$minutesUrl/$scheduleId/sign-chairman/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(_requestTimeout);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          isLoading: false,
          activeMinutes: data,
          message: 'Signed as Chairman successfully.',
          clearError: true,
        );
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: _errorFromResponse(response),
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to sign as chairman: $e',
      );
      return false;
    }
  }

  Future<Uint8List?> downloadPdf(int scheduleId) async {
    try {
      final response = await _client.get(
        Uri.parse('$minutesUrl/$scheduleId/pdf/'),
      ).timeout(_requestTimeout);
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String _errorFromResponse(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map) {
        if (data['detail'] != null) {
          return data['detail'].toString();
        }
        if (data['error'] != null) {
          return data['error'].toString();
        }
        if (data.isNotEmpty) {
          final firstValue = data.values.first;
          if (firstValue is List && firstValue.isNotEmpty) {
            return firstValue.first.toString();
          }
          return firstValue.toString();
        }
      }
    } catch (_) {}
    return 'Request failed with status: ${response.statusCode}';
  }
}
