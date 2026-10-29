import 'dart:convert';

import 'package:defensys/notifications/minutes_notification_route.dart';
import 'package:defensys/notifications/notifications_bell.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

class _Client implements AuthenticatedHttpClient {
  final requests = <Uri>[];
  bool available = true;
  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) async {
    requests.add(uri);
    return http.Response(
      jsonEncode({
        'schedules': [
          if (available)
            {'id': 33, 'team_id': 7, 'stage_label': 'Concept Proposal'},
        ],
      }),
      200,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MinutesInbox extends NotificationsNotifier {
  _MinutesInbox(super.workspace);
  static int reads = 0, refreshes = 0;
  Map<String, dynamic> get item => {
    'id': 1,
    'title': 'Minutes Ready for Review',
    'message': 'Review the minutes.',
    'is_read': false,
    'category': 'MINUTES',
    'action_route':
        '/${workspace == 'admin' ? 'admin' : 'faculty'}/defense-board/minutes/33',
    'action': {
      'status': 'pending',
      'label': 'Action needed',
      'is_complete': false,
      'route': workspace == 'admin'
          ? '/admin/defense-board?minutes=33'
          : '/faculty/deliverables/teams/7?scope=capstone&tab=defense&stage=Concept+Proposal',
      'cta': 'Open minutes',
    },
  };
  @override
  NotificationsState build() => workspace == 'account'
      ? const NotificationsState()
      : NotificationsState(
          notifications: [item],
          unreadCount: 1,
          totalCount: 1,
        );
  @override
  Future<void> fetchNotifications({
    bool? unreadOnly,
    bool loadMore = false,
  }) async {}
  @override
  Future<Map<String, dynamic>?> refreshNotification(int id) async {
    refreshes++;
    return item;
  }

  @override
  Future<bool> markAsRead(int id) async {
    reads++;
    return true;
  }
}

void main() {
  for (final workspace in ['adviser', 'admin']) {
    testWidgets(
      '$workspace notification opens its workspace instead of its stored editor URL',
      (tester) async {
        _MinutesInbox.reads = _MinutesInbox.refreshes = 0;
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Scaffold(
                appBar: AppBar(
                  actions: [
                    NotificationsBell(
                      workspace: workspace,
                      workspaceLabel: workspace,
                    ),
                  ],
                ),
              ),
            ),
            GoRoute(
              path: '/faculty/deliverables/teams/:teamId',
              builder: (_, state) => Scaffold(
                body: Text(
                  '${state.pathParameters['teamId']} ${state.uri.queryParameters['tab']} ${state.uri.queryParameters['stage']}',
                ),
              ),
            ),
            GoRoute(
              path: '/admin/defense-board',
              builder: (_, state) => Scaffold(
                body: Text(
                  'Board review ${state.uri.queryParameters['minutes']}',
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [notificationsProvider.overrideWith2(_MinutesInbox.new)],
            child: MaterialApp.router(
              theme: AppTheme.lightTheme,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.notifications_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open minutes'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            workspace == 'admin'
                ? 'Board review 33'
                : '7 defense Concept Proposal',
          ),
          findsOneWidget,
        );
        expect(_MinutesInbox.refreshes, 1);
        expect(_MinutesInbox.reads, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final available in [true, false]) {
    testWidgets(
      'legacy adviser link resolves the exact defense with access=$available',
      (tester) async {
        final client = _Client()..available = available;
        final router = GoRouter(
          initialLocation: '/faculty/defense-board/minutes/33',
          routes: [
            GoRoute(
              path: '/faculty/defense-board',
              builder: (_, _) => const Scaffold(),
              routes: [legacyMinutesNotificationRoute('faculty')],
            ),
            GoRoute(
              path: '/faculty/deliverables/teams/:teamId',
              builder: (_, state) => Scaffold(
                body: Text(
                  '${state.pathParameters['teamId']} ${state.uri.queryParameters['tab']} ${state.uri.queryParameters['stage']}',
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authenticatedHttpClientProvider.overrideWithValue(client),
            ],
            child: MaterialApp.router(
              theme: AppTheme.lightTheme,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(client.requests.single.path, '/api/defense/board/');
        expect(client.requests.single.queryParameters, {
          'schedule_id': '33',
          'scope': 'capstone',
          'workspace': 'adviser',
        });
        if (available) {
          expect(find.text('7 defense Concept Proposal'), findsOneWidget);
        } else {
          expect(
            find.text(
              'This defense record is unavailable. Retry or open Capstone Teams.',
            ),
            findsOneWidget,
          );
          expect(find.text('7 defense Concept Proposal'), findsNothing);
          client.available = true;
          await tester.tap(find.text('Retry'));
          await tester.pumpAndSettle();
          expect(find.text('7 defense Concept Proposal'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
