import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'authenticated_client.dart';
import 'provider_errors.dart';
import 'session_expired.dart';

final curriculumAnalyticsProvider =
    NotifierProvider<CurriculumAnalyticsNotifier, CurriculumAnalyticsState>(
      CurriculumAnalyticsNotifier.new,
    );

class CurriculumAnalyticsState {
  final bool isLoading;
  final bool isSaving;
  final Map<String, dynamic> data;
  final Map<String, dynamic>? proposal;
  final String selectedAcademicYear;
  final String? error;
  final String? message;

  const CurriculumAnalyticsState({
    this.isLoading = false,
    this.isSaving = false,
    this.data = const {},
    this.proposal,
    this.selectedAcademicYear = '',
    this.error,
    this.message,
  });

  CurriculumAnalyticsState copyWith({
    bool? isLoading,
    bool? isSaving,
    Map<String, dynamic>? data,
    Map<String, dynamic>? proposal,
    String? selectedAcademicYear,
    String? error,
    String? message,
    bool clearProposal = false,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return CurriculumAnalyticsState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      data: data ?? this.data,
      proposal: clearProposal ? null : proposal ?? this.proposal,
      selectedAcademicYear: selectedAcademicYear ?? this.selectedAcademicYear,
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

  Future<void> fetchAnalytics({String? academicYear}) async {
    final nextYear = academicYear ?? state.selectedAcademicYear;
    state = state.copyWith(
      isLoading: state.data.isEmpty,
      selectedAcademicYear: nextYear,
      clearError: true,
      clearMessage: true,
    );

    try {
      final uri = Uri.parse(baseUrl).replace(
        queryParameters: {if (nextYear.isNotEmpty) 'academic_year': nextYear},
      );
      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        state = state.copyWith(
          isLoading: false,
          data: payload,
          selectedAcademicYear:
              payload['selected_academic_year']?.toString() ?? nextYear,
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

  Future<void> generateProposal() async {
    state = state.copyWith(
      isSaving: true,
      clearError: true,
      clearMessage: true,
      clearProposal: true,
    );

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/proposal/'),
        
        body: jsonEncode({}),
      );
      if (response.statusCode == 200) {
        state = state.copyWith(
          isSaving: false,
          proposal: Map<String, dynamic>.from(jsonDecode(response.body)),
          message: 'Curriculum proposal generated.',
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
