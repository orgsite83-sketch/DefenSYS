import 'package:flutter/material.dart';
import 'report_center_workspace.dart';

/// Stable entry point for the Report Center tab and existing route imports.
class AuditReportCenterTab extends StatelessWidget {
  const AuditReportCenterTab({super.key, this.reportQuery = const {}});
  final Map<String, String> reportQuery;

  @override
  Widget build(BuildContext context) =>
      ReportCenterWorkspace(reportQuery: reportQuery);
}
