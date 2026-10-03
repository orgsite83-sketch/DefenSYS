import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api_config.dart';
import '../network/authenticated_client.dart';

final externalEvaluatorProvider =
    NotifierProvider<ExternalEvaluatorNotifier, ExternalEvaluatorState>(
      ExternalEvaluatorNotifier.new,
    );

class ExternalEvaluatorState {
  const ExternalEvaluatorState({
    this.evaluators = const [],
    this.invitations = const [],
    this.schedules = const [],
    this.createdInvitations = const [],
    this.canApprove = false,
    this.loading = false,
    this.saving = false,
    this.error,
    this.activeSemesterId,
  });
  final List<Map<String, dynamic>> evaluators,
      invitations,
      schedules,
      createdInvitations;
  final bool canApprove, loading, saving;
  final String? error;
  final int? activeSemesterId;
  ExternalEvaluatorState copyWith({
    bool? loading,
    bool? saving,
    String? error,
  }) => ExternalEvaluatorState(
    evaluators: evaluators,
    invitations: invitations,
    schedules: schedules,
    createdInvitations: const [],
    canApprove: canApprove,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    error: error,
    activeSemesterId: activeSemesterId,
  );
  List<Map<String, dynamic>> get approved => evaluators
      .where((e) => e['status'] == 'approved' && e['is_active'] == true)
      .toList();
}

class ExternalEvaluatorNotifier extends Notifier<ExternalEvaluatorState> {
  @override
  ExternalEvaluatorState build() => const ExternalEvaluatorState();
  String get _base => ApiConfig.usersUrl;
  List<Map<String, dynamic>> _list(dynamic value) => (value as List? ?? [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  Future<bool> fetch() => _request('external-evaluators/', null);
  Future<bool> register(Map<String, dynamic> data) =>
      _request('external-evaluators/', data);
  Future<bool> review(int id, Map<String, dynamic> data) =>
      _request('external-evaluators/$id/', data, patch: true);
  Future<bool> invite(
    List<int> evaluatorIds,
    List<int> scheduleIds,
    DateTime expiry,
  ) => _request('external-invitations/', {
    'evaluator_ids': evaluatorIds,
    'schedule_ids': scheduleIds,
    'expires_at': expiry.toUtc().toIso8601String(),
  });
  Future<bool> revoke(int id) =>
      _request('external-invitations/$id/', {'is_active': false}, patch: true);
  Future<bool> renew(int id, DateTime expiry) => _request(
    'external-invitations/$id/',
    {'is_active': true, 'expires_at': expiry.toUtc().toIso8601String()},
    patch: true,
  );
  Future<bool> _request(
    String path,
    Map<String, dynamic>? data, {
    bool patch = false,
  }) async {
    state = state.copyWith(loading: data == null, saving: data != null);
    try {
      final client = ref.read(authenticatedHttpClientProvider);
      final uri = Uri.parse('$_base/$path');
      final response = data == null
          ? await client.get(uri)
          : patch
          ? await client.patch(uri, body: jsonEncode(data))
          : await client.post(uri, body: jsonEncode(data));
      if (!ref.mounted) return false;
      final payload = jsonDecode(response.body) as Map;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String describe(dynamic value) => value is List
            ? value.map(describe).join(' ')
            : value is Map
            ? value.values.map(describe).join(' ')
            : value.toString();
        state = state.copyWith(
          loading: false,
          saving: false,
          error: describe(payload),
        );
        return false;
      }
      state = ExternalEvaluatorState(
        evaluators: _list(payload['evaluators']),
        invitations: _list(payload['invitations']),
        schedules: _list(payload['schedules']),
        createdInvitations: _list(payload['created_invitations']),
        canApprove: payload['can_approve'] == true,
        activeSemesterId: (payload['active_semester_id'] as num?)?.toInt(),
      );
      return true;
    } catch (_) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        loading: false,
        saving: false,
        error: 'Could not connect. Check your connection and try again.',
      );
      return false;
    }
  }
}
