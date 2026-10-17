import 'dart:convert';

import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/widgets/student_team_setup_tasks.dart';
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
}
