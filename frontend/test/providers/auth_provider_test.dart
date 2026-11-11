import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/auth_storage_keys.dart';

import '../helpers/mock_http_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installDefaultMockHttp();
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async => null);
  });

  tearDown(() {
    resetApiHttpClientForTesting();
  });

  group('AuthNotifier', () {
    test(
      'older role refresh cannot overwrite a newer workspace assignment',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final auth = container.read(authProvider.notifier);
        await auth.login('admin', 'pass');
        final older = Completer<http.Response>();
        final newer = Completer<http.Response>();
        var requests = 0;
        setApiHttpClientForTesting(
          MockClient((_) => ++requests == 1 ? older.future : newer.future),
        );
        final access = container.read(authProvider).token!;
        final first = auth.fetchCurrentUser(access);
        final second = auth.fetchCurrentUser(access);
        newer.complete(
          http.Response('{"id":1,"role":"admin","is_adviser":true}', 200),
        );
        expect(await second, isTrue);
        older.complete(
          http.Response('{"id":1,"role":"admin","is_adviser":false}', 200),
        );
        expect(await first, isFalse);
        expect(container.read(authProvider).user?['is_adviser'], isTrue);
      },
    );

    test('login succeeds and stores access in state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Wait for bootstrap to finish.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final success = await container
          .read(authProvider.notifier)
          .login('admin', 'pass', rememberMe: false);

      expect(success, isTrue);
      final state = container.read(authProvider);
      expect(state.token, isNotNull);
      expect(state.token!.isNotEmpty, isTrue);
      expect(state.user?['role'], 'admin');
      expect(state.error, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(AuthStorageKeys.rememberMe), isFalse);
      expect(prefs.getString(AuthStorageKeys.legacyJwtToken), isNull);
    });

    test('logout clears state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await container.read(authProvider.notifier).login('admin', 'pass');
      await container.read(authProvider.notifier).logout();

      expect(container.read(authProvider).token, isNull);
      expect(container.read(authProvider).user, isNull);
    });
  });

  group('AuthState', () {
    test('copyWith updates fields', () {
      final initial = AuthState(isLoading: true);
      final next = initial.copyWith(isLoading: false, token: 'abc');

      expect(next.isLoading, isFalse);
      expect(next.token, 'abc');
    });
  });
}
