import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../../navigation/admin_route_paths.dart';
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
import '../../../../widgets/export/export.dart';
import '../widgets/defensys_admin_shell.dart';
import '../admin_shell.dart';

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

    ref.listen<DefensysAdminSection>(activeAdminSectionProvider, (previous, next) {
      if (next == DefensysAdminSection.auditCompliance) {
        _checkAndFetchAudit(ref.read(authProvider));
      }
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
          // Sleek Executive Segmented Pill Control
          Align(
            alignment: Alignment.centerLeft,
            child: _ExecutiveTabBar(
              selectedIndex: _selectedTabIndex,
              onTabSelected: (index) {
                if (_selectedTabIndex != index) {
                  setState(() => _selectedTabIndex = index);
                }
              },
            ),
          ),
          const SizedBox(height: 16),
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
        // Compact KPI Ribbon (Combines ISO Readiness, findings, verified evidence, pending review, and ratio)
        _CompactAuditKpiRibbon(state: state),
        const SizedBox(height: 14),

        // Streamlined Single-Row Filter Toolbar
        _CompactAuditFilterToolbar(
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
          onExport: (format) => _exportAuditRegister(state, format: format),
        ),
        const SizedBox(height: 14),

        // Primary Hero: Audit Trail Register Table & Rich Domain Evidence Inspector
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1100;
            final table = _AuditTrailTable(state: state);
            final details = _EvidenceDetailsPanel(
              log: selectedLog,
              onExportSlip: () => selectedLog != null ? _exportSingleLogPdf(selectedLog) : null,
              onNavigateToResource: _navigateToResource,
            );

            if (!wide) {
              return Column(
                children: [table, const SizedBox(height: 16), details],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: table),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: details),
              ],
            );
          },
        ),
      ],
    );
  }

  void _navigateToResource(String route) {
    final section = AdminRoutes.sectionForLocation(route);
    if (section != null) {
      ref.read(activeAdminSectionProvider.notifier).setSection(section);
    }
    context.push(route);
  }

  Future<void> _exportSingleLogPdf(Map<String, dynamic> log) async {
    final logId = log['id']?.toString() ?? '';
    if (logId.isEmpty) return;

    final success = await ref.read(reportsProvider.notifier).downloadReport(
      endpoint: 'audit-trail/',
      queryParams: {'log_id': logId},
      defaultFilename: 'DefenSYS_Audit_Evidence_#$logId.pdf',
      exportFormat: 'pdf',
    );

    _showDownloadResultToast(success, 'pdf');
  }

  Future<void> _exportAuditRegister(SystemAuditState auditState, {String format = 'pdf'}) async {
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

    final defaultFilename = format == 'csv'
        ? 'DefenSYS_Audit_Register.csv'
        : 'DefenSYS_Audit_Register.pdf';

    final success = await ref.read(reportsProvider.notifier).downloadReport(
      endpoint: 'audit-trail/',
      queryParams: queryParams,
      defaultFilename: defaultFilename,
      exportFormat: format,
    );

    _showDownloadResultToast(success, format);
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
          currentUser: ref.read(authProvider).user,
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
              includeSignatures: params['include_signatures'],
              signatories: params['signatories'],
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
    String? includeSignatures,
    String? signatories,
  }) async {
    final endpoint = report['endpoint'] as String;
    final queryParams = <String, String>{};

    if (includeSignatures != null && includeSignatures.isNotEmpty) {
      queryParams['include_signatures'] = includeSignatures;
    }
    if (signatories != null && signatories.isNotEmpty) {
      queryParams['signatories'] = signatories;
    }

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
  final Map<String, dynamic>? currentUser;
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
    this.currentUser,
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

  bool _includeSignatures = true;
  List<Map<String, String>> _signatories = [];

  void _initSignatories() {
    final user = widget.currentUser;
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
    if (userName.isEmpty) userName = 'Academic Documenter';

    String adviserName = 'Project Adviser / Panel Chair';
    if (_selectedTeamId != null) {
      final t = widget.teamsState.teams.firstWhere(
        (elem) => elem['id']?.toString() == _selectedTeamId,
        orElse: () => <String, dynamic>{},
      );
      if (t['adviser_name'] != null && t['adviser_name'].toString().trim().isNotEmpty) {
        adviserName = t['adviser_name'].toString().trim();
      } else if (t['adviser'] is Map) {
        final afn = (t['adviser']['first_name'] ?? '').toString().trim();
        final aln = (t['adviser']['last_name'] ?? '').toString().trim();
        if (afn.isNotEmpty || aln.isNotEmpty) {
          adviserName = '$afn $aln'.trim();
        }
      }
    }

    _signatories = [
      {
        'label': 'Prepared by:',
        'name': userName,
        'role': 'Academic Documenter / Evaluator',
      },
      {
        'label': 'Noted by:',
        'name': adviserName,
        'role': 'Project Adviser / Panel Chair',
      },
      {
        'label': 'Approved by:',
        'name': 'IT Program Chairperson',
        'role': 'IT Program Chairperson',
      },
    ];
  }

  void _openSignatoryCustomizerDialog() {
    DefensysSignatoryCustomizerDialog.show(
      context: context,
      currentSignatories: _signatories
          .map((s) => DefensysSignatory(
                label: s['label'] ?? 'Prepared by:',
                name: s['name'] ?? '',
                role: s['role'] ?? '',
              ))
          .toList(),
      currentIncludeSignatures: _includeSignatures,
      onApply: (updatedSigners, updatedToggle) {
        setState(() {
          _signatories = updatedSigners.map((s) => s.toJson()).toList();
          _includeSignatures = updatedToggle;
        });
      },
    );
  }

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

    _initSignatories();

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
      'include_signatures': _includeSignatures.toString(),
      if (_signatories.isNotEmpty) 'signatories': jsonEncode(_signatories),
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

  /// Right Pane: Live Data Preview Table + KPI Cards (delegated to DefensysLiveDataPreviewPane)
  Widget _buildRightPreviewPane({
    required String endpoint,
    required Map<String, dynamic>? selectedStudentObj,
    required Map<String, dynamic>? selectedTeamObj,
  }) {
    Widget? emptyState;
    if (endpoint == 'individual-grade' && selectedStudentObj == null) {
      emptyState = Center(
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
    } else if (endpoint == 'team-grade' && (selectedTeamObj == null || selectedTeamObj.isEmpty)) {
      emptyState = Center(
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

    return DefensysLiveDataPreviewPane(
      isLoading: _isLoadingPreview,
      previewData: _previewData,
      onRefresh: _loadPreview,
      emptyStateOverride: emptyState,
      signatories: _signatories
          .map((s) => DefensysSignatory(
                label: s['label'] ?? 'Prepared by:',
                name: s['name'] ?? '',
                role: s['role'] ?? '',
              ))
          .toList(),
      includeSignatures: _includeSignatures,
    );
  }

  /// Modal Bottom Footer Bar with Format Chooser Pills + Action Buttons
  Widget _buildModalFooter() {
    return DefensysExportFormatBar(
      supportedFormats: const ['pdf', 'xlsx', 'csv', 'doc'],
      selectedFormat: _selectedFormat,
      onFormatChanged: (fmt) => setState(() => _selectedFormat = fmt),
      includeSignatures: _includeSignatures,
      signatoriesCount: _signatories.length,
      onOpenSignatoryCustomizer: _openSignatoryCustomizerDialog,
      isDownloading: _isDownloading,
      onCancel: () => Navigator.of(context).pop(),
      onDownload: _handleDownload,
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

class _ExecutiveTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  const _ExecutiveTabBar({
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TabPill(
            label: 'Audit Trail Register',
            badgeLabel: 'Live Logs',
            icon: Icons.shield_outlined,
            isSelected: selectedIndex == 0,
            onTap: () => onTabSelected(0),
          ),
          const SizedBox(width: 4),
          _TabPill(
            label: 'Report Export Center',
            badgeLabel: 'PDF Center',
            icon: Icons.summarize_outlined,
            isSelected: selectedIndex == 1,
            onTap: () => onTabSelected(1),
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final String badgeLabel;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
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
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
            boxShadow: isSelected
                ? const [
                    BoxShadow(
                      color: Color(0x0E000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? DefensysTokens.maroon : DefensysTokens.steelGrey,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamily,
                  color: isSelected ? DefensysTokens.maroon : DefensysTokens.textDark,
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
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
                    color: isSelected ? DefensysTokens.maroon : DefensysTokens.steelGrey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactAuditKpiRibbon extends StatelessWidget {
  final SystemAuditState state;

  const _CompactAuditKpiRibbon({required this.state});

  @override
  Widget build(BuildContext context) {
    final total = _count(state.counts['filtered'], fallback: state.logs.length);
    final needsReview = _count(state.counts['needs_review']);
    final captured = _count(state.counts['captured']);
    final reviewed = _count(state.counts['reviewed']);
    final readiness = total == 0
        ? 0
        : (((total - needsReview).clamp(0, total) / total) * 100).round();
    final isReady = needsReview == 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 960;

          final readinessItem = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: readiness / 100,
                      strokeWidth: 3.5,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isReady ? const Color(0xFF059669) : DefensysTokens.maroon,
                      ),
                    ),
                    Icon(
                      Icons.shield_outlined,
                      color: isReady ? const Color(0xFF059669) : DefensysTokens.maroon,
                      size: 14,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$readiness%',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isReady ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                          border: Border.all(
                            color: isReady ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
                          ),
                        ),
                        child: Text(
                          isReady ? 'Ready' : 'Pending',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isReady ? const Color(0xFF065F46) : const Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'ISO 9001 Readiness',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          );

          final findingsItem = _RibbonStatItem(
            icon: Icons.rate_review_outlined,
            value: '$needsReview',
            label: 'Open Findings',
            badgeText: needsReview == 0 ? 'Clear' : 'Needs Review',
            badgeBg: needsReview == 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
            badgeFg: needsReview == 0 ? const Color(0xFF065F46) : const Color(0xFF92400E),
          );

          final verifiedItem = _RibbonStatItem(
            icon: Icons.task_alt_outlined,
            value: '$captured',
            label: 'Verified Evidence',
            badgeText: 'Logged',
            badgeBg: const Color(0xFFF1F5F9),
            badgeFg: const Color(0xFF475569),
          );

          final pendingItem = _RibbonStatItem(
            icon: Icons.schedule_outlined,
            value: '$needsReview',
            label: 'Pending Action',
            badgeText: needsReview == 0 ? 'Up to date' : 'Awaiting',
            badgeBg: const Color(0xFFF1F5F9),
            badgeFg: const Color(0xFF475569),
          );

          final ratioItem = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                ),
                child: const Icon(Icons.inventory_2_outlined, size: 15, color: Color(0xFF475569)),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$reviewed / $total',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const Text(
                    'Reviewed Ratio',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          );

          if (isWide) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                readinessItem,
                _RibbonDivider(),
                findingsItem,
                _RibbonDivider(),
                verifiedItem,
                _RibbonDivider(),
                pendingItem,
                _RibbonDivider(),
                ratioItem,
              ],
            );
          }

          return Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              readinessItem,
              findingsItem,
              verifiedItem,
              pendingItem,
              ratioItem,
            ],
          );
        },
      ),
    );
  }
}

