import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user/services/api_http.dart';
import 'package:user/services/team_detail_provider.dart';

import '../helpers/mock_http_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'jwt_token': 'test-token'});
    installDefaultMockHttp();
  });

  tearDown(() {
    resetApiHttpClientForTesting();
  });

  test('load fetches team and related data', () async {
    final container = ProviderContainer();
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
