import 'dart:convert';
import 'package:defensys/screens/app/panelist_dashboard.dart';
import 'package:defensys/screens/app/panelist/grade_sheet_tab.dart';
import 'package:defensys/screens/app/panelist/panelist_stage.dart';
import 'package:defensys/screens/app/panelist/panelist_session.dart';
import 'package:defensys/screens/app/panelist/panelist_models.dart';
import 'package:defensys/screens/app/panelist/widgets/evaluation_score_picker.dart';
import 'package:defensys/screens/app/panelist/widgets/panelist_segmented_tabs.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/connectivity_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:defensys/screens/app/panelist/overall_results_tab.dart';
import 'package:defensys/screens/app/panelist/assignments_tab.dart';
import 'package:defensys/screens/app/panelist/widgets/team_grade_chooser.dart';
import '../helpers/capture_preview.dart';
import '../helpers/pump_app.dart';

class _Client extends Mock implements AuthenticatedHttpClient {}

class _Guest extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
    user: {'id': 42, 'role': 'guest_panelist'},
    isRestoring: false,
  );
}

class _Online extends ConnectivityNotifier {
  @override
  bool build() => true;
}

Map<String, dynamic> _assignment(int id, String name) => {
  'id': id,
  'schedule_id': id,
  'name': name,
  'project_title': 'Project for $name',
  'scope': 'pit',
  'scheduled_date': TeamData.manilaToday.toIso8601String().split('T').first,
  'defense_stage': 'Concept Proposal',
  'start_time': '08:00',
  'room': '301',
  'grading_available': true,
  'evaluation_context': 'context-$id',
  'members': [
    {'id': 1, 'name': 'Alice', 'is_leader': true},
  ],
  'panel_rubric': {
    'target_type': 'team',
    'criteria': [
      {'id': 1, 'name': 'Clarity', 'max_score': 10},
    ],
  },
};
Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => registerFallbackValue(Uri.parse('https://example.test')));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'Assignments confirms identity and a failed save blocks leaving the grade sheet',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _Client();
      final assignments = [
        _assignment(20, 'Team SkyLedger'),
        _assignment(21, 'Team BioPulse'),
      ];
      var reversed = false;
      when(() => client.get(any())).thenAnswer((invocation) async {
        final path = (invocation.positionalArguments.first as Uri).path;
        return http.Response(
          json.encode(
            path.contains('guest-assignments')
                ? {
                    'teams': reversed
                        ? assignments.reversed.toList()
                        : assignments,
                  }
                : {'results': []},
          ),
          200,
        );
      });
      when(
        () => client.post(any(), body: any(named: 'body')),
      ).thenAnswer((_) async => http.Response('{"detail":"Offline"}', 503));
      await pumpDefensysWidget(
        tester,
        const PanelistDashboard(),
        overrides: [
          authProvider.overrideWith(_Guest.new),
          connectivityProvider.overrideWith(_Online.new),
          authenticatedHttpClientProvider.overrideWithValue(client),
        ],
      );
      await _tap(tester, find.text('Grade Team').first);
      expect(find.text('Team preview'), findsOneWidget);
      expect(
        tester
            .widget<NavigationBar>(
              find.byType(NavigationBar, skipOffstage: false),
            )
            .selectedIndex,
        0,
      );
      await _tap(tester, find.byKey(const ValueKey('confirm-team-selection')));
      expect(find.text('Currently grading'), findsOneWidget);
      final score = find.descendant(
        of: find.byType(EvaluationScorePicker),
        matching: find.byKey(const ValueKey('score-value-8')),
      );
      await _tap(tester, score);
      await _tap(tester, find.text('Results').last);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(
        find.text('Couldn’t save draft. Your changes are still here.'),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const ValueKey('open-panel-workspace')));
      await _tap(tester, find.byKey(const ValueKey('panel-history-view')));
      expect(
        tester
            .widget<PanelistSegmentedTabs<bool>>(
              find.byKey(const ValueKey('panel-workspace-tabs')),
            )
            .controller!
            .selected,
        isFalse,
      );
      expect(
        find.text(
          'Your draft could not be saved. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const ValueKey('close-panel-workspace')));
      when(() => client.post(any(), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response(
          '{"draft":{"saved_at":"2026-10-05T08:00:00+08:00"}}',
          200,
        ),
      );
      await _tap(tester, find.text('Assignments').last);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await _tap(tester, find.text('Grade Team').last);
      expect(find.text('Team preview'), findsOneWidget);
      // A background refresh reorders the list while the preview is open.
      // Confirmation must locate the schedule again, not use its old index.
      reversed = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('confirm-team-selection')));
      final sheet = tester.widget<GradeSheetTab>(find.byType(GradeSheetTab));
      expect(sheet.teams[sheet.selectedTeamIndex].scheduleId, '21');
      expect(sheet.selectedTeamIndex, 0);
      expect(find.text('Currently grading'), findsOneWidget);
      expect(
        tester
            .widget<EvaluationScorePicker>(find.byType(EvaluationScorePicker))
            .value,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'finished days move to History when a new session is assigned and all tabs share context',
    (tester) async {
      await loadPreviewFonts();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _Client();
      Map<String, dynamic> team(
        int id,
        String name,
        String stage,
        int stageId, {
        bool posted = false,
        bool completed = false,
      }) => {
        ..._assignment(id, name),
        'scope': 'capstone',
        'semester_id': 10,
        'display_semester': 'Second semester · 2026–2027',
        'defense_stage': stage,
        'defense_stage_id': stageId,
        'session_id': posted ? 'previous-session' : 'current-session',
        'scheduled_date':
            (posted
                    ? TeamData.manilaToday.subtract(const Duration(days: 1))
                    : TeamData.manilaToday)
                .toIso8601String()
                .split('T')
                .first,
        'is_submitted': posted,
        'is_completed': completed,
        'schedule_status': posted ? 'done' : 'scheduled',
        'display_status': completed
            ? 'completed'
            : posted
            ? 'grading_incomplete'
            : 'awaiting_evaluation',
        'grading_available': !posted,
        'verdict': posted ? 'approved' : '',
        'submissions': posted
            ? [
                {
                  'student_id': null,
                  'criteria_scores': [
                    {'criterion_id': 1, 'score': 8, 'max_score': 10},
                  ],
                },
              ]
            : [],
      };
      final assignments = [
        team(20, 'Team Assessed', 'Concept Proposal', 1, posted: true),
        team(21, 'Team Pending', 'Project Proposal', 2),
        {
          ...team(23, 'Team ReDefense', 'Concept Proposal', 1),
          'id': 20,
          'attempt_count': 2,
        },
        team(
          22,
          'Team Completed',
          'Concept Proposal',
          1,
          posted: true,
          completed: true,
        ),
      ];
      final results = [
        for (final assignment in assignments.where(
          (t) => t['is_submitted'] == true,
        ))
          {
            ...assignment,
            'teamName': assignment['name'],
            'projectTitle': assignment['project_title'],
            'stage': assignment['defense_stage'],
            'percentage': 80.0,
            'total': 8.0,
            'max': 10.0,
            'teamStatus': assignment['is_completed'] == true
                ? 'Approved'
                : 'Pending',
            'criteria': [
              {'criteriaName': 'Clarity', 'score': 8.0, 'max': 10.0},
            ],
            'memberGrades': [],
            'weights': {'panel': 50, 'peer': 20, 'adviser': 30},
          },
      ];
      when(() => client.get(any())).thenAnswer((invocation) async {
        final path = (invocation.positionalArguments.first as Uri).path;
        return http.Response(
          json.encode(
            path.contains('guest-assignments')
                ? {'teams': assignments}
                : {'results': results},
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      await pumpDefensysWidget(
        tester,
        const RepaintBoundary(
          key: ValueKey('panel-stage-history-preview'),
          child: PanelistDashboard(),
        ),
        overrides: [
          authProvider.overrideWith(_Guest.new),
          connectivityProvider.overrideWith(_Online.new),
          authenticatedHttpClientProvider.overrideWithValue(client),
        ],
      );
      // First visit prioritizes the stage with work requiring grading.
      expect(
        find.byKey(const ValueKey('panel-session-selector')),
        findsNothing,
      );
      expect(find.text('Team Pending'), findsOneWidget);
      expect(find.text('Team Assessed'), findsNothing);
      expect(find.text('Team Completed'), findsNothing);
      await _tap(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('panel-stage-selector')),
          matching: find.text('Capstone · Concept Proposal'),
        ),
      );
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Team ReDefense'), findsOneWidget);
      expect(find.text('Team Completed'), findsNothing);
      expect(
        tester
            .widget<AssignmentsTab>(find.byType(AssignmentsTab))
            .teams
            .single
            .scheduleId,
        '23',
      );
      final stageKey = PanelistStage.forTeam(
        tester.widget<AssignmentsTab>(find.byType(AssignmentsTab)).teams.single,
      ).key;
      await capturePreview(
        tester,
        find.byKey(const ValueKey('panel-stage-history-preview')),
        'panel-active-stage',
      );
      await _tap(tester, find.text('Results').last);
      final activeResults = tester.widget<OverallResultsTab>(
        find.byType(OverallResultsTab),
      );
      expect(activeResults.results, isEmpty);
      expect(find.text('Hide Detailed Breakdown'), findsNothing);
      expect(find.textContaining('All Stages'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('panel-history-view')));
      expect(
        tester
            .widget<OverallResultsTab>(find.byType(OverallResultsTab))
            .results
            .length,
        2,
      );
      expect(find.text('Team ReDefense'), findsNothing);
      expect(
        find.text('Pending'),
        findsWidgets,
      ); // Panel scores do not determine the official pass.
      expect(
        find.byKey(ValueKey('panel-stage-option-$stageKey')),
        findsOneWidget,
      );
      await capturePreview(
        tester,
        find.byKey(const ValueKey('panel-stage-history-preview')),
        'panel-history-results',
      );
      await _tap(tester, find.text('Assignments').last);
      expect(
        tester
            .widget<AssignmentsTab>(find.byType(AssignmentsTab))
            .teams
            .map((team) => team.scheduleId)
            .toSet(),
        {'20', '22'},
      );
      await _tap(tester, find.text('View Grades').first);
      await _tap(tester, find.byKey(const ValueKey('confirm-team-selection')));
      expect(find.byKey(const ValueKey('panel-workspace-tabs')), findsNothing);
      expect(find.byKey(const ValueKey('panel-stage-selector')), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('evaluation-footer'))).height,
        lessThan(90),
      );
      expect(find.byType(EvaluationScorePicker), findsNothing);
      expect(find.text('Submitted grades'), findsWidgets);
      await capturePreview(
        tester,
        find.byKey(const ValueKey('panel-stage-history-preview')),
        'panel-compact-submitted',
      );
      await _tap(tester, find.byKey(const ValueKey('open-panel-workspace')));
      expect(
        find.byKey(const ValueKey('panel-session-selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('panel-stage-selector')),
        findsOneWidget,
      );
      await capturePreview(
        tester,
        find
            .ancestor(
              of: find.byKey(const ValueKey('panel-workspace-sheet')),
              matching: find.byType(RepaintBoundary),
            )
            .first,
        'panel-history-sheet',
      );
      await _tap(tester, find.byKey(const ValueKey('panel-session-selector')));
      expect(find.text('Choose a past session'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('panel-session-search')),
        'Team Assessed',
      );
      await tester.pumpAndSettle();
      final historyTeam = tester
          .widget<GradeSheetTab>(find.byType(GradeSheetTab))
          .teams
          .first;
      await _tap(
        tester,
        find.byKey(
          ValueKey(
            'panel-session-option-${PanelistSession.teamKey(historyTeam)}',
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('panel-workspace-sheet')),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const ValueKey('panel-active-view')));
      expect(
        tester
            .widget<GradeSheetTab>(find.byType(GradeSheetTab))
            .teams
            .single
            .scheduleId,
        '21',
      );
      expect(
        find.byKey(const ValueKey('panel-session-selector')),
        findsNothing,
      );
      await _tap(tester, find.byKey(const ValueKey('panel-history-view')));
      expect(
        tester
            .widget<GradeSheetTab>(find.byType(GradeSheetTab))
            .teams
            .map((team) => team.scheduleId)
            .toSet(),
        {'20', '22'},
      );
      await _tap(tester, find.byKey(const ValueKey('close-panel-workspace')));
      await _tap(tester, find.text('Change team'));
      expect(
        tester
            .widget<TeamGradeChooser>(find.byType(TeamGradeChooser))
            .teams
            .map((team) => team.scheduleId)
            .toSet(),
        {'20', '22'},
      );
      expect(find.text('All stages / events'), findsNothing);
      await tester.tap(find.byTooltip('Keep current team'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('panel_stage_guest_panelist_42'), stageKey);
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets('single active context leaves room for grading at $width', (
      tester,
    ) async {
      await loadPreviewFonts(force: true);
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _Client();
      when(() => client.get(any())).thenAnswer((invocation) async {
        final path = (invocation.positionalArguments.first as Uri).path;
        return http.Response(
          json.encode(
            path.contains('guest-assignments')
                ? {
                    'teams': [_assignment(20, 'Team SkyLedger')],
                  }
                : {'results': []},
          ),
          200,
        );
      });
      when(() => client.post(any(), body: any(named: 'body'))).thenAnswer(
        (_) async => http.Response(
          '{"draft":{"saved_at":"2026-10-09T08:00:00+08:00"}}',
          200,
        ),
      );
      await pumpDefensysWidget(
        tester,
        const RepaintBoundary(
          key: ValueKey('panel-compact-preview'),
          child: PanelistDashboard(),
        ),
        overrides: [
          authProvider.overrideWith(_Guest.new),
          connectivityProvider.overrideWith(_Online.new),
          authenticatedHttpClientProvider.overrideWithValue(client),
        ],
      );
      expect(
        find.byKey(const ValueKey('panel-session-selector')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('panel-stage-selector')), findsNothing);
      expect(
        find.byKey(const ValueKey('panel-active-context')),
        findsOneWidget,
      );
      await capturePreview(
        tester,
        find.byKey(const ValueKey('panel-compact-preview')),
        'panel-compact-active-${width.toInt()}',
      );
      await _tap(tester, find.text('Grade Team'));
      await _tap(tester, find.byKey(const ValueKey('confirm-team-selection')));
      expect(find.byKey(const ValueKey('panel-workspace-tabs')), findsNothing);
      expect(find.byKey(const ValueKey('panel-active-context')), findsNothing);
      expect(
        find.byKey(const ValueKey('open-panel-workspace')),
        findsOneWidget,
      );
      final viewport = find.descendant(
        of: find.byType(GradeSheetTab),
        matching: find.byType(SingleChildScrollView),
      );
      expect(tester.getSize(viewport).height, greaterThan(400));
      expect(
        tester.getSize(find.byKey(const ValueKey('evaluation-footer'))).height,
        lessThan(100),
      );
      final score = find.descendant(
        of: find.byType(EvaluationScorePicker),
        matching: find.byKey(const ValueKey('score-value-8')),
      );
      await _tap(tester, score);
      await _tap(tester, find.byKey(const ValueKey('more-grading-actions')));
      expect(find.text('Save Draft'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('save-evaluation-draft')));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('draft-save-state')))
            .data,
        contains('Draft saved'),
      );
      expect(find.text('Save Draft'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(EvaluationScorePicker));
      await tester.pumpAndSettle();
      await capturePreview(
        tester,
        find.byKey(const ValueKey('panel-compact-preview')),
        'panel-compact-grading-${width.toInt()}',
      );
      await _tap(tester, find.byKey(const ValueKey('open-panel-workspace')));
      expect(
        find.byKey(const ValueKey('panel-workspace-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('panel-session-selector')),
        findsNothing,
      );
      await _tap(tester, find.byKey(const ValueKey('close-panel-workspace')));
      expect(_valueForScore(tester), 8);
      expect(tester.takeException(), isNull);
    });
  }
}

double? _valueForScore(WidgetTester tester) => tester
    .widget<EvaluationScorePicker>(find.byType(EvaluationScorePicker))
    .value;
