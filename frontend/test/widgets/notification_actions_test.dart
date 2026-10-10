import 'dart:convert';

import 'package:defensys/notifications/notification_request_screen.dart';
import 'package:defensys/notifications/notifications_bell.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/capture_preview.dart';

const _preview = ValueKey('request-preview');

class _Client implements AuthenticatedHttpClient {
  String status = 'pending';
  bool canReview = true;
  int resultCode = 200;
  int patchCode = 200;
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];
  @override
  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) async {
    calls.add('GET ${uri.path}');
    return http.Response(
      jsonEncode({
        'can_review': canReview,
        'request': {
          'id': 42,
          'faculty_name': 'Ana Cruz',
          'name': 'External Expert',
          'requested_by_name': 'Ricardo Fontanilla',
          'pit_year': '1st Year',
          'created_at': '2026-10-06T09:00:00Z',
          'status': status,
          'reason': 'Project expertise',
          'review_note': status == 'declined' ? 'Insufficient experience' : '',
          'reviewed_at': status == 'pending' ? null : '2026-10-10T10:00:00Z',
          'reviewed_by_name': status == 'pending' ? null : 'Administrator',
        },
      }),
      resultCode,
    );
  }

  @override
  Future<http.Response> patch(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    calls.add('PATCH ${uri.path}');
    final data = Map<String, dynamic>.from(jsonDecode(body as String));
    bodies.add(data);
    status = patchCode == 200 ? data['decision'] ?? data['status'] : 'approved';
    return http.Response('{}', patchCode);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Inbox extends NotificationsNotifier {
  _Inbox(super.workspace);
  static int reads = 0, checks = 0;
  static bool unavailable = false;
  static String initialStatus = 'pending';
  Map<String, dynamic> item(String status) => {
    'id': 1,
    'title': 'Panelist eligibility request',
    'message': 'Review Ana Cruz’s nomination.',
    'is_read': false,
    'category': 'DEFENSE',
    'action_route': '/admin/defense-board',
    'action': {
      'status': status,
      'label': status == 'pending'
          ? 'Awaiting approval'
          : status == 'unavailable'
          ? 'No longer available'
          : 'Approved',
      'is_complete': status == 'completed',
      'route': status == 'unavailable'
          ? null
          : '/admin/defense-board/requests/panelist/42',
      'cta': status == 'pending' ? 'Review panelist request' : 'View request',
    },
  };
  @override
  NotificationsState build() => workspace == 'account'
      ? const NotificationsState()
      : NotificationsState(
          unreadCount: 1,
          totalCount: 1,
          notifications: [item(initialStatus)],
        );
  @override
  Future<void> fetchNotifications({
    bool? unreadOnly,
    bool loadMore = false,
  }) async {}
  @override
  Future<Map<String, dynamic>?> refreshNotification(int id) async {
    checks++;
    final current = item(unavailable ? 'unavailable' : 'completed');
    state = state.copyWith(notifications: [current]);
    return current;
  }

  @override
  Future<bool> markAsRead(int id) async {
    reads++;
    return true;
  }
}

Future<void> _pumpRequest(
  WidgetTester tester,
  _Client client, {
  String kind = 'panelist',
  Size size = const Size(1100, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts(force: true);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authenticatedHttpClientProvider.overrideWithValue(client)],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: RepaintBoundary(
            key: _preview,
            child: NotificationRequestScreen(
              kind: kind,
              requestId: 42,
              onBack: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _Inbox.initialStatus = 'pending');

  for (final status in ['pending', 'completed']) {
    testWidgets(
      'notification displays workflow status $status independently of unread state',
      (tester) async {
        _Inbox.initialStatus = status;
        await loadPreviewFonts(force: true);
        tester.view.physicalSize = const Size(1100, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [notificationsProvider.overrideWith2(_Inbox.new)],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: RepaintBoundary(
                key: _preview,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('Administrator'),
                    actions: const [
                      NotificationsBell(
                        workspace: 'admin',
                        workspaceLabel: 'Administrator',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.notifications_outlined));
        await tester.pumpAndSettle();
        expect(
          find.text(status == 'pending' ? 'Awaiting approval' : 'Approved'),
          findsOneWidget,
        );
        expect(
          find.text(
            status == 'pending' ? 'Review panelist request' : 'View request',
          ),
          findsOneWidget,
        );
        expect(find.text('Mark read'), findsOneWidget);
        await capturePreview(
          tester,
          find.byKey(_preview),
          'notification_action_$status',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('declining a request records the note on that request', (
    tester,
  ) async {
    final client = _Client();
    await _pumpRequest(tester, client);
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(EditableText),
      'Insufficient experience',
    );
    await tester.tap(find.widgetWithText(ShadButton, 'Decline request'));
    await tester.pumpAndSettle();
    expect(client.bodies.single['review_note'], 'Insufficient experience');
    expect(client.bodies.single['decision'], 'declined');
    expect(find.text('Declined'), findsOneWidget);
    expect(find.text('Approve request'), findsNothing);
  });

  testWidgets(
    'concurrent review refreshes the decision and removes obsolete controls',
    (tester) async {
      await _pumpRequest(tester, _Client()..patchCode = 400);
      await tester.tap(find.text('Approve request'));
      await tester.pumpAndSettle();
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Approve request'), findsNothing);
      expect(
        find.text(
          'The request could not be reviewed. Its latest status is shown below.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'specific pending request can be approved and then shows its decision',
    (tester) async {
      final client = _Client();
      await _pumpRequest(tester, client);
      expect(client.calls, ['GET /api/users/panelist-requests/42/']);
      expect(find.text('Ana Cruz'), findsOneWidget);
      expect(find.text('Awaiting approval'), findsOneWidget);
      await capturePreview(
        tester,
        find.byKey(_preview),
        'notification_request_pending',
      );
      await tester.tap(find.text('Approve request'));
      await tester.pumpAndSettle();
      expect(client.bodies.single['decision'], 'approved');
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('Approve request'), findsNothing);
      expect(
        find.text('This request has already been reviewed.'),
        findsOneWidget,
      );
      await capturePreview(
        tester,
        find.byKey(_preview),
        'notification_request_completed',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'declined request on a phone shows the decision without review controls',
    (tester) async {
      await _pumpRequest(
        tester,
        _Client()..status = 'declined',
        size: const Size(360, 780),
      );
      expect(find.text('Declined'), findsOneWidget);
      expect(find.text('Insufficient experience'), findsOneWidget);
      expect(find.text('Approve request'), findsNothing);
      await capturePreview(
        tester,
        find.byKey(_preview),
        'notification_request_mobile',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('requester sees pending request without approval controls', (
    tester,
  ) async {
    await _pumpRequest(tester, _Client()..canReview = false);
    expect(find.text('Awaiting approval'), findsOneWidget);
    expect(find.text('Approve request'), findsNothing);
  });

  testWidgets(
    'external evaluator action sends the decision to the exact evaluator',
    (tester) async {
      final client = _Client();
      await _pumpRequest(tester, client, kind: 'external');
      await tester.tap(find.text('Approve request'));
      await tester.pumpAndSettle();
      expect(
        client.calls,
        contains('PATCH /api/users/external-evaluators/42/'),
      );
      expect(client.bodies.single['status'], 'approved');
      expect(find.text('Approved'), findsOneWidget);
    },
  );

  testWidgets('deleted or inaccessible request shows a useful empty state', (
    tester,
  ) async {
    await _pumpRequest(tester, _Client()..resultCode = 404);
    expect(
      find.text(
        'This request is no longer available or you do not have access.',
      ),
      findsOneWidget,
    );
    expect(find.text('Approve request'), findsNothing);
  });

  for (final unavailable in [false, true]) {
    testWidgets(
      'notification checks live completion before opening: unavailable=$unavailable',
      (tester) async {
        _Inbox.reads = _Inbox.checks = 0;
        _Inbox.unavailable = unavailable;
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Scaffold(
                appBar: AppBar(
                  actions: const [
                    NotificationsBell(
                      workspace: 'admin',
                      workspaceLabel: 'Administrator',
                    ),
                  ],
                ),
              ),
            ),
            GoRoute(
              path: '/admin/defense-board/requests/panelist/:id',
              builder: (_, state) =>
                  Scaffold(body: Text('Request ${state.pathParameters['id']}')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [notificationsProvider.overrideWith2(_Inbox.new)],
            child: MaterialApp.router(
              theme: AppTheme.lightTheme,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.notifications_outlined));
        await tester.pumpAndSettle();
        expect(find.text('Awaiting approval'), findsOneWidget);
        await tester.tap(find.text('Review panelist request'));
        await tester.pumpAndSettle();
        expect(_Inbox.checks, 1);
        expect(_Inbox.reads, unavailable ? 0 : 1);
        expect(
          find.text(unavailable ? 'No longer available' : 'Request 42'),
          findsOneWidget,
        );
        if (unavailable) expect(find.text('View request'), findsNothing);
      },
    );
  }
}
