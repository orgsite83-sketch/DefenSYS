import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../../../services/academic/curriculum_analytics_provider.dart';
import '../../../../theme/app_theme.dart';
import '../widgets/defensys_admin_shell.dart';
import '../admin_shell.dart';

class CurriculumAnalyticsScreen extends ConsumerStatefulWidget {
  const CurriculumAnalyticsScreen({super.key});

  @override
  ConsumerState<CurriculumAnalyticsScreen> createState() =>
      _CurriculumAnalyticsScreenState();
}

class _CurriculumAnalyticsScreenState
    extends ConsumerState<CurriculumAnalyticsScreen> {
  int _scoresViewMode = 0; // 0: Clustered Bar Chart View, 1: Detailed Cards View
  int _clusterGrouping = 0; // 0: By Evaluator Role, 1: By Defense Stage, 2: By Metric Spread
  String _selectedStageFilter = 'all'; // 'all' for Overall Macro View, or specific stage id/name
  String _selectedScope = 'all'; // 'all', 'capstone', 'pit'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(curriculumAnalyticsProvider.notifier).fetchAnalytics();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<DefensysAdminSection>(
      activeAdminSectionProvider,
      (previous, next) {
        if (next == DefensysAdminSection.curriculumAnalytics) {
          ref.read(curriculumAnalyticsProvider.notifier).fetchAnalytics();
        }
      },
    );

    final state = ref.watch(curriculumAnalyticsProvider);

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(state),
          const SizedBox(height: 16),
          _buildTrackSwitcher(state),
          const SizedBox(height: 18),
          _buildSummaryMetrics(state),
          if (state.error != null) ...[
            const SizedBox(height: 14),
            _notice(Icons.error_outline_rounded, state.error!, AppColors.danger),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 14),
            _notice(Icons.check_circle_outline_rounded, state.message!, AppColors.success),
          ],
          const SizedBox(height: 24),
          if (state.isLoading)
            const SizedBox(
              height: 320,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.maroon),
              ),
            )
          else ...[
            // 1. Rubric Criteria & Student Performance
            _sectionHeader(
              icon: Icons.checklist_rtl_rounded,
              title: 'Rubric Criteria & Student Performance',
              subtitle: 'Average scores across rubric criteria and defense stages (${_scopeDisplayName(_selectedScope)})',
            ),
            const SizedBox(height: 12),
            _buildStudentScoresTab(state),
            const SizedBox(height: 32),

            // 2. Defense Stage Outcomes
            _sectionHeader(
              icon: Icons.alt_route_rounded,
              title: 'Defense Stage Outcomes & Pipeline',
              subtitle: 'First-time pass rates, revisions, and re-defense requirements by stage',
            ),
            const SizedBox(height: 12),
            _buildDefenseResultsAndTipsTab(state),
            const SizedBox(height: 32),

            // 3. Faculty Evaluator Scoring & Calibration
            _sectionHeader(
              icon: Icons.balance_rounded,
              title: 'Faculty Evaluator Scoring & Calibration',
              subtitle: 'Grading consistency between external defense panelists and project advisers',
            ),
            const SizedBox(height: 12),
            _buildEvaluatorCalibrationTab(state),
            const SizedBox(height: 32),

            // 4. Project Topics & Technology Stacks
            _sectionHeader(
              icon: Icons.category_rounded,
              title: 'Project Topics & Technology Stacks',
              subtitle: 'Specialization domains and frameworks detected from student deliverable submissions',
            ),
            const SizedBox(height: 12),
            _buildProjectTopicsTab(state),
            const SizedBox(height: 32),

            // 5. Improvement Recommendations
            _sectionHeader(
              icon: Icons.lightbulb_rounded,
              title: 'Improvement Recommendations',
              subtitle: 'Actionable suggestions based on student rubric scores and stage revision workloads',
            ),
            const SizedBox(height: 12),
            _buildPrescriptiveActionsTab(state),
            const SizedBox(height: 32),

            _buildSummaryFooter(state),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER & ACTIONS
  // ---------------------------------------------------------------------------

  Widget _buildHeader(CurriculumAnalyticsState state) {
    final years = _stringList(state.data['academic_years']);
    final selectedYear = state.selectedAcademicYear;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.maroon,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: AppColors.maroon.withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.insights_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Curriculum & Performance Analytics',
                style: TextStyle(
                  color: AppColors.maroon,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Student grades, defense results, and improvement recommendations',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        if (years.isNotEmpty) ...[
          _academicYearDropdown(years, selectedYear),
          const SizedBox(width: 10),
        ],
        _secondaryButton(
          icon: Icons.picture_as_pdf_rounded,
          label: state.isDownloadingPdf ? 'Exporting...' : 'Export PDF',
          onTap: state.isDownloadingPdf ? null : _downloadPdfReport,
        ),
        const SizedBox(width: 10),
        _primaryButton(
          icon: Icons.auto_awesome_rounded,
          label: state.isSaving ? 'Generating...' : 'Generate Proposal',
          onTap: state.isSaving ? null : _generateProposalModal,
        ),
      ],
    );
  }

  Widget _academicYearDropdown(List<String> years, String selectedYear) {
    final selected = years.contains(selectedYear) ? selectedYear : (years.isNotEmpty ? years.first : '');

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD1D5DB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected.isEmpty ? null : selected,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textPrimary),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
          items: years
              .map((year) => DropdownMenuItem(
                    value: year,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text('AY $year'),
                      ],
                    ),
                  ))
              .toList(),
          onChanged: (value) {
            if (value != null) {
              ref.read(curriculumAnalyticsProvider.notifier).fetchAnalytics(academicYear: value);
            }
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TRACK SWITCHER (CAPSTONE VS PIT VS UNIFIED)
  // ---------------------------------------------------------------------------

  Widget _buildTrackSwitcher(CurriculumAnalyticsState state) {
    final scopes = [
      {
        'key': 'capstone',
        'label': '🎯 Capstone Track',
        'sublabel': '4th Year Defense Stages',
        'color': AppColors.maroon,
      },
      {
        'key': 'pit',
        'label': '🔬 PIT Track',
        'sublabel': '1st–3rd Year Events',
        'color': const Color(0xFF0EA5E9),
      },
      {
        'key': 'all',
        'label': '🌐 Unified Overview',
        'sublabel': 'Cross-Cohort Impact',
        'color': const Color(0xFF6366F1),
      },
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;
          return Row(
            children: scopes.map((s) {
              final isSelected = _selectedScope == s['key'];
              final color = s['color'] as Color;

              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _changeScope(s['key'] as String, state),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withValues(alpha: 0.09) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? color : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s['label'] as String,
                          style: TextStyle(
                            color: isSelected ? color : const Color(0xFF475569),
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                        if (!isNarrow) ...[
                          const SizedBox(height: 2),
                          Text(
                            s['sublabel'] as String,
                            style: TextStyle(
                              color: isSelected ? color.withValues(alpha: 0.8) : const Color(0xFF94A3B8),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  void _changeScope(String newScope, CurriculumAnalyticsState state) {
    if (_selectedScope == newScope) return;
    setState(() {
      _selectedScope = newScope;
      _selectedStageFilter = 'all';
    });
    ref.read(curriculumAnalyticsProvider.notifier).fetchAnalytics(
      scope: newScope,
      academicYear: state.selectedAcademicYear,
    );
  }

  String _scopeDisplayName(String scope) {
    switch (scope.toLowerCase()) {
      case 'capstone':
        return '4th Year Capstone';
      case 'pit':
        return '1st–3rd Year PIT';
      default:
        return 'Unified (All Tracks)';
    }
  }

  // ---------------------------------------------------------------------------
  // SUMMARY METRICS (REAL DATA & SIMPLE LANGUAGE)
  // ---------------------------------------------------------------------------

  Widget _buildSummaryMetrics(CurriculumAnalyticsState state) {
    final kpis = _map(state.data['kpi_summary']);
    final competencies = _mapList(state.data['competency_matrix']);
    final funnel = _map(state.data['defense_funnel']);
    final bottleneckStage = funnel['bottleneck_stage']?.toString() ?? 'None Identified';
    final bottleneckReason = funnel['bottleneck_reason']?.toString() ?? 'All stages progressing normally.';

    final scoredComps = competencies.where((c) => c['average_score'] != null).toList();
    final avgCompetency = _asDouble(kpis['average_competency']);
    final hasGrades = scoredComps.isNotEmpty && avgCompetency > 0;

    // Lowest scoring real criterion from user input
    Map<String, dynamic>? lowestCriterion;
    if (scoredComps.isNotEmpty) {
      final sorted = List<Map<String, dynamic>>.from(scoredComps);
      sorted.sort((a, b) => _asDouble(a['average_score']).compareTo(_asDouble(b['average_score'])));
      lowestCriterion = sorted.first;
    }

    final totalEvals = _asInt(kpis['total_evaluations_count']);
    final totalFiles = _asInt(state.data['entries_count']);
    final rawPassRate = kpis['first_time_pass_rate'];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 950;
        final cardWidth = isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            // Card 1: Average Student Grade
            SizedBox(
              width: cardWidth,
              child: _summaryCard(
                icon: Icons.school_rounded,
                accentColor: hasGrades
                    ? (avgCompetency >= 75.0 ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                    : const Color(0xFF94A3B8),
                title: 'AVERAGE GRADE',
                value: hasGrades ? '$avgCompetency%' : 'No Grades Yet',
                subtitle: hasGrades
                    ? (avgCompetency >= 75.0 ? 'Passing benchmark met (≥75%)' : 'Below 75% target benchmark')
                    : 'Awaiting defense evaluations',
              ),
            ),
            // Card 2: Teams / Evaluations Recorded
            SizedBox(
              width: cardWidth,
              child: _summaryCard(
                icon: Icons.groups_rounded,
                accentColor: const Color(0xFF0EA5E9),
                title: 'EVALUATIONS RECORDED',
                value: totalEvals > 0 ? '$totalEvals Evals' : '0 Evals',
                subtitle: totalFiles > 0 ? '$totalFiles deliverable files uploaded' : 'No deliverables uploaded yet',
              ),
            ),
            // Card 3: Defense Pass Rate
            SizedBox(
              width: cardWidth,
              child: _summaryCard(
                icon: Icons.verified_rounded,
                accentColor: rawPassRate != null ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                title: 'DEFENSE PASS RATE',
                value: rawPassRate != null ? '$rawPassRate%' : 'Pending',
                subtitle: rawPassRate != null ? 'Passed without re-defense' : 'No defense hearings held yet',
              ),
            ),
            // Card 4: Focus Area
            SizedBox(
              width: cardWidth,
              child: _summaryCard(
                icon: Icons.lightbulb_outline_rounded,
                accentColor: (lowestCriterion != null && _asDouble(lowestCriterion['average_score']) < 75.0)
                    ? const Color(0xFFEF4444)
                    : ((bottleneckStage != 'None Identified' && bottleneckStage != 'None')
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF10B981)),
                title: 'FOCUS AREA',
                value: (lowestCriterion != null && _asDouble(lowestCriterion['average_score']) < 75.0)
                    ? '${lowestCriterion['name']}'
                    : ((bottleneckStage != 'None Identified' && bottleneckStage != 'None')
                        ? bottleneckStage
                        : (hasGrades ? 'All Criteria Passing' : 'None Identified')),
                subtitle: (lowestCriterion != null && _asDouble(lowestCriterion['average_score']) < 75.0)
                    ? 'Lowest scoring criterion (${lowestCriterion['average_score']}%)'
                    : ((bottleneckStage != 'None Identified' && bottleneckStage != 'None')
                        ? bottleneckReason
                        : (hasGrades ? 'All evaluated criteria exceed 75%' : 'Awaiting defense outcomes')),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required Color accentColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.maroon.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.maroon, size: 18),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: STUDENT SCORES & SKILLS (CLEAN & CONSOLIDATED)
  // ---------------------------------------------------------------------------

  Widget _buildStudentScoresTab(CurriculumAnalyticsState state) {
    final availableRubrics = _mapList(state.data['available_rubrics']);
    final availableStages = _mapList(state.data['available_stages']);
    final stageOverview = _mapList(state.data['stage_performance_overview']);
    final allCompetencies = _mapList(state.data['competency_matrix']);
    final selectedRubricId = state.selectedRubricId;

    final isOverall = _selectedStageFilter == 'all';

    // Find active stage name for title if specific stage is selected
    String activeStageName = 'Overall (All Stages)';
    if (!isOverall) {
      final matchedStage = availableStages.firstWhere(
        (s) => s['id']?.toString() == _selectedStageFilter || (s['label']?.toString().toLowerCase() == _selectedStageFilter.toLowerCase()),
        orElse: () => stageOverview.firstWhere(
          (s) => s['stage_id']?.toString() == _selectedStageFilter || (s['stage_name']?.toString().toLowerCase() == _selectedStageFilter.toLowerCase()),
          orElse: () => {'label': _selectedStageFilter, 'stage_name': _selectedStageFilter},
        ),
      );
      activeStageName = matchedStage['stage_name']?.toString() ?? (matchedStage['label']?.toString() ?? _selectedStageFilter);
    }

    // Filter competencies for specific stage
    final filteredCompetencies = isOverall
        ? allCompetencies
        : allCompetencies.where((c) {
            final cStageId = c['stage_id']?.toString() ?? '';
            final cStageName = c['stage_name']?.toString() ?? (c['stage_label']?.toString() ?? '');
            return cStageId == _selectedStageFilter ||
                cStageName.toLowerCase() == _selectedStageFilter.toLowerCase() ||
                cStageName.toLowerCase().contains(_selectedStageFilter.toLowerCase());
          }).toList();

    // Filter rubrics for dropdown if specific stage is selected
    final filteredRubrics = isOverall
        ? availableRubrics
        : availableRubrics.where((r) {
            final rStage = r['stage']?.toString() ?? '';
            final rStageId = r['defense_stage_id']?.toString() ?? '';
            return rStageId == _selectedStageFilter ||
                rStage.toLowerCase() == _selectedStageFilter.toLowerCase() ||
                rStage.toLowerCase().contains(_selectedStageFilter.toLowerCase());
          }).toList();

    final macroStagesList = stageOverview.isNotEmpty
        ? stageOverview
        : availableStages.map((s) => {
            'stage_id': s['id']?.toString() ?? '',
            'stage_name': s['label']?.toString() ?? 'Stage',
            'code': s['code']?.toString() ?? '',
            'total_teams': 0,
            'average_score': null,
            'pass_rate': 0,
            'rubrics_count': 0,
            'criteria_count': 0,
          }).toList();

    return _contentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. TOP DEFENSE STAGE PILL SWITCHER
          _buildStagePillSwitcher(availableStages.isNotEmpty ? availableStages : stageOverview),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 16),

          // 2. RESPONSIVE CONTROLS HEADER
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 920;

              final controls = [
                _scoresViewToggle(),
                if (_scoresViewMode == 0) ...[
                  _groupingSelectorDropdown(),
                ],
                if (!isOverall && filteredRubrics.isNotEmpty) ...[
                  _rubricSelectorDropdown(filteredRubrics, selectedRubricId),
                ] else if (isOverall) ...[
                  _rubricSelectorDropdown(availableRubrics, selectedRubricId),
                ],
              ];

              final titleText = isOverall
                  ? 'Stage-by-Stage Performance Overview'
                  : '$activeStageName: Rubric Criteria';

              final subtitleText = isOverall
                  ? 'Comparing defense stage outcomes side-by-side against the 75% target benchmark'
                  : 'Live student performance on specific rubric criteria evaluated in this defense stage';

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isOverall ? Icons.public_rounded : Icons.rule_folder_rounded,
                        color: const Color(0xFF10B981),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titleText,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitleText,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: controls,
                    ),
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isOverall ? Icons.public_rounded : Icons.rule_folder_rounded,
                            color: const Color(0xFF10B981),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titleText,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitleText,
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: controls,
                    ),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 18),

          // 3. MAIN VISUALIZATION CONTENT (CHART OR CARDS)
          if (isOverall) ...[
            if (_scoresViewMode == 0) ...[
              _DefensysClusteredBarChart(
                competencies: macroStagesList,
                groupingMode: _clusterGrouping,
                isStageMacroMode: true,
                stageTitle: 'Overall Defense Stages',
              ),
            ] else ...[
              ...macroStagesList.map(_stageMacroCard),
            ],
          ] else ...[
            if (filteredCompetencies.isEmpty)
              Container(
                padding: const EdgeInsets.all(28),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    const Icon(Icons.assignment_late_outlined, size: 42, color: Color(0xFF94A3B8)),
                    const SizedBox(height: 12),
                    Text(
                      'No criteria found specifically for $activeStageName.',
                      style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Create rubrics aligned to this defense stage in Rubrics Setup to track stage-specific criteria.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ],
                ),
              )
            else if (_scoresViewMode == 0) ...[
              _DefensysClusteredBarChart(
                competencies: filteredCompetencies,
                groupingMode: _clusterGrouping,
                isStageMacroMode: false,
                stageTitle: activeStageName,
              ),
            ] else ...[
              ...filteredCompetencies.map(_dynamicCriterionCard),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStagePillSwitcher(List<Map<String, dynamic>> stages) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _stagePillItem(
              id: 'all',
              label: '🌐 Overall (All Stages)',
              isSelected: _selectedStageFilter == 'all',
              accentColor: AppColors.maroon,
            ),
            const SizedBox(width: 4),
            ...stages.map((stg) {
              final stageId = stg['id']?.toString() ?? (stg['stage_id']?.toString() ?? '');
              final stageName = stg['stage_name']?.toString() ?? (stg['label']?.toString() ?? 'Stage');
              final code = stg['code']?.toString() ?? '';

              String iconPrefix = '📝 ';
              Color color = const Color(0xFF0EA5E9);
              if (stageName.toLowerCase().contains('concept') || code.toUpperCase() == 'CP') {
                iconPrefix = '📝 ';
                color = const Color(0xFFF59E0B);
              } else if (stageName.toLowerCase().contains('colloquium') || code.toUpperCase() == 'COL') {
                iconPrefix = '💻 ';
                color = const Color(0xFF0EA5E9);
              } else if (stageName.toLowerCase().contains('final') || stageName.toLowerCase().contains('presentation') || code.toUpperCase() == 'PP') {
                iconPrefix = '🎓 ';
                color = const Color(0xFF10B981);
              }

              final isSelected = _selectedStageFilter == stageId ||
                  _selectedStageFilter == stageName ||
                  _selectedStageFilter.toLowerCase() == stageName.toLowerCase();

              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _stagePillItem(
                  id: stageId.isNotEmpty ? stageId : stageName,
                  label: '$iconPrefix$stageName',
                  isSelected: isSelected,
                  accentColor: color,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _stagePillItem({
    required String id,
    required String label,
    required bool isSelected,
    required Color accentColor,
  }) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedStageFilter = id;
        });
      },
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
          border: isSelected ? Border.all(color: accentColor.withValues(alpha: 0.35)) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? accentColor : const Color(0xFF64748B),
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _stageMacroCard(Map<String, dynamic> stage) {
    final name = stage['stage_name']?.toString() ?? (stage['label']?.toString() ?? 'Stage');
    final total = _asInt(stage['total_teams']);
    final avgScore = stage['average_score'] != null ? _asDouble(stage['average_score']) : null;
    final passRate = _asInt(stage['pass_rate']);
    final rubricsCount = _asInt(stage['rubrics_count']);
    final criteriaCount = _asInt(stage['criteria_count']);
    final evalBreakdown = stage['evaluator_breakdown'] is Map
        ? Map<String, dynamic>.from(stage['evaluator_breakdown'] as Map)
        : <String, dynamic>{};
    final panelScore = evalBreakdown['panel']?['score'] != null ? _asDouble(evalBreakdown['panel']['score']) : null;
    final adviserScore = evalBreakdown['adviser']?['score'] != null ? _asDouble(evalBreakdown['adviser']['score']) : null;

    final hasScore = avgScore != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$total Teams Evaluated  ·  $rubricsCount Rubrics Configured  ·  $criteriaCount Criteria',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _selectedStageFilter = stage['stage_id']?.toString() ?? name;
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.maroon.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.maroon.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in_rounded, size: 14, color: AppColors.maroon),
                        SizedBox(width: 4),
                        Text(
                          'Drill Down Criteria',
                          style: TextStyle(color: AppColors.maroon, fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  hasScore ? '${avgScore.toStringAsFixed(1)}%' : '--',
                  style: TextStyle(
                    color: hasScore ? (avgScore >= 75.0 ? const Color(0xFF10B981) : const Color(0xFFEF4444)) : const Color(0xFF94A3B8),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (hasScore) ...[
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _stageMetricTag('Panelist Avg', panelScore != null ? '${panelScore.toStringAsFixed(1)}%' : '--', const Color(0xFF0EA5E9)),
                  _stageMetricTag('Adviser Avg', adviserScore != null ? '${adviserScore.toStringAsFixed(1)}%' : '--', const Color(0xFF10B981)),
                  _stageMetricTag('Pass Rate', '$passRate%', const Color(0xFF6366F1)),
                ],
              ),
            ] else ...[
              const Text(
                'No defense evaluations recorded for this stage yet in the selected academic year.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stageMetricTag(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5, fontWeight: FontWeight.w500),
        ),
        Text(
          value,
          style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _scoresViewToggle() {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleOption(
            index: 0,
            icon: Icons.bar_chart_rounded,
            label: 'Clustered Chart',
            isSelected: _scoresViewMode == 0,
            onTap: () => setState(() => _scoresViewMode = 0),
          ),
          _toggleOption(
            index: 1,
            icon: Icons.view_list_rounded,
            label: 'Detailed Cards',
            isSelected: _scoresViewMode == 1,
            onTap: () => setState(() => _scoresViewMode = 1),
          ),
        ],
      ),
    );
  }

  Widget _toggleOption({
    required int index,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? AppColors.maroon : const Color(0xFF64748B),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.maroon : const Color(0xFF64748B),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupingSelectorDropdown() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _clusterGrouping,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textPrimary),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          items: const [
            DropdownMenuItem(
              value: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline_rounded, size: 14, color: Color(0xFF0EA5E9)),
                  SizedBox(width: 6),
                  Text('Cluster: Evaluator Role'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers_outlined, size: 14, color: Color(0xFFF59E0B)),
                  SizedBox(width: 6),
                  Text('Cluster: Defense Stage'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.show_chart_rounded, size: 14, color: Color(0xFF10B981)),
                  SizedBox(width: 6),
                  Text('Cluster: Score Spread'),
                ],
              ),
            ),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _clusterGrouping = val);
          },
        ),
      ),
    );
  }

  Widget _rubricSelectorDropdown(List<Map<String, dynamic>> rubrics, String selectedId) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedId.isEmpty ? 'all' : selectedId,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textPrimary),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          items: [
            const DropdownMenuItem(
              value: 'all',
              child: Text('All Rubrics (Combined)'),
            ),
            ...rubrics.map((r) => DropdownMenuItem(
                  value: r['id']?.toString() ?? '',
                  child: Text(
                    '${r['name']} (${r['stage'] ?? "General"})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
          ],
          onChanged: (value) {
            if (value != null) {
              ref.read(curriculumAnalyticsProvider.notifier).fetchAnalytics(rubricId: value);
            }
          },
        ),
      ),
    );
  }

  Widget _dynamicCriterionCard(Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? 'Criterion';
    final rubricName = item['rubric_name']?.toString() ?? 'Rubric';
    final weight = item['weight'] != null ? '${item['weight']}%' : null;
    final alignedCourse = item['aligned_course']?.toString() ?? 'Major Subject';
    final evalCount = _asInt(item['evaluations_count']);
    final avgScore = item['average_score'] != null ? _asDouble(item['average_score']) : null;
    final status = item['status']?.toString() ?? 'No Grades Yet';
    final color = _color(item['color']);

    final hasScores = avgScore != null && evalCount > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (weight != null) ...[
                            const SizedBox(width: 8),
                            _Badge(
                              label: 'Weight: $weight',
                              bgColor: const Color(0xFFEEF2FF),
                              textColor: const Color(0xFF4F46E5),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Course Link: $alignedCourse  ·  $rubricName',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                _Badge(
                  label: status.toUpperCase(),
                  bgColor: hasScores
                      ? (avgScore >= 75.0 ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2))
                      : const Color(0xFFF1F5F9),
                  textColor: hasScores
                      ? (avgScore >= 75.0 ? const Color(0xFF059669) : const Color(0xFFDC2626))
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 14),
                Text(
                  hasScores ? '$avgScore%' : '--',
                  style: TextStyle(
                    color: hasScores ? color : const Color(0xFF94A3B8),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (hasScores) ...[
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: (avgScore / 100).clamp(0.0, 1.0),
                      minHeight: 8,
                      color: color,
                      backgroundColor: const Color(0xFFE2E8F0),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    child: LayoutBuilder(
                      builder: (context, box) {
                        return Container(
                          margin: EdgeInsets.only(left: box.maxWidth * 0.75 - 1),
                          width: 2,
                          height: 8,
                          color: const Color(0xFF0F172A).withValues(alpha: 0.6),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$evalCount evaluations recorded',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                  Text(
                    avgScore >= 75.0 ? '+${(avgScore - 75.0).toStringAsFixed(1)}% above 75% target' : '${(avgScore - 75.0).toStringAsFixed(1)}% below target',
                    style: TextStyle(
                      color: avgScore >= 75.0 ? const Color(0xFF059669) : const Color(0xFFDC2626),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ] else ...[
              const Text(
                'No grades submitted for this criterion yet in the selected academic year.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: PROJECT TOPICS & TECH
  // ---------------------------------------------------------------------------

  Widget _buildProjectTopicsTab(CurriculumAnalyticsState state) {
    final domains = _mapList(state.data['domain_distribution']);
    final distribution = _mapList(state.data['distribution']);
    final totalProjects = _asInt(state.data['entries_count']);

    final slices = domains.map((d) {
      return _ChartSlice(
        label: d['domain']?.toString() ?? 'General',
        count: _asInt(d['count']),
        percentage: _asInt(d['percentage']),
        color: _color(d['color']),
      );
    }).toList();

    return Column(
      children: [
        _contentCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.pie_chart_rounded, color: Color(0xFF6366F1), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What topics are students working on?',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Distribution of student capstone & research project themes',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 18),
              if (domains.isEmpty)
                const Text('No project deliverables recorded in the repository.')
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 700;

                    if (isWide) {
                      return Row(
                        children: [
                          SizedBox(
                            width: 260,
                            height: 220,
                            child: _DefensysDonutChart(
                              slices: slices,
                              centerTitle: '$totalProjects',
                              centerSubtitle: 'Projects',
                            ),
                          ),
                          const SizedBox(width: 30),
                          Expanded(
                            child: Column(
                              children: domains.map(_domainRow).toList(),
                            ),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          SizedBox(
                            height: 200,
                            child: _DefensysDonutChart(
                              slices: slices,
                              centerTitle: '$totalProjects',
                              centerSubtitle: 'Projects',
                            ),
                          ),
                          const SizedBox(height: 16),
                          ...domains.map(_domainRow),
                        ],
                      );
                    }
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _contentCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.code_rounded, color: Color(0xFF0EA5E9), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Programming Languages & Frameworks Used',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Technologies detected from student code and document submissions',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 16),
              if (distribution.isEmpty)
                const Text('No technology framework data recorded.')
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: distribution.map((item) {
                    final tech = item['tech']?.toString() ?? 'General';
                    final pct = _asInt(item['percentage']);
                    final count = _asInt(item['count']);
                    final color = _color(item['color']);

                    return Container(
                      width: 220,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tech,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w800),
                                ),
                              ),
                              Text('$pct%', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: pct / 100,
                              minHeight: 5,
                              color: color,
                              backgroundColor: const Color(0xFFE2E8F0),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('$count deliverable files', style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _domainRow(Map<String, dynamic> dom) {
    final domain = dom['domain']?.toString() ?? 'General Domain';
    final count = _asInt(dom['count']);
    final pct = _asInt(dom['percentage']);
    final color = _color(dom['color']);
    final topStacks = dom['top_stacks']?.toString() ?? 'General';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w800),
                ),
                Text(
                  '$count projects · Stacks: $topStacks',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 7,
                color: color,
                backgroundColor: const Color(0xFFF1F5F9),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 42,
            child: Text(
              '$pct%',
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: DEFENSE RESULTS & PRACTICAL TIPS
  // ---------------------------------------------------------------------------

  Widget _buildDefenseResultsAndTipsTab(CurriculumAnalyticsState state) {
    final funnel = _map(state.data['defense_funnel']);
    final stages = _mapList(funnel['stages']);
    final verdictsPie = _mapList(funnel['verdicts_distribution']);
    final totalEvaluated = _asInt(funnel['total_evaluated']);

    final slices = verdictsPie.map((v) {
      return _ChartSlice(
        label: v['label']?.toString() ?? 'Verdict',
        count: _asInt(v['count']),
        percentage: _asInt(v['percentage']),
        color: _color(v['color']),
      );
    }).toList();

    return Column(
      children: [
        _contentCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.pie_chart_rounded, color: Color(0xFF10B981), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Overall Defense Pass Rates',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 16.5, fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Proportion of student teams passing on their first try vs requiring revisions',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 700;

                  if (isWide) {
                    return Row(
                      children: [
                        SizedBox(
                          width: 260,
                          height: 220,
                          child: _DefensysDonutChart(
                            slices: slices,
                            centerTitle: '$totalEvaluated',
                            centerSubtitle: 'Teams Graded',
                          ),
                        ),
                        const SizedBox(width: 30),
                        Expanded(
                          child: Column(
                            children: verdictsPie.map((v) {
                              final label = v['label']?.toString() ?? '';
                              final count = _asInt(v['count']);
                              final pct = _asInt(v['percentage']);
                              final color = _color(v['color']);

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    Text(
                                      '$count teams ($pct%)',
                                      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        SizedBox(
                          height: 200,
                          child: _DefensysDonutChart(
                            slices: slices,
                            centerTitle: '$totalEvaluated',
                            centerSubtitle: 'Teams Graded',
                          ),
                        ),
                      ],
                    );
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _contentCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Results by Defense Stage',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'First-time pass rates and revision workloads across active defense stages',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              if (stages.isEmpty)
                const Text('No defense stages configured.')
              else
                ...stages.map(_stageFunnelRow),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _contentCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.alt_route_rounded, color: Color(0xFFF59E0B), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pipeline Bottleneck & Throughput Diagnosis',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          funnel['bottleneck_stage'] != null && funnel['bottleneck_stage'] != 'None Identified' && funnel['bottleneck_stage'] != 'None'
                              ? 'Identified Critical Bottleneck: ${funnel["bottleneck_stage"]} · ${funnel["bottleneck_reason"]}'
                              : 'All defense milestones maintain smooth throughput without excessive redefense friction.',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stageFunnelRow(Map<String, dynamic> stage) {
    final name = stage['stage_name']?.toString() ?? 'Stage';
    final total = _asInt(stage['total_teams']);
    final appCount = _asInt(stage['approved_count']);
    final revCount = _asInt(stage['revisions_count']);
    final redefCount = _asInt(stage['redefense_count']);
    final firstPass = _asInt(stage['first_pass_rate']);
    final revision = _asInt(stage['revision_rate']);
    final redefense = _asInt(stage['redefense_rate']);
    final friction = (redefense * 2) + revision;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '$total Teams Graded',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (total > 0) ...[
              Row(
                children: [
                  if (firstPass > 0)
                    Expanded(
                      flex: firstPass,
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.horizontal(
                            left: const Radius.circular(4),
                            right: (revision == 0 && redefense == 0) ? const Radius.circular(4) : Radius.zero,
                          ),
                        ),
                      ),
                    ),
                  if (revision > 0)
                    Expanded(
                      flex: revision,
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.horizontal(
                            left: (firstPass == 0) ? const Radius.circular(4) : Radius.zero,
                            right: (redefense == 0) ? const Radius.circular(4) : Radius.zero,
                          ),
                        ),
                      ),
                    ),
                  if (redefense > 0)
                    Expanded(
                      flex: redefense,
                      child: Container(
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _legendItem('Passed', '$appCount ($firstPass%)', const Color(0xFF10B981)),
                  _legendItem('Revisions', '$revCount ($revision%)', const Color(0xFFF59E0B)),
                  _legendItem('Re-Defense', '$redefCount ($redefense%)', const Color(0xFFEF4444)),
                  _legendItem('Friction Index', '$friction pts', friction >= 40 ? const Color(0xFFEF4444) : const Color(0xFF64748B)),
                ],
              ),
            ] else ...[
              const Text(
                'No defense hearings recorded for this stage yet in the selected academic year.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legendItem(String label, String val, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
        Text(val, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: EVALUATOR CALIBRATION & INTEGRITY
  // ---------------------------------------------------------------------------

  Widget _buildEvaluatorCalibrationTab(CurriculumAnalyticsState state) {
    final calibration = _map(state.data['evaluator_calibration']);
    final competencies = _mapList(state.data['competency_matrix']);
    final meanDiv = _asDouble(calibration['mean_divergence']);
    final calibStatus = calibration['calibration_status']?.toString() ?? 'Well Calibrated';
    final calibColor = _color(calibration['calibration_color']);
    final totalEvaluated = _asInt(calibration['total_evaluated_teams']);
    final adviserHigher = _asInt(calibration['adviser_higher_count']);
    final panelHigher = _asInt(calibration['panel_higher_count']);
    final equalCount = _asInt(calibration['equal_count']);
    final leniencyPct = _asInt(calibration['adviser_leniency_rate']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _contentCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: calibColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.balance_rounded, color: calibColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Evaluator Scoring Calibration & Integrity',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 16.5, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          calibration['diagnosis']?.toString() ??
                              'Cross-evaluates grading consistency between External Defense Panelists, Project Advisers, and Peers.',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: calibColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: calibColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      calibStatus.toUpperCase(),
                      style: TextStyle(color: calibColor, fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 850;
                  final w = isWide ? (constraints.maxWidth - 54) / 4 : (constraints.maxWidth - 18) / 2;

                  return Wrap(
                    spacing: 18,
                    runSpacing: 18,
                    children: [
                      SizedBox(
                        width: w,
                        child: _miniMetricCard(
                          label: 'MEAN DIVERGENCE DELTA',
                          value: '±${meanDiv.toStringAsFixed(1)}%',
                          sublabel: 'Avg |Panel - Adviser| variance',
                          color: calibColor,
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _miniMetricCard(
                          label: 'ADVISER LENIENCY RATE',
                          value: '$leniencyPct%',
                          sublabel: '$adviserHigher of $totalEvaluated criteria scored higher',
                          color: leniencyPct > 60 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _miniMetricCard(
                          label: 'PANEL HIGHER CRITERIA',
                          value: '$panelHigher criteria',
                          sublabel: 'Panelists graded more strictly',
                          color: const Color(0xFF0EA5E9),
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _miniMetricCard(
                          label: 'CONSISTENT CRITERIA',
                          value: '$equalCount criteria',
                          sublabel: 'Identical scores within ±1.0%',
                          color: const Color(0xFF6366F1),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _contentCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.rule_folder_rounded, color: AppColors.maroon, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Criterion Scoring Breakdown by Evaluator Role',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 15.5, fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Identifies specific rubric dimensions where adviser leniency or panel rigor causes high discrepancy',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 16),
              if (competencies.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  alignment: Alignment.center,
                  child: const Text('No graded criteria available for calibration analysis.',
                    style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                  ),
                )
              else
                ...competencies.map((c) => _calibrationCriterionRow(c)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _calibrationCriterionRow(Map<String, dynamic> c) {
    final name = c['name']?.toString() ?? 'Criterion';
    final course = c['aligned_course']?.toString() ?? 'Core Course';
    final stageName = c['stage_name']?.toString() ?? (c['stage_label']?.toString() ?? 'Stage');
    final brk = _map(c['evaluator_breakdown']);
    final panelScore = _asDouble(brk['panel']?['score']);
    final adviserScore = _asDouble(brk['adviser']?['score']);
    final peerScore = _asDouble(brk['peer']?['score']);
    final divergence = (panelScore > 0 && adviserScore > 0)
        ? (panelScore - adviserScore).abs()
        : 0.0;

    Color divColor = const Color(0xFF10B981);
    String divStatus = 'ALIGNED';
    if (divergence >= 15.0) {
      divColor = const Color(0xFFEF4444);
      divStatus = 'HIGH DISCREPANCY';
    } else if (divergence >= 8.0) {
      divColor = const Color(0xFFF59E0B);
      divStatus = 'MODERATE GAP';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: divergence >= 15.0 ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFC7D2FE)),
                            ),
                            child: Text(
                              course,
                              style: const TextStyle(color: Color(0xFF4338CA), fontSize: 10.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Stage: $stageName',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: divColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: divColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Δ ${divergence.toStringAsFixed(1)}% · $divStatus',
                    style: TextStyle(color: divColor, fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _roleScorePill(
                    role: 'External Panelist',
                    score: panelScore > 0 ? '${panelScore.toStringAsFixed(1)}%' : 'N/A',
                    color: const Color(0xFF0EA5E9),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _roleScorePill(
                    role: 'Project Adviser',
                    score: adviserScore > 0 ? '${adviserScore.toStringAsFixed(1)}%' : 'N/A',
                    color: const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _roleScorePill(
                    role: 'Peer Evaluation',
                    score: peerScore > 0 ? '${peerScore.toStringAsFixed(1)}%' : 'N/A',
                    color: const Color(0xFF8B5CF6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleScorePill({required String role, required String score, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(role, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w600)),
          Text(score, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _miniMetricCard({
    required String label,
    required String value,
    required String sublabel,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            sublabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: ACTION DIRECTIVES & PRESCRIPTIONS (KNOWLEDGE-BASED SUBSYSTEM)
  // ---------------------------------------------------------------------------

  Widget _buildPrescriptiveActionsTab(CurriculumAnalyticsState state) {
    final prescriptions = _mapList(state.data['prescriptions']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _contentCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.maroon.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: AppColors.maroon, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Knowledge-Based Subsystem (KBS) · Decision Directives',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 16.5, fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Heuristic rules engine translates empirical defense evaluations and prerequisite data into prioritized administrative actions.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 16),
              if (prescriptions.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  alignment: Alignment.center,
                  child: const Text(
                    'No active administrative prescriptions for the selected scope.',
                    style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                  ),
                )
              else
                ...prescriptions.map((p) => _prescriptiveActionCard(p)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _prescriptiveActionCard(Map<String, dynamic> item) {
    final typeLabel = item['type_label']?.toString() ?? 'Action';
    final severity = item['severity']?.toString() ?? 'medium';
    final track = item['track']?.toString() ?? 'operations';
    final title = item['title']?.toString() ?? 'Prescription';
    final diagnosis = item['diagnosis']?.toString() ?? '';
    final body = item['body']?.toString() ?? '';
    final actionLabel = item['action_label']?.toString() ?? 'Execute Directive';
    final target = item['target']?.toString() ?? 'Curriculum';

    Color tagColor = const Color(0xFF6366F1);
    Color tagBg = const Color(0xFFEEF2FF);
    if (severity == 'high') {
      tagColor = const Color(0xFFDC2626);
      tagBg = const Color(0xFFFEF2F2);
    } else if (severity == 'medium') {
      tagColor = const Color(0xFFD97706);
      tagBg = const Color(0xFFFFFBEB);
    }

    String trackBadge = track.toUpperCase();
    if (track == 'capstone') trackBadge = '🎯 CAPSTONE';
    if (track == 'pit') trackBadge = '🔬 PIT TRACK';
    if (track == 'calibration') trackBadge = '⚖️ CALIBRATION';
    if (track == 'curriculum') trackBadge = '📚 CURRICULUM';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Badge(label: typeLabel.toUpperCase(), bgColor: tagBg, textColor: tagColor),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    trackBadge,
                    style: const TextStyle(color: Color(0xFF475569), fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ),
                const Spacer(),
                Text(
                  'PRIORITY: ${severity.toUpperCase()}',
                  style: TextStyle(color: tagColor, fontSize: 10.5, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
            if (diagnosis.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFD97706)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Root Cause Diagnosis: $diagnosis',
                        style: const TextStyle(color: Color(0xFF92400E), fontSize: 12, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(color: Color(0xFF334155), fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    'Target: $target',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        title: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: tagColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.lightbulb_outline_rounded, color: tagColor, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (diagnosis.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: tagColor.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  diagnosis,
                                  style: TextStyle(color: tagColor, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            Text(
                              body,
                              style: const TextStyle(color: Color(0xFF334155), fontSize: 13, height: 1.4),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Target: $target',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Close', style: TextStyle(color: AppColors.maroon, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.maroon.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.maroon.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          actionLabel,
                          style: const TextStyle(color: AppColors.maroon, fontSize: 11.5, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.maroon),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY FOOTER
  // ---------------------------------------------------------------------------

  Widget _buildSummaryFooter(CurriculumAnalyticsState state) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.maroon,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.summarize_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Department Review & Faculty Meeting Summary',
                  style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 4),
                Text(
                  'All analytics are compiled directly from evaluated rubrics and project deliverables. Export a clean PDF copy for your meeting.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _primaryButton(
            icon: Icons.download_rounded,
            label: 'Download PDF Report',
            onTap: _downloadPdfReport,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ACTION HANDLERS & MODAL
  // ---------------------------------------------------------------------------

  Future<void> _downloadPdfReport() async {
    await ref.read(curriculumAnalyticsProvider.notifier).downloadProposalPdf(scope: _selectedScope);
  }

  Future<void> _generateProposalModal() async {
    await ref.read(curriculumAnalyticsProvider.notifier).generateProposal(scope: _selectedScope);
    if (!mounted) return;


    final proposal = ref.read(curriculumAnalyticsProvider).proposal;
    if (proposal == null) return;

    showDialog(
      context: context,
      builder: (context) {
        final title = proposal['title']?.toString() ?? 'Curriculum Proposal';
        final summary = proposal['summary']?.toString() ?? '';
        final recommendations = _mapList(proposal['recommendations']);
        final nextSteps = _stringList(proposal['next_steps']);

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.maroon.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: AppColors.maroon, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: AppColors.maroon, fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      summary,
                      style: const TextStyle(color: Color(0xFF334155), fontSize: 13, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Key Recommendations',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ...recommendations.map((rec) {
                    final t = rec['title']?.toString() ?? '';
                    final b = rec['body']?.toString() ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF10B981)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '$t: ',
                                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 12.5),
                                  ),
                                  TextSpan(
                                    text: b,
                                    style: const TextStyle(color: Color(0xFF475569), fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 14),
                  const Text(
                    'Next Action Steps',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ...nextSteps.map((step) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.arrow_right_rounded, size: 18, color: AppColors.maroon),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                step,
                                style: const TextStyle(color: Color(0xFF334155), fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.maroon,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
              label: const Text('Download Official PDF'),
              onPressed: () {
                Navigator.of(context).pop();
                _downloadPdfReport();
              },
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS & ATOMS
  // ---------------------------------------------------------------------------

  Widget _contentCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: onTap == null ? const Color(0xFF94A3B8) : AppColors.maroon,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: AppColors.maroon.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD1D5DB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.maroon, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notice(IconData icon, String message, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is List) {
      return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return {};
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value != null) {
      return int.tryParse(value.toString()) ?? 0;
    }
    return 0;
  }

  double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value != null) {
      return double.tryParse(value.toString()) ?? 0.0;
    }
    return 0.0;
  }

  Color _color(dynamic hexString) {
    if (hexString == null) return const Color(0xFF6366F1);
    final clean = hexString.toString().replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return const Color(0xFF6366F1);
  }
}

// -----------------------------------------------------------------------------
// CUSTOM DONUT & PIE CHART WIDGET
// -----------------------------------------------------------------------------

class _ChartSlice {
  final String label;
  final int count;
  final int percentage;
  final Color color;

  const _ChartSlice({
    required this.label,
    required this.count,
    required this.percentage,
    required this.color,
  });
}

class _DefensysDonutChart extends StatelessWidget {
  final List<_ChartSlice> slices;
  final String centerTitle;
  final String centerSubtitle;

  const _DefensysDonutChart({
    required this.slices,
    required this.centerTitle,
    required this.centerSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    final validSlices = slices.where((s) => s.count > 0 || s.percentage > 0).toList();

    return Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: const Size(220, 220),
          painter: _DonutChartPainter(slices: validSlices),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              centerTitle,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              centerSubtitle,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final List<_ChartSlice> slices;

  _DonutChartPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const strokeWidth = 22.0;

    if (slices.isEmpty) {
      final bgPaint = Paint()
        ..color = const Color(0xFFE2E8F0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(center, radius - strokeWidth / 2, bgPaint);
      return;
    }

    final total = slices.fold<int>(0, (sum, s) => sum + (s.percentage > 0 ? s.percentage : s.count));
    if (total == 0) return;

    double startAngle = -math.pi / 2;

    for (final slice in slices) {
      final value = slice.percentage > 0 ? slice.percentage : slice.count;
      final sweepAngle = (value / total) * 2 * math.pi;

      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweepAngle - 0.04,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.slices != slices;
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color textColor;

  const _Badge({
    required this.label,
    required this.bgColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// CLUSTERED (GROUPED) BAR CHART WIDGET & PAINTER
// -----------------------------------------------------------------------------

class _BarSeriesItem {
  final String label;
  final double? score;
  final int count;
  final Color color;

  const _BarSeriesItem({
    required this.label,
    required this.score,
    required this.count,
    required this.color,
  });
}

class _CriterionClusterData {
  final String id;
  final String name;
  final String alignedCourse;
  final String rubricName;
  final double? averageScore;
  final int evaluationsCount;
  final List<_BarSeriesItem> series;

  const _CriterionClusterData({
    required this.id,
    required this.name,
    required this.alignedCourse,
    required this.rubricName,
    required this.averageScore,
    required this.evaluationsCount,
    required this.series,
  });
}

class _ChartDataPoint {
  final String category;
  final double? value;
  final int count;
  final String seriesName;
  final Color color;
  final _CriterionClusterData cluster;
  final int clusterIndex;

  _ChartDataPoint({
    required this.category,
    required this.value,
    required this.count,
    required this.seriesName,
    required this.color,
    required this.cluster,
    required this.clusterIndex,
  });
}

class _DefensysClusteredBarChart extends StatefulWidget {
  final List<Map<String, dynamic>> competencies;
  final int groupingMode; // 0: Evaluator Role, 1: Defense Stage, 2: Score Spread
  final bool isStageMacroMode;
  final String stageTitle;

  const _DefensysClusteredBarChart({
    required this.competencies,
    required this.groupingMode,
    this.isStageMacroMode = false,
    this.stageTitle = '',
  });

  @override
  State<_DefensysClusteredBarChart> createState() =>
      _DefensysClusteredBarChartState();
}

class _DefensysClusteredBarChartState
    extends State<_DefensysClusteredBarChart> {
  int _hoveredClusterIndex = 0;

  @override
  void didUpdateWidget(covariant _DefensysClusteredBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hoveredClusterIndex >= widget.competencies.length &&
        widget.competencies.isNotEmpty) {
      _hoveredClusterIndex = 0;
    }
  }

  List<_CriterionClusterData> _buildClusters() {
    final clusters = <_CriterionClusterData>[];

    for (final item in widget.competencies) {
      final name = widget.isStageMacroMode
          ? (item['stage_name']?.toString() ?? (item['label']?.toString() ?? 'Stage'))
          : (item['name']?.toString() ?? 'Criterion');
      final alignedCourse = widget.isStageMacroMode
          ? '${_asInt(item['total_teams'])} Teams Graded · ${_asInt(item['rubrics_count'])} Rubrics'
          : (item['aligned_course']?.toString() ?? 'Major Subject');
      final rubricName = widget.isStageMacroMode
          ? 'Pass Rate: ${_asInt(item['pass_rate'])}%'
          : (item['rubric_name']?.toString() ?? 'Rubrics');
      final avgScore = item['average_score'] != null ? _asDouble(item['average_score']) : null;
      final evalCount = widget.isStageMacroMode ? _asInt(item['total_teams']) : _asInt(item['evaluations_count']);
      final evalBreakdown = item['evaluator_breakdown'] is Map
          ? Map<String, dynamic>.from(item['evaluator_breakdown'] as Map)
          : <String, dynamic>{};
      final stageBreakdown = item['stage_breakdown'] is List
          ? (item['stage_breakdown'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      final spread = item['score_spread'] is Map
          ? Map<String, dynamic>.from(item['score_spread'] as Map)
          : <String, dynamic>{};

      final seriesList = <_BarSeriesItem>[];

      if (widget.groupingMode == 0 || widget.isStageMacroMode) {
        // Group by Evaluator Role (Panelist vs Adviser vs Peer)
        final panelMap = evalBreakdown['panel'] is Map ? evalBreakdown['panel'] as Map : null;
        final adviserMap = evalBreakdown['adviser'] is Map ? evalBreakdown['adviser'] as Map : null;
        final peerMap = evalBreakdown['peer'] is Map ? evalBreakdown['peer'] as Map : null;

        final panelScore = panelMap != null && panelMap['score'] != null
            ? _asDouble(panelMap['score'])
            : avgScore;
        final adviserScore = adviserMap != null && adviserMap['score'] != null
            ? _asDouble(adviserMap['score'])
            : null;
        final peerScore = peerMap != null && peerMap['score'] != null
            ? _asDouble(peerMap['score'])
            : null;

        seriesList.add(_BarSeriesItem(
          label: 'Panelist',
          score: panelScore,
          count: panelMap != null ? _asInt(panelMap['count']) : evalCount,
          color: const Color(0xFF0EA5E9),
        ));
        seriesList.add(_BarSeriesItem(
          label: 'Adviser',
          score: adviserScore,
          count: adviserMap != null ? _asInt(adviserMap['count']) : 0,
          color: const Color(0xFF10B981),
        ));
        seriesList.add(_BarSeriesItem(
          label: 'Peer',
          score: peerScore,
          count: peerMap != null ? _asInt(peerMap['count']) : 0,
          color: const Color(0xFF6366F1),
        ));
      } else if (widget.groupingMode == 1) {
        // Group by Defense Stage (in criteria view)
        if (stageBreakdown.isNotEmpty) {
          final colors = [
            const Color(0xFFF59E0B),
            const Color(0xFF0EA5E9),
            const Color(0xFF10B981),
            const Color(0xFF8B5CF6),
            const Color(0xFFEC4899),
          ];
          for (int s = 0; s < stageBreakdown.length; s++) {
            final stg = stageBreakdown[s];
            seriesList.add(_BarSeriesItem(
              label: stg['stage']?.toString() ?? 'Stage ${s + 1}',
              score: stg['score'] != null ? _asDouble(stg['score']) : null,
              count: _asInt(stg['count']),
              color: colors[s % colors.length],
            ));
          }
        } else {
          seriesList.add(_BarSeriesItem(
            label: 'Concept Proposal',
            score: avgScore,
            count: evalCount,
            color: const Color(0xFFF59E0B),
          ));
          seriesList.add(const _BarSeriesItem(
            label: 'Colloquium',
            score: null,
            count: 0,
            color: Color(0xFF0EA5E9),
          ));
          seriesList.add(const _BarSeriesItem(
            label: 'Final Defense',
            score: null,
            count: 0,
            color: Color(0xFF10B981),
          ));
        }
      } else {
        // Group by Score Spread (Min vs Avg vs Max)
        final minVal = spread['min'] != null ? _asDouble(spread['min']) : (item['min_score'] != null ? _asDouble(item['min_score']) : null);
        final avgVal = spread['avg'] != null ? _asDouble(spread['avg']) : avgScore;
        final maxVal = spread['max'] != null ? _asDouble(spread['max']) : (item['max_score'] != null ? _asDouble(item['max_score']) : null);

        seriesList.add(_BarSeriesItem(
          label: 'Lowest Score',
          score: minVal,
          count: minVal != null ? 1 : 0,
          color: const Color(0xFFEF4444),
        ));
        seriesList.add(_BarSeriesItem(
          label: 'Average Score',
          score: avgVal,
          count: evalCount,
          color: const Color(0xFF6366F1),
        ));
        seriesList.add(_BarSeriesItem(
          label: 'Highest Score',
          score: maxVal,
          count: maxVal != null ? 1 : 0,
          color: const Color(0xFF10B981),
        ));
      }

      clusters.add(_CriterionClusterData(
        id: item['id']?.toString() ?? (item['stage_id']?.toString() ?? name),
        name: name,
        alignedCourse: alignedCourse,
        rubricName: rubricName,
        averageScore: avgScore,
        evaluationsCount: evalCount,
        series: seriesList,
      ));
    }

    return clusters;
  }

  @override
  Widget build(BuildContext context) {
    final clusters = _buildClusters();
    if (clusters.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'No data available to display in chart.',
            style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    final activeIndex = _hoveredClusterIndex.clamp(0, clusters.length - 1);
    final activeCluster = clusters[activeIndex];
    final seriesCount = clusters.isNotEmpty ? clusters.first.series.length : 0;

    // Build Syncfusion CartesianSeries
    final List<CartesianSeries<_ChartDataPoint, String>> chartSeries = [];

    for (int sIndex = 0; sIndex < seriesCount; sIndex++) {
      final sampleSeries = clusters.first.series[sIndex];
      final seriesName = sampleSeries.label;
      final seriesColor = sampleSeries.color;

      final dataPoints = <_ChartDataPoint>[];
      for (int cIndex = 0; cIndex < clusters.length; cIndex++) {
        final c = clusters[cIndex];
        if (sIndex < c.series.length) {
          final barItem = c.series[sIndex];
          dataPoints.add(_ChartDataPoint(
            category: c.name,
            value: barItem.score,
            count: barItem.count,
            seriesName: seriesName,
            color: seriesColor,
            cluster: c,
            clusterIndex: cIndex,
          ));
        }
      }

      chartSeries.add(
        ColumnSeries<_ChartDataPoint, String>(
          name: seriesName,
          dataSource: dataPoints,
          xValueMapper: (_ChartDataPoint d, _) => d.category,
          yValueMapper: (_ChartDataPoint d, _) => d.value,
          color: seriesColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
          spacing: 0.12,
          width: 0.72,
          animationDuration: 700,
          onPointTap: (ChartPointDetails details) {
            if (details.pointIndex != null && details.pointIndex! < clusters.length) {
              setState(() {
                _hoveredClusterIndex = details.pointIndex!;
              });
            }
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // MAIN SYNCFUSION CLUSTERED BAR CHART
        LayoutBuilder(
          builder: (context, constraints) {
            final minWidthPerCluster = 150.0;
            final calculatedWidth = math.max(constraints.maxWidth, clusters.length * minWidthPerCluster + 60);
            final needsScroll = calculatedWidth > constraints.maxWidth;

            final chartWidget = Container(
              height: 340,
              width: calculatedWidth,
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: SfCartesianChart(
                primaryXAxis: CategoryAxis(
                  labelIntersectAction: AxisLabelIntersectAction.wrap,
                  majorGridLines: const MajorGridLines(width: 0),
                  axisLine: const AxisLine(width: 1, color: Color(0xFFCBD5E1)),
                  labelStyle: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                primaryYAxis: NumericAxis(
                  minimum: 0,
                  maximum: 100,
                  interval: 20,
                  labelFormat: '{value}%',
                  majorGridLines: const MajorGridLines(
                    width: 1,
                    color: Color(0xFFF1F5F9),
                    dashArray: <double>[4, 4],
                  ),
                  axisLine: const AxisLine(width: 0),
                  plotBands: <PlotBand>[
                    PlotBand(
                      start: 75,
                      end: 75,
                      borderColor: const Color(0xFFDC2626),
                      borderWidth: 2,
                      dashArray: const <double>[6, 4],
                      text: '75% PASSING TARGET',
                      textStyle: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                      horizontalTextAlignment: TextAnchor.end,
                      verticalTextAlignment: TextAnchor.middle,
                    ),
                  ],
                ),
                legend: const Legend(
                  isVisible: true,
                  position: LegendPosition.top,
                  alignment: ChartAlignment.center,
                  toggleSeriesVisibility: true,
                  textStyle: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  header: '',
                  canShowMarker: true,
                  format: 'point.x\nseries.name: point.y%',
                  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
                series: chartSeries,
              ),
            );

            if (needsScroll) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: chartWidget,
              );
            }
            return chartWidget;
          },
        ),
        const SizedBox(height: 14),
        // INTERACTIVE DETAIL INSPECTION CARD FOR HOVERED CRITERION / STAGE
        _buildInspectionCard(activeCluster),
        const SizedBox(height: 14),
        // SUMMARY BENCHMARK INSIGHT STRIP
        _buildSummaryInsightStrip(clusters),
      ],
    );
  }

  Widget _buildInspectionCard(_CriterionClusterData cluster) {
    final hasScore = cluster.averageScore != null;
    final avg = cluster.averageScore ?? 0.0;
    final isPassing = avg >= 75.0;
    final delta = avg - 75.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(
              widget.isStageMacroMode ? Icons.public_rounded : Icons.analytics_rounded,
              color: AppColors.maroon,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      cluster.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    _Badge(
                      label: cluster.alignedCourse,
                      bgColor: const Color(0xFFEEF2FF),
                      textColor: const Color(0xFF4F46E5),
                    ),
                    Text(
                      '· ${cluster.rubricName}',
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: cluster.series.map((s) {
                    final sHasScore = s.score != null;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: s.color.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text('${s.label}: ', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5, fontWeight: FontWeight.w600)),
                          Text(
                            sHasScore ? '${s.score}%' : '--',
                            style: TextStyle(color: s.color, fontSize: 12, fontWeight: FontWeight.w900),
                          ),
                          if (sHasScore && s.count > 0)
                            Text(
                              ' (${s.count} evals)',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hasScore ? '$avg%' : '--',
                style: TextStyle(
                  color: hasScore ? (isPassing ? const Color(0xFF059669) : const Color(0xFFDC2626)) : const Color(0xFF94A3B8),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (hasScore)
                Text(
                  isPassing ? '+${delta.toStringAsFixed(1)}% above 75%' : '${delta.toStringAsFixed(1)}% below 75%',
                  style: TextStyle(
                    color: isPassing ? const Color(0xFF059669) : const Color(0xFFDC2626),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryInsightStrip(List<_CriterionClusterData> clusters) {
    final scored = clusters.where((c) => c.averageScore != null).toList();
    if (scored.isEmpty) {
      return const SizedBox.shrink();
    }

    scored.sort((a, b) => (b.averageScore ?? 0).compareTo(a.averageScore ?? 0));
    final topCriterion = scored.first;
    final lowestCriterion = scored.last;
    final needsFocusCount = scored.where((c) => (c.averageScore ?? 0) < 75.0).length;

    final topTitle = widget.isStageMacroMode ? 'HIGHEST PERFORMING STAGE' : 'HIGHEST COMPETENCY';
    final lowestTitle = widget.isStageMacroMode ? 'LOWEST SCORING STAGE' : 'CURRICULUM FOCUS (<75%)';

    final lowestValue = widget.isStageMacroMode
        ? '${lowestCriterion.name} (${lowestCriterion.averageScore}%)'
        : (needsFocusCount > 0
            ? '${lowestCriterion.name} (${lowestCriterion.averageScore}%)'
            : 'All Criteria Meet 75% Benchmark');

    return Row(
      children: [
        Expanded(
          child: _insightPill(
            icon: Icons.star_rounded,
            iconColor: const Color(0xFF10B981),
            title: topTitle,
            value: '${topCriterion.name} (${topCriterion.averageScore}%)',
            bgColor: const Color(0xFFECFDF5),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _insightPill(
            icon: needsFocusCount > 0 ? Icons.warning_amber_rounded : Icons.verified_rounded,
            iconColor: needsFocusCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF6366F1),
            title: lowestTitle,
            value: lowestValue,
            bgColor: needsFocusCount > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFEEF2FF),
          ),
        ),
      ],
    );
  }

  Widget _insightPill({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: iconColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static double _asDouble(dynamic val) => _toDouble(val);
  static int _asInt(dynamic val) => _toInt(val);

  static double _toDouble(dynamic val) {
    if (val is double) return val;
    if (val is num) return val.toDouble();
    if (val != null) return double.tryParse(val.toString()) ?? 0.0;
    return 0.0;
  }

  static int _toInt(dynamic val) {
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val != null) return int.tryParse(val.toString()) ?? 0;
    return 0;
  }
}
