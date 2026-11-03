import 'dart:convert';
import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/l10n/app_localizations.dart';
import 'package:defensys/notifications/notifications_provider.dart';
import 'package:defensys/services/connectivity_provider.dart';
import 'package:defensys/services/defense_board_provider.dart';
import 'package:defensys/services/app/unsaved_changes_provider.dart';
import 'package:defensys/screens/web/admin/defense_board/defense_board_screen.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/capstone_scheduling_workspace.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/scheduler_people_picker.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/documenter_workload_summary.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/models/capstone_planning_draft.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/defense_scheduler_screen.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/shadcn/workflow_step_progress.dart';
import '../helpers/auth_test_overrides.dart';
import '../helpers/capture_preview.dart';

Map<String, dynamic> fixture() => {
  'semester_id': 10,
  'semester_label': '2026–2027 · Second semester',
  'starts_on': '2026-11-01',
  'ends_on': '2027-03-31',
  'stages': [
    {'id': 71, 'label': 'Design review', 'default_slot_duration_minutes': 20},
  ],
  'faculty': [
    for (var id = 1; id <= 8; id++) {'id': id, 'name': 'Faculty $id'},
  ],
  'panelists': [
    for (var id = 1; id <= 8; id++) {'id': id, 'name': 'Faculty $id'},
  ],
  'documenters': [
    for (var id = 5; id <= 8; id++) {'id': id, 'name': 'Faculty $id'},
  ],
  'external_evaluators': [
    {'id': 100, 'name': 'Dr. Cruz', 'institution': 'Partner university'},
  ],
  'teams': [
    for (var i = 1; i <= 2; i++)
      <String, dynamic>{
        'id': i,
        'name': 'Team $i',
        'project_version': 1,
        'intake_semester_id': 10,
        'intake_label': '2026 intake',
        'adviser_id': i + 20,
        'adviser_name': 'Adviser $i',
        'applicable_stage_ids': [71],
        'ready_stage_ids': [71],
        'initial_stage_id': 71,
        'assignment_revision': 1,
        'assignment': {
          'chair_panelist_id': 1,
          'panelist_ids': [1, 2, 3, 4],
          'external_evaluator_ids': [],
          'documenter_id': 5,
        },
      },
  ],
};

Map<String, dynamic> previewFixture(
  Map<String, dynamic> inputs,
  Map<String, dynamic> data, [
  List<String> dates = const ['2026-11-16'],
]) {
  final ids = inputs['team_ids'] as List;
  String clock(int index) => DateTime(
    2026,
    1,
    1,
    8,
  ).add(Duration(minutes: index * 20)).toIso8601String().substring(11, 19);
  final slots = [
    for (var i = 0; i < ids.length; i++)
      {
        'team_id': ids[i],
        'team_name': (data['teams'] as List).firstWhere(
          (team) => team['id'] == ids[i],
        )['name'],
        'adviser_id': (data['teams'] as List).firstWhere(
          (team) => team['id'] == ids[i],
        )['adviser_id'],
        'scheduled_date': dates[i % dates.length],
        'start_time': clock(i),
        'end_time': clock(i + 1),
        'block_key': '${dates[i % dates.length]}:0',
        'window_index': 0,
        'room': inputs['room'],
        'roster':
            (inputs['overrides'] as Map?)?['${ids[i]}'] ??
            (data['teams'] as List).firstWhere(
              (team) => team['id'] == ids[i],
            )['assignment'],
      },
  ];
  return {
    'slots': slots,
    'days': dates.toSet().length,
    'sessions': dates.toSet().length,
    'scheduled_dates': dates,
    'complete': true,
    'finish': '${dates.last} ${clock(ids.length)}',
    'preview_token': 'token',
  };
}

Map<String, dynamic> reviewFixture() {
  final data = fixture();
  final teams = data['teams'] as List;
  teams.addAll(<Map<String, dynamic>>[
    {
      ...Map<String, dynamic>.from(teams[0]),
      'id': 3,
      'name': 'Team ThreadAtlas',
    },
    {
      ...Map<String, dynamic>.from(teams[1]),
      'id': 4,
      'name': 'Team ClayCircuit',
    },
  ]);
  for (final team in teams) {
    team['adviser_name'] = team['adviser_id'] == 21
        ? 'Analiza Corpuz'
        : 'Renato Villanueva';
  }
  return data;
}

class _FailedScheduler extends DefenseSchedulerNotifier {
  @override
  DefenseSchedulerState build() =>
      const DefenseSchedulerState(error: 'Service unavailable');
  @override
  Future<void> fetchSchedules({
    String? search,
    String? scope,
    String? status,
    String? successMessage,
  }) async {}
}

class _LoadedScheduler extends _FailedScheduler {
  @override
  DefenseSchedulerState build() => const DefenseSchedulerState(
    activeSemester: {'id': 10, 'display_name': '2026–2027 · Second semester'},
    canScheduleCapstone: true,
    defenseStages: [
      {'id': 71, 'label': 'Design review'},
    ],
  );
}

class _NoNotifications extends NotificationsNotifier {
  _NoNotifications(super.workspace);
  @override
  NotificationsState build() => const NotificationsState();
  @override
  Future<void> fetchNotifications({
    bool? unreadOnly,
    bool loadMore = false,
  }) async {}
}

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _ReadinessView extends DefenseBoardActiveViewNotifier {
  @override
  DefenseOperationsView build() => DefenseOperationsView.readiness;
}

