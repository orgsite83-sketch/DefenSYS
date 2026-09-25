import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/navigation/app_router.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/screens/app/student/profile_edit_screen.dart';

import '../helpers/pump_app.dart';

class FakeNotificationsNotifier extends NotificationsNotifier {
  @override
  NotificationsState build() {
    return const NotificationsState(notifications: [], unreadCount: 0);
  }

  @override
  Future<void> fetchNotifications() async {}
}

class FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState(
      isLoading: false,
      isRestoring: false,
      token: 'fake-token',
      user: {
        'id': 1,
        'username': 'admin',
        'email': 'admin@defensys.edu',
        'role': 'admin',
        'name': 'Administrator',
      },
    );
  }
}

void main() {
  testWidgets('Navigating to /admin/profile renders without error', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => FakeAuthNotifier()),
        notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => FakeAuthNotifier()),
          notificationsProvider.overrideWith(() => FakeNotificationsNotifier()),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ProfileScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('Identity & Account Details'), findsOneWidget);
    expect(find.text('Security & Password'), findsOneWidget);
  });
}
