import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user/services/api_http.dart';
import 'package:user/services/auth_provider.dart';

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
    test('login succeeds and stores token', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final success = await container.read(authProvider.notifier).login(
            'admin',
            'pass',
          );

      expect(success, isTrue);
      final state = container.read(authProvider);
      expect(state.token, 'test-jwt-token');
      expect(state.user?['role'], 'admin');
      expect(state.error, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), 'test-jwt-token');
    });

    test('logout clears state and preferences', () async {
      SharedPreferences.setMockInitialValues({
        'jwt_token': 'old',
        'user_data': '{"id":1}',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).logout();

      expect(container.read(authProvider).token, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), isNull);
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
