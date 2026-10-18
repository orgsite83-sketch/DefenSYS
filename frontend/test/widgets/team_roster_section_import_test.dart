import 'dart:convert';
import 'package:defensys/screens/web/admin/student_teams/team_creation_page.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _Teams extends StudentTeamsNotifier {
  @override
  StudentTeamsState build() => const StudentTeamsState();
  @override
  Future<void> refreshAfterGeneration(int count) async {}
}

void main() {
  var multipleSections = false;
  setUpAll(() => loadPreviewFonts(force: true));

  setUp(() {
    multipleSections = false;
    SharedPreferences.setMockInitialValues({});
    setApiHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('/context/')) {
          return http.Response(
            jsonEncode({
              'levels': ['3rd Year PIT'],
              'semester': {'id': 1, 'display_name': '2026-2027 | 1st Semester'},
              'events': [
                {
                  'id': 1,
                  'event_name': 'Mini Capstone',
                  'year_level': '3rd Year',
                  'is_officially_complete': false,
                },
              ],
              'assignments': [
                {'year_level': '3rd Year', 'section': 'BSIT-3A'},
                if (multipleSections) {'year_level': '3rd Year', 'section': 'BSIT-3B'},
              ],
              'can_manage_policy': true,
            }),
            200,
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'students': [],
              'sections': [
                {
                  'name': 'BSIT-3A',
                  'eligible_count': 0,
                  'total_count': 0,
                },
                if (multipleSections) {'name': 'BSIT-3B', 'eligible_count': 0, 'total_count': 0},
              ],
              'source_teams': [],
              'team_membership_policy': 'single',
              'can_manage_policy': true,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'preview_token': 'token-123',
            'ready': true,
            'rows': [
              {
                'name': 'Juan Dela Cruz',
                'username': '2024-00001',
                'previous_section': null,
                'section': 'BSIT-3A',
                'action': 'New Enrollment',
                'issues': [],
              },
            ],
          }),
          200,
        );
      }),
    );
  });

  tearDown(resetApiHttpClientForTesting);

  testWidgets('switching assigned sections updates the downloaded sample context', (tester) async {
    multipleSections = true;
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDefensysWidget(tester, const Material(child: TeamCreationPage(
      initialTab: 'generate', initialLevel: '3rd Year PIT', initialEvent: 'Mini Capstone',
    )), overrides: [...authTestOverrides(), studentTeamsProvider.overrideWith(_Teams.new)]);
    await tester.pumpAndSettle();
    expect(find.text('Section BSIT-3A'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('team-creation-section')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BSIT-3B').last);
    await tester.pumpAndSettle();
    expect(find.text('Section BSIT-3B'), findsOneWidget);
    await tester.tap(find.text('View Sheet Layout Blueprint'));
    await tester.pumpAndSettle();
    expect(find.text('defensys-class-list-bsit-3b-3rd-year.csv'), findsOneWidget);
    expect(find.text('BSIT-3B'), findsWidgets);
    expect(find.text('3rd Yr.'), findsWidgets);
    expect(find.text('1st Yr.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Team creation renders dual cards and opens section-only blueprint modal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpDefensysWidget(
      tester,
      const Material(
        child: TeamCreationPage(
          initialTab: 'generate',
          initialLevel: '3rd Year PIT',
          initialSection: 'BSIT-3A',
          initialEvent: 'Mini Capstone',
        ),
      ),
      overrides: [
        ...authTestOverrides(),
        studentTeamsProvider.overrideWith(_Teams.new),
      ],
    );

    await tester.pumpAndSettle();

    // Verify step 1 header
    expect(find.text('1. Prepare the roster'), findsOneWidget);

    // Verify left card: Official Class List Specification
    expect(find.text('Official Class List Specification'), findsOneWidget);
    expect(find.text('REGISTRAR PREAMBLE METADATA'), findsOneWidget);
    expect(find.text('ENROLLED STUDENT ROSTER (ROW 14+)'), findsOneWidget);
    expect(find.text('View Sheet Layout Blueprint'), findsOneWidget);
    expect(find.text('Download Sample Template'), findsOneWidget);

    // Verify right card: Upload Class List Files
    expect(find.text('Upload Class List Files'), findsOneWidget);
    expect(find.text('Import Class List'), findsOneWidget);
    expect(
      find.text('Drag & drop or click to choose official class list (.csv / .xlsx)'),
      findsOneWidget,
    );

    // Tap "View Sheet Layout Blueprint"
    await tester.tap(find.text('View Sheet Layout Blueprint'));
    await tester.pumpAndSettle();

    // Verify blueprint dialog renders specifically for section intake
    expect(
      find.text('Official University Class List Blueprint (Section Intake)'),
      findsOneWidget,
    );

    // Verify NO By Year Level tab or intake exists in this instructor view
    expect(find.text('By Year Level'), findsNothing);
    expect(find.text('Master Cohort Intake'), findsNothing);

    // Verify By Section intake details are shown
    expect(find.text('By Section'), findsOneWidget);
    expect(find.text('Class-Specific Intake'), findsWidgets);
    expect(find.text('Class Section: '), findsOneWidget);
    expect(find.text('BSIT-3A'), findsWidgets);
    expect(find.text('3rd Yr.'), findsWidgets);
    expect(find.text('1st Yr.'), findsNothing);
    expect(find.text('defensys-class-list-bsit-3a-3rd-year.csv'), findsOneWidget);
    expect(find.textContaining('2026-2027 | 1st Semester'), findsWidgets);
    expect(find.text('Download By Section Template (.csv)'), findsOneWidget);
    expect(find.text('Copy Sample CSV'), findsOneWidget);

    // Close the blueprint modal
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // Verify modal is dismissed and we are back on Team Creation
    expect(
      find.text('Official University Class List Blueprint (Section Intake)'),
      findsNothing,
    );
    expect(find.text('Official Class List Specification'), findsOneWidget);
  });
}
