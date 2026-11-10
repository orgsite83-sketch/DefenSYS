import 'package:defensys/screens/web/admin/defense_board/defense_board_screen.dart';
import 'package:defensys/screens/web/admin/defense_board/components/session_evaluator_access_dialog.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/team_readiness_tracker.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/defense_scheduler_screen.dart';
import 'package:defensys/services/admin/external_evaluator_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/defense_board_provider.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/defense/capstone_scheduling_api.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/export/report_export_menu.dart';
import 'package:defensys/widgets/table/defensys_segmented_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../helpers/capture_preview.dart';

class _Board extends DefenseBoardNotifier {
  _Board(this.schedules);
  final List<Map<String, dynamic>> schedules;
  @override
  DefenseBoardState build() => DefenseBoardState(
    schedules: schedules,
    statuses: schedules
        .map((row) => row['display_status'].toString())
        .toSet()
        .toList(),
  );
  @override
  Future<void> fetchBoard({
    String? search,
    String? stage,
    String? status,
    String? scope,
    String? adviser,
    String? section,
    String? successMessage,
  }) async {
    final selectedScope = scope ?? state.scope;
    final selectedSearch = search ?? state.search;
    final selectedStage = stage ?? state.stage;
    final selectedStatus = status ?? state.status;
    final scoped = schedules
        .where((row) => selectedScope.isEmpty || row['scope'] == selectedScope)
        .toList();
    state = state.copyWith(
      scope: selectedScope,
      search: selectedSearch,
      stage: selectedStage,
      status: selectedStatus,
      adviser: adviser,
      section: section,
      counts: {'scope_total': scoped.length},
      stageOptions: scoped
          .map((row) => row['stage_label'].toString())
          .toSet()
          .toList(),
      schedules: scoped
          .where(
            (row) =>
                (selectedStage.isEmpty ||
                    row['stage_label'] == selectedStage) &&
                (selectedStatus.isEmpty ||
                    row['display_status'] == selectedStatus) &&
                (selectedSearch.isEmpty ||
                    row['team_name'].toString().toLowerCase().contains(
                      selectedSearch.toLowerCase(),
                    )),
          )
          .toList(),
    );
  }
}

class _Scheduler extends DefenseSchedulerNotifier {
  _Scheduler([this.initialState = const DefenseSchedulerState()]);
  final DefenseSchedulerState initialState;
  @override
  DefenseSchedulerState build() => initialState;
  @override
  Future<void> fetchSchedules({
    String? search,
    String? scope,
    String? status,
    String? successMessage,
  }) async {}
}

class _RetryBoard extends _Board {
  _RetryBoard() : super([_defense(1, display: 'awaiting_evaluation')]);
  int attempts = 0;

  @override
  Future<void> fetchBoard({
    String? search,
    String? stage,
    String? status,
    String? scope,
    String? adviser,
    String? section,
    String? successMessage,
  }) async {
    attempts++;
    if (attempts == 1) {
      state = state.copyWith(
        scope: scope,
        schedules: [],
        error: 'Connection failed. Try again.',
      );
    } else {
      state = state.copyWith(schedules: schedules, clearError: true);
    }
  }
}

class _CapstoneWorkspace extends CapstoneSchedulingApi {
  _CapstoneWorkspace(super.client);

  @override
  Future<Map<String, dynamic>> workspace() async => {
    'semester_id': 1,
    'stages': [
      {'id': 1, 'label': 'Final Defense'},
    ],
    'teams': [],
  };
}

class _Auth extends AuthNotifier {
  _Auth(this.user);
  final Map<String, dynamic> user;
  @override
  AuthState build() => AuthState(user: user, token: 'test', isRestoring: false);
}

