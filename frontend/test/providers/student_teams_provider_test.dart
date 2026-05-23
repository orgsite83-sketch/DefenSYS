import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user/services/api_http.dart';
import 'package:user/services/student_teams_provider.dart';

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

  test('fetchTeams loads teams list', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(studentTeamsProvider.notifier).fetchTeams();

    final state = container.read(studentTeamsProvider);
    expect(state.isLoading, isFalse);
    expect(state.teams, hasLength(1));
    expect(state.teams.first['name'], 'Team CodeLearners');
    expect(state.students, isNotEmpty);
  });

  test('StudentTeamsState copyWith clears error when requested', () {
    const state = StudentTeamsState(error: 'oops');
    final next = state.copyWith(clearError: true);

    expect(next.error, isNull);
  });
}
