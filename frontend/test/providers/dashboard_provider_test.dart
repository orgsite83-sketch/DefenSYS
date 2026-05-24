import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user/services/api_http.dart';
import 'package:user/services/dashboard_provider.dart';

import '../helpers/auth_test_overrides.dart';
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

  test('fetchDashboardData loads admin stats', () async {
    final container = ProviderContainer(
      overrides: authTestOverrides(),
    );
    addTearDown(container.dispose);

    await container.read(dashboardProvider('admin').notifier).fetchDashboardData();

    final state = container.read(dashboardProvider('admin'));
    expect(state.isLoading, isFalse);
    expect(state.data?['stats'], isNotNull);
    expect(state.data?['stats']['total_teams'], 1);
  });
}
