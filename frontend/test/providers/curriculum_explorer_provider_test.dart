import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:defensys/services/academic/curriculum_explorer_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';

class _Client extends Mock implements AuthenticatedHttpClient {}

void main() {
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
      final old = notifier.fetch(const CurriculumExplorerQuery());
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
