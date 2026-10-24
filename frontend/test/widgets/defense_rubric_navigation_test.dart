import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/navigation/app_router.dart';
import 'package:defensys/navigation/route_pages.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/screens/web/admin/admin_shell.dart';
import 'package:defensys/screens/web/admin/defense_stages/defense_stage_editor_screen.dart';
import 'package:defensys/screens/web/admin/defense_stages/defense_stages_screen.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_minutes_settings.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_setup_actions.dart';
import 'package:defensys/screens/web/admin/defense_stages/widgets/stage_setup_draft_notice.dart';
import 'package:defensys/screens/web/admin/rubric_engine/rubric_engine_screen.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/app/data_refresh_provider.dart';
import 'package:defensys/services/dashboard_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/services/rubric_engine_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/utils/stage_setup_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/auth_test_overrides.dart';

const _stage = <String, dynamic>{
  'id': 7,
  'label': 'Concept Proposal',
  'code': 'concept-proposal',
  'display_order': 1,
  'is_active': false,
  'is_locked': false,
  'qualifying_score': 75,
};

class _Stages extends DefenseStagesNotifier {
  int adds = 0;
  Map<String, dynamic>? savedUpdate;
  Map<String, dynamic> gradingConfig = {};
  Map<String, dynamic>? savedGrading;
  int? savedStageId;
  bool gradingSucceeds = true;
  bool locked = false;
  @override
  DefenseStagesState build() => const DefenseStagesState(stages: [_stage]);

  @override
  Future<void> fetchStages({String? successMessage}) async {}

  @override
  Future<Map<String, dynamic>?> fetchStageDetail(
    int stageId, {
    int? semesterId,
  }) async => {
    'stage': {..._stage, 'id': stageId, 'is_locked': locked},
    'grading_config': gradingConfig,
  };

  @override
  Future<int?> addStage(Map<String, dynamic> payload) async {
    adds++;
    state = state.copyWith(
      stages: [
        ...state.stages,
        {...payload, 'id': 9},
      ],
    );
    return 9;
  }

  @override
  Future<bool> updateStage(int stageId, Map<String, dynamic> payload) async {
    savedStageId = stageId;
    savedUpdate = Map<String, dynamic>.from(payload);
    return true;
  }

  @override
  Future<bool> updateGradingConfig(
    int stageId,
    int semesterId,
    Map<String, dynamic> weights,
  ) async {
    if (gradingSucceeds) {
      savedGrading = weights;
      gradingConfig = {...gradingConfig, ...weights};
    }
    return gradingSucceeds;
  }
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
  _Rubrics({this.rubrics = const []});
  final List<Map<String, dynamic>> rubrics;
  void offerPanelRubric() => state = state.copyWith(rubrics: [{
    'id': 10, 'name': 'Pending panel rubric', 'scope': 'capstone',
    'semester_id': 3, 'status': 'published', 'evaluation_type': 'panel',
  }]);
  @override
  RubricEngineState build() => RubricEngineState(rubrics: rubrics);

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

class _Dashboard extends DashboardNotifier {
  _Dashboard() : super('admin');

  @override
  Future<void> fetchDashboardData({bool silent = false}) async {}
}

class _Notifications extends NotificationsNotifier {
  _Notifications([super.workspace = 'admin']);

