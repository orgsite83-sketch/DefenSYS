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

  for (final scope in ['capstone', 'pit']) {
    test('grade request uses the team identity and $scope scope', () async {
      Uri? gradeRequest;
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.url.path.endsWith('/teams/1/')) {
            return http.Response(
              jsonEncode({
                'team': {
                  'id': 1,
                  'level': scope == 'capstone'
                      ? '4th Year Capstone'
                      : '1st Year PIT',
                },
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/grading/grades/')) {
            gradeRequest = request.url;
            return http.Response(
              jsonEncode({
                'grades': [
                  {'id': 7, 'final_grade': '0.00'},
                ],
              }),
              200,
            );
          }
          return http.Response('{}', 200);
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      await container.read(teamDetailProvider(1).notifier).load();
      expect(gradeRequest?.queryParameters, {'team_id': '1', 'scope': scope});
      expect(
        container.read(teamDetailProvider(1)).grades.single['final_grade'],
        '0.00',
      );
    });
  }

  test(
    'a grade failure stays distinct from an empty result and clears on retry',
    () async {
      var failGrades = true;
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.url.path.endsWith('/teams/1/')) {
            return http.Response(
              jsonEncode({
                'team': {'id': 1, 'level': '4th Year Capstone'},
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/grading/grades/')) {
            return failGrades
                ? http.Response('{}', 503)
                : http.Response('{"grades":[]}', 200);
          }
          return http.Response('{}', 200);
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(teamDetailProvider(1).notifier);
      await notifier.load();
      expect(container.read(teamDetailProvider(1)).team?['id'], 1);
      expect(container.read(teamDetailProvider(1)).error, isNull);
      expect(container.read(teamDetailProvider(1)).gradesError, isNotNull);
      failGrades = false;
      await notifier.load();
      expect(container.read(teamDetailProvider(1)).gradesError, isNull);
      expect(container.read(teamDetailProvider(1)).grades, isEmpty);
    },
  );
}
