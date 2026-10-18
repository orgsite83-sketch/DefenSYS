import 'package:defensys/models/adviser_workflow.dart';
import 'package:defensys/screens/web/faculty/adviser/adviser_dashboard_content.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/deliverables_table.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/defense/team_defense_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

const _stage = 'Project Proposal';
Map<String, dynamic> _grade({
  bool available = true,
  String status = 'pending',
  double? score,
}) => {
  'id': 42,
  'team_id': 7,
  'stage_label': _stage,
  'semester_id': 3,
  'project_version': 1,
  'status': status,
  'adviser_score': score,
  'panel_score': 87.5,
  'peer_score': 91.0,
  'adviser_grading_available': available,
  'adviser_grading_unavailable_reason': available
      ? ''
      : 'This defense is paused. An administrator must resume it before grading.',
  'assigned_adviser_rubric_id': 1,
  'assigned_adviser_rubric_name': 'Project contributions',
  'assigned_adviser_rubric_target_type': 'team',
  'assigned_adviser_rubric_scale': '10-Point Scale',
  'assigned_adviser_criteria': [
    {'id': 1, 'name': 'Project contribution', 'max_score': 10},
    {'id': 2, 'name': 'Professional conduct', 'max_score': 10},
  ],
  'members': [],
  'breakdowns': [],
};

Map<String, dynamic> _team() => {
  'id': 7,
  'name': 'Team SkyLedger',
  'project_title': 'Alumni Career Tracker',
  'project_version': 1,
  'semester_id': 3,
  'current_stage': _stage,
  'year_level': '4th Year',
  'section': 'BSIT-4A',
  'members': [
    {'id': 1, 'name': 'Marcus VILLAR', 'role': 'leader'},
  ],
  'stages': [
    {
      'stage_label': _stage,
      'stage_status_detail': 'pending_post_defense',
      'endorsed': true,
      'is_defense_done': true,
      'required_complete': true,
      'deliverables_configured': true,
      'pre': [],
      'post': [],
    },
  ],
};

Map<String, dynamic> _schedule({
  String minutes = 'submitted',
  String status = 'done',
}) => {
  'id': 18,
  'team_id': 7,
  'scope': 'capstone',
  'stage_label': _stage,
  'project_version': 1,
  'semester_id': 3,
  'minutes_status': minutes,
  'minutes_required': true,
  'status': status,
  'scheduled_date': '2026-10-04',
  'start_time': '09:30:00',
  'room': 'Room 301',
  'documenter_name': 'Cecilia Magbanua',
};

class _Grades extends AdviserGradingNotifier {
  _Grades(this.rows, {this.loading = false});
  final List<Map<String, dynamic>> rows;
  final bool loading;
  @override
  AdviserGradingState build() =>
      AdviserGradingState(grades: rows, isLoading: loading);
  @override
  Future<void> fetchAll() async {}
  void replace(List<Map<String, dynamic>> rows) =>
      state = AdviserGradingState(grades: rows);
}

class _Schedules extends TeamDefenseNotifier {
  _Schedules(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  TeamDefenseState build() => TeamDefenseState(schedules: rows);
  @override
  Future<void> fetch({String? workspace}) async {}
}

class _Deliverables extends CapstoneDeliverablesNotifier {
  @override
  CapstoneDeliverablesState build() =>
      CapstoneDeliverablesState(teams: [_team()]);
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

Future<void> _pane(
  WidgetTester tester,
  _Grades grades, {
  int tab = 1,
  String minutes = 'submitted',
  bool dark = false,
  String? preview,
}) async {
  await pumpDefensysWidget(
    tester,
    RepaintBoundary(
      key: const Key('workflow-preview'),
      child: ColoredBox(
        color: dark ? const Color(0xFF161618) : const Color(0xFFF8FAFC),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DeliverablesTablePane(
              state: CapstoneDeliverablesState(
                selectedStage: _stage,
                stageOptions: const [_stage],
                teams: [_team()],
              ),
              isAdviser: true,
              initialTeamId: 7,
              initialTab: tab,
            ),
          ),
        ),
      ),
    ),
    theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
    overrides: [
      adviserGradingProvider.overrideWith(() => grades),
      teamDefenseProvider.overrideWith(
        () => _Schedules([_schedule(minutes: minutes)]),
      ),
    ],
  );
  if (preview != null) {
    await capturePreview(
      tester,
      find.byKey(const Key('workflow-preview')),
      preview,
    );
  }
}

