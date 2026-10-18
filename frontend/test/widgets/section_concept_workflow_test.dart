import 'dart:convert';

import 'package:defensys/screens/web/admin/student_teams/dialogs/generate_teams_dialog.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/widgets/repository/section_concept_workspace.dart';
import 'package:defensys/widgets/repository/concept_workspace.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/screens/app/student/section_integration_tab.dart';
import 'package:defensys/screens/web/admin/student_teams/components/student_teams_grid.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/widgets/student_team_setup_tasks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _Student extends AuthNotifier {
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: const {'id': 1, 'role': 'student'},
  );
}

class _IntegrationTeams extends StudentTeamsNotifier {
  @override
  StudentTeamsState build() => const StudentTeamsState();

  @override
  Future<void> fetchTeams({
    String? workspace,
    String? search,
    String? level,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? eventName,
    bool clearEventName = false,
    bool clearYearLevel = false,
    String? successMessage,
  }) async {}
}

Map<String, dynamic> projectFixture() => {
  'id': 7,
  'section': 'BSIT-2A',
  'stage_label': 'PIT Design',
  'round': 1,
  'round_id': 12,
  'review_token': 'reviewed-current-content',
  'project_manager_name': 'Ana Cruz',
  'reviewer_name': 'Prof. Reyes',
  'verdict': '',
  'remarks': '',
  'endorsed': true,
  'selected_key': '',
  'systems': [
    for (var i = 1; i <= 3; i++)
      {
        'key': 'c$i',
        'title': [
          'Campus Management',
          'Clinic Management',
          'Inventory Management',
        ][i - 1],
        'confirmed': true,
        'papers': [],
      },
  ],
  'teams': [
    {
      'id': 5,
      'name': 'Team Alpha',
      'leader_id': 1,
      'verdict': '',
      'schedule_id': null,
      'can_confirm_names': true,
      'concepts': [
        for (var i = 1; i <= 3; i++)
          {
            'key': 'c$i',
            'title': 'Module $i',
            'system_title': [
              'Campus Management',
              'Clinic Management',
              'Inventory Management',
            ][i - 1],
            'faculty_confirmed': true,
            'decision': '',
          },
      ],
    },
  ],
  'history': [],
  'available_schedules': [],
  'hearing_schedule_ids': [],
};

