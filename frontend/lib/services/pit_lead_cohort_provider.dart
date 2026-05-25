import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import 'authenticated_client.dart';

final pitLeadCohortProvider =
    NotifierProvider<PitLeadCohortNotifier, PitLeadCohortState>(
  PitLeadCohortNotifier.new,
);

class PitLeadCohortState {
  final bool isLoading;
  final List<Map<String, dynamic>> students;
  final Map<String, dynamic> counts;
  final String? pitLeadYear;
  final String? activeSemester;
  final String? error;
  final String operatingMode;
  final String? operatingMessage;
  final List<Map<String, dynamic>> historyStudents;
  final Map<String, dynamic> historyCounts;
  final String search;
  final String teamStatusFilter;

  PitLeadCohortState({
    this.isLoading = false,
    this.students = const [],
    this.counts = const {},
    this.pitLeadYear,
    this.activeSemester,
    this.error,
    this.operatingMode = 'active',
    this.operatingMessage,
    this.historyStudents = const [],
    this.historyCounts = const {},
    this.search = '',
    this.teamStatusFilter = 'all',
  });

  PitLeadCohortState copyWith({
    bool? isLoading,
    List<Map<String, dynamic>>? students,
    Map<String, dynamic>? counts,
    String? pitLeadYear,
    String? activeSemester,
    String? error,
    String? operatingMode,
    String? operatingMessage,
    List<Map<String, dynamic>>? historyStudents,
    Map<String, dynamic>? historyCounts,
    String? search,
    String? teamStatusFilter,
    bool clearError = false,
  }) {
    return PitLeadCohortState(
      isLoading: isLoading ?? this.isLoading,
      students: students ?? this.students,
      counts: counts ?? this.counts,
      pitLeadYear: pitLeadYear ?? this.pitLeadYear,
      activeSemester: activeSemester ?? this.activeSemester,
      error: clearError ? null : (error ?? this.error),
      operatingMode: operatingMode ?? this.operatingMode,
      operatingMessage: operatingMessage ?? this.operatingMessage,
      historyStudents: historyStudents ?? this.historyStudents,
      historyCounts: historyCounts ?? this.historyCounts,
      search: search ?? this.search,
      teamStatusFilter: teamStatusFilter ?? this.teamStatusFilter,
    );
  }
}

class PitLeadCohortNotifier extends Notifier<PitLeadCohortState> {
  AuthenticatedHttpClient get _client => ref.read(authenticatedHttpClientProvider);

  @override
  PitLeadCohortState build() => PitLeadCohortState();

  Future<void> fetchCohort({
    String? search,
    String? teamStatusFilter,
    String? scope,
  }) async {
    final nextSearch = search ?? state.search;
    final nextFilter = teamStatusFilter ?? state.teamStatusFilter;

    state = state.copyWith(
      isLoading: true,
      search: nextSearch,
      teamStatusFilter: nextFilter,
      clearError: true,
    );

    try {
      final query = <String, String>{};
      if (nextSearch.trim().isNotEmpty) {
        query['search'] = nextSearch.trim();
      }
      if (nextFilter != 'all') {
        query['team_status'] = nextFilter;
      }
      if (scope != null && scope.isNotEmpty) {
        query['scope'] = scope;
      }

      final uri = Uri.parse('${ApiConfig.dashboardsUrl}/pit-lead/cohort/')
          .replace(queryParameters: query.isEmpty ? null : query);

      final response = await _client.get(uri);

      if (response.statusCode == 200) {
        final payload = Map<String, dynamic>.from(jsonDecode(response.body));
        final students = (payload['students'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        final counts = payload['counts'] is Map
            ? Map<String, dynamic>.from(payload['counts'] as Map)
            : <String, dynamic>{};

        final historyStudents = (payload['history_students'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        final historyCounts = payload['history_counts'] is Map
            ? Map<String, dynamic>.from(payload['history_counts'] as Map)
            : <String, dynamic>{};

        state = state.copyWith(
          isLoading: false,
          students: students,
          counts: counts,
          pitLeadYear: payload['pit_lead_year']?.toString(),
          activeSemester: payload['active_semester']?.toString(),
          operatingMode: payload['operating_mode']?.toString() ?? 'active',
          operatingMessage: payload['operating_message']?.toString(),
          historyStudents: historyStudents,
          historyCounts: historyCounts,
          clearError: true,
        );
      } else if (response.statusCode == 403) {
        state = state.copyWith(
          isLoading: false,
          error: 'You do not have permission to view this cohort roster.',
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to load cohort roster (${response.statusCode}).',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Connection error: $e',
      );
    }
  }
}
