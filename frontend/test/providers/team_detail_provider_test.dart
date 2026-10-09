import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/team_detail_provider.dart';

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

  test('related reads start together after the team response', () async {
    final pending = <String, Completer<http.Response>>{};
    setApiHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('/teams/1/')) {
          return http.Response(
            jsonEncode({
              'team': {'id': 1, 'level': '3rd Year Capstone'},
            }),
            200,
          );
        }
        final response = Completer<http.Response>();
        pending[request.url.path] = response;
        return response.future;
      }),
    );
    final container = ProviderContainer(overrides: authTestOverrides());
    addTearDown(container.dispose);
    final loading = container.read(teamDetailProvider(1).notifier).load();
    await Future<void>.delayed(Duration.zero);
    expect(pending.length, 5);
    for (final response in pending.values) {
      response.complete(http.Response('{}', 200));
    }
    await loading;
    expect(container.read(teamDetailProvider(1)).isLoading, isFalse);
    expect(container.read(teamDetailProvider(1)).team?['id'], 1);
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