void main() {
  setUpAll(() => loadPreviewFonts(force: true));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(resetApiHttpClientForTesting);

  testWidgets(
    'student integration uses one list response and obeys paper upload permissions',
    (tester) async {
      final project = projectFixture()
        ..['can_upload'] = true
        ..['can_manage'] = true;
      for (final system in (project['systems'] as List).cast<Map>()) {
        system['can_upload'] = false;
      }
      final requests = <String>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url.path);
          return http.Response(
            jsonEncode({
              'projects': [project],
              'tasks': [],
            }),
            200,
          );
        }),
      );
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpDefensysWidget(
        tester,
        const SectionIntegrationTab(
          studentData: {
            'student': {'is_project_manager': true},
            'team': {'id': 5, 'section': 'BSIT-2A'},
          },
        ),
        overrides: [
          authProvider.overrideWith(_Student.new),
          studentTeamsProvider.overrideWith(_IntegrationTeams.new),
        ],
      );
      expect(requests, ['/api/repository/section-concepts/']);
      expect(find.text('Upload Concept Paper (PDF)'), findsNothing);
      expect(find.textContaining('Campus Management'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'student project manager can upload a paper only when the API permits it',
    (tester) async {
      final project = projectFixture();
      (project['systems'] as List).first['can_upload'] = true;
      setApiHttpClientForTesting(
        MockClient((request) async => http.Response(jsonEncode(project), 200)),
      );
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpDefensysWidget(
        tester,
        const SectionIntegrationTab(
          studentData: {
            'student': {'is_project_manager': true},
            'team': {'id': 5, 'section': 'BSIT-2A', 'section_project_id': 7},
          },
        ),
        overrides: [
          authProvider.overrideWith(_Student.new),
          studentTeamsProvider.overrideWith(_IntegrationTeams.new),
        ],
      );
      expect(find.text('Upload Concept Paper (PDF)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'team list exposes configured shared systems and module proposal counts',
    (tester) async {
      final project = projectFixture();
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: GroupedSectionView(
            state: StudentTeamsState(
              teams: [
                {
                  'id': 5,
                  'name': 'Team Alpha',
                  'section': 'BSIT-2A',
                  'level': '2nd Year PIT',
                  'project_pending': true,
                  'leader_name': 'Ana Cruz',
                  'pit_event_name': 'PIT Design',
                  'defense_context': {
                    'event_label': 'PIT Design',
                    'concept_workflow': {
                      'section_project_id': 7,
                      'system_concepts': project['systems'],
                      'concepts': project['teams'][0]['concepts'],
                    },
                  },
                },
              ],
            ),
            isPit: true,
            searchQuery: 'Alpha',
            onOpenTeamDetail: (_) {},
          ),
        ),
        overrides: authTestOverrides(),
      );
      expect(find.textContaining('3 modules proposed'), findsOneWidget);
      expect(find.textContaining('A. Campus Management'), findsOneWidget);
      expect(find.byType(SectionConceptWorkspace), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  Map<String, dynamic> reviewFixture() {
    final project = projectFixture()
      ..['endorsed'] = false
      ..['can_review'] = true
      ..['can_edit_names'] = true
      ..['can_endorse'] = false;
    for (final system in (project['systems'] as List).cast<Map>()) {
      system['papers'] = [
        {
          'id': system['key'] == 'c1'
              ? 41
              : system['key'] == 'c2'
              ? 42
              : 43,
          'file_name': '${system['title']} concept paper.pdf',
          'revision': 2,
          'is_current': true,
          'status': system['key'] == 'c1' ? 'pending' : 'accepted',
          'feedback': '',
          'file_url': '/api/repository/section-concepts/7/papers/41/',
        },
      ];
    }
    project['review_progress'] = {'papers_accepted': 2, 'names_confirmed': 3};
    return project;
  }

  testWidgets(
    'instructor reviews shared papers inside the existing concept dossier',
    (tester) async {
      final project = reviewFixture();
      final actions = <Map<String, dynamic>>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'POST') {
            final action = jsonDecode(request.body) as Map<String, dynamic>;
            actions.add(action);
            if (action['action'] == 'review') {
              (project['systems'] as List).first['papers'][0]['status'] =
                  'accepted';
              project['can_endorse'] = true;
              project['review_progress']['papers_accepted'] = 3;
            } else if (action['action'] == 'endorse') {
              project['endorsed'] = true;
              project['can_endorse'] = false;
            }
          }
          return http.Response(jsonEncode(project), 200);
        }),
      );
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: ConceptWorkspace(
            teamId: 5,
            stageLabel: 'PIT Design',
            stage: {
              'concept_workflow': {
                'enabled': true,
                'section_project_id': 7,
                'round': 1,
                'status': 'concept_review_pending',
                'concepts': project['teams'][0]['concepts'],
              },
            },
          ),
        ),
        overrides: authTestOverrides(),
      );
      expect(find.text('Team module concepts'), findsOneWidget);
      await tester.tap(find.text('Shared system'));
      await tester.pumpAndSettle();
      expect(find.text('Shared system review'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
      final endorseButton = find.ancestor(
        of: find.text('Endorse shared papers'),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      );
      expect(
        tester.widget<ButtonStyleButton>(endorseButton.first).onPressed,
        isNull,
      );
      await tester.tap(find.text('Accept paper'));
      await tester.pumpAndSettle();
      expect(actions.single['paper_id'], 41);
      expect(actions.single['round_id'], 12);
      expect(actions.single['review_token'], 'reviewed-current-content');
      await tester.tap(find.text('Endorse shared papers'));
      await tester.pumpAndSettle();
      expect(actions.last['action'], 'endorse');
      expect(find.text('Endorsed for hearing'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('embedded review fits desktop and phone in both themes', (
    tester,
  ) async {
    final project = reviewFixture();
    setApiHttpClientForTesting(
      MockClient((request) async => http.Response(jsonEncode(project), 200)),
    );
    const previewKey = ValueKey('inline-system-review-preview');
    for (final dark in [false, true]) {
      for (final size in [const Size(1280, 900), const Size(390, 1000)]) {
        await tester.binding.setSurfaceSize(size);
        await pumpDefensysWidget(
          tester,
          const RepaintBoundary(
            key: previewKey,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: SectionConceptWorkspace(projectId: 7, embedded: true),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          overrides: authTestOverrides(),
        );
        expect(tester.takeException(), isNull);
        await capturePreview(
          tester,
          find.byKey(previewKey),
          'inline-system-review-${size.width == 1280 ? 'desktop' : 'mobile'}-${dark ? 'dark' : 'light'}',
        );
        await tester.tap(find.text('System B'));
        await tester.pumpAndSettle();
        expect(find.text('Clinic Management'), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'lead sees proposal names before expanding review without an extra list request',
    (tester) async {
      final requests = <String>[];
      final project = reviewFixture()
        ..['can_review'] = false
        ..['can_edit_names'] = false;
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url.path);
          return http.Response(jsonEncode(project), 200);
        }),
      );
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: SectionConceptOverview(
            projectId: 7,
            stageLabel: 'PIT Design',
            systems: (project['systems'] as List).cast<Map<String, dynamic>>(),
          ),
        ),
        overrides: authTestOverrides(),
      );
      expect(find.textContaining('A. Campus Management'), findsOneWidget);
      expect(requests, isEmpty);
      await tester.tap(find.text('Shared system proposals · PIT Design'));
      await tester.pumpAndSettle();
      expect(requests, ['/api/repository/section-concepts/7/']);
      expect(find.text('Accept paper'), findsNothing);
      expect(find.text('Endorse shared papers'), findsNothing);
      expect(find.text('Read paper'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sections without a shared project have no shared-system shortcut',
    (tester) async {
      setApiHttpClientForTesting(
        MockClient(
          (request) async =>
              http.Response(jsonEncode({'projects': [], 'tasks': []}), 200),
        ),
      );
      await pumpDefensysWidget(
        tester,
        const SectionConceptHub(section: 'BSIT-2A'),
        overrides: authTestOverrides(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shared system concepts'), findsNothing);
    },
  );

  testWidgets('section workspace fits desktop and narrow mobile screens', (
    tester,
  ) async {
    final project = projectFixture()
      ..['can_manage'] = true
      ..['can_edit_names'] = true
      ..['can_review'] = true;
    setApiHttpClientForTesting(
      MockClient((request) async => http.Response(jsonEncode(project), 200)),
    );
    const previewKey = ValueKey('shared-section-preview');
    for (final size in [const Size(1280, 900), const Size(390, 844)]) {
      await tester.binding.setSurfaceSize(size);
      await pumpDefensysWidget(
        tester,
        const RepaintBoundary(
          key: previewKey,
          child: SectionConceptWorkspace(projectId: 7),
        ),
        overrides: authTestOverrides(),
      );
      expect(tester.takeException(), isNull);
      await capturePreview(
        tester,
        find.byKey(previewKey),
        'shared-system-${size.width == 1280 ? 'desktop' : 'mobile'}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('a project manager who leads a team sees two distinct tasks', (
    tester,
  ) async {
    setApiHttpClientForTesting(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'section_tasks': [
              {
                'project_id': 7,
                'section': 'BSIT-2A',
                'stage_label': 'PIT Design',
                'title': 'Submit three shared system concept papers',
                'status': 'action_required',
              },
            ],
            'teams': [
              {
                'id': 5,
                'name': 'Team Alpha',
                'section': 'BSIT-2A',
                'event_name': 'PIT Design',
                'scope': 'pit',
                'year_level': '2nd Year',
                'needs_name': false,
                'concept_tasks': [
                  {
                    'stage_label': 'PIT Design',
                    'required_count': 3,
                    'mode': 'proposals',
                    'shared_system': true,
                  },
                ],
              },
            ],
          }),
          200,
        ),
      ),
    );
    await pumpDefensysWidget(
      tester,
      StudentTeamSetupTasks(onOpenRepository: () {}),
      overrides: [authProvider.overrideWith(_Student.new)],
    );
    expect(
      find.text('Submit three shared system concept papers'),
      findsOneWidget,
    );
    expect(
      find.text('Submit 3 corresponding module concepts · PIT Design'),
      findsOneWidget,
    );
  });

  testWidgets(
    'section participants can read proposals without faculty controls',
    (tester) async {
      final project = projectFixture();
      (project['teams'] as List).first['can_confirm_names'] = false;
      setApiHttpClientForTesting(
        MockClient((request) async => http.Response(jsonEncode(project), 200)),
      );
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpDefensysWidget(
        tester,
        const SectionConceptWorkspace(projectId: 7),
        overrides: [authProvider.overrideWith(_Student.new)],
      );
      expect(find.text('System A · Campus Management'), findsOneWidget);
      expect(find.text('Confirm system names'), findsNothing);
      expect(find.text('Endorse shared papers'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'faculty confirms three module names with their shared system mapping',
    (tester) async {
      final project = projectFixture();
      Map<String, dynamic>? posted;
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'POST') {
            posted = jsonDecode(request.body) as Map<String, dynamic>;
          }
          return http.Response(jsonEncode(project), 200);
        }),
      );
      await pumpDefensysWidget(
        tester,
        const SectionConceptWorkspace(projectId: 7),
        overrides: authTestOverrides(),
      );
      await tester.scrollUntilVisible(
        find.text('Confirm module names'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Confirm module names'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(3));
      await tester.tap(find.text('Save names'));
      await tester.pumpAndSettle();
      expect(posted?['action'], 'confirm_modules');
      expect(posted?['team_id'], 5);
      expect((posted?['concepts'] as List).map((c) => c['key']), [
        'c1',
        'c2',
        'c3',
      ]);
      expect(posted?['round_id'], 12);
    },
  );

  testWidgets(
    'chair selects one shared system without submitting team outcomes',
    (tester) async {
      final project = projectFixture()..['can_decide'] = true;
      final actions = <Map<String, dynamic>>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'POST') {
            actions.add(jsonDecode(request.body) as Map<String, dynamic>);
          }
          return http.Response(jsonEncode(project), 200);
        }),
      );
      await pumpDefensysWidget(
        tester,
        const SectionConceptWorkspace(projectId: 7),
        overrides: authTestOverrides(),
      );
      await tester.scrollUntilVisible(
        find.text('Record section system decision'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Record section system decision'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clinic Management').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record decision'));
      await tester.pumpAndSettle();
      expect(actions, hasLength(1));
      expect(actions.single['action'], 'decide');
      expect(actions.single['review_token'], 'reviewed-current-content');
      final decisions = actions.single['concepts'] as List;
      expect(
        decisions.singleWhere((c) => c['decision'] == 'approved')['key'],
        'c2',
      );
      expect(
        decisions.where((c) => c['decision'] == 'not_selected'),
        hasLength(2),
      );
    },
  );

  testWidgets(
    'shared revision uploads are offered only for the selected system',
    (tester) async {
      final project = projectFixture()
        ..['selected_key'] = 'c2'
        ..['verdict'] = 'approved_with_revisions'
        ..['shared_revisions_pending'] = true;
      final systems = project['systems'] as List;
      systems[1]['can_upload'] = true;
      systems[1]['papers'] = [
        {
          'id': 21,
          'revision': 1,
          'file_name': 'clinic.pdf',
          'is_current': true,
          'status': 'accepted',
          'feedback': '',
        },
      ];
      setApiHttpClientForTesting(
        MockClient((request) async => http.Response(jsonEncode(project), 200)),
      );
      await pumpDefensysWidget(
        tester,
        const SectionConceptWorkspace(projectId: 7),
        overrides: [authProvider.overrideWith(_Student.new)],
      );
      expect(find.text('Upload revised paper'), findsOneWidget);
      expect(find.text('Upload concept paper'), findsNothing);
      expect(
        find.textContaining('Module approvals cannot complete progression'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'generation preview includes the PM, faculty reviewer and shared workflow',
    (tester) async {
      Map<String, dynamic>? preview;
      final options = {
        'students': [
          {'id': 1, 'name': 'Ana Cruz', 'section': 'BSIT-2A', 'eligible': true},
        ],
        'sections': [
          {'name': 'BSIT-2A', 'eligible_count': 1, 'total_count': 1},
        ],
        'source_teams': [],
        'event_id': 8,
        'team_membership_policy': 'single',
        'concept_contexts': [
          {'label': 'PIT Design'},
        ],
        'system_reviewers': [
          {'id': 9, 'name': 'Prof. Reyes'},
        ],
      };
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(jsonEncode(options), 200);
          }
          preview = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'teams': [
                {
                  'name': 'Team Alpha',
                  'section': 'BSIT-2A',
                  'leader_id': 1,
                  'member_ids': [1],
                },
              ],
              'students': options['students'],
              'preview_token': 'signed-preview',
            }),
            200,
          );
        }),
      );
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpDefensysWidget(
        tester,
        const GenerateTeamsDialog(
          levels: ['2nd Year PIT'],
          initialLevel: '2nd Year PIT',
          events: [
            {'id': 8, 'year_level': '2nd Year', 'event_name': 'PIT Design'},
          ],
        ),
        overrides: authTestOverrides(),
      );
      await tester.scrollUntilVisible(
        find.text('One shared system for this section'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('One shared system for this section'));
      await tester.pumpAndSettle();
      final manager = find.byKey(const ValueKey('shared-manager-BSIT-2A'));
      await tester.ensureVisible(manager);
      await tester.tap(manager);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ana Cruz').last);
      await tester.pumpAndSettle();
      final reviewer = find.widgetWithText(
        DropdownButtonFormField<int>,
        'System faculty reviewer',
      );
      await tester.ensureVisible(reviewer);
      await tester.tap(reviewer);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prof. Reyes').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview teams'));
      await tester.pumpAndSettle();
      expect(preview?['shared_system'], {
        'project_manager_id': 1,
        'reviewer_id': 9,
        'title_mode': 'student_proposed',
        'stage_label': 'PIT Design',
      });
      expect(tester.takeException(), isNull);
    },
  );
}
