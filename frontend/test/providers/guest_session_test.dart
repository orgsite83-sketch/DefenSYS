import 'dart:convert';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/session/guest_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    clearGuestSession();
    exitGuestPortalMode();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
  });
  tearDown(() {
    clearGuestSession();
    exitGuestPortalMode();
    resetApiHttpClientForTesting();
  });

  test(
    'Guest exchange stores only guest access and never refreshes into an institutional account',
    () async {
      final paths = <String>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(
            jsonEncode({
              'access': testAccessToken,
              'user': {
                'id': 21,
                'role': 'guest_panelist',
                'name': 'Guest Evaluator',
                'schedule_ids': [10, 11],
              },
            }),
            200,
          );
        }),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(authProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final auth = container.read(authProvider.notifier);
      expect(await auth.loginGuest('def-123'), isTrue);
      expect(container.read(authProvider).user?['schedule_ids'], [10, 11]);
      expect(jsonDecode(readGuestSession()!)['access'], testAccessToken);
      expect(await auth.refreshTokens(), isFalse);
      expect(paths, ['/api/users/guest-codes/exchange/']);
      await auth.logout();
      expect(readGuestSession(), isNull);
      expect(container.read(authProvider).user, isNull);
    },
  );

  test(
    'Guest access survives provider recreation without a token-refresh request',
    () async {
      writeGuestSession(
        jsonEncode({
          'access': testAccessToken,
          'user': {'role': 'guest_panelist', 'name': 'Guest'},
        }),
      );
      var requests = 0;
      setApiHttpClientForTesting(
        MockClient((_) async {
          requests++;
          return http.Response('{}', 500);
        }),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(authProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(authProvider).user?['role'], 'guest_panelist');
      expect(container.read(authProvider).isRestoring, isFalse);
      expect(requests, 0);
    },
  );

  test(
    'Expired guest storage is cleared and an exchange failure has actionable feedback',
    () async {
      writeGuestSession(
        jsonEncode({
          'access': 'invalid',
          'user': {'role': 'guest_panelist'},
        }),
      );
      setApiHttpClientForTesting(
        MockClient((_) async => http.Response('{"detail":"Expired"}', 401)),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(authProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(readGuestSession(), isNull);
      expect(
        await container.read(authProvider.notifier).loginGuest('DEF-EXPIRED'),
        isFalse,
      );
      expect(
        container.read(authProvider).error,
        contains('defense coordinator'),
      );
      expect(container.read(authProvider).token, isNull);
    },
  );
}
