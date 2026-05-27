import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import 'authenticated_client.dart';

final systemAuditProvider =
    NotifierProvider<SystemAuditNotifier, SystemAuditState>(
  SystemAuditNotifier.new,
);

class SystemAuditState {
  final bool isLoading;
  final List<Map<String, dynamic>> logs;
  final Map<String, dynamic> counts;
  final Map<String, dynamic> options;
  final String category;
  final String reviewStatus;
  final String action;
  final String search;
  final String? error;

  const SystemAuditState({
    this.isLoading = false,
    this.logs = const [],
    this.counts = const {},
    this.options = const {},
    this.category = '',
    this.reviewStatus = '',
    this.action = '',
    this.search = '',
    this.error,
  });

  SystemAuditState copyWith({
    bool? isLoading,
    List<Map<String, dynamic>>? logs,
    Map<String, dynamic>? counts,
    Map<String, dynamic>? options,
    String? category,
    String? reviewStatus,
    String? action,
    String? search,
    String? error,
    bool clearError = false,
  }) {
    return SystemAuditState(
      isLoading: isLoading ?? this.isLoading,
      logs: logs ?? this.logs,
      counts: counts ?? this.counts,
      options: options ?? this.options,
      category: category ?? this.category,
      reviewStatus: reviewStatus ?? this.reviewStatus,
      action: action ?? this.action,
      search: search ?? this.search,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class SystemAuditNotifier extends Notifier<SystemAuditState> {
  @override
  SystemAuditState build() => const SystemAuditState();

  Future<void> fetch() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final params = <String, String>{
      if (state.category.isNotEmpty) 'category': state.category,
      if (state.reviewStatus.isNotEmpty) 'review_status': state.reviewStatus,
      if (state.action.isNotEmpty) 'action': state.action,
      if (state.search.isNotEmpty) 'search': state.search,
    };
    final uri = Uri.parse('${ApiConfig.baseUrl}/audit-logs/').replace(
      queryParameters: params.isEmpty ? null : params,
    );
    try {
      final response = await ref.read(authenticatedHttpClientProvider).get(uri);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(body['detail']?.toString() ?? 'Unable to load audit logs.');
      }
      state = state.copyWith(
        isLoading: false,
        logs: List<Map<String, dynamic>>.from(body['audit_logs'] ?? const []),
        counts: Map<String, dynamic>.from(body['counts'] ?? const {}),
        options: Map<String, dynamic>.from(body['options'] ?? const {}),
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setCategory(String value) {
    state = state.copyWith(category: value);
    fetch();
  }

  void setReviewStatus(String value) {
    state = state.copyWith(reviewStatus: value);
    fetch();
  }

  void setAction(String value) {
    state = state.copyWith(action: value);
    fetch();
  }

  void setSearch(String value) {
    state = state.copyWith(search: value);
  }
}
