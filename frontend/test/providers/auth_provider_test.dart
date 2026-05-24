import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user/services/api_http.dart';
import 'package:user/services/auth_provider.dart';
import 'package:user/services/auth_storage_keys.dart';

import '../helpers/mock_http_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installDefaultMockHttp();
  });

  tearDown(() {
    resetApiHttpClientForTesting();
  });

  group('AuthNotifier', () {
    test('login succeeds and stores access in state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Wait for bootstrap to finish.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final success = await container.read(authProvider.notifier).login(
            'admin',
            'pass',
            rememberMe: false,
          );

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
      final next = initial.copyWith(
        isLoading: false,
        token: 'abc',
      );

      expect(next.isLoading, isFalse);
      expect(next.token, 'abc');
    });
  });
}
