import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:defensys/navigation/admin_route_paths.dart';
import 'package:defensys/widgets/export/report_export_menu.dart';
import 'package:defensys/widgets/export/report_source_context.dart';
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
  Map<String, String> _reportQuery = {};
  bool _didReadReportContext = false;
  final _searchController = TextEditingController();
  Timer? _refreshTimer;
  final Set<int> _updatingReviews = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndFetchAudit(ref.read(authProvider));
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _selectedTabIndex != 0 || !TickerMode.of(context)) return;
      final auth = ref.read(authProvider);
      final user = auth.user;
      if (auth.isRestoring || user == null) return;
      if (user['role'] != 'admin' &&
          user['is_superuser'] != true &&
          user['is_pit_lead'] != true) {
        return;
      }
      if (!ref.read(systemAuditProvider).isLoading &&
          _updatingReviews.isEmpty) {
        ref.read(systemAuditProvider.notifier).fetch();
      }
    });
  }

  void _checkAndFetchAudit(AuthState authState) {
    if (authState.isRestoring) return;
    if (_didInitialFetch) return;

    final user = authState.user;
    final isAdmin =
        user?['role']?.toString() == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;
    final canViewAudit = isAdmin || isPitLead;

    _didInitialFetch = true;

    if (canViewAudit) {
      ref.read(systemAuditProvider.notifier).fetch();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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

    final success = await ref
        .read(reportsProvider.notifier)
        .downloadReport(
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
      if (auditState.reviewStatus.isNotEmpty)
        'review_status': auditState.reviewStatus,
      if (auditState.action.isNotEmpty) 'action': auditState.action,
      if (auditState.search.isNotEmpty) 'search': auditState.search,
      if (auditState.startDate.isNotEmpty) 'start_date': auditState.startDate,
      if (auditState.endDate.isNotEmpty) 'end_date': auditState.endDate,
      if (auditState.track.isNotEmpty) 'track': auditState.track,
      if (auditState.yearLevel.isNotEmpty) 'year_level': auditState.yearLevel,
    };

    final defaultFilename = 'DefenSYS_Audit_Register.$format';

    final success = await ref
        .read(reportsProvider.notifier)
        .downloadReport(
          endpoint: 'audit-trail/',
          queryParams: queryParams,
          defaultFilename: defaultFilename,
          exportFormat: format,
        );

    _showDownloadResultToast(success, format);
  }

  Future<void> _updateReviewStatus(
    Map<String, dynamic> log,
    String newStatus,
  ) async {
    final logId = log['id'] as int?;
    if (logId == null || _updatingReviews.contains(logId)) return;
    String? reason;
    if (newStatus != 'reviewed' && log['review_status'] == 'reviewed') {
      reason = await _askReopenReason();
      if (!mounted || reason == null) return;
    }

    _updatingReviews.add(logId);
    final success = await ref
        .read(systemAuditProvider.notifier)
        .updateReviewStatus(logId, newStatus, reason: reason);
    _updatingReviews.remove(logId);
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
        ref.read(systemAuditProvider).error ?? 'Failed to update review status',
      );
    }
  }

  Future<String?> _askReopenReason() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reopen audit review'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Explain what needs another review.',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a reason to reopen this review.'
                  : null,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Reopen review'),
          ),
        ],
      ),
    );
    // The dialog finishes its closing animation before releasing its controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    return result;
  }

  void _showDownloadResultToast(bool success, [String format = 'pdf']) {
    if (!mounted) return;
    final error = ref.read(reportsProvider).error;
    final fmtUpper = format.toUpperCase();
    if (success) {
      ToastService.success(
        context,
        '$fmtUpper downloaded successfully.',
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
    if (!_didReadReportContext) {
      _didReadReportContext = true;
      final router = GoRouter.maybeOf(context);
      if (router != null) {
        _reportQuery = GoRouterState.of(context).uri.queryParameters;
        if (_reportQuery['tab'] == 'reports') _selectedTabIndex = 1;
      }
    }
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (previous, next) {
      _checkAndFetchAudit(next);
    });

    ref.listen<DefensysAdminSection>(activeAdminSectionProvider, (
      previous,
      next,
    ) {
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
    final isAdmin =
        user?['role']?.toString() == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;
    final canViewAudit = isAdmin || isPitLead;

    if (!canViewAudit) {
      return SingleChildScrollView(
        padding: DefensysUi.contentPadding,
        child: AuditReportCenterTab(reportQuery: _reportQuery),
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
            AuditReportCenterTab(reportQuery: _reportQuery),
        ],
      ),
    );
  }

  Widget _buildAuditTrailWorkspace(BuildContext context) {
    final auditState = ref.watch(systemAuditProvider);
    final notifier = ref.read(systemAuditProvider.notifier);
    final user = ref.watch(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;

    final selectedLog =
        auditState.selectedLog ??
        (auditState.logs.isNotEmpty ? auditState.logs.first : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Header with Title, Subtitle, and Export Dropdown Menu
        AuditHeaderAndExport(
          onExportExcel: () => _exportAuditRegister(format: 'xlsx'),
          onExportPdf: () => _exportAuditRegister(format: 'pdf'),
          onOpenReportCenter: () {
            final params = reportSourceParams(ref, 'audit-trail')..removeWhere((key, value) => value.isEmpty);
            final router = GoRouter.maybeOf(context);
            if (router != null) {
              context.push(reportCenterLocation(admin: isAdmin, reportId: 'audit-trail', params: params, source: GoRouterState.of(context).uri.toString()));
            } else {
              setState(() { _selectedTabIndex = 1; _reportQuery = {'report': 'audit-trail', ...params}; });
            }
          },
        ),
        const SizedBox(height: 20),

        // 2. Four scope cards double as an overview and direct filter shortcuts.
        AuditKpiMetrics(
          state: auditState,
          isAdmin: isAdmin,
          onSelectScope: isAdmin
              ? (track, year) => notifier.setScope(track, yearLevel: year)
              : null,
          onRefresh: () => notifier.fetch(),
        ),
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
              lockedYear: isAdmin
                  ? null
                  : user?['pit_lead_year']?.toString() ?? '',
              onApply: (track, yearLevel) {
                notifier.setScope(track, yearLevel: yearLevel);
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
              onQuickReviewStatus: (log, status) =>
                  _updateReviewStatus(log, status),
            );

            final details = EventDetailsPanel(
              log: selectedLog,
              onUpdateReviewStatus: (log, status) =>
                  _updateReviewStatus(log, status),
              onExportPdf: (log) => _exportSingleLogPdf(log),
              onNavigateToResource: _navigateToResource,
            );

            if (!isWide) {
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
