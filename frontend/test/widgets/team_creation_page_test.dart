import 'package:defensys/utils/import/team_creation_draft.dart';
import 'package:defensys/theme/app_theme.dart';
import 'dart:convert';
import 'package:defensys/screens/web/admin/student_teams/team_creation_page.dart';
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
  setUpAll(() => loadPreviewFonts(force: true));
  late List<http.Request> requests;
  late bool noEvents, emptyRoster;
  const roster = [
    {
      'id': 1,
      'name': 'Ana Cruz',
      'username': '2026-001',
      'section': 'BSIT-2A',
      'eligible': true,
      'assigned': false,
    },
    {
      'id': 2,
      'name': 'Ben Santos',
      'username': '2026-002',
      'section': 'BSIT-2A',
      'eligible': true,
      'assigned': false,
    },
  ];
  const event = {
    'id': 8,
    'event_name': 'PIT Design',
    'year_level': '2nd Year',
    'is_officially_complete': false,
  };
  setUp(() {
    noEvents = false;
    emptyRoster = false;
    requests = [];
    SharedPreferences.setMockInitialValues({});
    setApiHttpClientForTesting(
      MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/context/')) {
          return http.Response(
            jsonEncode({
              'levels': ['2nd Year PIT'],
              'semester': {'id': 1, 'display_name': '2026-2027 | 1st Semester'},
              'events': noEvents ? [] : [event],
              'assignments': [
                {'year_level': '2nd Year', 'section': 'BSIT-2A'},
              ],
              'can_manage_policy': false,
            }),
            200,
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'students': emptyRoster ? [] : roster,
              'sections': [
                {
                  'name': 'BSIT-2A',
                  'eligible_count': emptyRoster ? 0 : 2,
                  'total_count': emptyRoster ? 0 : 2,
                },
              ],
              'source_teams': [],
              'team_membership_policy': 'single',
              'can_manage_policy': false,
            }),
            200,
          );
        }
        final body = jsonDecode(request.body) as Map;
        if (request.url.path.endsWith('/import/')) {
          return http.Response(
            jsonEncode({
              'ready': true,
              'preview_token': 'signed-import',
              'rows': [
                for (final row in body['teams'])
                  {
                    'ready': true,
                    'team_name': row['team_name'],
                    'section': row['section'],
                    'member_count': 2,
                    'action': 'create',
                    'issues': [],
                    'warnings': [],
                  },
              ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/create/')) {
          return http.Response(
            '{"created_count":1,"updated_count":0,"team_ids":[9]}',
            201,
          );
        }
        return http.Response(
          jsonEncode({
            'preview_token': 'signed-preview',
            'students': roster,
            'teams': [
              {
                'name': 'Draft Team',
                'section': 'BSIT-2A',
                'member_ids': [1, 2],
                'leader_id': body['leader_method'] == 'manual' ? null : 1,
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
    String tab = 'generate',
    ThemeData? theme,
    Size size = const Size(1000, 760),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpDefensysWidget(
      tester,
      RepaintBoundary(
        key: const ValueKey('creation-capture'),
        child: Material(
          color: theme?.scaffoldBackgroundColor ?? const Color(0xFFF7FAFC),
          child: TeamCreationPage(
            initialTab: tab,
            initialLevel: '2nd Year PIT',
            initialSection: 'BSIT-2A',
          ),
        ),
      ),
      theme: theme,
      overrides: [
        ...authTestOverrides(),
        studentTeamsProvider.overrideWith(_Teams.new),
      ],
    );
  }

  Future<void> previewTeams(WidgetTester tester) async {
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Project architecture'), findsOneWidget);
    await tester.tap(find.text('Review teams'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'generation opens one flow and creates a current roster without an event choice',
    (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('creation-tab-0')), findsNothing);
      expect(find.text('Roster & grouping'), findsOneWidget);
      expect(find.text('Import or update class list'), findsOneWidget);
      expect(requests.where((r) => r.url.path.contains('/import/')), isEmpty);
      await previewTeams(tester);
      expect(find.text('Create 1 team'), findsOneWidget);
      final body =
          jsonDecode(requests.singleWhere((r) => r.method == 'POST').body)
              as Map;
      expect(body.containsKey('event_name'), isFalse);
      expect(requests.where((r) => r.url.path.endsWith('/create/')), isEmpty);
    },
  );

  testWidgets(
    'Back preserves reviewed team edits without regenerating unchanged grouping',
    (tester) async {
      await pump(tester);
      await previewTeams(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Draft Team'),
        'Reviewed Team',
      );
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review teams'));
      await tester.pumpAndSettle();
      expect(find.text('Reviewed Team'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST').length, 1);
    },
  );

  testWidgets(
    'generation draft resumes reviewed names and remains explicitly submitted',
    (tester) async {
      await pump(tester);
      await previewTeams(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Draft Team'),
        'Saved Team',
      );
      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await pump(tester);
      await tester.tap(find.text('Resume draft'));
      await tester.pumpAndSettle();
      expect(find.text('Saved Team'), findsOneWidget);
      expect(requests.where((r) => r.url.path.endsWith('/create/')), isEmpty);
    },
  );

  testWidgets('empty roster still offers class-list import without an event', (
    tester,
  ) async {
    noEvents = true;
    emptyRoster = true;
    await pump(tester);
    expect(find.text('Import or update class list'), findsOneWidget);
    final next = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Continue'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(next.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'import opens upload with its own steps and no generation controls',
    (tester) async {
      await pump(tester, tab: 'import');
      expect(find.text('Upload roster'), findsOneWidget);
      expect(find.text('Upload CSV / Excel'), findsOneWidget);
      expect(find.text('Current roster'), findsOneWidget);
      expect(find.text('Import Class List'), findsNothing);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('creation-capture')),
        'phase-two-import-light',
      );
    },
  );

  testWidgets(
    'prepared import resumes rows, configures, reviews and commits only on final action',
    (tester) async {
      await TeamCreationDraftStore(
        '1',
        'import:1:2nd Year PIT:BSIT-2A:current',
      ).save({
        'rows': [
          {
            'team_name': 'Prepared team',
            'section': 'BSIT-2A',
            'member_ids': ['2026-001', '2026-002'],
            'leader_id': '2026-001',
            'project_title': 'Assigned project',
          },
        ],
      });
      await pump(tester, tab: 'import');
      await tester.tap(find.text('Resume draft'));
      await tester.pumpAndSettle();
      expect(find.text('Project architecture'), findsOneWidget);
      await tester.tap(find.text('Review import'));
      await tester.pumpAndSettle();
      expect(find.text('Import 1 teams'), findsOneWidget);
      expect(requests.where((r) => r.url.path.endsWith('/create/')), isEmpty);
      final preview =
          jsonDecode(
                requests
                    .singleWhere((r) => r.url.path.endsWith('/import/'))
                    .body,
              )
              as Map;
      expect(preview['teams'][0]['project_title'], 'Assigned project');
      expect(preview.containsKey('event_name'), isFalse);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('creation-capture')),
        'phase-two-import-review',
      );
      // Commit is covered through the routed page in production; this isolated
      // page has no Navigator return target. The final button remains explicit.
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'generation grouping and project setup fit a laptop in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        await pump(
          tester,
          size: const Size(1100, 800),
          theme: dark ? AppTheme.mistDarkTheme : null,
        );
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('creation-capture')),
          'phase-two-generate-${dark ? 'dark' : 'light'}',
        );
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('creation-capture')),
          'phase-two-project-${dark ? 'dark' : 'light'}',
        );
      },
    );
  }

  testWidgets('import upload and step labels fit a phone width', (
    tester,
  ) async {
    await pump(tester, tab: 'import', size: const Size(390, 844));
    expect(tester.takeException(), isNull);
    await capturePreview(
      tester,
      find.byKey(const ValueKey('creation-capture')),
      'phase-two-import-mobile',
    );
  });
}
