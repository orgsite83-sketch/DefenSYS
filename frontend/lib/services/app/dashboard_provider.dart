import 'dart:convert';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api_config.dart';
import '../network/authenticated_client.dart';
import '../session/session_expired.dart';
import 'data_refresh_provider.dart';

final dashboardProvider =
    NotifierProvider.family<DashboardNotifier, DashboardState, String>(
      DashboardNotifier.new,
    );

class DashboardState {
  final bool isLoading;
  final bool isRefreshing;
  final Map<String, dynamic>? data;
  final String? error;

  DashboardState({
    this.isLoading = false,
    this.isRefreshing = false,
    this.data,
    this.error,
  });

  DashboardState copyWith({
    bool? isLoading,
    bool? isRefreshing,
    Map<String, dynamic>? data,
    String? error,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      data: data ?? this.data,
      error: error,
    );
  }
}

class DashboardNotifier extends Notifier<DashboardState> {
  DashboardNotifier(this.role);

  final String role;
  int _requestRevision = 0;
  Completer<void>? _studentRefresh;
  int? _studentRefreshRevision;

  @override
  DashboardState build() {
    return DashboardState();
  }

  static String get baseUrl => ApiConfig.dashboardsUrl;

  AuthenticatedHttpClient get _client =>
      ref.read(authenticatedHttpClientProvider);

  void applyStudentConceptWorkflow(int teamId, String stageLabel, Map<String, dynamic> workflow) {
    if (role != 'student' || state.data?['team']?['id'] != teamId) return;
    final stages = (state.data?['stages'] as List? ?? []).whereType<Map>().map((s) => <String, dynamic>{
      ...s,
      if (s['stage_label'] == stageLabel && (s['team_id'] == null || s['team_id'] == teamId))
        'concept_workflow': workflow,
    }).toList();
    state = state.copyWith(data: {...state.data!, 'stages': stages});
  }

  Future<void> fetchDashboardData({bool silent = false}) async {
    // The Team tab always resolves Current roster on the server. Event team
    // selection belongs to the event workspace and never changes the home team.
    final dataRevision = ref.read(dataRefreshProvider)[DataArea.dashboard] ?? 0;
    if (role == 'student' &&
        _studentRefresh != null &&
        _studentRefreshRevision == dataRevision) {
      return _studentRefresh!.future;
    }
    final completion = Completer<void>();
    if (role == 'student') {
      _studentRefresh = completion;
      _studentRefreshRevision = dataRevision;
    }
    final revision = ++_requestRevision;
    final hasData = state.data != null;
    if (!silent || !hasData) {
      state = state.copyWith(isLoading: true, isRefreshing: false, error: null);
    } else {
      state = state.copyWith(isRefreshing: true, error: null);
    }

    try {
      final url = '$baseUrl/$role/';
      final response = await _client.get(Uri.parse(url));
      if (!ref.mounted || revision != _requestRevision) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        state = state.copyWith(
          isLoading: false,
          isRefreshing: false,
          data: data is Map<String, dynamic>
              ? data
              : Map<String, dynamic>.from(data as Map),
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          isRefreshing: false,
          error:
              'Failed to load dashboard data. Status: ${response.statusCode}',
        );
      }
    } on SessionExpiredException {
      rethrow;
    } catch (e) {
      if (!ref.mounted || revision != _requestRevision) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: 'Connection error: $e',
      );
    } finally {
      completion.complete();
      if (identical(_studentRefresh, completion)) _studentRefresh = null;
    }
  }
}
