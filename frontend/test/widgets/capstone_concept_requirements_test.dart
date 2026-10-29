import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/screens/web/admin/defense_stages/defense_stage_editor_screen.dart';
import 'package:defensys/screens/web/admin/defense_stages/defense_stages_screen.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/services/rubric_engine_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/repository/document_policy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';

const _stage = <String, dynamic>{
  'id': 7,
  'label': 'Concept Proposal',
  'display_order': 1,
  'is_active': false,
  'is_locked': false,
  'qualifying_score': 75,
  'deliverables': <Map<String, dynamic>>[],
};

class _Stages extends DefenseStagesNotifier {
  Map<String, dynamic>? saved;

  @override
  DefenseStagesState build() => const DefenseStagesState(stages: [_stage]);

  @override
  Future<void> fetchStages({String? scope,
    String? intake,
    String? phase,
    String? stage,
    String? successMessage,}) async {}

  @override
  Future<Map<String, dynamic>?> fetchStageDetail(
    int stageId, {
    int? semesterId,
  }) async => {'stage': _stage, 'grading_config': <String, dynamic>{}};

  @override
  Future<int?> addStage(Map<String, dynamic> payload) async {
    saved = payload;
    return 9;
  }

  @override
  Future<bool> updateStage(int stageId, Map<String, dynamic> payload) async {
    saved = payload;
    return true;
  }

  @override
  Future<bool> updateGradingConfig(
    int stageId,
    int semesterId,
    Map<String, dynamic> weights,
  ) async => true;
}

class _Periods extends AcademicPeriodNotifier {
  @override
  AcademicPeriodState build() => const AcademicPeriodState(
    activeSemester: {'id': 3, 'display_name': '1st Semester, A.Y. 2026-2027'},
    schoolYears: [
      {
        'id': 1,
        'semesters': [
          {'id': 3, 'display_name': '1st Semester, A.Y. 2026-2027'},
        ],
      },
    ],
  );

  @override
  Future<void> fetchPeriods({String? successMessage}) async {}
}

class _Rubrics extends RubricEngineNotifier {
  @override
  RubricEngineState build() => const RubricEngineState();

  @override
  Future<void> fetchRubrics({
    String? search,
    String? scope,
    String? status,
    String? evaluationType,
    String? termContext,
    String? successMessage,
  }) async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final editing in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        '${editing ? 'Edit' : 'Add'} Capstone auto-adds concept papers in ${dark ? 'dark' : 'light'} mode',
        (tester) async {
          tester.view.physicalSize = const Size(1440, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.runAsync(loadPreviewFonts);
          final stages = _Stages();
          final router = GoRouter(
            initialLocation: AdminRoutes.defenseStages,
            routes: [
              GoRoute(
                path: AdminRoutes.defenseStages,
                builder: (_, _) => Scaffold(
                  body: RepaintBoundary(
                    key: const ValueKey('concept-stage-preview'),
                    child: editing
                        ? DefenseStageEditorScreen(stageId: 7, onBack: () {})
                        : const DefenseStagesScreen(),
                  ),
                ),
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                ...authTestOverrides(),
                defenseStagesProvider.overrideWith(() => stages),
                academicPeriodProvider.overrideWith(_Periods.new),
                rubricEngineProvider.overrideWith(_Rubrics.new),
              ],
              child: RepaintBoundary(
                key: const ValueKey('concept-dialog-preview'),
                child: MaterialApp.router(
                  theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
                  routerConfig: router,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (!editing) {
            await tester.tap(find.text('Add stage'));
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byType(TextField).first,
              'Concept Proposal',
            );
          }

          Future<void> toggleConcepts() async {
            await tester.ensureVisible(find.text('Concept selection'));
            await tester.tap(find.text('Concept selection'));
            await tester.pumpAndSettle();
          }

          Future<void> showRequirements() async {
            await tester.ensureVisible(find.text('3. Deliverables'));
            await tester.tap(find.text('3. Deliverables'));
            await tester.pumpAndSettle();
          }

          void expectPapers() {
            expect(find.text('Pre-defense: 1'), findsOneWidget);
            expect(find.text('Post-defense: 1'), findsOneWidget);
            expect(find.text('Concept Papers'), findsWidgets);
            expect(find.text('Approved Concept Paper'), findsWidgets);
          }

          await toggleConcepts();
          await showRequirements();
          expectPapers();
          await capturePreview(
            tester,
            find.byKey(
              ValueKey(
                editing ? 'concept-stage-preview' : 'concept-dialog-preview',
              ),
            ),
            'capstone-concepts-${editing ? 'edit' : 'add'}-${dark ? 'dark' : 'light'}',
          );

          // Disabling removes automatic requirements; re-enabling adds one pair.
          await tester.ensureVisible(find.text('1. Stage Details'));
          await tester.tap(find.text('1. Stage Details'));
          await tester.pumpAndSettle();
          await toggleConcepts();
          expect(
            tester
                .widget<ConceptSettings>(find.byType(ConceptSettings))
                .value['enabled'],
            false,
          );
          await showRequirements();
          expect(find.text('Pre-defense: 0'), findsOneWidget);
          expect(find.text('Post-defense: 0'), findsOneWidget);
          expect(find.text('Concept Papers'), findsNothing);
          expect(find.text('Approved Concept Paper'), findsNothing);
          await tester.ensureVisible(find.text('1. Stage Details'));
          await tester.tap(find.text('1. Stage Details'));
          await tester.pumpAndSettle();
          await toggleConcepts();

          if (!editing) {
            await tester.tap(find.text('2. Grading & Rubrics'));
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.byKey(const ValueKey('minimum-qualifying-score')),
            );
            await tester.enterText(
              find.byKey(const ValueKey('minimum-qualifying-score')),
              '75',
            );
          }
          await showRequirements();
          expectPapers();
          final save = find.text(editing ? 'Save changes' : 'Add Stage');
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();

          expect(stages.saved?['concept_config']['enabled'], true);
          final files = (stages.saved!['deliverables'] as List).cast<Map>();
          expect(files, hasLength(2));
          final proposals = files.singleWhere(
            (d) => d['file_policy']['mode'] == 'concepts',
          );
          expect(proposals['deliverable_type'], 'pre');
          expect(proposals['required'], true);
          expect(proposals['requirement_timing'], 'scheduling');
          expect(proposals['is_defense_material'], true);
          final approved = files.singleWhere(
            (d) => d['file_policy']['purpose'] == 'approved_concept',
          );
          expect(approved['deliverable_type'], 'post');
          expect(approved['required'], true);
          expect(approved['file_format'], 'pdf');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
