import 'package:flutter/material.dart';
import '../../theme/defensys_tokens.dart';
import 'defensys_export_models.dart';

/// Reusable modal footer bar with format pills, signatory trigger, and action buttons.
class DefensysExportFormatBar extends StatelessWidget {
  final List<String> supportedFormats;
  final String selectedFormat;
  final ValueChanged<String> onFormatChanged;
  final bool includeSignatures;
  final int signatoriesCount;
  final VoidCallback onOpenSignatoryCustomizer;
  final bool isDownloading;
  final VoidCallback onCancel;
  final VoidCallback onDownload;

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
  });

  @override
  Widget build(BuildContext context) {
    final formats = DefensysExportFormat.all
        .where((f) => supportedFormats.contains(f.id))
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: DefensysTokens.border)),
      ),
      child: Row(
        children: [
          // Format Selector Label
          const Text(
            'FILE FORMAT:',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: DefensysTokens.steelGrey,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 10),

          // Format Selector Pills
          ...formats.map((fmt) {
            final isSelected = selectedFormat.toLowerCase() == fmt.id;

            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onFormatChanged(fmt.id),
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSelected ? fmt.color.withValues(alpha: 0.08) : Colors.white,
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                      border: Border.all(
                        color: isSelected ? fmt.color : const Color(0xFFCBD5E1),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          fmt.icon,
                          size: 14,
                          color: isSelected ? fmt.color : DefensysTokens.steelGrey,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          fmt.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected ? fmt.color : DefensysTokens.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          // Signatures Customizer Trigger Pill
          Container(
            height: 20,
            width: 1,
            color: const Color(0xFFCBD5E1),
            margin: const EdgeInsets.symmetric(horizontal: 10),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpenSignatoryCustomizer,
              borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: includeSignatures ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                  border: Border.all(
                    color: includeSignatures ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      includeSignatures ? Icons.history_edu_rounded : Icons.edit_off_outlined,
                      size: 14,
                      color: includeSignatures ? const Color(0xFFB45309) : DefensysTokens.steelGrey,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      includeSignatures ? 'Signatures ($signatoriesCount)' : 'Signatures (Off)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: includeSignatures ? const Color(0xFF92400E) : DefensysTokens.steelGrey,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.tune_rounded,
                      size: 12,
                      color: includeSignatures ? const Color(0xFFB45309) : DefensysTokens.steelGrey,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const Spacer(),

          // Cancel Button
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: DefensysTokens.textDark,
              side: const BorderSide(color: DefensysTokens.border),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DefensysTokens.radiusMd)),
            ),
            onPressed: isDownloading ? null : onCancel,
            child: const Text('Cancel', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),

          // Download Primary Action
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: DefensysTokens.maroon,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DefensysTokens.radiusMd)),
            ),
            icon: isDownloading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
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
        ],
      ),
    );
  }
}
