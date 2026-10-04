import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/navigation/app_router.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:defensys/utils/guest_invitation.dart';
import '../helpers/auth_test_overrides.dart';

class _Auth extends AuthNotifier {
  _Auth(this.initial);
  final AuthState initial;
  @override
  AuthState build() => initial;
  void restoreGuest() => state = AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: const {'id': 21, 'role': 'guest_panelist', 'name': 'Guest Evaluator'},
  );
}

void main() {
  setUp(
    () => setApiHttpClientForTesting(
      MockClient((_) async => http.Response('{"teams":[],"results":[]}', 200)),
    ),
  );
  tearDown(resetApiHttpClientForTesting);
  Future<ProviderContainer> app(
    WidgetTester tester,
    AuthState auth, {
    String location = AppRoutes.guestEntry,
  }) async {
    final container = ProviderContainer(
      overrides: [authProvider.overrideWith(() => _Auth(auth))],
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    router.go(location);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('Public guest portal is available without institutional login', (
    tester,
  ) async {
    final container = await app(tester, const AuthState(isRestoring: false));
    expect(find.text('Guest evaluation'), findsOneWidget);
    final router = container.read(appRouterProvider);
    router.go(AppRoutes.guestDefenses);
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.guestEntry,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'A new invitation opens its own code while another guest session is active',
    (tester) async {
      final link = guestInvitationUrl(
        'DEF-NEW-STAGE',
        portal: 'http://192.168.1.3:57583/#/guest/evaluate',
      );
      final container = await app(
        tester,
        AuthState(
          isRestoring: false,
          token: testAccessToken,
          user: const {
            'id': 21,
            'role': 'guest_panelist',
            'name': 'Guest Evaluator',
          },
        ),
        location: Uri.parse(link).fragment,
      );
      expect(find.text('Guest evaluation'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'DEF-NEW-STAGE',
      );
      expect(
        container
            .read(appRouterProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .queryParameters['code'],
        'DEF-NEW-STAGE',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Changing invitation links updates the code without keeping the previous stage',
    (tester) async {
      final container = await app(
        tester,
        const AuthState(isRestoring: false),
        location: '${AppRoutes.guestEntry}?code=DEF-FIRST',
      );
      final router = container.read(appRouterProvider);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'DEF-FIRST',
      );
      router.go('${AppRoutes.guestEntry}?code=DEF-SECOND');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'DEF-SECOND',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Guest identity is confined to its evaluation workspace', (
    tester,
  ) async {
    final container = await app(
      tester,
      AuthState(
        isRestoring: false,
        token: testAccessToken,
        user: const {
          'id': 21,
          'name': 'Guest Evaluator',
          'role': 'guest_panelist',
        },
      ),
    );
    final router = container.read(appRouterProvider);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.guestDefenses,
    );
    router.go('/admin/users');
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.guestDefenses,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Guest reload waits for restoration before requesting assignments',
    (tester) async {
      final requests = <String>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url.path);
          return http.Response('{"teams":[],"results":[]}', 200);
        }),
      );
      final auth = _Auth(const AuthState(isRestoring: true));
      final container = ProviderContainer(
        overrides: [authProvider.overrideWith(() => auth)],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      router.go(AppRoutes.guestDefenses);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pump();
      expect(requests, isEmpty);
      auth.restoreGuest();
      await tester.pumpAndSettle();
      expect(requests, contains('/api/defense/schedules/guest-assignments/'));
      expect(
        requests,
        isNot(contains('/api/defense/schedules/panelist-assignments/')),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
