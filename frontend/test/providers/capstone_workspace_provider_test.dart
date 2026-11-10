import 'dart:async';
import 'dart:convert';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/grade_center_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';

http.Response phaseResponse(Uri uri) {
  final q = uri.queryParameters;
  final term = q['phase_semester_id'] ?? '14';
  return http.Response(
    jsonEncode({
      'teams': [],
      'grades': [],
      'stage_options': [],
      'capstone_stages': [],
      'active_semester': {'id': int.parse(term), 'is_active': term == '14'},
      'capstone_workspace': {
        'view': q['capstone_view'] ?? 'ongoing',
        'batch_id': q['batch_id'] ?? '12',
        'phase_semester_id': int.parse(term),
        'read_only': term != '14',
      },
    }),
    200,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(resetApiHttpClientForTesting);

  test(
    'current phase cards receive live updates without changing the source phase',
    () {
      const state = GradeCenterState(
        activeSemester: {'id': 14},
        groupSettings: {
          'capstone|Project': {'is_officially_complete': true},
        },
        grades: [
          {'id': 99},
        ],
        capstoneStages: [
          {'id': 35},
        ],
      );
      const current = {
        'semester_id': 14,
        'read_only': false,
        'payload': {
          'active_semester': {'id': 14},
          'grades': [],
          'group_settings': {
            'capstone|Project': {'is_officially_complete': false},
          },
        },
      };
      const source = {
        'semester_id': 12,
        'read_only': true,
        'payload': {
          'active_semester': {'id': 12},
          'grades': [
            {'id': 1},
          ],
          'group_settings': {
            'capstone|Project': {'is_officially_complete': false},
          },
        },
      };
      expect(
        state
            .forPhase(current)
            .groupSettings['capstone|Project']?['is_officially_complete'],
        isTrue,
      );
      expect(state.forPhase(current).grades.single['id'], 99);
      expect(state.forPhase(source).grades.single['id'], 1);
      expect(
        state
            .forPhase(source)
            .groupSettings['capstone|Project']?['is_officially_complete'],
        isFalse,
      );
    },
  );

  test(
    'adviser stage selection retains the stable term and stage key on refresh',
    () async {
      final requests = <Uri>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url);
          final q = request.url.queryParameters;
          return http.Response(
            jsonEncode({
              'teams': [],
              'stage_options': ['Project', 'Other'],
              'selected_stage': q['stage_label'] ?? 'Project',
              'capstone_workspace': {
                'view': 'ongoing',
                'batch_id': '12',
                'phase_semester_id': q['phase_semester_id'] ?? '14',
                'selected_stage_key': q['stage_key'] ?? '14:35',
                'stage_options': [
                  {'key': '12:34', 'semester_id': 12, 'stage_label': 'Project'},
                  {'key': '14:35', 'semester_id': 14, 'stage_label': 'Project'},
                  {'key': '12:36', 'semester_id': 12, 'stage_label': 'Other'},
                ],
              },
            }),
            200,
          );
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(capstoneDeliverablesProvider.notifier);
      notifier.configureBatchFilters(enabled: true);
      await notifier.fetchDeliverables(workspace: 'adviser');
      await notifier.selectSequenceStage('12:34');
      await notifier.fetchDeliverables(search: 'Cedar');
      expect(requests.last.queryParameters['stage_sequence'], 'all');
      expect(requests.last.queryParameters['stage_key'], '12:34');
      expect(requests.last.queryParameters['phase_semester_id'], '12');
      await notifier.fetchDeliverables(selectedStage: 'Other');
      expect(requests.last.queryParameters['stage_key'], '12:36');
    },
  );

  test(
    'adviser phase and history selections persist through search and refresh, isolated from PIT',
    () async {
      final requests = <Uri>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url);
          return phaseResponse(request.url);
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(capstoneDeliverablesProvider.notifier);
      notifier.configureBatchFilters(enabled: true);
      await notifier.fetchDeliverables(workspace: 'adviser');
      expect(requests.last.queryParameters['capstone_view'], 'ongoing');
      expect(
        requests.last.queryParameters.containsKey('participation'),
        isFalse,
      );
      await notifier.selectCapstoneWorkspace('history', '9', '10');
      await notifier.fetchDeliverables(search: 'Cedar');
      await notifier.fetchDeliverables();
      expect(
        requests.last.queryParameters,
        containsPair('capstone_view', 'history'),
      );
      expect(requests.last.queryParameters, containsPair('batch_id', '9'));
      expect(
        requests.last.queryParameters,
        containsPair('phase_semester_id', '10'),
      );
      await notifier.fetchDeliverables(scope: 'pit');
      expect(
        requests.last.queryParameters.containsKey('capstone_view'),
        isFalse,
      );
      expect(
        requests.last.queryParameters.containsKey('phase_semester_id'),
        isFalse,
      );
    },
  );

  test(
    'grade refresh requests both phases while retaining current phase statistics',
    () async {
      final requests = <Uri>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url);
          return phaseResponse(request.url);
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(gradeCenterProvider.notifier);
      await notifier.fetchGrades(scope: 'capstone');
      await notifier.selectCapstoneWorkspace('ongoing', '12', '12');
      await notifier.fetchGrades(search: 'Cedar');
      expect(
        requests.last.queryParameters,
        containsPair('include_phases', '1'),
      );
      expect(requests.last.queryParameters, containsPair('batch_id', '12'));
      expect(
        requests.last.queryParameters.containsKey('phase_semester_id'),
        isFalse,
      );
      expect(container.read(gradeCenterProvider).activeSemester?['id'], 14);
      await notifier.fetchGrades(scope: 'pit');
      expect(
        requests.last.queryParameters.containsKey('capstone_view'),
        isFalse,
      );
    },
  );

  test(
    'an earlier grade-phase response cannot replace the new phase',
    () async {
      final pending = <Completer<http.Response>>[];
      final urls = <Uri>[];
      setApiHttpClientForTesting(
        MockClient((request) {
          urls.add(request.url);
          final response = Completer<http.Response>();
          pending.add(response);
          return response.future;
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(gradeCenterProvider.notifier);
      final first = notifier.fetchGrades(scope: 'capstone');
      while (pending.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final second = notifier.selectCapstoneWorkspace('ongoing', '12', '12');
      while (pending.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      pending[1].complete(phaseResponse(urls[1]));
      await second;
      pending[0].complete(phaseResponse(urls[0]));
      await first;
      expect(
        container
            .read(gradeCenterProvider)
            .capstoneWorkspace['phase_semester_id'],
        14,
      );
    },
  );
}
