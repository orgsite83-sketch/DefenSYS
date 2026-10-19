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

class _Weekly extends WeeklyProgressNotifier {
  @override
  Future<void> fetchReports() async {}
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
      expect(find.byType(SectionConceptOverview), findsOneWidget);
      expect(find.text('Shared system review'), findsOneWidget);
      expect(find.text('Team module concepts'), findsOneWidget);
      await tester.ensureVisible(find.text('Module team 2').first);
      await tester.tap(find.text('Module team 2').first);
      await tester.pumpAndSettle();
      expect(find.byType(SectionConceptOverview), findsOneWidget);
      await tester.ensureVisible(find.text('View shared papers'));
      await tester.tap(find.text('View shared papers'));
      await tester.pumpAndSettle();
      expect(requests, ['/api/repository/section-concepts/7/']);
      await tester.ensureVisible(find.text('Cohort Matrix'));
      await tester.tap(find.text('Cohort Matrix'));
      await tester.pumpAndSettle();
      expect(find.byType(SectionConceptOverview), findsOneWidget);
      expect(find.text('Shared system review'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Shared system papers · BSIT-3A · Mini Capstone'));
      await tester.pumpAndSettle();
      expect(find.text('Shared system review'), findsNothing);
      await tester.tap(
        find.text('Shared system papers · BSIT-3A · Mini Capstone'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shared system review'), findsOneWidget);
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
          expect(find.text('Shared system review'), findsOneWidget);
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
      expect(find.text('Shared system review'), findsOneWidget);
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
      expect(find.text('Team module concepts'), findsOneWidget);
      expect(find.text('Shared papers awaiting upload'), findsOneWidget);
      expect(find.byType(SectionConceptWorkspace), findsNothing);
      await tester.tap(find.text('View shared papers'));
      expect(opened, 7);
      expect(find.text('Team module concepts'), findsOneWidget);
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
      expect(find.text('Request corrections'), findsOneWidget);
      expect(find.text('Awaiting review'), findsOneWidget);
      expect(find.text('Upload document'), findsNothing);
      expect(find.text('Upload revision'), findsNothing);
      expect(find.text('Remove'), findsNothing);
    },
  );
}
