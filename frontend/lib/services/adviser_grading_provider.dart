import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class AdviserGradingState {
  final bool isLoading;
  final bool isSaving;
  final bool adviserGradingEnabled;
  final List<Map<String, dynamic>> grades;
  final List<Map<String, dynamic>> adviserRubrics;
  final Map<String, dynamic> counts;
  final String? error;
  final String? message;

  const AdviserGradingState({
    this.isLoading = false,
    this.isSaving = false,
    this.adviserGradingEnabled = true,
    this.grades = const [],
    this.adviserRubrics = const [],
    this.counts = const {},
    this.error,
    this.message,
  });

  AdviserGradingState copyWith({
    bool? isLoading,
    bool? isSaving,
    bool? adviserGradingEnabled,
    List<Map<String, dynamic>>? grades,
    List<Map<String, dynamic>>? adviserRubrics,
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
      adviserRubrics: adviserRubrics ?? this.adviserRubrics,
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
  static String get _rubricsUrl => ApiConfig.rubricsUrl;

  @override
  AdviserGradingState build() => const AdviserGradingState();

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null) throw Exception('No authentication token found.');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

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
    } catch (_) {}
    return 'Request failed (${response.statusCode})';
  }

  List<Map<String, dynamic>> _readMapList(dynamic v) {
    if (v is! List) return [];
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Loads both grade records and available adviser rubrics in parallel.
  Future<void> fetchAll() async {
    state = state.copyWith(isLoading: true, clearError: true, clearMessage: true);
    try {
      final headers = await _headers();
      final results = await Future.wait([
        http.get(Uri.parse(_gradesUrl), headers: headers),
        http.get(
          Uri.parse(_rubricsUrl).replace(queryParameters: {
            'evaluation_type': 'adviser',
            'status': 'published',
          }),
          headers: headers,
        ),
      ]);

      final gradesResp = results[0];
      final rubricsResp = results[1];

      if (gradesResp.statusCode != 200) {
        state = state.copyWith(isLoading: false, error: _errorFromResponse(gradesResp));
        return;
      }
      if (rubricsResp.statusCode != 200) {
        state = state.copyWith(isLoading: false, error: _errorFromResponse(rubricsResp));
        return;
      }

      final gradesPayload = Map<String, dynamic>.from(jsonDecode(gradesResp.body));
      final rubricsPayload = Map<String, dynamic>.from(jsonDecode(rubricsResp.body));
      final adviserOn = gradesPayload['adviser_grading_enabled'] != false;

      state = state.copyWith(
        isLoading: false,
        adviserGradingEnabled: adviserOn,
        grades: _readMapList(gradesPayload['grades']),
        counts: gradesPayload['counts'] is Map
            ? Map<String, dynamic>.from(gradesPayload['counts'])
            : const {},
        adviserRubrics: _readMapList(rubricsPayload['rubrics']),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Connection error: $e');
    }
  }

  /// Submits the adviser score (and optional per-criterion breakdown) for a grade.
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

      final response = await http.post(
        Uri.parse('${ApiConfig.gradeCenterUrl}/adviser-grades/$gradeId/submit/'),
        headers: await _headers(),
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final updatedGrade = Map<String, dynamic>.from(data['grade'] as Map);
        // Patch the grade in local list without a full reload
        final updated = state.grades.map((g) {
          return (g['id'] == updatedGrade['id']) ? updatedGrade : g;
        }).toList();
        final graded = updated.where((g) => g['adviser_score'] != null).length;
        state = state.copyWith(
          isSaving: false,
          grades: updated,
          counts: {
            ...state.counts,
            'graded': graded,
            'pending': updated.length - graded,
          },
          message: 'Grade submitted successfully.',
        );
        return true;
      }

      state = state.copyWith(isSaving: false, error: _errorFromResponse(response));
      return false;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final adviserGradingProvider =
    NotifierProvider<AdviserGradingNotifier, AdviserGradingState>(
  AdviserGradingNotifier.new,
);
