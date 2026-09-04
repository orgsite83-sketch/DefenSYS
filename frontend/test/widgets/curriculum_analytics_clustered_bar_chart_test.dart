import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import 'package:defensys/screens/web/admin/curriculum_analytics/curriculum_analytics_screen.dart';
import 'package:defensys/services/academic/curriculum_analytics_provider.dart';

void main() {
  testWidgets('CurriculumAnalyticsScreen renders Clustered Bar Chart and allows switching views', (tester) async {
    final fakeState = CurriculumAnalyticsState(
      isLoading: false,
      data: {
        'academic_years': ['2026-2027'],
        'entries_count': 12,
        'kpi_summary': {
          'competency_index': 86.1,
          'top_domain': 'Artificial Intelligence & ML',
          'stages_count': 3,
          'bottleneck_stage': 'Concept Proposal',
          'has_evaluations': true,
        },
        'available_stages': [
          {'id': '1', 'label': 'Concept Proposal', 'code': 'CP', 'display_order': 1},
          {'id': '2', 'label': 'Final Defense', 'code': 'PP', 'display_order': 2},
        ],
        'stage_performance_overview': [
          {
            'stage_id': '1',
            'stage_name': 'Concept Proposal',
            'code': 'CP',
            'total_teams': 6,
            'average_score': 84.5,
            'pass_rate': 83,
            'rubrics_count': 1,
            'criteria_count': 2,
            'evaluator_breakdown': {
              'panel': {'score': 82.0, 'count': 4},
              'adviser': {'score': 88.0, 'count': 2},
              'peer': {'score': 83.5, 'count': 2},
            },
            'score_spread': {'min': 78.0, 'avg': 84.5, 'max': 91.0},
          },
          {
            'stage_id': '2',
            'stage_name': 'Final Defense',
            'code': 'PP',
            'total_teams': 6,
            'average_score': 91.0,
            'pass_rate': 100,
            'rubrics_count': 1,
            'criteria_count': 2,
            'evaluator_breakdown': {
              'panel': {'score': 90.0, 'count': 4},
              'adviser': {'score': 94.0, 'count': 2},
              'peer': {'score': 89.0, 'count': 2},
            },
            'score_spread': {'min': 86.0, 'avg': 91.0, 'max': 96.0},
          },
        ],
        'available_rubrics': [
          {'id': '1', 'name': 'Adviser Rubric', 'stage': 'Concept Proposal', 'defense_stage_id': '1'},
          {'id': '2', 'name': 'Panel Rubric', 'stage': 'Final Defense', 'defense_stage_id': '2'},
        ],
        'competency_matrix': [
          {
            'id': '1',
            'name': 'Problem Statement & Feasibility',
            'aligned_course': 'IT312 Advanced App Development',
            'rubric_name': 'Concept Proposal Rubric',
            'stage_id': '1',
            'stage_name': 'Concept Proposal',
            'stage_label': 'Concept Proposal',
            'average_score': 90.0,
            'evaluations_count': 6,
            'evaluator_breakdown': {
              'panel': {'score': 88.0, 'count': 4},
              'adviser': {'score': 92.0, 'count': 2},
              'peer': {'score': 85.0, 'count': 2},
            },
            'stage_breakdown': [
              {'stage': 'Concept Proposal', 'score': 90.0, 'count': 6},
            ],
            'score_spread': {
              'min': 82.0,
              'avg': 90.0,
              'max': 95.0,
            },
            'status': 'Good (80%+)',
            'color': '#10B981',
          },
          {
            'id': '2',
            'name': 'System Implementation & Code',
            'aligned_course': 'DIT Capstone Colloquium',
            'rubric_name': 'Final Defense Rubric',
            'stage_id': '2',
            'stage_name': 'Final Defense',
            'stage_label': 'Final Defense',
            'average_score': 82.2,
            'evaluations_count': 18,
            'evaluator_breakdown': {
              'panel': {'score': 80.0, 'count': 10},
              'adviser': {'score': 85.0, 'count': 4},
              'peer': {'score': 82.0, 'count': 4},
            },
            'stage_breakdown': [
              {'stage': 'Final Defense', 'score': 82.2, 'count': 18},
            ],
            'score_spread': {
              'min': 74.0,
              'avg': 82.2,
              'max': 90.0,
            },
            'status': 'Good (80%+)',
            'color': '#10B981',
          },
        ],
        'domain_distribution': [],
        'distribution': [],
        'defense_funnel': {
          'stages': [],
          'verdicts_distribution': [],
          'total_evaluated': 10,
        },
        'prescriptions': [],
      },
    );

    await tester.binding.setSurfaceSize(const Size(1600, 1600));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          curriculumAnalyticsProvider.overrideWith(() => _FakeNotifier(fakeState)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CurriculumAnalyticsScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Top Stage Pill Switcher
    expect(find.text('🌐 Overall (All Stages)'), findsOneWidget);
    expect(find.text('📝 Concept Proposal'), findsOneWidget);
    expect(find.text('🎓 Final Defense'), findsOneWidget);

    // 2. Verify Overall Macro View
    expect(find.text('Stage-by-Stage Performance Overview'), findsOneWidget);
    expect(find.text('Clustered Chart'), findsOneWidget);
    expect(find.text('Detailed Cards'), findsOneWidget);
    expect(find.byType(SfCartesianChart), findsOneWidget);
    expect(find.text('HIGHEST PERFORMING STAGE'), findsOneWidget);

    // 3. Drill down into Concept Proposal stage
    await tester.tap(find.text('📝 Concept Proposal'));
    await tester.pumpAndSettle();

    // 4. Verify Concept Proposal criteria drilldown
    expect(find.text('Concept Proposal: Rubric Criteria'), findsOneWidget);
    expect(find.textContaining('Problem Statement & Feasibility'), findsWidgets);

    // 5. Switch to Detailed Cards View in Stage Mode
    await tester.ensureVisible(find.text('Detailed Cards'));
    await tester.tap(find.text('Detailed Cards'));
    await tester.pumpAndSettle();

    // Verify Card View Items
    expect(find.textContaining('Course Link: IT312 Advanced App Development'), findsOneWidget);
    expect(find.text('6 evaluations recorded'), findsOneWidget);

    // 6. Switch back to Clustered Chart View
    await tester.ensureVisible(find.text('Clustered Chart'));
    await tester.tap(find.text('Clustered Chart'));
    await tester.pumpAndSettle();

    // 7. Switch back to Overall Macro View
    await tester.tap(find.text('🌐 Overall (All Stages)'));
    await tester.pumpAndSettle();
    expect(find.text('Stage-by-Stage Performance Overview'), findsOneWidget);
  });
}

class _FakeNotifier extends CurriculumAnalyticsNotifier {
  final CurriculumAnalyticsState _initial;
  _FakeNotifier(this._initial);

  @override
  CurriculumAnalyticsState build() => _initial;

  @override
  Future<void> fetchAnalytics({
    String? academicYear,
    String? rubricId,
    String? program,
    String? scope,
  }) async {}
}