void main() {
  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1440, 1000),
    bool dark = false,
    bool failFirstWorkspace = false,
    bool fullScreen = false,
    bool adminShell = false,
    bool operationsBoard = false,
    bool startWithReadiness = false,
    Map<String, dynamic>? workspaceData,
    int initialStageId = 71,
    void Function(Map<String, dynamic>)? onPlan,
    void Function(Map<String, dynamic>)? onPeople,
    Map<String, dynamic>? planError,
    List<String> Function(Map<String, dynamic>)? planDates,
    Future<http.Response?> Function(Map<String, dynamic>)? planResponse,
    void Function(Map<String, dynamic>)? onConfirm,
    Future<http.Response?> Function(Map<String, dynamic>)? confirmResponse,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var workspaceLoads = 0;
    var confirmed = false;
    Map<String, dynamic>? latestPlan;
    final data = workspaceData ?? fixture();
    setApiHttpClientForTesting(
      MockClient((request) async {
        if (request.url.path.endsWith('/capstone-workspace/')) {
          if (request.method == 'POST') {
            final edit = Map<String, dynamic>.from(jsonDecode(request.body));
            onPeople?.call(edit);
            for (final team in data['teams'] as List) {
              if (!(edit['team_ids'] as List).contains(team['id'])) continue;
              team['assignment'] =
                  edit['roster'] ??
                  CapstoneRosterDraft.fromJson(
                        Map<String, dynamic>.from(team['assignment']),
                      )
                      .applying(Map<String, dynamic>.from(edit['changes']))
                      .toJson();
              team['assignment_revision'] =
                  (team['assignment_revision'] as int) + 1;
            }
          }
          if (failFirstWorkspace && workspaceLoads++ == 0) {
            return http.Response(
              '<html>Database exception</html>',
              500,
              headers: {'content-type': 'text/html'},
            );
          }
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path.endsWith('/generate-plan/')) {
          final inputs = jsonDecode(request.body) as Map<String, dynamic>;
          latestPlan = inputs;
          onPlan?.call(inputs);
          final custom = await planResponse?.call(inputs);
          if (custom != null) return custom;
          if (planError != null) {
            return http.Response(jsonEncode(planError), 400);
          }
          final dates = planDates?.call(inputs) ?? ['2026-11-16'];
          return http.Response(
            jsonEncode(previewFixture(inputs, data, dates)),
            200,
          );
        }
        if (request.url.path.endsWith('/confirm-plan/')) {
          final inputs = Map<String, dynamic>.from(jsonDecode(request.body));
          onConfirm?.call(inputs);
          final response = await confirmResponse?.call(inputs);
          if (response != null) return response;
          confirmed = true;
          return http.Response(
            jsonEncode({
              'created_count': (data['teams'] as List).length,
              'created_invitations': [],
            }),
            201,
          );
        }
        if (request.url.path.endsWith('/defense/board')) {
          final slots = confirmed && latestPlan != null
              ? previewFixture(latestPlan!, data)['slots'] as List
              : const [];
          return http.Response(
            jsonEncode({
              'active_semester': {'id': 10, 'display_name': '2026–2027'},
              'schedules': [
                for (final slot in slots)
                  {
                    ...Map<String, dynamic>.from(slot),
                    'id': slot['team_id'],
                    'scope': 'capstone',
                    'semester_id': 10,
                    'defense_stage_id': 71,
                    'stage_label': 'Design review',
                    'status': 'scheduled',
                    'display_status': 'scheduled',
                    'session_id': 'adviser-${slot['adviser_id']}',
                    'slot_duration': 20,
                    'documenter_name': 'Faculty 5',
                    'panelists': [],
                    'external_evaluators': [],
                  },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{}', 200);
      }),
    );
    addTearDown(resetApiHttpClientForTesting);
    await loadPreviewFonts(force: true);
    final page = operationsBoard
        ? const DefenseBoardScreen()
        : fullScreen
        ? DefenseSchedulerScreen(
            initialScope: 'capstone',
            initialStageId: initialStageId,
          )
        : Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: CapstoneSchedulingWorkspace(
                  initialStageId: initialStageId,
                  onSaved: () async {},
                ),
              ),
            ),
          );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...authTestOverrides(),
          if (startWithReadiness)
            defenseBoardActiveViewProvider.overrideWith(_ReadinessView.new),
          if (adminShell) ...[
            notificationsProvider.overrideWith2(_NoNotifications.new),
            connectivityProvider.overrideWith(_Online.new),
          ],
          if (fullScreen || operationsBoard)
            defenseSchedulerProvider.overrideWith(_LoadedScheduler.new),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.theme,
          darkTheme: ThemeData.dark().copyWith(
            textTheme: AppTheme.theme.textTheme,
          ),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: adminShell
              ? DefensysAdminShell(
                  activeSection: DefensysAdminSection.defenseBoard,
                  activeSemesterLabel: 'Active Sem: 2026–2027',
                  onNavigate: (_) {},
                  onLogout: () {},
                  scrollContent: false,
                  child: page,
                )
              : page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choosePerson(WidgetTester tester, String label, int id) async {
    tester
        .widget<SchedulerPeoplePicker>(
          find.byKey(ValueKey('adviser-21:10-$label')),
        )
        .onChanged({id});
    await tester.pumpAndSettle();
  }

  Future<void> approveReplacement(
    WidgetTester tester,
    String scope,
    String reason,
  ) async {
    await tester.ensureVisible(find.text(scope));
    await tester.tap(find.text(scope));
    final input = find.byKey(const ValueKey('replacement-audit-reason'));
    await tester.ensureVisible(input);
    await tester.enterText(input, reason);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply change'));
    await tester.tap(find.text('Apply change'));
    await tester.pumpAndSettle();
  }

  Future<void> assignAndPlan(WidgetTester tester, {DateTime? start}) async {
    await tester.ensureVisible(find.text('Assign'));
    await tester.tap(find.text('Assign'));
    await tester.pumpAndSettle();
    tester
        .widget<ShadDatePicker>(find.byType(ShadDatePicker).first)
        .onChanged
        ?.call(start ?? DateTime(2026, 11, 16));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(ShadInput).at(1), '301');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  Future<void> openReview(WidgetTester tester) async {
    await assignAndPlan(tester);
    await tester.ensureVisible(find.text('Order & review →'));
    await tester.tap(find.text('Order & review →'));
    await tester.pumpAndSettle();
  }

  Future<void> keyboardMove(
    WidgetTester tester,
    String key, {
    bool cancel = false,
  }) async {
    tester
        .widget<Focus>(find.byKey(ValueKey('review-handle-$key')))
        .focusNode!
        .requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(
      cancel ? LogicalKeyboardKey.escape : LogicalKeyboardKey.enter,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> laterStageFixture() {
    final data = fixture();
    (data['stages'] as List).add({
      'id': 72,
      'label': 'Build review',
      'default_slot_duration_minutes': 60,
    });
    for (final team in data['teams'] as List) {
      team['applicable_stage_ids'] = [71, 72];
      team['ready_stage_ids'] = [72];
    }
    return data;
  }

  testWidgets(
    'initial adviser setup saves without replacement reason or dialog',
    (tester) async {
      final data = fixture();
      for (final team in data['teams'] as List) {
        team['assignment'] = null;
        team['assignment_revision'] = 0;
        team['adviser_id'] = 21;
        team['adviser_name'] = 'Adviser 1';
      }
      final writes = <Map<String, dynamic>>[];
      final plans = <Map<String, dynamic>>[];
      await mount(
        tester,
        workspaceData: data,
        onPeople: writes.add,
        onPlan: plans.add,
      );
      await choosePerson(tester, 'Panel chair', 1);
      for (var i = 1; i <= 3; i++) {
        await choosePerson(tester, 'Panel member $i', i + 1);
      }
      await choosePerson(tester, 'Documenter', 5);
      expect(find.text('Change assigned people'), findsNothing);
      expect(find.textContaining('Replacement reason'), findsNothing);
      await assignAndPlan(tester);
      expect(writes, hasLength(1));
      expect(writes.single['team_ids'], [1, 2]);
      expect(writes.single.containsKey('reason'), isFalse);
      expect(plans.last.containsKey('replacement_reason'), isFalse);
      expect(plans.last.containsKey('replacement_events'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved stage-only change requires explicit scope and reason and preserves baseline',
    (tester) async {
      final data = laterStageFixture();
      final writes = <Map<String, dynamic>>[];
      final plans = <Map<String, dynamic>>[];
      await mount(
        tester,
        workspaceData: data,
        initialStageId: 72,
        onPeople: writes.add,
        onPlan: plans.add,
      );
      await choosePerson(tester, 'Panel member 1', 6);
      expect(find.text('Change assigned people'), findsOneWidget);
      expect(
        tester
            .widget<ShadButton>(find.widgetWithText(ShadButton, 'Apply change'))
            .onPressed,
        isNull,
      );
      await capturePreview(
        tester,
        find.byType(Scaffold).first,
        'capstone-replacement-dialog',
        viewport: true,
      );
      await approveReplacement(tester, 'This stage only', 'Panelist travel');
      await assignAndPlan(tester);
      expect(writes, isEmpty);
      expect((data['teams'] as List).first['assignment']['panelist_ids'], [
        1,
        2,
        3,
        4,
      ]);
      final plan = plans.last;
      expect(plan['defense_stage_id'], 72);
      expect(plan['overrides']['1']['panelist_ids'], contains(6));
      expect(plan['overrides'].containsKey('2'), isFalse);
      expect(plan['replacement_reason'], 'Panelist travel');
      expect(plan['replacement_events'].single['scope'], 'stage_only');
      expect(plan['replacement_events'].single['team_ids'], [1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'permanent documenter edit does not promote a stage-only panel replacement',
    (tester) async {
      final data = laterStageFixture();
      final writes = <Map<String, dynamic>>[];
      final plans = <Map<String, dynamic>>[];
      await mount(
        tester,
        workspaceData: data,
        initialStageId: 72,
        onPeople: writes.add,
        onPlan: plans.add,
      );
      await choosePerson(tester, 'Panel member 1', 6);
      await approveReplacement(tester, 'This stage only', 'Panelist travel');
      await choosePerson(tester, 'Documenter', 7);
      await approveReplacement(
        tester,
        'This and future stages',
        'Documenter permanent replacement',
      );
      await assignAndPlan(tester);
      expect(writes, hasLength(1));
      expect(writes.single['changes'], {'documenter_id': 7});
      expect(writes.single['reason'], 'Documenter permanent replacement');
      expect((data['teams'] as List).first['assignment']['panelist_ids'], [
        1,
        2,
        3,
        4,
      ]);
      expect((data['teams'] as List).first['assignment']['documenter_id'], 7);
      expect(plans.last['overrides']['1']['panelist_ids'], contains(6));
      expect(plans.last['overrides']['1']['documenter_id'], 7);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'canceling a replacement restores approved choices in a narrow dark dialog',
    (tester) async {
      final plans = <Map<String, dynamic>>[];
      final writes = <Map<String, dynamic>>[];
      await mount(
        tester,
        size: const Size(390, 900),
        dark: true,
        onPlan: plans.add,
        onPeople: writes.add,
      );
      await choosePerson(tester, 'Panel member 1', 6);
      expect(find.text('Change assigned people'), findsOneWidget);
      await capturePreview(
        tester,
        find.byType(Scaffold).first,
        'capstone-replacement-dialog-mobile-dark',
        viewport: true,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SchedulerPeoplePicker>(
              find.byKey(const ValueKey('adviser-21:10-Panel member 1')),
            )
            .selected,
        {2},
      );
      expect(writes, isEmpty);
      expect(find.text('Change assigned people'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'service failure offers retry without claiming setup or stages are missing',
    (tester) async {
      await mount(tester, failFirstWorkspace: true);
      expect(find.text('Could not load scheduling workspace'), findsOneWidget);
      expect(find.textContaining('HTTP 500'), findsOneWidget);
      expect(
        find.text(
          'Configure the stage pipeline in Defense Stages before scheduling.',
        ),
        findsNothing,
      );
      expect(find.byType(WorkflowStepProgress), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Stage: Design review'), findsOneWidget);
      expect(find.text('Could not load scheduling workspace'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed options do not report the administrator lacks permission or an active semester',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      setApiHttpClientForTesting(
        MockClient(
          (_) async => http.Response('<html>Server error</html>', 500),
        ),
      );
      addTearDown(resetApiHttpClientForTesting);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...authTestOverrides(),
            defenseSchedulerProvider.overrideWith(_FailedScheduler.new),
          ],
          child: MaterialApp(
            theme: AppTheme.theme,
            home: const DefenseSchedulerScreen(initialScope: 'capstone'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unable to load academic period'), findsOneWidget);
      expect(find.text('No active semester configured'), findsNothing);
      expect(
        find.text(
          'Scheduling Capstone defenses is strictly reserved for Administrators.',
        ),
        findsNothing,
      );
      expect(find.text('Could not load scheduling workspace'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'adding a panel slot changes only its adviser row and retains four-person defaults',
    (tester) async {
      await mount(tester);
      expect(
        find.text('Stage: Design review'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      expect(find.text('Panel member 3'), findsNWidgets(2));
      await tester.tap(find.text('+ Panel member').first);
      await tester.pumpAndSettle();
      expect(find.text('Panel member 4'), findsOneWidget);
      expect(find.text('Must finish by'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'one page header and fixed stage context replace the duplicate title and stage switcher',
    (tester) async {
      await mount(tester, fullScreen: true);
      expect(find.text('Defense Scheduler'), findsOneWidget);
      expect(find.text('Defense scheduling'), findsNothing);
      expect(find.text('Stage: Design review'), findsOneWidget);
      expect(find.text('Design review •'), findsNothing);
      expect(find.byKey(const ValueKey('overall-readiness')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'adviser has one shared form, dropdown readiness, and an independent collapse control',
    (tester) async {
      final data = fixture();
      final teams = data['teams'] as List;
      teams[1]['adviser_id'] = teams[0]['adviser_id'];
      teams[1]['adviser_name'] = teams[0]['adviser_name'];
      teams[1]['ready_stage_ids'] = [];
      teams[1]['stage_readiness'] = {
        '71': {
          'status': 'awaiting_endorsement',
          'label': 'Awaiting endorsement',
          'endorsed': false,
          'can_schedule': false,
        },
      };
      await mount(tester, workspaceData: data);
      expect(find.text('Panel chair'), findsOneWidget);
      expect(find.text('Customize people for individual teams'), findsNothing);
      expect(
        find.textContaining('Not ready or already scheduled'),
        findsNothing,
      );
      expect(find.text('Partly ready'), findsOneWidget);
      expect(find.text('1/2 teams endorsed'), findsOneWidget);
      final readiness = find.text('Team readiness · 1/2 ready');
      await tester.tap(readiness);
      await tester.pumpAndSettle();
      expect(find.text('Team 1'), findsOneWidget);
      expect(find.text('Team 2'), findsOneWidget);
      expect(find.text('Awaiting endorsement'), findsOneWidget);
      expect(find.text('Not endorsed'), findsOneWidget);
      await tester.tap(readiness);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('collapse-21:10')));
      await tester.pumpAndSettle();
      expect(find.text('Panel chair'), findsNothing);
      expect(readiness, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('collapse-21:10')));
      await tester.pumpAndSettle();
      expect(find.text('Panel chair'), findsOneWidget);
      await capturePreview(
        tester,
        find.byType(Scaffold).first,
        'capstone-adviser-ready-status',
        viewport: true,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date planner and review keyboard reordering retain a stable queue',
    (tester) async {
      final plans = <Map<String, dynamic>>[];
      await mount(tester, onPlan: plans.add);
      final next = find.text('Assign');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WorkflowStepProgress>(find.byType(WorkflowStepProgress))
            .currentStep,
        2,
      );
      tester
          .widget<ShadDatePicker>(find.byType(ShadDatePicker).first)
          .onChanged
          ?.call(DateTime(2026, 11, 16));
      await tester.pumpAndSettle();
      final room = find.byType(ShadInput).first;
      await tester.enterText(room, '20'); // minutes remains editable
      final inputs = find.byType(ShadInput);
      await tester.enterText(inputs.at(1), '301');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Scheduled dates'), findsOneWidget);
      expect(find.text('Calculated plan'), findsOneWidget);
      await capturePreview(
        tester,
        find.byType(Scaffold).first,
        'capstone-planner-desktop',
        viewport: true,
      );
      final review = find.text('Order & review →');
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WorkflowStepProgress>(find.byType(WorkflowStepProgress))
            .currentStep,
        3,
      );
      await tester.tap(find.text('Assign people'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WorkflowStepProgress>(find.byType(WorkflowStepProgress))
            .currentStep,
        3,
      );
      await keyboardMove(tester, '21:10');
      expect(plans.last['team_ids'], [2, 1]);
      final previous = find.text('← Dates & sessions');
      await tester.ensureVisible(previous);
      await tester.tap(previous);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WorkflowStepProgress>(find.byType(WorkflowStepProgress))
            .currentStep,
        2,
      );
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      final editPeople = find.text('Edit people');
      await tester.ensureVisible(editPeople);
      await tester.tap(editPeople);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WorkflowStepProgress>(find.byType(WorkflowStepProgress))
            .currentStep,
        1,
      );
      expect(find.text('Panel chair'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dates layout prioritizes sessions and preserves optional scheduling inputs',
    (tester) async {
      final plans = <Map<String, dynamic>>[];
      await mount(tester, onPlan: plans.add);
      await assignAndPlan(tester);
      expect(
        tester.getTopLeft(find.text('Daily sessions')).dx,
        lessThan(tester.getTopLeft(find.text('Calculated plan')).dx),
      );
      expect(
        tester.getTopLeft(find.text('Daily sessions')).dy,
        lessThan(tester.getTopLeft(find.text('Scheduled dates')).dy),
      );
      expect(find.text('Include Sunday').hitTestable(), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('plan-teams-count')))
            .data,
        '2/2',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('plan-end-time'))).data,
        matches(RegExp(r'^8:40\sAM$')),
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('plan-end-date'))).data,
        'Mon, Nov 16',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('plan-start-time'))).data,
        matches(RegExp(r'^8:00\sAM$')),
      );

      await tester.enterText(
        find.byKey(const ValueKey('session-0-end')),
        '11:30',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(plans.last['windows'][0]['end_time'], '11:30');
      await tester.ensureVisible(find.text('Add session'));
      await tester.tap(find.text('Add session'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(plans.last['windows'], hasLength(3));
      await tester.ensureVisible(
        find.byKey(const ValueKey('remove-session-2')),
      );
      await tester.tap(find.byKey(const ValueKey('remove-session-2')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(plans.last['windows'], hasLength(2));

      await tester.ensureVisible(find.text('Scheduling options'));
      await tester.tap(find.text('Scheduling options'));
      await tester.pumpAndSettle();
      expect(find.text('Unavailable date'), findsNothing);
      expect(find.text('Skip date'), findsNothing);
      expect(find.byType(ShadDatePicker), findsOneWidget);
      await tester.ensureVisible(find.text('Include Sunday'));
      await tester.tap(find.text('Include Sunday'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(plans.last['include_sunday'], isTrue);
      final date = tester.widget<ShadCheckbox>(
        find.byKey(const ValueKey('schedule-date-2026-11-16')),
      );
      date.onChanged?.call(false);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(plans.last['excluded_dates'], ['2026-11-16']);
      tester
          .widget<ShadCheckbox>(
            find.byKey(const ValueKey('schedule-date-2026-11-16')),
          )
          .onChanged
          ?.call(true);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(plans.last['excluded_dates'], isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dates footer stays visible while the full page scrolls on a small laptop',
    (tester) async {
      await mount(tester, fullScreen: true, size: const Size(1280, 800));
      await assignAndPlan(tester);
      final footer = find.byKey(const ValueKey('capstone-date-actions'));
      final position = tester.getTopLeft(footer);
      expect(find.text('Order & review →').hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('capstone-workspace-scroll')),
        const Offset(0, -550),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(footer), position);
      expect(find.text('Order & review →').hitTestable(), findsOneWidget);
      expect(find.text('2/2 teams endorsed'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('capstone-workspace-scroll')),
        const Offset(0, 2000),
      );
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byType(Scaffold).first,
        'capstone-dates-laptop-light',
        viewport: true,
      );
      expect(
        find.byKey(const ValueKey('schedule-date-2026-11-16')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Sunday start shows only the allocated week and respects Include Sunday',
    (tester) async {
      await mount(
        tester,
        planDates: (inputs) => [
          inputs['include_sunday'] == true ? '2026-11-01' : '2026-11-02',
        ],
      );
      await assignAndPlan(tester, start: DateTime(2026, 11, 1));
      expect(find.text('Oct 26 – Nov 1'), findsNothing);
      expect(find.text('Nov 2 – Nov 8'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('plan-start-date'))).data,
        'Mon, Nov 2',
      );
      await tester.ensureVisible(find.text('Scheduling options'));
      await tester.tap(find.text('Scheduling options'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Include Sunday'));
      await tester.tap(find.text('Include Sunday'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Oct 26 – Nov 1'), findsOneWidget);
      expect(find.text('Nov 2 – Nov 8'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'calendar adds another week only when the allocated dates need it',
    (tester) async {
      await mount(tester, planDates: (_) => ['2026-11-02', '2026-11-09']);
      await assignAndPlan(tester, start: DateTime(2026, 11, 2));
      expect(find.text('Nov 2 – Nov 8'), findsOneWidget);
      expect(find.text('Nov 9 – Nov 15'), findsOneWidget);
      expect(find.text('Nov 16 – Nov 22'), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('plan-days-count'))).data,
        '2',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('plan-sessions-count')))
            .data,
        '2',
      );
      expect(find.byKey(const ValueKey('plan-day-2026-11-02')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-day-2026-11-09')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('plan-start-date'))).data,
        'Mon, Nov 2',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('plan-end-date'))).data,
        'Mon, Nov 9',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'calendar-skipped dates remain restorable when the plan moves to another week',
    (tester) async {
      final plans = <Map<String, dynamic>>[];
      await mount(
        tester,
        planDates: (inputs) => [
          (inputs['excluded_dates'] as List).contains('2026-11-02')
              ? '2026-11-09'
              : '2026-11-02',
        ],
        onPlan: plans.add,
      );
      await assignAndPlan(tester, start: DateTime(2026, 11, 1));
      tester
          .widget<ShadCheckbox>(
            find.byKey(const ValueKey('schedule-date-2026-11-02')),
          )
          .onChanged
          ?.call(false);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(plans.last['excluded_dates'], ['2026-11-02']);
      expect(find.text('Nov 2 – Nov 8'), findsNothing);
      expect(find.text('Nov 9 – Nov 15'), findsOneWidget);
      expect(find.text('Include Sunday').hitTestable(), findsNothing);
      expect(find.text('Restore Nov 2'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('restore-date-2026-11-02')),
      );
      await tester.tap(find.byKey(const ValueKey('restore-date-2026-11-02')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(plans.last['excluded_dates'], isEmpty);
      expect(find.text('Nov 2 – Nov 8'), findsOneWidget);
      expect(find.text('Nov 9 – Nov 15'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an incomplete late-week setup shows one week while awaiting a plan',
    (tester) async {
      await mount(tester);
      await tester.ensureVisible(find.text('Assign'));
      await tester.tap(find.text('Assign'));
      await tester.pumpAndSettle();
      tester
          .widget<ShadDatePicker>(find.byType(ShadDatePicker).first)
          .onChanged
          ?.call(DateTime(2026, 11, 4));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Nov 2 – Nov 8'), findsOneWidget);
      expect(find.text('Nov 9 – Nov 15'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'setup failures stay in the plan panel without claiming scheduling readiness',
    (tester) async {
      await mount(
        tester,
        planError: {
          'defense_stage_id': ['Publish the panel rubric before scheduling.'],
        },
      );
      await assignAndPlan(tester);
      expect(find.text('Stage setup needs attention'), findsOneWidget);
      expect(
        find.text('Publish the panel rubric before scheduling.'),
        findsOneWidget,
      );
      expect(find.textContaining('defense_stage_id:'), findsNothing);
      expect(find.text('Review stage setup'), findsOneWidget);
      expect(find.text('2/2 teams endorsed'), findsOneWidget);
      expect(find.text('Ready to schedule'), findsNothing);
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Order & review →'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow dark dates step stacks the summary and keeps the footer reachable',
    (tester) async {
      await mount(
        tester,
        fullScreen: true,
        size: const Size(390, 900),
        dark: true,
      );
      await assignAndPlan(tester);
      expect(
        tester.getTopLeft(find.text('Calculated plan')).dy,
        lessThan(tester.getTopLeft(find.text('Daily sessions')).dy),
      );
      expect(find.text('Order & review →').hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('capstone-workspace-scroll')),
        const Offset(0, 3000),
      );
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byType(Scaffold).first,
        'capstone-dates-mobile-dark',
        viewport: true,
      );
      tester.view.physicalSize = const Size(320, 900);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Calculated plan'));
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byType(Scaffold).first,
        'capstone-dates-preview-narrow-dark',
        viewport: true,
      );
      await tester.ensureVisible(find.text('Scheduled dates'));
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byType(Scaffold).first,
        'capstone-dates-calendar-narrow-dark',
        viewport: true,
      );
      expect(find.text('Order & review →').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review keyboard reordering commits whole adviser blocks and Escape restores the order',
    (tester) async {
      final plans = <Map<String, dynamic>>[];
      await mount(tester, workspaceData: reviewFixture(), onPlan: plans.add);
      await openReview(tester);
      final before = plans.length;
      expect(find.text('Panel chair'), findsNothing);
      await keyboardMove(tester, '21:10', cancel: true);
      expect(plans, hasLength(before));
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Confirm schedule'),
            )
            .onPressed,
        isNotNull,
      );
      await keyboardMove(tester, '21:10');
      expect(plans.last['team_ids'], [2, 4, 1, 3]);
      expect(plans.last['room'], '301');
      expect(plans.last['overrides'], isEmpty);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(
        prefs.getString(
          prefs.getKeys().firstWhere((key) => key.startsWith('capstone-auto:')),
        )!,
      );
      expect(saved['group_order'], ['22:10', '21:10']);
      await tester.tap(find.byKey(const ValueKey('review-expand-21:10')));
      await tester.pumpAndSettle();
      expect(find.text('Panel chair'), findsOneWidget);
      await tester.ensureVisible(find.text('Edit people'));
      await tester.tap(find.text('Edit people'));
      await tester.pumpAndSettle();
      expect(find.text('Panel chair'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review drag handle moves adviser blocks without changing people or scheduling inputs',
    (tester) async {
      final mouse = defaultTargetPlatform == TargetPlatform.windows;
      final plans = <Map<String, dynamic>>[];
      await mount(
        tester,
        workspaceData: reviewFixture(),
        onPlan: plans.add,
        fullScreen: true,
        size: mouse ? const Size(1902, 1009) : const Size(390, 900),
        dark: !mouse,
        adminShell: true,
      );
      await openReview(tester);
      final first = find.byKey(const ValueKey('review-handle-21:10'));
      final last = find.byKey(const ValueKey('review-handle-22:10'));
      await tester.ensureVisible(first);
      final destination = tester.getCenter(last) + const Offset(0, 160);
      final gesture = await tester.startGesture(
        tester.getCenter(first),
        kind: mouse ? PointerDeviceKind.mouse : PointerDeviceKind.touch,
      );
      await gesture.moveBy(const Offset(0, 32));
      await tester.pump();
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Confirm schedule'),
            )
            .onPressed,
        isNull,
      );
      await gesture.moveTo(destination);
      await tester.pump(const Duration(milliseconds: 350));
      await capturePreview(
        tester,
        find.byType(Scaffold).first,
        'capstone-review-drag-${mouse ? 'desktop-mouse' : 'narrow-touch'}',
        viewport: true,
      );
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Confirm schedule'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(plans.last['team_ids'], [2, 4, 1, 3]);
      expect(plans.last['slot_duration'], 20);
      expect(plans.last['windows'], [
        {'start_time': '08:00', 'end_time': '12:00'},
        {'start_time': '13:00', 'end_time': '17:00'},
      ]);
      final reverse = await tester.startGesture(
        tester.getCenter(first),
        kind: mouse ? PointerDeviceKind.mouse : PointerDeviceKind.touch,
      );
      await reverse.moveBy(const Offset(0, -32));
      await tester.pump();
      await reverse.moveTo(tester.getCenter(last) - const Offset(0, 160));
      await tester.pump(const Duration(milliseconds: 350));
      await reverse.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(plans.last['team_ids'], [1, 3, 2, 4]);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'review mouse drag safely cancels and drops in place after hovering the grip',
    (tester) async {
      final plans = <Map<String, dynamic>>[];
      await mount(
        tester,
        workspaceData: reviewFixture(),
        onPlan: plans.add,
        fullScreen: true,
        size: const Size(1280, 800),
        dark: true,
        adminShell: true,
      );
      await openReview(tester);
      final before = plans.length;
      final handle = find.byKey(const ValueKey('review-handle-21:10'));
      await tester.ensureVisible(handle);
      await tester.pumpAndSettle();
      for (final cancel in [true, false]) {
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: tester.getCenter(handle));
        await tester.pumpAndSettle();
        await gesture.down(tester.getCenter(handle));
        await gesture.moveBy(const Offset(0, 16));
        await tester.pump(const Duration(milliseconds: 16));
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pumpAndSettle();
        await gesture.removePointer();
        await tester.pumpAndSettle();
        expect(plans, hasLength(before));
        expect(
          tester
              .widget<ShadButton>(
                find.widgetWithText(ShadButton, 'Confirm schedule'),
              )
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final scenario in [
    (name: 'immediate drop', cancel: false, hoverOther: false),
    (name: 'immediate cancellation', cancel: true, hoverOther: false),
    (name: 'hovering another card', cancel: false, hoverOther: true),
  ]) {
    testWidgets(
      'review mouse handles ${scenario.name} without a render frame during the gesture',
      (tester) async {
        final plans = <Map<String, dynamic>>[];
        await mount(
          tester,
          workspaceData: reviewFixture(),
          onPlan: plans.add,
          fullScreen: true,
          adminShell: true,
          size: const Size(1902, 1009),
        );
        await openReview(tester);
        final before = plans.length;
        final first = find.byKey(const ValueKey('review-handle-21:10'));
        final last = find.byKey(const ValueKey('review-handle-22:10'));
        final hover = scenario.hoverOther
            ? find.byKey(const ValueKey('review-expand-22:10'))
            : first;
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: tester.getCenter(hover));
        await tester.pumpAndSettle();
        await gesture.down(tester.getCenter(first));
        await gesture.moveBy(const Offset(0, 32));
        await gesture.moveTo(tester.getCenter(last) + const Offset(0, 160));
        if (scenario.cancel) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pumpAndSettle();
        await gesture.removePointer();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        if (scenario.cancel) {
          expect(plans, hasLength(before));
        } else {
          expect(plans.last['team_ids'], [2, 4, 1, 3]);
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  for (final readiness in [false, true]) {
    testWidgets(
      'successful confirmation returns from ${readiness ? 'Readiness' : 'Schedules'} to fresh Operations sessions',
      (tester) async {
        await mount(
          tester,
          workspaceData: reviewFixture(),
          operationsBoard: true,
          adminShell: true,
          startWithReadiness: readiness,
          size: const Size(1902, 1009),
        );
        await tester.tap(find.text('Generate Schedule'));
        await tester.pumpAndSettle();
        await openReview(tester);
        await tester.ensureVisible(find.text('Confirm schedule'));
        await tester.tap(find.text('Confirm schedule'));
        await tester.pumpAndSettle();
        expect(find.byType(DefenseSchedulerScreen), findsNothing);
        expect(find.byType(CapstoneSchedulingWorkspace), findsNothing);
        expect(find.byType(DefenseBoardScreen), findsOneWidget);
        final context = tester.element(find.byType(DefenseBoardScreen));
        final container = ProviderScope.containerOf(context);
        expect(
          container.read(defenseBoardActiveViewProvider),
          DefenseOperationsView.schedules,
        );
        expect(
          container
              .read(defenseBoardProvider)
              .schedules
              .map((slot) => slot['id']),
          containsAll([1, 2, 3, 4]),
          reason: container.read(defenseBoardProvider).error,
        );
        await tester.scrollUntilVisible(
          find.text('Team ThreadAtlas'),
          300,
          scrollable: find
              .descendant(
                of: find.byType(DefenseBoardScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('Team ThreadAtlas'), findsOneWidget);
        expect(container.read(unsavedChangesProvider), isFalse);
        expect(container.read(unsavedChangesSaveDraftProvider), isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getKeys().where((key) => key.startsWith('capstone-auto:')),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'rejected confirmation keeps the review open with the scheduling draft',
    (tester) async {
      await mount(
        tester,
        workspaceData: reviewFixture(),
        operationsBoard: true,
        adminShell: true,
        startWithReadiness: true,
        size: const Size(1902, 1009),
        confirmResponse: (_) async => http.Response(
          jsonEncode({
            'detail': 'The reservation changed. Recalculate the plan.',
          }),
          400,
        ),
      );
      await tester.tap(find.text('Generate Schedule'));
      await tester.pumpAndSettle();
      await openReview(tester);
      await tester.ensureVisible(find.text('Confirm schedule'));
      await tester.tap(find.text('Confirm schedule'));
      await tester.pumpAndSettle();
      expect(find.byType(DefenseSchedulerScreen), findsOneWidget);
      expect(find.text('Defense order'), findsOneWidget);
      expect(
        find.text('The reservation changed. Recalculate the plan.'),
        findsWidgets,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DefenseSchedulerScreen)),
      );
      expect(
        container.read(defenseBoardActiveViewProvider),
        DefenseOperationsView.readiness,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((key) => key.startsWith('capstone-auto:')),
        isNotEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review blocks confirmation while pending and ignores an older reorder response',
    (tester) async {
      final data = reviewFixture();
      final pending = <(Map<String, dynamic>, Completer<http.Response>)>[];
      final confirmations = <Map<String, dynamic>>[];
      var hold = false;
      await mount(
        tester,
        workspaceData: data,
        onConfirm: confirmations.add,
        planResponse: (inputs) async {
          if (!hold) return null;
          final result = Completer<http.Response>();
          pending.add((inputs, result));
          return result.future;
        },
      );
      await openReview(tester);
      hold = true;
      await keyboardMove(tester, '21:10');
      expect(pending, hasLength(1));
      expect(find.textContaining('2 teams'), findsNWidgets(2));
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Confirm schedule'),
            )
            .onPressed,
        isNull,
      );
      await keyboardMove(tester, '22:10');
      expect(pending, hasLength(2));
      pending[0].$2.complete(
        http.Response(
          jsonEncode({
            ...previewFixture(pending[0].$1, data),
            'preview_token': 'stale',
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Confirm schedule'),
            )
            .onPressed,
        isNull,
      );
      pending[1].$2.complete(
        http.Response(
          jsonEncode({
            ...previewFixture(pending[1].$1, data),
            'preview_token': 'latest',
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Confirm schedule'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.text('Confirm schedule'));
      await tester.tap(find.text('Confirm schedule'));
      await tester.pumpAndSettle();
      expect(confirmations.single['preview_token'], 'latest');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review preserves pending rows on an error and retries before allowing confirmation',
    (tester) async {
      var reject = false;
      await mount(
        tester,
        planResponse: (_) async => reject
            ? http.Response(
                jsonEncode({'detail': 'The room reservation changed.'}),
                400,
              )
            : null,
      );
      await openReview(tester);
      reject = true;
      await keyboardMove(tester, '21:10');
      expect(find.text('The room reservation changed.'), findsOneWidget);
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Confirm schedule'),
            )
            .onPressed,
        isNull,
      );
      reject = false;
      await tester.ensureVisible(find.text('Retry calculation'));
      await tester.tap(find.text('Retry calculation'));
      await tester.pumpAndSettle();
      expect(find.text('The room reservation changed.'), findsNothing);
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Confirm schedule'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review incomplete allocation keeps selected team counts and blocks confirmation',
    (tester) async {
      final data = reviewFixture();
      await mount(
        tester,
        workspaceData: data,
        planResponse: (inputs) async {
          final plan = previewFixture(inputs, data);
          plan['slots'] = (plan['slots'] as List).take(1).toList();
          plan['complete'] = false;
          plan['remaining_team_ids'] = (inputs['team_ids'] as List)
              .skip(1)
              .toList();
          plan['blocking_reason'] =
              'No available slots remain in the semester.';
          return http.Response(jsonEncode(plan), 200);
        },
      );
      await openReview(tester);
      expect(find.textContaining('2 teams'), findsNWidgets(2));
      expect(find.text('Some teams could not fit'), findsOneWidget);
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Confirm schedule'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('review-expand-22:10')));
      await tester.pumpAndSettle();
      expect(find.text('Not allocated'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expanded review groups teams by actual date when an adviser spans multiple days',
    (tester) async {
      final data = fixture();
      (data['teams'] as List)[1]['adviser_id'] = 21;
      (data['teams'] as List)[1]['adviser_name'] = 'Adviser 1';
      await mount(
        tester,
        workspaceData: data,
        planDates: (_) => ['2026-11-16', '2026-11-17'],
      );
      await openReview(tester);
      await tester.tap(find.byKey(const ValueKey('review-expand-21:10')));
      await tester.pumpAndSettle();
      expect(find.text('Monday, Nov 16'), findsOneWidget);
      expect(find.text('Tuesday, Nov 17'), findsOneWidget);
      expect(find.text('Panel chair'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('plan-start-date'))).data,
        'Mon, Nov 16',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('plan-end-date'))).data,
        'Tue, Nov 17',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review shows actual team-specific people rather than a shared continuing roster',
    (tester) async {
      final data = fixture();
      (data['teams'] as List)[1]['adviser_id'] = 21;
      (data['teams'] as List)[1]['adviser_name'] = 'Adviser 1';
      await mount(
        tester,
        workspaceData: data,
        planResponse: (inputs) async {
          final result = previewFixture(inputs, data);
          final slot = (result['slots'] as List)[1];
          slot['roster'] = {
            ...Map<String, dynamic>.from(slot['roster']),
            'documenter_id': 6,
            'external_evaluator_ids': [100],
          };
          return http.Response(jsonEncode(result), 200);
        },
      );
      await openReview(tester);
      await tester.tap(find.byKey(const ValueKey('review-expand-21:10')));
      await tester.pumpAndSettle();
      expect(find.text('Faculty 5'), findsOneWidget);
      expect(find.text('Faculty 6'), findsOneWidget);
      expect(find.text('Dr. Cruz'), findsOneWidget);
      expect(find.text('Documenter'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  for (final variant in [
    (const Size(1280, 800), false, 'laptop-light'),
    (const Size(1440, 1000), true, 'desktop-dark'),
    (const Size(390, 900), false, 'mobile-light'),
    (const Size(320, 900), true, 'narrow-dark'),
  ]) {
    testWidgets('review summary and fixed actions reflow at ${variant.$3}', (
      tester,
    ) async {
      await mount(
        tester,
        workspaceData: reviewFixture(),
        fullScreen: true,
        size: variant.$1,
        dark: variant.$2,
      );
      await openReview(tester);
      final footer = find.byKey(const ValueKey('capstone-review-actions'));
      final position = tester.getTopLeft(footer);
      expect(find.text('Confirm schedule').hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('capstone-workspace-scroll')),
        const Offset(0, 3000),
      );
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byType(Scaffold).first,
        'capstone-review-${variant.$3}',
        viewport: true,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('review-expand-21:10')),
      );
      await tester.tap(find.byKey(const ValueKey('review-expand-21:10')));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(footer), position);
      expect(find.text('Confirm schedule').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('Panel chair'));
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byType(Scaffold).first,
        'capstone-review-details-${variant.$3}',
        viewport: true,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'documenter workload includes every role holder and counts teams rather than adviser rows',
    (tester) async {
      final data = reviewFixture();
      await mount(
        tester,
        workspaceData: data,
        fullScreen: true,
        size: const Size(1280, 800),
      );
      final workload = tester.widget<DocumenterWorkloadSummary>(
        find.byType(DocumenterWorkloadSummary),
      );
      expect(workload.items.map((item) => item.id), containsAll([5, 6, 7, 8]));
      expect(workload.items.singleWhere((item) => item.id == 5).teams, 4);
      expect(workload.items.where((item) => item.teams == 0), hasLength(3));
      expect(find.text('Expected records'), findsNothing);
      expect(find.text('Pending records'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('documenter-5-teams')))
            .data,
        '4 teams',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('documenter-6-teams')))
            .data,
        'Unassigned',
      );
      await tester.ensureVisible(find.byType(DocumenterWorkloadSummary));
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byType(Scaffold).first,
        'documenter-workload-laptop-light',
        viewport: true,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'approved documenter changes update the distribution across adviser groups',
    (tester) async {
      final data = reviewFixture();
      await mount(tester, workspaceData: data);
      await choosePerson(tester, 'Documenter', 6);
      await approveReplacement(
        tester,
        'This and future stages',
        'Balance the documenter workload',
      );
      final workload = tester.widget<DocumenterWorkloadSummary>(
        find.byType(DocumenterWorkloadSummary),
      );
      expect(workload.items.singleWhere((item) => item.id == 5).teams, 2);
      expect(workload.items.singleWhere((item) => item.id == 6).teams, 2);
      expect(workload.items.singleWhere((item) => item.id == 7).teams, 0);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('documenter-6-teams')))
            .data,
        '2 teams',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unassigned documenters stay visible in the narrow dark workload summary',
    (tester) async {
      final data = reviewFixture();
      for (final team in data['teams'] as List) {
        team['assignment'] = <String, dynamic>{
          ...Map<String, dynamic>.from(team['assignment']),
          'documenter_id': null,
        };
      }
      await mount(
        tester,
        workspaceData: data,
        fullScreen: true,
        size: const Size(320, 900),
        dark: true,
      );
      final workload = tester.widget<DocumenterWorkloadSummary>(
        find.byType(DocumenterWorkloadSummary),
      );
      expect(workload.items, hasLength(4));
      expect(workload.items.every((item) => item.teams == 0), isTrue);
      for (final id in [5, 6, 7, 8]) {
        expect(
          tester
              .widget<Text>(find.byKey(ValueKey('documenter-$id-teams')))
              .data,
          'Unassigned',
        );
      }
      await tester.ensureVisible(find.byType(DocumenterWorkloadSummary));
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byType(Scaffold).first,
        'documenter-workload-narrow-dark',
        viewport: true,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'workload retains an existing assignment outside the available documenter role list',
    (tester) async {
      final data = reviewFixture();
      (data['documenters'] as List).removeWhere((person) => person['id'] == 5);
      await mount(tester, workspaceData: data);
      final workload = tester.widget<DocumenterWorkloadSummary>(
        find.byType(DocumenterWorkloadSummary),
      );
      expect(workload.items, hasLength(4));
      final existing = workload.items.singleWhere((item) => item.id == 5);
      expect(existing.eligible, isFalse);
      expect(existing.teams, 4);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow dark workspace keeps inputs and actions usable without overflow',
    (tester) async {
      await mount(tester, size: const Size(390, 900), dark: true);
      expect(find.text('Panel chair'), findsNWidgets(2));
      await capturePreview(
        tester,
        find.byType(Scaffold).first,
        'capstone-planner-mobile-dark',
        viewport: true,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
