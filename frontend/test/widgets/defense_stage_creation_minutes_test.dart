import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/screens/web/admin/defense_stages/defense_stages_screen.dart';
import 'package:defensys/screens/web/admin/defense_stages/defense_stage_editor_screen.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_minutes_settings.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_weekly_settings.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/services/rubric_engine_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/utils/stage_setup_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../helpers/capture_preview.dart';
import '../helpers/stage_setup.dart';
import '../helpers/auth_test_overrides.dart';

class _StagesNotifier extends DefenseStagesNotifier {
  _StagesNotifier({this.conceptSelection = false, this.published = true,
    this.structureLocked = false, this.gradingConfig = const {},
    this.requirementSettings = const {}});
  final bool conceptSelection;
  final bool published;
  final bool structureLocked;
  final Map<String, dynamic> gradingConfig;
  final Map<String, dynamic> requirementSettings;
  Map<String, dynamic>? saved;
  Map<String, dynamic>? gradingSaved;
  bool gradingSucceeds = true;
  final saves = <String>[];

  @override
  DefenseStagesState build() => const DefenseStagesState();

  @override
  Future<void> fetchStages({String? scope,
    String? intake,
    String? phase,
    String? stage,
    String? successMessage,}) async {}

  @override
  Future<int?> addStage(Map<String, dynamic> payload) async {
    saves.add('create:${payload['is_active']}');
    saved = Map<String, dynamic>.from(payload);
    return 9;
  }

  @override
  Future<Map<String, dynamic>?> fetchStageDetail(
    int stageId, {
    int? semesterId,
  }) async => {
    'stage': {
      'id': stageId,
      'is_active': published,
      'structure_locked': structureLocked,
      if (structureLocked) 'structure_lock_reason': 'Scheduled defenses protect publication.',
      'label': 'Legacy Demo Stage',
      'display_order': 1,
      'is_presentation_only': true,
      'qualifying_score': 75,
      'concept_config': {'enabled': conceptSelection, 'required_count': 3},
      'shared_deliverables': [],
      'deliverables': [
        {
          'deliverable_id': 'PAPER',
          'label': 'Demo Report',
          'deliverable_type': 'pre',
          'required': true,
        },
      ],
      ...requirementSettings,
    },
    'grading_config': gradingConfig,
  };

  @override
  Future<bool> updateStage(int stageId, Map<String, dynamic> payload) async {
    saves.add('update:${payload['is_active']}');
    saved = {...?saved, ...payload};
    return true;
  }

  @override
  Future<bool> updateGradingConfig(
    int stageId,
    int semesterId,
    Map<String, dynamic> weights,
  ) async {
    gradingSaved = Map<String, dynamic>.from(weights);
    saves.add('grading');
    return gradingSucceeds;
  }
}

class _PeriodsNotifier extends AcademicPeriodNotifier {
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

class _RubricsNotifier extends RubricEngineNotifier {
  @override
  RubricEngineState build() => RubricEngineState(rubrics: [
    for (final (index, role) in ['panel', 'adviser', 'peer'].indexed)
      {'id': index + 1, 'name': 'Test $role rubric', 'scope': 'capstone',
        'semester_id': 3, 'status': 'published', 'evaluation_type': role},
  ]);

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

class _NoRubricsNotifier extends _RubricsNotifier {
  @override
  RubricEngineState build() => const RubricEngineState();
}

class _DelayedStages extends _StagesNotifier {
  final ready = Completer<void>();
  bool started = false;
  bool detailStarted = false;

  @override
  Future<void> fetchStages({String? scope, String? intake, String? phase,
    String? stage, String? successMessage}) async {
    started = true;
    await ready.future;
  }

  @override
  Future<Map<String, dynamic>?> fetchStageDetail(int stageId, {int? semesterId}) {
    detailStarted = true;
    return super.fetchStageDetail(stageId, semesterId: semesterId);
  }
}

class _DelayedPeriods extends _PeriodsNotifier {
  final ready = Completer<void>();
  bool started = false;

  @override
  Future<void> fetchPeriods({String? successMessage}) async {
    started = true;
    await ready.future;
  }
}

class _DelayedRubrics extends _RubricsNotifier {
  final ready = Completer<void>();
  bool started = false;

