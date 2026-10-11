import 'package:flutter/material.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/export/export_dropdown_button.dart';

class AuditHeaderAndExport extends StatelessWidget {
  final VoidCallback onExportExcel;
  final VoidCallback onExportPdf;
  final VoidCallback onOpenReportCenter;

  const AuditHeaderAndExport({
    super.key,
    required this.onExportExcel,
    required this.onExportPdf,
    required this.onOpenReportCenter,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = DefensysTokens.isDark(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Title & Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Audit Trail',
                    style: TextStyle(
                      fontSize: isCompact ? 24 : 28,
                      fontWeight: FontWeight.w800,
                      color: DefensysTokens.textPrimaryOf(context),
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Review administrative activity and system changes.',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : DefensysTokens.steelGrey,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),

            ExportDropdownButton(
              tooltip: 'Export Options',
              reportCenterLabel: 'Report center',
              onSelected: (value) {
                switch (value) {
                  case 'xlsx':
                    onExportExcel();
                    break;
                  case 'pdf':
                    onExportPdf();
                    break;
                  case 'report_center':
                    onOpenReportCenter();
                    break;
                }
              },
            ),
          ],
        );
      },
    );
  }
}