Map<String, dynamic> _defense(
  int id, {
  int days = 1,
  String display = 'scheduled',
  String stage = 'Concept Proposal',
  String scope = 'capstone',
  bool external = false,
  String? session,
}) => {
  'id': id,
  'team_name': 'Team $id',
  'project_title': 'Research project $id',
  'scope': scope,
  'session_id': session ?? '$id',
  'semester_id': 1,
  'defense_stage_id': stage == 'Concept Proposal' ? 1 : 2,
  'stage_label': stage,
  'scheduled_date': DateTime.now()
      .add(Duration(days: days))
      .toIso8601String()
      .split('T')
      .first,
  'start_time': '08:00:00',
  'slot_duration': 60,
  'room': 'Room 301',
  'status': display == 'completed' ? 'done' : 'scheduled',
  'display_status': display,
  'documenter_name': 'Cecilia Magbanua',
  'panelists': [],
  'external_evaluators': external
      ? [
          {'id': 11, 'name': 'Lina Santos'},
        ]
      : [],
};

Map<String, dynamic> _invitation(
  int id,
  List<int> schedules, {
  String status = 'Active',
}) => {
  'id': id,
  'guest_name': 'Evaluator $id',
  'code': 'DEF-SESSION-$id',
  'status': status,
  'expires_at': '2099-10-11T02:15:00Z',
  'schedule_ids': schedules,
  'schedules': [
    for (final id in schedules)
      {
        'id': id,
        'team_name': 'Team $id',
        'stage_label': 'Concept Proposal',
        'date': '2026-10-10',
      },
  ],
};

class _External extends ExternalEvaluatorNotifier {
  _External({this.invitations = const [], this.fail = false});
  final List<Map<String, dynamic>> invitations;
  bool fail;
  int reads = 0;
  @override
  ExternalEvaluatorState build() => ExternalEvaluatorState(
    invitations: [
      _invitation(999, [1]),
    ],
  ); // A stale result must not be shared.
  @override
  Future<bool> fetch() async {
    reads++;
    state = ExternalEvaluatorState(
      invitations: invitations,
      error: fail ? 'Could not connect. Try again.' : null,
    );
    return !fail;
  }
}

const _admin = {'id': 1, 'role': 'admin'};
const _pitLead = {
  'id': 2,
  'role': 'faculty',
  'is_pit_lead': true,
  'pit_lead_year': '1st Year',
};

