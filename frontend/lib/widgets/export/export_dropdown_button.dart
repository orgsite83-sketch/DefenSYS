import 'package:flutter/material.dart';
import '../../theme/defensys_tokens.dart';

/// The same compact, neutral export control for audit and data pages.
class ExportDropdownButton extends StatelessWidget {
  const ExportDropdownButton({
    super.key,
    required this.onSelected,
    this.enabled = true,
    this.isLoading = false,
    this.tooltip = 'Export filtered records',
    this.reportCenterLabel = 'Report Center',
  });

  final ValueChanged<String> onSelected;
  final bool enabled;
  final bool isLoading;
  final String tooltip;
  final String reportCenterLabel;

  @override
  Widget build(BuildContext context) {
    final surface = DefensysTokens.surfaceOf(context);
    final foreground = DefensysTokens.textPrimaryOf(context);
    final border = DefensysTokens.borderOf(context);
    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: DefensysTokens.isDark(context)
            ? const Color(0xFF293342)
            : const Color(0xFFF4F4F5),
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
      ),
      child: PopupMenuButton<String>(
        enabled: enabled && !isLoading,
        tooltip: tooltip,
        offset: const Offset(0, 44),
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
          side: BorderSide(color: border),
        ),
        constraints: const BoxConstraints(minWidth: 168, maxWidth: 220),
        onSelected: onSelected,
        itemBuilder: (_) => [
          _item('xlsx', 'Export Excel', Icons.table_view_outlined, foreground),
          _item('pdf', 'Export PDF', Icons.picture_as_pdf_outlined, foreground),
          const PopupMenuDivider(height: 1),
          _item(
            'report_center',
            reportCenterLabel,
            Icons.summarize_outlined,
            foreground,
          ),
        ],
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
              border: Border.all(color: border),
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
                if (isLoading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                else
                  Icon(
                    Icons.file_download_outlined,
                    size: 16,
                    color: foreground,
                  ),
                const SizedBox(width: 7),
                Text(
                  isLoading ? 'Exporting…' : 'Export',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _item(
    String value,
    String label,
    IconData icon,
    Color foreground,
  ) => PopupMenuItem<String>(
    value: value,
    height: 40,
    child: Row(
      children: [
        Icon(icon, size: 16, color: foreground),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
          ),
        ),
      ],
    ),
  );
}
