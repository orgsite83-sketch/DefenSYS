import 'dart:async';
import 'dart:convert';

import 'package:defensys/services/api_http.dart';
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
    final scope = ProviderContainer(overrides: authTestOverrides());
    addTearDown(scope.dispose);
    return scope;
  }

  test('compact preview keeps the loaded scheduler options', () async {
    setApiHttpClientForTesting(
      MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'teams': [
                {'id': 7, 'name': 'Ready team'},
              ],
              'defense_stages': [
                {'id': 3},
              ],
              'panelists': [
                {'id': 8},
              ],
              'can_schedule_capstone': true,
              'allowed_scopes': ['capstone'],
            }),
            200,
          );
        }
        expect(request.url.path, endsWith('/generate-plan/'));
        expect(request.url.queryParameters, {'response': 'compact'});
        expect(jsonDecode(request.body), {'scope': 'capstone'});
        return http.Response(
          jsonEncode({
            'slots': [
              {'team_id': 7, 'session_key': 'day-1'},
            ],
            'slot_count': 1,
            'unassigned_count': 0,
          }),
          200,
        );
      }),
    );
    final scope = container();
    final notifier = scope.read(defenseSchedulerProvider.notifier);
    await notifier.fetchSchedules();
    final before = scope.read(defenseSchedulerProvider);
    expect(await notifier.generatePlan({'scope': 'capstone'}), isTrue);
    final after = scope.read(defenseSchedulerProvider);
    expect(after.teams, before.teams);
    expect(after.defenseStages, before.defenseStages);
    expect(after.panelists, before.panelists);
    expect(after.canScheduleCapstone, isTrue);
    expect(after.allowedScopes, ['capstone']);
    expect(after.generatedSlots.single['team_id'], 7);
    expect(after.isSaving, isFalse);
  });

  testWidgets('a stalled preview clears busy state and can be retried', (
    tester,
  ) async {
    final stalled = Completer<http.Response>();
    var attempts = 0;
    setApiHttpClientForTesting(
      MockClient((request) {
        attempts++;
        if (attempts == 1) return stalled.future;
        return Future.value(
          http.Response(
            '{"slots":[{"team_id":9}],"slot_count":1,"unassigned_count":0}',
            200,
          ),
        );
      }),
    );
    final scope = container();
    final notifier = scope.read(defenseSchedulerProvider.notifier);
    final first = notifier.generatePlan({});
    await tester.pump();
    expect(scope.read(defenseSchedulerProvider).isSaving, isTrue);
    await tester.pump(DefenseSchedulerNotifier.planRequestTimeout);
    expect(await first, isFalse);
    expect(scope.read(defenseSchedulerProvider).isSaving, isFalse);
    expect(
      scope.read(defenseSchedulerProvider).error,
      contains('No schedules were saved'),
    );
    final retry = notifier.generatePlan({});
    await tester.pump();
    expect(await retry, isTrue);
    // A response arriving after timeout must not overwrite the newer preview.
    stalled.complete(http.Response('{"slots":[{"team_id":1}]}', 200));
    await tester.pump();
    expect(
      scope.read(defenseSchedulerProvider).generatedSlots.single['team_id'],
      9,
    );
    expect(scope.read(defenseSchedulerProvider).error, isNull);
  });

  test(
    'saving returns its acknowledgement while the board refresh is pending',
    () async {
      final refresh = Completer<http.Response>();
      var posts = 0;
      var gets = 0;
      setApiHttpClientForTesting(
        MockClient((request) {
          if (request.method == 'GET') {
            gets++;
            return refresh.future;
          }
          posts++;
          expect(request.url.path, endsWith('/confirm-plan/'));
          expect(request.url.queryParameters, {'response': 'compact'});
          return Future.value(
            http.Response(
              jsonEncode({
                'created_count': 16,
                'schedule_ids': List.generate(16, (i) => i + 1),
                'created_invitations': [
                  {'id': 5, 'code': 'guest-access'},
                ],
              }),
              201,
            ),
          );
        }),
      );
      final scope = container();
      final notifier = scope.read(defenseSchedulerProvider.notifier);
      expect(await notifier.confirmPlan({'slots': []}), isTrue);
      expect(scope.read(defenseSchedulerProvider).isSaving, isFalse);
      expect(scope.read(defenseSchedulerProvider).generatedSlots, isEmpty);
      expect(
        scope.read(defenseSchedulerProvider).createdInvitations.single['id'],
        5,
      );
      await Future<void>.delayed(Duration.zero);
      expect(posts, 1);
      expect(gets, 1);
      refresh.complete(http.Response('{"schedules":[{"id":1}]}', 200));
      await Future<void>.delayed(Duration.zero);
      expect(scope.read(defenseSchedulerProvider).schedules.single['id'], 1);
      // Refreshing the board cannot discard the access codes before the dialog opens.
      expect(
        scope.read(defenseSchedulerProvider).createdInvitations.single['id'],
        5,
      );
    },
  );

  test(
    'a failed board refresh does not change a successful save result',
    () async {
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response('{"detail":"Board unavailable"}', 503);
          }
          return http.Response(
            '{"created_count":1,"schedule_ids":[4],"created_invitations":[]}',
            201,
          );
        }),
      );
      final scope = container();
      final result = await scope
          .read(defenseSchedulerProvider.notifier)
          .confirmPlan({});
      await Future<void>.delayed(Duration.zero);
      expect(result, isTrue);
      expect(scope.read(defenseSchedulerProvider).isSaving, isFalse);
    },
  );

  testWidgets(
    'a save timeout preserves the draft and warns about an uncertain result',
    (tester) async {
      final pending = Completer<http.Response>();
      var posts = 0;
      setApiHttpClientForTesting(
        MockClient((request) {
          posts++;
          if (request.url.path.endsWith('/generate-plan/')) {
            return Future.value(
              http.Response('{"slots":[{"team_id":7}],"slot_count":1}', 200),
            );
          }
          return pending.future;
        }),
      );
      final scope = container();
      final notifier = scope.read(defenseSchedulerProvider.notifier);
      final preview = notifier.generatePlan({});
      await tester.pump();
      expect(await preview, isTrue);
      final saving = notifier.confirmPlan({});
      await tester.pump();
      expect(scope.read(defenseSchedulerProvider).isSaving, isTrue);
      await tester.pump(DefenseSchedulerNotifier.planSaveTimeout);
      expect(await saving, isFalse);
      expect(scope.read(defenseSchedulerProvider).isSaving, isFalse);
      expect(
        scope.read(defenseSchedulerProvider).generatedSlots.single['team_id'],
        7,
      );
      expect(
        scope.read(defenseSchedulerProvider).error,
        contains('may already be saved'),
      );
      expect(posts, 2);
      pending.complete(http.Response('{"created_count":1}', 201));
      await tester.pump();
      expect(
        scope.read(defenseSchedulerProvider).generatedSlots.single['team_id'],
        7,
      );
      expect(
        scope.read(defenseSchedulerProvider).error,
        contains('Check the Defense Board'),
      );
    },
  );

  test(
    'save validation errors remain visible, while connection failures warn before retry',
    () async {
      var attempts = 0;
      setApiHttpClientForTesting(
        MockClient((request) async {
          attempts++;
          if (attempts == 1) {
            return http.Response(
              '{"slots":["Team is no longer endorsed"]}',
              400,
            );
          }
          if (attempts == 2) {
            return http.Response(
              '{"detail":"Response failed after commit"}',
              500,
            );
          }
          throw http.ClientException('Connection lost');
        }),
      );
      final scope = container();
      final notifier = scope.read(defenseSchedulerProvider.notifier);
      expect(await notifier.confirmPlan({}), isFalse);
      expect(
        scope.read(defenseSchedulerProvider).error,
        'Team is no longer endorsed',
      );
      expect(await notifier.confirmPlan({}), isFalse);
      expect(
        scope.read(defenseSchedulerProvider).error,
        contains('may already be saved'),
      );
      expect(await notifier.confirmPlan({}), isFalse);
      expect(
        scope.read(defenseSchedulerProvider).error,
        contains('Check the Defense Board'),
      );
      expect(scope.read(defenseSchedulerProvider).isSaving, isFalse);
      expect(attempts, 3);
    },
  );
}
