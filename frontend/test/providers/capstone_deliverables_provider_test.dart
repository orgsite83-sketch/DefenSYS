import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/mock_http_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installDefaultMockHttp();
  });

  tearDown(() {
    resetApiHttpClientForTesting();
  });

  test('fetchDeliverables loads teams and stages', () async {
    final container = ProviderContainer(overrides: authTestOverrides());
    addTearDown(container.dispose);

    await container
        .read(capstoneDeliverablesProvider.notifier)
        .fetchDeliverables();

    final state = container.read(capstoneDeliverablesProvider);
    expect(state.isLoading, isFalse);
    expect(state.teams, hasLength(1));
    expect(state.stageOptions, contains('Concept Proposal'));
  });

  test(
    'batch filters persist on search and refresh and do not affect PIT',
    () async {
      final requests = <Uri>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'teams': [],
              'batch_options': [
                {'value': '12', 'label': '2nd Semester, A.Y. 2026-2027'},
              ],
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
      expect(requests.last.queryParameters['participation'], 'ongoing');
      await notifier.selectBatchFilters('12', 'completed');
      await notifier.fetchDeliverables(search: 'Eco');
      await notifier.fetchDeliverables();
      expect(requests.last.queryParameters, containsPair('batch_id', '12'));
      expect(
        requests.last.queryParameters,
        containsPair('participation', 'completed'),
      );
      expect(
        container.read(capstoneDeliverablesProvider).batchOptions,
        hasLength(1),
      );
      await notifier.fetchDeliverables(scope: 'pit');
      expect(requests.last.queryParameters.containsKey('batch_id'), isFalse);
      expect(
        requests.last.queryParameters.containsKey('participation'),
        isFalse,
      );
    },
  );

  test(
    'a late response from another batch cannot replace the selection',
    () async {
      final pending = <Completer<http.Response>>[];
      setApiHttpClientForTesting(
        MockClient((request) {
          final response = Completer<http.Response>();
          pending.add(response);
          return response.future;
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(capstoneDeliverablesProvider.notifier);
      final first = notifier.selectBatchFilters('1', 'ongoing');
      while (pending.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final second = notifier.selectBatchFilters('2', 'completed');
      while (pending.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      pending[1].complete(http.Response('{"teams":[{"id":2}]}', 200));
      await second;
      pending[0].complete(http.Response('{"teams":[{"id":1}]}', 200));
      await first;
      final state = container.read(capstoneDeliverablesProvider);
      expect(state.batchId, '2');
      expect(state.participation, 'completed');
      expect(state.teams.single['id'], 2);
    },
  );
}
