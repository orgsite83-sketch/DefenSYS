import 'dart:convert';

import 'package:defensys/screens/web/shared/team_deliverables/components/cohort_submissions_matrix.dart';
import 'package:defensys/screens/web/shared/team_deliverables/team_deliverables_screen.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/weekly_progress_provider.dart';
import 'package:defensys/services/defense/team_defense_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/concept_workspace.dart';
import 'package:defensys/widgets/repository/document_group.dart';
import 'package:defensys/widgets/repository/concept_review_section.dart';
import 'package:defensys/widgets/repository/section_concept_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

class _Faculty extends AuthNotifier {
  @override
  AuthState build() => AuthState(
    isRestoring: false,
    token: testAccessToken,
    user: const {'id': 2, 'role': 'faculty'},
  );
}

class _SharedDeliverables extends CapstoneDeliverablesNotifier {
  @override
  CapstoneDeliverablesState build() => CapstoneDeliverablesState(
    scope: 'pit',
    workspace: 'instructor',
    selectedStage: 'Mini Capstone',
    stageOptions: const ['Mini Capstone'],
    teams: [_team(1, 7, 'BSIT-3A'), _team(2, 7, 'BSIT-3A')],
  );
  @override
  Future<void> fetchDeliverables({
    String? workspace,
    String? search,
    String? selectedStage,
    String? status,
    String? scope,
    String? yearLevel,
    String? section,
    String? successMessage,
  }) async {}
}

class _Grades extends AdviserGradingNotifier {
  @override
  Future<void> fetchAll() async {}
}

class _ModuleDeliverables extends _SharedDeliverables {
  @override
  CapstoneDeliverablesState build() {
    final stage = {
      'stage_label': 'Mini Capstone',
      'deliverables_configured': true,
      'required_total': 2,
      'pre': [
        {
          'id': 'CONCEPTS',
          'label': 'Concept papers',
          'type': 'pre',
          'required': true,
          'can_faculty_review': true,
          'file_policy': {'mode': 'concepts'},
          'document_slots': [
            {
              'key': 'c1:outline',
              'label': 'Concept 1 outline',
              'required': true,
            },
            {'key': 'c2:brief', 'label': 'Concept 2 brief', 'required': true},
          ],
          'submission': {
            'files': [
              for (final entry in {'c1:outline': 1, 'c2:brief': 2}.entries)
                {
                  'id': entry.value,
                  'slot_key': entry.key,
                  'file_name': 'Module_${entry.value}.pdf',
                  'status': 'pending',
                  'revision': 1,
                },
            ],
          },
        },
      ],
      'post': <Map<String, dynamic>>[],
      'concept_workflow': {
        'enabled': true,
        'title_workflow_version': 2,
        'round_id': 12,
        'concepts': [
          for (var i = 1; i <= 2; i++)
            {
              'key': 'c$i',
              'title': 'Module proposal $i',
              'faculty_confirmed': i == 1,
              'title_review': {
                'state': i == 1 ? 'accepted' : 'submitted',
                'status_label': i == 1
                    ? 'Title accepted'
                    : 'Awaiting title review',
                'can_accept': i == 2,
              },
            },
        ],
      },
    };
    return CapstoneDeliverablesState(
      scope: 'pit',
      workspace: 'instructor',
      selectedStage: 'Mini Capstone',
      stageOptions: const ['Mini Capstone'],
      teams: [
        {
          'id': 1,
          'name': 'Team ColdChain',
          'section': 'BSIT-3A',
          'selected_stage': stage,
          'stages': [stage],
        },
      ],
    );
  }
}

class _Weekly extends WeeklyProgressNotifier {
  @override
  Future<void> fetchReports() async {}
}

class _ReviewShortcutDeliverables extends _ModuleDeliverables {
  _ReviewShortcutDeliverables({this.grouped = false});
  final bool grouped;

