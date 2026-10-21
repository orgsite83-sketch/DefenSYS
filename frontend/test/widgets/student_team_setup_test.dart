import 'dart:convert';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/widgets/student_team_setup_tasks.dart';
import 'package:defensys/services/academic/student_team_selection_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';

class _StudentAuth extends AuthNotifier {
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: const {'id': 1, 'role': 'student'},
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(resetApiHttpClientForTesting);

  testWidgets('leader confirms event-specific details without repeating initial setup', (tester) async {
    var confirmed = false;
    http.Request? saved;
    setApiHttpClientForTesting(MockClient((request) async {
      if (request.method == 'PATCH') {
        saved = request; confirmed = true;
        return http.Response('{"event_teams":[]}', 200);
      }
      return http.Response(jsonEncode({'teams': [], 'section_tasks': [], 'event_teams': confirmed ? [] : [{
        'id': 7, 'event_id': 11, 'event_name': 'PIT Expo', 'name': 'Team Sining',
        'section': 'BSIT-2A', 'year_level': '2nd Year', 'scope': 'pit', 'revision': 2,
        'needs_details': true, 'concept_enabled': false, 'project_title': 'Continuing project', 'concept_tasks': [],
      }]}), 200);
    }));
    await pumpDefensysWidget(tester, const StudentTeamSetupTasks(),
      overrides: [authProvider.overrideWith(_StudentAuth.new)]);
    expect(find.text('Choose team name'), findsNothing);
    await tester.tap(find.text('Confirm event team details')); await tester.pumpAndSettle();
    expect(find.text('Continuing project'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).first, 'Team Sining Expo');
    await tester.tap(find.text('Confirm details')); await tester.pumpAndSettle();
    expect(saved!.url.path, endsWith('/7/events/11/setup/'));
    expect(jsonDecode(saved!.body), {'name': 'Team Sining Expo', 'project_title': 'Continuing project', 'revision': 2});
    expect(find.text('Confirm event team details'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'leader sees configured concept count and can choose a team name',
    (tester) async {
      final team = {
        'id': 7,
        'name': 'Provisional 01',
        'section': 'BSIT-2A',
        'event_name': 'PIT Design',
        'needs_name': true,
        'scope': 'pit',
        'year_level': '2nd Year',
        'concept_tasks': [
          {
            'stage_label': 'PIT Design',
            'required_count': 5,
            'mode': 'proposals',
          },
        ],
      };
      http.Request? saved;
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'PATCH') {
            saved = request;
            team['name'] = jsonDecode(request.body)['name'];
            team['needs_name'] = false;
          }
          return http.Response(
            jsonEncode({
              'teams': [team],
            }),
            200,
          );
        }),
      );
      await pumpDefensysWidget(
        tester,
        const StudentTeamSetupTasks(),
        overrides: [authProvider.overrideWith(_StudentAuth.new)],
      );
      expect(find.text('Submit 5 concepts · PIT Design'), findsOneWidget);
      await tester.tap(find.text('Choose team name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Team Sining');
      await tester.tap(find.text('Save team name'));
      await tester.pumpAndSettle();
      expect(jsonDecode(saved!.body)['name'], 'Team Sining');
      expect(find.text('Choose team name'), findsNothing);
      expect(find.textContaining('Team Sining'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('concept task opens the selected team and configured stage', (
    tester,
  ) async {
    final requests = <http.Request>[];
    setApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/my-setup/')) {
          return http.Response(
            jsonEncode({
              'teams': [
                {
                  'id': 7,
                  'name': 'Team Sining',
                  'section': 'BSIT-2A',
                  'event_name': 'PIT Design',
                  'needs_name': false,
                  'scope': 'pit',
                  'year_level': '2nd Year',
                  'concept_tasks': [
                    {
                      'stage_label': 'PIT Design',
                      'required_count': 5,
                      'mode': 'proposals',
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path.contains('/dashboards/')) {
          return http.Response('{"team":{"id":7}}', 200);
        }
        return http.Response(
          jsonEncode({
            'teams': [
              {'id': 7},
            ],
            'selected_stage': 'PIT Design',
            'stage_options': ['PIT Design'],
          }),
          200,
        );
      }),
    );
    var opened = false;
    await pumpDefensysWidget(
      tester,
      StudentTeamSetupTasks(onOpenRepository: () => opened = true),
      overrides: [authProvider.overrideWith(_StudentAuth.new)],
    );
    await tester.tap(find.text('Submit 5 concepts · PIT Design'));
    await tester.pumpAndSettle();
    final dashboard = requests.singleWhere(
      (r) => r.url.path.contains('/dashboards/'),
    );
    expect(dashboard.url.queryParameters['team_id'], '7');
    final concepts = requests.singleWhere(
      (r) => r.url.path.contains('/deliverables'),
    );
    expect(concepts.url.queryParameters['stage_label'], 'PIT Design');
    expect(opened, isTrue);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StudentTeamSetupTasks)),
    );
    expect(container.read(studentTeamSelectionProvider), 7);
  });
}
