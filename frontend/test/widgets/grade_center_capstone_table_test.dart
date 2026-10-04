import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/admin/grade_center_capstone_table.dart';
import 'package:defensys/screens/web/admin/grade_center_shared.dart';
import 'package:defensys/services/grade_center_provider.dart';
import 'package:defensys/theme/app_theme.dart';

import '../helpers/pump_app.dart';

void main() {
  for (final scope in ['capstone', 'pit']) {
    for (final scenario in [
      (
        name: 'missing evaluations',
        visibleReady: false,
        visibleTeams: 1,
        total: null,
        ready: null,
        enabled: false,
        reason: '1 of 1 teams still need required evaluations.',
      ),
      (
        name: 'incomplete team hidden by filters',
        visibleReady: true,
        visibleTeams: 1,
        total: 2,
        ready: 1,
        enabled: false,
        reason: '1 of 2 teams still need required evaluations.',
      ),
      (
        name: 'all teams hidden by filters',
        visibleReady: true,
        visibleTeams: 0,
        total: 2,
        ready: 1,
        enabled: false,
        reason: '1 of 2 teams still need required evaluations.',
      ),
      (
        name: 'empty group',
        visibleReady: false,
        visibleTeams: 0,
        total: 0,
        ready: 0,
        enabled: false,
        reason: 'Schedule teams before marking complete.',
      ),
      (
        name: 'ready group',
        visibleReady: true,
        visibleTeams: 1,
        total: 2,
        ready: 2,
        enabled: true,
        reason: '',
      ),
    ]) {
      testWidgets(
        '$scope checks grading before confirmation: ${scenario.name}',
        (tester) async {
          tester.view.physicalSize = const Size(1400, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final searchController = TextEditingController();
          addTearDown(searchController.dispose);
          const label = 'Evaluation Stage';
          bool? updatedValue;
          final state = GradeCenterState(
            search: 'Visible team',
            grades: List.generate(
              scenario.visibleTeams,
              (index) => {
                'id': index + 1,
                'scope': scope,
                'stage_label': label,
                'grading_ready': scenario.visibleReady,
              },
            ),
            groupSettings: {
              '$scope|$label': {
                'is_officially_complete': false,
                if (scenario.total != null)
                  'grading_total_team_count': scenario.total,
                if (scenario.ready != null)
                  'grading_ready_team_count': scenario.ready,
              },
            },
          );
          await pumpDefensysWidget(
            tester,
            SingleChildScrollView(
              child: CapstoneStagesUnifiedCard(
                scope: scope,
                state: state,
                stages: const [
                  {'label': label, 'event_name': label, 'display_order': 1},
                ],
                isAdmin: true,
                searchController: searchController,
                scopeFilter: const SizedBox(height: 40),
                yearLevelFilter: const SizedBox(height: 40),
                statusFilter: const SizedBox(height: 40),
                onOpenStage: (_) {},
                onCheckCompletion: (_) async => GradeGroupCompletionReadiness(
                  totalTeams: scenario.total ?? scenario.visibleTeams,
                  readyTeams: scenario.ready ?? 0,
                  canComplete: scenario.enabled,
                  incompleteTeams: scenario.enabled || scenario.total == 0
                      ? []
                      : [
                          {
                            'team_name': 'Team Missing Grades',
                            'missing_components': ['panel'],
                          },
                        ],
                ),
                onOfficiallyCompleteChanged: (_, value) => updatedValue = value,
                onSearchChanged: (_) {},
                onSearchSubmitted: (_) {},
                onSearchFocusChanged: (_) {},
              ),
            ),
          );

          final button = find
              .ancestor(
                of: find.text('Mark Complete'),
                matching: find.byWidgetPredicate(
                  (widget) => widget is ElevatedButton,
                ),
              )
              .first;
          expect(
            tester.widget<ElevatedButton>(button).onPressed != null,
            isTrue,
          );
          if (scenario.reason.isNotEmpty) {
            expect(find.text(scenario.reason), findsOneWidget);
          }
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(
            find.text('Mark $label Complete?'),
            scenario.enabled ? findsOneWidget : findsNothing,
          );
          expect(updatedValue, isNull);
          if (!scenario.enabled) {
            expect(find.text('Grading not ready'), findsOneWidget);
            if (scenario.total != 0) {
              expect(find.text('Team Missing Grades'), findsOneWidget);
            }
          }
          if (scenario.enabled) {
            expect(
              find.textContaining('2 teams will be affected.'),
              findsOneWidget,
            );
            await tester.tap(
              find.widgetWithText(ElevatedButton, 'Mark Complete').last,
            );
            await tester.pumpAndSettle();
            expect(updatedValue, isTrue);
          }
        },
      );
    }

    testWidgets('$scope detail controls guard teams hidden by filters', (
      tester,
    ) async {
      bool? updatedValue;
      await pumpDefensysWidget(
        tester,
        gradeGroupStageControlsSection(
          state: const GradeCenterState(),
          scope: scope,
          stageLabel: 'Milestone',
          isOfficiallyComplete: false,
          peerGradingEnabled: false,
          groupSettings: const {
            'grading_total_team_count': 2,
            'grading_ready_team_count': 1,
          },
          grades: const [
            {'grading_ready': true},
          ],
          checkCompletion: () async => const GradeGroupCompletionReadiness(
            totalTeams: 2,
            readyTeams: 1,
            canComplete: false,
            incompleteTeams: [
              {
                'team_name': 'Team Hidden',
                'missing_components': ['panel'],
              },
            ],
          ),
          onOfficiallyCompleteChanged: (value) => updatedValue = value,
          onPeerGradingChanged: (_) {},
        ),
      );
      expect(find.text('1 of 2 teams grading-ready'), findsOneWidget);
      expect(
        find.text('1 of 2 teams still need required evaluations.'),
        findsOneWidget,
      );
      final button = find
          .ancestor(
            of: find.text('Mark Complete'),
            matching: find.byType(InkWell),
          )
          .first;
      expect(tester.widget<InkWell>(button).onTap, isNotNull);
      await tester.tap(find.text('Mark Complete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Complete?'), findsNothing);
      expect(find.text('Team Hidden'), findsOneWidget);
      expect(updatedValue, isNull);
    });

    testWidgets(
      '$scope completed detail controls can reopen without ready grades',
      (tester) async {
        bool? updatedValue;
        await pumpDefensysWidget(
          tester,
          gradeGroupStageControlsSection(
            state: const GradeCenterState(),
            scope: scope,
            stageLabel: 'Milestone',
            isOfficiallyComplete: true,
            peerGradingEnabled: false,
            grades: const [
              {'grading_ready': false},
            ],
            checkCompletion: () async =>
                throw StateError('Reopening must not check readiness'),
            onOfficiallyCompleteChanged: (value) => updatedValue = value,
            onPeerGradingChanged: (_) {},
          ),
        );
        await tester.tap(find.text('Reopen'));
        await tester.pumpAndSettle();
        expect(find.text('Reopen Milestone?'), findsOneWidget);
        await tester.tap(
          find.widgetWithText(
            ElevatedButton,
            scope == 'pit' ? 'Reopen Event' : 'Reopen Stage',
          ),
        );
        await tester.pumpAndSettle();
        expect(updatedValue, isFalse);
      },
    );
  }

  for (final isDark in [false, true]) {
    for (final scenario in [
      (
        name: 'zero completed teams',
        scope: 'capstone',
        teamCount: 16,
        panelDone: 0,
        adviserDone: 0,
        peerDone: 0,
        optionalEnabled: true,
        greenComponents: <String>{},
      ),
      (
        name: 'partially completed components',
        scope: 'capstone',
        teamCount: 16,
        panelDone: 16,
        adviserDone: 8,
        peerDone: 0,
        optionalEnabled: true,
        greenComponents: {'Panel'},
      ),
      (
        name: 'all evaluations submitted before official completion',
        scope: 'capstone',
        teamCount: 16,
        panelDone: 16,
        adviserDone: 16,
        peerDone: 16,
        optionalEnabled: true,
        greenComponents: {'Panel', 'Adviser', 'Peer'},
      ),
      (
        name: 'no scheduled teams',
        scope: 'capstone',
        teamCount: 0,
        panelDone: 0,
        adviserDone: 0,
        peerDone: 0,
        optionalEnabled: true,
        greenComponents: <String>{},
      ),
      (
        name: 'disabled optional evaluations',
        scope: 'capstone',
        teamCount: 16,
        panelDone: 16,
        adviserDone: 16,
        peerDone: 16,
        optionalEnabled: false,
        greenComponents: {'Panel'},
      ),
      (
        name: 'PIT components complete independently',
        scope: 'pit',
        teamCount: 16,
        panelDone: 8,
        adviserDone: 0,
        peerDone: 16,
        optionalEnabled: true,
        greenComponents: {'Peer'},
      ),
    ]) {
      testWidgets(
        '${scenario.name} uses accurate component colors (${isDark ? 'dark' : 'light'})',
        (tester) async {
          tester.view.physicalSize = const Size(1400, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          const label = 'Evaluation Stage';
          final isPit = scenario.scope == 'pit';
          final state = GradeCenterState(
            grades: List.generate(
              scenario.teamCount,
              (index) => {
                'id': index + 1,
                'scope': scenario.scope,
                'stage_label': label,
                'panel_complete': index < scenario.panelDone,
                'adviser_complete': index < scenario.adviserDone,
                'peer_eval_complete': index < scenario.peerDone,
              },
            ),
            activeSemester: {
              'capstone_peer_evaluation_enabled': scenario.optionalEnabled,
              'capstone_adviser_grading_enabled': scenario.optionalEnabled,
            },
            groupSettings: {
              '${scenario.scope}|$label': {
                'is_officially_complete': false,
                'peer_grading_enabled': isPit && scenario.optionalEnabled,
              },
            },
          );
          final searchController = TextEditingController();
          addTearDown(searchController.dispose);

          await pumpDefensysWidget(
            tester,
            Theme(
              data: isDark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
              child: SingleChildScrollView(
                child: CapstoneStagesUnifiedCard(
                  scope: scenario.scope,
                  state: state,
                  stages: [
                    {'label': label, 'event_name': label, 'display_order': 1},
                  ],
                  isAdmin: true,
                  searchController: searchController,
                  scopeFilter: const SizedBox(height: 40),
                  yearLevelFilter: const SizedBox(height: 40),
                  statusFilter: const SizedBox(height: 40),
                  onOpenStage: (_) {},
                  onOfficiallyCompleteChanged: (_, __) {},
                  onSearchChanged: (_) {},
                  onSearchSubmitted: (_) {},
                  onSearchFocusChanged: (_) {},
                ),
              ),
            ),
          );

          for (final component in ['Panel', if (!isPit) 'Adviser', 'Peer']) {
            final pill = tester.widget<Container>(
              find
                  .ancestor(
                    of: find.text(component),
                    matching: find.byType(Container),
                  )
                  .first,
            );
            final decoration = pill.decoration! as BoxDecoration;
            final completedColor = isDark
                ? const Color(0xFF064E3B).withValues(alpha: 0.35)
                : const Color(0xFFECFDF5);
            expect(
              decoration.color,
              scenario.greenComponents.contains(component)
                  ? completedColor
                  : (isDark
                        ? AppTheme.mistDarkTheme.colorScheme.surface
                        : Colors.white),
              reason: '$component must reflect submitted evaluations',
            );
          }
          expect(
            find.text(scenario.teamCount > 0 ? 'IN PROGRESS' : 'NOT STARTED'),
            findsOneWidget,
          );
          if (isPit) expect(find.text('Adviser'), findsNothing);
        },
      );
    }
  }

  testWidgets(
    'CapstoneStagesUnifiedCard renders stage milestone cards with actions',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const state = GradeCenterState(
        grades: [
          {
            'id': 1,
            'scope': 'capstone',
            'stage_label': 'Concept Proposal',
            'team_name': 'Team Alpha',
          },
        ],
        activeSemester: {
          'display_name': '2026-2027 · 2nd Semester',
          'capstone_peer_evaluation_enabled': true,
          'capstone_adviser_grading_enabled': true,
        },
        groupSettings: {
          'capstone|Concept Proposal': {
            'scope': 'capstone',
            'stage_label': 'Concept Proposal',
            'is_officially_complete': false,
            'peer_grading_enabled': false,
          },
        },
      );

      final stages = [
        {
          'label': 'Concept Proposal',
          'display_order': 1,
          'description': 'Concept stage',
          'is_active': true,
        },
        {
          'label': 'Final Defense',
          'display_order': 3,
          'description': 'Final stage',
          'is_active': true,
        },
      ];

      final searchController = TextEditingController();

      await pumpDefensysWidget(
        tester,
        SizedBox(
          width: 1400,
          child: SingleChildScrollView(
            child: CapstoneStagesUnifiedCard(
              state: state,
              stages: stages,
              stagesLoading: false,
              isAdmin: true,
              searchController: searchController,
              scopeFilter: const SizedBox(height: 40),
              yearLevelFilter: const SizedBox(height: 40),
              statusFilter: const SizedBox(height: 40),
              onOpenStage: (_) {},
              onOfficiallyCompleteChanged: (_, __) {},
              onSearchChanged: (_) {},
              onSearchSubmitted: (_) {},
              onSearchFocusChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Concept Proposal'), findsOneWidget);
      expect(find.text('Final Defense'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(2));
      expect(find.text('Mark Complete'), findsNWidgets(2));

      searchController.dispose();
    },
  );

  testWidgets(
    'CapstoneStagesUnifiedCard renders Officially Complete badge when complete',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const state = GradeCenterState(
        grades: [
          {
            'id': 1,
            'scope': 'capstone',
            'stage_label': 'Concept Proposal',
            'team_name': 'Team Alpha',
          },
        ],
        groupSettings: {
          'capstone|Concept Proposal': {
            'scope': 'capstone',
            'stage_label': 'Concept Proposal',
            'is_officially_complete': true,
            'peer_grading_enabled': false,
          },
        },
      );

      final stages = [
        {
          'label': 'Concept Proposal',
          'display_order': 1,
          'description': 'Concept stage',
          'is_active': true,
        },
      ];

      final searchController = TextEditingController();

      await pumpDefensysWidget(
        tester,
        SizedBox(
          width: 1400,
          child: SingleChildScrollView(
            child: CapstoneStagesUnifiedCard(
              state: state,
              stages: stages,
              stagesLoading: false,
              isAdmin: true,
              searchController: searchController,
              scopeFilter: const SizedBox(height: 40),
              yearLevelFilter: const SizedBox(height: 40),
              statusFilter: const SizedBox(height: 40),
              onOpenStage: (_) {},
              onOfficiallyCompleteChanged: (_, __) {},
              onSearchChanged: (_) {},
              onSearchSubmitted: (_) {},
              onSearchFocusChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('OFFICIALLY COMPLETE'), findsOneWidget);
      expect(find.text('Reopen Stage'), findsOneWidget);
      searchController.dispose();
    },
  );

  testWidgets(
    'Tapping Reopen opens confirm dialog and invokes callback with false',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool? updatedValue;
      const state = GradeCenterState(
        grades: [
          {
            'id': 1,
            'scope': 'capstone',
            'stage_label': 'Concept Proposal',
            'team_name': 'Team Alpha',
          },
        ],
        groupSettings: {
          'capstone|Concept Proposal': {
            'scope': 'capstone',
            'stage_label': 'Concept Proposal',
            'is_officially_complete': true,
            'peer_grading_enabled': false,
          },
        },
      );

      final stages = [
        {
          'label': 'Concept Proposal',
          'display_order': 1,
          'description': 'Concept stage',
          'is_active': true,
        },
      ];

      final searchController = TextEditingController();

      await pumpDefensysWidget(
        tester,
        SizedBox(
          width: 1400,
          child: SingleChildScrollView(
            child: CapstoneStagesUnifiedCard(
              state: state,
              stages: stages,
              stagesLoading: false,
              isAdmin: true,
              searchController: searchController,
              scopeFilter: const SizedBox(height: 40),
              yearLevelFilter: const SizedBox(height: 40),
              statusFilter: const SizedBox(height: 40),
              onOpenStage: (_) {},
              onOfficiallyCompleteChanged: (_, val) {
                updatedValue = val;
              },
              onSearchChanged: (_) {},
              onSearchSubmitted: (_) {},
              onSearchFocusChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Reopen Stage'), findsOneWidget);

      // Tap Reopen Stage
      await tester.tap(find.text('Reopen Stage'));
      await tester.pumpAndSettle();

      // Confirm dialog should be visible
      expect(find.text('Reopen Concept Proposal?'), findsOneWidget);

      // Tap Confirm button in dialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reopen Stage'));
      await tester.pumpAndSettle();

      expect(updatedValue, isFalse);

      searchController.dispose();
    },
  );

  testWidgets(
    'Tapping Mark Complete opens confirm dialog and invokes callback on confirm',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool? updatedValue;
      const state = GradeCenterState(
        grades: [
          {
            'id': 1,
            'scope': 'capstone',
            'stage_label': 'Concept Proposal',
            'team_name': 'Team Alpha',
            'grading_ready': true,
          },
        ],
        groupSettings: {
          'capstone|Concept Proposal': {
            'scope': 'capstone',
            'stage_label': 'Concept Proposal',
            'is_officially_complete': false,
          },
        },
      );

      final stages = [
        {
          'label': 'Concept Proposal',
          'display_order': 1,
          'description': 'Concept stage',
          'is_active': true,
        },
      ];

      final searchController = TextEditingController();

      await pumpDefensysWidget(
        tester,
        SizedBox(
          width: 1400,
          child: SingleChildScrollView(
            child: CapstoneStagesUnifiedCard(
              state: state,
              stages: stages,
              stagesLoading: false,
              isAdmin: true,
              searchController: searchController,
              scopeFilter: const SizedBox(height: 40),
              yearLevelFilter: const SizedBox(height: 40),
              statusFilter: const SizedBox(height: 40),
              onOpenStage: (_) {},
              onCheckCompletion: (_) async =>
                  const GradeGroupCompletionReadiness(
                    totalTeams: 1,
                    readyTeams: 1,
                    canComplete: true,
                  ),
              onOfficiallyCompleteChanged: (_, val) {
                updatedValue = val;
              },
              onSearchChanged: (_) {},
              onSearchSubmitted: (_) {},
              onSearchFocusChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Mark Complete'), findsOneWidget);

      // Tap Mark Complete
      await tester.tap(find.text('Mark Complete'));
      await tester.pumpAndSettle();

      // Confirm dialog should be visible
      expect(find.text('Mark Concept Proposal Complete?'), findsOneWidget);

      // Tap Confirm button in dialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Mark Complete'));
      await tester.pumpAndSettle();

      expect(updatedValue, isTrue);

      searchController.dispose();
    },
  );

  testWidgets(
    'CapstoneStagesUnifiedCard renders PIT stage milestone cards with peer toggle and snapshot',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const state = GradeCenterState(
        grades: [
          {
            'id': 101,
            'scope': 'pit',
            'stage_label': '1st Year Concept Pitch',
            'team_name': 'PIT Team Alpha',
            'grading_ready': true,
          },
        ],
        activeSemester: {'display_name': '2026-2027 · 1st Semester'},
        pitEvents: [
          {
            'event_name': '1st Year Concept Pitch',
            'display_order': 1,
            'panel_weight': 80,
            'peer_weight': 20,
            'is_officially_complete': false,
            'peer_grading_enabled': true,
          },
        ],
        groupSettings: {
          'pit|1st Year Concept Pitch': {
            'scope': 'pit',
            'stage_label': '1st Year Concept Pitch',
            'is_officially_complete': false,
            'peer_grading_enabled': true,
          },
        },
      );

      final searchController = TextEditingController();

      await pumpDefensysWidget(
        tester,
        SizedBox(
          width: 1400,
          child: SingleChildScrollView(
            child: CapstoneStagesUnifiedCard(
              scope: 'pit',
              state: state,
              stages: state.pitEvents,
              stagesLoading: false,
              isAdmin: true,
              searchController: searchController,
              scopeFilter: const SizedBox(height: 40),
              yearLevelFilter: const SizedBox(height: 40),
              statusFilter: const SizedBox(height: 40),
              onOpenStage: (_) {},
              onOfficiallyCompleteChanged: (_, __) {},
              onPeerGradingChanged: (_, __) {},
              onSearchChanged: (_) {},
              onSearchSubmitted: (_) {},
              onSearchFocusChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('PIT Expos & Event Stages'), findsOneWidget);
      expect(find.text('1st Year Concept Pitch'), findsOneWidget);
      expect(find.text('Peer grading open'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(find.text('Mark Complete'), findsOneWidget);
      expect(find.text('ENROLLED TEAMS'), findsOneWidget);
      expect(find.text('EVALUATION READINESS'), findsOneWidget);
      expect(find.text('EVALUATION COMPONENTS'), findsOneWidget);

      searchController.dispose();
    },
  );

  testWidgets(
    'CapstoneStagesUnifiedCard renders All Scopes with Capstone and PIT milestone cards',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const state = GradeCenterState(
        grades: [
          {
            'id': 1,
            'scope': 'capstone',
            'stage_label': 'Concept Proposal',
            'team_name': 'Team Alpha',
            'grading_ready': true,
          },
          {
            'id': 101,
            'scope': 'pit',
            'stage_label': '1st Year Concept Pitch',
            'team_name': 'PIT Team Alpha',
            'grading_ready': true,
          },
        ],
        activeSemester: {
          'display_name': '2026-2027 · 1st Semester',
          'capstone_peer_evaluation_enabled': true,
          'capstone_adviser_grading_enabled': true,
        },
        pitEvents: [
          {
            'event_name': '1st Year Concept Pitch',
            'display_order': 1,
            'panel_weight': 80,
            'peer_weight': 20,
            'is_officially_complete': false,
            'peer_grading_enabled': true,
          },
        ],
        groupSettings: {
          'capstone|Concept Proposal': {
            'scope': 'capstone',
            'stage_label': 'Concept Proposal',
            'is_officially_complete': false,
            'peer_grading_enabled': false,
          },
          'pit|1st Year Concept Pitch': {
            'scope': 'pit',
            'stage_label': '1st Year Concept Pitch',
            'is_officially_complete': false,
            'peer_grading_enabled': true,
          },
        },
      );

      final stages = [
        {
          'label': 'Concept Proposal',
          'display_order': 1,
          'description': 'Concept stage',
          'is_active': true,
        },
      ];

      final searchController = TextEditingController();

      await pumpDefensysWidget(
        tester,
        SizedBox(
          width: 1400,
          child: SingleChildScrollView(
            child: CapstoneStagesUnifiedCard(
              scope: 'all',
              state: state,
              stages: stages,
              stagesLoading: false,
              isAdmin: true,
              searchController: searchController,
              scopeFilter: const SizedBox(height: 40),
              yearLevelFilter: const SizedBox(height: 40),
              statusFilter: const SizedBox(height: 40),
              onOpenStage: (_) {},
              onOfficiallyCompleteChanged: (_, __) {},
              onPeerGradingChanged: (_, __) {},
              onSearchChanged: (_) {},
              onSearchSubmitted: (_) {},
              onSearchFocusChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('All Grade Groups'), findsOneWidget);
      expect(find.text('Capstone · Concept Proposal'), findsOneWidget);
      expect(find.text('PIT · 1st Year Concept Pitch'), findsOneWidget);
      expect(find.text('Peer grading open'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(2));
      expect(find.text('Mark Complete'), findsNWidgets(2));

      searchController.dispose();
    },
  );

  testWidgets(
    'gradeCenterKpiStatCard renders scoped title and metrics properly',
    (tester) async {
      await pumpDefensysWidget(
        tester,
        gradeCenterKpiStatCard(
          title: 'Total Capstone teams',
          value: '0',
          icon: Icons.groups_rounded,
          accent: const Color(0xFF2563EB),
          iconBg: const Color(0xFFEFF6FF),
          progress: 0,
        ),
      );

      expect(find.text('Total Capstone teams'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
    },
  );
}
