import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/system_audit_provider.dart';
import '../../../services/auth_provider.dart';
import '../../../services/academic_period_provider.dart';
import '../../../services/student_teams_provider.dart';
import '../../../services/reports_provider.dart';
import 'widgets/defensys_admin_shell.dart';

class AuditComplianceScreen extends ConsumerStatefulWidget {
  const AuditComplianceScreen({super.key});

  @override
  ConsumerState<AuditComplianceScreen> createState() =>
      _AuditComplianceScreenState();
}

class _AuditComplianceScreenState extends ConsumerState<AuditComplianceScreen> {
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
      final user = ref.read(authProvider).user;
      final isAdmin = user?['role']?.toString() == 'admin' || user?['is_superuser'] == true;
      final isPitLead = user?['is_pit_lead'] == true;
      final canViewAudit = isAdmin || isPitLead;

      if (canViewAudit) {
        ref.read(systemAuditProvider.notifier).fetch();
      }
      
      // Load periods and teams silently for Report dropdowns
      ref.read(academicPeriodProvider.notifier).fetchPeriods();
      ref.read(studentTeamsProvider.notifier).fetchTeams();
    });
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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isAdmin = user?['role']?.toString() == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;
    final canViewAudit = isAdmin || isPitLead;

    if (!canViewAudit) {
      // For Project Advisers, render Report Center directly without tabs
      return SingleChildScrollView(
        padding: DefensysUi.contentPadding,
        child: _buildReportCenter(context),
      );
    }

    // For Admins and PIT Leads, render Tabbed Layout
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: const TabBar(
              labelColor: DefensysUi.primaryMaroon,
              unselectedLabelColor: DefensysUi.steelGrey,
              indicatorColor: DefensysUi.accentGold,
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Audit Register'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.summarize_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Report Center'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            SingleChildScrollView(
              padding: DefensysUi.contentPadding,
              child: _buildAuditRegisterTab(context),
            ),
            SingleChildScrollView(
              padding: DefensysUi.contentPadding,
              child: _buildReportCenter(context),
            ),
          ],
        ),
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
              'Evidence trail for official academic actions and access changes.',
          actions: _AuditReadinessBadge(state: state),
        ),
        const SizedBox(height: 14),
        _EvidenceStatusCards(state: state),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: DefensysCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Audit Filters', style: DefensysUi.sectionTitle),
                const SizedBox(height: 10),
                    // Row 1: Dropdown filters
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (isAdmin) ...[
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _getCurrentAcademicScope(state),
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
                              onChanged: _onAcademicScopeChanged,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ]
                        else if (isPitLead) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Text(
                              'Scope: PIT (${user?['pit_lead_year'] ?? "N/A"})',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: DefensysUi.textDark,
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
                            onChanged: ref
                                .read(systemAuditProvider.notifier)
                                .setCategory,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _FilterDropdown(
                            label: 'Review Status',
                            value: state.reviewStatus,
                            options: state.options['review_statuses'],
                            onChanged: ref
                                .read(systemAuditProvider.notifier)
                                .setReviewStatus,
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
                            onChanged: ref
                                .read(systemAuditProvider.notifier)
                                .setAction,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Row 2: Search, date fields and Action buttons
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              labelText: 'Search evidence',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: ref
                                .read(systemAuditProvider.notifier)
                                .setSearch,
                            onSubmitted: (_) =>
                                ref.read(systemAuditProvider.notifier).fetch(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _startDateController,
                            decoration: const InputDecoration(
                              labelText: 'Start date',
                              hintText: 'YYYY-MM-DD',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: ref
                                .read(systemAuditProvider.notifier)
                                .setStartDate,
                            onSubmitted: (_) =>
                                ref.read(systemAuditProvider.notifier).fetch(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _endDateController,
                            decoration: const InputDecoration(
                              labelText: 'End date',
                              hintText: 'YYYY-MM-DD',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: ref
                                .read(systemAuditProvider.notifier)
                                .setEndDate,
                            onSubmitted: (_) =>
                                ref.read(systemAuditProvider.notifier).fetch(),
                          ),
                        ),
                        const SizedBox(width: 20),
                        SizedBox(
                          height: 44,
                          child: FilledButton.icon(
                            onPressed: () =>
                                ref.read(systemAuditProvider.notifier).fetch(),
                            icon: const Icon(Icons.search_rounded, size: 18),
                            label: const Text('Apply'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: state.isLoading ? null : () => _quickExportAuditPDF(state),
                            icon: ref.watch(reportsProvider).isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.download_rounded, size: 18),
                            label: const Text('Download PDF'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DefensysUi.primaryMaroon,
                              side: const BorderSide(color: DefensysUi.primaryMaroon),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1100;
            final table = _AuditTrailTable(state: state, auditRow: _auditRow);
            final details = _EvidenceDetailsPanel(log: selectedLog);

            if (!wide) {
              return Column(
                children: [table, const SizedBox(height: 14), details],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: table),
                const SizedBox(width: 14),
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

    // Build the lists of reports matching active user roles
    final List<Map<String, dynamic>> availableReports = [
      {
        'title': 'Team Grade Report Card',
        'desc': 'Detailed grading summary and criterion assessment scores from panelists, adviser, and peers.',
        'icon': Icons.badge_rounded,
        'endpoint': 'team-grade',
      },
      {
        'title': 'Semester Grade Summary',
        'desc': 'Compilation sheet of all student teams and final pass/fail results for the semester.',
        'icon': Icons.grade_rounded,
        'endpoint': 'semester-grades',
      },
      {
        'title': 'Defense Schedule Summary',
        'desc': 'Compiled list of scheduled defense events, panels, times, and venue rooms.',
        'icon': Icons.calendar_month_rounded,
        'endpoint': 'defense-schedules',
      },
      {
        'title': 'Team Roster Report',
        'desc': 'Directory list of active student teams, project titles, leaders, and advisers.',
        'icon': Icons.groups_rounded,
        'endpoint': 'team-roster',
      },
      if (isAdmin)
        {
          'title': 'User Directory',
          'desc': 'Complete list of registered accounts in the portal filtered by role and status.',
          'icon': Icons.person_search_rounded,
          'endpoint': 'user-directory',
        },
      if (isAdmin || isPitLead)
        {
          'title': 'Audit Trail Export',
          'desc': 'Compliance log register documenting all high-impact actions and access changes.',
          'icon': Icons.receipt_long_outlined,
          'endpoint': 'audit-trail',
        },
    ];

    final reportIndex = _selectedReportIndex.clamp(0, availableReports.length - 1);
    final selectedReport = availableReports[reportIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DefensysPageHeader(
          icon: Icons.summarize_rounded,
          title: 'Report Export Center',
          subtitle: 'Generate and download official compliance PDF reports.',
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1100;
            final cardsGrid = _buildReportCardsGrid(availableReports, reportIndex);
            final filterForm = _buildReportFilterForm(selectedReport);

            if (!wide) {
              return Column(
                children: [
                  cardsGrid,
                  const SizedBox(height: 20),
                  filterForm,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: cardsGrid),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: filterForm),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildReportCardsGrid(List<Map<String, dynamic>> reports, int selectedIdx) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 2.1,
      ),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final r = reports[index];
        final isSelected = index == selectedIdx;
        return InkWell(
          onTap: () => setState(() => _selectedReportIndex = index),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? DefensysUi.accentGold : const Color(0xFFE5E7EB),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: DefensysUi.accentGold.withOpacity(0.1), blurRadius: 8)]
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? DefensysUi.primaryMaroon.withOpacity(0.08) : const Color(0xFFF3F4F6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    r['icon'] as IconData,
                    color: isSelected ? DefensysUi.primaryMaroon : DefensysUi.steelGrey,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r['title'] as String,
                        style: const TextStyle(
                          color: DefensysUi.textDark,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Text(
                          r['desc'] as String,
                          style: const TextStyle(
                            color: DefensysUi.steelGrey,
                            fontSize: 11,
                            height: 1.35,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

    // Extract all semesters from schoolYears
    final List<Map<String, dynamic>> semestersList = [];
    for (final year in academicState.schoolYears) {
      final sems = year['semesters'];
      if (sems is List) {
        for (final sem in sems) {
          if (sem is Map) {
            semestersList.add({
              'id': sem['id']?.toString() ?? '',
              'label': '${year['school_year'] ?? ''} — ${sem['label'] ?? ''}',
            });
          }
        }
      }
    }

    return DefensysCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(report['icon'] as IconData, color: DefensysUi.primaryMaroon, size: 20),
              const SizedBox(width: 8),
              Text('Export Configuration', style: DefensysUi.sectionTitle),
            ],
          ),
          const SizedBox(height: 4),
          Text('Configure query filters for ${report['title']}.', style: DefensysUi.subtitle),
          const Divider(height: 30, color: Color(0xFFE5E7EB)),

          if (endpoint == 'team-grade') ...[
            const Text('SELECT STUDENT TEAM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DefensysUi.steelGrey)),
            const SizedBox(height: 8),
            teamsState.isLoading
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<String>(
                    value: _selectedTeamId,
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: teamsState.teams.map((t) {
                      return DropdownMenuItem<String>(
                        value: t['id']?.toString(),
                        child: Text(t['name']?.toString() ?? 'N/A'),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedTeamId = val),
                  ),
            const SizedBox(height: 20),
          ],

          if (endpoint == 'semester-grades' || endpoint == 'defense-schedules' || endpoint == 'team-roster') ...[
            const Text('ACADEMIC SEMESTER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DefensysUi.steelGrey)),
            const SizedBox(height: 8),
            academicState.isLoading
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<String>(
                    value: _selectedSemesterId,
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: semestersList.map((s) {
                      return DropdownMenuItem<String>(
                        value: s['id']?.toString(),
                        child: Text(s['label']?.toString() ?? 'N/A'),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedSemesterId = val),
                  ),
            const SizedBox(height: 20),
          ],

          if (endpoint == 'semester-grades' || endpoint == 'defense-schedules') ...[
            const Text('ACADEMIC SCOPE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DefensysUi.steelGrey)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedScope,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: '', child: Text('All Records (Capstone & PIT)')),
                DropdownMenuItem(value: 'capstone', child: Text('Capstone Only')),
                DropdownMenuItem(value: 'pit', child: Text('PIT Only')),
              ],
              onChanged: (val) => setState(() => _selectedScope = val ?? ''),
            ),
            const SizedBox(height: 20),
          ],

          if (endpoint == 'team-roster') ...[
            const Text('ACADEMIC PROGRAM LEVEL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DefensysUi.steelGrey)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedLevel,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: '', child: Text('All Levels (Capstone & PIT)')),
                DropdownMenuItem(value: 'capstone', child: Text('Capstone Teams')),
                DropdownMenuItem(value: 'pit', child: Text('PIT Teams')),
              ],
              onChanged: (val) => setState(() => _selectedLevel = val ?? ''),
            ),
            const SizedBox(height: 20),
            const Text('STUDENT YEAR LEVEL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DefensysUi.steelGrey)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedYearLevel,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: '', child: Text('All Year Levels')),
                DropdownMenuItem(value: '3rd Year', child: Text('3rd Year')),
                DropdownMenuItem(value: '4th Year', child: Text('4th Year')),
              ],
              onChanged: (val) => setState(() => _selectedYearLevel = val ?? ''),
            ),
            const SizedBox(height: 20),
          ],

          if (endpoint == 'user-directory') ...[
            const Text('FILTER BY PORTAL ROLE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DefensysUi.steelGrey)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: '', child: Text('All System Roles')),
                DropdownMenuItem(value: 'admin', child: Text('System Administrators')),
                DropdownMenuItem(value: 'faculty', child: Text('Faculty / Evaluators')),
                DropdownMenuItem(value: 'student', child: Text('Capstone Students')),
              ],
              onChanged: (val) => setState(() => _selectedRole = val ?? ''),
            ),
            const SizedBox(height: 20),
          ],

          if (endpoint == 'audit-trail') ...[
            const Text('ACADEMIC TRACK', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DefensysUi.steelGrey)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _reportTrackFilter,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: '', child: Text('All Tracks')),
                DropdownMenuItem(value: 'capstone', child: Text('Capstone')),
                DropdownMenuItem(value: 'pit', child: Text('PIT')),
              ],
              onChanged: (val) => setState(() => _reportTrackFilter = val ?? ''),
            ),
            const SizedBox(height: 20),
            const Text('YEAR LEVEL (FOR PIT)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DefensysUi.steelGrey)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _reportYearLevelFilter,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: '', child: Text('All Year Levels')),
                DropdownMenuItem(value: '1st Year', child: Text('1st Year')),
                DropdownMenuItem(value: '2nd Year', child: Text('2nd Year')),
                DropdownMenuItem(value: '3rd Year', child: Text('3rd Year')),
                DropdownMenuItem(value: '4th Year', child: Text('4th Year')),
              ],
              onChanged: (val) => setState(() => _reportYearLevelFilter = val ?? ''),
            ),
            const SizedBox(height: 20),
            const Text('AUDIT PROCESS AREA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DefensysUi.steelGrey)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _reportCategoryFilter,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
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
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('START DATE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DefensysUi.steelGrey)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _reportStartDateController,
                        decoration: const InputDecoration(
                          hintText: 'YYYY-MM-DD',
                          border: OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: Icon(Icons.calendar_today_rounded, size: 16),
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
                      const Text('END DATE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DefensysUi.steelGrey)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _reportEndDateController,
                        decoration: const InputDecoration(
                          hintText: 'YYYY-MM-DD',
                          border: OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: Icon(Icons.calendar_today_rounded, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: reportsState.isLoading ? null : () => _triggerReportDownload(report),
              icon: reportsState.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.file_download_rounded),
              label: Text(reportsState.isLoading ? 'Generating PDF...' : 'Generate & Download PDF'),
              style: FilledButton.styleFrom(
                backgroundColor: DefensysUi.primaryMaroon,
                foregroundColor: DefensysUi.accentGold,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerReportDownload(Map<String, dynamic> report) async {
    final endpoint = report['endpoint'] as String;
    final queryParams = <String, String>{};

    if (endpoint == 'team-grade') {
      if (_selectedTeamId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a student team.')),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF report generated and downloaded successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate PDF: ${error ?? "Unknown error"}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  DataRow _auditRow(Map<String, dynamic> log) {
    final selected = ref.watch(systemAuditProvider).selectedLog;
    final isSelected = selected?['id']?.toString() == log['id']?.toString();
    return DataRow(
      selected: isSelected,
      onSelectChanged: (_) =>
          ref.read(systemAuditProvider.notifier).selectLog(log),
      cells: [
        DataCell(Text(_dateTime(log['created_at']))),
        DataCell(Text(log['category_label']?.toString() ?? '')),
        DataCell(Text(log['action']?.toString() ?? '')),
        DataCell(Text(log['actor_name']?.toString() ?? 'System')),
        DataCell(Text(_evidenceStatus(log))),
        DataCell(Text(_reviewStatus(log))),
      ],
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
    final label = needsReview == 0 ? 'Ready for Review' : 'Pending Review';

    return DefensysCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.shield_outlined,
            color: DefensysUi.accentGold,
            size: 32,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ISO 9001:2015 Audit Readiness', style: DefensysUi.subtitle),
              const SizedBox(height: 2),
              Text(
                '$readiness%',
                style: const TextStyle(
                  color: DefensysUi.primaryMaroon,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(width: 22),
          _StatusPill(label: label, value: '$reviewed/$total'),
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

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _SummaryCard(
              width: cardWidth,
              label: 'Audit Readiness',
              value:
                  '${_readinessPercent(state.counts, fallback: state.logs.length)}%',
              status: _readinessStatus(state),
              icon: Icons.fact_check_outlined,
            ),
            _SummaryCard(
              width: cardWidth,
              label: 'Open Findings',
              value: '${_count(state.counts['needs_review'])}',
              status: 'Requires Attention',
              icon: Icons.rate_review_outlined,
            ),
            _SummaryCard(
              width: cardWidth,
              label: 'Verified Evidence',
              value: '${_count(state.counts['captured'])}',
              status: 'Verified',
              icon: Icons.task_alt_outlined,
            ),
            _SummaryCard(
              width: cardWidth,
              label: 'Pending Review',
              value: '${_count(state.counts['needs_review'])}',
              status: 'Awaiting Review',
              icon: Icons.schedule_outlined,
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

  const _SummaryCard({
    required this.width,
    required this.label,
    required this.value,
    required this.status,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DefensysCard(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: DefensysUi.accentGold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: DefensysUi.primaryMaroon, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: DefensysUi.textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: DefensysUi.primaryMaroon,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              status,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: DefensysUi.accentGold,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditTrailTable extends StatelessWidget {
  final SystemAuditState state;
  final DataRow Function(Map<String, dynamic>) auditRow;

  const _AuditTrailTable({required this.state, required this.auditRow});

  @override
  Widget build(BuildContext context) {
    return DefensysCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                color: DefensysUi.primaryMaroon,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text('Audit Trail Register', style: DefensysUi.sectionTitle),
            ],
          ),
          const SizedBox(height: 16),
          if (state.isLoading)
            const Center(child: CircularProgressIndicator())
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
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Date / Time')),
                  DataColumn(label: Text('Process Area')),
                  DataColumn(label: Text('Control Activity')),
                  DataColumn(label: Text('Responsible User')),
                  DataColumn(label: Text('Evidence Status')),
                  DataColumn(label: Text('Review Status')),
                ],
                rows: state.logs.map(auditRow).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _EvidenceDetailsPanel extends StatelessWidget {
  final Map<String, dynamic>? log;

  const _EvidenceDetailsPanel({required this.log});

  @override
  Widget build(BuildContext context) {
    final item = log;
    return DefensysCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.description_outlined,
                color: DefensysUi.primaryMaroon,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Evidence Packet Preview',
                  style: DefensysUi.sectionTitle,
                ),
              ),
              if (item != null)
                _StatusPill(label: 'ID', value: '${item['id'] ?? '-'}'),
            ],
          ),
          const SizedBox(height: 14),
          if (item == null)
            const Text('Select an audit record to review its evidence details.')
          else ...[
            _DetailLine('Responsible User', item['actor_name'] ?? 'System'),
            _DetailLine('Timestamp', _dateTime(item['created_at'])),
            _DetailLine('Category', item['category_label']),
            _DetailLine('Action', item['action']),
            _DetailLine(
              'Target',
              '${item['target_type'] ?? ''} #${item['target_id'] ?? ''}',
            ),
            _DetailLine('Review Status', item['review_status_label']),
            _DetailLine('Reason', item['reason']),
            const SizedBox(height: 12),
            _MetadataBlock(
              title: 'Previous Evidence',
              value: item['old_values'],
            ),
            const SizedBox(height: 12),
            _MetadataBlock(title: 'New Evidence', value: item['new_values']),
          ],
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DefensysUi.neutralBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DefensysUi.neutralBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: DefensysUi.primaryMaroon, size: 20),
          const SizedBox(width: 10),
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
          SizedBox(width: 128, child: Text(label, style: DefensysUi.subtitle)),
          Expanded(child: Text(text.isEmpty ? '-' : text)),
        ],
      ),
    );
  }
}

class _MetadataBlock extends StatelessWidget {
  final String title;
  final dynamic value;

  const _MetadataBlock({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final rows = _metadataRows(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: DefensysUi.subtitle),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: rows.isEmpty
              ? const Text(
                  'No evidence captured',
                  style: TextStyle(color: DefensysUi.steelGrey),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: rows
                      .map(
                        (row) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 150,
                                child: Text(
                                  row.label,
                                  style: const TextStyle(
                                    color: DefensysUi.steelGrey,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: SelectableText(row.value)),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _MetadataRow {
  final String label;
  final String value;

  const _MetadataRow({required this.label, required this.value});
}

class _StatusPill extends StatelessWidget {
  final String label;
  final String value;

  const _StatusPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: DefensysUi.primaryMaroon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: DefensysUi.primaryMaroon,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final dynamic options;
  final ValueChanged<String> onChanged;
  final double? width;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Map<String, dynamic>>[
      {'value': '', 'label': 'All $label'},
      ...List<Map<String, dynamic>>.from(options ?? const []),
    ];
    final dropdown = DropdownButtonFormField<String>(
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

    if (width != null) {
      return SizedBox(width: width, child: dropdown);
    }
    return dropdown;
  }
}

int _count(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int _readinessPercent(Map<String, dynamic> counts, {int fallback = 0}) {
  final total = _count(counts['filtered'], fallback: fallback);
  final needsReview = _count(counts['needs_review']);
  if (total == 0) return 0;
  return (((total - needsReview).clamp(0, total) / total) * 100).round();
}

String _readinessStatus(SystemAuditState state) {
  final total = _count(state.counts['filtered'], fallback: state.logs.length);
  final needsReview = _count(state.counts['needs_review']);
  if (total == 0) return 'No Records';
  return needsReview == 0 ? 'Excellent' : 'Needs Review';
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
    return 'Your sign-in session expired. Sign in again, then reopen Audit Trail to reload the records.';
  }
  return error;
}

String _evidenceStatus(Map<String, dynamic> log) {
  final status = log['review_status']?.toString() ?? '';
  if (status == 'needs_review' || status == 'requires_reason') {
    return 'Needs Review';
  }
  return 'Evidence Captured';
}

String _reviewStatus(Map<String, dynamic> log) {
  final status = log['review_status']?.toString() ?? '';
  if (status == 'reviewed') return 'Reviewed';
  return 'Pending Review';
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

List<_MetadataRow> _metadataRows(dynamic value) {
  if (value == null) return const [];
  if (value is Map && value.isEmpty) return const [];
  if (value is List && value.isEmpty) return const [];
  if (value is Map) {
    return value.entries
        .map(
          (entry) => _MetadataRow(
            label: _metadataLabel(entry.key),
            value: _metadataValue(entry.value),
          ),
        )
        .toList();
  }

  final text = _metadataText(value);
  if (text == '-' || text.trim().isEmpty) return const [];
  return [_MetadataRow(label: 'Evidence', value: text)];
}

String _metadataLabel(dynamic key) {
  final raw = key?.toString().trim() ?? '';
  if (raw.isEmpty) return 'Evidence';

  const labels = {
    'active_semester': 'Active Semester',
    'active_semester_id': 'Active Semester ID',
    'forced': 'Forced Switch',
  };
  final known = labels[raw];
  if (known != null) return known;

  final spaced = raw
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      );
  return spaced
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) {
        if (part.toUpperCase() == part && part.length <= 3) return part;
        return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
      })
      .join(' ');
}

String _metadataValue(dynamic value) {
  if (value == null) return 'Not set';
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is num) return value.toString();
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? 'Not set' : text;
  }
  if (value is Map) {
    if (value.isEmpty) return 'Not set';
    return value.entries
        .map((entry) => '${_metadataLabel(entry.key)}: ${_metadataValue(entry.value)}')
        .join(', ');
  }
  if (value is List) {
    if (value.isEmpty) return 'Not set';
    return value.map(_metadataValue).join(', ');
  }

  final text = value.toString().trim();
  return text.isEmpty ? 'Not set' : text;
}

String _metadataText(dynamic value) {
  if (value == null) return '-';
  if (value is Map && value.isEmpty) return '-';
  if (value is List && value.isEmpty) return '-';
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }
}
