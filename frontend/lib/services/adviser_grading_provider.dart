import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'authenticated_client.dart';
import 'session_expired.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class AdviserGradingState {
  final bool isLoading;
  final bool isSaving;
  final bool adviserGradingEnabled;
  final List<Map<String, dynamic>> grades;
  final Map<String, dynamic> counts;
  final String? error;
  final String? message;

  const AdviserGradingState({
    this.isLoading = false,
    this.isSaving = false,
    this.adviserGradingEnabled = true,
    this.grades = const [],
    this.counts = const {},
    this.error,
    this.message,
  });

  AdviserGradingState copyWith({
    bool? isLoading,
    bool? isSaving,
    bool? adviserGradingEnabled,
    List<Map<String, dynamic>>? grades,
    Map<String, dynamic>? counts,
    String? error,
    bool clearError = false,
    String? message,
    bool clearMessage = false,
  }) {
    return AdviserGradingState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      adviserGradingEnabled: adviserGradingEnabled ?? this.adviserGradingEnabled,
      grades: grades ?? this.grades,
      counts: counts ?? this.counts,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class AdviserGradingNotifier extends Notifier<AdviserGradingState> {
  static String get _gradesUrl => '${ApiConfig.gradeCenterUrl}/adviser-grades/';

  @override
  AdviserGradingState build() => const AdviserGradingState();

  AuthenticatedHttpClient get _client => ref.read(authenticatedHttpClientProvider);

  String _errorFromResponse(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map) {
        if (data['detail'] != null) return data['detail'].toString();
        if (data.isNotEmpty) {
          final firstValue = data.values.first;
          if (firstValue is List && firstValue.isNotEmpty) return firstValue.first.toString();
          return firstValue.toString();
        }
      }
    } catch (_) {
      // Non-JSON error body — use status line below.
    }
    return 'Request failed (${response.statusCode})';
  }

  List<Map<String, dynamic>> _readMapList(dynamic v) {
    if (v is! List) return [];
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Loads capstone grade records for teams this adviser supervises.
  Future<void> fetchAll() async {
    state = state.copyWith(isLoading: true, clearError: true, clearMessage: true);
    try {
      final gradesResp = await _client.get(Uri.parse(_gradesUrl));

      if (gradesResp.statusCode != 200) {
        state = state.copyWith(isLoading: false, error: _errorFromResponse(gradesResp));
        return;
      }

      final gradesPayload = Map<String, dynamic>.from(jsonDecode(gradesResp.body));
      final adviserOn = gradesPayload['adviser_grading_enabled'] != false;

      state = state.copyWith(
        isLoading: false,
        adviserGradingEnabled: adviserOn,
        grades: _readMapList(gradesPayload['grades']),
        counts: gradesPayload['counts'] is Map
            ? Map<String, dynamic>.from(gradesPayload['counts'])
            : const {},
      );
    } on SessionExpiredException {
      rethrow;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Connection error: $e');
    }
  }

  /// Submits the adviser score (and per-criterion breakdown) for a grade.
  Future<bool> submitGrade({
    required int gradeId,
    required double adviserScore,
    int? rubricId,
    List<Map<String, dynamic>> criteriaScores = const [],
  }) async {
    state = state.copyWith(isSaving: true, clearError: true, clearMessage: true);
    try {
      final body = <String, dynamic>{
        'adviser_score': adviserScore,
        if (rubricId != null) 'rubric_id': rubricId,
        if (criteriaScores.isNotEmpty) 'criteria_scores': criteriaScores,
      };

      final response = await _client.post(
        Uri.parse('${ApiConfig.gradeCenterUrl}/adviser-grades/$gradeId/submit/'),
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        await fetchAll();
        state = state.copyWith(
          isSaving: false,
          message: 'Grade submitted successfully.',
        );
        return true;
      }

      state = state.copyWith(isSaving: false, error: _errorFromResponse(response));
      return false;
    } on SessionExpiredException {
      rethrow;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final adviserGradingProvider =
    NotifierProvider<AdviserGradingNotifier, AdviserGradingState>(
  AdviserGradingNotifier.new,
);
