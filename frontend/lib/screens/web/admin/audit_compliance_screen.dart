import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/system_audit_provider.dart';
import '../../../services/auth_provider.dart';
import '../../../services/academic_period_provider.dart';
import '../../../services/student_teams_provider.dart';
import '../../../services/reports_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../toasts/feedback_toast.dart';
import 'widgets/defensys_admin_shell.dart';

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
  int _selectedReportIndex = 0;
  String? _selectedSemesterId;
  String? _selectedTeamId;
  String _selectedLevel = '';
  String _selectedYearLevel = '';
  String _selectedRole = '';
  final _reportStartDateController = TextEditingController();
  final _reportEndDateController = TextEditingController();
  String _reportCategoryFilter = '';
  String _selectedScope = '';
  String _reportTrackFilter = '';
  String _reportYearLevelFilter = '';

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

    // Load periods and teams silently for Report dropdowns
    ref.read(academicPeriodProvider.notifier).fetchPeriods();
    ref.read(studentTeamsProvider.notifier).fetchTeams();
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

    final List<Map<String, dynamic>> availableReports = [
      {
        'title': 'Team Grade Report Card',
        'desc': 'Detailed grading summary and criterion assessment scores from panelists, adviser, and peers.',
        'icon': Icons.badge_outlined,
        'endpoint': 'team-grade',
        'tag': 'Grades',
        'meta': 'PDF • Team Breakdown',
      },
      {
        'title': 'Semester Grade Summary',
        'desc': 'Compilation sheet of all student teams and final pass/fail results for the semester.',
        'icon': Icons.grade_outlined,
        'endpoint': 'semester-grades',
        'tag': 'Summary',
        'meta': 'PDF • Official Roster',
      },
      {
        'title': 'Defense Schedule Summary',
        'desc': 'Compiled list of scheduled defense events, panels, times, and venue rooms.',
        'icon': Icons.calendar_month_outlined,
        'endpoint': 'defense-schedules',
        'tag': 'Schedule',
        'meta': 'PDF • Timetable',
      },
      {
        'title': 'Team Roster Report',
        'desc': 'Directory list of active student teams, project titles, leaders, and advisers.',
        'icon': Icons.groups_outlined,
        'endpoint': 'team-roster',
        'tag': 'Roster',
        'meta': 'PDF • Directory',
      },
      if (isAdmin)
        {
          'title': 'User Directory',
          'desc': 'Complete list of registered accounts in the portal filtered by role and status.',
          'icon': Icons.person_search_outlined,
          'endpoint': 'user-directory',
          'tag': 'Accounts',
          'meta': 'PDF • System Users',
        },
      if (isAdmin || isPitLead)
        {
          'title': 'Audit Trail Export',
          'desc': 'Compliance log register documenting all high-impact actions and access changes.',
          'icon': Icons.receipt_long_outlined,
          'endpoint': 'audit-trail',
          'tag': 'Compliance',
          'meta': 'PDF • Change Logs',
        },
    ];

    final reportIndex = _selectedReportIndex.clamp(0, availableReports.length - 1);
    final selectedReport = availableReports[reportIndex];

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
                  '${availableReports.length} Reports Ready for PDF Export',
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
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1100;
            final masterList = _buildMasterReportList(availableReports, reportIndex);
            final filterForm = _buildReportFilterForm(selectedReport);

            if (!wide) {
              return Column(
                children: [
                  masterList,
                  const SizedBox(height: 20),
                  filterForm,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: masterList),
                const SizedBox(width: 20),
                Expanded(flex: 7, child: filterForm),
              ],
            );
          },
        ),
      ],
    );
  }

  /// Master Document Selection List (Option 2 Layout)
  Widget _buildMasterReportList(List<Map<String, dynamic>> reports, int selectedIdx) {
    return Container(
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
          // Master List Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: DefensysTokens.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.article_outlined, color: DefensysTokens.maroon, size: 20),
                const SizedBox(width: 10),
                Text('SELECT COMPLIANCE REPORT', style: DefensysUi.tableHeader),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: DefensysTokens.neutralBg,
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                  ),
                  child: Text(
                    '${reports.length} Available',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.steelGrey,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Master Document List Items
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: reports.length,
            separatorBuilder: (context, index) => const Divider(height: 1, color: DefensysTokens.border),
            itemBuilder: (context, index) {
              final r = reports[index];
              final isSelected = index == selectedIdx;

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _selectedReportIndex = index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? DefensysTokens.maroon.withValues(alpha: 0.05)
                          : Colors.transparent,
                    ),
                    child: Row(
                      children: [
                        // Left Selection Indicator Bar
                        Container(
                          width: 4,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isSelected ? DefensysTokens.maroon : Colors.transparent,
                            borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Icon Container
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? DefensysTokens.maroon
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                          ),
                          child: Icon(
                            r['icon'] as IconData,
                            color: isSelected ? Colors.white : DefensysTokens.steelGrey,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Title & Meta
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      r['title'] as String,
                                      style: TextStyle(
                                        fontFamily: DefensysTokens.fontFamily,
                                        color: isSelected
                                            ? DefensysTokens.maroon
                                            : DefensysTokens.textDark,
                                        fontSize: 13.5,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? DefensysTokens.gold.withValues(alpha: 0.15)
                                          : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                                    ),
                                    child: Text(
                                      r['tag'] as String,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? DefensysTokens.darkGold
                                            : DefensysTokens.steelGrey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                r['meta'] as String? ?? 'PDF Document',
                                style: TextStyle(
                                  color: isSelected
                                      ? DefensysTokens.maroon.withValues(alpha: 0.8)
                                      : DefensysTokens.steelGrey,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: isSelected ? DefensysTokens.maroon : DefensysTokens.steelGrey,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReportFilterForm(Map<String, dynamic> report) {
    final reportsState = ref.watch(reportsProvider);
    final academicState = ref.watch(academicPeriodProvider);
    final teamsState = ref.watch(studentTeamsProvider);
    
    final endpoint = report['endpoint'] as String;

    // Load active semester ID initially
    final activeSemId = academicState.activeSemester?['id']?.toString();
    _selectedSemesterId ??= activeSemId;

    // Load first team ID initially
    if (_selectedTeamId == null && teamsState.teams.isNotEmpty) {
      _selectedTeamId = teamsState.teams.first['id']?.toString();
    }

    final List<Map<String, dynamic>> semestersList = [];
    for (final year in academicState.schoolYears) {
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

    // Build Live Summary string
    String selectedSemLabel = semestersList.firstWhere(
      (s) => s['id'] == _selectedSemesterId,
      orElse: () => {'label': 'Active Semester'},
    )['label'] as String;

    String selectedTeamLabel = teamsState.teams.firstWhere(
      (t) => t['id']?.toString() == _selectedTeamId,
      orElse: () => {'name': 'Selected Team'},
    )['name']?.toString() ?? 'Selected Team';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with maroon top accent border
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: DefensysTokens.maroon, width: 4),
                bottom: BorderSide(color: DefensysTokens.border, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: DefensysTokens.maroon.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(report['icon'] as IconData, color: DefensysTokens.maroon, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              report['title'] as String,
                              style: DefensysUi.sectionTitle,
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
                            child: const Text(
                              'EXPORT CONFIG',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: DefensysTokens.maroon,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Configure output parameters and download official PDF.',
                        style: DefensysUi.subtitle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selected Report Information Preview Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: DefensysTokens.maroon.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                    border: Border.all(color: DefensysTokens.maroon.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 18, color: DefensysTokens.maroon),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'REPORT DESCRIPTION & OBJECTIVE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: DefensysTokens.maroon,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              report['desc'] as String,
                              style: const TextStyle(
                                fontSize: 12,
                                color: DefensysTokens.textDark,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (endpoint == 'team-grade') ...[
                  const _FormSectionLabel('SELECT STUDENT TEAM'),
                  const SizedBox(height: 6),
                  teamsState.isLoading
                      ? const LinearProgressIndicator()
                      : DropdownButtonFormField<String>(
                          initialValue: _selectedTeamId,
                          isExpanded: true,
                          decoration: _inputDecoration('Choose team...'),
                          items: teamsState.teams.map((t) {
                            return DropdownMenuItem<String>(
                              value: t['id']?.toString(),
                              child: Text(t['name']?.toString() ?? 'N/A'),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedTeamId = val),
                        ),
                  const SizedBox(height: 18),
                ],

                if (endpoint == 'semester-grades' || endpoint == 'defense-schedules' || endpoint == 'team-roster') ...[
                  const _FormSectionLabel('ACADEMIC SEMESTER'),
                  const SizedBox(height: 6),
                  academicState.isLoading
                      ? const LinearProgressIndicator()
                      : DropdownButtonFormField<String>(
                          initialValue: _selectedSemesterId,
                          isExpanded: true,
                          decoration: _inputDecoration('Choose semester...'),
                          items: semestersList.map((s) {
                            return DropdownMenuItem<String>(
                              value: s['id']?.toString(),
                              child: Text(s['label']?.toString() ?? 'N/A'),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedSemesterId = val),
                        ),
                  const SizedBox(height: 18),
                ],

                if (endpoint == 'semester-grades' || endpoint == 'defense-schedules') ...[
                  const _FormSectionLabel('ACADEMIC SCOPE'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedScope,
                    isExpanded: true,
                    decoration: _inputDecoration('Filter scope...'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('All Records (Capstone & PIT)')),
                      DropdownMenuItem(value: 'capstone', child: Text('Capstone Only')),
                      DropdownMenuItem(value: 'pit', child: Text('PIT Only')),
                    ],
                    onChanged: (val) => setState(() => _selectedScope = val ?? ''),
                  ),
                  const SizedBox(height: 18),
                ],

                if (endpoint == 'team-roster') ...[
                  const _FormSectionLabel('ACADEMIC PROGRAM LEVEL'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedLevel,
                    isExpanded: true,
                    decoration: _inputDecoration('Filter program level...'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('All Levels (Capstone & PIT)')),
                      DropdownMenuItem(value: 'capstone', child: Text('Capstone Teams')),
                      DropdownMenuItem(value: 'pit', child: Text('PIT Teams')),
                    ],
                    onChanged: (val) => setState(() => _selectedLevel = val ?? ''),
                  ),
                  const SizedBox(height: 18),
                  const _FormSectionLabel('STUDENT YEAR LEVEL'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedYearLevel,
                    isExpanded: true,
                    decoration: _inputDecoration('Filter year level...'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('All Year Levels')),
                      DropdownMenuItem(value: '3rd Year', child: Text('3rd Year')),
                      DropdownMenuItem(value: '4th Year', child: Text('4th Year')),
                    ],
                    onChanged: (val) => setState(() => _selectedYearLevel = val ?? ''),
                  ),
                  const SizedBox(height: 18),
                ],

                if (endpoint == 'user-directory') ...[
                  const _FormSectionLabel('FILTER BY PORTAL ROLE'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedRole,
                    isExpanded: true,
                    decoration: _inputDecoration('Select role filter...'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('All System Roles')),
                      DropdownMenuItem(value: 'admin', child: Text('System Administrators')),
                      DropdownMenuItem(value: 'faculty', child: Text('Faculty / Evaluators')),
                      DropdownMenuItem(value: 'student', child: Text('Capstone Students')),
                    ],
                    onChanged: (val) => setState(() => _selectedRole = val ?? ''),
                  ),
                  const SizedBox(height: 18),
                ],

                if (endpoint == 'audit-trail') ...[
                  const _FormSectionLabel('ACADEMIC TRACK'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _reportTrackFilter,
                    isExpanded: true,
                    decoration: _inputDecoration('All tracks'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('All Tracks')),
                      DropdownMenuItem(value: 'capstone', child: Text('Capstone')),
                      DropdownMenuItem(value: 'pit', child: Text('PIT')),
                    ],
                    onChanged: (val) => setState(() => _reportTrackFilter = val ?? ''),
                  ),
                  const SizedBox(height: 18),
                  const _FormSectionLabel('YEAR LEVEL (FOR PIT)'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _reportYearLevelFilter,
                    isExpanded: true,
                    decoration: _inputDecoration('All year levels'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('All Year Levels')),
                      DropdownMenuItem(value: '1st Year', child: Text('1st Year')),
                      DropdownMenuItem(value: '2nd Year', child: Text('2nd Year')),
                      DropdownMenuItem(value: '3rd Year', child: Text('3rd Year')),
                      DropdownMenuItem(value: '4th Year', child: Text('4th Year')),
                    ],
                    onChanged: (val) => setState(() => _reportYearLevelFilter = val ?? ''),
                  ),
                  const SizedBox(height: 18),
                  const _FormSectionLabel('AUDIT PROCESS AREA'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _reportCategoryFilter,
                    isExpanded: true,
                    decoration: _inputDecoration('All process areas'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('All Process Areas')),
                      DropdownMenuItem(value: 'academic_period', child: Text('Academic Period Changes')),
                      DropdownMenuItem(value: 'grade_center', child: Text('Grade & Result Decisions')),
                      DropdownMenuItem(value: 'scheduling', child: Text('Schedule Changes')),
                      DropdownMenuItem(value: 'repository', child: Text('Repository Vault Evidence')),
                      DropdownMenuItem(value: 'guest_access', child: Text('Guest Access Activity')),
                    ],
                    onChanged: (val) => setState(() => _reportCategoryFilter = val ?? ''),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FormSectionLabel('START DATE'),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _reportStartDateController,
                              readOnly: true,
                              onTap: () => _selectDate(context, _reportStartDateController, (_) {}),
                              decoration: _inputDecoration('YYYY-MM-DD').copyWith(
                                suffixIcon: const Icon(Icons.calendar_today_rounded, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FormSectionLabel('END DATE'),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _reportEndDateController,
                              readOnly: true,
                              onTap: () => _selectDate(context, _reportEndDateController, (_) {}),
                              decoration: _inputDecoration('YYYY-MM-DD').copyWith(
                                suffixIcon: const Icon(Icons.calendar_today_rounded, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],

                // Live Export Summary Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: DefensysTokens.neutralBg,
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                    border: Border.all(color: DefensysTokens.neutralBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: DefensysTokens.steelGrey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          endpoint == 'team-grade'
                              ? 'Exporting: $selectedTeamLabel Grade Card'
                              : endpoint == 'semester-grades' || endpoint == 'defense-schedules' || endpoint == 'team-roster'
                                  ? 'Exporting: ${report['title']} for $selectedSemLabel'
                                  : 'Exporting: ${report['title']} (Official Audit PDF)',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: DefensysTokens.textDark,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(
                  width: double.infinity,
                  height: DefensysTokens.buttonHeightPrimary,
                  child: FilledButton.icon(
                    onPressed: reportsState.isLoading ? null : () => _triggerReportDownload(report),
                    icon: reportsState.isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                    label: Text(
                      reportsState.isLoading ? 'Generating Document...' : 'Generate & Download PDF',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: DefensysTokens.maroon,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
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

  Future<void> _triggerReportDownload(Map<String, dynamic> report) async {
    final endpoint = report['endpoint'] as String;
    final queryParams = <String, String>{};

    if (endpoint == 'team-grade') {
      if (_selectedTeamId == null) {
        showValidationToast(context, 'Please select a student team.');
        return;
      }
      final fullEndpoint = 'team-grade/$_selectedTeamId/';

      final success = await ref.read(reportsProvider.notifier).downloadReport(
        endpoint: fullEndpoint,
        queryParams: queryParams,
        defaultFilename: 'DefenSYS_Team_Grade_Report.pdf',
      );

      _showDownloadResultToast(success);
      return;
    }

    if (endpoint == 'semester-grades' || endpoint == 'defense-schedules' || endpoint == 'team-roster') {
      if (_selectedSemesterId != null) {
        queryParams['semester_id'] = _selectedSemesterId!;
      }
    }

    if (endpoint == 'semester-grades' || endpoint == 'defense-schedules') {
      if (_selectedScope.isNotEmpty) {
        queryParams['scope'] = _selectedScope;
      }
    }

    if (endpoint == 'team-roster') {
      if (_selectedLevel.isNotEmpty) queryParams['level'] = _selectedLevel;
      if (_selectedYearLevel.isNotEmpty) queryParams['year_level'] = _selectedYearLevel;
    }

    if (endpoint == 'user-directory') {
      if (_selectedRole.isNotEmpty) queryParams['role'] = _selectedRole;
    }

    if (endpoint == 'audit-trail') {
      if (_reportCategoryFilter.isNotEmpty) queryParams['category'] = _reportCategoryFilter;
      if (_reportTrackFilter.isNotEmpty) queryParams['track'] = _reportTrackFilter;
      if (_reportYearLevelFilter.isNotEmpty) queryParams['year_level'] = _reportYearLevelFilter;
      final start = _reportStartDateController.text.trim();
      final end = _reportEndDateController.text.trim();
      if (start.isNotEmpty) queryParams['start_date'] = start;
      if (end.isNotEmpty) queryParams['end_date'] = end;
    }

    final success = await ref.read(reportsProvider.notifier).downloadReport(
      endpoint: '$endpoint/',
      queryParams: queryParams,
      defaultFilename: 'DefenSYS_${report['title'].toString().replaceAll(' ', '_')}.pdf',
    );

    _showDownloadResultToast(success);
  }

  void _showDownloadResultToast(bool success) {
    if (!mounted) return;
    final error = ref.read(reportsProvider).error;
    if (success) {
      showSuccessToast(context, 'PDF report generated and downloaded successfully!');
    } else {
      showErrorToast(context, 'Failed to generate PDF: ${error ?? "Unknown error"}');
    }
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.neutralBg,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.neutralBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: DefensysTokens.maroon, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: DefensysUi.sectionTitle),
                const SizedBox(height: 4),
                Text(message, style: DefensysUi.subtitle),
              ],
            ),
          ),
        ],
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
  {'value': 'repository', 'label': 'Repository Vault Evidence'},
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
