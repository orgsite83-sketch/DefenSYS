import 'dart:async';
import 'dart:convert';

import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class _Auth extends AuthNotifier {
  @override
  AuthState build() =>
      const AuthState(isRestoring: false, user: {'id': 1, 'role': 'faculty'});
  void changeUser(int id) =>
      state = state.copyWith(user: {'id': id, 'role': 'faculty'});
}

class _Client implements AuthenticatedHttpClient {
  late Future<http.Response> Function(Uri) onGet;
  late Future<http.Response> Function(Uri) onPost;
  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) =>
      onGet(uri);
  @override
  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) => onPost(uri);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

http.Response _response({
  int unread = 25,
  int total = 30,
  List<Map<String, dynamic>>? items,
  String? next,
}) => http.Response(
  jsonEncode({
    'notifications':
        items ??
        [
          {'id': 1, 'title': 'Defense update', 'is_read': false},
        ],
    'unread_count': unread,
    'total_count': total,
    'next': next,
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Client client;
  late ProviderContainer container;
  setUp(() {
    client = _Client()
      ..onGet = (_) async {
        return _response();
      }
      ..onPost = (_) async {
        return http.Response('{"unread_count":24}', 200);
      };
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_Auth.new),
        authenticatedHttpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> watch(String scope) async {
    container.listen(notificationsProvider(scope), (_, _) {});
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'read response merges authoritative workflow state without mixing inboxes',
    () async {
      await watch('adviser');
      await watch('panelist');
      client.onPost = (_) async => http.Response(
        jsonEncode({
          'unread_count': 24,
          'notification': {
            'id': 1,
            'is_read': true,
            'action': {
              'status': 'completed',
              'route': '/faculty/defense-board/minutes/42',
            },
          },
        }),
        200,
      );
      await container
          .read(notificationsProvider('adviser').notifier)
          .markAsRead(1);
      final current = container
          .read(notificationsProvider('adviser'))
          .notifications
          .single;
      expect(current['action']['status'], 'completed');
      expect(
        container
            .read(notificationsProvider('panelist'))
            .notifications
            .single['is_read'],
        false,
      );
    },
  );

  test(
    'checking an action refreshes its target without marking it read',
    () async {
      await watch('adviser');
      final requests = <Uri>[];
      client.onGet = (uri) async {
        requests.add(uri);
        return http.Response(
          jsonEncode({
            'notification': {
              'id': 1,
              'is_read': false,
              'action': {'status': 'unavailable', 'route': null},
            },
          }),
          200,
        );
      };
      final item = await container
          .read(notificationsProvider('adviser').notifier)
          .refreshNotification(1);
      expect(requests.single.path, '/api/notifications/1/');
      expect(requests.single.queryParameters['workspace'], 'adviser');
      expect(item?['is_read'], false);
      expect(container.read(notificationsProvider('adviser')).unreadCount, 25);
      client.onGet = (_) async => http.Response('{}', 500);
      expect(
        await container
            .read(notificationsProvider('adviser').notifier)
            .refreshNotification(1),
        isNull,
      );
      expect(container.read(notificationsProvider('adviser')).error, isNotNull);
      expect(container.read(notificationsProvider('adviser')).unreadCount, 25);
    },
  );

  test(
    'list, individual read and bulk read carry the selected workspace',
    () async {
      final requests = <Uri>[];
      client.onGet = (uri) async {
        requests.add(uri);
        return _response();
      };
      client.onPost = (uri) async {
        requests.add(uri);
        return http.Response('{"unread_count":24}', 200);
      };
      await watch('adviser');
      await watch('panelist');
      await container
          .read(notificationsProvider('adviser').notifier)
          .markAsRead(1);
      expect(container.read(notificationsProvider('adviser')).unreadCount, 24);
      expect(container.read(notificationsProvider('panelist')).unreadCount, 25);
      await container
          .read(notificationsProvider('adviser').notifier)
          .markAllAsRead();
      expect(
        requests.where((u) => u.path.contains('/read')),
        everyElement(
          predicate<Uri>((u) => u.queryParameters['workspace'] == 'adviser'),
        ),
      );
      expect(
        container
            .read(notificationsProvider('panelist'))
            .notifications
            .single['is_read'],
        false,
      );
    },
  );

  test(
    'failed reads preserve items and badge and display a retryable error',
    () async {
      await watch('documenter');
      client.onPost = (_) async => http.Response('{}', 500);
      final notifier = container.read(
        notificationsProvider('documenter').notifier,
      );
      expect(await notifier.markAsRead(1), false);
      expect(
        container
            .read(notificationsProvider('documenter'))
            .notifications
            .single['is_read'],
        false,
      );
      expect(
        container.read(notificationsProvider('documenter')).unreadCount,
        25,
      );
      expect(await notifier.markAllAsRead(), false);
      expect(
        container.read(notificationsProvider('documenter')).unreadCount,
        25,
      );
      expect(
        container.read(notificationsProvider('documenter')).error,
        contains('Could not mark'),
      );
      expect(
        container.read(notificationsProvider('documenter')).isSaving,
        false,
      );
    },
  );

  test(
    'unread filtering and older pages stay server scoped and deduplicate rows',
    () async {
      final requests = <Uri>[];
      client.onGet = (uri) async {
        requests.add(uri);
        if (uri.queryParameters['page'] == '2') {
          return _response(
            items: [
              {'id': 1, 'is_read': false},
              {'id': 2, 'is_read': false},
            ],
          );
        }
        return _response(
          next:
              'https://untrusted.example/api/notifications/?workspace=other&page=2',
        );
      };
      await watch('adviser');
      final notifier = container.read(
        notificationsProvider('adviser').notifier,
      );
      await notifier.fetchNotifications(unreadOnly: true);
      await notifier.fetchNotifications(loadMore: true);
      expect(
        container
            .read(notificationsProvider('adviser'))
            .notifications
            .map((n) => n['id']),
        [1, 2],
      );
      expect(container.read(notificationsProvider('adviser')).nextPage, null);
      expect(requests.last.queryParameters, {
        'workspace': 'adviser',
        'page': '2',
        'unread': 'true',
      });
      expect(requests.last.host, isNot('untrusted.example'));
      expect(container.read(notificationsProvider('adviser')).unreadCount, 25);
    },
  );

  test(
    'out of order filter responses cannot replace the current list',
    () async {
      await watch('adviser');
      final slow = Completer<http.Response>();
      client.onGet = (uri) async => uri.queryParameters['unread'] == 'true'
          ? slow.future
          : _response(
              items: [
                {'id': 9, 'is_read': true},
              ],
            );
      final notifier = container.read(
        notificationsProvider('adviser').notifier,
      );
      final pending = notifier.fetchNotifications(unreadOnly: true);
      await notifier.fetchNotifications(unreadOnly: false);
      slow.complete(
        _response(
          items: [
            {'id': 8, 'is_read': false},
          ],
        ),
      );
      await pending;
      expect(
        container
            .read(notificationsProvider('adviser'))
            .notifications
            .single['id'],
        9,
      );
      expect(
        container.read(notificationsProvider('adviser')).unreadOnly,
        false,
      );
    },
  );

  test(
    'changing accounts clears cached alerts and ignores the former user response',
    () async {
      await watch('adviser');
      final slow = Completer<http.Response>();
      client.onGet = (_) => slow.future;
      final pending = container
          .read(notificationsProvider('adviser').notifier)
          .fetchNotifications();
      client.onGet = (_) async => _response(unread: 0, total: 0, items: []);
      (container.read(authProvider.notifier) as _Auth).changeUser(2);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(notificationsProvider('adviser')).notifications,
        isEmpty,
      );
      slow.complete(
        _response(
          items: [
            {'id': 111, 'is_read': false},
          ],
        ),
      );
      await pending;
      expect(
        container.read(notificationsProvider('adviser')).notifications,
        isEmpty,
      );
      expect(container.read(notificationsProvider('adviser')).unreadCount, 0);
    },
  );
}
