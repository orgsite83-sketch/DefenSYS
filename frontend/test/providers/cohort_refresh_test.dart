import 'dart:async';
import 'dart:convert';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/pit_lead_cohort_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetApiHttpClientForTesting);

  test('cohort background refresh retains history and filters', () async {
    final requests = <http.Request>[];
    setApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request);
        return http.Response('{"students":[{"id":1}],"counts":{"all":1}}', 200);
      }),
    );
    final container = ProviderContainer(overrides: authTestOverrides());
    addTearDown(container.dispose);
    final notifier = container.read(pitLeadCohortProvider.notifier);
    await notifier.fetchCohort(
      scope: 'history',
      search: 'Sofia',
      teamStatusFilter: 'on_team',
    );
    await notifier.fetchCohort();
    expect(requests, hasLength(2));
    expect(requests.last.url.queryParameters, {
      'scope': 'history',
      'search': 'Sofia',
      'team_status': 'on_team',
    });
    expect(container.read(pitLeadCohortProvider).scope, 'history');
  });

  for (final oldStatus in [200, 503]) {
    test(
      'late $oldStatus cohort response cannot overwrite a new search',
      () async {
        final responses = <Completer<http.Response>>[];
        setApiHttpClientForTesting(
          MockClient((request) {
            final response = Completer<http.Response>();
            responses.add(response);
            return response.future;
          }),
        );
        final container = ProviderContainer(overrides: authTestOverrides());
        addTearDown(container.dispose);
        final notifier = container.read(pitLeadCohortProvider.notifier);
        final old = notifier.fetchCohort(search: 'old');
        await Future<void>.delayed(Duration.zero);
        final latest = notifier.fetchCohort(search: 'new');
        await Future<void>.delayed(Duration.zero);
        responses[1].complete(
          http.Response(
            jsonEncode({
              'students': [
                {'id': 2},
              ],
            }),
            200,
          ),
        );
        await latest;
        responses[0].complete(
          http.Response(
            jsonEncode({
              'students': [
                {'id': 1},
              ],
            }),
            oldStatus,
          ),
        );
        await old;
        final state = container.read(pitLeadCohortProvider);
        expect(state.search, 'new');
        expect(state.students.single['id'], 2);
        expect(state.error, isNull);
        expect(state.isLoading, isFalse);
      },
    );
  }

  test('cohort response after session disposal is ignored', () async {
    final response = Completer<http.Response>();
    setApiHttpClientForTesting(MockClient((request) => response.future));
    final container = ProviderContainer(overrides: authTestOverrides());
    final loading = container
        .read(pitLeadCohortProvider.notifier)
        .fetchCohort();
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    response.complete(http.Response('{}', 200));
    await loading;
  });
}
