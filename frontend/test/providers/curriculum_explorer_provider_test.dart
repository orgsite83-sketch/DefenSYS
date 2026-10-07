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
