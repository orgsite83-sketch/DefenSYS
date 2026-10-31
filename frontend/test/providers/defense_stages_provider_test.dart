import 'dart:convert';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(resetApiHttpClientForTesting);

  test('empty current setup has its own empty sequence', () async {
    setApiHttpClientForTesting(MockClient((request) async => http.Response(
      jsonEncode({
        'stages': [], 'active_stages': [],
        'counts': {'total': 0, 'active': 0, 'inactive': 0},
        'sequence_stages': [],
        'phase_groups': [
          {'phase_label': 'Capstone 1', 'semester_id': 4,
           'display_semester': '2nd Semester, A.Y. 2026-2027', 'stages': []},
        ],
      }), 200,
    )));
    final container = ProviderContainer(overrides: authTestOverrides());
    addTearDown(container.dispose);
    await container.read(defenseStagesProvider.notifier).fetchStages();
    final state = container.read(defenseStagesProvider);
    expect(state.error, isNull);
    expect(state.stages, isEmpty);
    expect(state.activeStages, isEmpty);
    expect(state.counts['total'], 0);
    expect(state.pipelineStages, isEmpty);
    expect(state.phaseGroups.single['stages'], isEmpty);
    expect(state.phaseGroups.single['semester_id'], 4);
  });

  test('history preserves source semester and year across refreshes', () async {
    final requests = <Uri>[];
    setApiHttpClientForTesting(MockClient((request) async {
      requests.add(request.url);
      return http.Response(jsonEncode({
        'stages': [{'id': 1, 'semester_id': 3, 'history_read_only': true}],
        'capstone_history': {'selected_intake_id': 3},
        'phase_groups': [
          {'phase_label': 'Capstone 1', 'semester_id': 3, 'read_only': true,
           'display_semester': '2nd Semester, A.Y. 2025-2026', 'stages': []},
          {'phase_label': 'Capstone 2', 'semester_id': 1, 'read_only': true,
           'display_semester': '1st Semester, A.Y. 2026-2027', 'stages': []},
        ],
      }), 200);
    }));
    final container = ProviderContainer(overrides: authTestOverrides());
    addTearDown(container.dispose);
    final notifier = container.read(defenseStagesProvider.notifier);
    await notifier.fetchStages(scope: 'history');
    await notifier.fetchStages(phase: 'capstone_1', stage: '3:1');
    await notifier.fetchStages();
    expect(requests.last.queryParameters, {
      'scope': 'history', 'intake_id': '3', 'phase': 'capstone_1', 'stage_key': '3:1',
    });
    final state = container.read(defenseStagesProvider);
    expect(state.stages.single['semester_id'], 3);
    expect(state.phaseGroups.map((g) => g['display_semester']), [
      '2nd Semester, A.Y. 2025-2026', '1st Semester, A.Y. 2026-2027',
    ]);
  });

  test('reordering current stages sends only this batch sequence', () async {
    List<dynamic>? reordered;
    setApiHttpClientForTesting(MockClient((request) async {
      if (request.method == 'POST') {
        reordered = jsonDecode(request.body)['stage_ids'] as List;
      }
      return http.Response(jsonEncode({
        'stages': [{'id': 3}, {'id': 4}],
        'sequence_stages': [{'id': 3}, {'id': 4}],
      }), 200);
    }));
    final container = ProviderContainer(overrides: authTestOverrides());
    addTearDown(container.dispose);
    final notifier = container.read(defenseStagesProvider.notifier);
    await notifier.fetchStages();
    expect(await notifier.moveStage(4, -1), isTrue);
    expect(reordered, [4, 3]);
  });
}
