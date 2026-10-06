import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/services/admin/system_audit_provider.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/reports_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/widgets/table/defensys_segmented_control.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/screens/web/admin/admin_shell.dart';

import 'components/audit_header_and_export.dart';
import 'components/audit_kpi_metrics.dart';
import 'components/audit_filter_toolbar.dart';
import 'components/audit_status_tabs.dart';
import 'components/audit_trail_table.dart';
import 'components/event_details_panel.dart';
import 'components/audit_report_center_tab.dart';
import 'dialogs/audit_date_range_dialog.dart';
import 'dialogs/audit_more_filters_dialog.dart';

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
    final canViewAudit = isAdmin || isPitLead;

    _didInitialFetch = true;

    if (canViewAudit) {
      ref.read(systemAuditProvider.notifier).fetch();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _exportAuditRegister({String format = 'pdf'}) async {
    final auditState = ref.read(systemAuditProvider);
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

  Future<void> _updateReviewStatus(Map<String, dynamic> log, String newStatus) async {
    final logId = log['id'] as int?;
    if (logId == null) return;

    final success = await ref.read(systemAuditProvider.notifier).updateReviewStatus(logId, newStatus);
    if (!mounted) return;

    if (success) {
      ToastService.success(
        context,
        newStatus == 'reviewed'
            ? 'Event #$logId marked as reviewed'
            : 'Event #$logId reopened for review',
      );
    } else {
      ToastService.error(
        context,
        'Failed to update review status',
      );
    }
  }

  void _showDownloadResultToast(bool success, [String format = 'pdf']) {
    if (!mounted) return;
    final error = ref.read(reportsProvider).error;
    final fmtUpper = format.toUpperCase();
    if (success) {
      ToastService.success(
        context,
        '$fmtUpper exported and downloaded successfully!',
      );
    } else {
      ToastService.error(
        context,
        'Failed to generate $fmtUpper: ${error ?? "Unknown error"}',
      );
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
      return const SingleChildScrollView(
        padding: DefensysUi.contentPadding,
        child: AuditReportCenterTab(),
      );
    }

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Portal-consistent Tab Switcher
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
          const SizedBox(height: 18),

          if (_selectedTabIndex == 0)
            _buildAuditTrailWorkspace(context)
          else
            const AuditReportCenterTab(),
        ],
      ),
    );
  }

  Widget _buildAuditTrailWorkspace(BuildContext context) {
    final auditState = ref.watch(systemAuditProvider);
    final notifier = ref.read(systemAuditProvider.notifier);

    final selectedLog = auditState.selectedLog ??
        (auditState.logs.isNotEmpty ? auditState.logs.first : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Header with Title, Subtitle, and Export Dropdown Menu
        AuditHeaderAndExport(
          onExportCurrentView: () => _exportAuditRegister(format: 'pdf'),
          onExportCsv: () => _exportAuditRegister(format: 'csv'),
          onExportPdf: () => _exportAuditRegister(format: 'pdf'),
          onOpenReportCenter: () {
            setState(() => _selectedTabIndex = 1);
          },
        ),
        const SizedBox(height: 20),

        // 2. Shadcn-style 4 KPI Metrics Strip
        AuditKpiMetrics(state: auditState),
        const SizedBox(height: 18),

        // 3. Search and Filters Toolbar
        AuditFilterToolbar(
          state: auditState,
          searchController: _searchController,
          onSearchSubmitted: (query) {
            notifier.setSearch(query.trim());
            notifier.fetch();
          },
          onCategoryChanged: (cat) => notifier.setCategory(cat),
          onActionChanged: (act) => notifier.setAction(act),
          onSelectDateRange: () {
            AuditDateRangeDialog.show(
              context,
              initialStartDate: auditState.startDate,
              initialEndDate: auditState.endDate,
              onApply: (start, end) {
                notifier.setStartDate(start);
                notifier.setEndDate(end);
                notifier.fetch();
              },
            );
          },
          onOpenMoreFilters: () {
            AuditMoreFiltersDialog.show(
              context,
              currentTrack: auditState.track,
              currentYearLevel: auditState.yearLevel,
              onApply: (track, yearLevel) {
                notifier.setTrack(track);
                notifier.setYearLevel(yearLevel);
              },
            );
          },
        ),
        const SizedBox(height: 16),

        // 4. Status Tab Ribbon (All Events, Needs Review, Reviewed)
        AuditStatusTabs(
          state: auditState,
          onStatusSelected: (status) => notifier.setReviewStatus(status),
        ),
        const SizedBox(height: 14),

        // 5. Master-Detail Workspace: Table & Event Details Panel
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1100;

            final table = AuditTrailTable(
              state: auditState,
              onSelectLog: (log) => notifier.selectLog(log),
              onPageChanged: (page) => notifier.setPage(page),
              onPageSizeChanged: (size) => notifier.setPageSize(size),
              onQuickReviewStatus: (log, status) => _updateReviewStatus(log, status),
            );

            final details = EventDetailsPanel(
              log: selectedLog,
              onUpdateReviewStatus: (log, status) => _updateReviewStatus(log, status),
              onExportPdf: (log) => _exportSingleLogPdf(log),
              onNavigateToResource: _navigateToResource,
            );

            if (!isWide) {
              return Column(
                children: [
                  table,
                  const SizedBox(height: 16),
                  details,
                ],
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
    return DefensysSegmentedControl<int>(
      value: selectedIndex,
      items: const [
        DefensysSegmentItem(
          value: 0,
          label: 'Audit Trail',
          badgeLabel: 'Live Logs',
          icon: Icons.receipt_long_outlined,
        ),
        DefensysSegmentItem(
          value: 1,
          label: 'Report Center',
          badgeLabel: 'PDF Center',
          icon: Icons.summarize_outlined,
        ),
      ],
      onChanged: onTabSelected,
    );
  }
}
