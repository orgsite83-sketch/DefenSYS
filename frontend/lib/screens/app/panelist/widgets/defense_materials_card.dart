import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../theme/defensys_tokens.dart';

class DefenseMaterialsCard extends StatelessWidget {
  const DefenseMaterialsCard({
    super.key,
    required this.materials,
    required this.onView,
  });
  final List<Map<String, dynamic>> materials;
  final ValueChanged<Map<String, dynamic>> onView;

  Widget _file(BuildContext context, Map<String, dynamic> material) {
    final submission = material['submission'] is Map
        ? material['submission'] as Map
        : null;
    final label =
        (material['label']?.toString().isNotEmpty == true
                ? material['label']
                : material['name'])
            ?.toString() ??
        'Defense material';
    final explicit = material['file_name']?.toString() ?? '';
    final fileName = explicit.isNotEmpty && explicit != 'File'
        ? explicit
        : submission?['file_name']?.toString() ??
              material['suggested_file_name']?.toString() ??
              'File';
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : '';
    final icon = extension == 'PDF'
        ? Icons.picture_as_pdf_outlined
        : Icons.description_outlined;
    final accent = DefensysTokens.maroonOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: DefensysTokens.maroonTextOf(context),
                ),
                if (extension.isNotEmpty && extension.length <= 4) ...[
                  const SizedBox(height: 3),
                  Text(
                    extension,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.maroonTextOf(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Tooltip(
                  message: fileName,
                  child: Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'View $label',
            child: ShadButton.outline(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: () => onView(material),
              child: const Text('View', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ShadCard(
    backgroundColor: DefensysTokens.surfaceOf(context),
    radius: BorderRadius.circular(16),
    border: ShadBorder.all(
      color: DefensysTokens.borderOf(context),
      radius: BorderRadius.circular(16),
    ),
    shadows: const [],
    padding: const EdgeInsets.all(18),
    width: double.infinity,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Defense materials',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manuscripts & presentation files',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ShadBadge.outline(
              child: Text(
                '${materials.length} ${materials.length == 1 ? 'file' : 'files'}',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
        if (materials.isEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                Icons.folder_open_outlined,
                size: 21,
                color: DefensysTokens.textSecondaryOf(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No materials uploaded yet.',
                  style: TextStyle(
                    fontSize: 12,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          for (final material in materials) _file(context, material),
        ],
      ],
    ),
  );
}
