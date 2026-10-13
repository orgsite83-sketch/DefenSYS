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
};

class _Stages extends DefenseStagesNotifier {
  int adds = 0;
  Map<String, dynamic>? savedUpdate;
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
    savedUpdate = Map<String, dynamic>.from(payload);
    return true;
  }

  @override
  Future<bool> updateGradingConfig(
    int stageId,
    int semesterId,
    Map<String, dynamic> weights,
  ) async => gradingSucceeds;
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
        defenseStagesProvider.overrideWith(_Stages.new),
        academicPeriodProvider.overrideWith(_Periods.new),
        rubricEngineProvider.overrideWith(_Rubrics.new),
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

  for (final shortcut in ['Create Rubric', 'Manage in Rubrics']) {
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
          await tester.enterText(find.byType(TextField).first, '65');
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

  for (final shortcut in ['Create Rubrics', 'Manage Evaluation Rubrics']) {
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

  testWidgets(
    'manual draft survives a rebuilt workspace with its deliverables and unanswered minutes',
    (tester) async {
      await pumpWorkspace(tester);
      await tester.tap(find.text('Add stage'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StageMinutesSettings>(find.byType(StageMinutesSettings))
            .requiredMinutes,
        isNull,
      );
      await tester.enterText(
        find.byType(TextField).first,
        'Reloadable concept',
      );
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
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new stage requires an explicit minutes choice for Next and Add Stage',
    (tester) async {
      await pumpWorkspace(tester);
      final stages =
          ProviderScope.containerOf(
                tester.element(find.byType(DefenseStagesScreen)),
              ).read(defenseStagesProvider.notifier)
              as _Stages;
      await tester.tap(find.text('Add stage'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Concept');
      await tester.tap(find.text('Next: Grading & Rubrics'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StageMinutesSettings>(find.byType(StageMinutesSettings))
            .requiredMinutes,
        isNull,
      );
      expect(
        find.text('Choose Signed minutes required or Minutes not required.'),
        findsOneWidget,
      );
      await tester.tap(find.text('3. Deliverables'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Stage'));
      await tester.pumpAndSettle();
      expect(stages.adds, 0);
      expect(find.byType(StageMinutesSettings), findsOneWidget);
      await tester.tap(find.text('Minutes not required'));
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
    },
  );

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
    'Edit Stage draft preserves independent defense timing and visibility',
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
      await tester.tap(find.text('Before scheduled defense').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('stage-custom-deadline-hours')),
        '36',
      );
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
      expect(files.single['requirement_timing'], 'defense');
      expect(files.single['deadline_hours_before'], 36);
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
      await tester.tap(find.text('Add stage'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Pending grading');
      await tester.tap(find.text('Minutes not required'));
      await tester.tap(find.text('3. Deliverables'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Stage'));
      await tester.pumpAndSettle();
      expect(stages.adds, 1);
      expect(find.text('Resume draft'), findsOneWidget);
      await tester.tap(find.text('Resume draft'));
      await tester.pumpAndSettle();
      expect(find.byType(DefenseStageEditorScreen), findsOneWidget);
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
