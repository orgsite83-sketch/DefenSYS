import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/navigation/app_router.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/terms_acceptance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';

class _Auth extends AuthNotifier {
  @override
  AuthState build() => AuthState(isRestoring: false, token: testAccessToken,
    requiresTerms: true, user: const {'id': 991, 'role': 'student', 'name': 'Mara Santos'});
}

void main() {
  testWidgets('Terms gate survives router refresh and prevents dashboard fetch until agreement', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final requests = <String>[];
    setApiHttpClientForTesting(MockClient((request) async {
      requests.add(request.url.path);
      return http.Response('{"team":null,"members":[],"results":[],"notifications":[],"stage_options":[],"teams":[]}', 200);
    }));
    addTearDown(resetApiHttpClientForTesting);
    final container = ProviderContainer(overrides: [authProvider.overrideWith(_Auth.new)]);
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    router.go(AppRoutes.student);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
    )));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.terms);
    expect(requests, isEmpty);
    router.go(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.terms);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Agree & Continue'));
    await tester.pumpAndSettle();
    expect(container.read(authProvider).requiresTerms, isFalse);
    expect(await TermsAcceptance.hasAcceptedCurrentTerms(), isTrue);
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.student);
    expect(requests.any((path) => path.contains('/dashboards/student')), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