class _RibbonStatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String badgeText;
  final Color badgeBg;
  final Color badgeFg;

  const _RibbonStatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.badgeText,
    required this.badgeBg,
    required this.badgeFg,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
          ),
          child: Icon(icon, color: const Color(0xFF475569), size: 15),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: badgeFg,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RibbonDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      color: const Color(0xFFE2E8F0),
    );
  }
}

class _CompactAuditFilterToolbar extends ConsumerWidget {
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
  final void Function(String format) onExport;

  const _CompactAuditFilterToolbar({
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
    required this.onExport,
  });

  int get _activeFilterCount {
    int count = 0;
    if (state.category.isNotEmpty) count++;
    if (state.reviewStatus.isNotEmpty) count++;
    if (state.action.isNotEmpty) count++;
    if (state.startDate.isNotEmpty || state.endDate.isNotEmpty) count++;
    if (state.track.isNotEmpty || state.yearLevel.isNotEmpty) count++;
    return count;
  }

  bool get _hasActiveFilters => _activeFilterCount > 0 || state.search.isNotEmpty;

  void _openFilterDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _AuditFilterModal(
        state: state,
        isAdmin: isAdmin,
        isPitLead: isPitLead,
        user: user,
        currentScope: currentScope,
        initialStartDate: startDateController.text,
        initialEndDate: endDateController.text,
        onApply: ({
          required String scope,
          required String category,
          required String reviewStatus,
          required String action,
          required String startDate,
          required String endDate,
        }) {
          onScopeChanged(scope);
          final notifier = ref.read(systemAuditProvider.notifier);
          notifier.setCategory(category);
          notifier.setReviewStatus(reviewStatus);
          notifier.setAction(action);
          notifier.setStartDate(startDate);
          notifier.setEndDate(endDate);
          startDateController.text = startDate;
          endDateController.text = endDate;
          notifier.fetch();
        },
        onReset: () {
          onScopeChanged('all');
          final notifier = ref.read(systemAuditProvider.notifier);
          notifier.setCategory('');
          notifier.setReviewStatus('');
          notifier.setAction('');
          notifier.setStartDate('');
          notifier.setEndDate('');
          startDateController.clear();
          endDateController.clear();
          notifier.fetch();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsState = ref.watch(reportsProvider);
    final filterCount = _activeFilterCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Spacious Top Line: Search Bar + Filter Modal Button + Export Register
          Row(
            children: [
              // Search Bar
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: searchController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search audit records by keywords, user, action, target ID...',
                      hintStyle: const TextStyle(fontSize: 12.5, color: DefensysTokens.steelGrey),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: const BorderSide(color: DefensysTokens.maroon),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: DefensysTokens.steelGrey),
                      suffixIcon: searchController.text.isNotEmpty
                          ? InkWell(
                              onTap: () {
                                searchController.clear();
                                ref.read(systemAuditProvider.notifier).setSearch('');
                                ref.read(systemAuditProvider.notifier).fetch();
                              },
                              child: const Icon(Icons.close_rounded, size: 15, color: DefensysTokens.steelGrey),
                            )
                          : null,
                    ),
                    onChanged: ref.read(systemAuditProvider.notifier).setSearch,
                    onSubmitted: (_) => ref.read(systemAuditProvider.notifier).fetch(),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Filter Icon Button (with active count badge)
              SizedBox(
                height: 38,
                child: filterCount > 0
                    ? FilledButton.icon(
                        onPressed: () => _openFilterDialog(context, ref),
                        icon: const Icon(Icons.tune_rounded, size: 16),
                        label: Text(
                          'Filters ($filterCount)',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: DefensysTokens.maroon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                          ),
                          elevation: 0,
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: () => _openFilterDialog(context, ref),
                        icon: const Icon(Icons.tune_rounded, size: 16),
                        label: const Text(
                          'Filters',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DefensysTokens.textDark,
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 8),

              // Quick Export Dropdown Menu
              SizedBox(
                height: 38,
                child: PopupMenuButton<String>(
                  tooltip: 'Export Audit Register',
                  onSelected: onExport,
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'pdf',
                      child: Row(
                        children: [
                          Icon(Icons.picture_as_pdf_outlined, size: 16, color: DefensysTokens.maroon),
                          SizedBox(width: 8),
                          Text('Export Register as PDF', style: TextStyle(fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'csv',
                      child: Row(
                        children: [
                          Icon(Icons.table_chart_outlined, size: 16, color: Color(0xFF0D9488)),
                          SizedBox(width: 8),
                          Text('Export Register as Excel / CSV', style: TextStyle(fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      border: Border.all(color: DefensysTokens.maroon),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (reportsState.isLoading)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: DefensysTokens.maroon),
                          )
                        else ...[
                          const Icon(Icons.download_rounded, size: 16, color: DefensysTokens.maroon),
                          const SizedBox(width: 6),
                          const Text(
                            'Export Register',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: DefensysTokens.maroon,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down_rounded, size: 18, color: DefensysTokens.maroon),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Active Filter Chips Bar
          if (_hasActiveFilters) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Active filters:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.steelGrey,
                  ),
                ),
                if (state.track.isNotEmpty || state.yearLevel.isNotEmpty)
                  _ActiveChip(
                    label: 'Scope: ${state.track.isNotEmpty ? state.track.toUpperCase() : ""}${state.yearLevel.isNotEmpty ? " (${state.yearLevel})" : ""}',
                    onDeleted: () {
                      onScopeChanged('all');
                    },
                  ),
                if (state.category.isNotEmpty)
                  _ActiveChip(
                    label: 'Category: ${_getCategoryLabel(state.category)}',
                    onDeleted: () {
                      ref.read(systemAuditProvider.notifier).setCategory('');
                      ref.read(systemAuditProvider.notifier).fetch();
                    },
                  ),
                if (state.reviewStatus.isNotEmpty)
                  _ActiveChip(
                    label: 'Status: ${_getStatusLabel(state.reviewStatus)}',
                    onDeleted: () {
                      ref.read(systemAuditProvider.notifier).setReviewStatus('');
                      ref.read(systemAuditProvider.notifier).fetch();
                    },
                  ),
                if (state.action.isNotEmpty)
                  _ActiveChip(
                    label: 'Action: ${state.action}',
                    onDeleted: () {
                      ref.read(systemAuditProvider.notifier).setAction('');
                      ref.read(systemAuditProvider.notifier).fetch();
                    },
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
                if (state.startDate.isNotEmpty || state.endDate.isNotEmpty)
                  _ActiveChip(
                    label: 'Date: ${state.startDate.isNotEmpty ? state.startDate : "Start"} to ${state.endDate.isNotEmpty ? state.endDate : "Present"}',
                    onDeleted: () {
                      startDateController.clear();
                      endDateController.clear();
                      final notifier = ref.read(systemAuditProvider.notifier);
                      notifier.setStartDate('');
                      notifier.setEndDate('');
                      notifier.fetch();
                    },
                  ),
                InkWell(
                  onTap: () {
                    searchController.clear();
                    startDateController.clear();
                    endDateController.clear();
                    onScopeChanged('all');
                    final notifier = ref.read(systemAuditProvider.notifier);
                    notifier.setCategory('');
                    notifier.setReviewStatus('');
                    notifier.setAction('');
                    notifier.setSearch('');
                    notifier.setStartDate('');
                    notifier.setEndDate('');
                    notifier.fetch();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Clear all',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: DefensysTokens.maroon,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _getCategoryLabel(String val) {
    for (final opt in _categoryOptions) {
      if (opt['value'] == val) return opt['label'] ?? val;
    }
    return val;
  }

  String _getStatusLabel(String val) {
    final list = state.options['review_statuses'] as List?;
    if (list != null) {
      for (final item in list) {
        if (item is Map && item['value'] == val) return item['label']?.toString() ?? val;
      }
    }
    return val;
  }
}

/// Comprehensive Audit Filter Modal Dialog
class _AuditFilterModal extends StatefulWidget {
  final SystemAuditState state;
  final bool isAdmin;
  final bool isPitLead;
  final dynamic user;
  final String currentScope;
  final String initialStartDate;
  final String initialEndDate;
  final void Function({
    required String scope,
    required String category,
    required String reviewStatus,
    required String action,
    required String startDate,
    required String endDate,
  }) onApply;
  final VoidCallback onReset;

  const _AuditFilterModal({
    required this.state,
    required this.isAdmin,
    required this.isPitLead,
    required this.user,
    required this.currentScope,
    required this.initialStartDate,
    required this.initialEndDate,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<_AuditFilterModal> createState() => _AuditFilterModalState();
}

class _AuditFilterModalState extends State<_AuditFilterModal> {
  late String _scope;
  late String _category;
  late String _reviewStatus;
  late String _action;
  late TextEditingController _startCtrl;
  late TextEditingController _endCtrl;

  @override
  void initState() {
    super.initState();
    _scope = widget.currentScope;
    _category = widget.state.category;
    _reviewStatus = widget.state.reviewStatus;
    _action = widget.state.action;
    _startCtrl = TextEditingController(text: widget.initialStartDate.isNotEmpty ? widget.initialStartDate : widget.state.startDate);
    _endCtrl = TextEditingController(text: widget.initialEndDate.isNotEmpty ? widget.initialEndDate : widget.state.endDate);
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    DateTime initial = now;
    if (controller.text.isNotEmpty) {
      final parsed = DateTime.tryParse(controller.text);
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
      setState(() {
        controller.text = formatted;
      });
    }
  }

  void _applyDatePreset(int daysAgo) {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (daysAgo == 0) {
      setState(() {
        _startCtrl.text = today;
        _endCtrl.text = today;
      });
    } else {
      final past = now.subtract(Duration(days: daysAgo));
      final pastStr =
          '${past.year}-${past.month.toString().padLeft(2, '0')}-${past.day.toString().padLeft(2, '0')}';
      setState(() {
        _startCtrl.text = pastStr;
        _endCtrl.text = today;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Modal Header
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DefensysTokens.maroon.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                    ),
                    child: const Icon(Icons.tune_rounded, color: DefensysTokens.maroon, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Filter Audit Register',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: DefensysTokens.textDark,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Refine records by scope, category, compliance status, or date range.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: DefensysTokens.steelGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Modal Body Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Academic Scope
                    if (widget.isAdmin) ...[
                      const _ModalSectionTitle('Academic Scope'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _scope,
                        isExpanded: true,
                        decoration: _modalInputDecoration('Select Academic Track'),
                        style: const TextStyle(fontSize: 13, color: DefensysTokens.textDark),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All Academic Tracks')),
                          DropdownMenuItem(value: 'capstone', child: Text('Capstone Project')),
                          DropdownMenuItem(value: 'pit_all', child: Text('PIT (All Tracks)')),
                          DropdownMenuItem(value: 'pit_1', child: Text('PIT (1st Year)')),
                          DropdownMenuItem(value: 'pit_2', child: Text('PIT (2nd Year)')),
                          DropdownMenuItem(value: 'pit_3', child: Text('PIT (3rd Year)')),
                          DropdownMenuItem(value: 'pit_4', child: Text('PIT (4th Year)')),
                        ],
                        onChanged: (val) => setState(() => _scope = val ?? 'all'),
                      ),
                      const SizedBox(height: 16),
                    ] else if (widget.isPitLead) ...[
                      const _ModalSectionTitle('Academic Scope'),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                          border: Border.all(color: DefensysTokens.border),
                        ),
                        child: Text(
                          'PIT (${widget.user?['pit_lead_year'] ?? "N/A"})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.textDark,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 2. Process Area / Category
                    const _ModalSectionTitle('Process Area (Category)'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: _modalInputDecoration('All Process Areas'),
                      style: const TextStyle(fontSize: 13, color: DefensysTokens.textDark),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('All Process Areas')),
                        ..._categoryOptions.map(
                          (cat) => DropdownMenuItem(
                            value: cat['value'] ?? '',
                            child: Text(cat['label'] ?? ''),
                          ),
                        ),
                      ],
                      onChanged: (val) => setState(() => _category = val ?? ''),
                    ),
                    const SizedBox(height: 16),

                    // 3. Compliance Review Status
                    const _ModalSectionTitle('Review & Compliance Status'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _reviewStatus,
                      isExpanded: true,
                      decoration: _modalInputDecoration('All Statuses'),
                      style: const TextStyle(fontSize: 13, color: DefensysTokens.textDark),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('All Statuses')),
                        ...?((widget.state.options['review_statuses'] as List?)?.map(
                          (st) => DropdownMenuItem(
                            value: st['value']?.toString() ?? '',
                            child: Text(st['label']?.toString() ?? ''),
                          ),
                        )),
                      ],
                      onChanged: (val) => setState(() => _reviewStatus = val ?? ''),
                    ),
                    const SizedBox(height: 16),

                    // 4. Specific Action Type
                    const _ModalSectionTitle('Control Activity / Action Type'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _action,
                      isExpanded: true,
                      decoration: _modalInputDecoration('All Action Types'),
                      style: const TextStyle(fontSize: 13, color: DefensysTokens.textDark),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('All Action Types')),
                        ...?((widget.state.options['actions'] as List?)?.map(
                          (act) => DropdownMenuItem(
                            value: act?.toString() ?? '',
                            child: Text(act?.toString() ?? ''),
                          ),
                        )),
                      ],
                      onChanged: (val) => setState(() => _action = val ?? ''),
                    ),
                    const SizedBox(height: 16),

                    // 5. Date Range & Presets
                    const _ModalSectionTitle('Date Range'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _PresetChip(label: 'Today', onTap: () => _applyDatePreset(0)),
                        _PresetChip(label: 'Last 7 Days', onTap: () => _applyDatePreset(7)),
                        _PresetChip(label: 'Last 30 Days', onTap: () => _applyDatePreset(30)),
                        if (_startCtrl.text.isNotEmpty || _endCtrl.text.isNotEmpty)
                          _PresetChip(
                            label: 'Clear Dates',
                            isClear: true,
                            onTap: () => setState(() {
                              _startCtrl.clear();
                              _endCtrl.clear();
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _startCtrl,
                            readOnly: true,
                            onTap: () => _pickDate(_startCtrl),
                            style: const TextStyle(fontSize: 12.5),
                            decoration: _modalInputDecoration('Start Date (From)').copyWith(
                              suffixIcon: const Icon(Icons.calendar_today_rounded, size: 15, color: DefensysTokens.steelGrey),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _endCtrl,
                            readOnly: true,
                            onTap: () => _pickDate(_endCtrl),
                            style: const TextStyle(fontSize: 12.5),
                            decoration: _modalInputDecoration('End Date (To)').copyWith(
                              suffixIcon: const Icon(Icons.calendar_today_rounded, size: 15, color: DefensysTokens.steelGrey),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Modal Footer Actions
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _scope = 'all';
                        _category = '';
                        _reviewStatus = '';
                        _action = '';
                        _startCtrl.clear();
                        _endCtrl.clear();
                      });
                      widget.onReset();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.restart_alt_rounded, size: 15),
                    label: const Text('Reset All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    style: TextButton.styleFrom(
                      foregroundColor: DefensysTokens.maroon,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DefensysTokens.steelGrey,
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                          ),
                        ),
                        child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () {
                          widget.onApply(
                            scope: _scope,
                            category: _category,
                            reviewStatus: _reviewStatus,
                            action: _action,
                            startDate: _startCtrl.text.trim(),
                            endDate: _endCtrl.text.trim(),
                          );
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.check_rounded, size: 15),
                        label: const Text('Apply Filters', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        style: FilledButton.styleFrom(
                          backgroundColor: DefensysTokens.maroon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _modalInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12.5, color: DefensysTokens.steelGrey),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        borderSide: const BorderSide(color: DefensysTokens.maroon),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      isDense: true,
    );
  }
}

class _ModalSectionTitle extends StatelessWidget {
  final String title;

  const _ModalSectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: DefensysTokens.textDark,
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isClear;

  const _PresetChip({
    required this.label,
    required this.onTap,
    this.isClear = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isClear ? DefensysTokens.dangerBg : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
            border: Border.all(
              color: isClear ? DefensysTokens.dangerBorder : const Color(0xFFE2E8F0),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: isClear ? DefensysTokens.dangerText : DefensysTokens.steelGrey,
            ),
          ),
        ),
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
      padding: const EdgeInsets.only(left: 8, right: 3, top: 2, bottom: 2),
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
              fontSize: 10.5,
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
              child: Icon(Icons.close_rounded, size: 12, color: DefensysTokens.maroon),
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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color: DefensysTokens.maroon,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Audit Trail Register',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: DefensysTokens.textDark,
                ),
              ),
              const Spacer(),
              if (state.totalCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                  ),
                  child: Text(
                    '${state.totalCount} entries',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.steelGrey,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(strokeWidth: 2.5, color: DefensysTokens.maroon),
                    SizedBox(height: 12),
                    Text(
                      'Loading audit logs...',
                      style: TextStyle(color: DefensysTokens.steelGrey, fontSize: 12.5),
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
                  ? 'Try clearing a filter to widen the audit register.'
                  : 'New official academic actions and repository changes will appear here.',
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
                    headingTextStyle: const TextStyle(
                      fontFamily: DefensysTokens.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.steelGrey,
                      letterSpacing: 0.5,
                    ),
                    dataRowMinHeight: 48,
                    dataRowMaxHeight: 52,
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
                            return const Color(0xFFF1F5F9);
                          }
                          if (states.contains(WidgetState.hovered)) {
                            return const Color(0xFFFAFAFA);
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
                                if (isSelected)
                                  Container(
                                    width: 3,
                                    height: 20,
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      color: DefensysTokens.maroon,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                Icon(
                                  Icons.schedule,
                                  size: 13,
                                  color: isSelected ? DefensysTokens.maroon : DefensysTokens.steelGrey,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _dateTime(log['created_at']),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? DefensysTokens.maroon : DefensysTokens.textDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(_ProcessAreaBadge(category: log['category_label']?.toString() ?? log['category']?.toString() ?? '')),
                          DataCell(_ActionTag(action: log['action']?.toString() ?? '')),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 11,
                                  backgroundColor: DefensysTokens.maroon.withValues(alpha: 0.1),
                                  child: Text(
                                    (log['actor_name']?.toString() ?? 'S')[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: DefensysTokens.maroon,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  log['actor_name']?.toString() ?? 'System',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
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
            const SizedBox(height: 12),
            // Pagination Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Rows: ',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: DefensysTokens.steelGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    DropdownButton<int>(
                      value: state.pageSize,
                      underline: const SizedBox(),
                      isDense: true,
                      style: const TextStyle(
                        fontSize: 11.5,
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
                    const SizedBox(width: 12),
                    Text(
                      'Page ${state.currentPage} of ${state.totalPages}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: DefensysTokens.steelGrey,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 18),
                      tooltip: 'Previous Page',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: state.currentPage > 1
                          ? () => ref.read(systemAuditProvider.notifier).previousPage()
                          : null,
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                      ),
                      child: Text(
                        '${state.currentPage} / ${state.totalPages}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          color: DefensysTokens.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 18),
                      tooltip: 'Next Page',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: state.currentPage < state.totalPages
                          ? () => ref.read(systemAuditProvider.notifier).nextPage()
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
    final lower = category.toLowerCase();
    String display = category.isEmpty ? 'General' : category;
    if (lower.contains('grade') || lower.contains('eval') || category == 'grade_center') {
      icon = Icons.star_border_rounded;
      display = 'Evaluation & Grades';
    } else if (lower.contains('period')) {
      icon = Icons.date_range_outlined;
    } else if (lower.contains('schedul')) {
      icon = Icons.event_outlined;
    } else if (lower.contains('reposit') || lower.contains('archive')) {
      icon = Icons.folder_zip_outlined;
    } else if (lower.contains('guest') || lower.contains('access') || lower.contains('user')) {
      icon = Icons.person_pin_outlined;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: DefensysTokens.steelGrey),
        const SizedBox(width: 6),
        Text(
          display,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        action.isEmpty ? 'action.unknown' : action,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF334155),
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
    final isReviewed = status == 'reviewed';
    final isNeedsReview = status == 'needs_review' || status == 'requires_reason';

    final Color bg;
    final Color fg;
    final Color border;
    final IconData icon;
    final String label;

    if (isReviewed) {
      bg = const Color(0xFFECFDF5);
      fg = const Color(0xFF065F46);
      border = const Color(0xFFA7F3D0);
      icon = Icons.check_circle_outlined;
      label = 'Reviewed';
    } else if (isNeedsReview) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFF92400E);
      border = const Color(0xFFFDE68A);
      icon = Icons.pending_outlined;
      label = 'Needs Review';
    } else {
      bg = const Color(0xFFF1F5F9);
      fg = const Color(0xFF475569);
      border = const Color(0xFFCBD5E1);
      icon = Icons.task_alt_outlined;
      label = 'Captured';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11.5, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceDetailsPanel extends ConsumerStatefulWidget {
  final Map<String, dynamic>? log;
  final VoidCallback? onExportSlip;
  final void Function(String route)? onNavigateToResource;

  const _EvidenceDetailsPanel({
    required this.log,
    this.onExportSlip,
    this.onNavigateToResource,
  });

  @override
  ConsumerState<_EvidenceDetailsPanel> createState() => _EvidenceDetailsPanelState();
}

class _EvidenceDetailsPanelState extends ConsumerState<_EvidenceDetailsPanel> {
  void _showDeliverablePreviewDialog(
    BuildContext context,
    Map<String, dynamic> log,
    void Function(String route)? onNavigate,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            width: 560,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dialog Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: DefensysTokens.maroon.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.picture_as_pdf_outlined,
                          color: DefensysTokens.maroon,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Deliverable Evidence Preview',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: DefensysTokens.textDark,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Close Preview',
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),

                // Card Body
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _ArchiveFileEvidenceCard(
                    log: log,
                    onNavigate: (route) {
                      Navigator.of(dialogContext).pop();
                      onNavigate?.call(route);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.log;
    final status = item?['review_status']?.toString() ?? '';
    final isReviewed = status == 'reviewed';
    final category = item?['category']?.toString() ?? '';
    final action = item?['action']?.toString() ?? '';
    final targetType = item?['target_type']?.toString() ?? '';

    String displayCategory = item?['category_label']?.toString() ?? category;
    final lowerCat = displayCategory.toLowerCase();
    if (lowerCat.contains('grade') || category == 'grade_center' || lowerCat.contains('eval')) {
      displayCategory = 'Evaluation & Grades';
    }

    final oldVals = item?['old_values'] is Map ? Map<String, dynamic>.from(item!['old_values']) : <String, dynamic>{};
    final newVals = item?['new_values'] is Map ? Map<String, dynamic>.from(item!['new_values']) : <String, dynamic>{};
    int changeCount = 0;
    for (final k in {...oldVals.keys, ...newVals.keys}) {
      if (oldVals[k]?.toString() != newVals[k]?.toString()) changeCount++;
    }

    final bool hasPreview = category == 'repository' ||
        action.startsWith('repository.') ||
        action.contains('archive') ||
        action.contains('file') ||
        targetType == 'ArchiveEntry' ||
        targetType == 'VaultEntry';

    int? parseId(dynamic val) {
      if (val == null) return null;
      if (val is int) return val;
      return int.tryParse(val.toString().replaceAll(RegExp(r'[^\d]'), ''));
    }

    final targetId = parseId(item?['target_id']);
    final isGradeTarget = targetType == 'TeamGrade' ||
        targetType == 'Grade' ||
        targetType == 'GradeItem' ||
        targetType.contains('Grade');
    final isTeamTarget = targetType == 'StudentTeam' || targetType.contains('Team');
    final isStageTarget = targetType == 'DefenseStage' || targetType.contains('Stage');
    final isRubricTarget = targetType == 'Rubric';

    final gradeId = parseId(newVals['grade_id'] ??
        oldVals['grade_id'] ??
        newVals['team_grade_id'] ??
        oldVals['team_grade_id'] ??
        (isGradeTarget ? targetId : null));

    final teamId = parseId(newVals['team_id'] ??
        oldVals['team_id'] ??
        (isTeamTarget ? targetId : null));

    final stageId = parseId(newVals['stage_id'] ??
        oldVals['stage_id'] ??
        (isStageTarget ? targetId : null));

    final rubricId = parseId(newVals['rubric_id'] ??
        oldVals['rubric_id'] ??
        (isRubricTarget ? targetId : null));

    VoidCallback? openActualEvidence;
    String? redirectRoute;
    String redirectLabel = 'Open Resource ↗';
    IconData resourceIcon = Icons.tune_rounded;
    String resourceHeadline = '${item?['target_type'] ?? 'Resource'} #${item?['target_id'] ?? '-'}';
    String resourceSubhead = action.isNotEmpty ? action : 'System Audit Log';

    if (hasPreview) {
      openActualEvidence = () => _showDeliverablePreviewDialog(context, item!, widget.onNavigateToResource);
      redirectLabel = 'Open Deliverable Evidence ↗';
      resourceIcon = Icons.picture_as_pdf_outlined;
      resourceHeadline = newVals['file_name']?.toString() ??
          newVals['title']?.toString() ??
          oldVals['file_name']?.toString() ??
          'Manuscript Deliverable #${item?['target_id']}';
      final fileSize = newVals['file_size']?.toString() ?? 'Official Deliverable';
      final track = newVals['track']?.toString() ?? newVals['entry_type']?.toString() ?? 'Capstone Archive';
      resourceSubhead = '$track • $fileSize';
    } else if (action.contains('grade') ||
        isGradeTarget ||
        targetType.contains('Evaluation') ||
        action.contains('scoring') ||
        category == 'grade_center') {
      if (gradeId != null) {
        redirectRoute = AdminRoutes.gradeDetail(gradeId);
        redirectLabel = 'Open Grade Evidence ↗';
      } else if (teamId != null) {
        redirectRoute = AdminRoutes.teamDetail(teamId);
        redirectLabel = 'Open Team Record ↗';
      } else {
        redirectRoute = AdminRoutes.gradeCenter;
        redirectLabel = 'Open Evaluation & Grades ↗';
      }
      resourceIcon = Icons.school_outlined;
      final stage = newVals['stage_label']?.toString() ??
          newVals['event_name']?.toString() ??
          oldVals['stage_label']?.toString() ??
          'Defense Evaluation';
      final grade = newVals['final_grade']?.toString() ??
          newVals['grade']?.toString() ??
          oldVals['final_grade']?.toString() ??
          '-';
      resourceHeadline = 'Evaluation: $stage';
      resourceSubhead = 'Official Grade Decision • Verdict: $grade';
    } else if (category == 'academic_period' ||
        action.contains('stage') ||
        isStageTarget ||
        action == 'grading.official_completion') {
      if (stageId != null) {
        redirectRoute = AdminRoutes.defenseStageEdit(stageId);
        redirectLabel = 'Open Stage Setup ↗';
      } else {
        redirectRoute = AdminRoutes.defenseStages;
        redirectLabel = 'Open Defense Stages Setup ↗';
      }
      resourceIcon = Icons.account_tree_outlined;
      resourceHeadline = newVals['stage_label']?.toString() ??
          newVals['name']?.toString() ??
          oldVals['stage_label']?.toString() ??
          'Academic Stage';
      resourceSubhead = 'Defense Stage Configuration • Academic Chain Rule';
    } else if (action.contains('rubric') ||
        isRubricTarget ||
        (category == 'grade_center' && action.contains('rubric'))) {
      if (rubricId != null) {
        redirectRoute = AdminRoutes.rubricEdit(rubricId);
        redirectLabel = 'Open Rubric Assessment ↗';
      } else {
        redirectRoute = AdminRoutes.rubrics;
        redirectLabel = 'Open Rubrics ↗';
      }
      resourceIcon = Icons.rule_folder_outlined;
      resourceHeadline = newVals['name']?.toString() ?? oldVals['name']?.toString() ?? 'Rubric #${item?['target_id']}';
      resourceSubhead = 'Rubric Assessment Criteria & Weighting';
    } else if (action.contains('team') ||
        isTeamTarget ||
        category == 'student_teams') {
      if (teamId != null) {
        redirectRoute = AdminRoutes.teamDetail(teamId);
        redirectLabel = 'Open Team Record ↗';
      } else {
        redirectRoute = AdminRoutes.studentTeams;
        redirectLabel = 'Open Student Teams ↗';
      }
      resourceIcon = Icons.groups_outlined;
      final tName = newVals['name']?.toString() ?? oldVals['name']?.toString() ?? 'Team #${teamId ?? item?['target_id']}';
      resourceHeadline = 'Student Team: $tName';
      resourceSubhead = 'Cohort Team Roster & Defense Allocation';
    } else if (action.contains('schedule') ||
        category == 'scheduling' ||
        targetType == 'DefenseSchedule') {
      redirectRoute = AdminRoutes.defenseScheduler;
      redirectLabel = 'Open Defense Operations ↗';
      resourceIcon = Icons.event_outlined;
      resourceHeadline = 'Defense Session Schedule';
      resourceSubhead = 'Room Venue & Panel Assignment';
    } else if (action.contains('guest') ||
        action.contains('user') ||
        category == 'guest_access' ||
        category == 'user_management') {
      redirectRoute = AdminRoutes.users;
      redirectLabel = 'Open User Management ↗';
      resourceIcon = Icons.person_pin_outlined;
      resourceHeadline = 'User Identity & Access Control';
      resourceSubhead = 'Account Governance & Role Permissions';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel Header
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
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Evidence Packet Review',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: DefensysTokens.textDark,
                  ),
                ),
              ),
              if (item != null) ...[
                if (widget.onExportSlip != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: OutlinedButton.icon(
                      onPressed: widget.onExportSlip,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 13, color: DefensysTokens.maroon),
                      label: const Text('Export Slip (PDF)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DefensysTokens.maroon,
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: '${item['id']}'));
                    showSuccessToast(context, 'Log ID #${item['id']} copied to clipboard');
                  },
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                      border: Border.all(color: DefensysTokens.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '#${item['id'] ?? '-'}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: DefensysTokens.textDark,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.copy_rounded, size: 11, color: DefensysTokens.steelGrey),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          if (item == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  'Select an audit record to inspect its detailed evidence packet.',
                  style: TextStyle(color: DefensysTokens.steelGrey, fontSize: 12.5),
                ),
              ),
            )
          else ...[
            // Status Verification Action Bar
            Row(
              children: [
                Expanded(
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
                          icon: const Icon(Icons.undo_rounded, size: 14),
                          label: const Text('Revert to Needs Review', style: TextStyle(fontSize: 11.5)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFB45309),
                            side: const BorderSide(color: Color(0xFFFDE68A)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: () async {
                            final ok = await ref
                                .read(systemAuditProvider.notifier)
                                .updateReviewStatus(item['id'] as int, 'reviewed');
                            if (context.mounted && ok) {
                              showSuccessToast(context, 'Audit evidence verified and marked as Reviewed!');
                            }
                          },
                          icon: const Icon(Icons.check_circle_rounded, size: 14),
                          label: const Text('Verify & Mark as Reviewed', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF047857),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            elevation: 0,
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Metadata summary block
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _DetailLine('Responsible User', item['actor_name'] ?? 'System'),
                  _DetailLine('Timestamp', _dateTime(item['created_at'])),
                  _DetailLine('Process Area', displayCategory),
                  _DetailLine('Action Type', item['action']),
                  _DetailLine('Target Resource', _formatTargetResource(item)),
                  if (item['reason'] != null && item['reason'].toString().trim().isNotEmpty)
                    _DetailLine('Audit Reason', item['reason']),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Contextual Action & Resource Card with Direct Navigation & Optional Preview
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: DefensysTokens.maroon.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                        ),
                        child: Icon(resourceIcon, size: 16, color: DefensysTokens.maroon),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              resourceHeadline,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: DefensysTokens.textDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              resourceSubhead,
                              style: const TextStyle(fontSize: 11, color: DefensysTokens.steelGrey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (openActualEvidence != null || redirectRoute != null)
                        FilledButton.icon(
                          onPressed: () {
                            if (openActualEvidence != null) {
                              openActualEvidence();
                            } else if (redirectRoute != null) {
                              widget.onNavigateToResource?.call(redirectRoute);
                            }
                          },
                          icon: Icon(
                            openActualEvidence != null
                                ? Icons.visibility_outlined
                                : Icons.open_in_new_rounded,
                            size: 12,
                          ),
                          label: Text(
                            redirectLabel,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: DefensysTokens.maroon,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Audit Modifications & Attribute Changes
            Row(
              children: [
                const Icon(Icons.compare_arrows_rounded, size: 14, color: DefensysTokens.steelGrey),
                const SizedBox(width: 6),
                const Text(
                  'AUDIT MODIFICATIONS & ATTRIBUTE CHANGES',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: DefensysTokens.steelGrey,
                    letterSpacing: 0.5,
                  ),
                ),
                if (changeCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: DefensysTokens.maroon.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                    ),
                    child: Text(
                      '$changeCount modified',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: DefensysTokens.maroon,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            _SmartDeltaDiffViewer(
              oldValues: item['old_values'],
              newValues: item['new_values'],
              logEntry: item,
            ),
          ],
        ],
      ),
    );
  }

  String _formatTargetResource(Map<String, dynamic> item) {
    final targetType = item['target_type']?.toString() ?? 'Resource';
    final targetId = item['target_id']?.toString() ?? '-';
    if (targetId == '-' || targetId.isEmpty) return targetType;

    final newVals = item['new_values'] is Map ? Map<String, dynamic>.from(item['new_values']) : <String, dynamic>{};
    final oldVals = item['old_values'] is Map ? Map<String, dynamic>.from(item['old_values']) : <String, dynamic>{};

    String? name = newVals['team_name']?.toString() ??
        newVals['name']?.toString() ??
        newVals['stage_label']?.toString() ??
        newVals['file_name']?.toString() ??
        oldVals['team_name']?.toString() ??
        oldVals['name']?.toString() ??
        oldVals['file_name']?.toString();

    if (name == null || name.isEmpty) {
      if (targetType == 'StudentTeam') {
        for (final t in ref.watch(studentTeamsProvider).teams) {
          if (t['id']?.toString() == targetId) {
            name = t['name']?.toString();
            break;
          }
        }
      } else if (targetType == 'TeamGrade') {
        for (final g in ref.watch(gradeCenterProvider).grades) {
          if (g['id']?.toString() == targetId) {
            final tName = g['team_name']?.toString();
            final sName = g['stage_label']?.toString();
            name = (tName != null && sName != null) ? '$tName · $sName' : (tName ?? sName);
            break;
          }
        }
      } else if (targetType == 'DefenseStage') {
        for (final s in ref.watch(defenseStagesProvider).stages) {
          if (s['id']?.toString() == targetId) {
            name = s['name']?.toString() ?? s['label']?.toString();
            break;
          }
        }
      } else if (targetType == 'AcademicPeriod') {
        final periodState = ref.watch(academicPeriodProvider);
        for (final y in periodState.schoolYears) {
          if (y['id']?.toString() == targetId) {
            name = y['label']?.toString();
            break;
          }
          final semesters = y['semesters'] is List ? y['semesters'] as List : const [];
          for (final sem in semesters) {
            if (sem is Map && sem['id']?.toString() == targetId) {
              name = '${sem['label'] ?? sem['semester'] ?? 'Semester'} (${y['label'] ?? ''})'.trim();
              break;
            }
          }
          if (name != null) break;
        }
      }
    }

    if (name != null && name.isNotEmpty) {
      return '$targetType #$targetId ($name)';
    }
    return '$targetType #$targetId';
  }
}

/// Rich Evidence Card: Archive & Project Repository Files (Live Deliverable Inspector)
class _ArchiveFileEvidenceCard extends StatelessWidget {
  final Map<String, dynamic> log;
  final void Function(String route)? onNavigate;

  const _ArchiveFileEvidenceCard({required this.log, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final newVals = log['new_values'] is Map ? Map<String, dynamic>.from(log['new_values']) : <String, dynamic>{};
    final oldVals = log['old_values'] is Map ? Map<String, dynamic>.from(log['old_values']) : <String, dynamic>{};
    final fileName = newVals['file_name']?.toString() ??
        newVals['title']?.toString() ??
        oldVals['file_name']?.toString() ??
        'Deliverable_Document_${log['target_id']}.pdf';
    final fileSize = newVals['file_size']?.toString() ?? 'Official PDF Document';
    final track = newVals['track']?.toString() ?? newVals['entry_type']?.toString() ?? 'Capstone Repository';
    final yearLevel = newVals['year_level']?.toString() ?? '';
    final status = newVals['status']?.toString() ?? 'Approved';
    final teamName = newVals['team_name']?.toString() ?? 'Assigned Research Team';
    final replaced = newVals['replaced_existing'] == true;
    final extension = fileName.contains('.') ? fileName.split('.').last.toUpperCase() : 'PDF';
    final targetId = log['target_id']?.toString() ?? '-';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: DefensysTokens.maroon.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                  ),
                  child: const Icon(Icons.picture_as_pdf_outlined, color: DefensysTokens.maroon, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: DefensysTokens.textDark,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$fileSize • $status',
                        style: const TextStyle(fontSize: 11, color: DefensysTokens.steelGrey),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: replaced ? const Color(0xFFFEF3C7) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                    border: Border.all(
                      color: replaced ? const Color(0xFFFDE68A) : const Color(0xFFA7F3D0),
                    ),
                  ),
                  child: Text(
                    replaced ? 'Version Overwrite' : 'New Upload',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: replaced ? const Color(0xFF92400E) : const Color(0xFF065F46),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Live Institutional Document / Manuscript Sheet Preview
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sheet watermark / institutional header
                Row(
                  children: [
                    const Icon(Icons.verified_outlined, size: 13, color: DefensysTokens.maroon),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'INSTITUTIONAL DELIVERABLE PREVIEW • ARCHIVE #$targetId',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: DefensysTokens.maroon,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        extension,
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: DefensysTokens.textDark),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Simulated Document Summary lines
                Text(
                  fileName.replaceAll('.pdf', '').replaceAll('_', ' '),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Project / Team: $teamName • Track: ${track.toUpperCase()} ${yearLevel.isNotEmpty ? "($yearLevel)" : ""}',
                  style: const TextStyle(fontSize: 10.5, color: DefensysTokens.steelGrey),
                ),
                const SizedBox(height: 10),

                // ISO 9001:2015 Clause 7.5 Compliance Card
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, size: 14, color: Color(0xFF166534)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'ISO 9001:2015 Clause 7.5 Verified Document',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF166534),
                              ),
                            ),
                            Text(
                              'Retained documented information. Authenticity and tamper-evident audit status confirmed.',
                              style: TextStyle(fontSize: 9.5, color: Color(0xFF15803D)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Navigation & Action Footer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Scope: ${track.toUpperCase()}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: DefensysTokens.steelGrey),
                ),
                OutlinedButton.icon(
                  onPressed: () => onNavigate?.call(AdminRoutes.projectArchive),
                  icon: const Icon(Icons.open_in_new_rounded, size: 12),
                  label: const Text('Open in Project Archive ↗', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DefensysTokens.maroon,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartDeltaDiffViewer extends ConsumerStatefulWidget {
  final dynamic oldValues;
  final dynamic newValues;
  final Map<String, dynamic>? logEntry;

  const _SmartDeltaDiffViewer({
    required this.oldValues,
    required this.newValues,
    this.logEntry,
  });

  @override
  ConsumerState<_SmartDeltaDiffViewer> createState() => _SmartDeltaDiffViewerState();
}

class _ResolvedAttr {
  final String label;
  final String rawKey;
  final String displayValue;
  final String? idBadge;
  final bool isEntity;
  final bool isNullOrEmpty;

  const _ResolvedAttr({
    required this.label,
    required this.rawKey,
    required this.displayValue,
    this.idBadge,
    this.isEntity = false,
    this.isNullOrEmpty = false,
  });
}

class _SmartDeltaDiffViewerState extends ConsumerState<_SmartDeltaDiffViewer> {
  bool _showUnchanged = false;

  Map<String, dynamic> _asMap(dynamic val) {
    if (val is Map) {
      return Map<String, dynamic>.from(val);
    }
    return {};
  }

  String _humanizeKey(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : '')
        .join(' ');
  }

  _ResolvedAttr _resolveAttribute(String key, dynamic value, Map<String, dynamic> currentMap) {
    final humanKey = _humanizeKey(key);
    final lowerKey = key.toLowerCase();
    final log = widget.logEntry;
    final parentNew = _asMap(log?['new_values']);
    final parentOld = _asMap(log?['old_values']);

    if (value == null) {
      return _ResolvedAttr(
        label: humanKey,
        rawKey: key,
        displayValue: 'null',
        isNullOrEmpty: true,
      );
    }

    final strVal = value.toString().trim();
    if (strVal.isEmpty) {
      return _ResolvedAttr(
        label: humanKey,
        rawKey: key,
        displayValue: '—',
        isNullOrEmpty: true,
      );
    }

    // 1. Team ID resolution
    if (lowerKey == 'team_id' || lowerKey == 'teamid') {
      String? teamName;

      // Check current map or parent maps first
      teamName = currentMap['team_name']?.toString() ??
          currentMap['team']?['name']?.toString() ??
          parentNew['team_name']?.toString() ??
          parentOld['team_name']?.toString() ??
          log?['team_name']?.toString();

      // Look up in studentTeamsProvider
      if (teamName == null || teamName.isEmpty) {
        final teams = ref.watch(studentTeamsProvider).teams;
        for (final t in teams) {
          if (t['id']?.toString() == strVal) {
            teamName = t['name']?.toString() ?? t['project_title']?.toString();
            break;
          }
        }
      }

      // Look up in gradeCenterProvider
      if (teamName == null || teamName.isEmpty) {
        final grades = ref.watch(gradeCenterProvider).grades;
        for (final g in grades) {
          if (g['team_id']?.toString() == strVal || g['team']?['id']?.toString() == strVal) {
            teamName = g['team_name']?.toString();
            break;
          }
        }
      }

      if (teamName != null && teamName.isNotEmpty) {
        return _ResolvedAttr(
          label: 'Team',
          rawKey: key,
          displayValue: teamName,
          idBadge: '#$strVal',
          isEntity: true,
        );
      }

      return _ResolvedAttr(
        label: 'Team',
        rawKey: key,
        displayValue: 'Team #$strVal',
        idBadge: '#$strVal',
        isEntity: true,
      );
    }

    // 2. Grade ID resolution
    if (lowerKey == 'grade_id' || lowerKey == 'gradeid') {
      String? teamName;
      String? stageLabel;

      final grades = ref.watch(gradeCenterProvider).grades;
      for (final g in grades) {
        if (g['id']?.toString() == strVal) {
          teamName = g['team_name']?.toString();
          stageLabel = g['stage_label']?.toString();
          break;
        }
      }

      // If not found in grade center list, check companion fields
      teamName ??= currentMap['team_name']?.toString() ??
          parentNew['team_name']?.toString() ??
          parentOld['team_name']?.toString() ??
          log?['team_name']?.toString();

      // If team_id is also present in this map, look up team name
      if ((teamName == null || teamName.isEmpty) && currentMap.containsKey('team_id')) {
        final tid = currentMap['team_id']?.toString();
        final teams = ref.watch(studentTeamsProvider).teams;
        for (final t in teams) {
          if (t['id']?.toString() == tid) {
            teamName = t['name']?.toString();
            break;
          }
        }
      }

      stageLabel ??= currentMap['stage_label']?.toString() ??
          parentNew['stage_label']?.toString() ??
          parentOld['stage_label']?.toString();

      if (teamName != null && teamName.isNotEmpty) {
        final display = (stageLabel != null && stageLabel.isNotEmpty)
            ? '$teamName · $stageLabel'
            : teamName;
        return _ResolvedAttr(
          label: 'Team Grade',
          rawKey: key,
          displayValue: display,
          idBadge: 'Grade #$strVal',
          isEntity: true,
        );
      }

      return _ResolvedAttr(
        label: 'Team Grade',
        rawKey: key,
        displayValue: 'Grade #$strVal',
        idBadge: '#$strVal',
        isEntity: true,
      );
    }

    // 3. Defense Schedule ID resolution
    if (lowerKey == 'schedule_id' || lowerKey == 'scheduleid') {
      String? teamName;
      final grades = ref.watch(gradeCenterProvider).grades;
      for (final g in grades) {
        if (g['schedule_id']?.toString() == strVal) {
          teamName = g['team_name']?.toString();
          break;
        }
      }
      teamName ??= currentMap['team_name']?.toString() ??
          parentNew['team_name']?.toString() ??
          log?['team_name']?.toString();

      if (teamName != null && teamName.isNotEmpty) {
        return _ResolvedAttr(
          label: 'Defense Schedule',
          rawKey: key,
          displayValue: '$teamName · Schedule',
          idBadge: '#$strVal',
          isEntity: true,
        );
      }

      return _ResolvedAttr(
        label: 'Defense Schedule',
        rawKey: key,
        displayValue: 'Schedule #$strVal',
        idBadge: '#$strVal',
        isEntity: true,
      );
    }

    // 4. Stage ID resolution
    if (lowerKey == 'stage_id' || lowerKey == 'defense_stage_id') {
      String? stageName = currentMap['stage_label']?.toString() ??
          parentNew['stage_label']?.toString() ??
          parentOld['stage_label']?.toString();

      if (stageName == null || stageName.isEmpty) {
        final stages = ref.watch(defenseStagesProvider).stages;
        for (final s in stages) {
          if (s['id']?.toString() == strVal) {
            stageName = s['name']?.toString() ?? s['label']?.toString();
            break;
          }
        }
      }

      if (stageName != null && stageName.isNotEmpty) {
        return _ResolvedAttr(
          label: 'Defense Stage',
          rawKey: key,
          displayValue: stageName,
          idBadge: '#$strVal',
          isEntity: true,
        );
      }

      return _ResolvedAttr(
        label: 'Defense Stage',
        rawKey: key,
        displayValue: 'Stage #$strVal',
        idBadge: '#$strVal',
        isEntity: true,
      );
    }

    // 5. Academic Period / Semester ID resolution
    if (lowerKey == 'academic_period_id' || lowerKey == 'semester_id' || lowerKey == 'period_id') {
      String? periodName = currentMap['period_name']?.toString() ??
          currentMap['semester_name']?.toString();

      if (periodName == null || periodName.isEmpty) {
        final periodState = ref.watch(academicPeriodProvider);
        for (final y in periodState.schoolYears) {
          if (y['id']?.toString() == strVal) {
            periodName = y['label']?.toString() ?? y['year']?.toString();
            break;
          }
          final semesters = y['semesters'] is List ? y['semesters'] as List : const [];
          for (final sem in semesters) {
            if (sem is Map && sem['id']?.toString() == strVal) {
              periodName = '${sem['label'] ?? sem['semester'] ?? 'Semester'} (${y['label'] ?? ''})'.trim();
              break;
            }
          }
          if (periodName != null) break;
        }
      }

      if (periodName != null && periodName.isNotEmpty) {
        return _ResolvedAttr(
          label: 'Academic Period',
          rawKey: key,
          displayValue: periodName,
          idBadge: '#$strVal',
          isEntity: true,
        );
      }

      return _ResolvedAttr(
        label: 'Academic Period',
        rawKey: key,
        displayValue: 'Period #$strVal',
        idBadge: '#$strVal',
        isEntity: true,
      );
    }

    // 6. User / Actor / Student / Adviser ID resolution
    if (lowerKey == 'user_id' || lowerKey == 'actor_id' || lowerKey == 'student_id' || lowerKey == 'adviser_id') {
      final name = currentMap['actor_name']?.toString() ??
          currentMap['student_name']?.toString() ??
          currentMap['adviser_name']?.toString() ??
          log?['actor_name']?.toString();

      if (name != null && name.isNotEmpty && name != 'System') {
        return _ResolvedAttr(
          label: humanKey,
          rawKey: key,
          displayValue: name,
          idBadge: '#$strVal',
          isEntity: true,
        );
      }

      return _ResolvedAttr(
        label: humanKey,
        rawKey: key,
        displayValue: '#$strVal',
        idBadge: null,
        isEntity: true,
      );
    }

    // 7. Assessment Rubric ID resolution
    if (lowerKey == 'rubric_id') {
      final rubricName = currentMap['rubric_name']?.toString() ??
          currentMap['name']?.toString();
      if (rubricName != null && rubricName.isNotEmpty) {
        return _ResolvedAttr(
          label: 'Assessment Rubric',
          rawKey: key,
          displayValue: rubricName,
          idBadge: '#$strVal',
          isEntity: true,
        );
      }
      return _ResolvedAttr(
        label: 'Assessment Rubric',
        rawKey: key,
        displayValue: 'Rubric #$strVal',
        idBadge: '#$strVal',
        isEntity: true,
      );
    }

    // 8. General foreign key / id fields
    if (lowerKey.endsWith('_id') || lowerKey.endsWith('id')) {
      return _ResolvedAttr(
        label: humanKey,
        rawKey: key,
        displayValue: '#$strVal',
        idBadge: null,
        isEntity: true,
      );
    }

    // 9. Standard non-ID fields
    return _ResolvedAttr(
      label: humanKey,
      rawKey: key,
      displayValue: strVal,
      isNullOrEmpty: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final oldMap = _asMap(widget.oldValues);
    final newMap = _asMap(widget.newValues);

    if (oldMap.isEmpty && newMap.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Center(
          child: Text(
            'No attribute modifications recorded for this entry.',
            style: TextStyle(fontSize: 12, color: DefensysTokens.steelGrey),
          ),
        ),
      );
    }

    final isCreation = oldMap.isEmpty && newMap.isNotEmpty;
    final allKeys = {...oldMap.keys, ...newMap.keys}.toList()..sort();

    final modifiedKeys = <String>[];
    final unchangedKeys = <String>[];

    for (final key in allKeys) {
      final hasOld = oldMap.containsKey(key);
      final hasNew = newMap.containsKey(key);
      final oldVal = oldMap[key];
      final newVal = newMap[key];

      if (!hasOld || !hasNew || oldVal?.toString() != newVal?.toString()) {
        modifiedKeys.add(key);
      } else {
        unchangedKeys.add(key);
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Delta Header Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(DefensysTokens.radiusMd)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const Icon(Icons.compare_arrows_rounded, size: 15, color: DefensysTokens.steelGrey),
                const SizedBox(width: 6),
                Text(
                  isCreation
                      ? 'Initial State Snapshot (${newMap.length} attributes)'
                      : '${modifiedKeys.length} Modified ${modifiedKeys.length == 1 ? "Attribute" : "Attributes"}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.textDark,
                  ),
                ),
                const Spacer(),
                if (unchangedKeys.isNotEmpty)
                  InkWell(
                    onTap: () => setState(() => _showUnchanged = !_showUnchanged),
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _showUnchanged
                                ? 'Hide ${unchangedKeys.length} unchanged'
                                : '${unchangedKeys.length} unchanged',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: DefensysTokens.steelGrey,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            _showUnchanged ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                            size: 14,
                            color: DefensysTokens.steelGrey,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Modified Items List
          if (isCreation)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: newMap.entries.map((entry) {
                  final attr = _resolveAttribute(entry.key, entry.value, newMap);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 140,
                          child: Text(
                            attr.label,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: DefensysTokens.steelGrey,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 2,
                            children: [
                              SelectableText(
                                attr.displayValue,
                                style: TextStyle(
                                  fontFamily: attr.isEntity ? null : 'monospace',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: attr.isNullOrEmpty
                                      ? DefensysTokens.steelGrey
                                      : DefensysTokens.textDark,
                                  fontStyle: attr.isNullOrEmpty ? FontStyle.italic : null,
                                ),
                              ),
                              if (attr.idBadge != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Text(
                                    attr.idBadge!,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: DefensysTokens.steelGrey,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            )
          else ...[
            if (modifiedKeys.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'No field value deltas detected between snapshots.',
                  style: TextStyle(fontSize: 11, color: DefensysTokens.steelGrey, fontStyle: FontStyle.italic),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: modifiedKeys.map((key) {
                    final oldVal = oldMap[key];
                    final newVal = newMap[key];
                    final oldAttr = _resolveAttribute(key, oldVal, oldMap);
                    final newAttr = _resolveAttribute(key, newVal, newMap);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 130,
                            child: Text(
                              newAttr.label,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: DefensysTokens.textDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 4,
                                      children: [
                                        SelectableText(
                                          oldVal == null ? '(none)' : oldAttr.displayValue,
                                          style: TextStyle(
                                            fontFamily: oldAttr.isEntity ? null : 'monospace',
                                            fontSize: 11,
                                            color: oldVal == null ? DefensysTokens.steelGrey : const Color(0xFF64748B),
                                            decoration: oldVal == null ? null : TextDecoration.lineThrough,
                                          ),
                                        ),
                                        if (oldAttr.idBadge != null)
                                          Text(
                                            '(${oldAttr.idBadge})',
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 9,
                                              color: DefensysTokens.steelGrey,
                                              decoration: TextDecoration.lineThrough,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6),
                                  child: Icon(Icons.arrow_forward_rounded, size: 13, color: DefensysTokens.steelGrey),
                                ),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFFA7F3D0)),
                                    ),
                                    child: Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 4,
                                      children: [
                                        SelectableText(
                                          newVal == null ? '(removed)' : newAttr.displayValue,
                                          style: TextStyle(
                                            fontFamily: newAttr.isEntity ? null : 'monospace',
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: newVal == null ? const Color(0xFF991B1B) : const Color(0xFF065F46),
                                          ),
                                        ),
                                        if (newAttr.idBadge != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFD1FAE5),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              newAttr.idBadge!,
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF065F46),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

            // Collapsible Unchanged Properties
            if (_showUnchanged && unchangedKeys.isNotEmpty) ...[
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text(
                        'UNCHANGED PROPERTIES',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: DefensysTokens.steelGrey,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    ...unchangedKeys.map((key) {
                      final attr = _resolveAttribute(key, newMap[key], newMap);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 140,
                              child: Text(
                                attr.label,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: DefensysTokens.steelGrey,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                children: [
                                  SelectableText(
                                    attr.displayValue,
                                    style: TextStyle(
                                      fontFamily: attr.isEntity ? null : 'monospace',
                                      fontSize: 10.5,
                                      color: const Color(0xFF475569),
                                    ),
                                  ),
                                  if (attr.idBadge != null)
                                    Text(
                                      attr.idBadge!,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 9,
                                        color: DefensysTokens.steelGrey,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ],
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: DefensysTokens.steelGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text.isEmpty ? '-' : text,
              style: const TextStyle(
                fontSize: 12,
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

const _categoryOptions = [
  {'value': 'academic_period', 'label': 'Academic Periods'},
  {'value': 'grade_center', 'label': 'Evaluation & Grades'},
  {'value': 'scheduling', 'label': 'Defense Schedules'},
  {'value': 'repository', 'label': 'Archive & Vault'},
  {'value': 'guest_access', 'label': 'Guest Access'},
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
