import 'dart:convert';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/rubric_engine_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetApiHttpClientForTesting);

  for (final scope in ['capstone', 'pit']) {
    test(
      '$scope copy sources ignore directory filters and keep directory state',
      () async {
        final requests = <http.Request>[];
        setApiHttpClientForTesting(
          MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode({
                'rubrics':
                    request.url.queryParameters['term_context'] == 'active'
                    ? []
                    : [
                        {
                          'id': 12,
                          'name': 'Historical rubric',
                          'semester_id': 2,
                          'is_locked': true,
                          'criteria': [
                            {'name': 'Historical criterion', 'weight': 100},
                          ],
                        },
                      ],
              }),
              200,
            );
          }),
        );
        final container = ProviderContainer(overrides: authTestOverrides());
        addTearDown(container.dispose);
        final notifier = container.read(rubricEngineProvider.notifier);
        await notifier.fetchRubrics(
          scope: scope,
          termContext: 'active',
          search: 'current search',
          status: 'draft',
          evaluationType: 'peer',
        );
        final before = container.read(rubricEngineProvider);
        final sources = await notifier.checkExistingRubrics(scope: scope);
        expect(sources.single['name'], 'Historical rubric');
        expect(
          (sources.single['criteria'] as List).single['name'],
          'Historical criterion',
        );
        expect(requests.last.url.queryParameters, {'scope': scope});
        expect(requests.last.method, 'GET');
        expect(container.read(rubricEngineProvider), same(before));
      },
    );
  }

  test(
    'copy source failures report an error instead of appearing empty',
    () async {
      setApiHttpClientForTesting(
        MockClient(
          (request) async =>
              http.Response('{"detail":"Source list unavailable"}', 503),
        ),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(rubricEngineProvider.notifier);
      await expectLater(
        notifier.checkExistingRubrics(scope: 'capstone'),
        throwsA(isA<Exception>()),
      );
    },
  );
}
