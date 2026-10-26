import 'package:flutter/material.dart';
import '../../theme/defensys_tokens.dart';
import 'defensys_export_models.dart';

/// Shared format, signature and download controls for every report workspace.
class DefensysExportFormatBar extends StatelessWidget {
  const DefensysExportFormatBar({
    super.key,
    required this.supportedFormats,
    required this.selectedFormat,
    required this.onFormatChanged,
    required this.includeSignatures,
    required this.signatoriesCount,
    required this.onOpenSignatoryCustomizer,
    required this.isDownloading,
    required this.onCancel,
    required this.onDownload,
    this.allowSignatoryCustomization = true,
  });

  final List<String> supportedFormats;
  final String selectedFormat;
  final ValueChanged<String> onFormatChanged;
  final bool includeSignatures, isDownloading, allowSignatoryCustomization;
  final int signatoriesCount;
  final VoidCallback onOpenSignatoryCustomizer, onCancel, onDownload;

  @override
  Widget build(BuildContext context) {
    final secondary = DefensysTokens.textSecondaryOf(context);
    final formats = DefensysExportFormat.all.where(
      (format) => supportedFormats.contains(format.id),
    );
    final controls = <Widget>[
      Text(
        'FILE FORMAT:',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: secondary,
          letterSpacing: .5,
        ),
      ),
      ...formats.map(
        (format) => _pill(
          context,
          icon: format.icon,
          label: format.label,
          selected: selectedFormat.toLowerCase() == format.id,
          color: format.color,
          onTap: () => onFormatChanged(format.id),
        ),
      ),
      if (allowSignatoryCustomization)
        _pill(
          context,
          icon: includeSignatures
              ? Icons.history_edu_rounded
              : Icons.edit_off_outlined,
          label: includeSignatures
              ? 'Signatures ($signatoriesCount)'
              : 'Signatures (Off)',
          selected: includeSignatures,
          color: const Color(0xFFB45309),
          trailing: Icons.tune_rounded,
          onTap: onOpenSignatoryCustomizer,
        ),
    ];
    final actions = <Widget>[
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: DefensysTokens.textPrimaryOf(context),
          side: BorderSide(color: DefensysTokens.borderOf(context)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
          ),
        ),
        onPressed: isDownloading ? null : onCancel,
        child: const Text('Cancel', style: TextStyle(fontSize: 12)),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: DefensysTokens.maroonOf(context),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
          ),
        ),
        icon: isDownloading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.file_download_outlined, size: 16),
        label: Text(
          isDownloading
              ? 'Generating ${selectedFormat.toUpperCase()}...'
              : 'Download ${selectedFormat.toUpperCase()} Export',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        onPressed: isDownloading ? null : onDownload,
      ),
    ];
    return Container(
      key: const ValueKey('report-export-footer'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: DefensysTokens.isDark(context)
            ? DefensysTokens.surfaceHigherOf(context)
            : const Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: controls,
                  ),
                ),
                const SizedBox(width: 8),
                actions.first,
                const SizedBox(width: 8),
                actions.last,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: controls,
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _pill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
    IconData? trailing,
  }) {
    final foreground = selected
        ? color
        : DefensysTokens.textSecondaryOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: DefensysTokens.surfaceHigherOf(context),
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? DefensysTokens.surfaceHigherOf(context)
                : DefensysTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
            border: Border.all(
              color: selected ? color : DefensysTokens.borderOf(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: foreground,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                Icon(trailing, size: 12, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
