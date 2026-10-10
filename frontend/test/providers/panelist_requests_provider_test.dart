import 'dart:async';
import 'dart:convert';

import 'package:defensys/services/admin/panelist_requests_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Auth extends AuthNotifier {
  @override
  AuthState build() =>
      const AuthState(isRestoring: false, user: {'id': 1, 'role': 'admin'});
  void changeUser(int id) =>
      state = state.copyWith(user: {'id': id, 'role': 'admin'});
}

class _Client implements AuthenticatedHttpClient {
  late Future<http.Response> Function(Uri) onGet;
  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) =>
      onGet(uri);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

http.Response _response(List<int> ids, {String? next}) => http.Response(
  jsonEncode({
    'panelist_requests': [
      for (final id in ids) {'id': id, 'faculty_name': 'Faculty $id'},
    ],
    'count': 3,
    'pending_count': 2,
    'reviewed_count': 1,
    'next': next,
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Client client;
  late ProviderContainer container;
  setUp(() {
    client = _Client()..onGet = (_) async => _response([1, 2]);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_Auth.new),
        authenticatedHttpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
  });
  Future<void> watch(String status) async {
    container.listen(panelistRequestsProvider(status), (_, _) {});
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'pending and reviewed queues keep their selection and data separate',
    () async {
      final requests = <Uri>[];
      client.onGet = (uri) async {
        requests.add(uri);
        return _response(
          uri.queryParameters['status'] == 'pending' ? [1, 2] : [3],
        );
      };
      await watch('pending');
      await watch('reviewed');
      expect(
        container
            .read(panelistRequestsProvider('pending'))
            .items
            .map((i) => i['id']),
        [1, 2],
      );
      expect(
        container.read(panelistRequestsProvider('reviewed')).items.single['id'],
        3,
      );
      expect(requests.map((u) => u.queryParameters['status']), [
        'pending',
        'reviewed',
      ]);
      expect(container.read(panelistRequestsProvider('pending')).pending, 2);
      expect(container.read(panelistRequestsProvider('reviewed')).reviewed, 1);
    },
  );

  test(
    'pagination deduplicates rows and constructs the next request locally',
    () async {
      client.onGet = (_) async =>
          _response([1, 2], next: 'https://untrusted.example/api?page=2');
      await watch('reviewed');
      Uri? requested;
      client.onGet = (uri) async {
        requested = uri;
        return _response([2, 3]);
      };
      await container
          .read(panelistRequestsProvider('reviewed').notifier)
          .fetch(more: true);
      expect(requested!.path, '/api/users/panelist-requests/');
      expect(requested!.host, isNot('untrusted.example'));
      expect(requested!.queryParameters, {'status': 'reviewed', 'page': '2'});
      expect(
        container
            .read(panelistRequestsProvider('reviewed'))
            .items
            .map((i) => i['id']),
        [1, 2, 3],
      );
      expect(
        container.read(panelistRequestsProvider('reviewed')).nextPage,
        isNull,
      );
    },
  );

  test('failed refresh preserves existing rows and can be retried', () async {
    await watch('pending');
    final notifier = container.read(
      panelistRequestsProvider('pending').notifier,
    );
    client.onGet = (_) async => http.Response('{}', 503);
    await notifier.fetch();
    expect(
      container.read(panelistRequestsProvider('pending')).items,
      hasLength(2),
    );
    expect(
      container.read(panelistRequestsProvider('pending')).error,
      isNotNull,
    );
    client.onGet = (_) async => _response([3]);
    await notifier.fetch();
    expect(container.read(panelistRequestsProvider('pending')).error, isNull);
    expect(
      container.read(panelistRequestsProvider('pending')).items.single['id'],
      3,
    );
  });

  test('a slower search response cannot replace the current search', () async {
    await watch('pending');
    final stale = Completer<http.Response>();
    client.onGet = (uri) => uri.queryParameters['search'] == 'old'
        ? stale.future
        : Future.value(_response([3]));
    final notifier = container.read(
      panelistRequestsProvider('pending').notifier,
    );
    final earlier = notifier.fetch(search: 'old');
    await notifier.fetch(search: 'current');
    stale.complete(_response([1]));
    await earlier;
    expect(
      container.read(panelistRequestsProvider('pending')).search,
      'current',
    );
    expect(
      container.read(panelistRequestsProvider('pending')).items.single['id'],
      3,
    );
  });

  test(
    'changing accounts clears the queue and ignores a response from the old login',
    () async {
      final stale = Completer<http.Response>();
      client.onGet = (_) => stale.future;
      await watch('pending');
      client.onGet = (_) async => _response([3]);
      (container.read(authProvider.notifier) as _Auth).changeUser(2);
      await Future<void>.delayed(Duration.zero);
      stale.complete(_response([1, 2]));
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(panelistRequestsProvider('pending')).items.single['id'],
        3,
      );
    },
  );
}
