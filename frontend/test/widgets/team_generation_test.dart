import 'dart:convert';

import 'package:defensys/screens/web/admin/student_teams/dialogs/generate_teams_dialog.dart';
import 'package:defensys/screens/web/admin/student_teams/dialogs/create_team_modal.dart';
import 'package:defensys/screens/web/admin/student_teams/components/student_teams_toolbar.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _Teams extends StudentTeamsNotifier {
  @override
  StudentTeamsState build() => const StudentTeamsState();
  @override
  Future<void> refreshAfterGeneration(int count) async {}
}

void main() {
  testWidgets(
    'roster managers retain bulk import and template actions without generation',
    (tester) async {
      var imports = 0;
      await pumpDefensysWidget(
        tester,
        StudentTeamsHeaderActions(
          isPitInstructor: false,
          canTapActions: true,
          onCreateTeam: () {},
          onDownloadTemplate: () {},
          onBulkImport: () => imports++,
        ),
      );
      expect(find.text('Import teams'), findsOneWidget);
      expect(find.text('Download template'), findsOneWidget);
      expect(find.text('Team Creation'), findsNothing);
      expect(find.text('Generate Teams'), findsNothing);
      await tester.tap(find.text('Import teams'));
      expect(imports, 1);
    },
  );
  setUpAll(() => loadPreviewFonts(force: true));
  const students = [
    {
      'id': 1,
      'name': 'Ana Cruz',
      'username': '2026-001',
      'section': 'BSIT-2A',
      'eligible': true,
    },
    {
      'id': 2,
      'name': 'Ben Santos',
      'username': '2026-002',
      'section': 'BSIT-2A',
      'eligible': true,
    },
  ];
  final options = {
    'students': students,
    'sections': [
      {'name': 'BSIT-2A', 'eligible_count': 2, 'total_count': 2},
    ],
    'source_teams': [],
    'event_id': 8,
    'team_membership_policy': 'single',
  };
  late List<http.Request> requests;
  setUp(() {
    options['team_membership_policy'] = 'single';
    SharedPreferences.setMockInitialValues({});
    requests = [];
    setApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(jsonEncode(options), 200);
        }
        if (request.url.path.endsWith('/policy/')) {
          options['team_membership_policy'] = jsonDecode(
            request.body,
          )['team_membership_policy'];
          return http.Response('{}', 200);
        }
        if (request.url.path.endsWith('/create/')) {
          return http.Response('{"created_count":1}', 201);
        }
        return http.Response(
          jsonEncode({
            'students': students,
            'preview_token': 'signed-preview',
            'teams': [
              {
                'name': 'BSIT-2A Team 01',
                'section': 'BSIT-2A',
                'member_ids': [1, 2],
                'leader_id': 1,
              },
            ],
          }),
          200,
        );
      }),
    );
  });
  tearDown(resetApiHttpClientForTesting);

  Future<void> pump(
    WidgetTester tester, {
    Size viewport = const Size(1100, 850),
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDefensysWidget(
      tester,
      const RepaintBoundary(
        key: ValueKey('formation-preview'),
        child: GenerateTeamsDialog(
          levels: ['2nd Year PIT'],
          initialLevel: '2nd Year PIT',
          events: [
            {'id': 8, 'event_name': 'PIT Design', 'year_level': '2nd Year'},
          ],
        ),
      ),
      overrides: [
        ...authTestOverrides(),
        studentTeamsProvider.overrideWith(_Teams.new),
      ],
    );
  }

  testWidgets('sole PIT instructor is displayed without a reviewer selection', (
    tester,
  ) async {
    options['concept_contexts'] = [
      {'label': 'PIT Design'},
    ];
    options['system_reviewers'] = [
      {'id': 1, 'name': 'Ana Instructor'},
    ];
    options['section_instructors'] = {
      'BSIT-2A': [
        {
          'faculty_id': 1,
          'faculty__first_name': 'Ana',
          'faculty__last_name': 'Instructor',
        },
      ],
    };
    addTearDown(() {
      options.remove('concept_contexts');
      options.remove('system_reviewers');
      options.remove('section_instructors');
    });
    await pump(tester, viewport: const Size(1200, 1100));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Independent projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shared section system').last);
    await tester.pumpAndSettle();
    expect(find.text('Ana Instructor'), findsOneWidget);
    expect(find.text('System faculty reviewer'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preview remains read-only and reviewed leader is sent on creation',
    (tester) async {
      await pump(tester);
      expect(
        requests.last.url.queryParameters.containsKey('event_name'),
        isFalse,
      );
      expect(find.text('BSIT-2A · 2/2 available'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review teams'));
      await tester.pumpAndSettle();
      expect(find.text('Review generated teams'), findsOneWidget);
      expect(requests.where((r) => r.url.path.endsWith('/create/')), isEmpty);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ben Santos').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create 1 team'));
      await tester.pumpAndSettle();
      final body = jsonDecode(
        requests.singleWhere((r) => r.url.path.endsWith('/create/')).body,
      );
      expect(body['preview_token'], 'signed-preview');
      expect(body.containsKey('event_name'), isFalse);
      expect(body['teams'][0]['leader_id'], 2);
    },
  );

  testWidgets(
    'ordinary generation uses the current roster without selecting an event',
    (tester) async {
      await pump(tester);
      expect(find.text('PIT event (optional)'), findsNothing);
      expect(find.text('One team in this event'), findsNothing);
      expect(
        requests.last.url.queryParameters.containsKey('event_name'),
        isFalse,
      );
    },
  );

  testWidgets('generation settings and preview fit a small laptop viewport', (
    tester,
  ) async {
    await pump(tester, viewport: const Size(900, 680));
    expect(tester.takeException(), isNull);
    await capturePreview(
      tester,
      find.byKey(const ValueKey('formation-preview')),
      'team-formation/settings',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review teams'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Create 1 team'), findsOneWidget);
    await capturePreview(
      tester,
      find.byKey(const ValueKey('formation-preview')),
      'team-formation/preview',
    );
  });

  testWidgets('roster manager chooser offers manual creation and bulk import', (
    tester,
  ) async {
    var imported = false;
    await pumpDefensysWidget(
      tester,
      Consumer(
        builder: (context, ref, _) => FilledButton(
          onPressed: () => showCreateTeamModal(
            context: context,
            ref: ref,
            state: const StudentTeamsState(),
            isCapstoneAdmin: true,
            isPitLeadManager: false,
            pitLeadYear: null,
            onBulkImport: () => imported = true,
          ),
          child: const Text('Open create teams'),
        ),
      ),
      overrides: authTestOverrides(),
    );
    await tester.tap(find.text('Open create teams'));
    await tester.pumpAndSettle();
    expect(find.text('Generate from students'), findsNothing);
    expect(find.text('Create manually'), findsOneWidget);
    await tester.tap(find.text('Bulk import'));
    await tester.pumpAndSettle();
    expect(imported, isTrue);
  });
}
