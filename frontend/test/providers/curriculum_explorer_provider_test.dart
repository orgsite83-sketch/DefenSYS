import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:defensys/services/academic/curriculum_explorer_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:defensys/services/app/data_refresh_provider.dart';

class _Client extends Mock implements AuthenticatedHttpClient {}

void main() {
  test(
    'expired bundles stay local for chart selection and revalidate on return',
    () async {
      registerFallbackValue(Uri.parse('http://localhost'));
      final client = _Client(), refresh = Completer<http.Response>();
      var calls = 0;
      when(() => client.get(any())).thenAnswer((_) async {
        calls++;
        if (calls == 2) return refresh.future;
        return http.Response(
          jsonEncode({
            'academic_year': '2026-2027',
            'context': 'stage:1',
            'assessment_bundles': {
              'stage:1': {
                'panel': {
                  'criteria': [
                    {'id': 'problem', 'score': 83},
                  ],
                },
              },
            },
          }),
          200,
        );
      });
      final container = ProviderContainer(
        overrides: [
          authenticatedHttpClientProvider.overrideWithValue(client),
          curriculumExplorerProvider.overrideWith(
            () => CurriculumExplorerNotifier(freshness: Duration.zero),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(curriculumExplorerProvider.notifier);
      const query = CurriculumExplorerQuery(view: 'year', year: '2026-2027');
      await notifier.fetch(query);
      await notifier.fetch(
        query.copyWith(view: 'assessment', context: 'stage:1'),
        selection: true,
      );
      expect(calls, 1);
      expect(
        explorerRows(
          container.read(curriculumExplorerProvider).data['criteria'],
        ).single['score'],
        83,
      );
      final returning = notifier.fetch(
        container.read(curriculumExplorerProvider).query,
      );
      expect(calls, 2);
      expect(container.read(curriculumExplorerProvider).isRefreshing, true);
      expect(container.read(curriculumExplorerProvider).isLoading, false);
      expect(container.read(curriculumExplorerProvider).data, isNotEmpty);
      refresh.complete(http.Response('{"detail":"Unavailable"}', 503));
      await returning;
      expect(container.read(curriculumExplorerProvider).data, isNotEmpty);
      expect(
        container.read(curriculumExplorerProvider).error,
        contains('Unavailable'),
      );
    },
  );

  test(
    'initial fetch selects its year in one response and coalesces duplicate requests',
    () async {
      registerFallbackValue(Uri.parse('http://localhost'));
      final client = _Client();
      final pending = Completer<http.Response>();
      var calls = 0;
      when(() => client.get(any())).thenAnswer((invocation) {
        final uri = invocation.positionalArguments[0] as Uri;
        expect(uri.queryParameters['initial'], 'true');
        calls++;
        return pending.future;
      });
      final container = ProviderContainer(
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(curriculumExplorerProvider.notifier);
      const query = CurriculumExplorerQuery(
        scope: 'pit',
        yearLevel: '2',
        initial: true,
      );
      final first = notifier.fetch(query);
      final duplicate = notifier.fetch(query);
      expect(calls, 1);
      pending.complete(
        http.Response('{"academic_year":"2026-2027","context":"event:7"}', 200),
      );
      await Future.wait([first, duplicate]);
      final result = container.read(curriculumExplorerProvider).query;
      expect(result.year, '2026-2027');
      expect(result.context, 'event:7');
      expect(result.initial, isFalse);
      expect(result.toParams().containsKey('initial'), isFalse);
    },
  );
  test(
    'workspace invalidation discards cached data and pending responses',
    () async {
      registerFallbackValue(Uri.parse('http://localhost'));
      final client = _Client();
      final pending = Completer<http.Response>();
      var calls = 0;
      when(() => client.get(any())).thenAnswer((_) async {
        calls++;
        if (calls == 2) return pending.future;
        return http.Response(
          jsonEncode({'scope': calls == 1 ? 'capstone' : 'pit'}),
          200,
        );
      });
      final container = ProviderContainer(
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        curriculumExplorerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      final notifier = container.read(curriculumExplorerProvider.notifier);
      await notifier.fetch(const CurriculumExplorerQuery());
      final old = notifier.fetch(const CurriculumExplorerQuery(), force: true);
      container.invalidate(curriculumExplorerProvider);
      expect(container.read(curriculumExplorerProvider).data, isEmpty);
      await container
          .read(curriculumExplorerProvider.notifier)
          .fetch(const CurriculumExplorerQuery(scope: 'pit', yearLevel: '2'));
      pending.complete(http.Response(jsonEncode({'scope': 'capstone'}), 200));
      await old;
      expect(container.read(curriculumExplorerProvider).data['scope'], 'pit');
      expect(container.read(curriculumExplorerProvider).query.yearLevel, '2');
    },
  );

  test('switching year clears the previous cohort while waiting', () async {
    registerFallbackValue(Uri.parse('http://localhost'));
    final client = _Client();
    final pending = Completer<http.Response>();
    when(() => client.get(any())).thenAnswer((invocation) async {
      final uri = invocation.positionalArguments[0] as Uri;
      return uri.queryParameters['year_level'] == '2'
          ? pending.future
          : http.Response('{"projects_count": 12}', 200);
    });
    final container = ProviderContainer(
      overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(curriculumExplorerProvider.notifier);
    await notifier.fetch(const CurriculumExplorerQuery(scope: 'pit'));
    final next = notifier.fetch(
      const CurriculumExplorerQuery(scope: 'pit', yearLevel: '2'),
    );
    expect(container.read(curriculumExplorerProvider).data, isEmpty);
    pending.complete(http.Response('{"projects_count": 3}', 200));
    await next;
    expect(
      container.read(curriculumExplorerProvider).data['projects_count'],
      3,
    );
  });
  test(
    'performance selection is sent to the API and project overview clears it',
    () async {
      registerFallbackValue(Uri.parse('http://localhost'));
      final client = _Client();
      final requests = <Uri>[];
      when(() => client.get(any())).thenAnswer((invocation) async {
        requests.add(invocation.positionalArguments[0] as Uri);
        return http.Response(jsonEncode({'context': 'stage:1'}), 200);
      });
      final container = ProviderContainer(
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(curriculumExplorerProvider.notifier);
      await notifier.fetch(
        const CurriculumExplorerQuery(
          year: '2026-2027',
          context: 'stage:1',
          subject: 'student:7',
        ),
      );
      await notifier.detail('1:1', allAssessments: true);
      await notifier.detail('1:1');
      expect(requests[0].queryParameters['subject'], 'student:7');
      expect(requests[1].queryParameters.containsKey('subject'), isFalse);
      expect(requests[1].queryParameters.containsKey('context'), isFalse);
      expect(requests[2].queryParameters['subject'], 'student:7');
    },
  );

  test(
    'cached bundles select assessment and evaluator without another request',
    () async {
      registerFallbackValue(Uri.parse('http://localhost'));
      final client = _Client();
      var calls = 0;
      final data = <String, dynamic>{
        'academic_year': '2026-2027',
        'year_from': '2026-2027',
        'year_to': '2026-2027',
        'context': 'stage:1',
        'evaluation_type': 'panel',
        'performance': {
          'contexts': [
            {'id': 'stage:1'},
            {'id': 'stage:2'},
          ],
        },
        'assessment_bundles': {
          'stage:1': {
            'panel': {
              'criteria': [
                {'id': 'proposal', 'name': 'Problem relevance'},
              ],
            },
          },
          'stage:2': {
            'panel': {
              'criteria': [
                {'id': 'final-panel', 'name': 'Implementation'},
              ],
            },
            'peer': {
              'criteria': [
                {'id': 'final-peer', 'name': 'Contribution'},
              ],
            },
          },
        },
      };
      when(() => client.get(any())).thenAnswer((_) async {
        calls++;
        return http.Response(jsonEncode(data), 200);
      });
      final container = ProviderContainer(
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(curriculumExplorerProvider.notifier);
      const query = CurriculumExplorerQuery(view: 'year', year: '2026-2027');
      await notifier.fetch(query);
      await notifier.fetch(
        query.copyWith(view: 'assessment', context: 'stage:2', role: 'peer'),
      );
      var result = container.read(curriculumExplorerProvider);
      expect(calls, 1);
      expect(result.query.context, 'stage:2');
      expect(result.query.role, 'peer');
      expect(
        explorerRows(result.data['criteria']).single['name'],
        'Contribution',
      );
      expect(result.isLoading, false);
      await notifier.fetch(
        query.copyWith(view: 'assessment', context: 'stage:1'),
      );
      result = container.read(curriculumExplorerProvider);
      expect(calls, 1);
      expect(
        explorerRows(result.data['criteria']).single['name'],
        'Problem relevance',
      );
    },
  );

  test(
    'refresh failures retain results and a retry bypasses the fresh cache',
    () async {
      registerFallbackValue(Uri.parse('http://localhost'));
      final client = _Client();
      var calls = 0;
      when(() => client.get(any())).thenAnswer((_) async {
        calls++;
        return calls == 2
            ? http.Response('{"detail":"Temporarily unavailable"}', 503)
            : http.Response('{"projects_count":7}', 200);
      });
      final container = ProviderContainer(
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(curriculumExplorerProvider.notifier);
      const query = CurriculumExplorerQuery();
      await notifier.fetch(query);
      await notifier.fetch(query);
      expect(calls, 1);
      await notifier.fetch(query, force: true);
      expect(
        container.read(curriculumExplorerProvider).data['projects_count'],
        7,
      );
      expect(container.read(curriculumExplorerProvider).error, isNotNull);
      await notifier.fetch(query, force: true);
      expect(calls, 3);
      expect(container.read(curriculumExplorerProvider).error, isNull);
    },
  );

  test(
    'project year selection keeps the complete range and partial tags',
    () async {
      registerFallbackValue(Uri.parse('http://localhost'));
      final client = _Client();
      var calls = 0;
      when(() => client.get(any())).thenAnswer((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'range_years': ['2025-2026', '2026-2027'],
            'project_collection': [
              {
                'id': 'old',
                'academic_year': '2025-2026',
                'category': 'Unclassified',
                'domain': 'Education',
                'technologies': ['Flutter'],
              },
              {'id': 'new', 'academic_year': '2026-2027'},
            ],
          }),
          200,
        );
      });
      final container = ProviderContainer(
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(curriculumExplorerProvider.notifier);
      const query = CurriculumExplorerQuery(view: 'projects');
      await notifier.fetch(query);
      expect(
        container.read(curriculumExplorerProvider).query.year,
        '2026-2027',
      );
      await notifier.fetch(query.copyWith(year: '2025-2026'));
      final result = container.read(curriculumExplorerProvider);
      expect(calls, 1);
      expect(explorerRows(result.data['project_collection']), hasLength(2));
      expect(
        explorerRows(result.data['projects']).single['domain'],
        'Education',
      );
      expect(explorerRows(result.data['projects']).single['technologies'], [
        'Flutter',
      ]);
    },
  );

  test(
    'a related save invalidates cached results and revalidates the current view',
    () async {
      registerFallbackValue(Uri.parse('http://localhost'));
      final client = _Client();
      var calls = 0;
      when(() => client.get(any())).thenAnswer((_) async {
        calls++;
        return http.Response(jsonEncode({'projects_count': calls}), 200);
      });
      final container = ProviderContainer(
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(curriculumExplorerProvider, (_, _) {});
      addTearDown(sub.close);
      final notifier = container.read(curriculumExplorerProvider.notifier);
      await notifier.fetch(const CurriculumExplorerQuery());
      container.read(dataRefreshProvider.notifier).markChanged([
        DataArea.deliverables,
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      expect(
        container.read(curriculumExplorerProvider).data['projects_count'],
        2,
      );
    },
  );

  test(
    'A to B to A coalesces the first pending read and commits the latest selection',
    () async {
      registerFallbackValue(Uri.parse('http://localhost'));
      final client = _Client(),
          a = Completer<http.Response>(),
          b = Completer<http.Response>();
      var calls = 0;
      when(() => client.get(any())).thenAnswer((invocation) {
        calls++;
        return (invocation.positionalArguments[0] as Uri)
                    .queryParameters['scope'] ==
                'pit'
            ? b.future
            : a.future;
      });
      final container = ProviderContainer(
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(curriculumExplorerProvider.notifier);
      final first = notifier.fetch(const CurriculumExplorerQuery());
      final second = notifier.fetch(
        const CurriculumExplorerQuery(scope: 'pit'),
      );
      final third = notifier.fetch(const CurriculumExplorerQuery());
      expect(calls, 2);
      a.complete(http.Response('{"projects_count":7}', 200));
      await Future.wait([first, third]);
      b.complete(http.Response('{"projects_count":9}', 200));
      await second;
      expect(
        container.read(curriculumExplorerProvider).query.scope,
        'capstone',
      );
      expect(
        container.read(curriculumExplorerProvider).data['projects_count'],
        7,
      );
    },
  );

  test(
    'permission denial clears completed and pending protected results',
    () async {
      registerFallbackValue(Uri.parse('http://localhost'));
      final client = _Client(), old = Completer<http.Response>();
      var calls = 0;
      when(() => client.get(any())).thenAnswer((_) async {
        calls++;
        if (calls == 1) return old.future;
        if (calls == 2) return http.Response('{"detail":"Forbidden"}', 403);
        return http.Response('{"projects_count":1}', 200);
      });
      final container = ProviderContainer(
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(curriculumExplorerProvider.notifier);
      final first = notifier.fetch(const CurriculumExplorerQuery());
      await notifier.fetch(const CurriculumExplorerQuery(scope: 'pit'));
      expect(container.read(curriculumExplorerProvider).data, isEmpty);
      expect(
        container.read(curriculumExplorerProvider).error,
        contains('Forbidden'),
      );
      old.complete(http.Response('{"projects_count":99}', 200));
      await first;
      await notifier.fetch(const CurriculumExplorerQuery());
      expect(calls, 3);
      expect(
        container.read(curriculumExplorerProvider).data['projects_count'],
        1,
      );
    },
  );

  test(
    'late Capstone response cannot replace the selected PIT workflow',
    () async {
      registerFallbackValue(Uri.parse('http://localhost'));
      final client = _Client(),
          capstone = Completer<http.Response>(),
          pit = Completer<http.Response>();
      when(() => client.get(any())).thenAnswer((invocation) {
        final uri = invocation.positionalArguments[0] as Uri;
        expect(uri.path, endsWith('/curriculum-analytics/explorer/'));
        return uri.queryParameters['scope'] == 'pit'
            ? pit.future
            : capstone.future;
      });
      final container = ProviderContainer(
        overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(curriculumExplorerProvider.notifier);
      final first = notifier.fetch(const CurriculumExplorerQuery());
      final second = notifier.fetch(
        const CurriculumExplorerQuery(scope: 'pit', yearLevel: '3'),
      );
      pit.complete(
        http.Response(jsonEncode({'scope': 'pit', 'projects_count': 7}), 200),
      );
      await second;
      capstone.complete(
        http.Response(
          jsonEncode({'scope': 'capstone', 'projects_count': 18}),
          200,
        ),
      );
      await first;
      final state = container.read(curriculumExplorerProvider);
      expect(state.query.scope, 'pit');
      expect(state.query.yearLevel, '3');
      expect(state.data['projects_count'], 7);
      expect(state.isLoading, isFalse);
    },
  );
}
