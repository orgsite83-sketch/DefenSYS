import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/academic_period_provider.dart';
import '../../../../services/admin/user_management_provider.dart';
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
    ref.read(userManagementProvider.notifier).fetchUsers();
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
    final userState = ref.watch(userManagementProvider);
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
                    return _buildPitTab(
                        semester, state.isSaving, userState.users);
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

  Map<String, dynamic>? _findPitLeadForYear(
    List<Map<String, dynamic>> users,
    String yearKey,
  ) {
    for (final user in users) {
      final isLead = user['is_pit_lead'] == true ||
          (user['roles'] is Map && user['roles']['is_pit_lead'] == true);
      if (!isLead) continue;

      final rawYear = (user['pit_lead_year'] ??
              (user['roles'] is Map ? user['roles']['pit_lead_year'] : null))
          ?.toString()
          .trim()
          .toLowerCase() ??
          '';

      if (yearKey == '1st Year') {
        if (rawYear.contains('1st') ||
            rawYear.contains('first') ||
            rawYear.contains('101')) {
          return user;
        }
      } else if (yearKey == '2nd Year') {
        if (rawYear.contains('2nd') ||
            rawYear.contains('second') ||
            rawYear.contains('201')) {
          return user;
        }
      } else if (yearKey == '3rd Year') {
        if (rawYear.contains('3rd') ||
            rawYear.contains('third') ||
            rawYear.contains('301')) {
          return user;
        }
      }
    }
    return null;
  }

  String _getUserDisplayName(Map<String, dynamic> user) {
    final first = (user['first_name'] ?? '').toString().trim();
    final last = (user['last_name'] ?? '').toString().trim();
    if (first.isNotEmpty || last.isNotEmpty) {
      return '$first $last'.trim();
    }
    final name = (user['name'] ?? user['username'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    return (user['email'] ?? 'Faculty Lead').toString().trim();
  }

  bool _eventMatchesCohort(Map<String, dynamic> config, String yearKey) {
    final name = (config['event_name']?.toString() ?? '').toLowerCase();
    final code = (config['event_code']?.toString() ?? '').toLowerCase();
    final combined = '$name $code';

    if (yearKey == '1st Year') {
      return combined.contains('1st') ||
          combined.contains('first') ||
          combined.contains('101') ||
          combined.contains('concept');
    } else if (yearKey == '2nd Year') {
      return combined.contains('2nd') ||
          combined.contains('second') ||
          combined.contains('201') ||
          combined.contains('design') ||
          combined.contains('architect');
    } else if (yearKey == '3rd Year') {
      return combined.contains('3rd') ||
          combined.contains('third') ||
          combined.contains('301') ||
          combined.contains('readiness') ||
          combined.contains('pre-capstone');
    }
    return false;
  }

  Future<void> _togglePitEventPeerEval(
    Map<String, dynamic> config,
    bool newValue,
  ) async {
    if (config['is_locked'] == true) {
      showValidationToast(
        context,
        config['lock_reason']?.toString() ??
            'Peer evaluation settings are locked because defenses are scheduled.',
      );
      return;
    }

    final previousValue = config['peer_grading_enabled'] != false;
    final eventName = config['event_name']?.toString() ?? 'PIT Event';

    setState(() {
      config['peer_grading_enabled'] = newValue;
    });

    final payload = <String, dynamic>{
      if (widget.semesterId != null) 'semester_id': widget.semesterId,
      'event_name': config['event_name'],
      if (config['event_code'] != null) 'event_code': config['event_code'],
      'panel_weight': config['panel_weight'] is int
          ? config['panel_weight']
          : int.tryParse(config['panel_weight']?.toString() ?? '80') ?? 80,
      'peer_weight': config['peer_weight'] is int
          ? config['peer_weight']
          : int.tryParse(config['peer_weight']?.toString() ?? '20') ?? 20,
      if (config['panel_rubric_id'] != null)
        'panel_rubric_id': config['panel_rubric_id'],
      if (config['peer_rubric_id'] != null)
        'peer_rubric_id': config['peer_rubric_id'],
      if (config['archive_file_template'] != null)
        'archive_file_template': config['archive_file_template'],
      'deliverables': config['deliverables'] ?? [],
      'peer_grading_enabled': newValue,
    };

    final success = await ref
        .read(defenseSchedulerProvider.notifier)
        .savePitEventConfig(payload);

    if (mounted) {
      if (success) {
        showSuccessToast(
          context,
          newValue
              ? 'Peer evaluation enabled for $eventName.'
              : 'Peer evaluation disabled for $eventName.',
        );
      } else {
        setState(() {
          config['peer_grading_enabled'] = previousValue;
        });
        final err = ref.read(defenseSchedulerProvider).error ??
            'Failed to update peer evaluation setting.';
        showErrorToast(context, err);
      }
    }
  }

  Widget _buildPitTab(
    Map<String, dynamic> semester,
    bool isSaving,
    List<Map<String, dynamic>> users,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPitGovernanceBanner(),
        const SizedBox(height: 20),
        _buildPitPolicyOverviewCard(),
        const SizedBox(height: 24),
        ..._buildCohortCards(users, isSaving),
      ],
    );
  }

  Widget _buildPitGovernanceBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isDark ? const Color(0xFF3730A3) : const Color(0xFFC7D2FE),
          width: 1.2,
        ),
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
                  color: _isDark
                      ? const Color(0xFF1E1B4B)
                      : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 20,
                  color: Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Faculty Lead Ownership & Admin Oversight',
                            style: TextStyle(
                              color: _inkColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _isDark
                                ? const Color(0xFF312E81)
                                : const Color(0xFFE0E7FF),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Governance Model',
                            style: TextStyle(
                              color: _isDark
                                  ? const Color(0xFFA5B4FC)
                                  : const Color(0xFF4338CA),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Operational responsibility is delegated to assigned PIT Year Coordinators. Admins maintain supervisory compliance and master review authorizations.',
                      style: TextStyle(
                        color: _mutedColor,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () => context.push(AdminRoutes.users),
                icon: const Icon(Icons.manage_accounts_outlined, size: 16),
                label: const Text('Manage PIT Leads in User Management ↗'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _inkColor,
                  side: BorderSide(color: _borderColor),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.person_pin_rounded,
                          size: 18, color: Color(0xFF2563EB)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PIT Coordinator (Faculty Lead)',
                              style: TextStyle(
                                color: _inkColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Operationally owns student team formation, assigns panel evaluators, oversees pitch deliverables, and guides defense schedules.',
                              style: TextStyle(
                                  color: _mutedColor,
                                  fontSize: 11.5,
                                  height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _panelBgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.security_rounded,
                          size: 18, color: Color(0xFF10B981)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Administrator (Institutional Oversight)',
                              style: TextStyle(
                                color: _inkColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Authorizes academic term activation, assigns faculty leads, audits grading completeness, and toggles event peer review permissions.',
                              style: TextStyle(
                                  color: _mutedColor,
                                  fontSize: 11.5,
                                  height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPitPolicyOverviewCard() {
    return _card(
      title: '📌 PIT Cohort Structure (1st–3rd Year)',
      description:
          'Project in Lieu of Thesis / Practicum milestone demo structure & evaluation rubric weights',
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
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
                  const SizedBox(height: 12),
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
            const SizedBox(width: 24),
            Expanded(
              flex: 2,
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
                                style:
                                    TextStyle(color: _mutedColor, fontSize: 11),
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
                                style:
                                    TextStyle(color: _mutedColor, fontSize: 11),
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: () =>
                        showPeerGradingHelpDialog(context, isPit: true),
                    icon: const Icon(Icons.help_outline_rounded, size: 15),
                    label: const Text('View PIT Peer Evaluation Guide'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _inkColor,
                      side: BorderSide(color: _borderColor),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCohortCards(
    List<Map<String, dynamic>> users,
    bool isSaving,
  ) {
    final cohorts = [
      {
        'key': '1st Year',
        'title': '1st Year Cohort — CS 101',
        'course': 'Concept Pitch & Problem Formulation',
        'desc':
            'Freshman teams formulate problem statements, persona interviews, and initial technical feasibility.',
      },
      {
        'key': '2nd Year',
        'title': '2nd Year Cohort — CS 201',
        'course': 'System Architecture & Design Prototype',
        'desc':
            'Sophomore teams present system architecture, ER diagrams, data flow models, and interactive UI mockups.',
      },
      {
        'key': '3rd Year',
        'title': '3rd Year Cohort — CS 301',
        'course': 'Capstone Readiness & Prototype Validation',
        'desc':
            'Junior teams validate functional MVPs and readiness for Senior Capstone transition.',
      },
    ];

    final matchedEventIds = <dynamic>{};
    final cohortWidgets = <Widget>[];

    for (final cohort in cohorts) {
      final key = cohort['key'] as String;
      final lead = _findPitLeadForYear(users, key);
      final cohortEvents = _pitEventConfigs.where((c) {
        final matches = _eventMatchesCohort(c, key);
        if (matches) matchedEventIds.add(c['id'] ?? c['event_name']);
        return matches;
      }).toList();

      cohortWidgets.add(
        _card(
          title: cohort['title'] as String,
          description: '${cohort['course']} • ${cohort['desc']}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _buildCohortLeadBanner(lead, key),
              ),
              if (_loadingPitConfigs)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(color: _maroon),
                  ),
                )
              else if (cohortEvents.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _panelBgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _borderColor),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 16, color: _mutedColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No milestone pitch events scheduled for $key yet. The assigned PIT Coordinator manages pitch events and defense schedules for this cohort.',
                            style: TextStyle(
                              color: _mutedColor,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...cohortEvents.map(
                  (config) => _buildCohortEventItem(config, isSaving),
                ),
            ],
          ),
        ),
      );
      cohortWidgets.add(const SizedBox(height: 20));
    }

    // Unmatched events (if any)
    final unmatched = _pitEventConfigs
        .where((c) => !matchedEventIds.contains(c['id'] ?? c['event_name']))
        .toList();
    if (unmatched.isNotEmpty) {
      cohortWidgets.add(
        _card(
          title: '📌 Additional PIT Events',
          description:
              'Events that are not specifically mapped to a 1st, 2nd, or 3rd year cohort title',
          child: Column(
            children: unmatched
                .map((config) => _buildCohortEventItem(config, isSaving))
                .toList(),
          ),
        ),
      );
    }

    return cohortWidgets;
  }

  Widget _buildCohortLeadBanner(Map<String, dynamic>? lead, String yearKey) {
    if (lead != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _isDark
              ? const Color(0xFF1E293B).withValues(alpha: 0.5)
              : const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isDark ? const Color(0xFF334155) : const Color(0xFFBBF7D0),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: _isDark
                  ? const Color(0xFF0F172A)
                  : const Color(0xFFDCFCE7),
              child: const Icon(
                Icons.person_rounded,
                size: 15,
                color: Color(0xFF16A34A),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  Text(
                    'PIT Coordinator: ',
                    style: TextStyle(
                      color: _mutedColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      _getUserDisplayName(lead),
                      style: TextStyle(
                        color: _inkColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (lead['email'] != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '(${lead['email']})',
                        style: TextStyle(
                          color: _mutedColor,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => context.push(AdminRoutes.users),
              icon: const Icon(Icons.open_in_new_rounded, size: 13),
              label: const Text('Coordinator Profile'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _isDark
            ? const Color(0xFF3B2912).withValues(alpha: 0.4)
            : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: Color(0xFFD97706),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No PIT Coordinator assigned for $yearKey. Assign a faculty coordinator in User Management to manage this cohort.',
              style: TextStyle(
                color: _isDark
                    ? const Color(0xFFFDE68A)
                    : const Color(0xFF92400E),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => context.push(AdminRoutes.users),
            icon: const Icon(Icons.person_add_outlined, size: 13),
            label: const Text('Assign Lead ↗'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _isDark
                  ? const Color(0xFFFDE68A)
                  : const Color(0xFF92400E),
              side: BorderSide(
                color: _isDark
                    ? const Color(0xFFB45309)
                    : const Color(0xFFF59E0B),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 30),
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCohortEventItem(
    Map<String, dynamic> config,
    bool isSaving,
  ) {
    final eventName = config['event_name']?.toString() ?? 'PIT Event';
    final panelWeight = config['panel_weight']?.toString() ?? '80';
    final peerWeight = config['peer_weight']?.toString() ?? '20';
    final isLocked = config['is_locked'] == true;
    final peerEnabled = config['peer_grading_enabled'] != false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
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
          // Event title and weights
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        eventName,
                        style: TextStyle(
                          color: _inkColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isLocked) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: _isDark
                              ? const Color(0xFF3B181F)
                              : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_rounded,
                                size: 11,
                                color: _isDark
                                    ? const Color(0xFFFCA5A5)
                                    : _maroon),
                            const SizedBox(width: 4),
                            Text(
                              'Defenses Scheduled (Locked)',
                              style: TextStyle(
                                color: _isDark
                                    ? const Color(0xFFFCA5A5)
                                    : _maroon,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Weights: $panelWeight% Panel / $peerWeight% Peer',
                  style: TextStyle(color: _mutedColor, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Interactive Peer Evaluation Switch
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _panelBgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Peer Evaluation',
                      style: TextStyle(
                        color: _inkColor,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: peerEnabled
                                ? const Color(0xFF10B981)
                                : _mutedColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          peerEnabled ? 'OPEN' : 'CLOSED',
                          style: TextStyle(
                            color: peerEnabled
                                ? (_isDark
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF047857))
                                : _mutedColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: isLocked
                      ? (config['lock_reason']?.toString() ??
                          'Locked: Defenses scheduled')
                      : (peerEnabled
                          ? 'Click to turn off student peer evaluation for this event'
                          : 'Click to turn on student peer evaluation for this event'),
                  child: Switch.adaptive(
                    value: peerEnabled,
                    activeColor: const Color(0xFF10B981),
                    onChanged: isSaving
                        ? null
                        : (val) => _togglePitEventPeerEval(config, val),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
