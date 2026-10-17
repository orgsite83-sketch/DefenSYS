import 'dart:convert';
import 'package:defensys/screens/web/admin/student_teams/team_creation_page.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/screens/web/shared/team_deliverables/team_deliverables_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

class _Deliverables extends CapstoneDeliverablesNotifier {
  @override
  CapstoneDeliverablesState build() => const CapstoneDeliverablesState(
    scope: 'pit',
    stageOptions: ['PIT Design'],
    selectedStage: 'PIT Design',
    counts: {'deliverables_configured': true},
    teams: [
      {
        'id': 1,
        'name': 'Existing Team',
        'section': 'BSIT-2A',
        'year_level': '2nd Year',
        'project_title': 'Existing Project',
        'members': [],
        'stages': [],
        'selected_stage': {
          'stage_label': 'PIT Design',
          'pre': [],
          'post': [],
          'vault': [],
        },
      },
    ],
  );
  @override
  Future<void> fetchDeliverables({
    String? search,
    String? selectedStage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
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
        if (request.url.path.endsWith('/create/')) {
          return http.Response('{"created_count":1,"team_ids":[9]}', 201);
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
          color: const Color(0xFFF7FAFC),
          child: TeamCreationPage(
            initialTab: tab,
            initialLevel: '2nd Year PIT',
            initialSection: 'BSIT-2A',
            initialEvent: 'PIT Design',
          ),
        ),
      ),
      overrides: [
        ...authTestOverrides(),
        studentTeamsProvider.overrideWith(_Teams.new),
      ],
    );
  }

  testWidgets(
    'PIT page actions are above the existing team list in the agreed order',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDefensysWidget(
        tester,
        const RepaintBoundary(
          key: ValueKey('toolbar-capture'),
          child: Material(
            color: Color(0xFFF7FAFC),
            child: TeamDeliverablesScreen(
              initialScope: 'pit',
              isPitInstructor: true,
              pitYearLevel: '2nd Year',
              pitSection: 'BSIT-2A',
            ),
          ),
        ),
        overrides: [
          ...authTestOverrides(),
          capstoneDeliverablesProvider.overrideWith(_Deliverables.new),
        ],
      );
      expect(find.text('Teams (1)'), findsOneWidget);
      expect(find.text('Export teams'), findsOneWidget);
      final refresh = tester.getCenter(find.byTooltip('Refresh'));
      final importPoint = tester.getCenter(find.text('Import'));
      final create = tester.getCenter(find.text('Team Creation'));
      expect(refresh.dx, lessThan(importPoint.dx));
      expect(importPoint.dx, lessThan(create.dx));
      expect(create.dy, lessThan(tester.getTopLeft(find.text('Teams (1)')).dy));
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('toolbar-capture')),
        'team-creation/pit-toolbar',
      );
    },
  );

  testWidgets('existing roster can preview without a class-list upload', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Import Class List'), findsOneWidget);
    expect(find.text('BSIT-2A · 2/2 available'), findsOneWidget);
    await tester.tap(find.text('Preview teams'));
    await tester.pumpAndSettle();
    expect(find.text('Create 1 team'), findsOneWidget);
    expect(requests.where((r) => r.url.path.contains('/roster/')), isEmpty);
    expect(requests.where((r) => r.url.path.endsWith('/create/')), isEmpty);
  });

  testWidgets(
    'switching tabs retains the generated preview and edited team name',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Preview teams'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Draft Team'),
        'Reviewed Team',
      );
      await tester.tap(find.byKey(const ValueKey('creation-tab-0')));
      await tester.pumpAndSettle();
      expect(find.text('Import prepared teams'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('creation-tab-1')));
      await tester.pumpAndSettle();
      expect(find.text('Reviewed Team'), findsOneWidget);
      expect(find.text('Create 1 team'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST').length, 1);
    },
  );

  testWidgets(
    'empty section still offers class-list import before teams or events exist',
    (tester) async {
      noEvents = true;
      emptyRoster = true;
      await pump(tester);
      expect(find.text('Import Class List'), findsOneWidget);
      final preview = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Preview teams'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(preview.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'import shortcut tab uses prepared-team upload with no class-list prerequisite',
    (tester) async {
      await pump(tester, tab: 'import');
      expect(find.text('Import prepared teams'), findsOneWidget);
      expect(find.text('Upload CSV / Excel'), findsOneWidget);
      expect(find.text('Import Class List'), findsNothing);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('creation-capture')),
        'team-creation/import',
      );
    },
  );

  testWidgets(
    'generation page fits a small laptop and preserves independent leader choice',
    (tester) async {
      await pump(tester, size: const Size(900, 680));
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('creation-capture')),
        'team-creation/generate',
      );
      final leader = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Randomize leaders',
      );
      await tester.ensureVisible(leader);
      await tester.tap(leader);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose leaders in preview').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview teams'));
      await tester.pumpAndSettle();
      final request = jsonDecode(
        requests.singleWhere((r) => r.method == 'POST').body,
      );
      expect(request['leader_method'], 'manual');
      expect(request['method'], 'random');
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('creation-capture')),
        'team-creation/preview',
      );
    },
  );

  testWidgets(
    'toolbar shortcuts open the same page with section and event context',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/faculty/deliverables',
        routes: [
          GoRoute(
            path: '/faculty/deliverables',
            builder: (context, state) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => openTeamCreation(
                    context,
                    importTab: true,
                    level: '2nd Year PIT',
                    section: 'BSIT-2A',
                    event: 'PIT Design',
                  ),
                  child: const Text('Import shortcut'),
                ),
              ),
            ),
            routes: [
              GoRoute(
                path: 'creation',
                builder: (_, state) => Scaffold(
                  body: TeamCreationPage(
                    initialTab: state.uri.queryParameters['tab']!,
                    initialLevel: state.uri.queryParameters['level'],
                    initialSection: state.uri.queryParameters['section'],
                    initialEvent: state.uri.queryParameters['event'],
                  ),
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...authTestOverrides(),
            studentTeamsProvider.overrideWith(_Teams.new),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import shortcut'));
      await tester.pumpAndSettle();
      expect(
        GoRouterState.of(
          tester.element(find.byType(TeamCreationPage)),
        ).uri.path,
        '/faculty/deliverables/creation',
      );
      expect(find.text('Import prepared teams'), findsOneWidget);
      expect(find.text('Section BSIT-2A'), findsOneWidget);
      expect(find.text('PIT Design'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('creation-tab-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview teams'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create 1 team'));
      await tester.pumpAndSettle();
      expect(find.text('Import shortcut'), findsOneWidget);
      expect(find.byType(TeamCreationPage), findsNothing);
      expect(requests.where((r) => r.url.path.endsWith('/create/')).length, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
