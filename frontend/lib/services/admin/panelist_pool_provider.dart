import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api_config.dart';
import '../auth_provider.dart';
import '../authenticated_client.dart';
import '../app/data_refresh_provider.dart';
import 'panelist_requests_provider.dart';

final panelistPoolProvider =
    NotifierProvider.autoDispose<PanelistPoolNotifier, PanelistPoolState>(
      PanelistPoolNotifier.new,
    );

class PanelistPoolState {
  const PanelistPoolState({
    this.faculty = const [],
    this.requests = const [],
    this.canApprovePanelists = false,
    this.loading = false,
    this.error,
  });
  final List<Map<String, dynamic>> faculty, requests;
  final bool canApprovePanelists, loading;
  final String? error;

  bool isEligiblePanelist(int id) => faculty.any(
    (person) => person['id'] == id && person['is_panelist'] == true,
  );
}

class PanelistPoolNotifier extends Notifier<PanelistPoolState> {
  int _epoch = 0, _request = 0;

  @override
  PanelistPoolState build() {
    final userId = ref.watch(authProvider.select((s) => s.user?['id']));
    final epoch = ++_epoch;
    if (userId != null) {
      Future.microtask(() {
        if (ref.mounted && epoch == _epoch) fetch();
      });
    }
    return PanelistPoolState(loading: userId != null);
  }

  Future<void> fetch() async {
    if (ref.read(authProvider).user?['id'] == null) return;
    final epoch = _epoch, request = ++_request;
    state = PanelistPoolState(
      faculty: state.faculty,
      requests: state.requests,
      canApprovePanelists: state.canApprovePanelists,
      loading: true,
    );
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(Uri.parse('${ApiConfig.usersUrl}/panelist-pool/'));
      if (!ref.mounted || epoch != _epoch || request != _request) return;
      if (response.statusCode != 200) throw Exception('Pool unavailable');
      final data = jsonDecode(response.body) as Map;
      state = PanelistPoolState(
        faculty: List<Map<String, dynamic>>.from(data['faculty'] ?? []),
        requests: List<Map<String, dynamic>>.from(
          data['panelist_requests'] ?? [],
        ),
        canApprovePanelists: data['can_approve_panelists'] == true,
      );
    } catch (_) {
      if (ref.mounted && epoch == _epoch && request == _request) {
        state = PanelistPoolState(
          faculty: state.faculty,
          requests: state.requests,
          canApprovePanelists: state.canApprovePanelists,
          error: 'Could not load panelist eligibility. Refresh to try again.',
        );
      }
    }
  }

  Future<bool> nominate(int facultyId, String reason) async {
    final epoch = _epoch;
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .post(
            Uri.parse('${ApiConfig.usersUrl}/panelist-requests/'),
            body: jsonEncode({'faculty_id': facultyId, 'reason': reason}),
          );
      if (!ref.mounted || epoch != _epoch) return false;
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Nomination failed');
      }
      ref.invalidate(panelistRequestsProvider);
      ref.read(dataRefreshProvider.notifier).markChanged([
        DataArea.scheduler,
        DataArea.users,
        DataArea.dashboard,
      ]);
      await fetch();
      // The POST succeeded even if the following refresh failed. Do not invite
      // a second submission; keep this faculty pending until a successful read.
      if (ref.mounted && epoch == _epoch && state.error != null) {
        state = PanelistPoolState(
          faculty: state.faculty,
          requests: [
            ...state.requests,
            {'faculty_id': facultyId, 'status': 'pending'},
          ],
          canApprovePanelists: state.canApprovePanelists,
          error: state.error,
        );
      }
      return true;
    } catch (_) {
      if (ref.mounted && epoch == _epoch) {
        state = PanelistPoolState(
          faculty: state.faculty,
          requests: state.requests,
          canApprovePanelists: state.canApprovePanelists,
          error:
              'Could not submit the request. Refresh its status before trying again.',
        );
      }
      return false;
    }
  }
}
