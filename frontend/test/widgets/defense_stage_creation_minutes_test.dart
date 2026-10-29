import 'dart:async';

import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/screens/web/admin/defense_stages/defense_stages_screen.dart';
import 'package:defensys/screens/web/admin/defense_stages/defense_stage_editor_screen.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_minutes_settings.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/services/rubric_engine_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/capture_preview.dart';
import '../helpers/auth_test_overrides.dart';

class _StagesNotifier extends DefenseStagesNotifier {
  Map<String, dynamic>? saved;

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
      'label': 'Legacy Demo Stage',
      'display_order': 1,
      'is_presentation_only': true,
      'qualifying_score': 75,
      'deliverables': [
        {
          'deliverable_id': 'PAPER',
          'label': 'Demo Report',
          'deliverable_type': 'pre',
          'required': true,
        },
      ],
    },
  };

  @override
  Future<bool> updateStage(int stageId, Map<String, dynamic> payload) async {
    saved = Map<String, dynamic>.from(payload);
    return true;
  }

  @override
  Future<bool> updateGradingConfig(
    int stageId,
    int semesterId,
    Map<String, dynamic> weights,
  ) async => true;
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
        await tester.tap(find.text('Add stage'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).first,
          'Concept Proposal',
        );
        await tester.tap(find.text('Signed minutes required'));
        await tester.pumpAndSettle();
        if (!requiredMinutes) {
          await tester.tap(find.text('Minutes not required'));
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
        await tester.tap(find.text('Add Stage'));
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
          expect(stages.saved?['deliverables'], isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
