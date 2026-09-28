import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/academic_period_provider.dart';
import '../../../../services/defense_scheduler_provider.dart';
import '../../../../services/defense_stages_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/feedback/empty_state.dart';
import '../grade_center/grade_center_shared.dart'
    show showPeerGradingHelpDialog;
import '../widgets/defensys_admin_shell.dart';

class SemesterDetailScreen extends ConsumerStatefulWidget {
  const SemesterDetailScreen({
    super.key,
    required this.semesterId,
    this.onBack,
  });

  final int? semesterId;
  final VoidCallback? onBack;

  @override
  ConsumerState<SemesterDetailScreen> createState() =>
      _SemesterDetailScreenState();
}

class _SemesterDetailScreenState extends ConsumerState<SemesterDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _pitEventConfigs = [];
  bool _loadingPitConfigs = false;

  static const _line = DefensysTokens.border;
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _borderColor => _isDark ? DefensysTokens.mistBorder : _line;
  Color get _surfaceColor => _isDark ? DefensysTokens.mistSurface : Colors.white;
  Color get _inkColor => _isDark ? const Color(0xFFF4F4F5) : _ink;
  Color get _mutedColor => _isDark ? const Color(0xFFA1A1AA) : _muted;
  Color get _panelBgColor =>
      _isDark ? const Color(0xFF1B1B1F) : const Color(0xFFF9FAFB);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    ref.read(academicPeriodProvider.notifier).fetchPeriods();
    ref.read(defenseStagesProvider.notifier).fetchStages();
    _loadPitEvents();
  }

  Future<void> _loadPitEvents() async {
    if (widget.semesterId == null) return;
    setState(() => _loadingPitConfigs = true);
    try {
      final configs = await ref
          .read(defenseSchedulerProvider.notifier)
          .fetchPitEventConfigs(semesterId: widget.semesterId);
      if (mounted) {
        setState(() {
          _pitEventConfigs = configs;
          _loadingPitConfigs = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingPitConfigs = false);
      }
    }
  }

  Map<String, dynamic>? _findSemester(AcademicPeriodState state) {
    if (widget.semesterId == null) return null;
    for (final year in state.schoolYears) {
      final rawSemesters = year['semesters'];
      if (rawSemesters is List) {
        for (final sem in rawSemesters) {
          if (sem is Map<String, dynamic> &&
              int.tryParse(sem['id']?.toString() ?? '') == widget.semesterId) {
            return {
              ...sem,
              'school_year_label': year['label'],
              'school_year_id': year['id'],
            };
          }
        }
      }
    }
    if (state.activeSemester != null &&
        int.tryParse(state.activeSemester!['id']?.toString() ?? '') ==
            widget.semesterId) {
      return state.activeSemester;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(academicPeriodProvider);
    final semester = _findSemester(state);

    if (state.isLoading && semester == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: _maroon),
        ),
      );
    }

    if (semester == null) {
      return Scaffold(
        backgroundColor: _isDark ? const Color(0xFF121214) : DefensysUi.bgLight,
        body: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: DefensysEmptyState.table(
              icon: Icons.error_outline_rounded,
              title: 'Semester Not Found',
              description:
                  'The requested academic term does not exist or has been deleted.',
              primaryAction: DefensysEmptyAction(
                label: 'Back to Academic Cycles',
                icon: Icons.arrow_back_rounded,
                onPressed: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AdminRoutes.academicPeriods);
                  }
                },
              ),
            ),
          ),
        ),
      );
    }

    final yearLabel = semester['school_year_label']?.toString() ??
        semester['school_year']?.toString() ??
        '';
    final termName = semester['label']?.toString() ?? 'Semester';
    final isActive = semester['is_active'] == true;

    return Scaffold(
      backgroundColor: _isDark ? const Color(0xFF121214) : DefensysUi.bgLight,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Breadcrumb & Back Action
            Row(
              children: [
                InkWell(
                  onTap: () {
                    if (widget.onBack != null) {
                      widget.onBack!();
                    } else if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(AdminRoutes.academicPeriods);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_rounded,
                            size: 16, color: _mutedColor),
                        const SizedBox(width: 6),
                        Text(
                          'Back to Academic Cycles',
                          style: TextStyle(
                            color: _mutedColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('/',
                    style: TextStyle(color: _borderColor, fontSize: 13)),
                const SizedBox(width: 12),
                Text(
                  'A.Y. $yearLabel',
                  style: TextStyle(color: _mutedColor, fontSize: 13),
                ),
                const SizedBox(width: 8),
                Text('/',
                    style: TextStyle(color: _borderColor, fontSize: 13)),
                const SizedBox(width: 8),
                Text(
                  termName,
                  style: TextStyle(
                    color: _inkColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Header Banner
            _buildTermHeader(semester, yearLabel, termName, isActive),
            const SizedBox(height: 20),

            // 3 KPI Overview Cards
            _buildKpiOverviewRow(semester, isActive),
            const SizedBox(height: 24),

            // Segmented Tabs
            _buildTabBar(),
            const SizedBox(height: 20),

            // Tab Content
            AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) {
                switch (_tabController.index) {
                  case 0:
                    return _buildCapstoneTab(semester, state.isSaving);
                  case 1:
                    return _buildPitTab(semester, state.isSaving);
                  case 2:
                  default:
                    return _buildMasterControlsTab(semester, state.isSaving);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTermHeader(
    Map<String, dynamic> semester,
    String yearLabel,
    String termName,
    bool isActive,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? (_isDark ? const Color(0xFF059669) : const Color(0xFF10B981))
              : _borderColor,
          width: isActive ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.25 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isActive
                  ? (_isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5))
                  : (_isDark ? const Color(0xFF27272A) : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? (_isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0))
                    : _borderColor,
              ),
            ),
            child: Icon(
              isActive ? Icons.verified_rounded : Icons.calendar_month_rounded,
              color: isActive
                  ? (_isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                  : _mutedColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$termName (A.Y. $yearLabel)',
                      style: TextStyle(
                        color: _inkColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: isActive
                            ? (_isDark
                                ? const Color(0xFF064E3B)
                                : const Color(0xFFECFDF5))
                            : (_isDark
                                ? const Color(0xFF27272A)
                                : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isActive
                              ? const Color(0xFF10B981)
                              : _borderColor,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFF10B981)
                                  : _mutedColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isActive
                                ? 'ACTIVE (WRITE-ENABLED)'
                                : 'INACTIVE / UPCOMING',
                            style: TextStyle(
                              color: isActive
                                  ? (_isDark
                                      ? const Color(0xFF34D399)
                                      : const Color(0xFF047857))
                                  : _mutedColor,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isActive
                      ? 'Live Institutional Term: All schedules, submissions, and grade entries currently route to this period.'
                      : 'Upcoming / Non-active term: You can configure defense stages, PIT events, and evaluation policies before activating.',
                  style: TextStyle(
                    color: _mutedColor,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (!isActive)
            ElevatedButton.icon(
              onPressed: () => _activateThisSemester(semester),
              icon: const Icon(Icons.flash_on_rounded, size: 16),
              label: const Text('Set as Active Semester'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _maroon,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _isDark
                    ? const Color(0xFF064E3B).withValues(alpha: 0.3)
                    : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isDark
                      ? const Color(0xFF059669)
                      : const Color(0xFFA7F3D0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_clock_rounded,
                      size: 15, color: Color(0xFF10B981)),
                  const SizedBox(width: 6),
                  Text(
                    'Current Live Period',
                    style: TextStyle(
                      color: _isDark
                          ? const Color(0xFF34D399)
                          : const Color(0xFF047857),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKpiOverviewRow(Map<String, dynamic> semester, bool isActive) {
    final phase = semester['capstone_program_phase']?.toString();
    String phaseLabel;
    if (phase == 'capstone_1') {
      phaseLabel = 'Capstone 1 Intake';
    } else if (phase == 'capstone_2') {
      phaseLabel = 'Capstone 2 Continue';
    } else {
      phaseLabel = 'Closed';
    }

    final stagesState = ref.watch(defenseStagesProvider);
    final stagesCount = stagesState.stages.length;

    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            icon: Icons.school_rounded,
            iconBg: _isDark ? const Color(0xFF3B181F) : const Color(0xFFFEE2E2),
            iconColor: _isDark ? const Color(0xFFF87171) : _maroon,
            title: '🎓 Capstone Program',
            value: phaseLabel,
            subtitle: '4th Year Cohorts • Senior Project',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _kpiCard(
            icon: Icons.rocket_launch_rounded,
            iconBg: _isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF),
            iconColor: _isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4338CA),
            title: '🚀 PIT Program Track',
            value: '${_pitEventConfigs.length} Pitch Events',
            subtitle: '1st, 2nd, and 3rd Year Cohorts',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _kpiCard(
            icon: Icons.timeline_rounded,
            iconBg: _isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
            iconColor: const Color(0xFF10B981),
            title: '🛡️ Defense Stages',
            value: '$stagesCount Stages Available',
            subtitle: isActive ? 'Write-Enabled & Scheduled' : 'Configurable',
          ),
        ),
      ],
    );
  }

  Widget _kpiCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.25 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: _inkColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(
              color: _inkColor,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: _mutedColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: _maroon,
        unselectedLabelColor: _mutedColor,
        indicatorColor: _maroon,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(
            iconMargin: EdgeInsets.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.school_outlined, size: 16),
                SizedBox(width: 8),
                Text('🎓 Capstone Program (4th Year)'),
              ],
            ),
          ),
          Tab(
            iconMargin: EdgeInsets.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.rocket_launch_outlined, size: 16),
                SizedBox(width: 8),
                Text('🚀 PIT Program (1st–3rd Year)'),
              ],
            ),
          ),
          Tab(
            iconMargin: EdgeInsets.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.settings_outlined, size: 16),
                SizedBox(width: 8),
                Text('⚙️ Master Controls & Logs'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapstoneTab(Map<String, dynamic> semester, bool isSaving) {
    final semesterId = int.tryParse(semester['id']?.toString() ?? '');
    final phase = semester['capstone_program_phase']?.toString();
    final teamCreationOn = semester['capstone_team_creation_enabled'] == true;
    final peerOn = semester['capstone_peer_evaluation_enabled'] != false;
    final adviserOn = semester['capstone_adviser_grading_enabled'] != false;

    final stagesState = ref.watch(defenseStagesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Two side-by-side policy cards
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: Capstone Cohort Policies
            Expanded(
              child: _card(
                title: '⚙️ Capstone Cohort Policies',
                description:
                    'Configure cohort intake, team formation window, and degree rollover',
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _settingRow(
                        label: 'Program Phase',
                        child: Text(
                          phase == 'capstone_1'
                              ? 'Capstone 1 (Intake - 3rd Year, 2nd Sem)'
                              : (phase == 'capstone_2'
                                  ? 'Capstone 2 (Continuation - 4th Year, 1st Sem)'
                                  : 'Closed / Inactive'),
                          style: TextStyle(
                            color: _inkColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _settingRow(
                        label: 'Team Formation',
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: teamCreationOn
                                    ? (_isDark
                                        ? const Color(0xFF064E3B)
                                        : const Color(0xFFECFDF5))
                                    : (_isDark
                                        ? const Color(0xFF27272A)
                                        : const Color(0xFFF1F5F9)),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                teamCreationOn ? 'Open for Intake' : 'Closed',
                                style: TextStyle(
                                  color: teamCreationOn
                                      ? (_isDark
                                          ? const Color(0xFF34D399)
                                          : const Color(0xFF047857))
                                      : _mutedColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                teamCreationOn
                                    ? 'Admins can create/import teams.'
                                    : 'Creation follows academic calendar.',
                                style: TextStyle(
                                    color: _mutedColor, fontSize: 11.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _settingRow(
                        label: 'Team Rollover',
                        child: Text(
                          'Capstone 2 automatically preserves teams & assigned advisers from Capstone 1.',
                          style: TextStyle(
                              color: _mutedColor, fontSize: 12, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),

            // Right: Term-wide Evaluation Switches
            Expanded(
              child: _card(
                title: '📝 Term-Wide Evaluation Master Toggles',
                description:
                    'Master authorization switches controlling peer and adviser grading',
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      _evaluationToggleTile(
                        title: 'Student Peer Evaluation',
                        subtitle:
                            'Enables Peer Eval tab for enrolled students on Capstone teams.',
                        value: peerOn,
                        enabled: !isSaving && semesterId != null,
                        helpTooltip: 'View Capstone Peer Evaluation Guide',
                        onHelpTap: () =>
                            showPeerGradingHelpDialog(context, isPit: false),
                        onChanged: (val) {
                          if (semesterId != null) {
                            ref
                                .read(academicPeriodProvider.notifier)
                                .updateSemesterEvaluationSettings(
                                  semesterId,
                                  peerEvaluationEnabled: val,
                                );
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _evaluationToggleTile(
                        title: 'Adviser Grading Submission',
                        subtitle:
                            'Allows assigned faculty advisers to submit rubric grades for their teams.',
                        value: adviserOn,
                        enabled: !isSaving && semesterId != null,
                        onChanged: (val) {
                          if (semesterId != null) {
                            ref
                                .read(academicPeriodProvider.notifier)
                                .updateSemesterEvaluationSettings(
                                  semesterId,
                                  adviserGradingEnabled: val,
                                );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // Defense Stages Pipeline Summary Card
        _card(
          title: '🛡️ Capstone Defense Stages Pipeline',
          description:
              'Active defense stages configured for this academic period',
          actionLabel: 'Configure Stages in Setup ↗',
          onActionTap: () => context.push(AdminRoutes.defenseStages),
          child: Column(
            children: [
              if (stagesState.isLoading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(color: _maroon),
                  ),
                )
              else if (stagesState.stages.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: DefensysEmptyState.table(
                    icon: Icons.timeline_outlined,
                    title: 'No Defense Stages Configured',
                    description:
                        'Create and order defense stages (e.g. Title Proposal, Outline Defense, Final Defense) in Defense Stages Setup.',
                    primaryAction: DefensysEmptyAction(
                      label: 'Open Defense Stages Setup',
                      icon: Icons.launch_rounded,
                      onPressed: () => context.push(AdminRoutes.defenseStages),
                    ),
                  ),
                )
              else
                ...stagesState.stages.asMap().entries.map((entry) {
                  final index = entry.key + 1;
                  final stage = entry.value;
                  return _buildStagePipelineRow(index, stage);
                }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPitTab(Map<String, dynamic> semester, bool isSaving) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // PIT Structure Info Card
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _card(
                title: '📌 PIT Cohort Structure (1st–3rd Year)',
                description:
                    'Project in Lieu of Thesis / Practicum milestone demo structure',
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'About PIT Cohorts:',
                        style: TextStyle(
                          color: _inkColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'PIT runs parallel across 1st Year (CS 101 Concept Pitch), 2nd Year (CS 201 System Design / Architecture), and 3rd Year (CS 301 Capstone Readiness). Each event represents a course milestone defense.',
                        style: TextStyle(
                          color: _mutedColor,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isDark
                              ? const Color(0xFF1E1B4B).withValues(alpha: 0.3)
                              : const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isDark
                                ? const Color(0xFF3730A3)
                                : const Color(0xFFC7D2FE),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 18, color: Color(0xFF6366F1)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Note: PIT does NOT have assigned faculty advisers. PIT grading relies exclusively on Panel Evaluators (80%) + Student Peer Reviews (20%).',
                                style: TextStyle(
                                  color: _isDark
                                      ? const Color(0xFFA5B4FC)
                                      : const Color(0xFF3730A3),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _card(
                title: '📝 PIT Evaluation Policy',
                description:
                    'Grading formula and rubric rules for PIT milestone events',
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _panelBgColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Panelist Weight',
                                    style: TextStyle(
                                        color: _mutedColor, fontSize: 11),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '80%',
                                    style: TextStyle(
                                      color: _inkColor,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Defense Panel Rubric',
                                    style: TextStyle(
                                        color: _mutedColor, fontSize: 10.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _panelBgColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Peer Evaluation',
                                    style: TextStyle(
                                        color: _mutedColor, fontSize: 11),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '20%',
                                    style: TextStyle(
                                      color: _inkColor,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Student Peer Rubric',
                                    style: TextStyle(
                                        color: _mutedColor, fontSize: 10.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Peer Evaluation Help Guide:',
                        style: TextStyle(
                            color: _inkColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: () =>
                            showPeerGradingHelpDialog(context, isPit: true),
                        icon: const Icon(Icons.help_outline_rounded, size: 15),
                        label: const Text('View PIT Peer Evaluation Guide'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _inkColor,
                          side: BorderSide(color: _borderColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // Configured PIT Events for this term
        _card(
          title: '🚀 Configured PIT Events for this Term',
          description:
              'Milestone pitch events configured for 1st, 2nd, and 3rd year cohorts',
          actionLabel: 'Manage PIT Events ↗',
          onActionTap: () => context.push('/faculty/pit-events'),
          child: Column(
            children: [
              if (_loadingPitConfigs)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(color: _maroon),
                  ),
                )
              else if (_pitEventConfigs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: DefensysEmptyState.table(
                    icon: Icons.event_available_outlined,
                    title: 'No PIT Events Configured for this Term',
                    description:
                        'PIT event themes (e.g. Concept Pitch, System Pitch) can be configured in PIT Events Management.',
                    primaryAction: DefensysEmptyAction(
                      label: 'Open PIT Events Management',
                      icon: Icons.launch_rounded,
                      onPressed: () => context.push('/faculty/pit-events'),
                    ),
                  ),
                )
              else
                ..._pitEventConfigs.map((config) => _buildPitEventRow(config)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMasterControlsTab(
      Map<String, dynamic> semester, bool isSaving) {
    final isActive = semester['is_active'] == true;
    final termName = semester['label']?.toString() ?? 'Semester';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(
          title: '⚙️ Semester Lifecycle & Status',
          description:
              'Activate, switch, or manage archive properties for this term',
          child: Padding(
            padding: const EdgeInsets.all(20),
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
                            isActive
                                ? 'This semester is currently LIVE'
                                : 'This semester is currently INACTIVE',
                            style: TextStyle(
                              color: _inkColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isActive
                                ? 'All users (students, faculty, admins) operate inside this period. Switching to another semester will preserve historical records.'
                                : 'Activating this semester will set it as the institutional active term.',
                            style: TextStyle(color: _mutedColor, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (!isActive)
                      ElevatedButton(
                        onPressed: () => _activateThisSemester(semester),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _maroon,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Activate This Semester'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _card(
          title: '⚠️ Danger Zone',
          description: 'Irreversible administrative operations',
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Delete $termName',
                        style: TextStyle(
                          color: _inkColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isActive
                            ? 'Cannot delete the currently active semester. You must activate another semester first.'
                            : 'Permanently remove this term configuration. Only permitted if no student teams, grades, or enrollments exist.',
                        style: TextStyle(color: _mutedColor, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: isActive ? null : () => _deleteThisSemester(semester),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFF87171)),
                  ),
                  child: const Text('Delete Term'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStagePipelineRow(int index, Map<String, dynamic> stage) {
    final label = stage['label']?.toString() ?? 'Stage';
    final desc = stage['description']?.toString() ?? '';
    final isPresentationOnly = stage['is_presentation_only'] == true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _isDark ? const Color(0xFF27272A) : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
              border: Border.all(color: _borderColor),
            ),
            child: Center(
              child: Text(
                '$index',
                style: TextStyle(
                  color: _inkColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: _inkColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isPresentationOnly)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _isDark
                              ? const Color(0xFF3F3F46)
                              : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Presentation Only',
                          style: TextStyle(color: _mutedColor, fontSize: 10),
                        ),
                      ),
                  ],
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TextStyle(color: _mutedColor, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () {
              final stageId = int.tryParse(stage['id']?.toString() ?? '');
              if (stageId != null) {
                context.push(AdminRoutes.defenseStageEdit(stageId));
              } else {
                context.push(AdminRoutes.defenseStages);
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: _inkColor,
              side: BorderSide(color: _borderColor),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 30),
              textStyle: const TextStyle(fontSize: 11.5),
            ),
            child: const Text('Configure Stage'),
          ),
        ],
      ),
    );
  }

  Widget _buildPitEventRow(Map<String, dynamic> config) {
    final eventName = config['event_name']?.toString() ?? 'PIT Event';
    final panelWeight = config['panel_weight']?.toString() ?? '80';
    final peerWeight = config['peer_weight']?.toString() ?? '20';
    final isLocked = config['is_locked'] == true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _isDark
                  ? const Color(0xFF1E1B4B)
                  : const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.flag_rounded,
              size: 16,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventName,
                  style: TextStyle(
                    color: _inkColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Weights: $panelWeight% Panel / $peerWeight% Peer',
                  style: TextStyle(color: _mutedColor, fontSize: 12),
                ),
              ],
            ),
          ),
          if (isLocked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _isDark
                    ? const Color(0xFF3B181F)
                    : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Defenses Scheduled',
                style: TextStyle(
                  color: _isDark ? const Color(0xFFFCA5A5) : _maroon,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    required Widget child,
    String? description,
    String? actionLabel,
    VoidCallback? onActionTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.25 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: _inkColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: TextStyle(
                            color: _mutedColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (actionLabel != null)
                  OutlinedButton(
                    onPressed: onActionTap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _inkColor,
                      side: BorderSide(color: _borderColor),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 6),
                      minimumSize: const Size(0, 30),
                      textStyle: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(actionLabel),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: _borderColor),
          child,
        ],
      ),
    );
  }

  Widget _settingRow({required String label, required Widget child}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              color: _mutedColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _evaluationToggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
    VoidCallback? onHelpTap,
    String? helpTooltip,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: _panelBgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _inkColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (onHelpTap != null) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: helpTooltip ?? 'View Guide',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: onHelpTap,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.help_outline_rounded,
                              size: 15,
                              color: _mutedColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: _mutedColor,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: _isDark ? const Color(0xFFF87171) : _maroon,
          ),
        ],
      ),
    );
  }

  Future<void> _activateThisSemester(Map<String, dynamic> semester) async {
    final semesterId = int.tryParse(semester['id']?.toString() ?? '');
    if (semesterId == null) return;

    final notifier = ref.read(academicPeriodProvider.notifier);
    final preview = await notifier.fetchTransitionPreview(semesterId);
    if (!mounted || preview == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceColor,
        title: Text('Activate Semester', style: TextStyle(color: _inkColor)),
        content: Text(
          'Are you sure you want to set "${semester['label']}" as the active institutional semester?',
          style: TextStyle(color: _mutedColor),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _maroon,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Activate'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await notifier.activateSemester(semesterId);
      _loadData();
    }
  }

  Future<void> _deleteThisSemester(Map<String, dynamic> semester) async {
    final semesterId = int.tryParse(semester['id']?.toString() ?? '');
    if (semesterId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceColor,
        title: Text('Delete Semester', style: TextStyle(color: _inkColor)),
        content: Text(
          'Are you sure you want to delete this semester configuration?',
          style: TextStyle(color: _mutedColor),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await ref
          .read(academicPeriodProvider.notifier)
          .deleteSemester(semesterId);
      if (success && mounted) {
        if (widget.onBack != null) {
          widget.onBack!();
        } else if (context.canPop()) {
          context.pop();
        } else {
          context.go(AdminRoutes.academicPeriods);
        }
      }
    }
  }
}
