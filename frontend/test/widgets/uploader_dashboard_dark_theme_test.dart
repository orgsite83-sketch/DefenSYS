import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/screens/web/uploader/uploader_dashboard.dart';
import 'package:defensys/widgets/buttons/defensys_theme_toggle.dart';

import '../helpers/auth_test_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setApiHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path.contains('/team-documents/')) {
          return http.Response(
            jsonEncode({
              'documents': [
                {
                  'id': 101,
                  'team': 1,
                  'team_name': 'Team Alpha',
                  'file_name': 'Project_Proposal.pdf',
                  'file_size_mb': 2.45,
                  'document_type': 'proposal',
                  'uploaded_by_name': 'Jane Doe',
                  'uploaded_at': '2026-09-24T10:00:00Z',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('/teams/')) {
          return http.Response(
            jsonEncode({
              'teams': [
                {
                  'id': 1,
                  'name': 'Team Alpha',
                  'level': 'Capstone 2',
                },
                {
                  'id': 2,
                  'name': 'Team Beta',
                  'level': 'Capstone 1',
                },
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"detail":"not found"}', 404);
      }),
    );
  });

  tearDown(() {
    resetApiHttpClientForTesting();
  });

  testWidgets('UploaderDashboard renders with Mist Dark surfaces and theme toggle',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: authTestOverrides(),
        child: MaterialApp(
          theme: AppTheme.mistDarkTheme,
          home: const UploaderDashboard(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Scaffold background matches Mist Dark token
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, equals(DefensysTokens.mistBackground));

    // Verify Theme Toggle is in the permanent sidebar
    expect(find.byType(DefensysThemeToggle), findsOneWidget);

    // Verify Sidebar navigation items
    expect(find.text('All Teams'), findsOneWidget);
    expect(find.text('All Documents'), findsOneWidget);
    expect(find.text('TEAMS'), findsOneWidget);

    // Verify loaded team names appear
    expect(find.text('Team Alpha'), findsWidgets);
    expect(find.text('Team Beta'), findsWidgets);

    // Verify search bar exists and is styled
    expect(find.byType(TextField), findsOneWidget);
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.decoration?.fillColor, equals(DefensysTokens.mistSurface));
  });
}
