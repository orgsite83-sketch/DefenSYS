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

  const DocumenterState({
    this.isLoading = false,
    this.assignments = const [],
    this.activeMinutes,
    this.error,
    this.message,
  });

  DocumenterState copyWith({
    bool? isLoading,
    List<Map<String, dynamic>>? assignments,
    Map<String, dynamic>? activeMinutes,
    String? error,
    String? message,
    bool clearActiveMinutes = false,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return DocumenterState(
      isLoading: isLoading ?? this.isLoading,
      assignments: assignments ?? this.assignments,
      activeMinutes: clearActiveMinutes ? null : (activeMinutes ?? this.activeMinutes),
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class DocumenterNotifier extends Notifier<DocumenterState> {
  static String get minutesUrl => ApiConfig.defenseMinutesUrl;

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
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          isLoading: false,
          assignments: data.map((item) => Map<String, dynamic>.from(item)).toList(),
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
    state = state.copyWith(isLoading: true, clearError: true, clearMessage: true);
    try {
      final response = await _client.get(
        Uri.parse('$minutesUrl/$scheduleId/'),
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          isLoading: false,
          activeMinutes: data,
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

  Future<bool> saveComments(int scheduleId, List<Map<String, dynamic>> comments) async {
    state = state.copyWith(isLoading: true, clearError: true, clearMessage: true);
    try {
      final response = await _client.patch(
        Uri.parse('$minutesUrl/$scheduleId/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'comments': comments}),
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          isLoading: false,
          activeMinutes: data,
          message: 'Draft comments saved.',
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

  Future<bool> submitMinutes(int scheduleId) async {
    state = state.copyWith(isLoading: true, clearError: true, clearMessage: true);
    try {
      final response = await _client.post(
        Uri.parse('$minutesUrl/$scheduleId/submit/'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          isLoading: false,
          activeMinutes: data,
          message: 'Minutes submitted successfully.',
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
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          isLoading: false,
          activeMinutes: data,
          message: 'Signed as Adviser successfully.',
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
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        state = state.copyWith(
          isLoading: false,
          activeMinutes: data,
          message: 'Signed as Chairman successfully.',
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
      );
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