  @override
  Future<void> fetchRubrics({String? search, String? scope, String? status,
    String? evaluationType, String? termContext, String? successMessage}) async {
    started = true;
    await ready.future;
  }
}

class _TemplatePicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({String? dialogTitle, String? initialDirectory,
    FileType type = FileType.any, List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading, bool allowCompression = true,
    int compressionQuality = 30, bool allowMultiple = false, bool withData = false,
    bool withReadStream = false, bool lockParentWindow = false, bool readSequential = false,
  }) async => FilePickerResult([
    PlatformFile(name: 'Paper.docx', size: 8, bytes: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
  ]);
}

Future<void> _pumpCreation(WidgetTester tester, _StagesNotifier stages, {
  bool dark = false,
  bool publishedRubrics = true,
}) async {
  final router = GoRouter(initialLocation: AdminRoutes.defenseStages, routes: [
    GoRoute(path: AdminRoutes.defenseStages,
      builder: (_, _) => const Scaffold(body: DefenseStagesScreen())),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(overrides: [
    ...authTestOverrides(), defenseStagesProvider.overrideWith(() => stages),
    academicPeriodProvider.overrideWith(_PeriodsNotifier.new),
    rubricEngineProvider.overrideWith(
      publishedRubrics ? _RubricsNotifier.new : _NoRubricsNotifier.new,
    ),
  ], child: RepaintBoundary(key: const ValueKey('stage-layout-preview'),
    child: MaterialApp.router(theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
      routerConfig: router))));
  await tester.pumpAndSettle();
}

Map<String, dynamic> _readyConceptDraft() => {
  'label': 'Concept Proposal', 'code': 'concept-proposal', 'qualifying_score': 75,
  'minutes_required': false, 'concept_config': {'enabled': true, 'required_count': 3},
  'shared_deliverables': [],
  'grading_config': {'panel_rubric_id': 1},
  'deliverables': [
    {'deliverable_id': 'PAPERS', 'label': 'Concept Papers', 'deliverable_type': 'pre',
      'required': true, 'requirement_timing': 'scheduling', 'file_policy': {'mode': 'concepts'}},
  ],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final editing in [false, true]) {
    for (final concept in [false, true]) {
      testWidgets(
        'Select later publishes ${concept ? 'concept' : 'standard'} stage from ${editing ? 'editor' : 'creation'} without rubrics',
        (tester) async {
          tester.view.physicalSize = const Size(1366, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final stages = _StagesNotifier(
            conceptSelection: concept,
            published: false,
            requirementSettings: {'minutes_required': false},
          );
          if (editing) {
            await tester.pumpWidget(ProviderScope(
              overrides: [
                ...authTestOverrides(),
                defenseStagesProvider.overrideWith(() => stages),
                academicPeriodProvider.overrideWith(_PeriodsNotifier.new),
                rubricEngineProvider.overrideWith(_NoRubricsNotifier.new),
              ],
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                home: Scaffold(body: DefenseStageEditorScreen(
                  stageId: 9, initialTab: 1, onBack: () {},
                )),
              ),
            ));
            await tester.pumpAndSettle();
          } else {
            await StageSetupDraftStore(userId: '1', semesterId: 3).save(
              StageSetupDraft(fields: {
                ..._readyConceptDraft(),
                'concept_config': {'enabled': concept, 'required_count': 3},
                'grading_config': <String, dynamic>{},
              }, tab: 1),
            );
            await _pumpCreation(tester, stages, publishedRubrics: false);
            await tester.tap(find.text('Resume draft'));
            await tester.pumpAndSettle();
          }

          expect(find.text('Select later'), findsNWidgets(concept ? 1 : 3));
          await tester.ensureVisible(find.text('Next: Deliverables'));
          await tester.tap(find.text('Next: Deliverables'));
          await tester.pumpAndSettle();
          expect(find.byKey(ValueKey(
            editing ? 'stage-editor-step-2' : 'stage-dialog-step-2',
          )), findsOneWidget);
          await chooseStagePublication(tester, true);
          await tester.ensureVisible(find.text('Publish stage'));
          await tester.tap(find.text('Publish stage'));
          await tester.pumpAndSettle();

          expect(stages.saves, [
            editing ? 'update:false' : 'create:false', 'grading', 'update:true',
          ]);
          expect(stages.saved?['is_active'], isTrue);
          expect(stages.gradingSaved?['panel_rubric_id'], isNull);
          expect(stages.gradingSaved?['panel_weight'], concept ? 100 : 50);
          expect(stages.gradingSaved?['adviser_weight'], concept ? 0 : 30);
          expect(stages.gradingSaved?['peer_weight'], concept ? 0 : 20);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final editing in [false, true]) {
    for (final dark in [false, true]) {
      for (final size in [const Size(1366, 768), const Size(390, 844)]) {
        testWidgets(
          'requirement links scroll to settings in ${editing ? 'editor' : 'dialog'} '
          'at ${size.width} dark=$dark and retain edits',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.runAsync(() => loadPreviewFonts());
            final settings = {
              ..._readyConceptDraft(),
              'minutes_required': true,
              'weekly_reporting': {
                'enabled': true,
                'starts_on': '2026-10-25',
                'total_weeks': 16,
                'due_weekday': 6,
                'due_time': '23:59',
                'required_start': 1,
                'required_end': 2,
              },
              'weekly_template': {
                'template': {
                  'original_name': 'Weekly.pdf',
                  'byte_size': 2048,
                  'file_url': '/template.pdf',
                },
              },
            };
            final stages = _StagesNotifier(requirementSettings: settings);
            if (editing) {
              await tester.pumpWidget(ProviderScope(
                overrides: [
                  ...authTestOverrides(),
                  defenseStagesProvider.overrideWith(() => stages),
                  academicPeriodProvider.overrideWith(_PeriodsNotifier.new),
                  rubricEngineProvider.overrideWith(_RubricsNotifier.new),
                ],
                child: RepaintBoundary(
                  key: const ValueKey('stage-layout-preview'),
                  child: MaterialApp(
                    theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
                    home: Scaffold(body: DefenseStageEditorScreen(
                      stageId: 9, initialTab: 2, onBack: () {},
                    )),
                  ),
                ),
              ));
              await tester.pumpAndSettle();
            } else {
              await StageSetupDraftStore(userId: '1', semesterId: 3).save(
                StageSetupDraft(fields: settings, tab: 2),
              );
              await _pumpCreation(tester, stages, dark: dark);
              await tester.tap(find.text('Resume draft'));
              await tester.pumpAndSettle();
            }

            final previewName = 'stage-requirements-${editing ? 'editor' : 'dialog'}-'
                '${size.width.toInt()}-${dark ? 'dark' : 'light'}';
            final weeklyRow = find.byType(StageWeeklyRequirementRow);
            await tester.ensureVisible(find.text('Pre-Defense Requirements'));
            await tester.pumpAndSettle();
            await capturePreview(tester,
              find.byKey(const ValueKey('stage-layout-preview')),
              '$previewName-deliverables');
            await tester.tap(weeklyRow);
            await tester.pumpAndSettle();

            void expectRequirementsVisible() {
              final scrollView = find.byKey(ValueKey(
                editing ? 'stage-editor-step-0' : 'stage-dialog-step-0',
              ));
              expect(scrollView, findsOneWidget);
              final viewport = tester.getRect(scrollView);
              final heading = tester.getRect(find.text('Stage requirements'));
              expect(heading.top, greaterThanOrEqualTo(viewport.top));
              expect(heading.bottom, lessThan(viewport.bottom));
              expect(find.byKey(const ValueKey('stage-minutes-switch')).hitTestable(), findsOneWidget);
              expect(find.byKey(const ValueKey('configure-weekly-reports')).hitTestable(), findsOneWidget);
            }

            expectRequirementsVisible();
            await tester.tap(find.byKey(const ValueKey('configure-weekly-reports')));
            await tester.pumpAndSettle();
            final count = find.byKey(const ValueKey('weekly-report_count'));
            await tester.ensureVisible(count);
            await tester.enterText(count, '3');
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.byKey(const ValueKey('configure-weekly-reports')));
            await tester.tap(find.byKey(const ValueKey('configure-weekly-reports')));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('3. Deliverables'));
            await tester.tap(find.text('3. Deliverables'));
            await tester.pumpAndSettle();
            expect(find.textContaining('Weeks 1-3'), findsOneWidget);

            await tester.ensureVisible(find.text('Signed Minutes'));
            await tester.tap(find.text('Signed Minutes'));
            await tester.pumpAndSettle();
            final minutesName = find.byKey(const ValueKey('minutes-deliverable-name'));
            await tester.ensureVisible(minutesName);
            await tester.enterText(minutesName, 'Official Signed Minutes');
            await tester.ensureVisible(find.text('Change in Stage Details'));
            await tester.tap(find.text('Change in Stage Details'));
            await tester.pumpAndSettle();
            expectRequirementsVisible();
            expect(find.textContaining('3 reports'), findsOneWidget);
            await capturePreview(tester,
              find.byKey(const ValueKey('stage-layout-preview')),
              '$previewName-jump');

            await tester.ensureVisible(find.text('3. Deliverables'));
            await tester.tap(find.text('3. Deliverables'));
            await tester.pumpAndSettle();
            expect(tester.widget<TextField>(minutesName).controller?.text,
              'Official Signed Minutes');
            expect(stages.saved, isNull);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  for (final dark in [false, true]) {
    for (final size in [const Size(1366, 768), const Size(390, 844)]) {
      testWidgets('stage workflow choices are visible at ${size.width} in ${dark ? 'dark' : 'light'} mode', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() => loadPreviewFonts());
        await _pumpCreation(tester, _StagesNotifier(), dark: dark);
        await tester.tap(find.text('Add stage'));
        await tester.pumpAndSettle();
        final concept = find.byKey(const ValueKey('stage-workflow-concept'));
        expect(tester.getRect(concept).top, greaterThan(0));
        expect(tester.getRect(concept).bottom, lessThan(size.height));
        expect(find.text('Published Stage'), findsNothing);
        expect(find.text('Publish stage'), findsNothing);
        await capturePreview(tester, find.byKey(const ValueKey('stage-layout-preview')),
          'stage-layout-${size.width.toInt()}-${dark ? 'dark' : 'light'}');
        // The padding around the radio label is also a selection target.
        await tester.tapAt(tester.getRect(concept).bottomRight - const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.text('Panel evaluation: 100%'), findsOneWidget);
        final standard = find.byKey(const ValueKey('stage-workflow-standard'));
        await tester.ensureVisible(standard);
        await tester.tapAt(tester.getRect(standard).bottomRight - const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.text('Panel evaluation: 100%'), findsNothing);
        final publication = find.byKey(const ValueKey('stage-publication-switch'));
        await tester.ensureVisible(publication);
        await tester.pumpAndSettle();
        expect(find.text('Published stage'), findsOneWidget);
        expect(find.text('Review stage setup'), findsNothing);
        expect(tester.getTopLeft(publication).dy,
          greaterThan(tester.getTopLeft(find.text('Stage description')).dy));
        await capturePreview(tester, find.byKey(const ValueKey('stage-layout-preview')),
          'stage-publication-${size.width.toInt()}-${dark ? 'dark' : 'light'}');
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final gradingSucceeds in [true, false]) {
    testWidgets('final publish ${gradingSucceeds ? 'follows grading save' : 'stops after grading failure'}', (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await StageSetupDraftStore(userId: '1', semesterId: 3).save(
        StageSetupDraft(fields: _readyConceptDraft(), tab: 0));
      final stages = _StagesNotifier()..gradingSucceeds = gradingSucceeds;
      await _pumpCreation(tester, stages);
      await tester.tap(find.text('Resume draft'));
      await tester.pumpAndSettle();
      expect(find.text('Publish stage'), findsNothing);
      await tester.tap(find.text('2. Grading & Rubrics'));
      await tester.pumpAndSettle();
      expect(find.text('Publish stage'), findsNothing);
      await tester.tap(find.text('3. Deliverables'));
      await tester.pumpAndSettle();
      await chooseStagePublication(tester, true);
      expect(stagePublishEnabled(tester), isTrue);
      expect(find.text('Review stage setup'), findsNothing);
      expect(find.byKey(const ValueKey('stage-publication-switch')), findsNothing);
      await capturePreview(tester, find.byKey(const ValueKey('stage-layout-preview')),
        'stage-final-review');
      await tester.tap(find.text('Publish stage'));
      await tester.pumpAndSettle();
      expect(stages.saves, ['create:false', 'grading', if (gradingSucceeds) 'update:true']);
      expect(stages.saved?['is_active'], gradingSucceeds);
      final draft = await StageSetupDraftStore(userId: '1', semesterId: 3).load();
      expect(draft, gradingSucceeds ? isNull : isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('an unpublished editor publishes only from the final step', (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final stages = _StagesNotifier(conceptSelection: true, published: false,
      gradingConfig: {'panel_rubric_id': 1});
    await tester.pumpWidget(ProviderScope(overrides: [
      ...authTestOverrides(), defenseStagesProvider.overrideWith(() => stages),
      academicPeriodProvider.overrideWith(_PeriodsNotifier.new),
      rubricEngineProvider.overrideWith(_RubricsNotifier.new),
    ], child: MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(
      body: DefenseStageEditorScreen(stageId: 9, onBack: () {})))));
    await tester.pumpAndSettle();
    expect(find.text('Publish stage'), findsNothing);
    await tester.tap(find.text('2. Grading & Rubrics'));
    await tester.pumpAndSettle();
    expect(find.text('Publish stage'), findsNothing);
    await tester.ensureVisible(find.text('3. Deliverables'));
    await tester.tap(find.text('3. Deliverables'));
    await tester.pumpAndSettle();
    await chooseStagePublication(tester, true);
    await tester.ensureVisible(find.text('Publish stage'));
    await tester.tap(find.text('Publish stage'));
    await tester.pumpAndSettle();
    expect(stages.saves, ['update:false', 'grading', 'update:true']);
    expect(stages.saved?['is_active'], isTrue);
    expect(tester.takeException(), isNull);
  });
  for (final locked in [false, true]) {
    testWidgets('published stage switch ${locked ? 'respects defense locks' : 'returns the stage to draft on save'}', (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final stages = _StagesNotifier(conceptSelection: true, structureLocked: locked,
        gradingConfig: {'panel_rubric_id': 1});
      await tester.pumpWidget(ProviderScope(overrides: [
        ...authTestOverrides(), defenseStagesProvider.overrideWith(() => stages),
        academicPeriodProvider.overrideWith(_PeriodsNotifier.new),
        rubricEngineProvider.overrideWith(_RubricsNotifier.new),
      ], child: MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(
        body: DefenseStageEditorScreen(stageId: 9, initialTab: 2, onBack: () {})))));
      await tester.pumpAndSettle();
      if (locked) {
        await tester.ensureVisible(find.text('1. Stage Details'));
        await tester.tap(find.text('1. Stage Details'));
        await tester.pumpAndSettle();
        final toggle = tester.widget<ShadSwitch>(find.byKey(const ValueKey('stage-publication-switch')));
        expect(toggle.enabled, isFalse);
        expect(toggle.value, isTrue);
        expect(find.text('Scheduled defenses protect publication.'), findsWidgets);
      } else {
        await chooseStagePublication(tester, false);
        expect(stages.saves, isEmpty);
        await tester.ensureVisible(find.text('Unpublish stage'));
        await tester.tap(find.text('Unpublish stage'));
        await tester.pumpAndSettle();
        expect(stages.saves, ['update:false', 'grading']);
        expect(stages.saved?['is_active'], isFalse);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('concept editor saves panel-only weights with ordinary hidden draft defaults', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final stages = _StagesNotifier(conceptSelection: true);
    await tester.pumpWidget(ProviderScope(overrides: [
      ...authTestOverrides(),
      defenseStagesProvider.overrideWith(() => stages),
      academicPeriodProvider.overrideWith(_PeriodsNotifier.new),
      rubricEngineProvider.overrideWith(_RubricsNotifier.new),
    ], child: MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(
      body: DefenseStageEditorScreen(stageId: 9, initialTab: 1, onBack: () {}),
    ))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('panel-fixed-weight')), findsOneWidget);
    expect(find.byKey(const ValueKey('adviser-weight')), findsNothing);
    expect(find.byKey(const ValueKey('peer-weight')), findsNothing);
    await tester.tap(find.text('3. Deliverables'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(stages.gradingSaved?['panel_weight'], 100);
    expect(stages.gradingSaved?['adviser_weight'], 0);
    expect(stages.gradingSaved?['peer_weight'], 0);
    expect(stages.gradingSaved?.containsKey('adviser_rubric_id'), false);
    expect(stages.gradingSaved?.containsKey('peer_rubric_id'), false);
    expect(stages.gradingSaved?.containsKey('default_slot_duration_minutes'), false);
    expect((stages.saved?['concept_config'] as Map?)?['enabled'], true);
    expect(tester.takeException(), isNull);
  });
  for (final scope in ['team', 'shared']) {
    testWidgets('restored $scope template keeps Add Stage open until reselected or removed', (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requirement = <String, dynamic>{'deliverable_id': scope == 'team' ? 'D1' : 'PM1',
        'label': 'Concept Papers', 'deliverable_type': 'pre', 'required': true,
        'template_action': 'replace', 'template_selection_name': 'Paper.docx', 'template_selection_size': 8};
      await StageSetupDraftStore(userId: '1', semesterId: 3).save(StageSetupDraft(fields: {
        'label': 'Concept Proposal', 'qualifying_score': 75, 'minutes_required': false,
        'grading_config': {'panel_rubric_id': 1, 'adviser_rubric_id': 2, 'peer_rubric_id': 3},
        'deliverables': scope == 'team' ? [requirement] : [],
        'shared_deliverables': scope == 'shared' ? [requirement] : [],
      }, tab: 2));
      final stages = _StagesNotifier();
      final router = GoRouter(initialLocation: AdminRoutes.defenseStages, routes: [
        GoRoute(path: AdminRoutes.defenseStages,
          builder: (_, _) => const Scaffold(body: DefenseStagesScreen())),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(overrides: [
        ...authTestOverrides(), defenseStagesProvider.overrideWith(() => stages),
        academicPeriodProvider.overrideWith(_PeriodsNotifier.new),
        rubricEngineProvider.overrideWith(_RubricsNotifier.new),
      ], child: MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume draft'));
      await tester.pumpAndSettle();
      expect(stagePublishEnabled(tester), isFalse);
      await tester.tap(find.text('Save as draft'));
      await tester.pumpAndSettle();
      expect(stages.saved, isNull);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.textContaining('Select the template for "Concept Papers" again'), findsWidgets);
      expect(find.text('Replace'), findsOneWidget);
      expect(find.text('Connection Failed'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      if (scope == 'team') {
        FilePicker.platform = _TemplatePicker();
        await tester.tap(find.text('Replace'));
      } else {
        await tester.tap(find.text('Remove'));
      }
      await tester.pumpAndSettle();
      await chooseStagePublication(tester, true);
      await tester.tap(find.text('Publish stage'));
      await tester.pumpAndSettle();
      expect(stages.saved, isNotNull);
      final drafts = stages.saved!['_templateDrafts'] as List;
      final selected = (drafts.single as Map)['row'] as Map;
      if (scope == 'team') {
        expect((selected['_templateFile'] as PlatformFile).bytes, isNotEmpty);
      } else {
        expect(selected['template_action'], 'remove');
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('stage editor starts independent reads together', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final stages = _DelayedStages();
    final periods = _DelayedPeriods();
    final rubrics = _DelayedRubrics();
    addTearDown(() {
      for (final gate in [stages.ready, periods.ready, rubrics.ready]) {
        if (!gate.isCompleted) gate.complete();
      }
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...authTestOverrides(),
        defenseStagesProvider.overrideWith(() => stages),
        academicPeriodProvider.overrideWith(() => periods),
        rubricEngineProvider.overrideWith(() => rubrics),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: DefenseStageEditorScreen(stageId: 9, onBack: () {})),
      ),
    ));
    await tester.pump();
    expect(stages.started, isTrue);
    expect(periods.started, isTrue);
    expect(rubrics.started, isTrue);
    expect(stages.detailStarted, isFalse);
    periods.ready.complete();
    await tester.pump();
    expect(stages.detailStarted, isTrue);
    stages.ready.complete();
    rubrics.ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('Legacy Demo Stage'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'editing a legacy demo stage keeps file requirements visible and saves them',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => loadPreviewFonts());
      final stages = _StagesNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...authTestOverrides(),
            defenseStagesProvider.overrideWith(() => stages),
            academicPeriodProvider.overrideWith(_PeriodsNotifier.new),
            rubricEngineProvider.overrideWith(_RubricsNotifier.new),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: DefenseStageEditorScreen(
                stageId: 9,
                initialTab: 2,
                onBack: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Presentation / Demo Only'), findsNothing);
      expect(
        find.text('Will students submit files for this stage?'),
        findsNothing,
      );
      expect(find.text('Demo Report'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('pre-defense-deliverables-section')), matching: find.text('Add deliverable'),), findsOneWidget,);
      expect(find.descendant(of: find.byKey(const ValueKey('post-defense-deliverables-section')), matching: find.text('Add deliverable'),), findsOneWidget,);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(stages.saved?['is_presentation_only'], false);
      expect(
        (stages.saved?['deliverables'] as List).single['label'],
        'Demo Report',
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final requiredMinutes in [false, true]) {
    testWidgets(
      'Add Stage saves minutes=$requiredMinutes with student file submissions',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() => loadPreviewFonts());
        if (requiredMinutes) {
          await StageSetupDraftStore(userId: '1', semesterId: 3).save(
            StageSetupDraft(fields: {'label': 'Concept Proposal', 'display_order': 4}, tab: 0),
          );
        }
        final stages = _StagesNotifier();
        final router = GoRouter(
          initialLocation: AdminRoutes.defenseStages,
          routes: [
            GoRoute(
              path: AdminRoutes.defenseStages,
              builder: (_, _) => const Scaffold(
                body: RepaintBoundary(
                  key: ValueKey('stage-creation-preview'),
                  child: DefenseStagesScreen(),
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
              academicPeriodProvider.overrideWith(_PeriodsNotifier.new),
              rubricEngineProvider.overrideWith(_RubricsNotifier.new),
            ],
            child: RepaintBoundary(
              key: const ValueKey('stage-dialog-preview'),
              child: MaterialApp.router(
                theme: AppTheme.lightTheme,
                routerConfig: router,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (!requiredMinutes) {
          await capturePreview(
            tester,
            find.byKey(const ValueKey('stage-creation-preview')),
            'stage-setup-empty-centered',
          );
        }
        await tester.tap(find.text(requiredMinutes ? 'Resume draft' : 'Add stage'));
        await tester.pumpAndSettle();
        expect(find.text('Position 1 of 1'), findsOneWidget);
        await tester.enterText(
          find.byType(TextField).first,
          'Concept Proposal',
        );
        await chooseStageMinutes(tester, true);
        await tester.pumpAndSettle();
        if (!requiredMinutes) {
          await chooseStageMinutes(tester, false);
          await tester.pumpAndSettle();
        }
        if (requiredMinutes) {
          await capturePreview(
            tester,
            find.byKey(const ValueKey('stage-dialog-preview')),
            'stage-setup-minutes-selector',
          );
        }
        await tester.tap(find.text('2. Grading & Rubrics'));
        await tester.pumpAndSettle();
        await chooseStageRubrics(tester);
        await tester.ensureVisible(
          find.byKey(const ValueKey('minimum-qualifying-score')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('minimum-qualifying-score')),
          '75',
        );
        await tester.tap(find.text('3. Deliverables'));
        await tester.pumpAndSettle();
        expect(find.text('Presentation / Demo Only'), findsNothing);
        expect(
          find.text('Will students submit files for this stage?'),
          findsNothing,
        );
        expect(find.descendant(of: find.byKey(const ValueKey('pre-defense-deliverables-section')), matching: find.text('Add deliverable'),), findsOneWidget,);
        expect(find.descendant(of: find.byKey(const ValueKey('post-defense-deliverables-section')), matching: find.text('Add deliverable'),), findsOneWidget,);
        expect(
          find.byType(StageMinutesDeliverableCard),
          requiredMinutes ? findsOneWidget : findsNothing,
        );
        if (requiredMinutes) {
          expect(find.text('System records (1)'), findsOneWidget);
          expect(find.text('Signed Minutes'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('minutes-deliverable-number')),
            findsNothing,
          );
          await tester.ensureVisible(find.text('Signed Minutes'));
          await tester.tap(find.text('Signed Minutes'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('minutes-deliverable-number')),
          );
          await tester.enterText(
            find.byKey(const ValueKey('minutes-deliverable-number')),
            'DOC-7',
          );
          await tester.enterText(
            find.byKey(const ValueKey('minutes-deliverable-name')),
            'Official Signed Minutes',
          );
          await tester.tap(find.text('Change in Stage Details'));
          await tester.pumpAndSettle();
          expect(find.text('Session documentation'), findsOneWidget);
          await tester.tap(find.text('3. Deliverables'));
          await tester.pumpAndSettle();
        }
        if (requiredMinutes) {
          await tester.tap(find.descendant(of: find.byKey(const ValueKey('pre-defense-deliverables-section'),), matching: find.text('Add deliverable'),
            ),);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.labelText ==
                      'Pre-Defense Deliverable Name *',
            ),
            'Panel Deck',
          );
          await tester.tap(find.text('More options'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Defense material for panelists'));
          await tester.pumpAndSettle();
          expect(find.text('Before scheduled defense'), findsNothing);
          await tester.ensureVisible(find.text('Required').last);
          await tester.tap(find.text('Required').last);
          await tester.pumpAndSettle();

          await tester.ensureVisible(find.descendant(of: find.byKey(const ValueKey('post-defense-deliverables-section'),), matching: find.text('Add deliverable'),
            ),);
          await tester.tap(find.descendant(of: find.byKey(const ValueKey('post-defense-deliverables-section'),), matching: find.text('Add deliverable'),
            ),);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.labelText ==
                      'Post-Defense Deliverable Name *',
            ),
            'Revision Matrix',
          );
          await tester.tap(find.text('More options'));
          await tester.pumpAndSettle();
          expect(find.text('Approved with revisions only'), findsNothing);
          await capturePreview(
            tester,
            find.byKey(const ValueKey('stage-dialog-preview')),
            'stage-setup-step-three-controls',
          );
        }
        if (!requiredMinutes) {
          final add = find.descendant(of: find.byKey(const ValueKey('pre-defense-deliverables-section')), matching: find.text('Add deliverable'));
          await tester.ensureVisible(add);
          await tester.tap(add);
          await tester.pumpAndSettle();
          await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Pre-Defense Deliverable Name *'), 'Panel Deck');
          await tester.pumpAndSettle();
        }
        await chooseStagePublication(tester, true);
        await tester.tap(find.text('Publish stage'));
        await tester.pumpAndSettle();
        expect(stages.saved?['minutes_required'], requiredMinutes);
        expect(stages.saved?['is_presentation_only'], false);
        expect(
          stages.saved?['minutes_deliverable_id'],
          requiredMinutes ? 'DOC-7' : 'MINUTES',
        );
        expect(
          stages.saved?['minutes_deliverable_label'],
          requiredMinutes ? 'Official Signed Minutes' : '',
        );
        if (requiredMinutes) {
          final files = (stages.saved?['deliverables'] as List).cast<Map>();
          expect(files.length, 2);
          expect(files[0]['label'], 'Panel Deck');
          expect(files[0]['requirement_timing'], 'scheduling');
          expect(files[0]['deadline_hours_before'], 24);
          expect(files[0]['is_defense_material'], true);
          expect(files[0]['required'], false);
          expect(files[1]['label'], 'Revision Matrix');
          expect(files[1]['verdict_condition'], 'all_pass');
          expect(files[1]['required'], true);
        } else {
          expect((stages.saved?['deliverables'] as List).single['label'], 'Panel Deck');
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
