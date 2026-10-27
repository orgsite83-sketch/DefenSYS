import 'dart:convert';
import 'dart:async';

import 'package:defensys/screens/web/admin/student_teams/dialogs/generate_teams_dialog.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/widgets/repository/section_concept_workspace.dart';
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
    'assigned shared systems load configured uploads without requiring concept selection',
    (tester) async {
      final requests = <String>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url.path);
          return http.Response(
            jsonEncode({
              'projects': [],
              'tasks': [],
              'shared_contexts': [
                {
                  'team_id': 5,
                  'section': 'BSIT-2A',
                  'stage_label': 'Project Proposal',
                  'context_id': 8,
                  'scope': 'pit',
                  'imported': false,
                  'concept_selection_enabled': false,
                  'project_manager_id': 1,
                  'project_manager_name': 'Gabriel Navarro',
                  'systems': [
                    {'key': 'assigned', 'title': 'Existing shared system'},
                  ],
                  'requirements': [
                    {
                      'deliverable_id': 'FORM',
                      'label': 'Section endorsement',
                      'required': true,
                      'deliverable_type': 'pre',
                      'status': 'missing',
                      'file_policy': {'mode': 'single'},
                      'documents': [
                        {
                          'key': 'primary',
                          'label': 'Section endorsement',
                          'file_format': 'pdf',
                          'max_file_size': 52428800,
                          'can_upload': true,
                        },
                      ],
                    },
                  ],
                },
              ],
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
      expect(find.text('Upload Section endorsement'), findsOneWidget);
      expect(find.text('Existing shared system'), findsOneWidget);
      expect(find.text('PM: Gabriel Navarro'), findsOneWidget);
      expect(find.textContaining('Attempt'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shared progress and names follow four configured alternatives', (
    tester,
  ) async {
    final project = projectFixture()
      ..['endorsed'] = false
      ..['can_edit_names'] = true
      ..['can_manage'] = false
      ..['can_review'] = false
      ..['review_progress'] = {'required': 4, 'papers_accepted': 0};
    (project['systems'] as List).add({
      'id': 4,
      'key': 'c4',
      'title': '',
      'confirmed': false,
      'papers': [],
    });
    setApiHttpClientForTesting(
      MockClient((request) async => http.Response(jsonEncode(project), 200)),
    );
    await pumpDefensysWidget(
      tester,
      const SingleChildScrollView(
        child: SectionConceptWorkspace(projectId: 7, embedded: true),
      ),
      overrides: [authProvider.overrideWith(_Student.new)],
    );
    await tester.pumpAndSettle();
    expect(find.text('0 of 4 documents accepted'), findsOneWidget);
    expect(find.text('System D'), findsWidgets);
    await tester.ensureVisible(find.text('Propose system names').first);
    await tester.tap(find.text('Propose system names').first);
    await tester.pumpAndSettle();
    final inputs = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    expect(inputs, hasLength(4));
    expect(inputs.first.enabled, isFalse);
    expect(inputs.last.enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

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
    'PIT Lead Teams shows proposed names without loading the review workspace',
    (tester) async {
      final project = projectFixture();
      final requests = <String>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url.path);
          return http.Response(jsonEncode(project), 200);
        }),
      );
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
            sharedProposalNamesOnly: true,
            searchQuery: 'Alpha',
            onOpenTeamDetail: (_) {},
          ),
        ),
        overrides: authTestOverrides(),
      );
      expect(
        find.text('Concept selection · 3 of 3 titles provided'),
        findsOneWidget,
      );
      expect(find.text('Campus Management'), findsOneWidget);
      expect(find.byType(SectionConceptWorkspace), findsNothing);
      expect(find.text('Shared system proposals · PIT Design'), findsOneWidget);
      expect(requests, isEmpty);
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
    'section review clears accepted papers without a separate endorsement',
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
              project['endorsed'] = true;
              project['review_progress']['papers_accepted'] = 3;
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
          child: const SectionConceptWorkspace(projectId: 7, embedded: true),
        ),
        overrides: authTestOverrides(),
      );
      expect(find.text('Shared concepts'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text('Endorse shared papers'), findsNothing);
      await tester.tap(find.text('Accept paper'));
      await tester.pumpAndSettle();
      expect(actions.single['paper_id'], 41);
      expect(actions.single['round_id'], 12);
      expect(actions.single['review_token'], 'reviewed-current-content');
      expect(actions.single['action'], 'review');
      expect(find.text('Shared papers cleared for hearing'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'focused shared review reuses Details and saves before advancing',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final dark in [false, true]) {
        await tester.binding.setSurfaceSize(
          dark ? const Size(390, 1000) : const Size(1280, 1000),
        );
        final project = reviewFixture();
        final actions = <Map<String, dynamic>>[];
        setApiHttpClientForTesting(
          MockClient((request) async {
            if (request.method == 'POST') {
              final action = jsonDecode(request.body) as Map<String, dynamic>;
              actions.add(action);
              project['systems'][0]['papers'][0]['status'] = 'accepted';
            }
            return http.Response(jsonEncode(project), 200);
          }),
        );
        await pumpDefensysWidget(
          tester,
          const RepaintBoundary(
            key: ValueKey('focused-shared-preview'),
            child: SingleChildScrollView(
              child: SectionConceptWorkspace(
                projectId: 7,
                embedded: true,
                focused: true,
              ),
            ),
          ),
          theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
          overrides: authTestOverrides(),
        );
        expect(find.text('Read paper'), findsNothing);
        expect(find.text('Details'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('shared-module-review-table')),
          findsNothing,
        );
        await tester.tap(find.text('Details'));
        await tester.pumpAndSettle();
        expect(find.text('View Document'), findsOneWidget);
        expect(find.text('Replace File'), findsNothing);
        await tester.tap(find.byTooltip('Close details'));
        await tester.pumpAndSettle();
        await capturePreview(
          tester,
          find.byKey(const ValueKey('focused-shared-preview')),
          'focused-shared-${dark ? 'dark-phone' : 'light-desktop'}',
        );
        await tester.ensureVisible(find.text('Accept & next'));
        await tester.tap(find.text('Accept & next'));
        await tester.pumpAndSettle();
        expect(actions.single['paper_id'], 41);
        expect(actions.single['round_id'], 12);
        expect(actions.single['review_token'], 'reviewed-current-content');
        expect(find.text('Clinic Management'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'focused shared name confirmation is inline and retains the review snapshot on failure',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final project = reviewFixture();
      final actions = <Map<String, dynamic>>[];
      var succeed = false;
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'POST') {
            actions.add(jsonDecode(request.body) as Map<String, dynamic>);
            if (!succeed) {
              return http.Response(
                jsonEncode({'detail': 'Could not confirm names.'}),
                400,
              );
            }
          }
          return http.Response(jsonEncode(project), 200);
        }),
      );
      await pumpDefensysWidget(
        tester,
        const SingleChildScrollView(
          child: SectionConceptWorkspace(
            projectId: 7,
            embedded: true,
            focused: true,
          ),
        ),
        overrides: authTestOverrides(),
      );
      await tester.tap(find.text('Edit name'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Save and confirm name'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      await tester.enterText(
        find.byType(EditableText).first,
        'Confirmed campus system',
      );
      await tester.tap(find.text('Save and confirm name'));
      await tester.pumpAndSettle();
      expect(find.text('Could not confirm names.'), findsOneWidget);
      expect(find.text('Save and confirm name'), findsOneWidget);
      succeed = true;
      await tester.tap(find.text('Save and confirm name'));
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsOneWidget);
      expect(actions.last['action'], 'confirm_title');
      expect(actions.last['round_id'], 12);
      expect(actions.last['review_token'], 'reviewed-current-content');
      expect(actions.last['concept_key'], 'c1');
      expect(actions.last['title'], 'Confirmed campus system');
      expect(actions.last.containsKey('concepts'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'configured shared files stay under their system and section-wide files appear once',
    (tester) async {
      final project = reviewFixture();
      project['systems'] = (project['systems'] as List).take(2).toList();
      project['systems'][0]['confirmed'] = false;
      project['review_progress'] = {
        'names_confirmed': 1,
        'documents_required': 5,
        'documents_accepted': 0,
      };
      final group = <String, dynamic>{
        'team_id': 5,
        'stage_label': 'PIT Design',
        'review_token': 'configured-files',
        'systems': [
          for (var i = 1; i <= 2; i++)
            {'key': 'c$i', 'title': project['systems'][i - 1]['title']},
        ],
        'requirements': [
          {
            'deliverable_id': 'BUNDLE',
            'label': 'Shared concept bundle',
            'deliverable_type': 'pre',
            'required': true,
            'file_policy': {'mode': 'concepts'},
            'status': 'pending',
            'documents': [
              for (var i = 1; i <= 2; i++)
                for (final slot in ['paper', 'brief'])
                  {
                    'key': 'c$i:$slot',
                    'system_key': 'c$i',
                    'label': slot,
                    'required': true,
                    'can_review': true,
                    'file_format': 'pdf',
                    'file': {
                      'id': i * 10 + (slot == 'paper' ? 1 : 2),
                      'file_name': 'system_${i}_$slot.pdf',
                      'status': 'pending',
                      'revision': 1,
                    },
                  },
            ],
          },
          {
            'deliverable_id': 'SECTION',
            'label': 'Section checklist',
            'deliverable_type': 'pre',
            'required': true,
            'file_policy': {'mode': 'single'},
            'status': 'pending',
            'documents': [
              {
                'key': 'primary',
                'label': 'Overview',
                'can_review': true,
                'file': {
                  'id': 50,
                  'file_name': 'section_overview.pdf',
                  'status': 'pending',
                  'revision': 1,
                },
              },
            ],
          },
        ],
      };
      project['shared_deliverables'] = group;
      project['shared_review'] = {
        'can_review_shared_context': true,
        'papers_available': true,
        'can_acknowledge': true,
        'acknowledged': false,
        'acknowledgment_required': true,
      };
      final actions = <Map<String, dynamic>>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'POST') {
            final data = jsonDecode(request.body) as Map<String, dynamic>;
            actions.add(data);
            if (data['action'] == 'confirm_title') {
              project['systems'][0]['confirmed'] = true;
              project['review_progress']['names_confirmed'] = 2;
            }
            if (request.url.path.endsWith('/shared-deliverables/')) {
              group['requirements'][0]['documents'][0]['file']['status'] =
                  'accepted';
              project['review_progress']['documents_accepted'] = 1;
              return http.Response(
                jsonEncode({'shared_deliverables': group}),
                200,
              );
            }
          }
          return http.Response(jsonEncode(project), 200);
        }),
      );
      await tester.binding.setSurfaceSize(const Size(1280, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final scenario in [(1280.0, false), (390.0, false), (320.0, true)]) {
        await tester.binding.setSurfaceSize(Size(scenario.$1, 1200));
        await pumpDefensysWidget(
          tester,
          RepaintBoundary(
            key: const ValueKey('configured-review-capture'),
            child: const SingleChildScrollView(
              child: SectionConceptWorkspace(
                projectId: 7,
                embedded: true,
                focused: true,
              ),
            ),
          ),
          theme: scenario.$2 ? AppTheme.mistDarkTheme : AppTheme.theme,
          overrides: authTestOverrides(),
        );
        expect(find.text('system_1_paper.pdf'), findsOneWidget);
        expect(find.text('system_1_brief.pdf'), findsOneWidget);
        expect(find.text('system_2_paper.pdf'), findsNothing);
        expect(find.text('section_overview.pdf'), findsOneWidget);
        expect(find.text('Section-wide documents'), findsOneWidget);
        if (actions.isEmpty) {
          await tester.ensureVisible(find.text('Confirm system name'));
          await tester.tap(find.text('Confirm system name'));
          await tester.pumpAndSettle();
          expect(actions.single['concept_key'], 'c1');
          expect(find.text('Required documents: 0/5 accepted'), findsOneWidget);
          await tester.ensureVisible(find.text('Accept file').first);
          await tester.tap(find.text('Accept file').first);
          await tester.pumpAndSettle();
          expect(actions.last['slot_key'], 'c1:paper');
          expect(find.text('Required documents: 1/5 accepted'), findsOneWidget);
        }
        await capturePreview(
          tester,
          find.byKey(const ValueKey('configured-review-capture')),
          'concept-review-configured-${scenario.$1.toInt()}-${scenario.$2 ? 'dark' : 'light'}',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('a delayed refresh cannot undo paper acceptance', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final project = reviewFixture();
    final original = jsonEncode(project);
    final refresh = Completer<http.Response>();
    var reads = 0;
    setApiHttpClientForTesting(
      MockClient((request) async {
        if (request.method == 'GET') {
          if (++reads == 1) return http.Response(original, 200);
          return refresh.future;
        }
        project['endorsed'] = true;
        project['review_progress']['papers_accepted'] = 3;
        project['systems'][0]['papers'][0]['status'] = 'accepted';
        return http.Response(jsonEncode(project), 200);
      }),
    );
    await pumpDefensysWidget(
      tester,
      const SectionConceptWorkspace(projectId: 7),
      overrides: authTestOverrides(),
    );
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(reads, 2);
    await tester.ensureVisible(find.text('Accept paper').first);
    await tester.tap(find.text('Accept paper').first);
    await tester.pumpAndSettle();
    expect(find.text('Accepted'), findsNWidgets(3));
    refresh.complete(http.Response(original, 200));
    await tester.pumpAndSettle();
    expect(find.text('Accepted'), findsNWidgets(3));
  });

  testWidgets(
    'shared acknowledgment records the displayed version without accepting papers',
    (tester) async {
      final project = reviewFixture();
      project['scope'] = 'capstone';
      project['can_review'] = false;
      project['shared_review'] = {
        'can_review_shared_context': true,
        'papers_available': true,
        'can_acknowledge': true,
        'acknowledged': false,
      };
      final actions = <Map<String, dynamic>>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'POST') {
            actions.add(jsonDecode(request.body) as Map<String, dynamic>);
            project['shared_review'] = {
              'can_review_shared_context': true,
              'papers_available': true,
              'can_acknowledge': false,
              'acknowledged': true,
            };
          }
          return http.Response(jsonEncode(project), 200);
        }),
      );
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpDefensysWidget(
        tester,
        const SingleChildScrollView(
          child: SectionConceptWorkspace(projectId: 7, embedded: true),
        ),
        overrides: authTestOverrides(),
      );
      expect(find.text('Accept paper'), findsNothing);
      await tester.ensureVisible(find.text('Confirm alignment for my teams'));
      await tester.tap(find.text('Confirm alignment for my teams'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm alignment'));
      await tester.pumpAndSettle();
      expect(actions.single['action'], 'acknowledge');
      expect(actions.single['round_id'], 12);
      expect(actions.single['review_token'], 'reviewed-current-content');
      expect(find.text('Your alignment: Recorded'), findsOneWidget);
      expect(
        (project['systems'] as List).first['papers'][0]['status'],
        'pending',
      );
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
            collapsible: true,
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
      find.text('Submit 3 matching module concepts · PIT Design'),
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
      await tester.ensureVisible(find.text('Confirm module names'));
      await tester.pumpAndSettle();
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
        find.text('Select section system'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Select section system'));
      await tester.tap(find.text('Select section system'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clinic Management').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save section decision'));
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
        ..['shared_revisions_pending'] = true
        ..['post_unlocked'] = true;
      final systems = project['systems'] as List;
      systems[1]['can_upload_final'] = true;
      systems[1]['final_papers'] = [
        {
          'id': 21,
          'revision': 1,
          'file_name': 'clinic.pdf',
          'is_current': true,
          'status': 'rejected',
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
      expect(find.text('Upload corrected final paper'), findsOneWidget);
      expect(find.text('Upload concept paper'), findsNothing);
      expect(
        find.textContaining('Module approvals cannot complete progression'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'PIT Lead records module selection through the concept decision action',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final project = projectFixture()
        ..['scope'] = 'pit'
        ..['selected_key'] = 'c2'
        ..['verdict'] = 'approved';
      final team = (project['teams'] as List).first as Map;
      team['can_record_decision'] = true;
      team['decision_review_token'] = 'current-module-papers';
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
        find.text('Review module'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Review module'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review module'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialog, matching: find.text('Review module')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Module 2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('Module 1')),
        findsOneWidget,
      );
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      await tester.tap(find.text('Save module review'));
      await tester.pumpAndSettle();
      expect(actions.single['action'], 'module_decision');
      expect(actions.single['module_review_token'], 'current-module-papers');
      expect(actions.single['team_id'], team['id']);
      expect(actions.single['module_key'], 'c2');
    },
  );

  testWidgets(
    'PM final-paper requirements fit phone and desktop in both themes',
    (tester) async {
      final project = projectFixture()
        ..['selected_key'] = 'c2'
        ..['verdict'] = 'approved'
        ..['post_unlocked'] = true;
      (project['systems'] as List)[1]['can_upload_final'] = true;
      setApiHttpClientForTesting(
        MockClient((request) async => http.Response(jsonEncode(project), 200)),
      );
      const preview = ValueKey('shared-final-paper-preview');
      for (final dark in [false, true]) {
        for (final size in [const Size(1100, 1000), const Size(390, 1000)]) {
          await tester.binding.setSurfaceSize(size);
          await pumpDefensysWidget(
            tester,
            const RepaintBoundary(
              key: preview,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: SectionConceptWorkspace(projectId: 7, embedded: true),
              ),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
            overrides: [authProvider.overrideWith(_Student.new)],
          );
          await tester.ensureVisible(
            find.text('Approved shared concept paper'),
          );
          await tester.pumpAndSettle();
          expect(find.text('Upload approved concept paper'), findsOneWidget);
          expect(find.textContaining('Module 1'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(preview),
            'shared-final-paper-${size.width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets(
    'chair starts the shared hearing without posting grades or choosing a module',
    (tester) async {
      final project = projectFixture()..['can_start_presentation'] = true;
      final actions = <Map<String, dynamic>>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'POST') {
            actions.add(jsonDecode(request.body) as Map<String, dynamic>);
            project['can_start_presentation'] = false;
            project['can_decide'] = true;
            project['presentation_started_at'] = '2026-10-20T09:00:00+08:00';
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
        find.text('Start shared presentation'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Start shared presentation'));
      await tester.pumpAndSettle();
      expect(actions.single['action'], 'start_presentation');
      expect(actions.single.containsKey('team_outcomes'), isFalse);
      expect(find.text('Select section system'), findsOneWidget);
    },
  );

  testWidgets(
    'late system selection finalizes an assessed earlier team with its revision notes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final project = projectFixture()..['can_decide'] = true;
      final teams = project['teams'] as List;
      final alpha = teams.first as Map;
      alpha['can_finalize_with_selection'] = true;
      alpha['module_outcome_review_token'] = 'alpha-current-assessment';
      teams.add(<String, Object?>{
        ...Map<String, Object?>.from(alpha),
        'id': 8,
        'name': 'Team Beta',
        'can_finalize_with_selection': false,
        'module_assessment_reason': 'Every panelist must finish grading.',
      });
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
        find.text('Select section system'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Select section system'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clinic Management').last);
      await tester.pumpAndSettle();
      final outcome = find.byKey(const ValueKey('batch-outcome-5-c2'));
      await tester.ensureVisible(outcome);
      await tester.tap(outcome);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approved with revisions').last);
      await tester.pumpAndSettle();
      final notes = find.byKey(const ValueKey('batch-notes-5-c2'));
      await tester.ensureVisible(notes);
      await tester.enterText(notes, 'Clarify the module permissions.');
      await tester.tap(find.text('Save section decision'));
      await tester.pumpAndSettle();
      expect(posted?['team_outcomes'], [
        {
          'team_id': 5,
          'verdict': 'approved_with_revisions',
          'remarks': 'Clarify the module permissions.',
          'review_token': 'alpha-current-assessment',
        },
      ]);
      expect(
        (posted?['concepts'] as List).singleWhere(
          (c) => c['decision'] == 'approved',
        )['key'],
        'c2',
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
        'section_instructors': {
          'BSIT-2A': [
            {
              'faculty_id': 9,
              'faculty__first_name': 'Prof.',
              'faculty__last_name': 'Reyes',
            },
          ],
        },
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
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Independent projects'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shared section system').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose an option').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ana Cruz').last);
      await tester.pumpAndSettle();
      expect(find.text('Prof. Reyes'), findsOneWidget);
      expect(find.text('System faculty reviewer'), findsNothing);
      await tester.tap(find.text('Review teams'));
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
