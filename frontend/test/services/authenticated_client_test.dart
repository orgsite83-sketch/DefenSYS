import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/session_expired.dart';

import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    resetApiHttpClientForTesting();
  });

  test(
    'concurrent identical GETs share a request but later reads stay fresh',
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
      final client = container.read(authenticatedHttpClientProvider);
      final uri = Uri.parse('http://example.com/api/teams/');
      final first = client.get(uri);
      final second = client.get(uri);
      await Future<void>.delayed(Duration.zero);
      expect(responses, hasLength(1));
      responses[0].complete(http.Response('first', 200));
      expect((await first).body, 'first');
      expect((await second).body, 'first');
      final third = client.get(uri);
      await Future<void>.delayed(Duration.zero);
      expect(responses, hasLength(2));
      responses[1].complete(http.Response('new', 200));
      expect((await third).body, 'new');
    },
  );

  test('GET sharing keeps filters and response headers separate', () async {
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
    final client = container.read(authenticatedHttpClientProvider);
    final uri = Uri.parse('http://example.com/api/teams/');
    final reads = [
      client.get(uri),
      client.get(uri.replace(queryParameters: {'scope': 'history'})),
      client.get(uri, headers: {'Accept': 'application/pdf'}),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(responses, hasLength(3));
    for (final response in responses) {
      response.complete(http.Response('ok', 200));
    }
    await Future.wait(reads);
  });

  test(
    'save separates reads started before, during, and after the write',
    () async {
      final reads = <Completer<http.Response>>[];
      final saved = Completer<http.Response>();
      setApiHttpClientForTesting(
        MockClient((request) {
          if (request.method == 'PATCH') return saved.future;
          final response = Completer<http.Response>();
          reads.add(response);
          return response.future;
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final client = container.read(authenticatedHttpClientProvider);
      final uri = Uri.parse('http://example.com/api/teams/');
      final before = client.get(uri);
      await Future<void>.delayed(Duration.zero);
      final write = client.patch(uri, body: '{}');
      final during = client.get(uri);
      await Future<void>.delayed(Duration.zero);
      expect(reads, hasLength(2));
      saved.complete(http.Response('{}', 200));
      await write;
      final after = client.get(uri);
      await Future<void>.delayed(Duration.zero);
      expect(reads, hasLength(3));
      reads[0].complete(http.Response('old', 200));
      await before;
      // Completing the old read must not evict the post-save shared request.
      final sharedAfter = client.get(uri);
      await Future<void>.delayed(Duration.zero);
      expect(reads, hasLength(3));
      reads[1].complete(http.Response('during', 200));
      reads[2].complete(http.Response('fresh', 200));
      await during;
      expect((await after).body, 'fresh');
      expect((await sharedAfter).body, 'fresh');
    },
  );

  test('failed reads are removed so a retry can succeed', () async {
    var calls = 0;
    setApiHttpClientForTesting(
      MockClient((request) async {
        if (++calls == 1) throw http.ClientException('offline');
        return http.Response('online', 200);
      }),
    );
    final container = ProviderContainer(overrides: authTestOverrides());
    addTearDown(container.dispose);
    final client = container.read(authenticatedHttpClientProvider);
    final uri = Uri.parse('http://example.com/api/teams/');
    await expectLater(client.get(uri), throwsA(isA<http.ClientException>()));
    expect((await client.get(uri)).body, 'online');
    expect(calls, 2);
  });

  test('401 after failed refresh throws SessionExpiredException', () async {
    SharedPreferences.setMockInitialValues({});
    var refreshCalls = 0;

    setApiHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('token/refresh/')) {
          refreshCalls++;
          return http.Response('{"detail":"invalid"}', 401);
        }
        if (request.url.path.endsWith('login/')) {
          return http.Response(
            '{"access":"a","refresh":"r","user":{"id":1,"role":"admin"}}',
            200,
          );
        }
        return http.Response('', 401);
      }),
    );

    final container = ProviderContainer(overrides: authTestOverrides());
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(authenticatedHttpClientProvider)
          .get(Uri.parse('http://example.com/api/dashboards/admin/')),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(refreshCalls, greaterThanOrEqualTo(0));
  });
}
