import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/api_http.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/capstone_scheduling_workspace.dart';
import 'package:defensys/screens/web/admin/defense_scheduler/components/scheduler_people_picker.dart';
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

void main() {
  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1440, 1000),
    bool dark = false,
    bool failFirstWorkspace = false,
    bool fullScreen = false,
    Map<String, dynamic>? workspaceData,
    int initialStageId = 71,
    void Function(Map<String, dynamic>)? onPlan,
    void Function(Map<String, dynamic>)? onPeople,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var workspaceLoads = 0;
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
          onPlan?.call(inputs);
          final ids = inputs['team_ids'] as List;
          final slots = [
            for (var i = 0; i < ids.length; i++)
              {
                'team_id': ids[i],
                'team_name': 'Team ${ids[i]}',
                'adviser_id': ids[i] + 20,
                'scheduled_date': '2026-11-16',
                'start_time': '08:${i == 0 ? '00' : '20'}:00',
                'end_time': '08:${i == 0 ? '20' : '40'}:00',
                'block_key': '2026-11-16:0',
                'window_index': 0,
                'room': '301',
                'roster': (fixture()['teams'] as List).first['assignment'],
              },
          ];
          return http.Response(
            jsonEncode({
              'slots': slots,
              'days': 1,
              'sessions': 1,
              'scheduled_dates': ['2026-11-16'],
              'complete': true,
              'finish': '2026-11-16 08:40',
              'preview_token': 'token',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    addTearDown(resetApiHttpClientForTesting);
    await loadPreviewFonts(force: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...authTestOverrides(),
          if (fullScreen)
            defenseSchedulerProvider.overrideWith(_LoadedScheduler.new),
        ],
        child: MaterialApp(
          theme: AppTheme.theme,
          darkTheme: ThemeData.dark().copyWith(
            textTheme: AppTheme.theme.textTheme,
          ),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: fullScreen
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
                ),
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

  Future<void> assignAndPlan(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Assign'));
    await tester.tap(find.text('Assign'));
    await tester.pumpAndSettle();
    tester
        .widget<ShadDatePicker>(find.byType(ShadDatePicker).first)
        .onChanged
        ?.call(DateTime(2026, 11, 16));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(ShadInput).at(1), '301');
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
      expect(find.text('Partly ready'), findsNWidgets(2));
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
    'date planner uses two columns and adviser arrows recalculate stable queue',
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
      await tester.tap(find.text('Move down').first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
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
