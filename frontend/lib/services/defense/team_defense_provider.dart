import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_config.dart';
import '../network/authenticated_client.dart';

class TeamDefenseState {
  final bool isLoading;
  final List<Map<String, dynamic>> schedules;
  final String? error;

  const TeamDefenseState({
    this.isLoading = false,
    this.schedules = const [],
    this.error,
  });
}

final teamDefenseProvider =
    NotifierProvider<TeamDefenseNotifier, TeamDefenseState>(
      TeamDefenseNotifier.new,
    );

final pitInstructorDefenseProvider =
    NotifierProvider<PitInstructorDefenseNotifier, TeamDefenseState>(
      PitInstructorDefenseNotifier.new,
    );

/// The board scopes access on the server. Each workspace additionally filters
/// by its team, so multi-role users only see that team's defense records.
class TeamDefenseNotifier extends Notifier<TeamDefenseState> {
  int _requestVersion = 0;
  String get scope => 'capstone';
  String? get defaultWorkspace => null;

  @override
  TeamDefenseState build() {
    ref.onDispose(() => _requestVersion++);
    return const TeamDefenseState();
  }

  Future<void> fetch({String? workspace}) async {
    final version = ++_requestVersion;
    state = TeamDefenseState(isLoading: true, schedules: state.schedules);
    try {
      final uri = Uri.parse(ApiConfig.defenseBoardUrl).replace(
        queryParameters: {
          'scope': scope,
          if (workspace ?? defaultWorkspace case final String selectedWorkspace)
            'workspace': selectedWorkspace,
        },
      );
      final response = await ref.read(authenticatedHttpClientProvider).get(uri);
      if (!ref.mounted || version != _requestVersion) return;
      if (response.statusCode != 200) {
        state = TeamDefenseState(
          schedules: state.schedules,
          error: 'Unable to load defense details (${response.statusCode}).',
        );
        return;
      }
      final payload = jsonDecode(response.body);
      final raw = payload is Map ? payload['schedules'] : null;
      if (raw is! List) {
        throw const FormatException('Missing defense schedules');
      }
      state = TeamDefenseState(
        schedules: raw
            .whereType<Map>()
            .map((s) => Map<String, dynamic>.from(s))
            .toList(),
      );
    } catch (_) {
      if (!ref.mounted || version != _requestVersion) return;
      state = TeamDefenseState(
        schedules: state.schedules,
        error:
            'Unable to load defense details. Check your connection and retry.',
      );
    }
  }
}

class PitInstructorDefenseNotifier extends TeamDefenseNotifier {
  @override
  String get scope => 'pit';
  @override
  String get defaultWorkspace => 'instructor';
}
