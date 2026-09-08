import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/screens/web/shared/team_deliverables/dialogs/grade_deliverable_modal.dart';
import 'package:defensys/services/adviser_grading_provider.dart';

import '../helpers/pump_app.dart';

void main() {
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

  testWidgets('GradeDeliverableTab renders team and individual criteria for both target type', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final teamCriteriaCtrls = <String, Map<String, TextEditingController>>{};
    final teamStudentCriteriaCtrls = <String, Map<dynamic, Map<String, TextEditingController>>>{};
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
    expect(find.textContaining('Rubric: CP - Adviser'), findsOneWidget);
    expect(find.text('Both (Team & Individual)'), findsOneWidget);

    // 1 team criterion + 2 individual * 4 students = 9 total
    expect(find.text('0 / 9 scored'), findsOneWidget);

    // Verify Team-Wide Criteria section
    expect(find.text('Team-Wide Criteria'), findsOneWidget);
    expect(find.text('Literature Grounding'), findsOneWidget);

    // Verify Individual Criteria section
    expect(find.text('Individual Criteria (Score Each Member)'), findsOneWidget);

    // Verify student tabs
    expect(find.text('Marcus VILLAR'), findsWidgets);
    expect(find.text('Patricia ONG'), findsWidgets);
    expect(find.text('Ethan SALAZAR'), findsWidgets);
    expect(find.text('Zoe CASTILLO'), findsWidgets);

    // First student is active by default
    expect(find.text('Scoring: Marcus VILLAR'), findsOneWidget);
    expect(find.text('Scope Appropriateness'), findsOneWidget);
    expect(find.text('Research Questions'), findsOneWidget);

    // Tap second student tab (Patricia ONG)
    await tester.tap(find.text('Patricia ONG').first);
    await tester.pumpAndSettle();

    // Active student should now be Patricia ONG
    expect(find.text('Scoring: Patricia ONG'), findsOneWidget);
  });

  testWidgets('GradeDeliverableTab correctly computes scores and submits full payload for both target type', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final teamCriteriaCtrls = <String, Map<String, TextEditingController>>{};
    final teamStudentCriteriaCtrls = <String, Map<dynamic, Map<String, TextEditingController>>>{};
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
      overrides: [
        adviserGradingProvider.overrideWith(() => notifier),
      ],
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
    expect(find.text('9 / 9 scored'), findsOneWidget);

    // Active student is Patricia: (9 + 10 + 10) / 30 * 100 = 96.67
    expect(find.text('Student Score: 96.67 / 100'), findsOneWidget);

    // Overall team average: (83.333... + 96.666... + 76.666... + 90.0) / 4 = 86.67
    expect(find.text('86.67'), findsOneWidget);

    // Tap submit button
    final submitBtn = find.text('Submit Adviser Grade');
    expect(submitBtn, findsOneWidget);
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    // Verify payload sent to provider
    expect(notifier.lastSubmittedPayload, isNotNull);
    expect(notifier.lastSubmittedPayload!['gradeId'], 100);
    expect(notifier.lastSubmittedPayload!['rubricId'], 5);
    expect(notifier.lastSubmittedPayload!['adviserScore'], closeTo(86.67, 0.01));

    final teamScores = notifier.lastSubmittedPayload!['teamCriteriaScores'] as List;
    expect(teamScores.length, 1);
    expect(teamScores[0]['criterion_name'], 'Literature Grounding');
    expect(teamScores[0]['score'], 9.0);

    final studentSubs = notifier.lastSubmittedPayload!['studentSubmissions'] as List;
    expect(studentSubs.length, 4);
    expect(studentSubs[0]['student_id'], 1);
    expect(studentSubs[0]['criteria_scores'].length, 2);
    expect(studentSubs[1]['student_id'], 2);
    expect(studentSubs[1]['criteria_scores'][0]['score'], 10.0);

    // Drain toast timers
    await tester.pump(const Duration(seconds: 5));
  });
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
