import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_action_menu.dart';

class AuditHeaderAndExport extends StatelessWidget {
  final VoidCallback onExportExcel;
  final VoidCallback onExportPdf;
  final VoidCallback onOpenReportCenter;
  final VoidCallback onRefresh;
  final bool isRefreshing;

  const AuditHeaderAndExport({
    super.key,
    required this.onExportExcel,
    required this.onExportPdf,
    required this.onOpenReportCenter,
    required this.onRefresh,
    this.isRefreshing = false,
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
                    'Logs',
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: isCompact ? 24 : 28,
                      fontWeight: FontWeight.w800,
                      color: DefensysTokens.textPrimaryOf(context),
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Recorded activity and system changes.',
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
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

            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Tooltip(
                  message: 'Refresh logs',
                  child: ShadButton.ghost(
                    onPressed: isRefreshing ? null : onRefresh,
                    width: 36,
                    height: 36,
                    padding: EdgeInsets.zero,
                    child: const Icon(Icons.refresh_rounded, size: 18),
                  ),
                ),
                DefensysActionMenu(
                  label: 'Export Options',
                  triggerLabel: 'Export',
                  triggerIcon: Icons.keyboard_arrow_down_rounded,
                  items: [
                    DefensysMenuItem(
                      label: 'Export Excel',
                      icon: Icons.table_view_outlined,
                      onPressed: onExportExcel,
                    ),
                    DefensysMenuItem(
                      label: 'Export PDF',
                      icon: Icons.picture_as_pdf_outlined,
                      onPressed: onExportPdf,
                    ),
                    DefensysMenuItem(
                      label: 'Report Center',
                      icon: Icons.summarize_outlined,
                      onPressed: onOpenReportCenter,
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
