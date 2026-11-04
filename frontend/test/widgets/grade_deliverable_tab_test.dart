import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/screens/web/shared/team_deliverables/dialogs/grade_deliverable_modal.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/widgets/export/report_export_menu.dart';

import '../helpers/pump_app.dart';
import '../helpers/capture_preview.dart';

void main() {
  setUpAll(loadPreviewFonts);
  final mockTeam = {
    'id': 10,
    'name': 'Team SkyLedger',
    'project_title': 'Alumni Career Tracker',
    'members': [
      {'id': 1, 'name': 'Marcus VILLAR', 'role': 'leader'},
      {'id': 2, 'name': 'Patricia ONG', 'role': 'member'},
      {'id': 3, 'name': 'Ethan SALAZAR', 'role': 'member'},
      {'id': 4, 'name': 'Zoe CASTILLO', 'role': 'member'},
    ],
  };

  final mockGradeRecord = {
    'id': 100,
    'team_id': 10,
    'stage_label': 'Concept Proposal',
    'status': 'pending',
    'adviser_grading_available': true,
    'assigned_adviser_rubric_id': 5,
    'assigned_adviser_rubric_name': 'CP - Adviser',
    'assigned_adviser_rubric_scale': '10-Point Scale',
    'assigned_adviser_rubric_target_type': 'both',
    'assigned_adviser_criteria': [
      {
        'id': 501,
        'name': 'Literature Grounding',
        'description': 'Relevance and depth of background literature',
        'max_score': 10,
        'target_type': 'team',
        'display_order': 0,
      },
      {
        'id': 502,
        'name': 'Scope Appropriateness',
        'description': 'Student understanding of project scope',
        'max_score': 10,
        'target_type': 'individual',
        'display_order': 1,
      },
      {
        'id': 503,
        'name': 'Research Questions',
        'description': 'Clarity of student research formulation',
        'max_score': 10,
        'target_type': 'individual',
        'display_order': 2,
      },
    ],
    'members': [
      {'id': 1, 'name': 'Marcus VILLAR', 'is_leader': true},
      {'id': 2, 'name': 'Patricia ONG', 'is_leader': false},
      {'id': 3, 'name': 'Ethan SALAZAR', 'is_leader': false},
      {'id': 4, 'name': 'Zoe CASTILLO', 'is_leader': false},
    ],
    'breakdowns': [],
  };

  testWidgets('unopened grading does not show an empty overall assessment', (
    tester,
  ) async {
    final notifier = _MockAdviserGradingNotifier([]);
    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: GradeDeliverableTab(
          team: mockTeam,
          selectedStage: 'Concept Proposal',
          isAdviser: true,
          teamCriteriaScoreCtrls: {},
          teamStudentCriteriaScoreCtrls: {},
          teamManualScoreCtrls: {},
          teamSelectedRubrics: {},
        ),
      ),
      overrides: [adviserGradingProvider.overrideWith(() => notifier)],
    );

    expect(find.text('Grading is not open yet'), findsOneWidget);
    expect(find.textContaining('Overall assessment'), findsNothing);
    expect(find.text('Awaiting all scores'), findsNothing);
  });

  testWidgets('PIT grades are informative and exports keep the exact event', (
    tester,
  ) async {
    final notifier = _MockAdviserGradingNotifier([
      {
        ...mockGradeRecord,
        'scope': 'pit',
        'semester_id': 7,
        'panel_score': 85.0,
      },
    ]);
    final selectedRubrics = <String, Map<String, dynamic>?>{};
    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: GradeDeliverableTab(
          team: mockTeam,
          selectedStage: 'Concept Proposal',
          programScope: 'pit',
          isAdviser: true,
          teamCriteriaScoreCtrls: {},
          teamStudentCriteriaScoreCtrls: {},
          teamManualScoreCtrls: {},
          teamSelectedRubrics: selectedRubrics,
        ),
      ),
      overrides: [
        adviserGradingProvider.overrideWith(() => notifier),
        authProvider.overrideWith(_GradeExportAuth.new),
      ],
    );
    expect(find.text('Adviser evaluation'), findsNothing);
    expect(find.text('Submit Adviser Grade'), findsNothing);
    expect(selectedRubrics, isEmpty);
    await tester.tap(find.text('Event grade breakdown'));
    await tester.pumpAndSettle();
    expect(find.text('Adviser'), findsNothing);
    expect(find.text('Panel'), findsOneWidget);
    expect(find.text('Peer'), findsOneWidget);
    expect(find.text('85.00'), findsOneWidget);
    var export = tester.widget<ReportExportMenu>(find.byType(ReportExportMenu));
    expect(export.reportId, 'team-grade');
    expect(export.params, containsPair('grade_id', '100'));
    expect(export.params, containsPair('scope', 'pit'));
    expect(export.params, containsPair('semester_id', '7'));
    await tester.tap(find.text('Team and all members'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcus VILLAR').last);
    await tester.pumpAndSettle();
    export = tester.widget<ReportExportMenu>(find.byType(ReportExportMenu));
    expect(export.reportId, 'individual-grade');
    expect(export.params, containsPair('student_id', '1'));
    expect(export.params, containsPair('grade_id', '100'));
    await tester.tap(find.text('Export').first);
    await tester.pumpAndSettle();
    expect(find.text('Export Excel'), findsOneWidget);
    expect(find.text('Export PDF'), findsOneWidget);
  });

  testWidgets('recorded scores remain visible when adviser grading is closed', (
    tester,
  ) async {
    final notifier = _MockAdviserGradingNotifier([
      {
        ...mockGradeRecord,
        'adviser_grading_available': false,
        'panel_score': 85.0,
      },
    ]);
    await pumpDefensysWidget(
      tester,
      SingleChildScrollView(
        child: GradeDeliverableTab(
          team: mockTeam,
          selectedStage: 'Concept Proposal',
          isAdviser: true,
          teamCriteriaScoreCtrls: {},
          teamStudentCriteriaScoreCtrls: {},
          teamManualScoreCtrls: {},
          teamSelectedRubrics: {},
        ),
      ),
      overrides: [adviserGradingProvider.overrideWith(() => notifier)],
    );

    expect(find.text('Stage grade breakdown'), findsOneWidget);
    await tester.ensureVisible(find.text('Stage grade breakdown'));
    await tester.tap(find.text('Stage grade breakdown'));
    await tester.pumpAndSettle();
    expect(find.textContaining('85'), findsWidgets);
  });

  testWidgets(
    'GradeDeliverableTab renders team and individual criteria for both target type',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final teamCriteriaCtrls = <String, Map<String, TextEditingController>>{};
      final teamStudentCriteriaCtrls =
          <String, Map<dynamic, Map<String, TextEditingController>>>{};
      final teamManualCtrls = <String, TextEditingController>{};
      final teamSelectedRubrics = <String, Map<String, dynamic>?>{};

      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: GradeDeliverableTab(
            team: mockTeam,
            selectedStage: 'Concept Proposal',
            isAdviser: true,
            teamCriteriaScoreCtrls: teamCriteriaCtrls,
            teamStudentCriteriaScoreCtrls: teamStudentCriteriaCtrls,
            teamManualScoreCtrls: teamManualCtrls,
            teamSelectedRubrics: teamSelectedRubrics,
          ),
        ),
        overrides: [
          adviserGradingProvider.overrideWith(() {
            return _MockAdviserGradingNotifier([mockGradeRecord]);
          }),
        ],
      );

      // Verify rubric header and target type pill
      expect(find.text('Adviser evaluation'), findsOneWidget);
      expect(find.textContaining('CP - Adviser'), findsOneWidget);
      expect(find.textContaining('Overall assessment'), findsNothing);

      // 1 team criterion + 2 individual * 4 students = 9 total
      expect(find.text('0 of 4 members scored'), findsOneWidget);
      expect(find.text('Not complete'), findsOneWidget);
      expect(find.textContaining('0.00 / 100'), findsNothing);

      // Verify Team-Wide Criteria section
      expect(find.text('Team criteria'), findsOneWidget);
      expect(find.text('Literature Grounding'), findsOneWidget);

      // Verify Individual Criteria section
      expect(find.text('Members'), findsOneWidget);
      expect(find.text('Patricia ONG'), findsOneWidget);

      // Verify student tabs
      expect(find.text('Marcus VILLAR'), findsWidgets);
      expect(find.text('Patricia ONG'), findsWidgets);
      expect(find.text('Ethan SALAZAR'), findsWidgets);
      expect(find.text('Zoe CASTILLO'), findsWidgets);
      expect(
        tester
            .widget<ShadButton>(
              find.widgetWithText(ShadButton, 'Submit Adviser Grade'),
            )
            .enabled,
        isFalse,
      );
      await capturePreview(
        tester,
        find.byType(GradeDeliverableTab),
        'adviser-evaluation/desktop',
        viewport: true,
      );

      // First student is active by default
      expect(find.text('Scoring: Marcus VILLAR'), findsOneWidget);
      expect(find.text('Scope Appropriateness'), findsOneWidget);
      expect(find.text('Research Questions'), findsOneWidget);

      // Tap second student tab (Patricia ONG)
      await tester.tap(find.text('Patricia ONG').first);
      await tester.pumpAndSettle();

      // Active student should now be Patricia ONG
      expect(find.text('Scoring: Patricia ONG'), findsOneWidget);
    },
  );

  for (final target in ['team', 'individual']) {
    testWidgets(
      '$target rubric distinguishes missing, invalid and zero scores',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        final record = {
          ...mockGradeRecord,
          'assigned_adviser_rubric_target_type': target,
          'assigned_adviser_criteria': [
            {
              'id': 1,
              'name': 'Contribution',
              'max_score': 10,
              'target_type': target,
            },
          ],
        };
        final teamControllers = <String, Map<String, TextEditingController>>{};
        final memberControllers =
            <String, Map<dynamic, Map<String, TextEditingController>>>{};
        await pumpDefensysWidget(
          tester,
          SingleChildScrollView(
            child: GradeDeliverableTab(
              team: mockTeam,
              selectedStage: 'Concept Proposal',
              isAdviser: true,
              teamCriteriaScoreCtrls: teamControllers,
              teamStudentCriteriaScoreCtrls: memberControllers,
              teamManualScoreCtrls: {},
              teamSelectedRubrics: {},
            ),
          ),
          overrides: [
            adviserGradingProvider.overrideWith(
              () => _MockAdviserGradingNotifier([record]),
            ),
          ],
        );
        expect(find.text('Not complete'), findsOneWidget);
        final input = find.byType(EditableText).first;
        await tester.enterText(input, '11');
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ShadButton>(
                find.widgetWithText(ShadButton, 'Submit Adviser Grade'),
              )
              .enabled,
          isFalse,
        );
        await tester.enterText(input, '0');
        if (target == 'individual') {
          for (final name in [
            'Patricia ONG',
            'Ethan SALAZAR',
            'Zoe CASTILLO',
          ]) {
            await tester.tap(find.text(name));
            await tester.pumpAndSettle();
            await tester.enterText(find.byType(EditableText).first, '0');
          }
        }
        await tester.pumpAndSettle();
        expect(find.text('Not complete'), findsNothing);
        expect(find.text('0.00 / 100'), findsOneWidget);
        expect(
          tester
              .widget<ShadButton>(
                find.widgetWithText(ShadButton, 'Submit Adviser Grade'),
              )
              .enabled,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'member scoring fits $width pixels, dark=$dark, enlarged text',
        (tester) async {
          tester.view.physicalSize = Size(width, 1500);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          await pumpDefensysWidget(
            tester,
            MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1500),
                textScaler: TextScaler.linear(1.25),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: GradeDeliverableTab(
                    team: mockTeam,
                    selectedStage: 'Concept Proposal',
                    isAdviser: true,
                    teamCriteriaScoreCtrls: {},
                    teamStudentCriteriaScoreCtrls: {},
                    teamManualScoreCtrls: {},
                    teamSelectedRubrics: {},
                  ),
                ),
              ),
            ),
            theme: dark ? AppTheme.mistDarkTheme : AppTheme.lightTheme,
            overrides: [
              adviserGradingProvider.overrideWith(
                () => _MockAdviserGradingNotifier([mockGradeRecord]),
              ),
            ],
          );
          await tester.tap(find.text('Patricia ONG'));
          await tester.pumpAndSettle();
          expect(find.text('Scoring: Patricia ONG'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capturePreview(
            tester,
            find.byType(GradeDeliverableTab),
            'adviser-evaluation/$width-${dark ? 'dark' : 'light'}',
            viewport: true,
          );
        },
      );
    }
  }

  testWidgets(
    'GradeDeliverableTab correctly computes scores and submits full payload for both target type',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final teamCriteriaCtrls = <String, Map<String, TextEditingController>>{};
      final teamStudentCriteriaCtrls =
          <String, Map<dynamic, Map<String, TextEditingController>>>{};
      final teamManualCtrls = <String, TextEditingController>{};
      final teamSelectedRubrics = <String, Map<String, dynamic>?>{};
      final notifier = _MockAdviserGradingNotifier([mockGradeRecord]);

      await pumpDefensysWidget(
        tester,
        SingleChildScrollView(
          child: GradeDeliverableTab(
            team: mockTeam,
            selectedStage: 'Concept Proposal',
            isAdviser: true,
            teamCriteriaScoreCtrls: teamCriteriaCtrls,
            teamStudentCriteriaScoreCtrls: teamStudentCriteriaCtrls,
            teamManualScoreCtrls: teamManualCtrls,
            teamSelectedRubrics: teamSelectedRubrics,
          ),
        ),
        overrides: [adviserGradingProvider.overrideWith(() => notifier)],
      );

      final key = '10-Concept Proposal';
      // Team score: 9 / 10
      teamCriteriaCtrls[key]!['Literature Grounding']!.text = '9';

      // Student 1 (Marcus): 9 + 8 + 8 = 25 / 30 -> 83.33%
      teamStudentCriteriaCtrls[key]![1]!['Scope Appropriateness']!.text = '8';
      teamStudentCriteriaCtrls[key]![1]!['Research Questions']!.text = '8';

      // Student 2 (Patricia): 9 + 10 + 10 = 29 / 30 -> 96.67%
      teamStudentCriteriaCtrls[key]![2]!['Scope Appropriateness']!.text = '10';
      teamStudentCriteriaCtrls[key]![2]!['Research Questions']!.text = '10';

      // Student 3 (Ethan): 9 + 7 + 7 = 23 / 30 -> 76.67%
      teamStudentCriteriaCtrls[key]![3]!['Scope Appropriateness']!.text = '7';
      teamStudentCriteriaCtrls[key]![3]!['Research Questions']!.text = '7';

      // Student 4 (Zoe): 9 + 9 + 9 = 27 / 30 -> 90.00%
      teamStudentCriteriaCtrls[key]![4]!['Scope Appropriateness']!.text = '9';
      teamStudentCriteriaCtrls[key]![4]!['Research Questions']!.text = '9';

      // Trigger rebuild with updated controllers
      await tester.tap(find.text('Patricia ONG').first);
      await tester.pumpAndSettle();

      // Verify all 9 criteria are scored
      expect(find.text('4 of 4 members scored'), findsOneWidget);

      // Active student is Patricia: (9 + 10 + 10) / 30 * 100 = 96.67
      expect(find.text('Student score: 96.67 / 100'), findsOneWidget);

      // Overall team average: (83.333... + 96.666... + 76.666... + 90.0) / 4 = 86.67
      expect(find.text('86.67 / 100'), findsOneWidget);

      // Tap submit button
      final submitBtn = find.text('Submit Adviser Grade');
      expect(submitBtn, findsOneWidget);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Verify payload sent to provider
      expect(notifier.lastSubmittedPayload, isNotNull);
      expect(notifier.lastSubmittedPayload!['gradeId'], 100);
      expect(notifier.lastSubmittedPayload!['rubricId'], 5);
      expect(
        notifier.lastSubmittedPayload!['adviserScore'],
        closeTo(86.67, 0.01),
      );

      final teamScores =
          notifier.lastSubmittedPayload!['teamCriteriaScores'] as List;
      expect(teamScores.length, 1);
      expect(teamScores[0]['criterion_name'], 'Literature Grounding');
      expect(teamScores[0]['score'], 9.0);

      final studentSubs =
          notifier.lastSubmittedPayload!['studentSubmissions'] as List;
      expect(studentSubs.length, 4);
      expect(studentSubs[0]['student_id'], 1);
      expect(studentSubs[0]['criteria_scores'].length, 2);
      expect(studentSubs[1]['student_id'], 2);
      expect(studentSubs[1]['criteria_scores'][0]['score'], 10.0);

      // Drain toast timers
      await tester.pump(const Duration(seconds: 5));
    },
  );
}

class _GradeExportAuth extends AuthNotifier {
  @override
  AuthState build() =>
      AuthState(user: {'id': 1, 'role': 'faculty', 'is_pit_lead': true});
}

class _MockAdviserGradingNotifier extends AdviserGradingNotifier {
  final List<Map<String, dynamic>> _initialGrades;
  Map<String, dynamic>? lastSubmittedPayload;

  _MockAdviserGradingNotifier(this._initialGrades);

  @override
  AdviserGradingState build() {
    return AdviserGradingState(
      isLoading: false,
      adviserGradingEnabled: true,
      grades: _initialGrades,
    );
  }

  @override
  Future<bool> submitGrade({
    required int gradeId,
    double? adviserScore,
    int? rubricId,
    List<Map<String, dynamic>> criteriaScores = const [],
    List<Map<String, dynamic>> teamCriteriaScores = const [],
    List<Map<String, dynamic>> studentSubmissions = const [],
  }) async {
    lastSubmittedPayload = {
      'gradeId': gradeId,
      'adviserScore': adviserScore,
      'rubricId': rubricId,
      'criteriaScores': criteriaScores,
      'teamCriteriaScores': teamCriteriaScores,
      'studentSubmissions': studentSubmissions,
    };
    return true;
  }
}
