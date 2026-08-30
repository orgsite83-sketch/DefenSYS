import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/system_audit_provider.dart';
import '../../../../services/auth_provider.dart';
import '../../../../services/academic_period_provider.dart';
import '../../../../services/student_teams_provider.dart';
import '../../../../services/reports_provider.dart';
import '../../../../services/defense/defense_stages_provider.dart';
import '../../../../services/grading/grade_center_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/feedback/empty_state.dart';
import '../widgets/defensys_admin_shell.dart';

class AuditComplianceScreen extends ConsumerStatefulWidget {
  const AuditComplianceScreen({super.key});

  @override
  ConsumerState<AuditComplianceScreen> createState() =>
      _AuditComplianceScreenState();
}

class _AuditComplianceScreenState extends ConsumerState<AuditComplianceScreen> {
  bool _didInitialFetch = false;
  int _selectedTabIndex = 0;
  final _searchController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();

  // Report Center Form Controllers & States
  String? _selectedSemesterId;
  String? _selectedTeamId;
  String? _selectedStudentId;
  String _selectedLevel = '';
  String _selectedYearLevel = '';
  String _selectedRole = '';
  final _reportStartDateController = TextEditingController();
  final _reportEndDateController = TextEditingController();
  String _reportCategoryFilter = '';
  String _selectedScope = '';
  String _reportTrackFilter = '';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndFetchAudit(ref.read(authProvider));
    });
  }

  void _checkAndFetchAudit(AuthState authState) {
    if (authState.isRestoring) return;
    if (_didInitialFetch) return;

    final user = authState.user;
    final isAdmin = user?['role']?.toString() == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;
    final isPitInstructor = user?['is_pit_instructor'] == true;
    final canViewAudit = isAdmin || isPitLead;

    _didInitialFetch = true;

    if (canViewAudit) {
      ref.read(systemAuditProvider.notifier).fetch();
    }

    if (isPitLead || isPitInstructor) {
      if (mounted && _selectedScope.isEmpty) {
        setState(() {
          _selectedScope = 'pit';
          _selectedLevel = 'pit';
        });
      }
    }

    // Load periods, teams, defense stages, and PIT events dynamically for Report dropdowns
    ref.read(academicPeriodProvider.notifier).fetchPeriods();
    ref.read(studentTeamsProvider.notifier).fetchTeams();
    ref.read(defenseStagesProvider.notifier).fetchStages();
    ref.read(gradeCenterProvider.notifier).fetchGrades();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _reportStartDateController.dispose();
    _reportEndDateController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(
      BuildContext context, TextEditingController controller, Function(String) onSaved) async {
    DateTime initial = DateTime.now();
    if (controller.text.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(controller.text.trim());
      if (parsed != null) initial = parsed;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: DefensysTokens.maroon,
              onPrimary: Colors.white,
              onSurface: DefensysTokens.textDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formatted =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      controller.text = formatted;
      onSaved(formatted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (previous, next) {
      _checkAndFetchAudit(next);
    });

    if (authState.isRestoring) {
      return SingleChildScrollView(
        padding: DefensysUi.contentPadding,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 80),
          child: Center(
            child: CircularProgressIndicator(color: DefensysTokens.maroon),
          ),
        ),
      );
    }

    final user = authState.user;
    final isAdmin = user?['role']?.toString() == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;
    final canViewAudit = isAdmin || isPitLead;

    if (!canViewAudit) {
      return SingleChildScrollView(
        padding: DefensysUi.contentPadding,
        child: _buildReportCenter(context),
      );
    }

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sleek Executive Segmented Control Bar
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
              border: Border.all(color: DefensysTokens.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: _SegmentTabButton(
                    label: 'Audit Trail Register',
                    subtitle: 'Realtime compliance & change logs',
                    badgeLabel: 'Live Logs',
                    icon: Icons.shield_outlined,
                    isSelected: _selectedTabIndex == 0,
                    onTap: () {
                      if (_selectedTabIndex != 0) {
                        setState(() => _selectedTabIndex = 0);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SegmentTabButton(
                    label: 'Report Export Center',
                    subtitle: 'Official PDF audit documents',
                    badgeLabel: 'PDF Center',
                    icon: Icons.summarize_outlined,
                    isSelected: _selectedTabIndex == 1,
                    onTap: () {
                      if (_selectedTabIndex != 1) {
                        setState(() => _selectedTabIndex = 1);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_selectedTabIndex == 0)
            _buildAuditRegisterTab(context)
          else
            _buildReportCenter(context),
        ],
      ),
    );
  }

  void _onAcademicScopeChanged(String? value) {
    if (value == null) return;
    String track = '';
    String yearLevel = '';
    if (value == 'capstone') {
      track = 'capstone';
    } else if (value == 'pit_all') {
      track = 'pit';
    } else if (value == 'pit_1') {
      track = 'pit';
      yearLevel = '1st Year';
    } else if (value == 'pit_2') {
      track = 'pit';
      yearLevel = '2nd Year';
    } else if (value == 'pit_3') {
      track = 'pit';
      yearLevel = '3rd Year';
    } else if (value == 'pit_4') {
      track = 'pit';
      yearLevel = '4th Year';
    }
    ref.read(systemAuditProvider.notifier).setTrack(track);
    ref.read(systemAuditProvider.notifier).setYearLevel(yearLevel);
  }

  String _getCurrentAcademicScope(SystemAuditState state) {
    if (state.track == 'capstone') return 'capstone';
    if (state.track == 'pit') {
      if (state.yearLevel == '1st Year') return 'pit_1';
      if (state.yearLevel == '2nd Year') return 'pit_2';
      if (state.yearLevel == '3rd Year') return 'pit_3';
      if (state.yearLevel == '4th Year') return 'pit_4';
      return 'pit_all';
    }
    return 'all';
  }

  Widget _buildAuditRegisterTab(BuildContext context) {
    final state = ref.watch(systemAuditProvider);
    final user = ref.watch(authProvider).user;
    final isAdmin = user?['role']?.toString() == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;
    final selectedLog =
        state.selectedLog ?? (state.logs.isNotEmpty ? state.logs.first : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DefensysPageHeader(
          icon: Icons.verified_user_outlined,
          title: 'Audit Trail & Evidence Review',
          subtitle:
              'Official compliance trail for institutional actions, grade updates, and access changes.',
          actions: _AuditReadinessBadge(state: state),
        ),
        const SizedBox(height: 20),
        _EvidenceStatusCards(state: state),
        const SizedBox(height: 20),
        _AuditFilterToolbar(
          state: state,
          isAdmin: isAdmin,
          isPitLead: isPitLead,
          user: user,
          searchController: _searchController,
          startDateController: _startDateController,
          endDateController: _endDateController,
          currentScope: _getCurrentAcademicScope(state),
          onScopeChanged: _onAcademicScopeChanged,
          onSelectStartDate: () => _selectDate(context, _startDateController, (val) {
            ref.read(systemAuditProvider.notifier).setStartDate(val);
            ref.read(systemAuditProvider.notifier).fetch();
          }),
          onSelectEndDate: () => _selectDate(context, _endDateController, (val) {
            ref.read(systemAuditProvider.notifier).setEndDate(val);
            ref.read(systemAuditProvider.notifier).fetch();
          }),
          onQuickExport: () => _quickExportAuditPDF(state),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1100;
            final table = _AuditTrailTable(state: state);
            final details = _EvidenceDetailsPanel(log: selectedLog);

            if (!wide) {
              return Column(
                children: [table, const SizedBox(height: 20), details],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: table),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: details),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _quickExportAuditPDF(SystemAuditState auditState) async {
    final queryParams = <String, String>{
      if (auditState.category.isNotEmpty) 'category': auditState.category,
      if (auditState.reviewStatus.isNotEmpty) 'review_status': auditState.reviewStatus,
      if (auditState.action.isNotEmpty) 'action': auditState.action,
      if (auditState.search.isNotEmpty) 'search': auditState.search,
      if (auditState.startDate.isNotEmpty) 'start_date': auditState.startDate,
      if (auditState.endDate.isNotEmpty) 'end_date': auditState.endDate,
      if (auditState.track.isNotEmpty) 'track': auditState.track,
      if (auditState.yearLevel.isNotEmpty) 'year_level': auditState.yearLevel,
    };

    final success = await ref.read(reportsProvider.notifier).downloadReport(
      endpoint: 'audit-trail/',
      queryParams: queryParams,
      defaultFilename: 'DefenSYS_Audit_Register.pdf',
    );

    _showDownloadResultToast(success);
  }

  Widget _buildReportCenter(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isAdmin = user?['role']?.toString() == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;

    final List<Map<String, dynamic>> gradingReports = [
      {
        'title': 'Team Grade Report Card',
        'desc': 'Detailed grading summary and criterion assessment scores from panelists, adviser, and peers.',
        'icon': Icons.badge_outlined,
        'endpoint': 'team-grade',
        'tag': 'Grades',
        'meta': 'PDF • Team Breakdown',
        'paramHint': 'Requires Team Selection',
      },
      {
        'title': 'Individual Student Grade Audit Card',
        'desc': 'Official confidential evaluation card detailing individual student performance, peer review contribution, panel remarks, and certification seal.',
        'icon': Icons.person_outline,
        'endpoint': 'individual-grade',
        'tag': 'Audit Slip',
        'meta': 'PDF • Individual Breakdown',
        'paramHint': 'Requires Student Candidate',
      },
      {
        'title': 'Capstone Stage Grade Sheet',
        'desc': 'Official compiled grade sheet for a specific Capstone defense stage (Concept, Outline, Pre-Oral, Final).',
        'icon': Icons.school_outlined,
        'endpoint': 'semester-grades',
        'scope': 'capstone',
        'tag': 'Capstone',
        'meta': 'PDF • Stage Matrix',
        'paramHint': 'Capstone Stage Scope',
      },
      {
        'title': 'PIT Event Grade Sheet',
        'desc': 'Official compiled grade sheet for a specific Project in IT (PIT) event or year-level showcase.',
        'icon': Icons.event_available_outlined,
        'endpoint': 'semester-grades',
        'scope': 'pit',
        'tag': 'PIT Events',
        'meta': 'PDF • Event Matrix',
        'paramHint': 'PIT Event Scope',
      },
      {
        'title': 'Semester Grade Summary',
        'desc': 'Compilation sheet of all student teams and final pass/fail results for the semester across all scopes.',
        'icon': Icons.grade_outlined,
        'endpoint': 'semester-grades',
        'tag': 'Summary',
        'meta': 'PDF • Official Roster',
        'paramHint': 'Semester & Scope Filter',
      },
    ];

    final List<Map<String, dynamic>> operationsReports = [
      {
        'title': 'Defense Schedule Summary',
        'desc': 'Compiled list of scheduled defense events, panels, times, and venue rooms.',
        'icon': Icons.calendar_month_outlined,
        'endpoint': 'defense-schedules',
        'tag': 'Schedule',
        'meta': 'PDF • Timetable',
        'paramHint': 'Semester & Scope Filter',
      },
      {
        'title': 'Team Roster Report',
        'desc': 'Directory list of active student teams, project titles, leaders, and advisers.',
        'icon': Icons.groups_outlined,
        'endpoint': 'team-roster',
        'tag': 'Roster',
        'meta': 'PDF • Directory',
        'paramHint': 'Semester & Level Filter',
      },
    ];

    final List<Map<String, dynamic>> governanceReports = [
      if (isAdmin)
        {
          'title': 'User Directory',
          'desc': 'Complete list of registered accounts in the portal filtered by role and status.',
          'icon': Icons.person_search_outlined,
          'endpoint': 'user-directory',
          'tag': 'Accounts',
          'meta': 'PDF • System Users',
          'paramHint': 'Role & Status Filter',
        },
      if (isAdmin || isPitLead)
        {
          'title': 'Audit Trail Export',
          'desc': 'Compliance log register documenting all high-impact actions and access changes.',
          'icon': Icons.receipt_long_outlined,
          'endpoint': 'audit-trail',
          'tag': 'Compliance',
          'meta': 'PDF • Change Logs',
          'paramHint': 'Date Range & Category Filter',
        },
    ];

    final totalReports = gradingReports.length + operationsReports.length + governanceReports.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DefensysPageHeader(
          icon: Icons.summarize_outlined,
          title: 'Report Export Center',
          subtitle: 'Generate and download official compliance PDF reports for academic audits.',
          actions: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
              border: Border.all(color: DefensysTokens.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: DefensysTokens.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$totalReports Reports Ready for PDF Export',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.textDark,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Section 1: Academic Grading & Evaluation
        _buildReportCategoryHeader(
          title: 'ACADEMIC GRADING & EVALUATION',
          subtitle: 'Official defense grades, individual evaluation slips, and semester compilation rosters.',
          icon: Icons.assignment_turned_in_outlined,
          count: gradingReports.length,
        ),
        const SizedBox(height: 12),
        _buildReportCardsGrid(gradingReports),
        const SizedBox(height: 28),

        // Section 2: Defense Schedules & Team Rosters
        _buildReportCategoryHeader(
          title: 'DEFENSE OPERATIONS & ROSTERS',
          subtitle: 'Defense timetable schedules, panel room assignments, and official team directories.',
          icon: Icons.event_note_outlined,
          count: operationsReports.length,
        ),
        const SizedBox(height: 12),
        _buildReportCardsGrid(operationsReports),
        const SizedBox(height: 28),

        // Section 3: Governance & System Compliance
        if (governanceReports.isNotEmpty) ...[
          _buildReportCategoryHeader(
            title: 'GOVERNANCE & SYSTEM COMPLIANCE',
            subtitle: 'Institutional audit registers, evidence logs, and system account directories.',
            icon: Icons.verified_user_outlined,
            count: governanceReports.length,
          ),
          const SizedBox(height: 12),
          _buildReportCardsGrid(governanceReports),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _buildReportCategoryHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required int count,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: DefensysTokens.maroon.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
          ),
          child: Icon(icon, color: DefensysTokens.maroon, size: 16),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: DefensysTokens.textDark,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.steelGrey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11.5,
                color: DefensysTokens.steelGrey,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReportCardsGrid(List<Map<String, dynamic>> reports) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 1150
            ? 3
            : constraints.maxWidth >= 720
                ? 2
                : 1;

        if (crossAxisCount == 1) {
          return Column(
            children: reports
                .map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildReportCatalogCard(r),
                    ))
                .toList(),
          );
        }

        // Chunk reports into rows for clean grid layout
        final rows = <Widget>[];
        for (var i = 0; i < reports.length; i += crossAxisCount) {
          final rowItems = reports.skip(i).take(crossAxisCount).toList();
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < crossAxisCount; j++) ...[
                  if (j > 0) const SizedBox(width: 16),
                  Expanded(
                    child: j < rowItems.length
                        ? _buildReportCatalogCard(rowItems[j])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
          if (i + crossAxisCount < reports.length) {
            rows.add(const SizedBox(height: 16));
          }
        }

        return Column(children: rows);
      },
    );
  }

  Widget _buildReportCatalogCard(Map<String, dynamic> report) {
    final title = report['title'] as String;
    final desc = report['desc'] as String;
    final icon = report['icon'] as IconData;
    final tag = report['tag'] as String;
    final paramHint = report['paramHint'] as String? ?? 'PDF Document';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        child: InkWell(
          onTap: () => _openReportExportDialog(context, report),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: DefensysTokens.maroon.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      ),
                      child: Icon(icon, color: DefensysTokens.maroon, size: 20),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: DefensysTokens.gold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                      ),
                      child: Text(
                        tag,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: DefensysTokens.darkGold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Report Title
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.textDark,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),

                // Description
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: DefensysTokens.steelGrey,
                    height: 1.45,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 18),

                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 14),

                // Footer Row: Param Hint & Action Button
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.tune_rounded, size: 13, color: DefensysTokens.steelGrey),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              paramHint,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: DefensysTokens.steelGrey,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.download_rounded, size: 14),
                      label: const Text('Export PDF'),
                      style: FilledButton.styleFrom(
                        backgroundColor: DefensysTokens.maroon,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => _openReportExportDialog(context, report),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the Dedicated Export Configuration Dialog
  void _openReportExportDialog(BuildContext context, Map<String, dynamic> report) {
    final teamsState = ref.read(studentTeamsProvider);
    final academicState = ref.read(academicPeriodProvider);
    final defenseStagesState = ref.read(defenseStagesProvider);
    final gradeCenterState = ref.read(gradeCenterProvider);

    // Build combined students list from team members (primary) and unassigned students
    final Map<String, Map<String, dynamic>> studentMetaMap = {};
    final Map<String, Map<String, dynamic>> allStudentsMap = {};

    for (final team in teamsState.teams) {
      final sec = team['section']?.toString() ?? team['year_level']?.toString();
      final leader = team['leader'] as Map<String, dynamic>?;
      if (leader != null) {
        final id = leader['id']?.toString();
        if (id != null) {
          allStudentsMap[id] = leader;
          studentMetaMap[id] = {
            'teamName': team['name'],
            'projectTitle': team['project_title'],
            'section': sec,
          };
        }
      }

      final members = team['members'] as List<dynamic>?;
      if (members != null) {
        for (final m in members) {
          if (m is Map<String, dynamic>) {
            final mId = m['id']?.toString();
            if (mId != null) {
              allStudentsMap[mId] = m;
              studentMetaMap[mId] = {
                'teamName': team['name'],
                'projectTitle': team['project_title'],
                'section': sec,
              };
            }
          }
        }
      }
    }

    // If no team memberships, add raw students
    for (final st in teamsState.students) {
      final sId = st['id']?.toString();
      if (sId != null && !allStudentsMap.containsKey(sId)) {
        allStudentsMap[sId] = st;
        studentMetaMap[sId] = {
          'teamName': 'Unassigned',
          'projectTitle': null,
          'section': null,
        };
      }
    }

    final List<Map<String, dynamic>> allStudentsList = allStudentsMap.values.toList();

    // Extract student sections & counts
    final Set<String> studentSectionsSet = {};
    final Map<String, int> studentSectionCounts = {};
    for (final meta in studentMetaMap.values) {
      final sec = meta['section'] as String?;
      if (sec != null && sec.trim().isNotEmpty) {
        studentSectionsSet.add(sec.trim());
        studentSectionCounts[sec.trim()] = (studentSectionCounts[sec.trim()] ?? 0) + 1;
      }
    }
    final List<String> studentSections = studentSectionsSet.toList()..sort();

    // Extract team sections & counts
    final Set<String> teamSectionsSet = {};
    final Map<String, int> teamSectionCounts = {};
    for (final team in teamsState.teams) {
      final sec = team['section']?.toString() ?? team['year_level']?.toString();
      if (sec != null && sec.trim().isNotEmpty) {
        teamSectionsSet.add(sec.trim());
        teamSectionCounts[sec.trim()] = (teamSectionCounts[sec.trim()] ?? 0) + 1;
      }
    }
    final List<String> teamSections = teamSectionsSet.toList()..sort();

    final List<Map<String, dynamic>> capstoneStages = [];
    for (final s in defenseStagesState.stages) {
      final label = s['label']?.toString() ?? s['name']?.toString() ?? '';
      if (label.trim().isNotEmpty) {
        capstoneStages.add({
          'id': s['id'],
          'label': label.trim(),
          'sequence': s['sequence_order'] ?? s['display_order'] ?? s['sequence'],
        });
      }
    }

    final List<Map<String, dynamic>> pitEvents = [];
    for (final evt in gradeCenterState.pitEvents) {
      final name = evt['event_name']?.toString() ?? evt['name']?.toString() ?? evt['label']?.toString() ?? '';
      if (name.trim().isNotEmpty) {
        pitEvents.add({
          'id': evt['id'],
          'event_name': name.trim(),
          'year_level': evt['year_level'],
        });
      }
    }
    if (pitEvents.isEmpty) {
      pitEvents.addAll([
        {'id': 1, 'event_name': '1st Year PIT'},
        {'id': 2, 'event_name': '2nd Year PIT'},
        {'id': 3, 'event_name': '3rd Year PIT'},
      ]);
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return _ReportExportConfigDialog(
          report: report,
          academicState: academicState,
          teamsState: teamsState,
          allStudents: allStudentsList,
          studentMetaMap: studentMetaMap,
          studentSections: studentSections,
          studentSectionCounts: studentSectionCounts,
          teamSections: teamSections,
          teamSectionCounts: teamSectionCounts,
          capstoneStages: capstoneStages,
          pitEvents: pitEvents,
          initialSemesterId: _selectedSemesterId ?? academicState.activeSemester?['id']?.toString(),
          initialStudentId: _selectedStudentId,
          initialTeamId: _selectedTeamId,
          initialScope: report['scope']?.toString() ?? _selectedScope,
          initialLevel: _selectedLevel,
          initialYearLevel: _selectedYearLevel,
          initialRole: _selectedRole,
          initialCategory: _reportCategoryFilter,
          initialTrack: _reportTrackFilter,
          initialStartDate: _reportStartDateController.text.trim(),
          initialEndDate: _reportEndDateController.text.trim(),
          onDownload: (params) async {
            return await _triggerReportDownload(
              report,
              studentId: params['studentId'],
              teamId: params['teamId'],
              semesterId: params['semesterId'],
              scope: params['scope'],
              stage: params['stage'],
              pitEvent: params['pitEvent'],
              level: params['level'],
              yearLevel: params['yearLevel'],
              role: params['role'],
              category: params['category'],
              track: params['track'],
              startDate: params['startDate'],
              endDate: params['endDate'],
              exportFormat: params['exportFormat'] ?? 'pdf',
            );
          },
          onFetchPreview: (params) async {
            return await _triggerReportPreview(
              report,
              studentId: params['studentId'],
              teamId: params['teamId'],
              semesterId: params['semesterId'],
              scope: params['scope'],
              stage: params['stage'],
              pitEvent: params['pitEvent'],
              level: params['level'],
              yearLevel: params['yearLevel'],
              role: params['role'],
              category: params['category'],
              track: params['track'],
              startDate: params['startDate'],
              endDate: params['endDate'],
            );
          },
          onOpenStudentPicker: (currId) => _showStudentPickerDialog(
            context: context,
            students: allStudentsList,
            studentMetaMap: studentMetaMap,
            sections: studentSections,
            sectionCounts: studentSectionCounts,
            currentSelectedId: currId,
          ),
          onOpenTeamPicker: (currId) => _showTeamPickerDialog(
            context: context,
            teams: teamsState.teams,
            sections: teamSections,
            sectionCounts: teamSectionCounts,
            currentSelectedId: currId,
          ),
        );
      },
    );
  }

  /// Fetches structured preview data for the Live Data Viewer
  Future<ReportPreviewData?> _triggerReportPreview(
    Map<String, dynamic> report, {
    String? studentId,
    String? teamId,
    String? semesterId,
    String? scope,
    String? stage,
    String? pitEvent,
    String? level,
    String? yearLevel,
    String? role,
    String? category,
    String? track,
    String? startDate,
    String? endDate,
  }) async {
    final endpoint = report['endpoint'] as String;
    final queryParams = <String, String>{};

    if (endpoint == 'team-grade') {
      final tId = teamId ?? _selectedTeamId;
      if (tId == null) return null;
      final fullEndpoint = 'team-grade/$tId/';
      return await ref.read(reportsProvider.notifier).fetchReportPreview(
        endpoint: fullEndpoint,
        queryParams: queryParams,
      );
    }

    if (endpoint == 'individual-grade') {
      final sId = studentId ?? _selectedStudentId;
      if (sId == null) return null;
      final semId = semesterId ?? _selectedSemesterId;
      if (semId != null && semId.isNotEmpty) {
        queryParams['semester_id'] = semId;
      }
      final fullEndpoint = 'individual-grade/$sId/';
      return await ref.read(reportsProvider.notifier).fetchReportPreview(
        endpoint: fullEndpoint,
        queryParams: queryParams,
      );
    }

    final semId = semesterId ?? _selectedSemesterId;
    if (endpoint == 'semester-grades' || endpoint == 'defense-schedules' || endpoint == 'team-roster') {
      if (semId != null && semId.isNotEmpty) {
        queryParams['semester_id'] = semId;
      }
    }

    final scp = scope ?? _selectedScope;
    if (endpoint == 'semester-grades' || endpoint == 'defense-schedules') {
      if (scp.isNotEmpty) queryParams['scope'] = scp;
      if (stage != null && stage.isNotEmpty) queryParams['stage'] = stage;
      if (pitEvent != null && pitEvent.isNotEmpty) queryParams['pit_event'] = pitEvent;
    }

    if (endpoint == 'team-roster') {
      final lvl = level ?? _selectedLevel;
      final yLvl = yearLevel ?? _selectedYearLevel;
      if (lvl.isNotEmpty) queryParams['level'] = lvl;
      if (yLvl.isNotEmpty) queryParams['year_level'] = yLvl;
    }

    if (endpoint == 'user-directory') {
      final r = role ?? _selectedRole;
      if (r.isNotEmpty) queryParams['role'] = r;
    }

    if (endpoint == 'audit-trail') {
      final cat = category ?? _reportCategoryFilter;
      final trk = track ?? _reportTrackFilter;
      final yLvl = yearLevel ?? _selectedYearLevel;
      final start = startDate ?? _reportStartDateController.text.trim();
      final end = endDate ?? _reportEndDateController.text.trim();
      if (cat.isNotEmpty) queryParams['category'] = cat;
      if (trk.isNotEmpty) queryParams['track'] = trk;
      if (yLvl.isNotEmpty) queryParams['year_level'] = yLvl;
      if (start.isNotEmpty) queryParams['start_date'] = start;
      if (end.isNotEmpty) queryParams['end_date'] = end;
    }

    return await ref.read(reportsProvider.notifier).fetchReportPreview(
      endpoint: '$endpoint/',
      queryParams: queryParams,
    );
  }

  /// Opens the Keyboard-Friendly Student Picker Modal Dialog
  Future<String?> _showStudentPickerDialog({
    required BuildContext context,
    required List<Map<String, dynamic>> students,
    required Map<String, Map<String, dynamic>> studentMetaMap,
    required List<String> sections,
    required Map<String, int> sectionCounts,
    String? currentSelectedId,
  }) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return _StudentPickerDialog(
          students: students,
          studentMetaMap: studentMetaMap,
          sections: sections,
          sectionCounts: sectionCounts,
          initialSelectedId: currentSelectedId,
        );
      },
    );
  }

  /// Opens the Keyboard-Friendly Team Picker Modal Dialog
  Future<String?> _showTeamPickerDialog({
    required BuildContext context,
    required List<Map<String, dynamic>> teams,
    required List<String> sections,
    required Map<String, int> sectionCounts,
    String? currentSelectedId,
  }) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return _TeamPickerDialog(
          teams: teams,
          sections: sections,
          sectionCounts: sectionCounts,
          initialSelectedId: currentSelectedId,
        );
      },
    );
  }

  Future<bool> _triggerReportDownload(
    Map<String, dynamic> report, {
    String? studentId,
    String? teamId,
    String? semesterId,
    String? scope,
    String? stage,
    String? pitEvent,
    String? level,
    String? yearLevel,
    String? role,
    String? category,
    String? track,
    String? startDate,
    String? endDate,
    String exportFormat = 'pdf',
  }) async {
    final endpoint = report['endpoint'] as String;
    final queryParams = <String, String>{};

    final ext = exportFormat == 'xlsx'
        ? '.xlsx'
        : exportFormat == 'csv'
            ? '.csv'
            : exportFormat == 'doc' || exportFormat == 'docx'
                ? '.doc'
                : '.pdf';

    if (endpoint == 'team-grade') {
      final tId = teamId ?? _selectedTeamId;
      if (tId == null) {
        showValidationToast(context, 'Please select a student team.');
        return false;
      }
      final fullEndpoint = 'team-grade/$tId/';

      final success = await ref.read(reportsProvider.notifier).downloadReport(
        endpoint: fullEndpoint,
        queryParams: queryParams,
        defaultFilename: 'DefenSYS_Team_Grade_Report$ext',
        exportFormat: exportFormat,
      );

      _showDownloadResultToast(success, exportFormat);
      return success;
    }

    if (endpoint == 'individual-grade') {
      final sId = studentId ?? _selectedStudentId;
      if (sId == null) {
        showValidationToast(context, 'Please select a student candidate.');
        return false;
      }
      final semId = semesterId ?? _selectedSemesterId;
      if (semId != null && semId.isNotEmpty) {
        queryParams['semester_id'] = semId;
      }
      final fullEndpoint = 'individual-grade/$sId/';

      final success = await ref.read(reportsProvider.notifier).downloadReport(
        endpoint: fullEndpoint,
        queryParams: queryParams,
        defaultFilename: 'DefenSYS_Individual_Grade_Audit$ext',
        exportFormat: exportFormat,
      );

      _showDownloadResultToast(success, exportFormat);
      return success;
    }

    final semId = semesterId ?? _selectedSemesterId;
    if (endpoint == 'semester-grades' || endpoint == 'defense-schedules' || endpoint == 'team-roster') {
      if (semId != null && semId.isNotEmpty) {
        queryParams['semester_id'] = semId;
      }
    }

    final scp = scope ?? _selectedScope;
    if (endpoint == 'semester-grades' || endpoint == 'defense-schedules') {
      if (scp.isNotEmpty) queryParams['scope'] = scp;
      if (stage != null && stage.isNotEmpty) queryParams['stage'] = stage;
      if (pitEvent != null && pitEvent.isNotEmpty) queryParams['pit_event'] = pitEvent;
    }

    if (endpoint == 'team-roster') {
      final lvl = level ?? _selectedLevel;
      final yLvl = yearLevel ?? _selectedYearLevel;
      if (lvl.isNotEmpty) queryParams['level'] = lvl;
      if (yLvl.isNotEmpty) queryParams['year_level'] = yLvl;
    }

    if (endpoint == 'user-directory') {
      final r = role ?? _selectedRole;
      if (r.isNotEmpty) queryParams['role'] = r;
    }

    if (endpoint == 'audit-trail') {
      final cat = category ?? _reportCategoryFilter;
      final trk = track ?? _reportTrackFilter;
      final yLvl = yearLevel ?? _selectedYearLevel;
      final start = startDate ?? _reportStartDateController.text.trim();
      final end = endDate ?? _reportEndDateController.text.trim();
      if (cat.isNotEmpty) queryParams['category'] = cat;
      if (trk.isNotEmpty) queryParams['track'] = trk;
      if (yLvl.isNotEmpty) queryParams['year_level'] = yLvl;
      if (start.isNotEmpty) queryParams['start_date'] = start;
      if (end.isNotEmpty) queryParams['end_date'] = end;
    }

    final success = await ref.read(reportsProvider.notifier).downloadReport(
      endpoint: '$endpoint/',
      queryParams: queryParams,
      defaultFilename: 'DefenSYS_${report['title'].toString().replaceAll(' ', '_')}$ext',
      exportFormat: exportFormat,
    );

    _showDownloadResultToast(success, exportFormat);
    return success;
  }

  void _showDownloadResultToast(bool success, [String format = 'pdf']) {
    if (!mounted) return;
    final error = ref.read(reportsProvider).error;
    final fmtUpper = format.toUpperCase();
    if (success) {
      showSuccessToast(context, '$fmtUpper report generated and downloaded successfully!');
    } else {
      showErrorToast(context, 'Failed to generate $fmtUpper: ${error ?? "Unknown error"}');
    }
  }
}

