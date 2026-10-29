import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../theme/defensys_tokens.dart';

class DefenseMaterialsCard extends StatelessWidget {
  const DefenseMaterialsCard({
    super.key,
    required this.materials,
    required this.onView,
    this.embedded = false,
    this.flat = false,
    this.title = 'Defense materials',
    this.emptyLabel = 'No materials uploaded yet.',
  });
  final List<Map<String, dynamic>> materials;
  final ValueChanged<Map<String, dynamic>> onView;
  final bool embedded, flat;
  final String title, emptyLabel;
  int get fileCount => materials.where((row) => row['missing'] != true).length;

  Widget _file(BuildContext context, Map<String, dynamic> material) {
    final missing = material['missing'] == true;
    final submission = material['submission'] is Map
        ? material['submission'] as Map
        : null;
    final label =
        (material['requirement_label'] ??
                material['label'] ??
                material['name'] ??
                'Defense material')
            .toString();
    final explicit = material['file_name']?.toString() ?? '';
    final fileName = missing
        ? 'Not uploaded'
        : explicit.isNotEmpty && explicit != 'File'
        ? explicit
        : submission?['file_name']?.toString() ??
              material['suggested_file_name']?.toString() ??
              'File';
    final extension = !missing && fileName.contains('.')
        ? fileName.split('.').last.toUpperCase()
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 40,
            decoration: BoxDecoration(
              color: DefensysTokens.surfaceHigherOf(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              extension == 'PDF'
                  ? Icons.picture_as_pdf_outlined
                  : Icons.description_outlined,
              size: 19,
              color: DefensysTokens.maroonTextOf(context),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    fileName,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.45,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'View $label, $fileName',
            child: ShadButton.outline(
              height: 44,
              enabled: !missing,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: () => onView(material),
              child: const Text('View', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!embedded) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$fileCount ${fileCount == 1 ? 'file' : 'files'}',
              style: TextStyle(
                fontSize: 11,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
      if (materials.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            emptyLabel,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ),
      for (final (index, material) in materials.indexed) ...[
        if (index > 0)
          Divider(height: 1, color: DefensysTokens.borderOf(context)),
        _file(context, material),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => embedded || flat
      ? _content(context)
      : ShadCard(
          backgroundColor: DefensysTokens.surfaceOf(context),
          radius: BorderRadius.circular(16),
          border: ShadBorder.all(
            color: DefensysTokens.borderOf(context),
            radius: BorderRadius.circular(16),
          ),
          shadows: const [],
          padding: const EdgeInsets.all(18),
          width: double.infinity,
          child: _content(context),
        );
}
