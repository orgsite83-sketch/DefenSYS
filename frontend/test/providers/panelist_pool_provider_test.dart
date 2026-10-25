import 'dart:async';
import 'dart:convert';
import 'package:defensys/services/admin/panelist_pool_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Auth extends AuthNotifier {
  @override
  AuthState build() => const AuthState(user: {'id': 1, 'role': 'faculty'});
  void switchUser(int id) =>
      state = state.copyWith(user: {'id': id, 'role': 'faculty'});
}

class _Client implements AuthenticatedHttpClient {
  final calls = <Uri>[];
  bool requested = false, failRefresh = false;
  Future<http.Response> Function(Uri)? read;
  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) async {
    calls.add(uri);
    if (read != null) return read!(uri);
    if (failRefresh) return http.Response('{}', 503);
    return http.Response(
      jsonEncode({
        'faculty': [
          {'id': 12, 'name': 'Lina Santos', 'is_panelist': false},
        ],
        'panelist_requests': requested
            ? [
                {'faculty_id': 12, 'status': 'pending'},
              ]
            : [],
      }),
      200,
    );
  }

  @override
  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    calls.add(uri);
    requested = true;
    return http.Response('{"request":{"id":42}}', 201);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Scheduler extends DefenseSchedulerNotifier {
  @override
  DefenseSchedulerState build() => const DefenseSchedulerState(
    generatedSlots: [
      {'team_id': 99},
    ],
    search: 'Retained search',
  );
}

void main() {
  test(
    'nomination loads independently and preserves the scheduling draft',
    () async {
      final client = _Client();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(_Auth.new),
          authenticatedHttpClientProvider.overrideWithValue(client),
          defenseSchedulerProvider.overrideWith(_Scheduler.new),
        ],
      );
      addTearDown(container.dispose);
      container.listen(panelistPoolProvider, (_, _) {});
      final before = container.read(defenseSchedulerProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(panelistPoolProvider).faculty.single['id'], 12);
      expect(
        await container
            .read(panelistPoolProvider.notifier)
            .nominate(12, 'Expertise'),
        isTrue,
      );
      expect(
        container.read(panelistPoolProvider).requests.single['status'],
        'pending',
      );
      expect(container.read(defenseSchedulerProvider), same(before));
      expect(
        client.calls.every((uri) => uri.path.startsWith('/api/users/')),
        isTrue,
      );
      client.failRefresh = true;
      expect(
        await container.read(panelistPoolProvider.notifier).nominate(13, ''),
        isTrue,
      );
      expect(
        container.read(panelistPoolProvider).requests.last['faculty_id'],
        13,
      );
      expect(container.read(panelistPoolProvider).error, isNotNull);
    },
  );

  test(
    'a previous login response cannot populate the current faculty pool',
    () async {
      final first = Completer<http.Response>();
      final client = _Client();
      var reads = 0;
      client.read = (_) async => ++reads == 1
          ? first.future
          : http.Response('{"faculty":[{"id":22}]}', 200);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(_Auth.new),
          authenticatedHttpClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);
      container.listen(panelistPoolProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      (container.read(authProvider.notifier) as _Auth).switchUser(2);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(panelistPoolProvider).faculty.single['id'], 22);
      first.complete(http.Response('{"faculty":[{"id":11}]}', 200));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(panelistPoolProvider).faculty.single['id'], 22);
    },
  );
}
