import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth_provider.dart';
import '../../services/reports_provider.dart';
import '../../toasts/feedback_toast.dart';
import 'report_catalog.dart';
import 'export_dropdown_button.dart';
import 'report_export_configuration.dart';
import 'report_source_context.dart';

String reportCenterLocation({
  required bool admin,
  required String reportId,
  required Map<String, String> params,
  required String source,
}) => Uri(
  path: admin ? '/admin/audit-compliance' : '/faculty/audit-compliance',
  queryParameters: {
    ...params,
    'tab': 'reports',
    'report': reportId,
    'source': source,
  },
).toString();

class ReportExportMenu extends ConsumerStatefulWidget {
  const ReportExportMenu({
    super.key,
    required this.reportId,
    this.params = const {},
    this.enabled = true,
    this.configureExport = false,
  });
  final String reportId;
  final Map<String, String> params;
  final bool enabled;

  /// Open advanced export settings here instead of navigating to Report Center.
  final bool configureExport;

  @override
  ConsumerState<ReportExportMenu> createState() => _ReportExportMenuState();
}

class _ReportExportMenuState extends ConsumerState<ReportExportMenu> {
  bool _downloading = false;

  Future<void> _select(String choice) async {
    final report = ReportCatalog.find(widget.reportId)!;
    final user = ref.read(authProvider).user;
    final params = {
      ...reportSourceParams(ref, widget.reportId),
      ...widget.params,
    };
    params.removeWhere(
      (key, value) =>
          value.isEmpty ||
          value == 'ALL' ||
          (value == 'all' && key != 'coverage' && key != 'term_context'),
    );
    if (report.scope.isNotEmpty) params['scope'] = report.scope;
    if (user?['is_pit_lead'] == true &&
        user?['role'] != 'admin' &&
        user?['is_superuser'] != true) {
      params['scope'] = 'pit';
      params['year_level'] = user?['pit_lead_year']?.toString() ?? '';
    }
    if (choice == 'report_center') {
      if (widget.configureExport) {
        await showReportExportConfiguration(
          context: context,
          ref: ref,
          report: report,
          params: params,
          initialFormat: 'xlsx',
        );
        return;
      }
      final source = GoRouterState.of(context).uri.toString();
      context.push(
        reportCenterLocation(
          admin: user?['role'] == 'admin' || user?['is_superuser'] == true,
          reportId: widget.reportId,
          params: params,
          source: source,
        ),
      );
      return;
    }
    if (report.missingSelection(params) != null) {
      await showReportExportConfiguration(
        context: context,
        ref: ref,
        report: report,
        params: params,
        initialFormat: choice,
      );
      return;
    }
    setState(() => _downloading = true);
    final success = await ref
        .read(reportsProvider.notifier)
        .downloadReport(
          endpoint: report.endpointFor(params),
          queryParams: params,
          defaultFilename:
              'DefenSYS_${report.id}_${DateTime.now().toIso8601String().substring(0, 10)}.${choice == 'xlsx' ? 'xlsx' : 'pdf'}',
          exportFormat: choice,
        );
    if (!mounted) return;
    setState(() => _downloading = false);
    if (success) {
      showSuccessToast(
        context,
        '${choice == 'xlsx' ? 'Excel' : 'PDF'} exported.',
      );
    } else {
      showErrorToast(
        context,
        ref.read(reportsProvider).error ?? 'Unable to export report.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ReportCatalog.visible(
      ref.watch(authProvider).user,
    ).any((report) => report.id == widget.reportId)) {
      return const SizedBox.shrink();
    }
    return ExportDropdownButton(
      enabled: widget.enabled,
      isLoading: _downloading,
      reportCenterLabel: widget.configureExport
          ? 'Configure export'
          : 'Report Center',
      onSelected: _select,
    );
  }
}
