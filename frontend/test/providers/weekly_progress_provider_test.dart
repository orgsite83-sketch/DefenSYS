import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user/services/api_http.dart';
import 'package:user/services/weekly_progress_provider.dart';

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

  test('fetchReports loads weekly progress list', () async {
    final container = ProviderContainer(
      overrides: authTestOverrides(),
    );
    addTearDown(container.dispose);

    await container.read(weeklyProgressProvider.notifier).fetchReports();

    final state = container.read(weeklyProgressProvider);
    expect(state.isLoading, isFalse);
    expect(state.reports, hasLength(1));
    expect(state.reports.first['week_number'], 1);
  });
}