Future<void> _pumpPlannerLink(
  WidgetTester tester,
  String date, {
  bool focusSession = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1400, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation:
        '/admin/defense-board?date=$date${focusSession ? '&session=focus&scope=capstone' : ''}',
    routes: [
      GoRoute(
        path: '/admin/defense-board',
        builder: (_, __) => const DefenseBoardScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _Auth(_admin)),
        defenseBoardProvider.overrideWith(
          () => _Board([
            _defense(1, days: 1, session: 'focus'),
            _defense(2, days: 1, session: 'other'),
            _defense(3, days: 2, session: 'later'),
          ]),
        ),
        defenseSchedulerProvider.overrideWith(_Scheduler.new),
        externalEvaluatorProvider.overrideWith(_External.new),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.lightTheme,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester, {
  required _External external,
  List<Map<String, dynamic>>? schedules,
  _Board? board,
  Map<String, dynamic> user = _admin,
  DefenseSchedulerState schedulerState = const DefenseSchedulerState(),
  double width = 1400,
  double? height,
  double textScale = 1,
  bool dark = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, height ?? (width < 600 ? 844 : 1100));
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await loadPreviewFonts();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => _Auth(user)),
        defenseBoardProvider.overrideWith(
          () => board ?? _Board(schedules ?? []),
        ),
        defenseSchedulerProvider.overrideWith(() => _Scheduler(schedulerState)),
        capstoneSchedulingApiProvider.overrideWith(
          (ref) =>
              _CapstoneWorkspace(ref.read(authenticatedHttpClientProvider)),
        ),
        externalEvaluatorProvider.overrideWith(() => external),
      ],
      child: RepaintBoundary(
        key: const ValueKey('board-session-preview'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.mistDarkTheme,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: schedules != null
              ? const DefenseBoardScreen()
              : Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () =>
                          SessionEvaluatorAccessDialog.show(context, {1, 2}),
                      child: const Text('Open session access'),
                    ),
                  ),
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _menu(
  WidgetTester tester,
  String session, {
  String scope = 'capstone',
}) async {
  final menu = find.byKey(ValueKey('session-actions-$session|$scope|1'));
  await tester.ensureVisible(menu);
  await tester.tap(
    find.descendant(of: menu, matching: find.byIcon(LucideIcons.ellipsis)),
  );
  await tester.pumpAndSettle();
}

DefenseSchedulerState readinessState({String capstoneStatus = 'ready'}) =>
    DefenseSchedulerState(
      canScheduleCapstone: true,
      canSchedulePit: true,
      defenseStages: const [
        {'id': 1, 'label': 'Final Defense'},
      ],
      pitEvents: const [
        {
          'event_name': 'PIT Presentation',
          'year_level': '1st Year',
          'deliverables': [],
        },
      ],
      teams: [
        {
          'id': 1,
          'name': 'Capstone Team',
          'level': '4th Year Capstone',
          'section': 'Capstone Section',
          if (capstoneStatus == 'ready') 'ready_for_stage': 'Final Defense',
          if (capstoneStatus == 'completed')
            'completed_stages': ['Final Defense'],
          'stage_progress': {'Final Defense': capstoneStatus},
        },
        for (final id in [2, 3])
          {
            'id': id,
            'name': 'PIT Team $id',
            'level': '1st Year PIT',
            'year_level': '1st Year',
            'section': 'PIT Section',
            'ready_for_stage': 'PIT Presentation',
          },
        {
          'id': 4,
          'name': 'Completed PIT Team',
          'level': '1st Year PIT',
          'year_level': '1st Year',
          'section': 'PIT Section',
          'completed_stages': ['PIT Presentation'],
        },
      ],
    );

void main() {
  testWidgets(
    'sessions workspace explains follow-up and keeps evaluation in More actions',
    (tester) async {
      await _pump(
        tester,
        external: _External(),
        schedules: [
          {
            ..._defense(1, days: -4, display: 'pending_post_defense'),
            'assessment': {'post_defense_complete': false},
          },
          {
            ..._defense(2, days: -4, display: 'evaluating'),
            'assessment': {
              'panel_evaluators_submitted': 1,
              'panel_evaluators_required': 3,
            },
          },
        ],
      );
      expect(
        find.byKey(const ValueKey('board-sessions-workspace')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('board-sessions-body')), findsOneWidget);
      expect(
        find.textContaining('2 sessions · 2 defenses shown'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          '1 defense has post-defense requirements remaining',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Required post-defense files incomplete'),
        findsOneWidget,
      );
      expect(find.text('1/3 panel evaluations submitted'), findsOneWidget);
      expect(find.text('View evaluation'), findsNothing);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('board-session-preview')),
        'defense-board-follow-up',
      );
      await tester.tap(find.byKey(const ValueKey('board-open-sessions-info')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Includes defenses with unfinished evaluation or follow-up requirements, even when their scheduled date has passed.',
        ),
        findsOneWidget,
      );
      final menu = find.byKey(const ValueKey('defense-actions-1'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text('Evaluation & grades'), findsOneWidget);
      await tester.tap(find.text('Evaluation & grades'));
      await tester.pumpAndSettle();
      expect(find.text('Evaluation unavailable'), findsOneWidget);
      expect(find.text('Refresh schedules'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Team 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('load failures offer retry without claiming the board is empty', (
    tester,
  ) async {
    final board = _RetryBoard();
    await _pump(
      tester,
      external: _External(),
      schedules: [],
      board: board,
      dark: true,
    );
    expect(find.text('Connection failed. Try again.'), findsOneWidget);
    expect(find.text('No defenses scheduled'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Team 1'), findsOneWidget);
    expect(find.text('Connection failed. Try again.'), findsNothing);
    expect(board.attempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty search explains recovery and retains selected program', (
    tester,
  ) async {
    await _pump(
      tester,
      external: _External(),
      schedules: [
        _defense(1),
        _defense(2, scope: 'pit'),
      ],
    );
    await tester.enterText(find.byType(EditableText), 'Missing team');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.textContaining('Showing 0 of 1 defense'), findsOneWidget);
    expect(find.text('No matching defenses'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Team 1'), findsOneWidget);
    expect(find.text('Team 2'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'program context follows the admin into readiness without granting PIT scheduling',
    (tester) async {
      await _pump(
        tester,
        external: _External(),
        schedules: [
          _defense(1, display: 'awaiting_evaluation'),
          _defense(2, scope: 'pit'),
        ],
        schedulerState: readinessState(),
        width: 1440,
      );
      expect(
        find.textContaining('1 defense needs panel evaluation'),
        findsOneWidget,
      );
      expect(find.textContaining('1 defense shown'), findsOneWidget);
      await tester.tap(find.text('PIT'));
      await tester.pumpAndSettle();
      expect(find.text('Team 1'), findsNothing);
      expect(find.text('Team 2'), findsOneWidget);
      expect(find.text('2 teams ready to schedule'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('board-generate-schedule')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('board-view-readiness')));
      await tester.pumpAndSettle();
      final tracker = tester.widget<TeamReadinessTracker>(
        find.byType(TeamReadinessTracker),
      );
      expect(tracker.scope, 'pit');
      expect(tracker.activeStageOrEventName, 'PIT Presentation');
      expect(find.text('PIT Section'), findsOneWidget);
      expect(find.text('Capstone Section'), findsNothing);
      expect(
        find.byKey(const ValueKey('board-generate-schedule')),
        findsNothing,
      );
      await tester.tap(find.text('Capstone'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TeamReadinessTracker>(find.byType(TeamReadinessTracker))
            .scope,
        'capstone',
      );
      expect(find.text('Capstone Section'), findsOneWidget);
      expect(find.text('Schedule 1 ready team'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'status filtering explains the subset and clearing restores program rows',
    (tester) async {
      await _pump(
        tester,
        external: _External(),
        schedules: [
          _defense(1, display: 'awaiting_evaluation'),
          _defense(2, display: 'completed'),
          _defense(3, scope: 'pit'),
        ],
      );
      expect(find.textContaining('2 defenses shown'), findsOneWidget);
      await tester.tap(find.text('All statuses'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ShadOption<String>),
          matching: find.text('Awaiting evaluation'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Showing 1 of 2 defenses'), findsOneWidget);
      expect(find.text('Team 1'), findsOneWidget);
      expect(find.text('Team 2'), findsNothing);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 defenses shown'), findsOneWidget);
      expect(find.text('Team 2'), findsOneWidget);
      expect(find.text('Team 3'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, height, dark, scale) in [
    (1440.0, 900.0, false, 1.0),
    (1440.0, 900.0, true, 1.0),
    (1100.0, 768.0, false, 1.0),
    (390.0, 844.0, true, 1.0),
    (320.0, 844.0, false, 1.3),
  ]) {
    testWidgets(
      'connected board fits $width with scale $scale in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await _pump(
          tester,
          external: _External(),
          width: width,
          height: height,
          dark: dark,
          textScale: scale,
          schedules: [
            {
              ..._defense(
                1,
                days: -4,
                display: dark ? 'pending_post_defense' : 'awaiting_evaluation',
              ),
              if (dark) 'assessment': {'post_defense_complete': false},
              'team_name': 'Team EcoSort',
              'project_title':
                  'AI-Powered Waste Sorting & Recyclable Material Identification System',
              'adviser_name': 'Renato Villanueva',
              'panelists': [
                {'id': 1, 'name': 'Maricel Suarez', 'is_chair': true},
                {'id': 2, 'name': 'Jonathan Beltran'},
              ],
            },
          ],
        );
        expect(
          find.textContaining(
            dark
                ? '1 defense has post-defense requirements remaining'
                : '1 defense needs panel evaluation',
          ),
          findsOneWidget,
        );
        expect(find.text('Open sessions'), findsOneWidget);
        expect(find.text('Total Schedules'), findsNothing);
        expect(tester.takeException(), isNull);
        if (width >= 600) {
          expect(
            tester
                .getRect(find.byKey(const ValueKey('defense-actions-1')))
                .bottom,
            lessThan(height),
          );
        }
        await capturePreview(
          tester,
          find.byKey(const ValueKey('board-session-preview')),
          'defense-board-${width.toInt()}-${dark ? 'dark' : 'light'}',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('defense-actions-1')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (width < 600) {
          await capturePreview(
            tester,
            find.byKey(const ValueKey('board-session-preview')),
            'defense-board-${width.toInt()}-session',
          );
        }
      },
    );
  }

  testWidgets(
    'new import sessions appear above older hearings in their section',
    (tester) async {
      await _pump(
        tester,
        external: _External(),
        schedules: [
          {
            ..._defense(
              1,
              days: 0,
              display: 'awaiting_completion',
              session: 'old',
            ),
            'created_at': '2026-11-01T08:00:00Z',
          },
          {
            ..._defense(
              2,
              days: 0,
              display: 'awaiting_evaluation',
              session: 'new',
            ),
            'start_time': '09:00:00',
            'created_at': '2026-11-04T08:00:00Z',
          },
        ],
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('board-session-new|capstone|1')),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('board-session-old|capstone|1')),
              )
              .dy,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [1400.0, 900.0]) {
    testWidgets(
      'mixed sessions identify the exact repeat team at width $width',
      (tester) async {
        await _pump(
          tester,
          external: _External(),
          width: width,
          dark: width == 900,
          schedules: [
            {
              ..._defense(
                2,
                days: 0,
                display: 'awaiting_evaluation',
                session: 'mixed',
              ),
              'start_time': '09:00:00',
              'assessment': {'attempt_count': 2},
            },
            {
              ..._defense(
                1,
                days: 0,
                display: 'awaiting_evaluation',
                session: 'mixed',
              ),
              'assessment': {'attempt_count': 1},
              'attempt_count': 9,
            },
          ],
        );
        expect(find.text('1 re-defense'), findsOneWidget);
        expect(find.text('Re-defense · Attempt 2'), findsOneWidget);
        expect(find.byKey(const ValueKey('defense-attempt-1')), findsNothing);
        expect(
          tester.getTopLeft(find.text('Team 1')).dy,
          lessThan(tester.getTopLeft(find.text('Team 2')).dy),
        );
        await tester.ensureVisible(find.text('Re-defense · Attempt 2'));
        await tester.pumpAndSettle();
        await capturePreview(
          tester,
          find.byKey(const ValueKey('board-session-preview')),
          'board-repeat-mixed-${width.toInt()}',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a repeat session is identifiable while collapsed', (
    tester,
  ) async {
    await _pump(
      tester,
      external: _External(),
      schedules: [
        {
          ..._defense(
            2,
            days: 0,
            display: 'awaiting_evaluation',
            session: 'repeat',
          ),
          'assessment': {'attempt_count': 3},
        },
      ],
    );
    expect(find.text('Re-defense'), findsOneWidget);
    expect(find.text('Re-defense · Attempt 3'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('session-toggle-repeat|capstone|1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Re-defense'), findsOneWidget);
    expect(find.text('Re-defense · Attempt 3'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final user in [
    _admin,
    {..._admin, 'is_pit_lead': true},
    {'id': 2, 'role': 'faculty', 'is_superuser': true, 'is_pit_lead': true},
  ]) {
    testWidgets('admin readiness stays Capstone for $user', (tester) async {
      await _pump(
        tester,
        external: _External(),
        schedules: [],
        user: user,
        width: 1920,
        schedulerState: readinessState(),
      );
      expect(
        find.text('PIT'),
        findsOneWidget,
      ); // Schedule scope remains available.
      expect(find.byType(DefensysSegmentedControl<String>), findsOneWidget);
      expect(find.text('Readiness · 1 ready'), findsOneWidget);
      expect(find.text('1 team ready to schedule'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('board-view-readiness')));
      await tester.pumpAndSettle();
      expect(find.text('PIT'), findsOneWidget);
      expect(find.text('PIT Presentation'), findsNothing);
      expect(find.text('PIT Section'), findsNothing);
      expect(find.text('Capstone Section'), findsOneWidget);
      expect(find.text('Deliverables & readiness'), findsOneWidget);
      expect(find.text('Schedule 1 ready team'), findsOneWidget);
      final tracker = tester.widget<TeamReadinessTracker>(
        find.byType(TeamReadinessTracker),
      );
      expect(tracker.scope, 'capstone');
      expect(tracker.activeStageOrEventName, 'Final Defense');
      final export = tester.widget<ReportExportMenu>(
        find.byType(ReportExportMenu),
      );
      expect(export.params['scope'], 'capstone');
      expect(export.params['stage'], 'Final Defense');
      await capturePreview(
        tester,
        find.byKey(const ValueKey('board-session-preview')),
        'admin-capstone-readiness',
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Schedule 1 ready team').first);
      await tester.pumpAndSettle();
      final scheduler = tester.widget<DefenseSchedulerScreen>(
        find.byType(DefenseSchedulerScreen),
      );
      expect(scheduler.initialScope, 'capstone');
      expect(scheduler.initialStageId, 1);
      expect(scheduler.initialEventName, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final status in ['pending', 'completed']) {
    testWidgets('admin readiness badge ignores PIT when Capstone is $status', (
      tester,
    ) async {
      await _pump(
        tester,
        external: _External(),
        schedules: [],
        schedulerState: readinessState(capstoneStatus: status),
      );
      expect(find.text('Readiness'), findsOneWidget);
      expect(find.textContaining('teams ready to schedule'), findsNothing);
      expect(find.text('Review readiness'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('continued teams keep two completed milestones in the queue', (
    tester,
  ) async {
    await _pump(
      tester,
      external: _External(),
      schedules: [],
      width: 1920,
      schedulerState: DefenseSchedulerState(
        schedulerMode: 'capstone',
        canScheduleCapstone: true,
        defenseStages: const [
          {'id': 1, 'label': 'Concept Proposal'},
          {'id': 2, 'label': 'Project Proposal'},
          {'id': 3, 'label': 'Final Defense'},
        ],
        teams: [
          for (var id = 1; id <= 16; id++)
            {
              'id': id,
              'name': 'Continued Team $id',
              'level': '4th Year Capstone',
              'section': id <= 8 ? 'BSIT-4A' : 'BSIT-4B',
              'completed_stages': ['Concept Proposal', 'Project Proposal'],
              'stage_progress': {
                'Concept Proposal': 'completed',
                'Project Proposal': 'completed',
              },
              'eligible_stages': <String>[],
            },
        ],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('board-view-readiness')));
    await tester.pumpAndSettle();
    final queue = find.byType(TeamReadinessTracker);
    expect(
      find.descendant(of: queue, matching: find.text('Complete')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: queue, matching: find.text('16 pending')),
      findsOneWidget,
    );

    await tester.tap(find.text('Project Proposal'));
    await tester.pumpAndSettle();
    expect(find.text('16 completed this stage'), findsOneWidget);
    expect(find.text('Completed'), findsNWidgets(2));
    expect(find.text('Needs Endorsement'), findsNothing);
    final tracker = tester.widget<TeamReadinessTracker>(
      find.byType(TeamReadinessTracker),
    );
    expect(tracker.activeStageOrEventName, 'Project Proposal');
    expect(tester.takeException(), isNull);
  });

  testWidgets('PIT lead retains PIT readiness and counts', (tester) async {
    await _pump(
      tester,
      external: _External(),
      schedules: [],
      user: {
        'id': 2,
        'role': 'faculty',
        'is_pit_lead': true,
        'pit_lead_year': '1st Year',
      },
      width: 1920,
      schedulerState: readinessState(),
    );
    expect(find.text('Readiness · 2 ready'), findsOneWidget);
    expect(find.text('2 teams ready to schedule'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board-view-readiness')));
    await tester.pumpAndSettle();
    final tracker = tester.widget<TeamReadinessTracker>(
      find.byType(TeamReadinessTracker),
    );
    expect(tracker.scope, 'pit');
    expect(tracker.activeStageOrEventName, 'PIT Presentation');
    expect(find.text('PIT Section'), findsOneWidget);
    expect(find.text('Capstone Section'), findsNothing);
    expect(find.text('Schedule 2 ready teams'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [1200.0, 1920.0]) {
    testWidgets('PIT lead has no program switcher at width $width', (
      tester,
    ) async {
      await _pump(
        tester,
        external: _External(),
        schedules: [_defense(1, scope: 'pit')],
        user: _pitLead,
        width: width,
        dark: width == 1920,
      );
      expect(find.byType(DefensysSegmentedControl<String>), findsNothing);
      expect(find.text('Capstone'), findsNothing);
      expect(find.text('Manage schedules'), findsOneWidget);
      expect(find.text('Team 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('team slots show start and end times', (tester) async {
    await _pump(
      tester,
      external: _External(),
      schedules: [
        {..._defense(31), 'start_time': '16:00:00', 'slot_duration': 60},
        {..._defense(32), 'start_time': '09:15:00', 'slot_duration': 45},
      ],
    );
    expect(find.text('16:00–17:00'), findsOneWidget);
    expect(find.text('09:15–10:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'planner session link focuses one session and can show all schedules',
    (tester) async {
      final day = DateTime.now().add(const Duration(days: 1));
      final date = day.toIso8601String().split('T').first;
      await _pumpPlannerLink(tester, date);
      expect(find.text('Team 1'), findsOneWidget);
      expect(find.text('Team 2'), findsNothing);
      expect(find.textContaining('Session scheduled for'), findsOneWidget);
      await tester.tap(find.text('Show all schedules'));
      await tester.pumpAndSettle();
      expect(find.text('Team 2'), findsOneWidget);
      expect(find.text('Team 3'), findsOneWidget);
    },
  );

  testWidgets('planner date link includes every session on that day', (
    tester,
  ) async {
    final day = DateTime.now().add(const Duration(days: 1));
    final date = day.toIso8601String().split('T').first;
    await _pumpPlannerLink(tester, date, focusSession: false);
    expect(find.text('Team 1'), findsOneWidget);
    expect(find.text('Team 2'), findsOneWidget);
    expect(find.text('Team 3'), findsNothing);
    expect(find.textContaining('Schedule for'), findsOneWidget);
  });

  testWidgets('schedule actions are anchored to the upper right', (
    tester,
  ) async {
    await _pump(tester, external: _External(), schedules: [], width: 1400);

    final action = find.byKey(const ValueKey('board-generate-schedule'));
    expect(action, findsOneWidget);
    expect(tester.getRect(action).right, greaterThan(1300));
    expect(
      tester.getTopLeft(action).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('board-defense-summary')))
            .dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('board prioritizes current work across stage groups and dates', (
    tester,
  ) async {
    await _pump(
      tester,
      external: _External(),
      schedules: [
        _defense(1, days: -7, display: 'completed'),
        _defense(2, days: 3),
        _defense(3, days: 1, stage: 'Project Proposal'),
        _defense(
          4,
          days: 0,
          display: 'evaluating',
          stage: 'Project Proposal',
          external: true,
        ),
        _defense(5, days: -1, display: 'completed'),
      ],
    );
    double y(String text) => tester.getTopLeft(find.text(text).first).dy;
    expect(y('Open sessions'), lessThan(y('Upcoming sessions')));
    expect(y('Upcoming sessions'), lessThan(y('History')));
    expect(y('Team 4'), lessThan(y('Team 3')));
    expect(y('Team 3'), lessThan(y('Team 2')));
    expect(y('Team 2'), lessThan(y('Team 5')));
    expect(y('Team 5'), lessThan(y('Team 1')));
    await capturePreview(
      tester,
      find.byKey(const ValueKey('board-session-preview')),
      'defense-board-current-sessions',
    );
    await _menu(tester, '4');
    expect(find.text('Evaluator access'), findsOneWidget);
    await capturePreview(
      tester,
      find.byKey(const ValueKey('board-session-preview')),
      'defense-board-session-actions',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'session access includes every evaluator assigned within the session',
    (tester) async {
      final external = _External(
        invitations: [
          _invitation(21, [1]),
          _invitation(22, [2]),
          _invitation(23, [3]),
        ],
      );
      await _pump(
        tester,
        external: external,
        schedules: [
          _defense(1, external: false, session: 'shared'),
          _defense(2, external: true, session: 'shared'),
        ],
      );
      await _menu(tester, 'shared');
      await tester.tap(find.text('Evaluator access'));
      await tester.pumpAndSettle();
      expect(find.text('Evaluator invitations'), findsOneWidget);
      expect(find.text('DEF-SESSION-21'), findsOneWidget);
      expect(find.text('DEF-SESSION-22'), findsOneWidget);
      expect(find.text('DEF-SESSION-23'), findsNothing);
      expect(find.text('DEF-SESSION-999'), findsNothing);
      expect(external.reads, 1);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(call.arguments['text']);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.text('Copy code').first);
      await tester.pumpAndSettle();
      expect(copied, ['DEF-SESSION-21']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('faculty-only sessions omit evaluator access', (tester) async {
    await _pump(tester, external: _External(), schedules: [_defense(1)]);
    await _menu(tester, '1');
    expect(find.text('Evaluator access'), findsNothing);
    expect(find.text('Edit session'), findsOneWidget);
  });

  testWidgets('PIT leads can open their session access', (tester) async {
    await _pump(
      tester,
      external: _External(
        invitations: [
          _invitation(21, [1]),
        ],
      ),
      user: {'id': 2, 'role': 'faculty', 'is_pit_lead': true},
      schedules: [
        {..._defense(1, scope: 'pit', external: true), 'can_manage': true},
      ],
    );
    await _menu(tester, '1', scope: 'pit');
    await tester.tap(find.text('Evaluator access'));
    await tester.pumpAndSettle();
    expect(find.text('DEF-SESSION-21'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary faculty have no session access action', (tester) async {
    await _pump(
      tester,
      external: _External(),
      user: {'id': 2, 'role': 'faculty'},
      schedules: [_defense(1, external: true)],
    );
    expect(
      find.byKey(const ValueKey('session-actions-1|capstone|1')),
      findsNothing,
    );
  });

  for (final permission in [false, null]) {
    testWidgets('PIT lead assignment reads grant no management ($permission)', (
      tester,
    ) async {
      await _pump(
        tester,
        external: _External(),
        user: {
          'id': 2,
          'role': 'faculty',
          'is_pit_lead': true,
          'pit_lead_year': '3rd Year',
        },
        schedules: [
          {
            ..._defense(1, scope: 'pit', external: true),
            if (permission != null) 'can_manage': permission,
            'section': 'BSIT-2A',
          },
        ],
      );
      expect(
        find.byKey(const ValueKey('session-actions-1|pit|1')),
        findsNothing,
      );
      expect(find.text('Stage actions'), findsNothing);
      final menu = find.byKey(const ValueKey('defense-actions-1'));
      await tester.ensureVisible(menu);
      await tester.tap(
        find.descendant(of: menu, matching: find.byIcon(LucideIcons.ellipsis)),
      );
      await tester.pumpAndSettle();
      expect(find.text('View details'), findsOneWidget);
      for (final action in [
        'Edit panel',
        'Change room',
        'Reschedule defense',
        'View change history',
      ]) {
        expect(find.text(action), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('access failures are retryable and never show stale codes', (
    tester,
  ) async {
    final external = _External(
      fail: true,
      invitations: [
        _invitation(21, [1]),
      ],
    );
    await _pump(tester, external: external);
    await tester.tap(find.text('Open session access'));
    await tester.pumpAndSettle();
    expect(find.text('Could not connect. Try again.'), findsOneWidget);
    expect(find.text('DEF-SESSION-21'), findsNothing);
    external.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('DEF-SESSION-21'), findsOneWidget);
    expect(external.reads, 2);
  });

  testWidgets('missing invitations have an explicit empty state', (
    tester,
  ) async {
    await _pump(tester, external: _External());
    await tester.tap(find.text('Open session access'));
    await tester.pumpAndSettle();
    expect(
      find.text('No evaluator invitations are available for this session.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Evaluator access'), findsNothing);
  });

  for (final (width, dark, status) in [
    (1400.0, false, 'Expired'),
    (390.0, true, 'Revoked'),
  ]) {
    testWidgets(
      '$status session access fits $width in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await _pump(
          tester,
          external: _External(
            invitations: [
              _invitation(21, [1], status: status),
            ],
          ),
          width: width,
          dark: dark,
        );
        await tester.tap(find.text('Open session access'));
        await tester.pumpAndSettle();
        expect(find.textContaining('$status access.'), findsOneWidget);
        expect(find.text('Copy code'), findsOneWidget);
        await capturePreview(
          tester,
          find.byKey(const ValueKey('board-session-preview')),
          'session-evaluator-access-${dark ? 'dark' : 'light'}-${width.toInt()}',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
