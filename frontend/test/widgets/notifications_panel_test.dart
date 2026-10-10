import 'package:defensys/notifications/notifications_bell.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/capture_preview.dart';

final _writes = <String>[];
const _preview = ValueKey('notification-preview');

class _Inbox extends NotificationsNotifier {
  _Inbox(super.workspace);
  @override
  NotificationsState build() => NotificationsState(
    unreadCount: 2,
    totalCount: 2,
    notifications: workspace == 'account'
        ? [
            {
              'id': 20,
              'title': 'Password changed',
              'message': 'Your account password was updated successfully.',
              'category': 'SECURITY',
              'priority': 'HIGH',
              'is_read': false,
              'created_at': DateTime.now().toUtc().toIso8601String(),
              'action_route': '/me/profile',
            },
            {
              'id': 21,
              'title': 'Account security update',
              'message': 'Review your account settings.',
              'is_read': false,
            },
          ]
        : [
            {
              'id': 1,
              'title': 'Minutes ready for review',
              'message':
                  "The minutes for Team AgriSense's Project Proposal defense are ready for your review and signature.",
              'category': 'MINUTES',
              'priority': 'HIGH',
              'is_read': false,
              'sender_name': 'Maria Santos',
              'created_at': DateTime.now().toUtc().toIso8601String(),
              'action_route': '/faculty/defense-board',
            },
            {
              'id': 2,
              'title': 'Defense schedule updated',
              'message':
                  'Team BioPulse will defend on October 14 at 9:00 AM in Room 301.',
              'category': 'DEFENSE',
              'is_read': false,
              'created_at': DateTime.now()
                  .subtract(const Duration(days: 1))
                  .toUtc()
                  .toIso8601String(),
              'action_route': '/faculty/defense-board',
            },
          ],
  );
  @override
  Future<void> fetchNotifications({
    bool? unreadOnly,
    bool loadMore = false,
  }) async {
    if (unreadOnly != null) state = state.copyWith(unreadOnly: unreadOnly);
  }

  @override
  Future<bool> markAllAsRead() async {
    _writes.add(workspace);
    state = state.copyWith(
      unreadCount: 0,
      notifications: [
        for (final n in state.notifications) {...n, 'is_read': true},
      ],
    );
    return true;
  }

  @override
  Future<bool> markAsRead(int id) async {
    _writes.add('$workspace:$id');
    state = state.copyWith(
      unreadCount: state.unreadCount - 1,
      notifications: [
        for (final n in state.notifications)
          n['id'] == id ? {...n, 'is_read': true} : n,
      ],
    );
    return true;
  }
}

class _StatusInbox extends _Inbox {
  _StatusInbox(super.workspace, this.status);
  final NotificationsState status;
  @override
  NotificationsState build() => status;
}

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  bool dark = false,
  NotificationsState? status,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationsProvider.overrideWith2(
          (workspace) => status == null
              ? _Inbox(workspace)
              : _StatusInbox(workspace, status),
        ),
      ],
      child: RepaintBoundary(
        key: _preview,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.mistDarkTheme,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: Scaffold(
            appBar: AppBar(
              backgroundColor: dark ? const Color(0xFF212024) : Colors.white,
              foregroundColor: dark ? Colors.white : const Color(0xFF0F172A),
              title: const Text('Project Adviser'),
              actions: const [
                NotificationsBell(
                  workspace: 'adviser',
                  workspaceLabel: 'Project Adviser',
                ),
              ],
            ),
            body: const Center(child: Text('Adviser dashboard')),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.notifications_outlined));
  await tester.pumpAndSettle();
}

void main() {
  for (final status in [
    const NotificationsState(isLoading: true),
    const NotificationsState(
      error: 'Could not load notifications. Please try again.',
    ),
    const NotificationsState(),
  ]) {
    testWidgets(
      'loading, error and empty states fit a short phone: ${status.isLoading}/${status.error}',
      (tester) async {
        await _pump(tester, const Size(320, 360), status: status);
        expect(
          find.byKey(const ValueKey('notifications-panel')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'notification action marks only its role alert and opens its destination',
    (tester) async {
      _writes.clear();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              appBar: AppBar(
                actions: const [
                  NotificationsBell(
                    workspace: 'adviser',
                    workspaceLabel: 'Project Adviser',
                  ),
                ],
              ),
            ),
          ),
          GoRoute(
            path: '/faculty/defense-board',
            builder: (_, _) =>
                const Scaffold(body: Text('Defense destination')),
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
      await tester.tap(find.text('Open minutes'));
      await tester.pumpAndSettle();
      expect(_writes, ['adviser:1']);
      expect(find.text('Defense destination'), findsOneWidget);
      expect(find.byKey(const ValueKey('notifications-panel')), findsNothing);
    },
  );

  for (final sample in [
    (name: 'notifications_desktop', size: const Size(1366, 768), dark: false),
    (name: 'notifications_mobile', size: const Size(320, 568), dark: false),
    (name: 'notifications_dark', size: const Size(1366, 768), dark: true),
    (name: 'notifications_short', size: const Size(600, 360), dark: false),
  ]) {
    testWidgets('top panel fits ${sample.name}', (tester) async {
      await _pump(tester, sample.size, dark: sample.dark);
      final panel = find.byKey(const ValueKey('notifications-panel'));
      final rect = tester.getRect(panel);
      expect(rect.top, lessThan(100));
      expect(rect.bottom, lessThanOrEqualTo(sample.size.height - 10));
      expect(rect.left, greaterThanOrEqualTo(10));
      expect(rect.right, lessThanOrEqualTo(sample.size.width - 10));
      expect(find.text('Workspace (2)'), findsOneWidget);
      expect(find.text('Password changed'), findsNothing);
      expect(tester.takeException(), isNull);
      await capturePreview(tester, find.byKey(_preview), sample.name);
      await tester.tap(find.byTooltip('Close notifications'));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
    });
  }

  testWidgets('account read all leaves workspace count and content unchanged', (
    tester,
  ) async {
    _writes.clear();
    await _pump(tester, const Size(1366, 768));
    await tester.tap(find.text('Account (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Password changed'), findsOneWidget);
    expect(find.text('Minutes ready for review'), findsNothing);
    await tester.tap(find.byTooltip('Mark all read in Account & security'));
    await tester.pumpAndSettle();
    expect(_writes, ['account']);
    expect(find.text('Workspace (2)'), findsOneWidget);
    await tester.tap(find.text('Workspace (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Minutes ready for review'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
  });
}
