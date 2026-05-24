import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_http.dart';
import 'authenticated_client.dart';
import 'provider_errors.dart';
import 'session_expired.dart';

final pitRepositoryAssistantProvider =
    NotifierProvider<PitRepositoryAssistantNotifier, PitRepositoryAssistantState>(
      PitRepositoryAssistantNotifier.new,
    );

class PitRepositoryAssistantState {
  final bool isLoading;
  final bool isSaving;
  final String yearLevel;
  final Map<String, dynamic>? assigned;
  final List<Map<String, dynamic>> candidates;
  final String? error;
  final String? message;

  const PitRepositoryAssistantState({
    this.isLoading = false,
    this.isSaving = false,
    this.yearLevel = '',
    this.assigned,
    this.candidates = const [],
    this.error,
    this.message,
  });

  PitRepositoryAssistantState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? yearLevel,
    Map<String, dynamic>? assigned,
    List<Map<String, dynamic>>? candidates,
    String? error,
    String? message,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return PitRepositoryAssistantState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      yearLevel: yearLevel ?? this.yearLevel,
      assigned: assigned ?? this.assigned,
      candidates: candidates ?? this.candidates,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class PitRepositoryAssistantNotifier extends Notifier<PitRepositoryAssistantState> {
  static String get _url => '${ApiConfig.dashboardsUrl}/pit-lead/repository-assistant/';

  @override
  PitRepositoryAssistantState build() => const PitRepositoryAssistantState();

  Future<void> fetch() async {
    state = state.copyWith(isLoading: true, clearError: true, clearMessage: true);
    try {
      final response = await _client.get(
        Uri.parse(_url),
        
      );
      if (response.statusCode == 200) {
        _applyPayload(jsonDecode(response.body));
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

  Future<bool> assign(int facultyId) async {
    state = state.copyWith(isSaving: true, clearError: true, clearMessage: true);
    try {
      final response = await _client.post(
        Uri.parse(_url),
        
        body: jsonEncode({'faculty_id': facultyId}),
      );
      if (response.statusCode == 200) {
        _applyPayload(jsonDecode(response.body), message: 'Repository assistant assigned.');
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

  void _applyPayload(Map<String, dynamic> payload, {String? message}) {
    final assigned = payload['assigned'];
    state = state.copyWith(
      isLoading: false,
      isSaving: false,
      yearLevel: payload['year_level']?.toString() ?? '',
      assigned: assigned is Map ? Map<String, dynamic>.from(assigned) : null,
      candidates: _readCandidates(payload['candidates']),
      message: message,
      clearError: true,
    );
  }

  List<Map<String, dynamic>> _readCandidates(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  AuthenticatedHttpClient get _client => ref.read(authenticatedHttpClientProvider);


  String _errorFromResponse(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map) {
        if (data['detail'] != null) return data['detail'].toString();
        if (data.isNotEmpty) {
          final first = data.values.first;
          if (first is List && first.isNotEmpty) return first.first.toString();
          return first.toString();
        }
      }
    } catch (_) {
      // Non-JSON error body — use status line below.
    }
    return 'Request failed. Status: ${response.statusCode}';
  }
}
