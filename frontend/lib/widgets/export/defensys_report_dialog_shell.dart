import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/defensys_tokens.dart';

/// Shared report workspace for the catalog and assessment exports.
class DefensysReportDialogShell extends StatelessWidget {
  const DefensysReportDialogShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tag,
    required this.filters,
    required this.preview,
    required this.footer,
    required this.onClose,
    this.controls,
    this.filterPaneWidth = 380,
  });

  final String title, subtitle, tag;
  final IconData icon;
  final Widget filters, preview, footer;
  final Widget? controls;
  final VoidCallback onClose;
  final double filterPaneWidth;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: DefensysTokens.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: SizedBox(
        width: math.min(1120, math.max(0, size.width - 48)),
        height: math.min(size.height * .90, math.max(0, size.height - 40)),
        child: Column(
          children: [
            _header(context),
            if (controls != null) controls!,
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 760) {
                    return DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          TabBar(
                            labelColor: DefensysTokens.maroonOf(context),
                            indicatorColor: DefensysTokens.maroonOf(context),
                            tabs: const [
                              Tab(text: 'Filters'),
                              Tab(text: 'Preview'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(children: [filters, preview]),
                          ),
                        ],
                      ),
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: math.min(
                          filterPaneWidth,
                          constraints.maxWidth * .40,
                        ),
                        child: filters,
                      ),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: DefensysTokens.borderOf(context),
                      ),
                      Expanded(child: preview),
                    ],
                  );
                },
              ),
            ),
            footer,
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final maroon = DefensysTokens.maroonOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 20, 16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: maroon, width: 4),
          bottom: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: maroon.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            ),
            child: Icon(icon, color: maroon, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Tooltip(
                        message: title,
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: maroon.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(
                          DefensysTokens.radiusSm,
                        ),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: maroon,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close report',
            onPressed: onClose,
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}