  @override
  CapstoneDeliverablesState build() {
    final base = super.build();
    final team = base.teams.single;
    final original = team['selected_stage'] as Map;
    final paper = (original['pre'] as List).single as Map;
    final stage = <String, dynamic>{
      ...original,
      'required_total': grouped ? 2 : 3,
      'pre': [
        {
          ...paper,
          'submission': {
            'files': [
              for (final file in (paper['submission'] as Map)['files'] as List)
                {
                  ...file as Map,
                  'status': grouped && file['slot_key'] == 'c2:brief'
                      ? 'pending'
                      : 'accepted',
                },
            ],
          },
        },
        if (!grouped)
          {
            'id': 'ACCEPTANCE',
            'label': 'Adviser Acceptance Form',
            'type': 'pre',
            'required': true,
            'can_faculty_review': true,
            'uploaded': true,
            'submission': {
              'id': 30,
              'file_name': 'ColdChain_Adviser_Acceptance.pdf',
              'file_url': '/test/acceptance.pdf',
              'status': 'pending',
            },
          },
      ],
    };
    final emptyStage = <String, dynamic>{
      'stage_label': 'Mini Capstone',
      'deliverables_configured': true,
      'pre': <Map<String, dynamic>>[],
      'post': <Map<String, dynamic>>[],
    };
    return base.copyWith(
      teams: [
        {
          'id': 2,
          'name': 'Team AgroTrade',
          'section': 'BSIT-3A',
          'selected_stage': emptyStage,
          'stages': [emptyStage],
        },
        {
          ...team,
          'selected_stage': stage,
          'stages': [stage],
        },
      ],
    );
  }
}

class _Defense extends PitInstructorDefenseNotifier {
  @override
  Future<void> fetch({String? workspace}) async {}
}

Map<String, dynamic> _stage(int projectId) => {
  'stage_label': 'Mini Capstone',
  'deliverables_configured': true,
  'required_total': 0,
  'pre': <Map<String, dynamic>>[],
  'post': <Map<String, dynamic>>[],
  'concept_workflow': {
    'enabled': true,
    'section_project_id': projectId,
    'concepts': <Map<String, dynamic>>[],
    'shared_review': {
      'project_id': projectId,
      'cleared': false,
      'status': 'awaiting_files',
      'status_label': 'Shared papers awaiting upload',
      'review_progress': {'papers_accepted': 0},
      'systems': <Map<String, dynamic>>[],
    },
  },
};

Map<String, dynamic> _team(int id, int projectId, String section) => {
  'id': id,
  'name': 'Module team $id',
  'section': section,
  'selected_stage': _stage(projectId),
  'stages': [_stage(projectId)],
};

