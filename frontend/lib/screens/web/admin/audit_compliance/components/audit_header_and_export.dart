import 'package:flutter/material.dart';
import 'package:defensys/theme/defensys_tokens.dart';

class AuditHeaderAndExport extends StatelessWidget {
  final VoidCallback onExportCurrentView;
  final VoidCallback onExportCsv;
  final VoidCallback onExportPdf;
  final VoidCallback onOpenReportCenter;

  const AuditHeaderAndExport({
    super.key,
    required this.onExportCurrentView,
    required this.onExportCsv,
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
                      color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),

            // Shadcn-style Export Dropdown Button
            PopupMenuButton<String>(
              tooltip: 'Export Options',
              offset: const Offset(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                side: BorderSide(color: DefensysTokens.borderOf(context)),
              ),
              color: DefensysTokens.surfaceOf(context),
              elevation: 4,
              onSelected: (val) {
                switch (val) {
                  case 'current':
                    onExportCurrentView();
                    break;
                  case 'csv':
                    onExportCsv();
                    break;
                  case 'pdf':
                    onExportPdf();
                    break;
                  case 'report_center':
                    onOpenReportCenter();
                    break;
                }
              },
              itemBuilder: (context) => [
                _buildMenuItem(
                  context,
                  value: 'current',
                  icon: Icons.file_download_outlined,
                  label: 'Export current view',
                ),
                _buildMenuItem(
                  context,
                  value: 'csv',
                  icon: Icons.table_chart_outlined,
                  label: 'Export CSV',
                ),
                _buildMenuItem(
                  context,
                  value: 'pdf',
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'Export PDF',
                ),
                const PopupMenuDivider(height: 1),
                _buildMenuItem(
                  context,
                  value: 'report_center',
                  icon: Icons.summarize_outlined,
                  label: 'Report center',
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: DefensysTokens.surfaceOf(context),
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                  border: Border.all(color: DefensysTokens.borderOf(context)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x06000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.file_download_outlined,
                      size: 16,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Export',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: isDark ? const Color(0xFF94A3B8) : DefensysTokens.steelGrey,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  PopupMenuItem<String> _buildMenuItem(
    BuildContext context, {
    required String value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: DefensysTokens.textPrimaryOf(context),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}
