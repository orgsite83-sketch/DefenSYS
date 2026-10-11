import 'package:go_router/go_router.dart';
import 'package:defensys/widgets/export/report_catalog.dart';
import 'package:defensys/widgets/export/report_export_configuration.dart';
import 'package:defensys/widgets/export/defensys_report_dialog_shell.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/academic_period_provider.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/services/reports_provider.dart';
import 'package:defensys/services/defense/defense_stages_provider.dart';
import 'package:defensys/services/grading/grade_center_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/widgets/export/export.dart';
import 'package:defensys/widgets/shadcn/defensys_filter_chip.dart';
import 'package:defensys/widgets/table/defensys_segmented_control.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';

bool _isPitLeadOnly(Map<String, dynamic>? user) =>
    user?['is_pit_lead'] == true && user?['role'] != 'admin' && user?['is_superuser'] != true;

String _assignedPitYear(Map<String, dynamic>? user) =>
    (user?['pit_lead_year'] ?? '').toString().trim();

class AuditReportCenterTab extends ConsumerStatefulWidget {
  const AuditReportCenterTab({super.key, this.reportQuery = const {}});
  final Map<String, String> reportQuery;

  @override
  ConsumerState<AuditReportCenterTab> createState() => _AuditReportCenterTabState();
}

class _AuditReportCenterTabState extends ConsumerState<AuditReportCenterTab> {
  String? _selectedSemesterId;
  String? _selectedTeamId;
  String? _selectedStudentId;
  String _selectedLevel = '';
  String _selectedYearLevel = '';
  String _selectedRole = '';
  final _reportStartDateController = TextEditingController();
  final _reportEndDateController = TextEditingController();
  final _reportSearchController = TextEditingController();
  String _reportSearch = '';
  String _catalogCategory = '';
  bool _showCatalogFilters = false;
  String _reportCategoryFilter = '';
  String _selectedScope = '';
  String _reportTrackFilter = '';

