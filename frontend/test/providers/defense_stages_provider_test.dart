import 'dart:convert';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/services/defense/defense_scheduler_provider.dart';
import 'package:defensys/services/defense/template_configuration.dart';
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

  test('missing draft template is validation, not a network failure, in all setup saves', () async {
    var requests = 0;
    setApiHttpClientForTesting(MockClient((request) async {
      requests++;
      return http.Response('{}', 500);
    }));
    final container = ProviderContainer(overrides: authTestOverrides());
    addTearDown(container.dispose);
    final row = <String, dynamic>{'deliverable_id': 'D1', 'label': 'Concept Papers',
      'template_action': 'replace', 'template_selection_name': 'Paper.docx'};
    final payload = <String, dynamic>{'label': 'Concept Proposal', 'deliverables': [row],
      '_templateDrafts': templateDrafts([row], [])};
    final stages = container.read(defenseStagesProvider.notifier);
    expect(await stages.addStage(payload), isNull);
    expect(container.read(defenseStagesProvider).error, startsWith('Select the template'));
    expect(container.read(defenseStagesProvider).error, isNot(contains('Connection')));
    expect(container.read(defenseStagesProvider).isSaving, isFalse);
    expect(await stages.updateStage(7, payload), isFalse);
    expect(container.read(defenseStagesProvider).error, isNot(contains('Connection')));
    expect(await container.read(defenseSchedulerProvider.notifier).savePitEventConfig(payload), isFalse);
    expect(container.read(defenseSchedulerProvider).error, startsWith('Select the template'));
    expect(container.read(defenseSchedulerProvider).error, isNot(contains('Connection')));
    expect(requests, 0);
  });

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

  test('locked source timeline is excluded from an empty continuation sequence', () {
    const state = DefenseStagesState(
      stages: [
        {'id': 1, 'semester_id': 3, 'history_read_only': true},
      ],
      sequenceStages: [],
      phaseGroups: [
        {'phase': 'capstone_1', 'semester_id': 3, 'read_only': true},
        {'phase': 'capstone_2', 'semester_id': 4, 'read_only': false},
      ],
    );
    expect(state.pipelineStages, isEmpty);
    expect(state.stages, hasLength(1));
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