  @override
  Future<void> fetchNotifications({
    bool? unreadOnly,
    bool loadMore = false,
  }) async {}
}

void main() {
  Future<GoRouter> pumpWorkspace(
    WidgetTester tester, {
    bool resetStorage = true,
    String initialLocation = AdminRoutes.defenseStages,
    Map<String, dynamic> gradingConfig = const {},
    List<Map<String, dynamic>> rubricOptions = const [],
  }) async {
    final previousUrlOption = GoRouter.optionURLReflectsImperativeAPIs;
    GoRouter.optionURLReflectsImperativeAPIs = true;
    addTearDown(
      () => GoRouter.optionURLReflectsImperativeAPIs = previousUrlOption,
    );
    if (resetStorage) SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        ...authTestOverrides(),
        defenseStagesProvider.overrideWith(() => _Stages()..gradingConfig = gradingConfig),
        academicPeriodProvider.overrideWith(_Periods.new),
        rubricEngineProvider.overrideWith(() => _Rubrics(rubrics: rubricOptions)),
        dashboardProvider('admin').overrideWith(_Dashboard.new),
        notificationsProvider.overrideWith2(_Notifications.new),
      ],
    );
    addTearDown(container.dispose);
    // The production router allows the admin workspace only on web. Native
    // widget tests use the same two shell branches without the access redirect.
    final router = kIsWeb
        ? container.read(appRouterProvider)
        : GoRouter(
            initialLocation: AdminRoutes.defenseStages,
            routes: [
              StatefulShellRoute.indexedStack(
                builder: (_, _, shell) => AdminShell(navigationShell: shell),
                branches: [
                  StatefulShellBranch(
                    initialLocation: AdminRoutes.defenseStages,
                    routes: [
                      GoRoute(
                        path: AdminRoutes.defenseStages,
                        builder: (_, _) => const DefenseStagesScreen(),
                        routes: [
                          GoRoute(
                            path: ':stageId/edit',
                            builder: (_, state) => AdminDefenseStageEditorRoute(
                              stageId: int.parse(
                                state.pathParameters['stageId']!,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  StatefulShellBranch(
                    initialLocation: AdminRoutes.rubrics,
                    routes: [
                      GoRoute(
                        path: AdminRoutes.rubrics,
                        builder: (_, _) => const RubricEngineScreen(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
    addTearDown(router.dispose);
    router.go(initialLocation);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  for (final shortcut in ['Create rubric']) {
    testWidgets(
      '$shortcut from Add Stage allows returning through the sidebar',
      (tester) async {
        final router = await pumpWorkspace(tester);
        for (var visit = 0; visit < 2; visit++) {
          await tester.tap(find.text('Add stage'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('1. Stage Details'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField).first,
            'Concept draft $visit',
          );
          await tester.enterText(find.byType(TextField).at(1), 'draft-$visit');
          await tester.tap(find.text('Signed minutes required'));
          await tester.tap(find.text('2. Grading & Rubrics'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byKey(const ValueKey('panel-weight')), '65');
          await tester.ensureVisible(find.text(shortcut));
          await tester.tap(find.text(shortcut));
          await tester.pumpAndSettle();
          expect(find.byType(RubricEngineScreen), findsOneWidget);
          expect(find.byType(Dialog), findsNothing);

          await tester.tap(find.text('Defense Stages Setup'));
          await tester.pumpAndSettle();
          expect(find.byType(DefenseStagesScreen), findsOneWidget);
          expect(find.byType(RubricEngineScreen), findsNothing);
          expect(find.text('Resume draft'), findsOneWidget);
          expect(
            router.routeInformationProvider.value.uri.path,
            AdminRoutes.defenseStages,
          );
          await tester.tap(find.text('Resume draft'));
          await tester.pumpAndSettle();
          expect(find.text('65'), findsOneWidget);
          await tester.tap(find.text('1. Stage Details'));
          await tester.pumpAndSettle();
          expect(find.text('Concept draft $visit'), findsWidgets);
          expect(find.text('draft-$visit'), findsOneWidget);
          expect(
            tester
                .widget<StageMinutesSettings>(find.byType(StageMinutesSettings))
                .requiredMinutes,
            isTrue,
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  for (final shortcut in ['Create rubric']) {
    testWidgets(
      '$shortcut from stage editor restores the editor from the sidebar',
      (tester) async {
        final router = await pumpWorkspace(tester);
        await tester.tap(find.byKey(const ValueKey('stage-configure-7')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).first,
          'Edited concept draft',
        );
        await tester.tap(find.text('2. Grading & Rubrics'));
        await tester.pumpAndSettle();
        final editorState = tester.state(find.byType(DefenseStageEditorScreen));
        await tester.ensureVisible(find.text(shortcut));
        await tester.tap(find.text(shortcut));
        await tester.pumpAndSettle();
        expect(find.byType(RubricEngineScreen), findsOneWidget);

        await tester.tap(find.text('Defense Stages Setup'));
        await tester.pumpAndSettle();
        expect(find.byType(DefenseStageEditorScreen), findsOneWidget);
        expect(
          tester.state(find.byType(DefenseStageEditorScreen)),
          same(editorState),
        );
        expect(find.byType(RubricEngineScreen), findsNothing);
        await tester.tap(find.text('1. Stage Details'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'Edited concept draft',
        );
        expect(
          router.routeInformationProvider.value.uri.path,
          AdminRoutes.defenseStageEdit(7),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  const assignedRubrics = {
    'panel_rubric_id': 10, 'panel_rubric_name': 'Published panel rubric',
    'adviser_rubric_id': 15, 'adviser_rubric_name': 'Published adviser rubric',
    'peer_rubric_id': 20, 'peer_rubric_name': 'Published peer rubric',
  };

  for (final creating in [false, true]) {
    testWidgets('Capstone ${creating ? 'creation' : 'editing'} excludes rubrics assigned elsewhere', (tester) async {
      final options = <Map<String, dynamic>>[];
      final grading = <String, dynamic>{};
      for (final (index, role) in ['panel', 'adviser', 'peer'].indexed) {
        final id = 10 + index * 10;
        final rubric = {
          'id': id, 'name': '$role rubric', 'scope': 'capstone', 'semester_id': 3,
          'status': 'published', 'evaluation_type': role, 'defense_stage_id': 7,
          'is_locked': true,
        };
        grading['${role}_rubric_id'] = id;
        grading['${role}_rubric_name'] = rubric['name'];
        options.addAll([
          rubric,
          {...rubric, 'id': id + 1, 'defense_stage_id': 8},
          {...rubric, 'id': id + 2, 'defense_stage_id': null, 'is_locked': false,
            'name': 'Available $role'},
          {...rubric, 'id': id + 3, 'defense_stage_id': null, 'semester_id': 9},
          {...rubric, 'id': id + 4, 'defense_stage_id': null, 'status': 'draft'},
          {...rubric, 'id': id + 5, 'defense_stage_id': null},
          {...rubric, 'id': id + 6, 'defense_stage_id': 8, 'is_locked': false},
        ]);
      }
      await pumpWorkspace(tester,
        initialLocation: creating ? AdminRoutes.defenseStages : AdminRoutes.defenseStageEdit(7),
        gradingConfig: grading, rubricOptions: options);
      if (creating) {
        await tester.tap(find.text('Add stage'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('2. Grading & Rubrics'));
      await tester.pumpAndSettle();
      for (final (index, role) in ['panel', 'adviser', 'peer'].indexed) {
        final id = 10 + index * 10;
        final picker = find.byKey(ValueKey('$role-rubric-${creating ? 0 : id}'));
        final items = tester.widget<ShadSelect<int>>(picker).options!.whereType<ShadOption<int>>();
        expect(items.map((item) => item.value), [0, if (!creating) id, id + 2]);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('returning from Rubrics refreshes stage assignments without losing edits', (tester) async {
    await pumpWorkspace(tester, initialLocation: AdminRoutes.defenseStageEdit(7),
      gradingConfig: assignedRubrics);
    final container = ProviderScope.containerOf(tester.element(find.byType(DefenseStageEditorScreen)));
    final stages = container.read(defenseStagesProvider.notifier) as _Stages;
    await tester.enterText(find.byType(TextField).first, 'Keep my stage edits');
    await tester.tap(find.text('2. Grading & Rubrics'));
    await tester.pumpAndSettle();
    final oldPanel = find.byKey(const ValueKey('panel-rubric-10'));
    await tester.ensureVisible(oldPanel);
    await tester.tap(oldPanel);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select later').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Manage rubrics'));
    await tester.tap(find.text('Manage rubrics'));
    await tester.pumpAndSettle();
    final newAssignments = {...assignedRubrics,
      'panel_rubric_id': 30, 'panel_rubric_name': 'New panel assignment'};
    stages.gradingConfig = newAssignments;
    container.read(dataRefreshProvider.notifier).markChanged([DataArea.defenseStages]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Defense Stages Setup'));
    await tester.pumpAndSettle();
    for (final role in ['panel', 'adviser', 'peer']) {
      final id = newAssignments['${role}_rubric_id'];
      final picker = find.byKey(ValueKey('$role-rubric-$id'));
      expect(tester.widget<ShadSelect<int>>(picker).initialValue, id);
      expect(find.text(newAssignments['${role}_rubric_name'] as String), findsOneWidget);
    }
    await tester.tap(find.text('1. Stage Details'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Keep my stage edits');
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    for (final role in ['panel', 'adviser', 'peer']) {
      expect(stages.gradingConfig['${role}_rubric_id'], newAssignments['${role}_rubric_id']);
      expect(stages.savedGrading!.containsKey('${role}_rubric_id'), isFalse);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('restoring an old stage draft keeps newly assigned rubrics', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await StageSetupDraftStore(userId: '1', semesterId: 3, stageId: 7).save(
      StageSetupDraft(tab: 1, fields: {
        ..._stage,
        'label': 'Saved setup edits',
        'grading_config': {
          'panel_weight': 60, 'adviser_weight': 20, 'peer_weight': 20,
          'panel_rubric_id': null, 'adviser_rubric_id': null, 'peer_rubric_id': null,
        },
      }),
    );
    await pumpWorkspace(tester, resetStorage: false,
      initialLocation: AdminRoutes.defenseStageEdit(7), gradingConfig: assignedRubrics);
    for (final role in ['panel', 'adviser', 'peer']) {
      expect(find.byKey(ValueKey('$role-rubric-${assignedRubrics['${role}_rubric_id']}')), findsOneWidget);
    }
    await tester.tap(find.text('1. Stage Details'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Saved setup edits');
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicitly clearing a stage rubric survives draft restoration', (tester) async {
    await pumpWorkspace(tester, initialLocation: AdminRoutes.defenseStageEdit(7),
      gradingConfig: assignedRubrics);
    await tester.tap(find.text('2. Grading & Rubrics'));
    await tester.pumpAndSettle();
    final picker = find.byKey(const ValueKey('panel-rubric-10'));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select later').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save draft'));
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpWorkspace(tester, resetStorage: false,
      initialLocation: AdminRoutes.defenseStageEdit(7), gradingConfig: assignedRubrics);
    expect(find.byKey(const ValueKey('panel-rubric-0')), findsOneWidget);
    final stages = ProviderScope.containerOf(tester.element(find.byType(DefenseStageEditorScreen)))
        .read(defenseStagesProvider.notifier) as _Stages;
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(stages.savedGrading!.containsKey('panel_rubric_id'), isTrue);
    expect(stages.savedGrading!['panel_rubric_id'], isNull);
    expect(stages.gradingConfig['adviser_rubric_id'], 15);
    expect(stages.gradingConfig['peer_rubric_id'], 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual draft keeps required minutes after a workspace rebuild', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    await tester.tap(find.text('Add stage'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StageMinutesSettings>(find.byType(StageMinutesSettings))
          .requiredMinutes,
      isTrue,
    );
    await tester.enterText(find.byType(TextField).first, 'Reloadable concept');
    await tester.tap(find.text('3. Deliverables'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Pre-Defense'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Concept manuscript',
    );
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    dismissFeedbackToasts();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpWorkspace(tester, resetStorage: false);
    await tester.tap(find.text('Resume draft'));
    await tester.pumpAndSettle();
    expect(find.text('Concept manuscript'), findsOneWidget);
    await tester.tap(find.text('1. Stage Details'));
    await tester.pumpAndSettle();
    expect(find.text('Reloadable concept'), findsWidgets);
    expect(
      tester
          .widget<StageMinutesSettings>(find.byType(StageMinutesSettings))
          .requiredMinutes,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  for (final tab in [0, 1, 2]) {
    testWidgets('capstone rename updates original stage from step ${tab + 1}', (tester) async {
      final router = await pumpWorkspace(tester,
        initialLocation: AdminRoutes.defenseStageEdit(7));
      final stages = ProviderScope.containerOf(
        tester.element(find.byType(DefenseStageEditorScreen)),
      ).read(defenseStagesProvider.notifier) as _Stages;
      await tester.enterText(find.byType(TextField).first, 'Updated Concept Proposal');
      if (tab > 0) {
        await tester.tap(find.text(tab == 1 ? '2. Grading & Rubrics' : '3. Deliverables'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(stages.savedStageId, 7);
      expect(stages.savedUpdate?['label'], 'Updated Concept Proposal');
      expect(stages.adds, 0);
      expect(router.routeInformationProvider.value.uri.path, AdminRoutes.defenseStages);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('new stage starts with signed minutes required', (tester) async {
    await pumpWorkspace(tester);
    final stages =
        ProviderScope.containerOf(
              tester.element(find.byType(DefenseStagesScreen)),
            ).read(defenseStagesProvider.notifier)
            as _Stages;
    await tester.tap(find.text('Add stage'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Concept');
    expect(find.text('Stage policies'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Session documentation')).dy,
      lessThan(tester.getTopLeft(find.text('Concept selection')).dy),
    );
    await tester.tap(find.text('Next: Grading & Rubrics'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('minimum-qualifying-score')), '75');
    await tester.tap(find.text('3. Deliverables'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Stage'));
    await tester.pumpAndSettle();
    expect(stages.adds, 1);
    expect(
      await StageSetupDraftStore(userId: '1', semesterId: 3).load(),
      isNull,
    );
    expect(find.text('Resume draft'), findsNothing);
    dismissFeedbackToasts();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editor draft survives workspace rebuild and successful save clears it',
    (tester) async {
      final router = await pumpWorkspace(tester);
      router.go(AdminRoutes.defenseStageEdit(7));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Reloadable edit');
      await tester.tap(find.text('Minutes not required'));
      await tester.ensureVisible(find.text('Save draft'));
      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final rebuilt = await pumpWorkspace(
        tester,
        resetStorage: false,
        initialLocation: AdminRoutes.defenseStageEdit(7),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Reloadable edit',
      );
      expect(find.text('Stage setup draft saved'), findsOneWidget);
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        await StageSetupDraftStore(
          userId: '1',
          semesterId: 3,
          stageId: 7,
        ).load(),
        isNull,
      );
      expect(
        rebuilt.routeInformationProvider.value.uri.path,
        AdminRoutes.defenseStages,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Edit Stage draft preserves scheduling review and panel visibility',
    (tester) async {
      var router = await pumpWorkspace(tester);
      router.go(AdminRoutes.defenseStageEdit(7));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Minutes not required'));
      await tester.tap(find.text('3. Deliverables'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Pre-Defense'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Pre-Defense Requirement Name *',
        ),
        'Panel Deck',
      );
      await tester.tap(find.text('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Defense material for panelists'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Required').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save draft'));
      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      router = await pumpWorkspace(
        tester,
        resetStorage: false,
        initialLocation: AdminRoutes.defenseStageEdit(7),
      );
      expect(find.text('Panel Deck'), findsWidgets);
      final stages =
          ProviderScope.containerOf(
                tester.element(find.byType(DefenseStageEditorScreen)),
              ).read(defenseStagesProvider.notifier)
              as _Stages;
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      final files = (stages.savedUpdate?['deliverables'] as List).cast<Map>();
      expect(files.length, 1);
      expect(files.single['label'], 'Panel Deck');
      expect(files.single['requirement_timing'], 'scheduling');
      expect(files.single['deadline_hours_before'], 24);
      expect(files.single['is_defense_material'], true);
      expect(files.single['required'], false);
      expect(
        router.routeInformationProvider.value.uri.path,
        AdminRoutes.defenseStages,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'partial creation resumes the created stage without duplicating it',
    (tester) async {
      final router = await pumpWorkspace(tester);
      final stages =
          ProviderScope.containerOf(
                tester.element(find.byType(DefenseStagesScreen)),
              ).read(defenseStagesProvider.notifier)
              as _Stages;
      stages.gradingSucceeds = false;
      (ProviderScope.containerOf(tester.element(find.byType(DefenseStagesScreen)))
          .read(rubricEngineProvider.notifier) as _Rubrics).offerPanelRubric();
      await tester.tap(find.text('Add stage'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Pending grading');
      await tester.tap(find.text('Minutes not required'));
      await tester.tap(find.text('2. Grading & Rubrics'));
      await tester.pumpAndSettle();
      final panelPicker = find.byKey(const ValueKey('panel-rubric-0'));
      await tester.enterText(find.byKey(const ValueKey('minimum-qualifying-score')), '75');
      await tester.ensureVisible(panelPicker);
      await tester.tap(panelPicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pending panel rubric').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('3. Deliverables'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Stage'));
      await tester.pumpAndSettle();
      expect(stages.adds, 1);
      expect(find.text('Resume draft'), findsOneWidget);
      await tester.tap(find.text('Resume draft'));
      await tester.pumpAndSettle();
      expect(find.byType(DefenseStageEditorScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('panel-rubric-10')), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.path,
        AdminRoutes.defenseStageEdit(9, initialTab: 1).split('?').first,
      );
      expect(stages.adds, 1);
      expect(
        await StageSetupDraftStore(
          userId: '1',
          semesterId: 3,
          stageId: 9,
        ).load(),
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'discarding a creation draft requires confirmation and removes its saved setup',
    (tester) async {
      await pumpWorkspace(tester);
      await tester.tap(find.text('Add stage'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Discardable draft');
      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();
      dismissFeedbackToasts();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Resume draft'), findsOneWidget);
      await tester.tap(find.text('Discard draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard draft').last);
      await tester.pumpAndSettle();
      expect(find.text('Resume draft'), findsNothing);
      expect(
        await StageSetupDraftStore(userId: '1', semesterId: 3).load(),
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a browser draft cannot override a stage locked by the server', (
    tester,
  ) async {
    final router = await pumpWorkspace(tester);
    final stages =
        ProviderScope.containerOf(
              tester.element(find.byType(DefenseStagesScreen)),
            ).read(defenseStagesProvider.notifier)
            as _Stages;
    stages.locked = true;
    await StageSetupDraftStore(userId: '1', semesterId: 3, stageId: 7).save(
      StageSetupDraft(
        fields: {
          'label': 'Blocked override',
          'is_locked': false,
          'minutes_required': true,
        },
        tab: 0,
      ),
    );
    router.go(AdminRoutes.defenseStageEdit(7));
    await tester.pumpAndSettle();
    expect(find.text('Stage Configuration Locked'), findsOneWidget);
    expect(find.text('Blocked override'), findsNothing);
    expect(find.text('Save draft'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Concept Proposal',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('draft notice and footer actions fit a narrow window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                StageSetupDraftNotice(
                  title:
                      'Stage setup draft: a long concept proposal configuration',
                  onDiscard: () {},
                  onResume: () {},
                ),
                const SizedBox(height: 16),
                StageSetupActions(
                  children: [
                    TextButton(onPressed: () {}, child: const Text('Cancel')),
                    OutlinedButton(
                      onPressed: () {},
                      child: const Text('Save draft'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {},
                      child: const Text('Next: Grading & Rubrics'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Resume draft'), findsOneWidget);
    expect(find.text('Save draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