void main() {
  setUpAll(() => loadPreviewFonts(force: true));

  test(
    'grading guidance honors availability and finalization independently of panel scores',
    () {
      expect(
        AdviserGradingStatus.fromGrade({
          ..._grade(),
          'panel_score': null,
          'peer_score': null,
        }).needsGrade,
        isTrue,
      );
      expect(AdviserGradingStatus.fromGrade(_grade(score: 0)).canGrade, isTrue);
      expect(
        AdviserGradingStatus.fromGrade(_grade(score: 0)).needsGrade,
        isFalse,
      );
      expect(
        AdviserGradingStatus.fromGrade(_grade(status: 'published')).canGrade,
        isFalse,
      );
      expect(
        AdviserGradingStatus.fromGrade(_grade(available: false)).canGrade,
        isFalse,
      );
      expect(AdviserGradingStatus.fromGrade({'id': 42}).canGrade, isFalse);
      expect(
        AdviserGradingStatus.fromGrade(_grade(), enabled: false).canGrade,
        isFalse,
      );
    },
  );

  test(
    'minutes reminders exclude cancelled defenses, other stages, terms and projects',
    () {
      expect(
        adviserMinutesToSign(_team(), _stage, [
          _schedule(),
          _schedule(status: 'cancelled'),
          {..._schedule(), 'stage_label': 'Concept Proposal'},
          {..._schedule(), 'project_version': 2},
          {..._schedule(), 'semester_id': 4},
        ]).length,
        1,
      );
      expect(
        AdviserMinutesStatus.fromSchedule(
          _schedule(minutes: 'adviser_signed'),
        ).needsSignature,
        isFalse,
      );
      expect(
        AdviserMinutesStatus.fromSchedule(
          _schedule(minutes: 'completed'),
        ).badge,
        'Finalized',
      );
    },
  );

  testWidgets(
    'grading reminder, tab badges and team shortcuts open the right work',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await _pane(
        tester,
        _Grades([_grade()]),
        preview: 'adviser-workflow/grading-desktop',
      );
      expect(find.text('You can grade this team now'), findsOneWidget);
      expect(find.text('Ready to grade'), findsOneWidget);
      expect(
        find.textContaining('before or after the defense'),
        findsOneWidget,
      );
      expect(find.text('0 of 2 criteria completed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('adviser-team-action-7-3')));
      await tester.pumpAndSettle();
      expect(find.text('Minutes ready for your signature'), findsOneWidget);
      expect(find.text('Review and sign minutes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('backend grading blocker is explained and disables score entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await _pane(tester, _Grades([_grade(available: false)]));
    expect(find.textContaining('This defense is paused.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Grading unavailable'), findsOneWidget);
    expect(find.text('Grade now'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'grading initializes after asynchronous load and updates its submitted reminder',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final grades = _Grades([], loading: true);
      await _pane(tester, grades);
      expect(find.text('Checking grading availability'), findsOneWidget);
      grades.replace([_grade()]);
      await tester.pumpAndSettle();
      expect(find.text('Project contribution'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      grades.replace([_grade(score: 85)]);
      await tester.pumpAndSettle();
      expect(find.text('Adviser grade submitted — editable'), findsOneWidget);
      expect(find.text('Grade now'), findsNothing);
      grades.replace([_grade(score: 85, status: 'published')]);
      await tester.pumpAndSettle();
      expect(find.text('Grades finalized — read only'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard shows grading and signature tasks with stage-specific navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      String? opened;
      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: AdviserDashboardContent(
            data: const {
              'advised_teams': [
                {'id': 7, 'name': 'Team SkyLedger'},
              ],
            },
            facultyName: 'Ricardo Fontanilla',
            onOpenDeliverables: (_) {},
            onOpenGrades: (id, stage) => opened = 'grade:$id:$stage',
            onOpenDefense: (id, stage) => opened = 'minutes:$id:$stage',
          ),
        ),
        overrides: [
          adviserGradingProvider.overrideWith(
            () => _Grades([
              _grade(),
              {..._grade(), 'team_id': 99},
            ]),
          ),
          teamDefenseProvider.overrideWith(
            () => _Schedules([_schedule(), _schedule(status: 'cancelled')]),
          ),
          capstoneDeliverablesProvider.overrideWith(_Deliverables.new),
        ],
      );
      await tester.tap(find.text('Project Proposal · Ready to grade'));
      expect(opened, 'grade:7:Project Proposal');
      await tester.tap(find.text('Project Proposal · Minutes ready to sign'));
      expect(opened, 'minutes:7:Project Proposal');
      expect(tester.takeException(), isNull);
    },
  );

  for (final sample in [('phone', 390.0, false), ('dark', 1500.0, true)]) {
    testWidgets('grading reminder fits the ${sample.$1} workspace', (
      tester,
    ) async {
      tester.view.physicalSize = Size(sample.$2, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final grade = {
        ..._grade(),
        'assigned_adviser_rubric_target_type': 'both',
        'assigned_adviser_criteria': [
          {
            'id': 1,
            'name': 'Project contribution',
            'max_score': 10,
            'target_type': 'team',
          },
          {
            'id': 2,
            'name': 'Professional conduct',
            'max_score': 10,
            'target_type': 'individual',
          },
        ],
      };
      await _pane(
        tester,
        _Grades([grade]),
        dark: sample.$3,
        preview: 'adviser-workflow/grading-${sample.$1}',
      );
      expect(find.text('You can grade this team now'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('minutes reminder fits the ${sample.$1} workspace', (
      tester,
    ) async {
      tester.view.physicalSize = Size(sample.$2, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await _pane(
        tester,
        _Grades([_grade(score: 85)]),
        tab: 3,
        dark: sample.$3,
        preview: 'adviser-workflow/minutes-${sample.$1}',
      );
      expect(find.text('Minutes ready for your signature'), findsOneWidget);
      expect(find.text('Review and sign minutes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
