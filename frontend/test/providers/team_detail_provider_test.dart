import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user/services/api_http.dart';
import 'package:user/services/team_detail_provider.dart';

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

  test('load fetches team and related data', () async {
    final container = ProviderContainer(overrides: authTestOverrides());
    addTearDown(container.dispose);

    await container.read(teamDetailProvider(1).notifier).load();

    final state = container.read(teamDetailProvider(1));
    expect(state.isLoading, isFalse);
    expect(state.team?['name'], 'Team CodeLearners');
    expect(state.students, isNotEmpty);
    expect(state.weeklyReports, isNotEmpty);
    expect(state.deliverableTeam, isNotNull);
  });
}
