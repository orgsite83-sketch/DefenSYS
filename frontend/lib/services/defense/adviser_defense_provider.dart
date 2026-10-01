import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_config.dart';
import '../network/authenticated_client.dart';

class AdviserDefenseState {
  final bool isLoading;
  final List<Map<String, dynamic>> schedules;
  final String? error;

  const AdviserDefenseState({
    this.isLoading = false,
    this.schedules = const [],
    this.error,
  });
}

final adviserDefenseProvider =
    NotifierProvider<AdviserDefenseNotifier, AdviserDefenseState>(
      AdviserDefenseNotifier.new,
    );

/// Uses the existing, permission-scoped defense board feed. The adviser UI
/// additionally matches schedule team IDs to the adviser's assigned teams so
/// multi-role accounts do not see their admin/PIT schedules in this workspace.
class AdviserDefenseNotifier extends Notifier<AdviserDefenseState> {
  @override
  AdviserDefenseState build() => const AdviserDefenseState();

  Future<void> fetch() async {
    state = AdviserDefenseState(isLoading: true, schedules: state.schedules);
    try {
      final uri = Uri.parse(
        ApiConfig.defenseBoardUrl,
      ).replace(queryParameters: {'scope': 'capstone'});
      final response = await ref.read(authenticatedHttpClientProvider).get(uri);
      if (response.statusCode != 200) {
        state = AdviserDefenseState(
          schedules: state.schedules,
          error: 'Unable to load defense details (${response.statusCode}).',
        );
        return;
      }
      final payload = jsonDecode(response.body);
      final raw = payload is Map ? payload['schedules'] : null;
      state = AdviserDefenseState(
        schedules: raw is List
            ? raw
                  .whereType<Map>()
                  .map((s) => Map<String, dynamic>.from(s))
                  .toList()
            : const [],
      );
    } catch (_) {
      state = AdviserDefenseState(
        schedules: state.schedules,
        error:
            'Unable to load defense details. Check your connection and retry.',
      );
    }
  }
}