void main() {
  setUpAll(() => loadPreviewFonts(force: true));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(resetApiHttpClientForTesting);

  for (final grouped in [false, true]) {
    testWidgets(
      'review shortcut opens the pending ${grouped ? 'concept slot' : 'form'} without filtering teams',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpDefensysWidget(
          tester,
          const TeamDeliverablesScreen(
            isPitInstructor: true,
            initialTeamId: 2,
            initialTab: 1,
          ),
          overrides: [
            authProvider.overrideWith(_Faculty.new),
            capstoneDeliverablesProvider.overrideWith(
              () => _ReviewShortcutDeliverables(grouped: grouped),
            ),
            adviserGradingProvider.overrideWith(_Grades.new),
            weeklyProgressProvider.overrideWith(_Weekly.new),
            pitInstructorDefenseProvider.overrideWith(_Defense.new),
          ],
        );
        if (grouped) {
          await tester.tap(find.text('Concept review').first);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Review 1 submission'));
        await tester.pumpAndSettle();
        final fileName = grouped
            ? 'Module_2.pdf'
            : 'ColdChain_Adviser_Acceptance.pdf';
        expect(find.text(fileName), findsOneWidget);
        expect(find.text('Module_1.pdf'), findsNothing);
        expect(find.text('All deliverables'), findsOneWidget);
        expect(find.text('Teams (2)'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('faculty-team-choice-t2')),
          findsOneWidget,
        );
        expect(find.text('Accept'), findsOneWidget);
        await capturePreview(
          tester,
          find.byType(TeamDeliverablesScreen),
          'direct-review-${grouped ? 'concept' : 'form'}',
          viewport: true,
        );

        // Returning to the checklist must not consume a later request to open
        // this same pending file, including when a different team tab is active.
        await tester.tap(find.text('All deliverables'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Team details'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review 1 submission'));
        await tester.pumpAndSettle();
        expect(find.text(fileName), findsOneWidget);
        expect(find.text('All deliverables'), findsOneWidget);
        expect(find.text('Teams (2)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Review files opens By team at the selected concept and configured slot',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpDefensysWidget(
        tester,
        const TeamDeliverablesScreen(isPitInstructor: true, initialTeamId: 1),
        overrides: [
          authProvider.overrideWith(_Faculty.new),
          capstoneDeliverablesProvider.overrideWith(_ModuleDeliverables.new),
          adviserGradingProvider.overrideWith(_Grades.new),
          weeklyProgressProvider.overrideWith(_Weekly.new),
          pitInstructorDefenseProvider.overrideWith(_Defense.new),
        ],
      );
      await tester.tap(find.text('Concept review').first);
      await tester.pumpAndSettle();
      expect(find.text('Title accepted'), findsOneWidget);
      expect(find.text('Module_1.pdf'), findsOneWidget);
      await capturePreview(
        tester,
        find.byType(TeamDeliverablesScreen),
        'nested-team-concept-review',
        viewport: true,
      );

      await tester.tap(find.text('Review files'));
      await tester.pumpAndSettle();
      expect(find.text('Module_1.pdf'), findsOneWidget);
      expect(find.text('Awaiting review'), findsOneWidget);
      expect(find.text('Under Review'), findsNothing);
      expect(find.text('Module proposal 1'), findsOneWidget);
      expect(find.text('Title details'), findsNothing);
      await capturePreview(
        tester,
        find.byType(TeamDeliverablesScreen),
        'clean-team-file-review',
        viewport: true,
      );
      expect(find.text('Title accepted'), findsOneWidget);
      await tester.tap(find.text('Review title'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Concept 2'));
      await tester.pumpAndSettle();
      expect(find.text('Module_2.pdf'), findsOneWidget);
      expect(find.text('Accept concept title'), findsOneWidget);
      expect(find.byType(ConceptReviewSection), findsOneWidget);
      await tester.tap(find.text('Review files'));
      await tester.pumpAndSettle();

      expect(find.byType(ConceptReviewSection), findsOneWidget);
      expect(find.text('All deliverables'), findsOneWidget);
      expect(find.text('Module_2.pdf'), findsOneWidget);
      expect(find.text('Module_1.pdf'), findsNothing);
      expect(find.text('Review title'), findsOneWidget);
      await tester.tap(find.text('Review title'));
      await tester.pumpAndSettle();
      expect(find.text('Module proposal 2'), findsOneWidget);
      expect(find.text('Accept concept title'), findsOneWidget);
      expect(find.text('Module_2.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared title and file actions remain together in Concept review',
    (tester) async {
      var accepted = false;
      final actions = <String>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          if (request.method == 'POST') {
            final body = jsonDecode(request.body) as Map;
            actions.add('${body['action']}');
            accepted = body['action'] == 'accept_title';
          }
          final system = {
            'key': 'c1',
            'title': 'Shared system proposal',
            'title_review': {
              'state': accepted ? 'accepted' : 'submitted',
              'status_label': accepted
                  ? 'Title accepted'
                  : 'Awaiting title review',
              'can_accept': !accepted,
              'can_request_revision': true,
            },
          };
          return http.Response(
            jsonEncode({
              'id': 7,
              'section': 'BSIT-3A',
              'stage_label': 'Mini Capstone',
              'round': 1,
              'round_id': 12,
              'review_token': 'shared-snapshot',
              'title_workflow_version': 2,
              'editable': true,
              'project_manager_name': 'Ana Cruz',
              'systems': [system],
              'shared_deliverables': {
                'team_id': 1,
                'systems': [system],
                'requirements': [
                  {
                    'deliverable_id': 'SHARED',
                    'label': 'Shared concept paper',
                    'required': true,
                    'file_policy': {'mode': 'concepts'},
                    'documents': [
                      {
                        'key': 'c1:paper',
                        'system_key': 'c1',
                        'required': true,
                        'can_review': true,
                        'title_blocker': accepted
                            ? ''
                            : 'Accept the matching system title first.',
                        'file': {
                          'id': 18,
                          'file_name': 'Shared_Concept.pdf',
                          'revision': 1,
                          'status': 'pending',
                        },
                      },
                    ],
                  },
                ],
              },
            }),
            200,
          );
        }),
      );
      await tester.binding.setSurfaceSize(const Size(1500, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpDefensysWidget(
        tester,
        const TeamDeliverablesScreen(
          isPitInstructor: true,
          initialScope: 'pit',
        ),
        overrides: [
          authProvider.overrideWith(_Faculty.new),
          capstoneDeliverablesProvider.overrideWith(_SharedDeliverables.new),
          adviserGradingProvider.overrideWith(_Grades.new),
          weeklyProgressProvider.overrideWith(_Weekly.new),
          pitInstructorDefenseProvider.overrideWith(_Defense.new),
        ],
      );
      await tester.tap(find.text('Concept review').first);
      await tester.pumpAndSettle();
      expect(find.text('Accept system title'), findsOneWidget);
      expect(find.text('Shared_Concept.pdf'), findsOneWidget);
      expect(find.text('Request revision'), findsOneWidget);
      await tester.ensureVisible(find.text('Accept system title'));
      await tester.tap(find.text('Accept system title'));
      await tester.pumpAndSettle();
      expect(actions, ['accept_title']);
      expect(find.text('Title accepted'), findsOneWidget);
      expect(find.text('Shared_Concept.pdf'), findsOneWidget);
      expect(find.text('Accept file'), findsOneWidget);
      expect(
        find.text('Refresh'),
        findsOneWidget,
      ); // The page-level refresh only.
      await capturePreview(
        tester,
        find.byType(TeamDeliverablesScreen),
        'corrected-shared-concept-review',
        viewport: true,
      );
      await tester.tap(find.text('By team'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('faculty-team-choice-p7')),
        findsNothing,
      );
      expect(find.text('Shared_Concept.pdf'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'instructor has one section review across team selection and matrix switching',
    (tester) async {
      final requests = <String>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url.path);
          return http.Response(
            jsonEncode({
              'id': 7,
              'section': 'BSIT-3A',
              'stage_label': 'Mini Capstone',
              'round': 1,
              'verdict': '',
              'systems': [],
              'history': [],
            }),
            200,
          );
        }),
      );
      await tester.binding.setSurfaceSize(const Size(1500, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.physicalSize = const Size(1500, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpDefensysWidget(
        tester,
        const TeamDeliverablesScreen(
          isPitInstructor: true,
          initialScope: 'pit',
        ),
        overrides: [
          authProvider.overrideWith(_Faculty.new),
          capstoneDeliverablesProvider.overrideWith(_SharedDeliverables.new),
          adviserGradingProvider.overrideWith(_Grades.new),
          weeklyProgressProvider.overrideWith(_Weekly.new),
          pitInstructorDefenseProvider.overrideWith(_Defense.new),
        ],
      );
      expect(find.byType(SectionConceptOverview), findsNothing);
      expect(find.text('Shared concepts'), findsNothing);
      expect(find.text('By team'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('faculty-team-choice-p7')),
        findsNothing,
      );
      expect(requests, isEmpty);
      await tester.ensureVisible(find.text('Module team 2').first);
      await tester.tap(find.text('Module team 2').first);
      await tester.pumpAndSettle();
      expect(find.byType(SectionConceptOverview), findsNothing);
      expect(requests, isEmpty);
      await tester.ensureVisible(find.text('Concept review').first);
      await tester.tap(find.text('Concept review').first);
      await tester.pumpAndSettle();
      expect(requests, ['/api/repository/section-concepts/7/']);
      expect(find.text('Shared concepts'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('faculty-team-choice-p7')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('shared-module-review-table')),
        findsNothing,
      );
      expect(find.text('Cohort Matrix'), findsNothing);
      await tester.ensureVisible(find.text('By team'));
      await tester.tap(find.text('By team'));
      await tester.pumpAndSettle();
      expect(find.byType(SectionConceptOverview), findsNothing);
      expect(find.text('Shared concepts'), findsNothing);
      expect(
        find.byKey(const ValueKey('faculty-team-choice-p7')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Concept review').first);
      await tester.pumpAndSettle();
      expect(find.text('Shared concepts'), findsOneWidget);
      await tester.tap(find.text('By team'));
      await tester.pumpAndSettle();
      expect(find.text('Shared concepts'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expanded matrix section review fits desktop and phone in both themes',
    (tester) async {
      setApiHttpClientForTesting(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'id': 7,
              'section': 'BSIT-3A',
              'stage_label': 'Mini Capstone',
              'round': 1,
              'verdict': '',
              'can_review': true,
              'can_edit_names': true,
              'project_manager_name': 'Ana Cruz',
              'reviewer_name': 'Prof. Reyes',
              'systems': [
                for (var i = 1; i <= 3; i++)
                  {
                    'key': 'c$i',
                    'title': 'Shared system proposal $i',
                    'confirmed': true,
                    'papers': [
                      {
                        'id': i,
                        'file_name': 'System-$i-concept-paper.pdf',
                        'revision': 1,
                        'is_current': true,
                        'status': 'pending',
                      },
                    ],
                  },
              ],
              'history': [],
            }),
            200,
          ),
        ),
      );
      const previewKey = ValueKey('shared-matrix-preview');
      for (final dark in [false, true]) {
        for (final size in [const Size(1280, 1000), const Size(390, 1200)]) {
          await tester.binding.setSurfaceSize(size);
          final teams = [_team(1, 7, 'BSIT-3A'), _team(2, 7, 'BSIT-3A')];
          await pumpDefensysWidget(
            tester,
            RepaintBoundary(
              key: previewKey,
              child: SingleChildScrollView(
                child: CohortSubmissionsMatrix(
                  teams: teams,
                  state: CapstoneDeliverablesState(
                    scope: 'pit',
                    selectedStage: 'Mini Capstone',
                    teams: teams,
                  ),
                  isAdviser: false,
                ),
              ),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.theme,
            overrides: authTestOverrides(),
          );
          await tester.tap(
            find.text('Shared system papers · BSIT-3A · Mini Capstone'),
          );
          await tester.pumpAndSettle();
          expect(find.text('Shared concepts'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byKey(previewKey),
            'shared-matrix-${size.width == 1280 ? 'desktop' : 'mobile'}-${dark ? 'dark' : 'light'}',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets(
    'matrix groups shared papers once per section and loads review on expansion',
    (tester) async {
      final requests = <String>[];
      setApiHttpClientForTesting(
        MockClient((request) async {
          requests.add(request.url.path);
          return http.Response(
            jsonEncode({
              'id': 7,
              'section': 'BSIT-3A',
              'stage_label': 'Mini Capstone',
              'round': 1,
              'verdict': '',
              'systems': [],
              'history': [],
            }),
            200,
          );
        }),
      );
      await tester.binding.setSurfaceSize(const Size(1500, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final teams = [
        _team(1, 7, 'BSIT-3A'),
        _team(2, 7, 'BSIT-3A'),
        _team(3, 8, 'BSIT-3B'),
      ];
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: CohortSubmissionsMatrix(
            teams: teams,
            state: CapstoneDeliverablesState(
              scope: 'pit',
              selectedStage: 'Mini Capstone',
              teams: teams,
            ),
            isAdviser: false,
          ),
        ),
        overrides: authTestOverrides(),
      );
      expect(find.byType(SectionConceptOverview), findsNWidgets(2));
      expect(
        find.text('Shared system papers · BSIT-3A · Mini Capstone'),
        findsOneWidget,
      );
      expect(
        find.text('0/3 papers accepted · Shared papers awaiting upload'),
        findsNWidgets(2),
      );
      expect(requests, isEmpty);
      await tester.tap(
        find.text('Shared system papers · BSIT-3A · Mini Capstone'),
      );
      await tester.pumpAndSettle();
      expect(requests, ['/api/repository/section-concepts/7/']);
      expect(find.text('Shared concepts'), findsOneWidget);
      expect(find.text('Endorse shared papers'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'team dossier keeps module review and opens its section through a compact link',
    (tester) async {
      int? opened;
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: ConceptWorkspace(
            teamId: 1,
            stageLabel: 'Mini Capstone',
            stage: _stage(7),
            onOpenSharedReview: (id) => opened = id,
          ),
        ),
        overrides: authTestOverrides(),
      );
      expect(find.text('Shared section system'), findsOneWidget);
      expect(
        find.textContaining('Your linked module will appear here'),
        findsOneWidget,
      );
      expect(find.byType(SectionConceptWorkspace), findsNothing);
      await tester.tap(find.text('Open section systems'));
      expect(opened, 7);
      expect(find.text('Shared section system'), findsOneWidget);
    },
  );

  testWidgets(
    'faculty document groups retain review actions and hide upload controls',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: DocumentGroup(
            teamId: 1,
            stageLabel: 'Mini Capstone',
            item: {
              'id': 'PAPER',
              'label': 'Concept papers',
              'can_upload': true,
              'can_faculty_review': true,
              'file_policy': {'mode': 'named'},
              'document_slots': [
                {'key': 'c1:paper', 'label': 'Module A paper'},
                {'key': 'c2:paper', 'label': 'Module B paper'},
              ],
              'submission': {
                'files': [
                  {
                    'id': 1,
                    'slot_key': 'c1:paper',
                    'file_name': 'module.pdf',
                    'status': 'pending',
                    'revision': 1,
                  },
                ],
              },
            },
          ),
        ),
        overrides: [authProvider.overrideWith(_Faculty.new)],
      );
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Request revision'), findsOneWidget);
      expect(find.text('Awaiting review'), findsOneWidget);
      expect(find.text('Upload document'), findsNothing);
      expect(find.text('Upload revision'), findsNothing);
      expect(find.text('Remove'), findsNothing);
    },
  );
}
