import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/services/app/data_refresh_provider.dart';

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

  test('fetchTeams loads teams list', () async {
    final container = ProviderContainer(overrides: authTestOverrides());
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

  test(
    'PIT import keeps event context when the directory has no explicit level',
    () async {
      http.Request? previewRequest;
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'POST') previewRequest = request;
          return http.Response('{"teams":[],"rows":[],"summary":{}}', 200);
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(studentTeamsProvider.notifier);
      await notifier.fetchTeams(level: '', eventName: 'PIT Design');
      await notifier.bulkImportPreview([
        {'team_name': 'Prepared roster'},
      ]);
      expect(jsonDecode(previewRequest!.body)['event_name'], 'PIT Design');
    },
  );

  test(
    'stale preview failure cannot replace a newer successful validation',
    () async {
      final responses = [
        Completer<http.Response>(),
        Completer<http.Response>(),
      ];
      final bothStarted = Completer<void>();
      var count = 0;
      setApiHttpClientForTesting(
        MockClient((request) {
          final index = count++;
          if (count == 2) bothStarted.complete();
          return responses[index].future;
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(studentTeamsProvider.notifier);
      final older = notifier.bulkImportPreview([
        {'team_name': 'Old'},
      ]);
      final newer = notifier.bulkImportPreview([
        {'team_name': 'New'},
      ]);
      await bothStarted.future;
      responses[1].complete(
        http.Response('{"rows":[],"summary":{"ready":0}}', 200),
      );
      expect(await newer, isNotNull);
      responses[0].complete(
        http.Response('{"detail":"Old validation error"}', 400),
      );
      expect(await older, isNull);
      expect(container.read(studentTeamsProvider).error, isNull);
    },
  );

  test(
    'section choices ignore directory search without changing its filters',
    () async {
      final requests = <http.Request>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'teams': [
                {'id': 5, 'section': 'BSIT-2A', 'is_editable': true},
              ],
            }),
            200,
          );
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(studentTeamsProvider.notifier);
      await notifier.fetchTeams(
        search: 'Team One',
        level: 'PIT',
        status: 'Pending',
        eventName: 'Demo',
      );
      final directory = container.read(studentTeamsProvider);
      final choices = await notifier.fetchSectionTeams(
        level: 'PIT',
        scope: 'active',
        yearLevel: '2nd Year',
        section: 'BSIT-2A',
      );
      expect(choices.single['section'], 'BSIT-2A');
      expect(requests.last.url.queryParameters, {
        'level': 'PIT',
        'scope': 'active',
        'year_level': '2nd Year',
        'section': 'BSIT-2A',
      });
      expect(container.read(studentTeamsProvider), same(directory));
    },
  );

  test(
    'section save refreshes renamed filter and notifies related screens',
    () async {
      final requests = <http.Request>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request);
          if (request.method == 'PATCH') {
            return http.Response(jsonEncode({'section': 'BSIT-4B'}), 200);
          }
          return http.Response(
            jsonEncode({
              'teams': [],
              'active_semester': {'id': 1},
            }),
            200,
          );
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final notifier = container.read(studentTeamsProvider.notifier);
      await notifier.fetchTeams(
        section: 'BSIT-4b',
        search: 'Team One',
        level: 'PIT',
        eventName: 'Demo',
      );
      final success = await notifier.updateSectionDetails(5, {
        'expected_section': 'BSIT-4b',
        'section': 'BSIT-4B',
        'system_name': 'New system',
        'project_manager_id': null,
      }, scope: 'active');
      expect(success, isTrue);
      final patch = requests.firstWhere((request) => request.method == 'PATCH');
      expect(patch.url.path, endsWith('/teams/5/section/'));
      expect(jsonDecode(patch.body)['project_manager_id'], isNull);
      expect(
        requests.last.url.queryParameters,
        containsPair('section', 'BSIT-4B'),
      );
      expect(
        requests.last.url.queryParameters,
        containsPair('search', 'Team One'),
      );
      expect(
        requests.last.url.queryParameters,
        containsPair('event_name', 'Demo'),
      );
      expect(
        requests.last.url.queryParameters,
        containsPair('scope', 'active'),
      );
      expect(
        container.read(studentTeamsProvider).message,
        'Section details updated.',
      );
      expect(
        container.read(dataRefreshProvider),
        containsPair(DataArea.academicRecords, 1),
      );
    },
  );

  test(
    'failed section save reports validation error without refreshing list',
    () async {
      final requests = <http.Request>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'section': ['This section already exists.'],
            }),
            400,
          );
        }),
      );
      final container = ProviderContainer(overrides: authTestOverrides());
      addTearDown(container.dispose);
      final success = await container
          .read(studentTeamsProvider.notifier)
          .updateSectionDetails(5, {
            'expected_section': 'BSIT-4b',
            'section': 'BSIT-4B',
          });
      expect(success, isFalse);
      expect(requests, hasLength(1));
      expect(container.read(studentTeamsProvider).isSaving, isFalse);
      expect(
        container.read(studentTeamsProvider).error,
        'This section already exists.',
      );
      expect(container.read(dataRefreshProvider), isEmpty);
    },
  );
}
