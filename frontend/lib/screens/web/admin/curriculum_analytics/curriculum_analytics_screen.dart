import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../services/academic/curriculum_analytics_provider.dart';
import '../../../../services/auth/auth_provider.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/export/export.dart';
import 'widgets/curriculum_academic_highlights.dart';
import 'widgets/curriculum_circular_kpis.dart';
import 'widgets/curriculum_cohort_progression_card.dart';
import 'widgets/curriculum_multi_year_trajectory_card.dart';
import 'widgets/curriculum_projects_donut.dart';
import 'widgets/curriculum_radar_chart.dart';
import 'widgets/curriculum_remediation_tracker_card.dart';
import 'widgets/curriculum_rubric_matrix_dialog.dart';

class CurriculumAnalyticsScreen extends ConsumerStatefulWidget {
  const CurriculumAnalyticsScreen({super.key});

  @override
  ConsumerState<CurriculumAnalyticsScreen> createState() =>
      _CurriculumAnalyticsScreenState();
}

class _CurriculumAnalyticsScreenState
    extends ConsumerState<CurriculumAnalyticsScreen> {
  String _selectedScope = 'capstone'; // 'capstone', 'pit', 'all'
  String _selectedStageFilter = 'all'; // 'all' or stage_id / label

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(curriculumAnalyticsProvider.notifier).fetchAnalytics(
            scope: _selectedScope,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(curriculumAnalyticsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header with Actions & Academic Year selector
          _buildHeader(state),
          const SizedBox(height: 16),

          // 2. Track Switcher (Capstone vs PIT vs Unified)
          _buildTrackSwitcher(state),
          const SizedBox(height: 18),

          // Error / Success Banners
          if (state.error != null) ...[
            _notice(Icons.error_outline_rounded, state.error!, AppColors.danger),
            const SizedBox(height: 14),
          ],
          if (state.message != null) ...[
            _notice(Icons.check_circle_outline_rounded, state.message!, AppColors.success),
            const SizedBox(height: 14),
          ],

          if (state.isLoading)
            const SizedBox(
              height: 380,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.maroon),
              ),
            )
          else ...[
            // =================================================================
            // SECTION 0: ANNUAL COHORT & INSTITUTIONAL PROGRESSION (Unified)
            // =================================================================
            if (_selectedScope == 'all') ...[
              _sectionHeader(
                icon: Icons.auto_graph_rounded,
                title: 'Annual Cohort & Institutional Progression',
                subtitle:
                    'Multi-year competency trajectory, 4-year cohort progression funnel, and CQI remediation tracking',
              ),
              const SizedBox(height: 14),

              _buildProgressionOverviewSection(state),
              const SizedBox(height: 32),
            ],

            // =================================================================
            // SECTION 1: STUDENT COMPETENCY & DEFENSE OUTCOMES
            // =================================================================
            _sectionHeader(
              icon: Icons.school_rounded,
              title: 'Student Competency & Defense Outcomes',
              subtitle:
                  'Multi-axial rubric evaluations, benchmark achievement, and faculty consensus (${_scopeDisplayName(_selectedScope)})',
            ),
            const SizedBox(height: 14),

            // Top Circular KPI Badges
            _buildCircularKpis(state),
            const SizedBox(height: 18),

            // Main Competency Card: Stage Pill Selector + Highlights + Radar Chart
            _buildCompetencySection(state),
            const SizedBox(height: 32),

            // =================================================================
            // SECTION 2: PROJECT DOMAINS & INDUSTRY TECH STACKS
            // =================================================================
            _sectionHeader(
              icon: Icons.category_rounded,
              title: 'Project Domains & Industry Tech Stacks',
              subtitle:
                  'Specialization domains and software frameworks extracted from deliverable repositories',
            ),
            const SizedBox(height: 14),

            _buildProjectsSection(state),
            const SizedBox(height: 32),

            // Footer Summary & Report Download
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 820;

        final titleBlock = Row(
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
            const SizedBox(width: 14),
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
                  SizedBox(height: 4),
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
          ],
        );

        final actionControls = Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (years.isNotEmpty) _academicYearDropdown(years, selectedYear),
            _secondaryButton(
              icon: Icons.file_download_outlined,
              label: 'Export Proposal',
              onTap: _openExportModal,
            ),
            _primaryButton(
              icon: Icons.auto_awesome_rounded,
              label: state.isSaving ? 'Generating...' : 'Generate Proposal',
              onTap: state.isSaving ? null : _generateProposalModal,
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 14),
              actionControls,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            actionControls,
          ],
        );
      },
    );
  }

  Widget _academicYearDropdown(List<String> years, String selectedYear) {
    final selected = years.contains(selectedYear)
        ? selectedYear
        : (years.isNotEmpty ? years.first : '');

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD1D5DB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected.isEmpty ? null : selected,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: AppColors.textPrimary),
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
                        const Icon(Icons.calendar_today_rounded,
                            size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text('AY $year'),
                      ],
                    ),
                  ))
              .toList(),
          onChanged: (value) {
            if (value != null) {
              ref.read(curriculumAnalyticsProvider.notifier).fetchAnalytics(
                    academicYear: value,
                    scope: _selectedScope,
                  );
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
        'label': 'Capstone Track',
        'sublabel': '4th Year Defense Stages',
        'icon': Icons.school_outlined,
        'color': AppColors.maroon,
      },
      {
        'key': 'pit',
        'label': 'PIT Track',
        'sublabel': '1st–3rd Year Events',
        'icon': Icons.science_outlined,
        'color': const Color(0xFF0284C7),
      },
      {
        'key': 'all',
        'label': 'Unified Overview',
        'sublabel': 'Cross-Cohort Impact',
        'icon': Icons.hub_outlined,
        'color': const Color(0xFF475569),
      },
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 6,
            offset: Offset(0, 2),
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
              final icon = s['icon'] as IconData;

              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _changeScope(s['key'] as String, state),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? color : Colors.transparent,
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              icon,
                              size: 15,
                              color: isSelected
                                  ? color
                                  : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              s['label'] as String,
                              style: TextStyle(
                                color: isSelected
                                    ? color
                                    : const Color(0xFF334155),
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (!isNarrow) ...[
                          const SizedBox(height: 2),
                          Text(
                            s['sublabel'] as String,
                            style: TextStyle(
                              color: isSelected
                                  ? color.withValues(alpha: 0.8)
                                  : const Color(0xFF94A3B8),
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

  // ---------------------------------------------------------------------------
  // SECTION 1: STUDENT COMPETENCY & DEFENSE OUTCOMES
  // ---------------------------------------------------------------------------

  Widget _buildCircularKpis(CurriculumAnalyticsState state) {
    final kpiSummary = _mapOrEmpty(state.data['kpi_summary']);
    final defenseFunnel = _mapOrEmpty(state.data['defense_funnel']);
    final hasEvaluations = kpiSummary['has_evaluations'] == true;

    return CurriculumCircularKpis(
      kpiSummary: kpiSummary,
      defenseFunnel: defenseFunnel,
      hasEvaluations: hasEvaluations,
    );
  }

  Widget _buildCompetencySection(CurriculumAnalyticsState state) {
    final availableStages = _mapList(state.data['available_stages']);
    final stageOverview = _mapList(state.data['stage_performance_overview']);
    final allCompetencies = _mapList(state.data['competency_matrix']);
    final kpiSummary = _mapOrEmpty(state.data['kpi_summary']);
    final defenseFunnel = _mapOrEmpty(state.data['defense_funnel']);
    final prescriptions = _mapList(state.data['prescriptions']);

    final isOverall = _selectedStageFilter == 'all';

    // Find active stage name for title
    String activeStageName = 'Overall (All Stages)';
    if (!isOverall) {
      final matchedStage = availableStages.firstWhere(
        (s) =>
            s['id']?.toString() == _selectedStageFilter ||
            (s['label']?.toString().toLowerCase() ==
                _selectedStageFilter.toLowerCase()),
        orElse: () => stageOverview.firstWhere(
          (s) =>
              s['stage_id']?.toString() == _selectedStageFilter ||
              (s['stage_name']?.toString().toLowerCase() ==
                  _selectedStageFilter.toLowerCase()),
          orElse: () =>
              {'label': _selectedStageFilter, 'stage_name': _selectedStageFilter},
        ),
      );
      activeStageName = matchedStage['stage_name']?.toString() ??
          (matchedStage['label']?.toString() ?? _selectedStageFilter);
    }

    // Filter criteria for selected stage
    final filteredCompetencies = isOverall
        ? allCompetencies
        : allCompetencies.where((c) {
            final cStageId = c['stage_id']?.toString() ?? '';
            final cStageName = c['stage_name']?.toString() ??
                (c['stage_label']?.toString() ?? '');
            return cStageId == _selectedStageFilter ||
                cStageName.toLowerCase() == _selectedStageFilter.toLowerCase() ||
                cStageName.toLowerCase().contains(_selectedStageFilter.toLowerCase());
          }).toList();

    // Map to RadarCriterionPoint items
    final radarCriteria = filteredCompetencies
        .map((c) => RadarCriterionPoint.fromMap(c))
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 920;

        final highlightsCard = CurriculumAcademicHighlights(
          criteria: radarCriteria,
          kpiSummary: kpiSummary,
          defenseFunnel: defenseFunnel,
          prescriptions: prescriptions,
          onOpenMatrixDialog: () => _openRubricMatrixDialog(
            filteredCompetencies.isNotEmpty
                ? filteredCompetencies
                : allCompetencies,
            activeStageName,
          ),
        );

        final radarCard = CurriculumRadarChart(
          criteria: radarCriteria,
          stageTitle: activeStageName,
          selectedStageId: _selectedStageFilter,
          availableStages:
              availableStages.isNotEmpty ? availableStages : stageOverview,
          onStageChanged: (newStage) {
            setState(() {
              _selectedStageFilter = newStage;
            });
          },
          stageOverview: stageOverview,
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: highlightsCard),
              const SizedBox(width: 18),
              Expanded(flex: 6, child: radarCard),
            ],
          );
        } else {
          return Column(
            children: [
              highlightsCard,
              const SizedBox(height: 18),
              radarCard,
            ],
          );
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION 0: ANNUAL COHORT & INSTITUTIONAL PROGRESSION
  // ---------------------------------------------------------------------------

  Widget _buildProgressionOverviewSection(CurriculumAnalyticsState state) {
    final longitudinal = _mapList(state.data['longitudinal_5year']);
    final cohortProgression = _mapList(state.data['cohort_progression']);
    final remediationTracker = _mapList(state.data['remediation_tracker']);
    final activeYear = state.selectedAcademicYear.isNotEmpty
        ? state.selectedAcademicYear
        : '2024-2025';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Multi-Year Trajectory
        CurriculumMultiYearTrajectoryCard(
          longitudinalSeries: longitudinal,
          activeAcademicYear: activeYear,
        ),
        const SizedBox(height: 18),

        // 2. 4-Year Cohort Funnel
        CurriculumCohortProgressionCard(
          cohortProgression: cohortProgression,
        ),
        const SizedBox(height: 18),

        // 3. CQI Remediation Tracker
        CurriculumRemediationTrackerCard(
          remediationTracker: remediationTracker,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION 2: PROJECT DOMAINS & INDUSTRY TECH STACKS
  // ---------------------------------------------------------------------------

  Widget _buildProjectsSection(CurriculumAnalyticsState state) {
    final domainDist = _mapList(state.data['domain_distribution']);
    final techDist = _mapList(state.data['distribution']);
    final totalProjects = int.tryParse(
            state.data['kpi_summary']?['total_projects']?.toString() ?? '0') ??
        0;

    return CurriculumProjectsDonut(
      domainDistribution: domainDist,
      techDistribution: techDist,
      totalProjects: totalProjects,
    );
  }

  // ---------------------------------------------------------------------------
  // FOOTER ACTIONS & MODALS
  // ---------------------------------------------------------------------------

  Widget _buildSummaryFooter(CurriculumAnalyticsState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.policy_rounded, size: 18, color: Color(0xFF64748B)),
              const SizedBox(width: 8),
              Text(
                'Reporting Period: AY ${state.selectedAcademicYear.isNotEmpty ? state.selectedAcademicYear : "Active"} (${_scopeDisplayName(_selectedScope)})',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569), fontWeight: FontWeight.w600),
              ),
            ],
          ),
          _secondaryButton(
            icon: Icons.file_download_outlined,
            label: 'Export Curriculum Decision Support Proposal',
            onTap: _openExportModal,
          ),
        ],
      ),
    );
  }

  void _openRubricMatrixDialog(
    List<Map<String, dynamic>> criteria,
    String stageTitle,
  ) {
    showDialog(
      context: context,
      builder: (context) => CurriculumRubricMatrixDialog(
        criteria: criteria,
        stageTitle: stageTitle,
      ),
    );
  }

  Future<void> _openExportModal() async {
    final state = ref.read(curriculumAnalyticsProvider);
    final user = ref.read(authProvider).user;
    String userName = '';
    if (user != null) {
      final fn = (user['first_name'] ?? '').toString().trim();
      final ln = (user['last_name'] ?? '').toString().trim();
      if (fn.isNotEmpty || ln.isNotEmpty) {
        userName = '$fn $ln'.trim();
      } else {
        userName = (user['username'] ?? '').toString().trim();
      }
    }
    if (userName.isEmpty) userName = 'admin';

    final selectedYear = state.selectedAcademicYear.isNotEmpty ? state.selectedAcademicYear : '2024-2025';
    final trackSuffix = _selectedScope != 'all' ? ' (${_scopeDisplayName(_selectedScope)})' : '';

    final config = DefensysExportConfig(
      title: 'Curriculum Analytics & Decision Support Proposal',
      subtitle: 'Evidence-Based Academic Improvement Report · AY $selectedYear$trackSuffix',
      tag: 'DECISION SUPPORT',
      icon: Icons.auto_awesome_rounded,
      defaultFilename: 'Curriculum_Proposal_AY_${selectedYear}_${_selectedScope.toUpperCase()}',
      supportedFormats: const ['pdf', 'xlsx', 'csv', 'doc'],
      initialFormat: 'pdf',
      initialSignatories: [
        DefensysSignatory(
          label: 'Prepared by:',
          name: userName,
          role: 'Curriculum Analytics Lead / Evaluator',
        ),
        const DefensysSignatory(
          label: 'Noted by:',
          name: 'Academic Department Secretary',
          role: 'Department Curriculum Committee Secretary',
        ),
        const DefensysSignatory(
          label: 'Approved by:',
          name: 'IT Program Chairperson / College Dean',
          role: 'Chairperson, Department of Information Technology',
        ),
      ],
      initialIncludeSignatures: true,
      onFetchPreview: (params) async {
        return await ref.read(curriculumAnalyticsProvider.notifier).fetchProposalPreview(
              scope: _selectedScope,
              queryParams: params,
            );
      },
      onDownload: (params, format, signatories, includeSignatures) async {
        return await ref.read(curriculumAnalyticsProvider.notifier).downloadProposalExport(
              scope: _selectedScope,
              format: format,
              signatories: signatories,
              includeSignatures: includeSignatures,
              customFilename: params['custom_filename'],
            );
      },
    );

    await showDefensysExportModal(
      context: context,
      config: config,
    );
  }

  Future<void> _generateProposalModal() async {
    await ref
        .read(curriculumAnalyticsProvider.notifier)
        .generateProposal(scope: _selectedScope);
    if (!mounted) return;

    final proposal = ref.read(curriculumAnalyticsProvider).proposal;
    if (proposal == null) return;

    showDialog(
      context: context,
      builder: (context) {
        final title = proposal['title']?.toString() ?? 'Curriculum Proposal';
        final summary = proposal['summary']?.toString() ?? '';
        final recommendations = _mapList(proposal['recommendations']);

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.maroon.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: AppColors.maroon, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      color: AppColors.maroon,
                      fontSize: 17,
                      fontWeight: FontWeight.w800),
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
                      style: const TextStyle(
                          color: Color(0xFF334155),
                          fontSize: 13,
                          height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Key Recommendations',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800),
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
                          const Icon(Icons.check_circle_rounded,
                              size: 16, color: Color(0xFF10B981)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '$t: ',
                                    style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.5),
                                  ),
                                  TextSpan(
                                    text: b,
                                    style: const TextStyle(
                                        color: Color(0xFF475569),
                                        fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openExportModal();
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.maroon),
              child: const Text('Export Official Proposal'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // HELPER WIDGETS
  // ---------------------------------------------------------------------------

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.maroon.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.maroon, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: Colors.white),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.maroon,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _secondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: AppColors.textPrimary),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: Color(0xFFD1D5DB)),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _notice(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _scopeDisplayName(String scope) {
    switch (scope.toLowerCase()) {
      case 'capstone':
        return '4th Year Capstone';
      case 'pit':
        return '1st-3rd Year PIT';
      default:
        return 'Unified Overview';
    }
  }

  List<String> _stringList(dynamic val) {
    if (val is List) {
      return val.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();
    }
    return [];
  }

  List<Map<String, dynamic>> _mapList(dynamic val) {
    if (val is List) {
      return val
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  Map<String, dynamic> _mapOrEmpty(dynamic val) {
    if (val is Map) {
      return Map<String, dynamic>.from(val);
    }
    return {};
  }
}
