import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/session_expired.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/app/data_refresh_provider.dart';

import '../helpers/auth_test_overrides.dart';

class _SwitchableAuth extends TestAuthNotifier {
  void change(AuthState next) => state = next;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    resetApiHttpClientForTesting();
  });

  test(
    'completed file downloads are reused; API metadata still stays fresh',
    () async {
      var reads = 0;
      setApiHttpClientForTesting(
        MockClient((_) async => http.Response('${++reads}', 200)),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final client = container.read(authenticatedHttpClientProvider);
      expect(await client.fetchAuthenticatedFile('/media/paper.pdf'), [49]);
      expect(await client.fetchAuthenticatedFile('/media/paper.pdf'), [49]);
      expect(reads, 1);
      // Shelf progress is unrelated to file contents and must not evict bytes.
      await client.post(Uri.parse('http://example.com/api/repository/shelf/'));
      expect(await client.fetchAuthenticatedFile('/media/paper.pdf'), [49]);
      expect(reads, 2);
      container.read(dataRefreshProvider.notifier).markChanged([
        DataArea.deliverables,
      ]);
      expect(await client.fetchAuthenticatedFile('/media/paper.pdf'), [51]);
      expect(reads, 3);
    },
  );

  test(
    'file cache clears on account changes, logout and explicit refresh',
    () async {
      var reads = 0;
      setApiHttpClientForTesting(
        MockClient((_) async => http.Response('${++reads}', 200)),
      );
      final container = ProviderContainer(
        overrides: [authProvider.overrideWith(_SwitchableAuth.new)],
      );
      addTearDown(container.dispose);
      final client = container.read(authenticatedHttpClientProvider);
      final auth = container.read(authProvider.notifier) as _SwitchableAuth;
      await client.fetchAuthenticatedFile('/media/paper.pdf');
      auth.change(
        testAuthState.copyWith(
          token: testAccessToken.replaceFirst('header', 'refreshed'),
        ),
      );
      expect(await client.fetchAuthenticatedFile('/media/paper.pdf'), [49]);
      expect(reads, 1);
      auth.change(
        AuthState(
          isRestoring: false,
          token: testAccessToken,
          user: const {'id': 2, 'role': 'student'},
        ),
      );
      expect(await client.fetchAuthenticatedFile('/media/paper.pdf'), [50]);
      auth.change(const AuthState(isRestoring: false));
      auth.change(testAuthState);
      expect(await client.fetchAuthenticatedFile('/media/paper.pdf'), [51]);
      client.clearFileCache();
      expect(await client.fetchAuthenticatedFile('/media/paper.pdf'), [52]);
    },
  );

  test(
    'an invalidated pending download cannot repopulate the file cache',
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
      final client = container.read(authenticatedHttpClientProvider);
      final old = client.fetchAuthenticatedFile('/media/paper.pdf');
      await Future<void>.delayed(Duration.zero);
      container.read(dataRefreshProvider.notifier).markChanged([
        DataArea.repository,
      ]);
      responses[0].complete(http.Response('old', 200));
      await old;
      final current = client.fetchAuthenticatedFile('/media/paper.pdf');
      await Future<void>.delayed(Duration.zero);
      expect(responses, hasLength(2));
      responses[1].complete(http.Response('new', 200));
      await current;
      expect(await client.fetchAuthenticatedFile('/media/paper.pdf'), [
        110,
        101,
        119,
      ]);
      expect(responses, hasLength(2));
    },
  );

  test('failed file downloads are retried rather than cached', () async {
    var calls = 0;
    setApiHttpClientForTesting(
      MockClient((_) async {
        return ++calls == 1
            ? http.Response('unavailable', 503)
            : http.Response('ok', 200);
      }),
    );
    final container = ProviderContainer(overrides: authTestOverrides());
    addTearDown(container.dispose);
    final client = container.read(authenticatedHttpClientProvider);
    await expectLater(
      client.fetchAuthenticatedFile('/media/paper.pdf'),
      throwsException,
    );
    expect(await client.fetchAuthenticatedFile('/media/paper.pdf'), [111, 107]);
    expect(await client.fetchAuthenticatedFile('/media/paper.pdf'), [111, 107]);
    expect(calls, 2);
  });

  test('guest file openings continue to check server-scoped access', () async {
    var calls = 0;
    setApiHttpClientForTesting(MockClient((_) async {
      calls++;
      return http.Response('ok', 200);
    }));
    final container = ProviderContainer(overrides: [authProvider.overrideWith(_SwitchableAuth.new)]);
    addTearDown(container.dispose);
    (container.read(authProvider.notifier) as _SwitchableAuth).change(AuthState(
      isRestoring: false, token: testAccessToken,
      user: const {'id': 7, 'role': 'guest_panelist'},
    ));
    final client = container.read(authenticatedHttpClientProvider);
    await client.fetchAuthenticatedFile('/media/paper.pdf');
    await client.fetchAuthenticatedFile('/media/paper.pdf');
    expect(calls, 2);
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

  test(
    'discarding a stalled read allows retry without evicting the new read',
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
      final uri = Uri.parse(
        'http://example.com/api/grading/grades/group-settings/',
      );
      final stalled = client.get(uri);
      await Future<void>.delayed(Duration.zero);
      client.discardPendingReads();
      final retry = client.get(uri);
      await Future<void>.delayed(Duration.zero);
      expect(responses, hasLength(2));
      responses[0].complete(http.Response('late', 200));
      await stalled;
      final sharedRetry = client.get(uri);
      await Future<void>.delayed(Duration.zero);
      expect(responses, hasLength(2));
      responses[1].complete(http.Response('current', 200));
      expect((await retry).body, 'current');
      expect((await sharedRetry).body, 'current');
    },
  );

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
