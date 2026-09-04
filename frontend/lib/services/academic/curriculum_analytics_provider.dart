import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../utils/platform/pdf_viewer.dart';
import '../network/authenticated_client.dart';

final curriculumAnalyticsProvider =
    NotifierProvider<CurriculumAnalyticsNotifier, CurriculumAnalyticsState>(
      CurriculumAnalyticsNotifier.new,
    );

class CurriculumAnalyticsState {
  final bool isLoading;
  final bool isSaving;
  final bool isDownloadingPdf;
  final Map<String, dynamic> data;
  final Map<String, dynamic>? proposal;
  final String selectedAcademicYear;
  final String selectedRubricId;
  final String selectedProgram;
  final String selectedScope;
  final String? error;
  final String? message;

  const CurriculumAnalyticsState({
    this.isLoading = false,
    this.isSaving = false,
    this.isDownloadingPdf = false,
    this.data = const {},
    this.proposal,
    this.selectedAcademicYear = '',
    this.selectedRubricId = 'all',
    this.selectedProgram = 'All Programs',
    this.selectedScope = 'All Levels',
    this.error,
    this.message,
  });

  CurriculumAnalyticsState copyWith({
    bool? isLoading,
    bool? isSaving,
    bool? isDownloadingPdf,
    Map<String, dynamic>? data,
    Map<String, dynamic>? proposal,
    String? selectedAcademicYear,
    String? selectedRubricId,
    String? selectedProgram,
    String? selectedScope,
    String? error,
    String? message,
    bool clearProposal = false,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return CurriculumAnalyticsState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isDownloadingPdf: isDownloadingPdf ?? this.isDownloadingPdf,
      data: data ?? this.data,
      proposal: clearProposal ? null : proposal ?? this.proposal,
      selectedAcademicYear: selectedAcademicYear ?? this.selectedAcademicYear,
      selectedRubricId: selectedRubricId ?? this.selectedRubricId,
      selectedProgram: selectedProgram ?? this.selectedProgram,
      selectedScope: selectedScope ?? this.selectedScope,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class CurriculumAnalyticsNotifier extends Notifier<CurriculumAnalyticsState> {
  static String get baseUrl => ApiConfig.curriculumAnalyticsUrl;

  @override
  CurriculumAnalyticsState build() {
    return const CurriculumAnalyticsState();
  }

  Future<void> fetchAnalytics({
    String? academicYear,
    String? rubricId,
    String? program,
    String? scope,
  }) async {
    final nextYear = academicYear ?? state.selectedAcademicYear;
    final nextRubricId = rubricId ?? state.selectedRubricId;
    final nextProgram = program ?? state.selectedProgram;
    final nextScope = scope ?? state.selectedScope;

    state = state.copyWith(
      isLoading: state.data.isEmpty,
      selectedAcademicYear: nextYear,
      selectedRubricId: nextRubricId,
      selectedProgram: nextProgram,
      selectedScope: nextScope,
      clearError: true,
      clearMessage: true,
    );

    try {
      final queryParams = <String, String>{};
      if (nextYear.isNotEmpty) queryParams['academic_year'] = nextYear;
      if (nextRubricId.isNotEmpty && nextRubricId != 'all') {
        queryParams['rubric_id'] = nextRubricId;
      }
      if (nextProgram.isNotEmpty && nextProgram != 'All Programs') {
        queryParams['program'] = nextProgram;
      }
      if (nextScope.isNotEmpty && nextScope != 'All Levels') {
        queryParams['scope'] = nextScope.toLowerCase();
      }

      final uri = Uri.parse(baseUrl).replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        state = state.copyWith(
          isLoading: false,
          data: payload,
          selectedAcademicYear:
              payload['selected_academic_year']?.toString() ?? nextYear,
          selectedRubricId:
              payload['selected_rubric_id']?.toString() ?? nextRubricId,
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

  Future<void> generateProposal({String? academicYear, String? rubricId, String? scope}) async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
      clearProposal: true,
    );

    final targetYear = academicYear ?? state.selectedAcademicYear;
    final targetRubric = rubricId ?? state.selectedRubricId;
    final targetScope = scope ?? state.selectedScope;

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/proposal/'),
        body: jsonEncode({
          if (targetYear.isNotEmpty) 'academic_year': targetYear,
          if (targetRubric.isNotEmpty && targetRubric != 'all') 'rubric_id': targetRubric,
          if (targetScope.isNotEmpty && targetScope != 'all' && targetScope != 'All Levels') 'scope': targetScope.toLowerCase(),
        }),
      );
      if (response.statusCode == 200) {
        state = state.copyWith(
          isSaving: false,
          proposal: Map<String, dynamic>.from(jsonDecode(response.body)),
          message: 'Curriculum Decision Support Proposal generated.',
          clearError: true,
        );
        return;
      }
      state = state.copyWith(
        isSaving: false,
        error: _errorFromResponse(response),
      );
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Connection error: $e');
    }
  }

  Future<void> downloadProposalPdf({String? academicYear, String? rubricId, String? scope}) async {
    state = state.copyWith(
      isDownloadingPdf: true,
      clearError: true,
      clearMessage: true,
    );

    final targetYear = academicYear ?? state.selectedAcademicYear;
    final targetRubric = rubricId ?? state.selectedRubricId;
    final targetScope = scope ?? state.selectedScope;

    try {
      final uri = Uri.parse('$baseUrl/proposal/pdf/').replace(
        queryParameters: {
          if (targetYear.isNotEmpty) 'academic_year': targetYear,
          if (targetRubric.isNotEmpty && targetRubric != 'all') 'rubric_id': targetRubric,
          if (targetScope.isNotEmpty && targetScope != 'all' && targetScope != 'All Levels') 'scope': targetScope.toLowerCase(),
        },
      );
      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        final trackSuffix = (targetScope.isNotEmpty && targetScope != 'all' && targetScope != 'All Levels') ? '_${targetScope.toUpperCase()}' : '';
        final fileName = 'Curriculum_Proposal_AY_${targetYear.isNotEmpty ? targetYear : "Report"}$trackSuffix.pdf';
        await downloadBytesFile(
          bytes: response.bodyBytes,
          fileName: fileName,
          mimeType: 'application/pdf',
        );
        state = state.copyWith(
          isDownloadingPdf: false,
          message: 'Curriculum Proposal PDF downloaded successfully.',
          clearError: true,
        );
        return;
      }
      state = state.copyWith(
        isDownloadingPdf: false,
        error: _errorFromResponse(response),
      );
    } catch (e) {
      state = state.copyWith(isDownloadingPdf: false, error: 'Download failed: $e');
    }
  }


  AuthenticatedHttpClient get _client => ref.read(authenticatedHttpClientProvider);

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