  @override
  void initState() {
    super.initState();
    final initialUser = ref.read(authProvider).user;
    if (_isPitLeadOnly(initialUser)) {
      _selectedScope = 'pit';
      _selectedLevel = 'pit';
      _selectedYearLevel = _assignedPitYear(initialUser);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider).user;
      final restrictedPitLead = _isPitLeadOnly(user);
      final isPitLead = user?['is_pit_lead'] == true;
      final isPitInstructor = user?['is_pit_instructor'] == true;
      if (restrictedPitLead || isPitLead || isPitInstructor) {
        if (mounted && (restrictedPitLead || _selectedScope.isEmpty)) {
          setState(() {
            _selectedScope = 'pit';
            _selectedLevel = 'pit';
            if (restrictedPitLead) _selectedYearLevel = _assignedPitYear(user);
          });
        }
      }
      final initialReport = ReportCatalog.find(widget.reportQuery['report'] ?? '');
      if (mounted && initialReport != null && ReportCatalog.visible(user).contains(initialReport)) {
        final params = Map<String, String>.from(widget.reportQuery)..remove('tab')..remove('report')..remove('source');
        showReportExportConfiguration(context: context, ref: ref, report: initialReport, params: params);
      }
      ref.read(academicPeriodProvider.notifier).fetchPeriods();
      ref.read(studentTeamsProvider.notifier).fetchTeams();
      ref.read(defenseStagesProvider.notifier).fetchStages();
      ref.read(gradeCenterProvider.notifier).fetchGrades();
    });
  }

  @override
  void dispose() {
    _reportStartDateController.dispose();
    _reportEndDateController.dispose();
    _reportSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildReportCenter(context);
  }

  Widget _buildReportCenter(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final restrictedPitLead = _isPitLeadOnly(user);
    final catalogScope = restrictedPitLead ? 'pit' : _selectedScope;
    final catalog = ReportCatalog.visible(user);
    List<Map<String, dynamic>> group(String category) => catalog.where((report) => report.category == category).map((report) => report.toCatalogEntry()).toList();
    final gradingReports = group('grading');
    final operationsReports = group('operations');
    final governanceReports = group('governance');
    final setupReports = group('setup');
    final totalReports = [...gradingReports, ...operationsReports, ...governanceReports, ...setupReports]
        .where((report) => catalogScope.isEmpty || report['scope'] == null || report['scope'] == catalogScope).length;
    final visibleGradingReports = _filterReports(gradingReports, 'grading');
    final visibleOperationsReports = _filterReports(operationsReports, 'operations');
    final visibleGovernanceReports = _filterReports(governanceReports, 'governance');
    final visibleSetupReports = _filterReports(setupReports, 'setup');
    final visibleCount =
        visibleGradingReports.length +
        visibleOperationsReports.length +
        visibleGovernanceReports.length + visibleSetupReports.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((widget.reportQuery['source'] ?? '').startsWith('/admin/') || (widget.reportQuery['source'] ?? '').startsWith('/faculty/'))
          Padding(padding: const EdgeInsets.only(bottom: 12), child: TextButton.icon(icon: const Icon(Icons.arrow_back, size: 16), label: const Text('Back to source'), onPressed: () {
            if (GoRouter.of(context).canPop()) { context.pop(); } else { context.go(widget.reportQuery['source']!); }
          })),
        DefensysPageHeader(
          icon: Icons.summarize_outlined,
          title: 'Report Export Center',
          subtitle:
              'Preview and export filtered academic records as PDF or Excel.',
          actions: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: DefensysTokens.surfaceOf(context),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
              border: Border.all(color: DefensysTokens.borderOf(context)),
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
                  '$totalReports reports available',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (restrictedPitLead)
          _buildPitLeadScopeBanner(_assignedPitYear(user))
        else
          DefensysSegmentedControl<String>(
            value: _selectedScope,
            items: const [
              DefensysSegmentItem(value: '', label: 'All scopes'),
              DefensysSegmentItem(value: 'capstone', label: 'Capstone'),
              DefensysSegmentItem(value: 'pit', label: 'PIT'),
            ],
            onChanged: (value) => setState(() {
              _selectedScope = value;
              _selectedLevel = value;
            }),
          ),
        const SizedBox(height: 12),
        _buildReportSearch(visibleCount, totalReports),
        const SizedBox(height: 24),

        // Section 1: Academic Grading & Evaluation
        if (visibleGradingReports.isNotEmpty) ...[
          _buildReportCategoryHeader(
            title: 'ACADEMIC GRADING & EVALUATION',
            subtitle:
                'Official defense grades, individual evaluation slips, and semester compilation rosters.',
            icon: Icons.assignment_turned_in_outlined,
            count: visibleGradingReports.length,
          ),
          const SizedBox(height: 12),
          _buildReportList(visibleGradingReports),
          const SizedBox(height: 24),
        ],

        // Section 2: Defense Schedules & Team Rosters
        if (visibleOperationsReports.isNotEmpty) ...[
          _buildReportCategoryHeader(
            title: 'DEFENSE OPERATIONS & ROSTERS',
            subtitle:
                'Defense timetable schedules, panel room assignments, and official team directories.',
            icon: Icons.event_note_outlined,
            count: visibleOperationsReports.length,
          ),
          const SizedBox(height: 12),
          _buildReportList(visibleOperationsReports),
          const SizedBox(height: 24),
        ],

        // Section 3: Governance & System Compliance
        if (visibleGovernanceReports.isNotEmpty) ...[
          _buildReportCategoryHeader(
            title: 'GOVERNANCE & SYSTEM COMPLIANCE',
            subtitle:
                'Institutional audit registers, evidence logs, and system account directories.',
            icon: Icons.verified_user_outlined,
            count: visibleGovernanceReports.length,
          ),
          const SizedBox(height: 12),
          _buildReportList(visibleGovernanceReports),
          const SizedBox(height: 20),
        ],
        if (visibleSetupReports.isNotEmpty) ...[
          _buildReportCategoryHeader(title: 'ACADEMIC SETUP & REQUIREMENTS', subtitle: 'Academic periods, grading configuration and required deliverables.', icon: Icons.tune_outlined, count: visibleSetupReports.length),
          const SizedBox(height: 12), _buildReportList(visibleSetupReports), const SizedBox(height: 24),
        ],
        if (visibleCount == 0) _buildNoReportsFound(),
      ],
    );
  }

  List<Map<String, dynamic>> _filterReports(
    List<Map<String, dynamic>> reports,
    String category,
  ) {
    if (_catalogCategory.isNotEmpty && _catalogCategory != category) return [];
    final effectiveScope = _isPitLeadOnly(ref.read(authProvider).user) ? 'pit' : _selectedScope;
    final query = _reportSearch.trim().toLowerCase();
    return reports.where((report) {
      final scope = report['scope']?.toString() ?? '';
      if (effectiveScope.isNotEmpty && scope.isNotEmpty && scope != effectiveScope) return false;
      if (query.isEmpty) return true;
      final searchable = [
        report['title'],
        report['desc'],
        report['tag'],
        report['paramHint'],
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  Widget _buildPitLeadScopeBanner(String year) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lock_outline_rounded, size: 17, color: DefensysTokens.maroonOf(context)),
        const SizedBox(width: 8),
        Text('PIT reports · ${year.isEmpty ? 'No assigned year level' : year}',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            color: DefensysTokens.textPrimaryOf(context))),
      ]),
    );
  }

  Widget _buildReportSearch(int visibleCount, int totalReports) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final search = SizedBox(
          height: 40,
          child: TextField(
            controller: _reportSearchController,
            onChanged: (value) => setState(() => _reportSearch = value),
            style: TextStyle(fontSize: 13, color: DefensysTokens.textPrimaryOf(context)),
            decoration: InputDecoration(
              hintText: 'Search reports by name, topic, or required filter...',
              hintStyle: TextStyle(
                fontSize: 13,
                color: DefensysTokens.textSecondaryOf(context),
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 18,
                color: DefensysTokens.textSecondaryOf(context),
              ),
              suffixIcon: _reportSearch.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear report search',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _reportSearchController.clear();
                        setState(() => _reportSearch = '');
                      },
                    ),
              filled: true,
              fillColor: DefensysTokens.isDark(context)
                  ? DefensysTokens.mistInputFill
                  : const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: DefensysTokens.maroonOf(context)),
              ),
            ),
          ),
        );
        final filterButton = SizedBox(
          height: 40,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _showCatalogFilters = !_showCatalogFilters),
            icon: Icon(
              _showCatalogFilters ? Icons.filter_alt_off_rounded : Icons.filter_alt_rounded,
              size: 16,
            ),
            label: Text(_showCatalogFilters ? 'Hide Filters' : 'Filters'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _showCatalogFilters || _catalogCategory.isNotEmpty
                  ? DefensysTokens.maroonOf(context)
                  : DefensysTokens.textPrimaryOf(context),
              side: BorderSide(
                color: _showCatalogFilters || _catalogCategory.isNotEmpty
                    ? DefensysTokens.maroonOf(context)
                    : DefensysTokens.borderOf(context),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        );
        final clearButton = SizedBox(
          height: 40,
          child: OutlinedButton.icon(
            onPressed: () {
              _reportSearchController.clear();
              final restrictedPitLead = _isPitLeadOnly(ref.read(authProvider).user);
              setState(() {
                _reportSearch = '';
                _catalogCategory = '';
                _selectedScope = restrictedPitLead ? 'pit' : '';
                _selectedLevel = _selectedScope;
              });
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Clear Filters'),
            style: OutlinedButton.styleFrom(
              foregroundColor: DefensysTokens.textSecondaryOf(context),
              side: BorderSide(color: DefensysTokens.borderOf(context)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        );
        final count = Text(
          _reportSearch.isEmpty && _catalogCategory.isEmpty
              ? 'Browse reports by category'
              : '$visibleCount of $totalReports reports',
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        );
        final toolbar = constraints.maxWidth < 580
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  search,
                  const SizedBox(height: 10),
                  Wrap(spacing: 10, runSpacing: 10, children: [filterButton, clearButton]),
                ],
              )
            : Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  filterButton,
                  const SizedBox(width: 12),
                  clearButton,
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            toolbar,
            if (_showCatalogFilters) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: DefensysTokens.surfaceOf(context),
                  border: Border.all(color: DefensysTokens.borderOf(context)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Report category', style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.textPrimaryOf(context),
                    )),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _catalogCategoryChip('', 'All categories'),
                        _catalogCategoryChip('grading', 'Academic grading & evaluation'),
                        _catalogCategoryChip('operations', 'Defense operations & rosters'),
                        _catalogCategoryChip('setup', 'Academic setup & requirements'),
                        _catalogCategoryChip('governance', 'Governance & system compliance'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            count,
          ],
        );
      },
    );
  }

  Widget _catalogCategoryChip(String value, String label) {
    return DefensysFilterChip(
      label: label,
      selected: _catalogCategory == value,
      onSelected: (_) => setState(() => _catalogCategory = value),
    );
  }

  Widget _buildNoReportsFound() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 28,
            color: DefensysTokens.textSecondaryOf(context),
          ),
          const SizedBox(height: 10),
          Text(
            'No reports found',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try a report name, topic, or required filter.',
            style: TextStyle(color: DefensysTokens.textSecondaryOf(context)),
          ),
        ],
      ),
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
            color: DefensysTokens.maroonOf(context).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
          ),
          child: Icon(icon, color: DefensysTokens.maroonOf(context), size: 16),
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
                title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: DefensysTokens.textPrimaryOf(context),
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: DefensysTokens.isDark(context)
                          ? DefensysTokens.surfaceHigherOf(context)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(
                        DefensysTokens.radiusPill,
                      ),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReportList(List<Map<String, dynamic>> reports) {
    return Container(
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < reports.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                indent: 64,
                color: DefensysTokens.borderOf(context),
              ),
            _buildReportRow(reports[index]),
          ],
        ],
      ),
    );
  }

  Widget _buildReportRow(Map<String, dynamic> report) {
    final title = report['title'] as String;
    final desc = report['desc'] as String;
    final icon = report['icon'] as IconData;
    final paramHint = report['paramHint'] as String? ?? 'PDF Document';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openReportExportDialog(context, report),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 700;
            final reportDetails = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 3),
              Text(
                report['scope'] == 'pit' ? 'PIT' : report['scope'] == 'capstone' ? 'Capstone'
                    : ['user-directory', 'audit-trail'].contains(report['endpoint']) ? 'System reports'
                    : _selectedScope.isEmpty ? 'Capstone & PIT' : _scopeLabel(_selectedScope),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: DefensysTokens.maroonOf(context)),
              ),
              const SizedBox(height: 3),
                Text(
                  desc,
                  maxLines: compact ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ],
            );
            final filterHint = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 14,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    paramHint,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ),
              ],
            );
            final exportButton = FilledButton.icon(
              icon: const Icon(Icons.download_rounded, size: 15),
              label: const Text('Configure export'),
              style: FilledButton.styleFrom(
                backgroundColor: DefensysTokens.maroonOf(context),
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                ),
                elevation: 0,
              ),
              onPressed: () => _openReportExportDialog(context, report),
            );

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 20,
                vertical: compact ? 14 : 13,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: DefensysTokens.maroonOf(
                        context,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(
                        DefensysTokens.radiusMd,
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: DefensysTokens.maroonOf(context),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              reportDetails,
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(child: filterHint),
                                  const SizedBox(width: 8),
                                  exportButton,
                                ],
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: reportDetails),
                              const SizedBox(width: 20),
                              SizedBox(width: 180, child: filterHint),
                              const SizedBox(width: 20),
                              exportButton,
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Opens the Dedicated Export Configuration Dialog
  void _openReportExportDialog(BuildContext context, Map<String, dynamic> report) {
    final definition = ReportCatalog.find(report['id']?.toString() ?? '');
    if (definition != null && !definition.legacy) {
      showReportExportConfiguration(context: context, ref: ref, report: definition, params: {if (_selectedScope.isNotEmpty) 'scope': _selectedScope});
      return;
    }
    final teamsState = ref.read(studentTeamsProvider);
    final academicState = ref.read(academicPeriodProvider);
    final defenseStagesState = ref.read(defenseStagesProvider);
    final gradeCenterState = ref.read(gradeCenterProvider);
    final user = ref.read(authProvider).user;
    final restrictedPitLead = _isPitLeadOnly(user);
    final assignedYear = _assignedPitYear(user);
    final visibleTeams = restrictedPitLead
        ? teamsState.teams.where((team) =>
            assignedYear.isNotEmpty && _teamScope(team) == 'pit' &&
            team['year_level']?.toString() == assignedYear).toList()
        : teamsState.teams;

    // Build combined students list from team members (primary) and unassigned students
    final Map<String, Map<String, dynamic>> studentMetaMap = {};
    final Map<String, Map<String, dynamic>> allStudentsMap = {};

    for (final team in visibleTeams) {
      final sec = team['section']?.toString() ?? team['year_level']?.toString();
      final leader = team['leader'] as Map<String, dynamic>?;
      if (leader != null) {
        final id = leader['id']?.toString();
        if (id != null) {
          allStudentsMap[id] = leader;
          studentMetaMap[id] = {
            'student': leader,
            'team': team,
            'isLeader': true,
            'contexts': [
              ...?studentMetaMap[id]?['contexts'] as List<dynamic>?,
              {'team': team, 'section': sec, 'isLeader': true},
            ],
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
                'student': m,
                'team': team,
                'isLeader': false,
                'contexts': [
                  ...?studentMetaMap[mId]?['contexts'] as List<dynamic>?,
                  {'team': team, 'section': sec, 'isLeader': false},
                ],
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
    for (final st in restrictedPitLead ? <Map<String, dynamic>>[] : teamsState.students) {
      final sId = st['id']?.toString();
      if (sId != null && !allStudentsMap.containsKey(sId)) {
        allStudentsMap[sId] = st;
        studentMetaMap[sId] = {
          'student': st,
          'contexts': <Map<String, dynamic>>[],
          'teamName': 'Unassigned',
          'projectTitle': null,
          'section': null,
        };
      }
    }

    final List<Map<String, dynamic>> allStudentsList = allStudentsMap.values.map((student) => {
      ...student,
      'name': student['name'] ?? '${student['first_name'] ?? ''} ${student['last_name'] ?? ''}'.trim(),
    }).toList();

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
    for (final team in visibleTeams) {
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
        {'id': 1, 'event_name': '1st Year PIT', 'year_level': '1st Year'},
        {'id': 2, 'event_name': '2nd Year PIT', 'year_level': '2nd Year'},
        {'id': 3, 'event_name': '3rd Year PIT', 'year_level': '3rd Year'},
      ]);
    }
    if (restrictedPitLead) {
      pitEvents.removeWhere((event) {
        final eventYear = (event['year_level'] ?? '').toString().trim();
        return eventYear.isNotEmpty && eventYear != assignedYear;
      });
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return _ReportExportConfigDialog(
          report: report,
          currentUser: user,
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
          initialScope: restrictedPitLead ? 'pit' : report['scope']?.toString() ?? _selectedScope,
          initialLevel: restrictedPitLead ? 'pit' : _selectedLevel,
          initialYearLevel: restrictedPitLead ? assignedYear : _selectedYearLevel,
          initialRole: _selectedRole,
          initialCategory: _reportCategoryFilter,
          initialTrack: _reportTrackFilter,
          initialStartDate: _reportStartDateController.text.trim(),
          initialEndDate: _reportEndDateController.text.trim(),
          onFetchCandidates: (params) => ref.read(reportsProvider.notifier).fetchAssessmentCandidates(params),
          onDownload: (params) async {
            return await _triggerReportDownload(
              report,
              studentId: params['studentId'],
              teamId: params['teamId'],
              semesterId: params['semesterId'],
              scope: params['scope'],
              coverage: params['coverage'],
              gradeId: params['gradeId'],
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
              coverage: params['coverage'],
              gradeId: params['gradeId'],
              stage: params['stage'],
              pitEvent: params['pitEvent'],
              level: params['level'],
              yearLevel: params['yearLevel'],
              role: params['role'],
              category: params['category'],
              track: params['track'],
              startDate: params['startDate'],
              endDate: params['endDate'],
              includeSignatures: params['include_signatures'],
              signatories: params['signatories'],
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
            teams: visibleTeams,
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
    String? coverage,
    String? gradeId,
    String? stage,
    String? pitEvent,
    String? level,
    String? yearLevel,
    String? role,
    String? category,
    String? track,
    String? startDate,
    String? endDate,
    String? includeSignatures,
    String? signatories,
  }) async {
    final endpoint = report['endpoint'] as String;
    final queryParams = <String, String>{};

    if (endpoint == 'team-grade' || endpoint == 'individual-grade') {
      final selectedScope = scope ?? _selectedScope;
      final selectedSemester = semesterId ?? _selectedSemesterId;
      if (selectedScope.isNotEmpty) queryParams['scope'] = selectedScope;
      if (selectedSemester != null && selectedSemester.isNotEmpty) queryParams['semester_id'] = selectedSemester;
      queryParams['coverage'] = coverage ?? 'latest';
      if (gradeId != null && gradeId.isNotEmpty) queryParams['grade_id'] = gradeId;
    }

    if (includeSignatures != null && includeSignatures.isNotEmpty) {
      queryParams['include_signatures'] = includeSignatures;
    }
    if (signatories != null && signatories.isNotEmpty) {
      queryParams['signatories'] = signatories;
    }

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
    String? coverage,
    String? gradeId,
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

    if (endpoint == 'team-grade' || endpoint == 'individual-grade') {
      final selectedScope = scope ?? _selectedScope;
      final selectedSemester = semesterId ?? _selectedSemesterId;
      if (selectedScope.isNotEmpty) queryParams['scope'] = selectedScope;
      if (selectedSemester != null && selectedSemester.isNotEmpty) queryParams['semester_id'] = selectedSemester;
      queryParams['coverage'] = coverage ?? 'latest';
      if (gradeId != null && gradeId.isNotEmpty) queryParams['grade_id'] = gradeId;
    }

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

String _teamScope(Map<String, dynamic> team) {
  final scope = team['scope']?.toString().toLowerCase() ?? '';
  if (scope == 'capstone' || scope == 'pit' || scope == 'mixed') return scope;
  final level = team['level']?.toString().toLowerCase() ?? '';
  if (level.contains('capstone')) return 'capstone';
  if (level.contains('pit')) return 'pit';
  return '';
}

String _scopeLabel(String scope) => scope == 'capstone' ? 'Capstone' : scope == 'pit' ? 'PIT' : scope == 'mixed' ? 'Capstone & PIT' : 'Scope unavailable';

InputDecoration _reportInputDecoration(BuildContext context, String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: 12.5, color: DefensysTokens.textSecondaryOf(context)),
    filled: true,
    fillColor: DefensysTokens.isDark(context) ? DefensysTokens.surfaceHigherOf(context) : const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    isDense: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      borderSide: BorderSide(color: DefensysTokens.maroonOf(context), width: 1.5),
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
      backgroundColor: DefensysTokens.surfaceOf(context),
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
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: DefensysTokens.borderOf(context))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DefensysTokens.maroonOf(context).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                    ),
                    child: Icon(Icons.person_search_rounded, color: DefensysTokens.maroonOf(context), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Student Candidate',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${filtered.length} of ${widget.students.length} candidates available',
                          style: TextStyle(fontSize: 11.5, color: DefensysTokens.textSecondaryOf(context)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: DefensysTokens.textSecondaryOf(context)),
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
                    style: TextStyle(fontSize: 13, color: DefensysTokens.textPrimaryOf(context)),
                    decoration: InputDecoration(
                      hintText: 'Search by student ID (e.g. 4011), name, team, section...',
                      hintStyle: TextStyle(fontSize: 13, color: DefensysTokens.textSecondaryOf(context)),
                      prefixIcon: Icon(Icons.search_rounded, color: DefensysTokens.textSecondaryOf(context), size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear_rounded, size: 18, color: DefensysTokens.textSecondaryOf(context)),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: DefensysTokens.isDark(context) ? DefensysTokens.surfaceHigherOf(context) : const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: BorderSide(color: DefensysTokens.maroonOf(context), width: 1.5),
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

            Divider(height: 1, color: DefensysTokens.borderOf(context)),

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
                              decoration: BoxDecoration(
                                color: DefensysTokens.isDark(context) ? DefensysTokens.surfaceHigherOf(context) : const Color(0xFFF1F5F9),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.person_off_outlined, size: 36, color: DefensysTokens.textSecondaryOf(context)),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'No matching student candidates',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DefensysTokens.textPrimaryOf(context)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Try adjusting your search keywords or resetting the section filter.',
                              style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context)),
                              textAlign: TextAlign.center,
                            ),
                            if (_searchController.text.isNotEmpty || _selectedSection.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              TextButton.icon(
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('Reset Filters'),
                                style: TextButton.styleFrom(foregroundColor: DefensysTokens.maroonOf(context)),
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
                                color: isSelected
                                    ? DefensysTokens.maroonOf(context).withValues(alpha: 0.08)
                                    : (DefensysTokens.isDark(context) ? DefensysTokens.surfaceHigherOf(context) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                                border: Border.all(
                                  color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.borderOf(context),
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
                                      color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.maroonOf(context).withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      _extractInitials(name.toString()),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: isSelected ? Colors.white : DefensysTokens.maroonOf(context),
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
                                                  color: DefensysTokens.textPrimaryOf(context),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: isSelected ? DefensysTokens.maroonOf(context) : (DefensysTokens.isDark(context) ? const Color(0xFF334155) : const Color(0xFF1E293B)),
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
                                                  color: DefensysTokens.goldOf(context).withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                                ),
                                                child: Text(
                                                  'LEADER',
                                                  style: TextStyle(
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: DefensysTokens.goldOf(context),
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
                                                  color: DefensysTokens.maroonOf(context).withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.groups_rounded, size: 11, color: DefensysTokens.maroonOf(context)),
                                                    const SizedBox(width: 3),
                                                    Text(
                                                      team['name']?.toString() ?? 'Team',
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.w700,
                                                        color: DefensysTokens.maroonOf(context),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ] else ...[
                                              Text(
                                                'No Team Assigned',
                                                style: TextStyle(fontSize: 11, color: DefensysTokens.textSecondaryOf(context)),
                                              ),
                                            ],
                                            if (section != null && section.isNotEmpty) ...[
                                              const SizedBox(width: 6),
                                              Text('•', style: TextStyle(color: DefensysTokens.textSecondaryOf(context))),
                                              const SizedBox(width: 6),
                                              Text(
                                                section,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: DefensysTokens.textSecondaryOf(context),
                                                ),
                                              ),
                                            ],
                                            if (email.isNotEmpty) ...[
                                              const SizedBox(width: 6),
                                              Text('•', style: TextStyle(color: DefensysTokens.textSecondaryOf(context))),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  email,
                                                  style: TextStyle(fontSize: 11, color: DefensysTokens.textSecondaryOf(context)),
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
                                    color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.borderOf(context),
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
            color: isSelected
                ? DefensysTokens.maroonOf(context)
                : (DefensysTokens.isDark(context) ? DefensysTokens.surfaceHigherOf(context) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
            border: Border.all(
              color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.borderOf(context),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : DefensysTokens.textSecondaryOf(context),
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
      backgroundColor: DefensysTokens.surfaceOf(context),
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
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: DefensysTokens.borderOf(context))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DefensysTokens.maroonOf(context).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                    ),
                    child: Icon(Icons.groups_rounded, color: DefensysTokens.maroonOf(context), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Student Team',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${filtered.length} of ${widget.teams.length} teams available',
                          style: TextStyle(fontSize: 11.5, color: DefensysTokens.textSecondaryOf(context)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: DefensysTokens.textSecondaryOf(context)),
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
                    style: TextStyle(fontSize: 13, color: DefensysTokens.textPrimaryOf(context)),
                    decoration: InputDecoration(
                      hintText: 'Search by team name, project title, leader, adviser, section...',
                      hintStyle: TextStyle(fontSize: 13, color: DefensysTokens.textSecondaryOf(context)),
                      prefixIcon: Icon(Icons.search_rounded, color: DefensysTokens.textSecondaryOf(context), size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear_rounded, size: 18, color: DefensysTokens.textSecondaryOf(context)),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: DefensysTokens.isDark(context) ? DefensysTokens.surfaceHigherOf(context) : const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: BorderSide(color: DefensysTokens.maroonOf(context), width: 1.5),
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

            Divider(height: 1, color: DefensysTokens.borderOf(context)),

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
                              decoration: BoxDecoration(
                                color: DefensysTokens.isDark(context) ? DefensysTokens.surfaceHigherOf(context) : const Color(0xFFF1F5F9),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.group_off_outlined, size: 36, color: DefensysTokens.textSecondaryOf(context)),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'No matching student teams',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DefensysTokens.textPrimaryOf(context)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Try adjusting your search keywords or resetting the section filter.',
                              style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context)),
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
                                color: isSelected
                                    ? DefensysTokens.maroonOf(context).withValues(alpha: 0.08)
                                    : (DefensysTokens.isDark(context) ? DefensysTokens.surfaceHigherOf(context) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                                border: Border.all(
                                  color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.borderOf(context),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.maroonOf(context).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.groups_rounded,
                                      color: isSelected ? Colors.white : DefensysTokens.maroonOf(context),
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
                                                  color: DefensysTokens.textPrimaryOf(context),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (sec.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.maroonOf(context).withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                                ),
                                                child: Text(
                                                  sec,
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: isSelected ? Colors.white : DefensysTokens.maroonOf(context),
                                                  ),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(width: 5),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: DefensysTokens.isDark(context) ? DefensysTokens.surfaceHigherOf(context) : const Color(0xFFE2E8F0),
                                                borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                              ),
                                              child: Text(
                                                '${members.length} members',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w600,
                                                  color: DefensysTokens.textSecondaryOf(context),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          projectTitle,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w500,
                                            color: DefensysTokens.textSecondaryOf(context),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Leader: $leaderName • Adviser: $adviserName',
                                          style: TextStyle(fontSize: 10.5, color: DefensysTokens.textSecondaryOf(context)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 10),
                                  Icon(
                                    isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                    color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.borderOf(context),
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
            color: isSelected
                ? DefensysTokens.maroonOf(context)
                : (DefensysTokens.isDark(context) ? DefensysTokens.surfaceHigherOf(context) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
            border: Border.all(
              color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.borderOf(context),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : DefensysTokens.textSecondaryOf(context),
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
  final String initialLevel;
  final String initialYearLevel;
  final String initialRole;
  final String initialCategory;
  final String initialTrack;
  final String initialStartDate;
  final String initialEndDate;
  final Future<bool> Function(Map<String, String>) onDownload;
  final Future<ReportPreviewData?> Function(Map<String, String>) onFetchPreview;
  final Future<Map<String, dynamic>?> Function(Map<String, String>) onFetchCandidates;
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
    required this.initialLevel,
    required this.initialYearLevel,
    required this.initialRole,
    required this.initialCategory,
    required this.initialTrack,
    required this.initialStartDate,
    required this.initialEndDate,
    required this.onDownload,
    required this.onFetchPreview,
    required this.onFetchCandidates,
    required this.onOpenStudentPicker,
    required this.onOpenTeamPicker,
  });

  @override
  State<_ReportExportConfigDialog> createState() => _ReportExportConfigDialogState();
}

class _ReportExportConfigDialogState extends State<_ReportExportConfigDialog> {
  bool get _restrictedPitLead => _isPitLeadOnly(widget.currentUser);
  String get _assignedYear => _assignedPitYear(widget.currentUser);
  String _selectedFormat = 'pdf'; // 'pdf', 'xlsx'

  String? _selectedSemesterId;
  String? _selectedStudentId;
  String? _selectedTeamId;
  String _selectedScope = '';
  String _selectedStage = '';
  String _selectedPitEvent = '';
  String _selectedCoverage = 'latest';
  List<Map<String, dynamic>> _candidateTeams = [];
  List<Map<String, dynamic>> _candidateStudents = [];
  Map<String, Map<String, dynamic>> _candidateStudentMeta = {};
  List<Map<String, dynamic>> _availableAssessments = [];
  int _candidateRequestId = 0;
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
  int _previewRequestId = 0;

  bool _includeSignatures = false;
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
      final t = _candidateTeams.firstWhere(
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
        _loadPreview();
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedSemesterId = widget.initialSemesterId;
    _selectedStudentId = widget.initialStudentId;
    _selectedTeamId = widget.initialTeamId;
    _selectedScope = _restrictedPitLead ? 'pit' : widget.initialScope;
    _candidateTeams = widget.teamsState.teams;
    _candidateStudents = widget.allStudents;
    _candidateStudentMeta = widget.studentMetaMap;
    _selectedStage = '';
    _selectedPitEvent = '';
    _selectedLevel = _restrictedPitLead ? 'pit' : widget.initialLevel;
    _selectedYearLevel = _restrictedPitLead ? _assignedYear : widget.initialYearLevel;
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
      if (_selectedSemesterId != null || _selectedScope.isNotEmpty) _loadCandidates();
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
      if (_restrictedPitLead) 'scope': 'pit' else if (_selectedScope.isNotEmpty) 'scope': _selectedScope,
      'coverage': _selectedCoverage == 'all' ? 'all' : _selectedCoverage.startsWith('grade:') ? 'specific' : 'latest',
      if (_selectedCoverage.startsWith('grade:')) 'gradeId': _selectedCoverage.substring(6),
      if (_selectedStage.isNotEmpty) 'stage': _selectedStage,
      if (_selectedPitEvent.isNotEmpty) 'pitEvent': _selectedPitEvent,
      if (_restrictedPitLead) 'level': 'pit' else if (_selectedLevel.isNotEmpty) 'level': _selectedLevel,
      if (_restrictedPitLead) 'yearLevel': _assignedYear else if (_selectedYearLevel.isNotEmpty) 'yearLevel': _selectedYearLevel,
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
    final requestId = ++_previewRequestId;
    final endpoint = widget.report['endpoint'] as String;

    // Check if required selection is missing
    if (endpoint == 'individual-grade' && _selectedStudentId == null) {
      if (mounted) {
        setState(() {
          _previewData = null;
          _isLoadingPreview = false;
        });
      }
      return;
    }
    if (endpoint == 'team-grade' && _selectedTeamId == null) {
      if (mounted) {
        setState(() {
          _previewData = null;
          _isLoadingPreview = false;
        });
      }
      return;
    }

    setState(() => _isLoadingPreview = true);

    try {
      final preview = await widget.onFetchPreview(_buildCurrentParams());
      if (!mounted || requestId != _previewRequestId) return;
      setState(() {
        _isLoadingPreview = false;
        _previewData = preview;
        if (preview != null) _availableAssessments = preview.assessments;
      });
    } catch (_) {
      if (!mounted || requestId != _previewRequestId) return;
      setState(() {
        _isLoadingPreview = false;
        _previewData = null;
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

    final selectedStudentObj = _selectedStudentId == null ? null : _candidateStudents.firstWhere(
      (student) => student['id']?.toString() == _selectedStudentId,
      orElse: () => <String, dynamic>{},
    );

    final selectedTeamObj = _selectedTeamId != null
        ? _candidateTeams.firstWhere(
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
              'label': '${year['school_year'] ?? year['label'] ?? ''} | ${sem['label'] ?? ''}',
            });
          }
        }
      }
    }

    return DefensysReportDialogShell(
      title: title,
      subtitle: desc,
      icon: icon,
      tag: tag,
      onClose: () => Navigator.of(context).pop(),
      controls: endpoint == 'team-grade' || endpoint == 'individual-grade'
          ? _buildAssessmentControls(semestersList) : null,
      filters: _buildLeftSelectorPane(endpoint: endpoint, semestersList: semestersList),
      preview: _buildRightPreviewPane(
        endpoint: endpoint,
        selectedStudentObj: selectedStudentObj,
        selectedTeamObj: selectedTeamObj,
      ),
      footer: _buildModalFooter(),
    );
  }

  /// Left Pane: Either List of Items (Teams/Students) or Filter Parameters Form
  bool _teamMatchesContext(Map<String, dynamic> team) {
    if (_restrictedPitLead && (_assignedYear.isEmpty || _teamScope(team) != 'pit'
        || team['year_level']?.toString() != _assignedYear)) {
      return false;
    }
    if (_selectedScope.isNotEmpty && _teamScope(team) != _selectedScope
        && !(team['scope'] == 'mixed' && (team['scopes'] as List? ?? []).contains(_selectedScope))) {
      return false;
    }
    final semester = team['semester_id']?.toString();
    return _selectedSemesterId == null || semester == null || semester == _selectedSemesterId;
  }

  List<String> get _candidateTeamSections => _candidateTeams.where(_teamMatchesContext)
      .map((team) => (team['section'] ?? team['year_level'] ?? '').toString().trim())
      .where((section) => section.isNotEmpty).toSet().toList()..sort();

  List<String> get _candidateStudentSections => _candidateStudents
      .map((student) => (_studentContext(student['id'].toString())?['section'] ?? '').toString().trim())
      .where((section) => section.isNotEmpty).toSet().toList()..sort();

  Future<void> _loadCandidates() async {
    final requestId = ++_candidateRequestId;
    final data = await widget.onFetchCandidates({
      if (_restrictedPitLead) 'scope': 'pit' else if (_selectedScope.isNotEmpty) 'scope': _selectedScope,
      if (_selectedSemesterId != null) 'semester_id': _selectedSemesterId!,
    });
    if (!mounted || requestId != _candidateRequestId || data == null || data['teams'] is! List) return;
    setState(() {
      _candidateTeams = (data['teams'] as List).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
      _candidateStudents = (data['students'] as List? ?? []).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
      _candidateStudentMeta = (data['student_contexts'] as Map? ?? {}).map((key, value) => MapEntry(key.toString(), Map<String, dynamic>.from(value as Map)));
      if (_selectedTeamId != null && !_candidateTeams.any((team) => team['id']?.toString() == _selectedTeamId)) _selectedTeamId = null;
      if (_selectedStudentId != null && !_candidateStudents.any((student) => student['id']?.toString() == _selectedStudentId)) _selectedStudentId = null;
    });
    _loadPreview();
  }

  Map<String, dynamic>? _studentContext(String id) {
    final meta = _candidateStudentMeta[id];
    final contexts = meta?['contexts'] as List<dynamic>?;
    if (contexts != null) {
      for (final item in contexts) {
        if (item is Map<String, dynamic> && item['team'] is Map<String, dynamic>
            && _teamMatchesContext(item['team'] as Map<String, dynamic>)) {
          return item;
        }
      }
      return null;
    }
    return meta;
  }

  String _studentContextLabel(String id) {
    final contexts = (_candidateStudentMeta[id]?['contexts'] as List? ?? [])
        .whereType<Map>().where((item) => item['team'] is Map<String, dynamic>
            && _teamMatchesContext(item['team'] as Map<String, dynamic>)).toList();
    final scopes = contexts.map((item) => _scopeLabel(_teamScope(item['team'] as Map<String, dynamic>))).toSet();
    if (contexts.length > 1) return '${scopes.join(' & ')} · ${contexts.length} team / period contexts';
    final meta = _studentContext(id);
    final team = meta?['team'] as Map<String, dynamic>?;
    return team == null ? 'No assessment context' : '${_scopeLabel(_teamScope(team))} · ${team['name']} · ${meta?['section'] ?? ''}';
  }

  Widget _buildAssessmentControls(List<Map<String, dynamic>> semesters) {
    final assessments = _availableAssessments;
    final selectedTeam = _candidateTeams.where((team) => team['id']?.toString() == _selectedTeamId).firstOrNull;
    final effectiveScope = _selectedScope.isNotEmpty ? _selectedScope : selectedTeam == null ? '' : _teamScope(selectedTeam);
    final noun = effectiveScope == 'pit' ? 'event' : effectiveScope == 'capstone' ? 'stage' : 'assessment';
    final coverageItems = <DropdownMenuItem<String>>[
      DropdownMenuItem(value: 'latest', child: Text('Latest recorded $noun')),
      DropdownMenuItem(value: 'all', child: Text(effectiveScope == 'pit' ? 'All recorded events' : effectiveScope == 'capstone' ? 'All recorded stages' : 'All recorded stages / events')),
      ...assessments.map((grade) => DropdownMenuItem(
        value: 'grade:${grade['id']}',
        child: Tooltip(
          message: '${_scopeLabel(grade['scope']?.toString() ?? '')} · ${grade['stage_label']} · ${grade['team_name'] ?? ''} · ${grade['academic_period'] ?? ''}',
          child: Text('${_scopeLabel(grade['scope']?.toString() ?? '')} · ${grade['stage_label']}${grade['academic_period'] == null ? '' : ' · ${grade['academic_period']}'}', overflow: TextOverflow.ellipsis),
        ),
      )),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: DefensysTokens.borderOf(context)))),
      child: Wrap(
        spacing: 12, runSpacing: 10,
        children: [
          SizedBox(width: 200, child: DropdownButtonFormField<String>(
            key: ValueKey('assessment-scope-$_selectedScope'),
            initialValue: _selectedScope,
            isExpanded: true,
            decoration: _reportInputDecoration(context, '').copyWith(labelText: 'Academic scope'),
            items: _restrictedPitLead ? const [
              DropdownMenuItem(value: 'pit', child: Text('PIT · assigned year')),
            ] : const [
              DropdownMenuItem(value: '', child: Text('All scopes')),
              DropdownMenuItem(value: 'capstone', child: Text('Capstone')),
              DropdownMenuItem(value: 'pit', child: Text('PIT')),
            ],
            onChanged: _restrictedPitLead ? null : (value) {
              setState(() {
                _selectedScope = value ?? '';
                _selectedTeamId = null;
                _selectedStudentId = null;
                _selectedSectionFilter = '';
                _selectedCoverage = 'latest';
                _availableAssessments = [];
                _previewData = null;
              });
              _loadCandidates();
              _loadPreview();
            },
          )),
          SizedBox(width: 245, child: DropdownButtonFormField<String>(
            key: ValueKey('assessment-period-$_selectedSemesterId'),
            initialValue: _selectedSemesterId,
            isExpanded: true,
            decoration: _reportInputDecoration(context, '').copyWith(labelText: 'Academic period'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All academic periods')),
              ...semesters.map((semester) => DropdownMenuItem(value: semester['id']?.toString(), child: Text(semester['label']?.toString() ?? ''))),
              if (_selectedSemesterId != null && !semesters.any((semester) => semester['id']?.toString() == _selectedSemesterId))
                DropdownMenuItem(value: _selectedSemesterId, child: const Text('Active academic period')),
            ],
            onChanged: (value) {
              setState(() {
                _selectedSemesterId = value;
                _selectedTeamId = null;
                _selectedStudentId = null;
                _selectedCoverage = 'latest';
                _availableAssessments = [];
                _selectedSectionFilter = '';
                _previewData = null;
              });
              _loadCandidates();
              _loadPreview();
            },
          )),
          SizedBox(width: 340, child: DropdownButtonFormField<String>(
            key: ValueKey('assessment-coverage-$_selectedCoverage-${assessments.length}'),
            initialValue: _selectedCoverage,
            isExpanded: true,
            decoration: _reportInputDecoration(context, '').copyWith(labelText: 'Report coverage'),
            items: coverageItems,
            onChanged: (value) {
              setState(() => _selectedCoverage = value ?? 'latest');
              _loadPreview();
            },
          )),
        ],
      ),
    );
  }

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

    final filtered = _candidateTeams.where((t) {
      if (!_teamMatchesContext(t)) return false;
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
                  Text(
                    'SELECT TEAM',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: DefensysTokens.textSecondaryOf(context),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${filtered.length} of ${_candidateTeams.length}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: DefensysTokens.textSecondaryOf(context)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: TextField(
                  controller: _selectorSearchController,
                  style: TextStyle(fontSize: 12, color: DefensysTokens.textPrimaryOf(context)),
                  decoration: InputDecoration(
                    hintText: 'Search team, project, leader...',
                    hintStyle: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context)),
                    prefixIcon: Icon(Icons.search_rounded, size: 16, color: DefensysTokens.textSecondaryOf(context)),
                    suffixIcon: _selectorSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, size: 14, color: DefensysTokens.textSecondaryOf(context)),
                            onPressed: () => _selectorSearchController.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: DefensysTokens.isDark(context) ? DefensysTokens.surfaceHigherOf(context) : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: BorderSide(color: DefensysTokens.maroonOf(context), width: 1.2),
                    ),
                  ),
                ),
              ),
              if (_candidateTeamSections.isNotEmpty) ...[
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
                      ..._candidateTeamSections.map((sec) {
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

        Divider(height: 1, color: DefensysTokens.borderOf(context)),

        // Selectable Teams List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No matching teams found.',
                      style: TextStyle(fontSize: 12.5, color: DefensysTokens.textSecondaryOf(context)),
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
                          setState(() {
                            _selectedTeamId = tId;
                            if (_selectedCoverage.startsWith('grade:')) _selectedCoverage = 'latest';
                            _previewData = null;
                            _availableAssessments = [];
                          });
                          _loadPreview();
                        },
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? DefensysTokens.maroonOf(context).withValues(alpha: 0.08)
                                : (DefensysTokens.isDark(context) ? DefensysTokens.surfaceHigherOf(context) : const Color(0xFFF8FAFC)),
                            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                            border: Border.all(
                              color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.borderOf(context),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.maroonOf(context).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.groups_rounded,
                                  color: isSelected ? Colors.white : DefensysTokens.maroonOf(context),
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
                                              color: DefensysTokens.textPrimaryOf(context),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.maroonOf(context).withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                            ),
                                            child: Text(
                                              '${_scopeLabel(_teamScope(t))}${sec.isEmpty ? '' : ' · $sec'}',
                                              style: TextStyle(
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.w700,
                                                color: isSelected ? Colors.white : DefensysTokens.maroonOf(context),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      projectTitle,
                                      style: TextStyle(fontSize: 11, color: DefensysTokens.textSecondaryOf(context)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      'Leader: $leaderName',
                                      style: TextStyle(fontSize: 10, color: DefensysTokens.textSecondaryOf(context)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.borderOf(context),
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

    final filtered = _candidateStudents.where((s) {
      final sId = s['id']?.toString() ?? '';
      final meta = _studentContext(sId);
      if (meta == null && (_selectedScope.isNotEmpty || _selectedSemesterId != null)) return false;

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
                  Text(
                    'SELECT STUDENT CANDIDATE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: DefensysTokens.textSecondaryOf(context),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${filtered.length} of ${_candidateStudents.length}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: DefensysTokens.textSecondaryOf(context)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: TextField(
                  controller: _selectorSearchController,
                  style: TextStyle(fontSize: 12, color: DefensysTokens.textPrimaryOf(context)),
                  decoration: InputDecoration(
                    hintText: 'Search by ID (e.g. 4011), name, team...',
                    hintStyle: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context)),
                    prefixIcon: Icon(Icons.search_rounded, size: 16, color: DefensysTokens.textSecondaryOf(context)),
                    suffixIcon: _selectorSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, size: 14, color: DefensysTokens.textSecondaryOf(context)),
                            onPressed: () => _selectorSearchController.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: DefensysTokens.isDark(context) ? DefensysTokens.surfaceHigherOf(context) : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: BorderSide(color: DefensysTokens.borderOf(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      borderSide: BorderSide(color: DefensysTokens.maroonOf(context), width: 1.2),
                    ),
                  ),
                ),
              ),
              if (_candidateStudentSections.isNotEmpty) ...[
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
                      ..._candidateStudentSections.map((sec) {
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

        Divider(height: 1, color: DefensysTokens.borderOf(context)),

        // Selectable Students List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No matching candidates found.',
                      style: TextStyle(fontSize: 12.5, color: DefensysTokens.textSecondaryOf(context)),
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
                    final meta = _studentContext(sId);
                    final name = s['name'] ?? s['username'] ?? 'Student';
                    final username = s['username']?.toString() ?? sId;
                    final team = meta?['team'] as Map<String, dynamic>?;
                    final isLeader = meta?['isLeader'] == true;
                    final isSelected = _selectedStudentId == sId;

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedStudentId = sId;
                            if (_selectedCoverage.startsWith('grade:')) _selectedCoverage = 'latest';
                            _previewData = null;
                            _availableAssessments = [];
                          });
                          _loadPreview();
                        },
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? DefensysTokens.maroonOf(context).withValues(alpha: 0.08)
                                : (DefensysTokens.isDark(context) ? DefensysTokens.surfaceHigherOf(context) : const Color(0xFFF8FAFC)),
                            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                            border: Border.all(
                              color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.borderOf(context),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.maroonOf(context).withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _extractInitials(name.toString()),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected ? Colors.white : DefensysTokens.maroonOf(context),
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
                                              color: DefensysTokens.textPrimaryOf(context),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: isSelected ? DefensysTokens.maroonOf(context) : (DefensysTokens.isDark(context) ? const Color(0xFF334155) : const Color(0xFF1E293B)),
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
                                              color: DefensysTokens.goldOf(context).withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                            ),
                                            child: Text(
                                              'LEAD',
                                              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: DefensysTokens.goldOf(context)),
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
                                              _studentContextLabel(sId),
                                              style: TextStyle(fontSize: 10.5, color: DefensysTokens.textSecondaryOf(context)),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ] else ...[
                                          Text('No Team Assigned', style: TextStyle(fontSize: 10.5, color: DefensysTokens.textSecondaryOf(context))),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.borderOf(context),
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
          Text(
            'EXPORT FILTERS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: DefensysTokens.textSecondaryOf(context),
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
              decoration: _reportInputDecoration(context, 'Choose semester...'),
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
              initialValue: _selectedScope,
              isExpanded: true,
              decoration: _reportInputDecoration(context, 'Filter scope...'),
              items: _restrictedPitLead ? const [
                DropdownMenuItem(value: 'pit', child: Text('PIT · assigned year', style: TextStyle(fontSize: 12.5))),
              ] : const [
                DropdownMenuItem(value: '', child: Text('All Records (Capstone & PIT)', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'capstone', child: Text('Capstone Only', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'pit', child: Text('PIT Only', style: TextStyle(fontSize: 12.5))),
              ],
              onChanged: _restrictedPitLead || widget.report['scope'] != null ? null : (val) {
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
                initialValue: _selectedStage,
                isExpanded: true,
                decoration: _reportInputDecoration(context, 'Select stage...'),
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
                initialValue: _selectedPitEvent,
                isExpanded: true,
                decoration: _reportInputDecoration(context, 'Select PIT event...'),
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
              decoration: _reportInputDecoration(context, 'Filter level...'),
              items: _restrictedPitLead ? const [
                DropdownMenuItem(value: 'pit', child: Text('PIT Teams', style: TextStyle(fontSize: 12.5))),
              ] : const [
                DropdownMenuItem(value: '', child: Text('All Program Levels', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'capstone', child: Text('Capstone Teams', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: 'pit', child: Text('PIT Teams', style: TextStyle(fontSize: 12.5))),
              ],
              onChanged: _restrictedPitLead ? null : (val) {
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
              decoration: _reportInputDecoration(context, 'Filter year level...'),
              items: _restrictedPitLead ? [
                DropdownMenuItem(value: _assignedYear, child: Text(_assignedYear.isEmpty ? 'No assigned year level' : _assignedYear,
                    style: const TextStyle(fontSize: 12.5))),
              ] : const [
                DropdownMenuItem(value: '', child: Text('All Year Levels', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: '1st Year', child: Text('1st Year', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: '2nd Year', child: Text('2nd Year', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: '3rd Year', child: Text('3rd Year', style: TextStyle(fontSize: 12.5))),
                DropdownMenuItem(value: '4th Year', child: Text('4th Year', style: TextStyle(fontSize: 12.5))),
              ],
              onChanged: _restrictedPitLead ? null : (val) {
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
              decoration: _reportInputDecoration(context, 'Choose role...'),
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
                    style: TextStyle(fontSize: 12.5, color: DefensysTokens.textPrimaryOf(context)),
                    decoration: _reportInputDecoration(context, 'Start Date').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(Icons.calendar_today_outlined, size: 16, color: DefensysTokens.textSecondaryOf(context)),
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
                    style: TextStyle(fontSize: 12.5, color: DefensysTokens.textPrimaryOf(context)),
                    decoration: _reportInputDecoration(context, 'End Date').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(Icons.calendar_today_outlined, size: 16, color: DefensysTokens.textSecondaryOf(context)),
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
              decoration: _reportInputDecoration(context, 'Filter category...'),
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
                foregroundColor: DefensysTokens.maroonOf(context),
                side: BorderSide(color: DefensysTokens.maroonOf(context).withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DefensysTokens.radiusMd)),
              ),
              onPressed: () {
                setState(() {
                  _selectedScope = _restrictedPitLead ? 'pit' : '';
                  _selectedLevel = _restrictedPitLead ? 'pit' : '';
                  _selectedYearLevel = _restrictedPitLead ? _assignedYear : '';
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
                  color: DefensysTokens.maroonOf(context).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person_search_rounded, size: 42, color: DefensysTokens.maroonOf(context)),
              ),
              const SizedBox(height: 16),
              Text(
                'Select a Student Candidate',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: DefensysTokens.textPrimaryOf(context)),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose a student candidate from the list on the left to preview individual grade breakdowns and peer multipliers.',
                style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context)),
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
                  color: DefensysTokens.maroonOf(context).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.groups_rounded, size: 42, color: DefensysTokens.maroonOf(context)),
              ),
              const SizedBox(height: 16),
              Text(
                'Select a Student Team',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: DefensysTokens.textPrimaryOf(context)),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose a team from the list on the left to preview evaluation criteria, panel scores, and member grades.',
                style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context)),
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
      selectedFormat: _selectedFormat,
    );
  }

  /// Modal Bottom Footer Bar with Format Chooser Pills + Action Buttons
  Widget _buildModalFooter() {
    return DefensysExportFormatBar(
      supportedFormats: const ['pdf', 'xlsx'],
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
            color: isSelected
                ? DefensysTokens.maroonOf(context)
                : (DefensysTokens.isDark(context) ? DefensysTokens.surfaceHigherOf(context) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
            border: Border.all(
              color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.borderOf(context),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormSectionLabel extends StatelessWidget {
  final String text;
  const _FormSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: DefensysTokens.textSecondaryOf(context),
        letterSpacing: 0.5,
      ),
    );
  }
}
