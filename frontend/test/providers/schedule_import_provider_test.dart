import 'dart:async';
import 'dart:convert';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/app/data_refresh_provider.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetApiHttpClientForTesting);

  ProviderContainer container() {
    final result = ProviderContainer(overrides: authTestOverrides());
    addTearDown(result.dispose);
    return result;
  }

  test(
    'faculty reference preview posts typed selections and verifies the returned revision',
    () async {
      setApiHttpClientForTesting(
        MockClient((request) async {
          expect(
            request.url.path.endsWith('/import-reference-preview/'),
            isTrue,
          );
          final payload = jsonDecode(request.body) as Map;
          expect(
            (payload['references'] as List).single['selected_account_id'],
            42,
          );
          return http.Response(
            jsonEncode({
              'revision': payload['revision'],
              'references': [
                {
                  'reference_id': 'file:0:chair',
                  'review_state': 'matched',
                  'account': {'id': 42},
                },
              ],
            }),
            200,
          );
        }),
      );
      final scope = container();
      final references = await scope
          .read(defenseSchedulerProvider.notifier)
          .previewImportReferences({
            'revision': 'r1',
            'scope': 'capstone',
            'semester_id': 1,
            'references': [
              {
                'reference_id': 'file:0:chair',
                'duty': 'chair',
                'text': 'Name in file',
                'selected_account_id': 42,
              },
            ],
          });
      expect(references['file:0:chair']!['account']['id'], 42);
    },
  );

  test(
    'conflict check requests only the lightweight appointments view',
    () async {
      setApiHttpClientForTesting(
        MockClient((request) async {
          expect(request.url.queryParameters, {'view': 'import-conflicts'});
          return http.Response('{"schedules":[{"id":7}]}', 200);
        }),
      );
      final scope = container();
      final rows = await scope
          .read(defenseSchedulerProvider.notifier)
          .fetchImportConflictSchedules();
      expect(rows.single['id'], 7);
    },
  );

  test(
    '16 saves use compact responses and finish while the single refresh is pending',
    () async {
      final requests = <http.Request>[];
      final refresh = Completer<http.Response>();
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') return refresh.future;
          expect(request.url.queryParameters, {'response': 'compact'});
          return http.Response(
            jsonEncode({'schedule_id': requests.length}),
            201,
          );
        }),
      );
      final scope = container();
      final progress = <int>[];
      final result = await scope
          .read(defenseSchedulerProvider.notifier)
          .importSchedules(
            List.generate(16, (i) => {'team_id': i + 1}),
            onProgress: (completed, total) {
              expect(total, 16);
              progress.add(completed);
            },
          );
      expect(result['created'], 16);
      expect(result['imported_indices'], List.generate(16, (i) => i));
      expect(progress, List.generate(17, (i) => i));
      expect(scope.read(defenseSchedulerProvider).isSaving, isFalse);
      expect(scope.read(dataRefreshProvider)[DataArea.defenseBoard], 1);
      await Future<void>.delayed(Duration.zero);
      expect(requests.where((r) => r.method == 'POST').length, 16);
      expect(requests.where((r) => r.method == 'GET').length, 1);
      refresh.complete(http.Response('{"detail":"Board unavailable"}', 503));
      await Future<void>.delayed(Duration.zero);
      expect(result['created'], 16);
      expect(result['errors'], isEmpty);
    },
  );

  test(
    'a lost response stops later writes and preserves confirmed successes',
    () async {
      var writes = 0;
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response('{"schedules":[]}', 200);
          }
          writes++;
          if (writes == 2) throw http.ClientException('Connection lost');
          return http.Response('{"schedule_id":1}', 201);
        }),
      );
      final result = await container()
          .read(defenseSchedulerProvider.notifier)
          .importSchedules([
            {'team_id': 1},
            {'team_id': 2},
            {'team_id': 3},
          ]);
      expect(writes, 2);
      expect(result['created'], 1);
      expect(result['imported_indices'], [0]);
      expect(
        (result['errors'] as List).single,
        contains('may already be saved'),
      );
    },
  );

  testWidgets('stalled preflight and save requests time out', (tester) async {
    setApiHttpClientForTesting(
      MockClient((request) {
        if (request.method == 'GET' &&
            !request.url.queryParameters.containsKey('view')) {
          return Future.value(http.Response('{"schedules":[]}', 200));
        }
        return Completer<http.Response>().future;
      }),
    );
    final scope = container();
    final notifier = scope.read(defenseSchedulerProvider.notifier);
    final check = expectLater(
      notifier.fetchImportConflictSchedules(),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump();
    await tester.pump(DefenseSchedulerNotifier.importRequestTimeout);
    await check;

    final saving = notifier.importSchedules([
      {'team_id': 1},
      {'team_id': 2},
    ]);
    await tester.pump();
    await tester.pump(DefenseSchedulerNotifier.importRequestTimeout);
    final result = await saving;
    expect(result['created'], 0);
    expect((result['errors'] as List).single, contains('too long to respond'));
    expect(scope.read(defenseSchedulerProvider).isSaving, isFalse);
    await tester.pump();
  });
}
