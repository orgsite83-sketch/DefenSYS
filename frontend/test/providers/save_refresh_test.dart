import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:defensys/navigation/web_section_navigation.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/app/data_refresh_provider.dart';
import 'package:defensys/services/defense/defense_scheduler_provider.dart';
import 'package:defensys/services/defense/defense_stages_provider.dart';
import 'package:defensys/services/grading/rubric_engine_provider.dart';

import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetApiHttpClientForTesting);

  test(
    'published rubric appears on scheduler return without loading hidden pages',
    () async {
      var published = false;
      final requests = <http.Request>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/publish/')) {
            published = true;
            return http.Response('{}', 200);
          }
          if (request.url.path.contains('/grading/rubrics')) {
            return http.Response(jsonEncode({'rubrics': []}), 200);
          }
          if (request.url.path.contains('/defense/schedules')) {
            return http.Response(
              jsonEncode({
                'schedules': [],
                'rubrics': [
                  if (published) {'id': 7, 'name': 'New panel rubric'},
                ],
              }),
              200,
            );
          }
          throw StateError('Unexpected hidden-page request: ${request.url}');
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final gate = WebSectionRefreshGate(now: () => DateTime(2026));
      expect(gate.activate('scheduler'), isFalse);
      await container
          .read(defenseSchedulerProvider.notifier)
          .fetchSchedules(
            scope: 'capstone',
            search: 'my team',
            status: 'scheduled',
          );
      expect(container.read(defenseSchedulerProvider).rubrics, isEmpty);
      gate.activate('rubrics');

      expect(
        await container.read(rubricEngineProvider.notifier).publishRubric(7),
        isTrue,
      );
      final revision = container.read(dataRefreshProvider)[DataArea.scheduler]!;
      expect(gate.activate('scheduler', revision: revision), isTrue);
      await container.read(defenseSchedulerProvider.notifier).fetchSchedules();

      final state = container.read(defenseSchedulerProvider);
      expect(state.rubrics.single['name'], 'New panel rubric');
      expect(state.scope, 'capstone');
      expect(state.search, 'my team');
      expect(state.status, 'scheduled');
      expect(requests.length, 4);
      expect(gate.activate('scheduler', revision: revision), isFalse);
    },
  );

  test('failed rubric save does not mark dependencies as changed', () async {
    setApiHttpClientForTesting(
      MockClient(
        (_) async => http.Response('{"detail":"Invalid rubric"}', 400),
      ),
    );
    final container = ProviderContainer(overrides: authTestOverrides());
    addTearDown(container.dispose);
    expect(
      await container.read(rubricEngineProvider.notifier).publishRubric(7),
      isFalse,
    );
    expect(container.read(dataRefreshProvider), isEmpty);
  });

  test(
    'stage update uses its response and does not reload hidden pages',
    () async {
      final requests = <http.Request>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'stages': [
                {'id': 1, 'label': 'Updated stage'},
              ],
              'active_stages': [
                {'id': 1, 'label': 'Updated stage'},
              ],
              'counts': {'total': 1},
            }),
            200,
          );
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      expect(
        await container.read(defenseStagesProvider.notifier).updateStage(1, {
          'label': 'Updated stage',
        }),
        isTrue,
      );
      expect(requests.single.method, 'PATCH');
      expect(
        container.read(defenseStagesProvider).stages.single['label'],
        'Updated stage',
      );
      expect(container.read(dataRefreshProvider)[DataArea.scheduler], 1);
    },
  );

  test(
    'duplicate scheduler reads share a request and old results cannot replace new rubrics',
    () async {
      final responses = <Completer<http.Response>>[];
      setApiHttpClientForTesting(
        MockClient((_) {
          final response = Completer<http.Response>();
          responses.add(response);
          return response.future;
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(defenseSchedulerProvider.notifier);
      final first = notifier.fetchSchedules();
      final duplicate = notifier.fetchSchedules();
      await Future<void>.delayed(Duration.zero);
      expect(responses.length, 1);
      container.read(dataRefreshProvider.notifier).markChanged([
        DataArea.scheduler,
      ]);
      final latest = notifier.fetchSchedules();
      await Future<void>.delayed(Duration.zero);
      expect(responses.length, 2);
      responses[1].complete(
        http.Response('{"rubrics":[{"id":7,"name":"New rubric"}]}', 200),
      );
      await latest;
      responses[0].complete(http.Response('{"rubrics":[]}', 200));
      await Future.wait([first, duplicate]);
      expect(container.read(defenseSchedulerProvider).rubrics.single['id'], 7);
    },
  );
}
