import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/academic/student_team_selection_provider.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
    final container = ProviderContainer(overrides: authTestOverrides());
    addTearDown(container.dispose);

    await container
        .read(dashboardProvider('admin').notifier)
        .fetchDashboardData();

    final state = container.read(dashboardProvider('admin'));
    expect(state.isLoading, isFalse);
    expect(state.data?['stats'], isNotNull);
    expect(state.data?['stats']['total_teams'], 1);
  });

  test(
    'event team selection cannot replace the current home team or duplicate its request',
    () async {
      final requests = <http.Request>[];
      final responses = <Completer<http.Response>>[];
      setApiHttpClientForTesting(
        MockClient((request) {
          requests.add(request);
          final response = Completer<http.Response>();
          responses.add(response);
          return response.future;
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final selection = container.read(studentTeamSelectionProvider.notifier);
      final dashboard = container.read(dashboardProvider('student').notifier);
      selection.select(7);
      final first = dashboard.fetchDashboardData();
      final shared = dashboard.fetchDashboardData(silent: true);
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(1));
      expect(requests.first.url.queryParameters.containsKey('team_id'), isFalse);
      selection.select(9);
      final second = dashboard.fetchDashboardData();
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(1));
      responses[0].complete(
        http.Response(
          jsonEncode({
            'team': {'id': 1},
          }),
          200,
        ),
      );
      await Future.wait([first, shared, second]);
      expect(
        container.read(dashboardProvider('student')).data?['team']['id'],
        1,
      );
    },
  );
}