/// Helper function to get 2 initials from full name
String _extractInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts[0].isEmpty) return '?';
  if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
  return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
}

InputDecoration _reportInputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    isDense: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      borderSide: const BorderSide(color: DefensysTokens.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      borderSide: const BorderSide(color: DefensysTokens.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.5),
    ),
  );
}

/// Dialog: Student Candidate Picker with Search & Section Filters
class _StudentPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> students;
  final Map<String, Map<String, dynamic>> studentMetaMap;
  final List<String> sections;
  final Map<String, int> sectionCounts;
  final String? initialSelectedId;

  const _StudentPickerDialog({
    required this.students,
    required this.studentMetaMap,
    required this.sections,
    required this.sectionCounts,
    this.initialSelectedId,
  });

  @override
  State<_StudentPickerDialog> createState() => _StudentPickerDialogState();
}

class _StudentPickerDialogState extends State<_StudentPickerDialog> {
  final _searchController = TextEditingController();
  String _selectedSection = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = widget.students.where((s) {
      final sId = s['id']?.toString() ?? '';
      final meta = widget.studentMetaMap[sId];

      if (_selectedSection.isNotEmpty && meta?['section'] != _selectedSection) {
        return false;
      }

      if (query.isEmpty) return true;

      final name = (s['name'] ?? s['username'] ?? '').toString().toLowerCase();
      final username = (s['username'] ?? sId).toString().toLowerCase();
      final email = (s['email'] ?? '').toString().toLowerCase();
      final team = meta?['team'] as Map<String, dynamic>?;
      final teamName = (team?['name'] ?? '').toString().toLowerCase();
      final sec = (meta?['section'] ?? '').toString().toLowerCase();

      return name.contains(query) ||
          username.contains(query) ||
          sId.contains(query) ||
          email.contains(query) ||
          teamName.contains(query) ||
          sec.contains(query);
    }).toList();

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: DefensysTokens.border)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DefensysTokens.maroon.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                    ),
                    child: const Icon(Icons.person_search_rounded, color: DefensysTokens.maroon, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select Student Candidate',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${filtered.length} of ${widget.students.length} candidates available',
                          style: const TextStyle(fontSize: 11.5, color: DefensysTokens.steelGrey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: DefensysTokens.steelGrey),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Search Bar & Filter Chips
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search by student ID (e.g. 4011), name, team, section...',
                      hintStyle: const TextStyle(fontSize: 13, color: DefensysTokens.steelGrey),
                      prefixIcon: const Icon(Icons.search_rounded, color: DefensysTokens.steelGrey, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: const BorderSide(color: DefensysTokens.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: const BorderSide(color: DefensysTokens.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.5),
                      ),
                    ),
                  ),
                  if (widget.sections.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(
                            label: 'All Sections (${widget.students.length})',
                            isSelected: _selectedSection.isEmpty,
                            onTap: () => setState(() => _selectedSection = ''),
                          ),
                          const SizedBox(width: 6),
                          ...widget.sections.map((sec) {
                            final count = widget.sectionCounts[sec] ?? 0;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _buildFilterChip(
                                label: '$sec ($count)',
                                isSelected: _selectedSection == sec,
                                onTap: () => setState(() => _selectedSection = sec),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFF1F5F9)),

            // Candidates List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF1F5F9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.person_off_outlined, size: 36, color: DefensysTokens.steelGrey),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'No matching student candidates',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DefensysTokens.textDark),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Try adjusting your search keywords or resetting the section filter.',
                              style: TextStyle(fontSize: 12, color: DefensysTokens.steelGrey),
                              textAlign: TextAlign.center,
                            ),
                            if (_searchController.text.isNotEmpty || _selectedSection.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              TextButton.icon(
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('Reset Filters'),
                                style: TextButton.styleFrom(foregroundColor: DefensysTokens.maroon),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _selectedSection = '');
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      itemCount: filtered.length,
                      separatorBuilder: (ctx, i) => const SizedBox(height: 6),
                      itemBuilder: (ctx, i) {
                        final s = filtered[i];
                        final sId = s['id']?.toString() ?? '';
                        final meta = widget.studentMetaMap[sId];
                        final name = s['name'] ?? s['username'] ?? 'Student';
                        final username = s['username']?.toString() ?? sId;
                        final email = s['email']?.toString() ?? '';
                        final team = meta?['team'] as Map<String, dynamic>?;
                        final isLeader = meta?['isLeader'] == true;
                        final section = meta?['section'] as String?;
                        final isSelected = widget.initialSelectedId == sId;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(sId),
                            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? DefensysTokens.maroon.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                                border: Border.all(
                                  color: isSelected ? DefensysTokens.maroon : const Color(0xFFE2E8F0),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Initials Avatar
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: isSelected ? DefensysTokens.maroon : DefensysTokens.maroon.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      _extractInitials(name.toString()),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: isSelected ? Colors.white : DefensysTokens.maroon,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                name.toString(),
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                                                  color: DefensysTokens.textDark,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: isSelected ? DefensysTokens.maroon : const Color(0xFF1E293B),
                                                borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                              ),
                                              child: Text(
                                                'ID: $username',
                                                style: const TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            if (isLeader) ...[
                                              const SizedBox(width: 5),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: DefensysTokens.gold.withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                                ),
                                                child: const Text(
                                                  'LEADER',
                                                  style: TextStyle(
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: DefensysTokens.darkGold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            if (team != null) ...[
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: DefensysTokens.maroon.withValues(alpha: 0.08),
                                                  borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.groups_rounded, size: 11, color: DefensysTokens.maroon),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      team['name']?.toString() ?? 'Team',
                                                      style: const TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.w700,
                                                        color: DefensysTokens.maroon,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ] else ...[
                                              const Text(
                                                'No Team Assigned',
                                                style: TextStyle(fontSize: 11, color: DefensysTokens.steelGrey),
                                              ),
                                            ],
                                            if (section != null && section.isNotEmpty) ...[
                                              const SizedBox(width: 6),
                                              const Text('•', style: TextStyle(color: DefensysTokens.steelGrey)),
                                              const SizedBox(width: 6),
                                              Text(
                                                section,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: DefensysTokens.steelGrey,
                                                ),
                                              ),
                                            ],
                                            if (email.isNotEmpty) ...[
                                              const SizedBox(width: 6),
                                              const Text('•', style: TextStyle(color: DefensysTokens.steelGrey)),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  email,
                                                  style: const TextStyle(fontSize: 11, color: DefensysTokens.steelGrey),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Radio Checkmark
                                  const SizedBox(width: 10),
                                  Icon(
                                    isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                    color: isSelected ? DefensysTokens.maroon : const Color(0xFFCBD5E1),
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? DefensysTokens.maroon : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
            border: Border.all(
              color: isSelected ? DefensysTokens.maroon : const Color(0xFFE2E8F0),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : DefensysTokens.steelGrey,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog: Student Team Picker with Search & Section Filters
class _TeamPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> teams;
  final List<String> sections;
  final Map<String, int> sectionCounts;
  final String? initialSelectedId;

  const _TeamPickerDialog({
    required this.teams,
    required this.sections,
    required this.sectionCounts,
    this.initialSelectedId,
  });

  @override
  State<_TeamPickerDialog> createState() => _TeamPickerDialogState();
}

class _TeamPickerDialogState extends State<_TeamPickerDialog> {
  final _searchController = TextEditingController();
  String _selectedSection = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = widget.teams.where((t) {
      final sec = (t['section']?.toString() ?? t['year_level']?.toString() ?? '').trim();

      if (_selectedSection.isNotEmpty && sec != _selectedSection) {
        return false;
      }

      if (query.isEmpty) return true;

      final name = (t['name'] ?? '').toString().toLowerCase();
      final title = (t['project_title'] ?? t['system_name'] ?? '').toString().toLowerCase();
      final lead = (t['leader_name'] ?? '').toString().toLowerCase();
      final adviser = (t['adviser_name'] ?? '').toString().toLowerCase();
      final secLower = sec.toLowerCase();

      return name.contains(query) ||
          title.contains(query) ||
          lead.contains(query) ||
          adviser.contains(query) ||
          secLower.contains(query);
    }).toList();

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: DefensysTokens.border)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DefensysTokens.maroon.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                    ),
                    child: const Icon(Icons.groups_rounded, color: DefensysTokens.maroon, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select Student Team',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${filtered.length} of ${widget.teams.length} teams available',
                          style: const TextStyle(fontSize: 11.5, color: DefensysTokens.steelGrey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: DefensysTokens.steelGrey),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Search Bar & Filter Chips
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search by team name, project title, leader, adviser, section...',
                      hintStyle: const TextStyle(fontSize: 13, color: DefensysTokens.steelGrey),
                      prefixIcon: const Icon(Icons.search_rounded, color: DefensysTokens.steelGrey, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: const BorderSide(color: DefensysTokens.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: const BorderSide(color: DefensysTokens.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.5),
                      ),
                    ),
                  ),
                  if (widget.sections.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(
                            label: 'All Sections (${widget.teams.length})',
                            isSelected: _selectedSection.isEmpty,
                            onTap: () => setState(() => _selectedSection = ''),
                          ),
                          const SizedBox(width: 6),
                          ...widget.sections.map((sec) {
                            final count = widget.sectionCounts[sec] ?? 0;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _buildFilterChip(
                                label: '$sec ($count)',
                                isSelected: _selectedSection == sec,
                                onTap: () => setState(() => _selectedSection = sec),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFF1F5F9)),

            // Teams List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF1F5F9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.group_off_outlined, size: 36, color: DefensysTokens.steelGrey),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'No matching student teams',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DefensysTokens.textDark),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Try adjusting your search keywords or resetting the section filter.',
                              style: TextStyle(fontSize: 12, color: DefensysTokens.steelGrey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      itemCount: filtered.length,
                      separatorBuilder: (ctx, i) => const SizedBox(height: 6),
                      itemBuilder: (ctx, i) {
                        final t = filtered[i];
                        final tId = t['id']?.toString() ?? '';
                        final teamName = t['name']?.toString() ?? 'Team';
                        final projectTitle = t['project_title']?.toString() ?? t['system_name']?.toString() ?? 'No Project Title';
                        final leaderName = t['leader_name']?.toString() ?? 'Unassigned';
                        final adviserName = t['adviser_name']?.toString() ?? 'Unassigned';
                        final sec = t['section']?.toString() ?? t['year_level']?.toString() ?? '';
                        final members = t['members'] is List ? (t['members'] as List) : [];
                        final isSelected = widget.initialSelectedId == tId;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(tId),
                            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? DefensysTokens.maroon.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                                border: Border.all(
                                  color: isSelected ? DefensysTokens.maroon : const Color(0xFFE2E8F0),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: isSelected ? DefensysTokens.maroon : DefensysTokens.maroon.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.groups_rounded,
                                      color: isSelected ? Colors.white : DefensysTokens.maroon,
                                      size: 20,
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
                                                teamName,
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                                                  color: DefensysTokens.textDark,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (sec.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: isSelected ? DefensysTokens.maroon : DefensysTokens.maroon.withValues(alpha: 0.08),
                                                  borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                                ),
                                                child: Text(
                                                  sec,
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: isSelected ? Colors.white : DefensysTokens.maroon,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(width: 5),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFE2E8F0),
                                                borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                              ),
                                              child: Text(
                                                '${members.length} members',
                                                style: const TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w600,
                                                  color: DefensysTokens.steelGrey,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          projectTitle,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w500,
                                            color: DefensysTokens.textSecondary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Leader: $leaderName • Adviser: $adviserName',
                                          style: const TextStyle(fontSize: 10.5, color: DefensysTokens.steelGrey),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 10),
                                  Icon(
                                    isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                    color: isSelected ? DefensysTokens.maroon : const Color(0xFFCBD5E1),
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? DefensysTokens.maroon : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
            border: Border.all(
              color: isSelected ? DefensysTokens.maroon : const Color(0xFFE2E8F0),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : DefensysTokens.steelGrey,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog: Dedicated Report Export Master-Detail Configuration & Live Data Viewer Modal
class _ReportExportConfigDialog extends StatefulWidget {
  final Map<String, dynamic> report;
  final AcademicPeriodState academicState;
  final StudentTeamsState teamsState;
  final List<Map<String, dynamic>> allStudents;
  final Map<String, Map<String, dynamic>> studentMetaMap;
  final List<String> studentSections;
  final Map<String, int> studentSectionCounts;
  final List<String> teamSections;
  final Map<String, int> teamSectionCounts;
  final List<Map<String, dynamic>> capstoneStages;
  final List<Map<String, dynamic>> pitEvents;
  final String? initialSemesterId;
  final String? initialStudentId;
  final String? initialTeamId;
  final String initialScope;
  final String? initialStage;
  final String? initialPitEvent;
  final String initialLevel;
  final String initialYearLevel;
  final String initialRole;
  final String initialCategory;
  final String initialTrack;
  final String initialStartDate;
  final String initialEndDate;
  final Future<bool> Function(Map<String, String>) onDownload;
  final Future<ReportPreviewData?> Function(Map<String, String>) onFetchPreview;
  final Future<String?> Function(String? currentId) onOpenStudentPicker;
  final Future<String?> Function(String? currentId) onOpenTeamPicker;

  const _ReportExportConfigDialog({
    required this.report,
    required this.academicState,
    required this.teamsState,
    required this.allStudents,
    required this.studentMetaMap,
    required this.studentSections,
    required this.studentSectionCounts,
    required this.teamSections,
    required this.teamSectionCounts,
    required this.capstoneStages,
    required this.pitEvents,
    this.initialSemesterId,
    this.initialStudentId,
    this.initialTeamId,
    required this.initialScope,
    this.initialStage,
    this.initialPitEvent,
    required this.initialLevel,
    required this.initialYearLevel,
    required this.initialRole,
    required this.initialCategory,
    required this.initialTrack,
    required this.initialStartDate,
    required this.initialEndDate,
    required this.onDownload,
    required this.onFetchPreview,
    required this.onOpenStudentPicker,
    required this.onOpenTeamPicker,
  });

  @override
  State<_ReportExportConfigDialog> createState() => _ReportExportConfigDialogState();
}

class _ReportExportConfigDialogState extends State<_ReportExportConfigDialog> {
  String _selectedFormat = 'pdf'; // 'pdf', 'xlsx', 'csv', 'doc'

  String? _selectedSemesterId;
  String? _selectedStudentId;
  String? _selectedTeamId;
  String _selectedScope = '';
  String _selectedStage = '';
  String _selectedPitEvent = '';
  String _selectedLevel = '';
  String _selectedYearLevel = '';
  String _selectedRole = '';
  String _reportCategoryFilter = '';
  String _reportTrackFilter = '';
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();

  final _selectorSearchController = TextEditingController();
  String _selectedSectionFilter = '';
  final _viewerSearchController = TextEditingController();

  bool _isDownloading = false;
  bool _isLoadingPreview = false;
  ReportPreviewData? _previewData;

  @override
  void initState() {
    super.initState();
    _selectedSemesterId = widget.initialSemesterId;
    _selectedStudentId = widget.initialStudentId;
    _selectedTeamId = widget.initialTeamId;
    _selectedScope = widget.initialScope;
    _selectedStage = widget.initialStage ?? '';
    _selectedPitEvent = widget.initialPitEvent ?? '';
    _selectedLevel = widget.initialLevel;
    _selectedYearLevel = widget.initialYearLevel;
    _selectedRole = widget.initialRole;
    _reportCategoryFilter = widget.initialCategory;
    _reportTrackFilter = widget.initialTrack;
    _startDateController.text = widget.initialStartDate;
    _endDateController.text = widget.initialEndDate;

    _selectorSearchController.addListener(() => setState(() {}));
    _viewerSearchController.addListener(() => setState(() {}));

    // Auto load preview if parameters are ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPreview();
    });
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    _selectorSearchController.dispose();
    _viewerSearchController.dispose();
    super.dispose();
  }

  Map<String, String> _buildCurrentParams() {
    return <String, String>{
      if (_selectedStudentId != null) 'studentId': _selectedStudentId!,
      if (_selectedTeamId != null) 'teamId': _selectedTeamId!,
      if (_selectedSemesterId != null) 'semesterId': _selectedSemesterId!,
      if (_selectedScope.isNotEmpty) 'scope': _selectedScope,
      if (_selectedStage.isNotEmpty) 'stage': _selectedStage,
      if (_selectedPitEvent.isNotEmpty) 'pitEvent': _selectedPitEvent,
      if (_selectedLevel.isNotEmpty) 'level': _selectedLevel,
      if (_selectedYearLevel.isNotEmpty) 'yearLevel': _selectedYearLevel,
      if (_selectedRole.isNotEmpty) 'role': _selectedRole,
      if (_reportCategoryFilter.isNotEmpty) 'category': _reportCategoryFilter,
      if (_reportTrackFilter.isNotEmpty) 'track': _reportTrackFilter,
      if (_startDateController.text.isNotEmpty) 'startDate': _startDateController.text.trim(),
      if (_endDateController.text.isNotEmpty) 'endDate': _endDateController.text.trim(),
      'exportFormat': _selectedFormat,
    };
  }

  Future<void> _loadPreview() async {
    final endpoint = widget.report['endpoint'] as String;

    // Check if required selection is missing
    if (endpoint == 'individual-grade' && _selectedStudentId == null) {
      if (mounted) setState(() => _previewData = null);
      return;
    }
    if (endpoint == 'team-grade' && _selectedTeamId == null) {
      if (mounted) setState(() => _previewData = null);
      return;
    }

    setState(() => _isLoadingPreview = true);

    final preview = await widget.onFetchPreview(_buildCurrentParams());

    if (mounted) {
      setState(() {
        _isLoadingPreview = false;
        _previewData = preview;
      });
    }
  }

  Future<void> _handleDownload() async {
    final endpoint = widget.report['endpoint'] as String;

    if (endpoint == 'individual-grade' && _selectedStudentId == null) {
      showValidationToast(context, 'Please select a student candidate from the list.');
      return;
    }

    if (endpoint == 'team-grade' && _selectedTeamId == null) {
      showValidationToast(context, 'Please select a student team from the list.');
      return;
    }

    setState(() => _isDownloading = true);

    final success = await widget.onDownload(_buildCurrentParams());

    if (mounted) {
      setState(() => _isDownloading = false);
      if (success) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final endpoint = widget.report['endpoint'] as String;
    final title = widget.report['title'] as String;
    final desc = widget.report['desc'] as String;
    final icon = widget.report['icon'] as IconData;
    final tag = widget.report['tag'] as String;

    final selectedStudentMeta = _selectedStudentId != null ? widget.studentMetaMap[_selectedStudentId] : null;
    final selectedStudentObj = selectedStudentMeta?['student'] as Map<String, dynamic>?;

    final selectedTeamObj = _selectedTeamId != null
        ? widget.teamsState.teams.firstWhere(
            (t) => t['id']?.toString() == _selectedTeamId,
            orElse: () => <String, dynamic>{},
          )
        : null;

    final List<Map<String, dynamic>> semestersList = [];
    for (final year in widget.academicState.schoolYears) {
      final sems = year['semesters'];
      if (sems is List) {
        for (final sem in sems) {
          if (sem is Map) {
            semestersList.add({
              'id': sem['id']?.toString() ?? '',
              'label': '${year['school_year'] ?? ''} | ${sem['label'] ?? ''}',
            });
          }
        }
      }
    }

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1120,
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Column(
          children: [
            // 1. Modal Institutional Header
            Container(
              padding: const EdgeInsets.fromLTRB(22, 16, 20, 16),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: DefensysTokens.maroon, width: 4),
                  bottom: BorderSide(color: DefensysTokens.border),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: DefensysTokens.maroon.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                    ),
                    child: Icon(icon, color: DefensysTokens.maroon, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: DefensysTokens.textDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: DefensysTokens.maroon.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: DefensysTokens.maroon,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          desc,
                          style: const TextStyle(fontSize: 11.5, color: DefensysTokens.steelGrey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: DefensysTokens.steelGrey),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // 2. Main Two-Pane Split (Left: Selector / Filters, Right: Live Data Viewer)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Pane (Width: 380)
                  SizedBox(
                    width: 380,
                    child: _buildLeftSelectorPane(
                      endpoint: endpoint,
                      semestersList: semestersList,
                    ),
                  ),

                  // Vertical Separator
                  const VerticalDivider(width: 1, thickness: 1, color: DefensysTokens.border),

                  // Right Pane: Live Data Preview
                  Expanded(
                    child: _buildRightPreviewPane(
                      endpoint: endpoint,
                      selectedStudentObj: selectedStudentObj,
                      selectedTeamObj: selectedTeamObj,
                    ),
                  ),
                ],
              ),
            ),

            // 3. Modal Bottom Footer (Format selector pills + Download button)
            _buildModalFooter(),
          ],
        ),
      ),
    );
  }

  /// Left Pane: Either List of Items (Teams/Students) or Filter Parameters Form
  Widget _buildLeftSelectorPane({
    required String endpoint,
    required List<Map<String, dynamic>> semestersList,
  }) {
    if (endpoint == 'team-grade') {
      return _buildTeamListSelector();
    }

    if (endpoint == 'individual-grade') {
      return _buildStudentListSelector(semestersList: semestersList);
    }

    // Filter controls for aggregate reports
    return _buildAggregateFiltersPane(endpoint: endpoint, semestersList: semestersList);
  }

  /// Left Pane: Student Teams List Selector
  Widget _buildTeamListSelector() {
    final query = _selectorSearchController.text.trim().toLowerCase();

    final filtered = widget.teamsState.teams.where((t) {
      final sec = (t['section']?.toString() ?? t['year_level']?.toString() ?? '').trim();

      if (_selectedSectionFilter.isNotEmpty && sec != _selectedSectionFilter) {
        return false;
      }

      if (query.isEmpty) return true;

      final name = (t['name'] ?? '').toString().toLowerCase();
      final title = (t['project_title'] ?? t['system_name'] ?? '').toString().toLowerCase();
      final lead = (t['leader_name'] ?? '').toString().toLowerCase();
      final adviser = (t['adviser_name'] ?? '').toString().toLowerCase();
      final secLower = sec.toLowerCase();

      return name.contains(query) ||
          title.contains(query) ||
          lead.contains(query) ||
          adviser.contains(query) ||
          secLower.contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Pane Search & Filter Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'SELECT TEAM',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: DefensysTokens.steelGrey,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${filtered.length} of ${widget.teamsState.teams.length}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: DefensysTokens.steelGrey),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: TextField(
                  controller: _selectorSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search team, project, leader...',
                    hintStyle: const TextStyle(fontSize: 12, color: DefensysTokens.steelGrey),
                    prefixIcon: const Icon(Icons.search_rounded, size: 16, color: DefensysTokens.steelGrey),
                    suffixIcon: _selectorSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 14),
                            onPressed: () => _selectorSearchController.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: const BorderSide(color: DefensysTokens.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: const BorderSide(color: DefensysTokens.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.2),
                    ),
                  ),
                ),
              ),
              if (widget.teamSections.isNotEmpty) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildMiniFilterChip(
                        label: 'All',
                        isSelected: _selectedSectionFilter.isEmpty,
                        onTap: () => setState(() => _selectedSectionFilter = ''),
                      ),
                      const SizedBox(width: 5),
                      ...widget.teamSections.map((sec) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: _buildMiniFilterChip(
                            label: sec,
                            isSelected: _selectedSectionFilter == sec,
                            onTap: () => setState(() => _selectedSectionFilter = sec),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        const Divider(height: 1, color: Color(0xFFF1F5F9)),

        // Selectable Teams List
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No matching teams found.',
                      style: TextStyle(fontSize: 12.5, color: DefensysTokens.steelGrey),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final t = filtered[i];
                    final tId = t['id']?.toString() ?? '';
                    final teamName = t['name']?.toString() ?? 'Team';
                    final projectTitle = t['project_title']?.toString() ?? t['system_name']?.toString() ?? 'No Project Title';
                    final leaderName = t['leader_name']?.toString() ?? 'Unassigned';
                    final sec = t['section']?.toString() ?? t['year_level']?.toString() ?? '';
                    final isSelected = _selectedTeamId == tId;

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() => _selectedTeamId = tId);
                          _loadPreview();
                        },
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? DefensysTokens.maroon.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                            border: Border.all(
                              color: isSelected ? DefensysTokens.maroon : const Color(0xFFE2E8F0),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: isSelected ? DefensysTokens.maroon : DefensysTokens.maroon.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.groups_rounded,
                                  color: isSelected ? Colors.white : DefensysTokens.maroon,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            teamName,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                                              color: DefensysTokens.textDark,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (sec.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: isSelected ? DefensysTokens.maroon : DefensysTokens.maroon.withValues(alpha: 0.08),
                                              borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                            ),
                                            child: Text(
                                              sec,
                                              style: TextStyle(
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.w700,
                                                color: isSelected ? Colors.white : DefensysTokens.maroon,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      projectTitle,
                                      style: const TextStyle(fontSize: 11, color: DefensysTokens.textSecondary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      'Leader: $leaderName',
                                      style: const TextStyle(fontSize: 10, color: DefensysTokens.steelGrey),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                color: isSelected ? DefensysTokens.maroon : const Color(0xFFCBD5E1),
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Left Pane: Student Candidates List Selector
  Widget _buildStudentListSelector({required List<Map<String, dynamic>> semestersList}) {
    final query = _selectorSearchController.text.trim().toLowerCase();

    final filtered = widget.allStudents.where((s) {
      final sId = s['id']?.toString() ?? '';
      final meta = widget.studentMetaMap[sId];

      if (_selectedSectionFilter.isNotEmpty && meta?['section'] != _selectedSectionFilter) {
        return false;
      }

      if (query.isEmpty) return true;

      final name = (s['name'] ?? s['username'] ?? '').toString().toLowerCase();
      final username = (s['username'] ?? sId).toString().toLowerCase();
      final email = (s['email'] ?? '').toString().toLowerCase();
      final team = meta?['team'] as Map<String, dynamic>?;
      final teamName = (team?['name'] ?? '').toString().toLowerCase();
      final sec = (meta?['section'] ?? '').toString().toLowerCase();

      return name.contains(query) ||
          username.contains(query) ||
          sId.contains(query) ||
          email.contains(query) ||
          teamName.contains(query) ||
          sec.contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Pane Search & Filter Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'SELECT STUDENT CANDIDATE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: DefensysTokens.steelGrey,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${filtered.length} of ${widget.allStudents.length}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: DefensysTokens.steelGrey),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: TextField(
                  controller: _selectorSearchController,
                  decoration: InputDecoration(
                    hintText: 'Search by ID (e.g. 4011), name, team...',
                    hintStyle: const TextStyle(fontSize: 12, color: DefensysTokens.steelGrey),
                    prefixIcon: const Icon(Icons.search_rounded, size: 16, color: DefensysTokens.steelGrey),
                    suffixIcon: _selectorSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 14),
                            onPressed: () => _selectorSearchController.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: const BorderSide(color: DefensysTokens.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: const BorderSide(color: DefensysTokens.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.2),
                    ),
                  ),
                ),
              ),
              if (widget.studentSections.isNotEmpty) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildMiniFilterChip(
                        label: 'All',
                        isSelected: _selectedSectionFilter.isEmpty,
                        onTap: () => setState(() => _selectedSectionFilter = ''),
                      ),
                      const SizedBox(width: 5),
                      ...widget.studentSections.map((sec) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: _buildMiniFilterChip(
                            label: sec,
                            isSelected: _selectedSectionFilter == sec,
                            onTap: () => setState(() => _selectedSectionFilter = sec),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        const Divider(height: 1, color: Color(0xFFF1F5F9)),

        // Selectable Students List
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No matching candidates found.',
                      style: TextStyle(fontSize: 12.5, color: DefensysTokens.steelGrey),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final s = filtered[i];
                    final sId = s['id']?.toString() ?? '';
                    final meta = widget.studentMetaMap[sId];
                    final name = s['name'] ?? s['username'] ?? 'Student';
                    final username = s['username']?.toString() ?? sId;
                    final team = meta?['team'] as Map<String, dynamic>?;
                    final isLeader = meta?['isLeader'] == true;
                    final section = meta?['section'] as String?;
                    final isSelected = _selectedStudentId == sId;

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() => _selectedStudentId = sId);
                          _loadPreview();
                        },
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? DefensysTokens.maroon.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                            border: Border.all(
                              color: isSelected ? DefensysTokens.maroon : const Color(0xFFE2E8F0),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: isSelected ? DefensysTokens.maroon : DefensysTokens.maroon.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _extractInitials(name.toString()),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected ? Colors.white : DefensysTokens.maroon,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            name.toString(),
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                                              color: DefensysTokens.textDark,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: isSelected ? DefensysTokens.maroon : const Color(0xFF1E293B),
                                            borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                          ),
                                          child: Text(
                                            'ID: $username',
                                            style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: Colors.white),
                                          ),
                                        ),
                                        if (isLeader) ...[
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: DefensysTokens.gold.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                            ),
                                            child: const Text(
                                              'LEAD',
                                              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: DefensysTokens.darkGold),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        if (team != null) ...[
                                          Expanded(
                                            child: Text(
                                              '${team['name']} ${section != null ? "• $section" : ""}',
                                              style: const TextStyle(fontSize: 10.5, color: DefensysTokens.steelGrey),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ] else ...[
                                          const Text('No Team Assigned', style: TextStyle(fontSize: 10.5, color: DefensysTokens.steelGrey)),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                color: isSelected ? DefensysTokens.maroon : const Color(0xFFCBD5E1),
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Left Pane: Aggregate Reports Filter Parameters
  Widget _buildAggregateFiltersPane({
    required String endpoint,
    required List<Map<String, dynamic>> semestersList,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'EXPORT FILTERS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: DefensysTokens.steelGrey,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 14),

          // Semester Dropdown
          if (endpoint != 'user-directory') ...[
            const _FormSectionLabel('ACADEMIC SEMESTER'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _selectedSemesterId,
              isExpanded: true,
              decoration: _reportInputDecoration('Choose semester...'),
              items: semestersList.map((s) {
                return DropdownMenuItem<String>(
                  value: s['id']?.toString(),
                  child: Text(s['label']?.toString() ?? 'N/A', style: const TextStyle(fontSize: 12.5)),
                );
              }).toList(),
              onChanged: (val) {
                setState(() => _selectedSemesterId = val);
                _loadPreview();
              },
            ),
            const SizedBox(height: 16),
          ],

          // Scope Dropdown
          if (endpoint == 'semester-grades' || endpoint == 'defense-schedules') ...[
            const _FormSectionLabel('ACADEMIC SCOPE'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedScope,
              isExpanded: true,
              decoration: _reportInputDecoration('Filter scope...'),
              items: const [
                DropdownMenuItem(value: '', child: Text('All Records (Capstone & PIT)', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'capstone', child: Text('Capstone Only', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'pit', child: Text('PIT Only', style: TextStyle(fontSize: 12.5))),
              ],
              onChanged: (val) {
                setState(() {
                  _selectedScope = val ?? '';
                  if (_selectedScope == 'capstone') {
                    _selectedPitEvent = '';
                  } else if (_selectedScope == 'pit') {
                    _selectedStage = '';
                  } else {
                    _selectedStage = '';
                    _selectedPitEvent = '';
                  }
                });
                _loadPreview();
              },
            ),
            const SizedBox(height: 16),

            // Capstone Stage Dropdown
            if (_selectedScope == 'capstone') ...[
              const _FormSectionLabel('CAPSTONE DEFENSE STAGE'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedStage,
                isExpanded: true,
                decoration: _reportInputDecoration('Select stage...'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All Capstone Stages', style: TextStyle(fontSize: 12.5))),
                  ...widget.capstoneStages.map((stg) {
                    final label = stg['label']?.toString() ?? stg['name']?.toString() ?? 'Stage';
                    return DropdownMenuItem<String>(
                      value: label,
                      child: Text(label, style: const TextStyle(fontSize: 12.5)),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() => _selectedStage = val ?? '');
                  _loadPreview();
                },
              ),
              const SizedBox(height: 16),
            ],

            // PIT Event / Year Level Dropdown
            if (_selectedScope == 'pit') ...[
              const _FormSectionLabel('PIT EVENT / YEAR LEVEL'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedPitEvent,
                isExpanded: true,
                decoration: _reportInputDecoration('Select PIT event...'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All PIT Events', style: TextStyle(fontSize: 12.5))),
                  ...widget.pitEvents.map((evt) {
                    final name = evt['event_name']?.toString() ?? evt['name']?.toString() ?? evt['label']?.toString() ?? 'PIT Event';
                    return DropdownMenuItem<String>(
                      value: name,
                      child: Text(name, style: const TextStyle(fontSize: 12.5)),
                    );
                  }),
                  if (widget.pitEvents.isEmpty) ...const [
                    DropdownMenuItem(value: '1st Year PIT', child: Text('1st Year PIT', style: TextStyle(fontSize: 12.5))),
                    DropdownMenuItem(value: '2nd Year PIT', child: Text('2nd Year PIT', style: TextStyle(fontSize: 12.5))),
                    DropdownMenuItem(value: '3rd Year PIT', child: Text('3rd Year PIT', style: TextStyle(fontSize: 12.5))),
                  ],
                ],
                onChanged: (val) {
                  setState(() => _selectedPitEvent = val ?? '');
                  _loadPreview();
                },
              ),
              const SizedBox(height: 16),
            ],
          ],

          // Program & Year Level Filters
          if (endpoint == 'team-roster') ...[
            const _FormSectionLabel('PROGRAM LEVEL'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _selectedLevel,
              isExpanded: true,
              decoration: _reportInputDecoration('Filter level...'),
              items: const [
                DropdownMenuItem(value: '', child: Text('All Program Levels', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'capstone', child: Text('Capstone Teams', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'pit', child: Text('PIT Teams', style: TextStyle(fontSize: 12.5))),
              ],
              onChanged: (val) {
                setState(() => _selectedLevel = val ?? '');
                _loadPreview();
              },
            ),
            const SizedBox(height: 16),
            const _FormSectionLabel('STUDENT YEAR LEVEL'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _selectedYearLevel,
              isExpanded: true,
              decoration: _reportInputDecoration('Filter year level...'),
              items: const [
                DropdownMenuItem(value: '', child: Text('All Year Levels', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: '3rd Year', child: Text('3rd Year', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: '4th Year', child: Text('4th Year', style: TextStyle(fontSize: 12.5))),
              ],
              onChanged: (val) {
                setState(() => _selectedYearLevel = val ?? '');
                _loadPreview();
              },
            ),
            const SizedBox(height: 16),
          ],

          // User Directory Role Filter
          if (endpoint == 'user-directory') ...[
            const _FormSectionLabel('SYSTEM ROLE'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              isExpanded: true,
              decoration: _reportInputDecoration('Choose role...'),
              items: const [
                DropdownMenuItem(value: '', child: Text('All Roles & Accounts', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'student', child: Text('Students Only', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'faculty', child: Text('Faculty & Panelists', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'admin', child: Text('System Administrators', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'pit_lead', child: Text('PIT Leads', style: TextStyle(fontSize: 12.5))),
              ],
              onChanged: (val) {
                setState(() => _selectedRole = val ?? '');
                _loadPreview();
              },
            ),
            const SizedBox(height: 16),
          ],

          // Audit Trail Date Range & Category
          if (endpoint == 'audit-trail') ...[
            const _FormSectionLabel('DATE RANGE (OPTIONAL)'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _startDateController,
                    readOnly: true,
                    decoration: _reportInputDecoration('Start Date').copyWith(
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_today_outlined, size: 16),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            _startDateController.text =
                                '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                            setState(() {});
                            _loadPreview();
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _endDateController,
                    readOnly: true,
                    decoration: _reportInputDecoration('End Date').copyWith(
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.calendar_today_outlined, size: 16),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            _endDateController.text =
                                '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                            setState(() {});
                            _loadPreview();
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _FormSectionLabel('AUDIT LOG CATEGORY'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _reportCategoryFilter,
              isExpanded: true,
              decoration: _reportInputDecoration('Filter category...'),
              items: const [
                DropdownMenuItem(value: '', child: Text('All Audit Categories', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'authentication', child: Text('Authentication & Access', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'grading', child: Text('Grading & Defense Scores', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'team', child: Text('Team Management & Roster', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'compliance', child: Text('System & Compliance', style: TextStyle(fontSize: 12.5))),
              ],
              onChanged: (val) {
                setState(() => _reportCategoryFilter = val ?? '');
                _loadPreview();
              },
            ),
            const SizedBox(height: 16),
          ],

          // Quick Reset Filters Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('Reset All Filters'),
              style: OutlinedButton.styleFrom(
                foregroundColor: DefensysTokens.maroon,
                side: BorderSide(color: DefensysTokens.maroon.withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DefensysTokens.radiusMd)),
              ),
              onPressed: () {
                setState(() {
                  _selectedScope = '';
                  _selectedLevel = '';
                  _selectedYearLevel = '';
                  _selectedRole = '';
                  _reportCategoryFilter = '';
                  _startDateController.clear();
                  _endDateController.clear();
                });
                _loadPreview();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Right Pane: Live Data Preview Table + KPI Cards
  Widget _buildRightPreviewPane({
    required String endpoint,
    required Map<String, dynamic>? selectedStudentObj,
    required Map<String, dynamic>? selectedTeamObj,
  }) {
    // Missing selection guard
    if (endpoint == 'individual-grade' && selectedStudentObj == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_search_rounded, size: 42, color: DefensysTokens.maroon),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select a Student Candidate',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: DefensysTokens.textDark),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose a student candidate from the list on the left to preview individual grade breakdowns and peer multipliers.',
                style: TextStyle(fontSize: 12, color: DefensysTokens.steelGrey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (endpoint == 'team-grade' && (selectedTeamObj == null || selectedTeamObj.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.groups_rounded, size: 42, color: DefensysTokens.maroon),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select a Student Team',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: DefensysTokens.textDark),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose a team from the list on the left to preview evaluation criteria, panel scores, and member grades.',
                style: TextStyle(fontSize: 12, color: DefensysTokens.steelGrey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoadingPreview) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: DefensysTokens.maroon),
              SizedBox(height: 16),
              Text(
                'Compiling live report dataset...',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DefensysTokens.textDark),
              ),
              SizedBox(height: 4),
              Text(
                'Fetching realtime evaluations, defense scores, and audit records.',
                style: TextStyle(fontSize: 11.5, color: DefensysTokens.steelGrey),
              ),
            ],
          ),
        ),
      );
    }

    final data = _previewData;
    if (data == null || data.rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.dataset_linked_outlined, size: 40, color: DefensysTokens.steelGrey),
              const SizedBox(height: 12),
              const Text(
                'No data records found for current filter',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DefensysTokens.textDark),
              ),
              const SizedBox(height: 4),
              const Text(
                'Try adjusting the semester or filter criteria on the left.',
                style: TextStyle(fontSize: 12, color: DefensysTokens.steelGrey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh Data'),
                onPressed: _loadPreview,
              ),
            ],
          ),
        ),
      );
    }

    // Filter rows by in-viewer search
    final query = _viewerSearchController.text.trim().toLowerCase();
    final displayRows = data.rows.where((row) {
      if (query.isEmpty) return true;
      for (final val in row.values) {
        if (val != null && val.toString().toLowerCase().contains(query)) {
          return true;
        }
      }
      return false;
    }).toList();

    return Column(
      children: [
        // KPI Summary Cards
        if (data.summaryKpis.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: DefensysTokens.border)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: data.summaryKpis.map((kpi) {
                  final label = kpi['label']?.toString() ?? '';
                  final val = kpi['value']?.toString() ?? '';
                  final badge = kpi['badge']?.toString();

                  return Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      border: Border.all(color: DefensysTokens.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.steelGrey,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              val,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: DefensysTokens.textDark,
                              ),
                            ),
                            if (badge != null && badge.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: badge == 'PASSED'
                                      ? DefensysTokens.successBg
                                      : DefensysTokens.gold.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                ),
                                child: Text(
                                  badge,
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    color: badge == 'PASSED' ? DefensysTokens.successText : DefensysTokens.darkGold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

        // Live Table Search Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _viewerSearchController,
                    decoration: InputDecoration(
                      hintText: 'Search within preview table...',
                      hintStyle: const TextStyle(fontSize: 12, color: DefensysTokens.steelGrey),
                      prefixIcon: const Icon(Icons.search_rounded, size: 15, color: DefensysTokens.steelGrey),
                      suffixIcon: _viewerSearchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 13),
                              onPressed: () => _viewerSearchController.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: const BorderSide(color: DefensysTokens.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: const BorderSide(color: DefensysTokens.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                ),
                child: Text(
                  '${displayRows.length} of ${data.rows.length} rows',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: DefensysTokens.steelGrey),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18, color: DefensysTokens.steelGrey),
                tooltip: 'Refresh dataset',
                onPressed: _loadPreview,
              ),
            ],
          ),
        ),

        const Divider(height: 1, color: Color(0xFFF1F5F9)),

        // Interactive Data Grid
        Expanded(
          child: displayRows.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No matching records found in table.',
                      style: TextStyle(fontSize: 12.5, color: DefensysTokens.steelGrey),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 620),
                      child: DataTable(
                        headingRowHeight: 36,
                        dataRowMinHeight: 32,
                        dataRowMaxHeight: 44,
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                        horizontalMargin: 14,
                        columnSpacing: 16,
                        columns: data.columns.map((col) {
                          final label = col['label']?.toString() ?? '';
                          final align = col['align']?.toString() ?? 'left';

                          return DataColumn(
                            numeric: align == 'center' || align == 'right',
                            label: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: DefensysTokens.textDark,
                                letterSpacing: 0.3,
                              ),
                            ),
                          );
                        }).toList(),
                        rows: displayRows.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final row = entry.value;
                          final isStripe = idx % 2 == 1;

                          return DataRow(
                            color: WidgetStateProperty.all(
                              isStripe ? const Color(0xFFFAFAFA) : Colors.white,
                            ),
                            cells: data.columns.map((col) {
                              final key = col['key']?.toString() ?? '';
                              final val = row[key]?.toString() ?? '';
                              final align = col['align']?.toString() ?? 'left';

                              // Check if cell is a result/badge
                              final isPassed = val == 'PASSED' || val == 'ACTIVE';
                              final isFailed = val == 'FAILED' || val == 'REVISION';
                              final isSpecial = isPassed || isFailed;

                              if (isSpecial) {
                                return DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isPassed ? DefensysTokens.successBg : DefensysTokens.dangerBg,
                                      borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                    ),
                                    child: Text(
                                      val,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: isPassed ? DefensysTokens.successText : DefensysTokens.dangerText,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              return DataCell(
                                Align(
                                  alignment: align == 'center'
                                      ? Alignment.center
                                      : align == 'right'
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                  child: Text(
                                    val,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: DefensysTokens.textDark,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// Modal Bottom Footer Bar with Format Chooser Pills + Action Buttons
  Widget _buildModalFooter() {
    final formats = [
      {
        'id': 'pdf',
        'label': 'PDF Document',
        'ext': '.pdf',
        'icon': Icons.picture_as_pdf_outlined,
        'color': DefensysTokens.maroon,
      },
      {
        'id': 'xlsx',
        'label': 'Excel Spreadsheet',
        'ext': '.xlsx',
        'icon': Icons.table_view_rounded,
        'color': const Color(0xFF16A34A),
      },
      {
        'id': 'csv',
        'label': 'CSV File',
        'ext': '.csv',
        'icon': Icons.grid_on_rounded,
        'color': const Color(0xFF2563EB),
      },
      {
        'id': 'doc',
        'label': 'Word Document',
        'ext': '.doc',
        'icon': Icons.description_outlined,
        'color': const Color(0xFF0284C7),
      },
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: DefensysTokens.border)),
      ),
      child: Row(
        children: [
          // Format Selector Label
          const Text(
            'FILE FORMAT:',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: DefensysTokens.steelGrey,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 10),

          // Format Selector Pills
          ...formats.map((fmt) {
            final id = fmt['id'] as String;
            final label = fmt['label'] as String;
            final iconData = fmt['icon'] as IconData;
            final color = fmt['color'] as Color;
            final isSelected = _selectedFormat == id;

            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _selectedFormat = id),
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withValues(alpha: 0.08) : Colors.white,
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                      border: Border.all(
                        color: isSelected ? color : const Color(0xFFCBD5E1),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          iconData,
                          size: 14,
                          color: isSelected ? color : DefensysTokens.steelGrey,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected ? color : DefensysTokens.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          const Spacer(),

          // Cancel Button
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: DefensysTokens.textDark,
              side: const BorderSide(color: DefensysTokens.border),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DefensysTokens.radiusMd)),
            ),
            onPressed: _isDownloading ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),

          // Download Primary Action
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: DefensysTokens.maroon,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DefensysTokens.radiusMd)),
            ),
            icon: _isDownloading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined, size: 16),
            label: Text(
              _isDownloading
                  ? 'Generating ${_selectedFormat.toUpperCase()}...'
                  : 'Download ${_selectedFormat.toUpperCase()} Export',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            onPressed: _isDownloading ? null : _handleDownload,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected ? DefensysTokens.maroon : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
            border: Border.all(
              color: isSelected ? DefensysTokens.maroon : const Color(0xFFE2E8F0),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : DefensysTokens.steelGrey,
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentTabButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final String badgeLabel;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentTabButton({
    required this.label,
    required this.subtitle,
    required this.badgeLabel,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            border: Border.all(
              color: isSelected ? DefensysTokens.maroon : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: isSelected
                ? const [
                    BoxShadow(
                      color: Color(0x0B000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: isSelected
                      ? DefensysTokens.maroon
                      : const Color(0xFFE2E8F0),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: isSelected ? Colors.white : DefensysTokens.steelGrey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontFamily: DefensysTokens.fontFamily,
                            color: isSelected
                                ? DefensysTokens.maroon
                                : DefensysTokens.textDark,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? DefensysTokens.maroon.withValues(alpha: 0.1)
                                : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                          ),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? DefensysTokens.maroon
                                  : DefensysTokens.steelGrey,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isSelected
                            ? DefensysTokens.textSecondary
                            : DefensysTokens.steelGrey,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuditReadinessBadge extends StatelessWidget {
  final SystemAuditState state;

  const _AuditReadinessBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final total = _count(state.counts['filtered'], fallback: state.logs.length);
    final needsReview = _count(state.counts['needs_review']);
    final reviewed = _count(state.counts['reviewed']);
    final readiness = total == 0
        ? 0
        : (((total - needsReview).clamp(0, total) / total) * 100).round();
    final isReady = needsReview == 0;

    return DefensysCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  value: readiness / 100,
                  strokeWidth: 4.5,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isReady ? DefensysTokens.success : DefensysTokens.gold,
                  ),
                ),
              ),
              Icon(
                Icons.shield_outlined,
                color: isReady ? DefensysTokens.successText : DefensysTokens.darkGold,
                size: 24,
              ),
            ],
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ISO 9001:2015 Readiness',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DefensysTokens.steelGrey,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$readiness%',
                    style: const TextStyle(
                      color: DefensysTokens.maroon,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isReady ? DefensysTokens.successBg : DefensysTokens.warningBg,
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                      border: Border.all(
                        color: isReady
                            ? DefensysTokens.successBorder
                            : DefensysTokens.warningBorder,
                      ),
                    ),
                    child: Text(
                      isReady ? 'Ready for Audit' : 'Pending Review',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isReady
                            ? DefensysTokens.successText
                            : DefensysTokens.warningText,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 20),
          Container(
            width: 1,
            height: 36,
            color: DefensysTokens.border,
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reviewed Ratio',
                style: TextStyle(
                  fontSize: 11,
                  color: DefensysTokens.steelGrey,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$reviewed / $total',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DefensysTokens.textDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EvidenceStatusCards extends StatelessWidget {
  final SystemAuditState state;

  const _EvidenceStatusCards({required this.state});

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        final cardWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;

        final total = _count(state.counts['filtered'], fallback: state.logs.length);
        final needsReview = _count(state.counts['needs_review']);
        final captured = _count(state.counts['captured']);
        final percent = total == 0
            ? 0
            : (((total - needsReview).clamp(0, total) / total) * 100).round();

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _SummaryCard(
              width: cardWidth,
              label: 'Audit Readiness',
              value: '$percent%',
              status: percent >= 80 ? 'Optimal Status' : 'Needs Review',
              icon: Icons.fact_check_outlined,
              accentColor: DefensysTokens.maroon,
              statusBg: percent >= 80 ? DefensysTokens.successBg : DefensysTokens.warningBg,
              statusText: percent >= 80 ? DefensysTokens.successText : DefensysTokens.warningText,
            ),
            _SummaryCard(
              width: cardWidth,
              label: 'Open Findings',
              value: '$needsReview',
              status: 'Requires Attention',
              icon: Icons.rate_review_outlined,
              accentColor: DefensysTokens.warningText,
              statusBg: DefensysTokens.warningBg,
              statusText: DefensysTokens.warningText,
            ),
            _SummaryCard(
              width: cardWidth,
              label: 'Verified Evidence',
              value: '$captured',
              status: 'System Logged',
              icon: Icons.task_alt_outlined,
              accentColor: DefensysTokens.success,
              statusBg: DefensysTokens.successBg,
              statusText: DefensysTokens.successText,
            ),
            _SummaryCard(
              width: cardWidth,
              label: 'Pending Review',
              value: '$needsReview',
              status: 'Awaiting Action',
              icon: Icons.schedule_outlined,
              accentColor: DefensysTokens.techBlue,
              statusBg: DefensysTokens.infoBg,
              statusText: DefensysTokens.infoText,
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final String status;
  final IconData icon;
  final Color accentColor;
  final Color statusBg;
  final Color statusText;

  const _SummaryCard({
    required this.width,
    required this.label,
    required this.value,
    required this.status,
    required this.icon,
    required this.accentColor,
    required this.statusBg,
    required this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
          border: Border.all(color: DefensysTokens.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                  ),
                  child: Icon(icon, color: accentColor, size: 22),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: statusText,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: TextStyle(
                color: accentColor,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: DefensysTokens.steelGrey,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditFilterToolbar extends ConsumerWidget {
  final SystemAuditState state;
  final bool isAdmin;
  final bool isPitLead;
  final dynamic user;
  final TextEditingController searchController;
  final TextEditingController startDateController;
  final TextEditingController endDateController;
  final String currentScope;
  final ValueChanged<String?> onScopeChanged;
  final VoidCallback onSelectStartDate;
  final VoidCallback onSelectEndDate;
  final VoidCallback onQuickExport;

  const _AuditFilterToolbar({
    required this.state,
    required this.isAdmin,
    required this.isPitLead,
    required this.user,
    required this.searchController,
    required this.startDateController,
    required this.endDateController,
    required this.currentScope,
    required this.onScopeChanged,
    required this.onSelectStartDate,
    required this.onSelectEndDate,
    required this.onQuickExport,
  });

  bool get _hasActiveFilters {
    return state.category.isNotEmpty ||
        state.reviewStatus.isNotEmpty ||
        state.action.isNotEmpty ||
        state.search.isNotEmpty ||
        state.startDate.isNotEmpty ||
        state.endDate.isNotEmpty ||
        state.track.isNotEmpty ||
        state.yearLevel.isNotEmpty;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsState = ref.watch(reportsProvider);

    return DefensysCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_list_rounded, color: DefensysTokens.maroon, size: 20),
              const SizedBox(width: 8),
              Text('Audit Trail Filters', style: DefensysUi.sectionTitle),
              const Spacer(),
              if (_hasActiveFilters)
                TextButton.icon(
                  onPressed: () {
                    searchController.clear();
                    startDateController.clear();
                    endDateController.clear();
                    final notifier = ref.read(systemAuditProvider.notifier);
                    notifier.setCategory('');
                    notifier.setReviewStatus('');
                    notifier.setAction('');
                    notifier.setSearch('');
                    notifier.setStartDate('');
                    notifier.setEndDate('');
                    notifier.setTrack('');
                    notifier.setYearLevel('');
                  },
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('Reset Filters'),
                  style: TextButton.styleFrom(
                    foregroundColor: DefensysTokens.maroon,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Dropdowns Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isAdmin) ...[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: currentScope,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Academic Scope',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Academic Tracks')),
                      DropdownMenuItem(value: 'capstone', child: Text('Capstone Project')),
                      DropdownMenuItem(value: 'pit_all', child: Text('PIT (All Tracks)')),
                      DropdownMenuItem(value: 'pit_1', child: Text('PIT (1st Year)')),
                      DropdownMenuItem(value: 'pit_2', child: Text('PIT (2nd Year)')),
                      DropdownMenuItem(value: 'pit_3', child: Text('PIT (3rd Year)')),
                      DropdownMenuItem(value: 'pit_4', child: Text('PIT (4th Year)')),
                    ],
                    onChanged: onScopeChanged,
                  ),
                ),
                const SizedBox(width: 10),
              ] else if (isPitLead) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: DefensysTokens.neutralBg,
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                    border: Border.all(color: DefensysTokens.border),
                  ),
                  child: Text(
                    'Scope: PIT (${user?['pit_lead_year'] ?? "N/A"})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.textDark,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: _FilterDropdown(
                  label: 'Category',
                  value: state.category,
                  options: _categoryOptions,
                  onChanged: ref.read(systemAuditProvider.notifier).setCategory,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FilterDropdown(
                  label: 'Review Status',
                  value: state.reviewStatus,
                  options: state.options['review_statuses'],
                  onChanged: ref.read(systemAuditProvider.notifier).setReviewStatus,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FilterDropdown(
                  label: 'Action',
                  value: state.action,
                  options: (state.options['actions'] as List?)
                      ?.map(
                        (item) => {'value': '$item', 'label': '$item'},
                      )
                      .toList(),
                  onChanged: ref.read(systemAuditProvider.notifier).setAction,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Inputs Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search evidence keywords',
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                  ),
                  onChanged: ref.read(systemAuditProvider.notifier).setSearch,
                  onSubmitted: (_) => ref.read(systemAuditProvider.notifier).fetch(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: startDateController,
                  readOnly: true,
                  onTap: onSelectStartDate,
                  decoration: const InputDecoration(
                    labelText: 'Start date',
                    hintText: 'YYYY-MM-DD',
                    border: OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: Icon(Icons.calendar_today_rounded, size: 16),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: endDateController,
                  readOnly: true,
                  onTap: onSelectEndDate,
                  decoration: const InputDecoration(
                    labelText: 'End date',
                    hintText: 'YYYY-MM-DD',
                    border: OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: Icon(Icons.calendar_today_rounded, size: 16),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                height: DefensysTokens.buttonHeightPrimary,
                child: FilledButton.icon(
                  onPressed: () => ref.read(systemAuditProvider.notifier).fetch(),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Apply'),
                  style: FilledButton.styleFrom(
                    backgroundColor: DefensysTokens.maroon,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: DefensysTokens.buttonHeightPrimary,
                child: OutlinedButton.icon(
                  onPressed: state.isLoading ? null : onQuickExport,
                  icon: reportsState.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download PDF'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DefensysTokens.maroon,
                    side: const BorderSide(color: DefensysTokens.maroon),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Active Filter Chips Bar
          if (_hasActiveFilters) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Active filters:',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.steelGrey,
                  ),
                ),
                if (state.category.isNotEmpty)
                  _ActiveChip(
                    label: 'Category: ${state.category}',
                    onDeleted: () =>
                        ref.read(systemAuditProvider.notifier).setCategory(''),
                  ),
                if (state.reviewStatus.isNotEmpty)
                  _ActiveChip(
                    label: 'Status: ${state.reviewStatus}',
                    onDeleted: () =>
                        ref.read(systemAuditProvider.notifier).setReviewStatus(''),
                  ),
                if (state.action.isNotEmpty)
                  _ActiveChip(
                    label: 'Action: ${state.action}',
                    onDeleted: () =>
                        ref.read(systemAuditProvider.notifier).setAction(''),
                  ),
                if (state.search.isNotEmpty)
                  _ActiveChip(
                    label: 'Search: "${state.search}"',
                    onDeleted: () {
                      searchController.clear();
                      ref.read(systemAuditProvider.notifier).setSearch('');
                      ref.read(systemAuditProvider.notifier).fetch();
                    },
                  ),
                if (state.startDate.isNotEmpty)
                  _ActiveChip(
                    label: 'From: ${state.startDate}',
                    onDeleted: () {
                      startDateController.clear();
                      ref.read(systemAuditProvider.notifier).setStartDate('');
                      ref.read(systemAuditProvider.notifier).fetch();
                    },
                  ),
                if (state.endDate.isNotEmpty)
                  _ActiveChip(
                    label: 'To: ${state.endDate}',
                    onDeleted: () {
                      endDateController.clear();
                      ref.read(systemAuditProvider.notifier).setEndDate('');
                      ref.read(systemAuditProvider.notifier).fetch();
                    },
                  ),
                if (state.track.isNotEmpty)
                  _ActiveChip(
                    label: 'Track: ${state.track}',
                    onDeleted: () {
                      ref.read(systemAuditProvider.notifier).setTrack('');
                    },
                  ),
                if (state.yearLevel.isNotEmpty)
                  _ActiveChip(
                    label: 'Year: ${state.yearLevel}',
                    onDeleted: () {
                      ref.read(systemAuditProvider.notifier).setYearLevel('');
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActiveChip extends StatelessWidget {
  final String label;
  final VoidCallback onDeleted;

  const _ActiveChip({required this.label, required this.onDeleted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: DefensysTokens.maroon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        border: Border.all(color: DefensysTokens.maroon.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.maroon,
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onDeleted,
            borderRadius: BorderRadius.circular(99),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: 14, color: DefensysTokens.maroon),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditTrailTable extends ConsumerWidget {
  final SystemAuditState state;

  const _AuditTrailTable({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedLog = state.selectedLog ?? (state.logs.isNotEmpty ? state.logs.first : null);

    return DefensysCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                color: DefensysTokens.maroon,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text('Audit Trail Register', style: DefensysUi.sectionTitle),
              const Spacer(),
              if (state.totalCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: DefensysTokens.neutralBg,
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                  ),
                  child: Text(
                    '${state.totalCount} total entries',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.steelGrey,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      'Loading audit logs...',
                      style: TextStyle(color: DefensysTokens.steelGrey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else if (state.error != null)
            _AuditMessage(
              icon: Icons.error_outline_rounded,
              title: 'Audit records could not be loaded',
              message: _auditErrorMessage(state.error!),
            )
          else if (state.logs.isEmpty)
            _AuditMessage(
              icon: Icons.info_outline_rounded,
              title: _hasAuditFilters(state)
                  ? 'No matching audit records'
                  : 'No audit records yet',
              message: _hasAuditFilters(state)
                  ? 'Try clearing a category, status, action, search, or date filter to widen the audit register.'
                  : 'New official academic actions and repository changes will appear here after they are logged.',
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: DefensysTokens.border),
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    showCheckboxColumn: false,
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                    headingTextStyle: DefensysUi.tableHeader,
                    dataRowMinHeight: 52,
                    dataRowMaxHeight: 56,
                    columns: const [
                      DataColumn(label: Text('DATE / TIME')),
                      DataColumn(label: Text('PROCESS AREA')),
                      DataColumn(label: Text('CONTROL ACTIVITY')),
                      DataColumn(label: Text('RESPONSIBLE USER')),
                      DataColumn(label: Text('REVIEW STATUS')),
                    ],
                    rows: state.logs.map((log) {
                      final isSelected =
                          selectedLog?['id']?.toString() == log['id']?.toString();
                      return DataRow(
                        selected: false,
                        color: WidgetStateProperty.resolveWith((states) {
                          if (isSelected) {
                            return const Color(0xFFE2E8F0); // Subtle soft slate highlight
                          }
                          if (states.contains(WidgetState.hovered)) {
                            return const Color(0xFFF1F5F9);
                          }
                          return Colors.white;
                        }),
                        onSelectChanged: (_) =>
                            ref.read(systemAuditProvider.notifier).selectLog(log),
                        cells: [
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.schedule,
                                  size: 14,
                                  color: isSelected ? DefensysTokens.maroon : DefensysTokens.steelGrey,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _dateTime(log['created_at']),
                                  style: DefensysUi.tableCell.copyWith(
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(_ProcessAreaBadge(category: log['category_label']?.toString() ?? '')),
                          DataCell(_ActionTag(action: log['action']?.toString() ?? '')),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: DefensysTokens.maroon.withValues(alpha: 0.1),
                                  child: Text(
                                    (log['actor_name']?.toString() ?? 'S')[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: DefensysTokens.maroon,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  log['actor_name']?.toString() ?? 'System',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: DefensysTokens.textDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(_ReviewStatusPill(log: log)),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Rows per page: ',
                      style: TextStyle(
                        fontSize: 12,
                        color: DefensysTokens.steelGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    DropdownButton<int>(
                      value: state.pageSize,
                      underline: const SizedBox(),
                      isDense: true,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: DefensysTokens.textDark,
                      ),
                      items: const [
                        DropdownMenuItem(value: 10, child: Text('10')),
                        DropdownMenuItem(value: 25, child: Text('25')),
                        DropdownMenuItem(value: 50, child: Text('50')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(systemAuditProvider.notifier).setPageSize(val);
                        }
                      },
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Showing page ${state.currentPage} of ${state.totalPages} (${state.totalCount} total entries)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: DefensysTokens.steelGrey,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Previous Page',
                      onPressed: state.currentPage > 1
                          ? () => ref
                              .read(systemAuditProvider.notifier)
                              .previousPage()
                          : null,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: DefensysTokens.neutralBg,
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      ),
                      child: Text(
                        'Page ${state.currentPage} / ${state.totalPages}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: DefensysTokens.textDark,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Next Page',
                      onPressed: state.currentPage < state.totalPages
                          ? () => ref
                              .read(systemAuditProvider.notifier)
                              .nextPage()
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProcessAreaBadge extends StatelessWidget {
  final String category;

  const _ProcessAreaBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    IconData icon = Icons.folder_open_outlined;
    if (category.toLowerCase().contains('grade')) {
      icon = Icons.grade_outlined;
    } else if (category.toLowerCase().contains('period')) {
      icon = Icons.date_range_outlined;
    } else if (category.toLowerCase().contains('schedul')) {
      icon = Icons.event_outlined;
    } else if (category.toLowerCase().contains('reposit')) {
      icon = Icons.folder_zip_outlined;
    } else if (category.toLowerCase().contains('guest')) {
      icon = Icons.person_pin_outlined;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: DefensysTokens.steelGrey),
        const SizedBox(width: 6),
        Text(
          category.isEmpty ? 'General' : category,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
            color: DefensysTokens.textDark,
          ),
        ),
      ],
    );
  }
}

class _ActionTag extends StatelessWidget {
  final String action;

  const _ActionTag({required this.action});

  @override
  Widget build(BuildContext context) {
    Color bg = DefensysTokens.neutralBg;
    Color fg = DefensysTokens.neutralText;
    Color border = DefensysTokens.neutralBorder;

    final lower = action.toLowerCase();
    if (lower.contains('delete') || lower.contains('remove')) {
      bg = DefensysTokens.dangerBg;
      fg = DefensysTokens.dangerText;
      border = DefensysTokens.dangerBorder;
    } else if (lower.contains('create') || lower.contains('upload') || lower.contains('add')) {
      bg = DefensysTokens.successBg;
      fg = DefensysTokens.successText;
      border = DefensysTokens.successBorder;
    } else if (lower.contains('override') || lower.contains('update') || lower.contains('edit')) {
      bg = DefensysTokens.overriddenBg;
      fg = DefensysTokens.overriddenText;
      border = DefensysTokens.overriddenBorder;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
        border: Border.all(color: border),
      ),
      child: Text(
        action.isEmpty ? 'action.unknown' : action,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }
}

class _ReviewStatusPill extends StatelessWidget {
  final Map<String, dynamic> log;

  const _ReviewStatusPill({required this.log});

  @override
  Widget build(BuildContext context) {
    final status = log['review_status']?.toString() ?? '';
    bool isReviewed = status == 'reviewed';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isReviewed ? DefensysTokens.successBg : DefensysTokens.warningBg,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        border: Border.all(
          color: isReviewed
              ? DefensysTokens.successBorder
              : DefensysTokens.warningBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isReviewed ? Icons.check_circle_outlined : Icons.pending_outlined,
            size: 13,
            color: isReviewed ? DefensysTokens.successText : DefensysTokens.warningText,
          ),
          const SizedBox(width: 4),
          Text(
            isReviewed ? 'Reviewed' : 'Needs Review',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isReviewed ? DefensysTokens.successText : DefensysTokens.warningText,
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceDetailsPanel extends ConsumerWidget {
  final Map<String, dynamic>? log;

  const _EvidenceDetailsPanel({required this.log});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = log;
    final status = item?['review_status']?.toString() ?? '';
    final isReviewed = status == 'reviewed';

    return DefensysCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: DefensysTokens.maroon,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Evidence Packet Preview',
                  style: DefensysUi.sectionTitle,
                ),
              ),
              if (item != null)
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: '${item['id']}'));
                    showSuccessToast(context, 'Log ID copied to clipboard');
                  },
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: DefensysTokens.neutralBg,
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                      border: Border.all(color: DefensysTokens.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ID: #${item['id'] ?? '-'}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: DefensysTokens.textDark,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.copy_rounded, size: 12, color: DefensysTokens.steelGrey),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (item == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  'Select an audit record to review its detailed evidence packet.',
                  style: TextStyle(color: DefensysTokens.steelGrey),
                ),
              ),
            )
          else ...[
            _DetailLine('Responsible User', item['actor_name'] ?? 'System'),
            _DetailLine('Timestamp', _dateTime(item['created_at'])),
            _DetailLine('Process Area', item['category_label']),
            _DetailLine('Action', item['action']),
            _DetailLine(
              'Target Resource',
              '${item['target_type'] ?? 'Resource'} #${item['target_id'] ?? '-'}',
            ),
            _DetailLine('Review Status', item['review_status_label']),
            _DetailLine('Reason Note', item['reason']),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: isReviewed
                  ? OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await ref
                            .read(systemAuditProvider.notifier)
                            .updateReviewStatus(item['id'] as int, 'needs_review');
                        if (context.mounted && ok) {
                          showSuccessToast(context, 'Log status reverted to Needs Review.');
                        }
                      },
                      icon: const Icon(Icons.undo_rounded, size: 16),
                      label: const Text('Mark as Needs Review'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DefensysTokens.warningText,
                        side: const BorderSide(color: DefensysTokens.warningBorder),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: () async {
                        final ok = await ref
                            .read(systemAuditProvider.notifier)
                            .updateReviewStatus(item['id'] as int, 'reviewed');
                        if (context.mounted && ok) {
                          showSuccessToast(context, 'Audit log verified & marked as Reviewed!');
                        }
                      },
                      icon: const Icon(Icons.check_circle_rounded, size: 16),
                      label: const Text('Mark as Reviewed'),
                      style: FilledButton.styleFrom(
                        backgroundColor: DefensysTokens.successText,
                        foregroundColor: Colors.white,
                      ),
                    ),
            ),
            const SizedBox(height: 14),

            // Visual Diff Viewer
            _VisualDiffViewer(
              oldValues: item['old_values'],
              newValues: item['new_values'],
            ),
          ],
        ],
      ),
    );
  }
}

class _VisualDiffViewer extends StatelessWidget {
  final dynamic oldValues;
  final dynamic newValues;

  const _VisualDiffViewer({
    required this.oldValues,
    required this.newValues,
  });

  @override
  Widget build(BuildContext context) {
    final oldMap = _asMap(oldValues);
    final newMap = _asMap(newValues);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Evidence Changes & Diff Log',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: DefensysTokens.steelGrey,
          ),
        ),
        const SizedBox(height: 8),

        // Old Values Block
        _DiffBlock(
          title: 'Previous Evidence',
          dataMap: oldMap,
          isOld: true,
        ),
        const SizedBox(height: 10),

        // New Values Block
        _DiffBlock(
          title: 'New Evidence',
          dataMap: newMap,
          isOld: false,
        ),
      ],
    );
  }

  Map<String, dynamic> _asMap(dynamic val) {
    if (val is Map) {
      return Map<String, dynamic>.from(val);
    }
    return {};
  }
}

class _DiffBlock extends StatelessWidget {
  final String title;
  final Map<String, dynamic> dataMap;
  final bool isOld;

  const _DiffBlock({
    required this.title,
    required this.dataMap,
    required this.isOld,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isOld ? DefensysTokens.dangerBg : DefensysTokens.successBg;
    final border = isOld ? DefensysTokens.dangerBorder : DefensysTokens.successBorder;
    final headerColor = isOld ? DefensysTokens.dangerText : DefensysTokens.successText;
    final icon = isOld ? Icons.remove_circle_outline : Icons.add_circle_outline;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: headerColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: headerColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (dataMap.isEmpty)
            Text(
              isOld ? 'No previous evidence recorded (Initial creation)' : 'No new evidence payload',
              style: const TextStyle(
                fontSize: 11.5,
                color: DefensysTokens.steelGrey,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Column(
              children: dataMap.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: headerColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText(
                          '${entry.value}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: DefensysTokens.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _FormSectionLabel extends StatelessWidget {
  final String label;

  const _FormSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: DefensysTokens.steelGrey,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final dynamic value;

  const _DetailLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final text = value?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: DefensysTokens.steelGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text.isEmpty ? '-' : text,
              style: const TextStyle(
                fontSize: 13,
                color: DefensysTokens.textDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _AuditMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.border),
      ),
      child: DefensysEmptyState.table(
        icon: icon,
        title: title,
        description: message,
        size: DefensysEmptyStateSize.standard,
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final dynamic options;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Map<String, dynamic>>[
      {'value': '', 'label': 'All $label'},
      ...List<Map<String, dynamic>>.from(options ?? const []),
    ];
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item['value']?.toString() ?? '',
              child: Text(
                item['label']?.toString() ?? '',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      selectedItemBuilder: (context) => items
          .map(
            (item) => Text(
              item['label']?.toString() ?? '',
              overflow: TextOverflow.ellipsis,
            ),
          )
          .toList(),
      onChanged: (next) => onChanged(next ?? ''),
    );
  }
}

const _categoryOptions = [
  {'value': 'academic_period', 'label': 'Academic Period Changes'},
  {'value': 'grade_center', 'label': 'Grade & Result Decisions'},
  {'value': 'scheduling', 'label': 'Schedule Changes'},
  {'value': 'repository', 'label': 'Project Archive Evidence'},
  {'value': 'guest_access', 'label': 'Guest Access Activity'},
];

int _count(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool _hasAuditFilters(SystemAuditState state) {
  return state.category.isNotEmpty ||
      state.reviewStatus.isNotEmpty ||
      state.action.isNotEmpty ||
      state.search.isNotEmpty ||
      state.startDate.isNotEmpty ||
      state.endDate.isNotEmpty;
}

String _auditErrorMessage(String error) {
  final lower = error.toLowerCase();
  if (lower.contains('signed out') ||
      lower.contains('session') ||
      lower.contains('token')) {
    return 'Your sign in session expired. Sign in again, then reopen Audit Trail to reload the records.';
  }
  return error;
}

String _dateTime(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return '';
  final date =
      '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  final time =
      '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}
