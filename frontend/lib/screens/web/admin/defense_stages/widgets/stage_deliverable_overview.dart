import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';

Future<bool> confirmRemoveStageDeliverables(
  BuildContext context,
  int count,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Remove student file requirements?'),
          content: Text(
            'Presentation / Demo Only does not use student file uploads. '
            'Saving this stage will remove $count configured '
            '${count == 1 ? 'deliverable' : 'deliverables'}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep requirements'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Use presentation only'),
            ),
          ],
        ),
      ) ??
      false;
}

class StageDeliverableCounts extends StatelessWidget {
  const StageDeliverableCounts({
    super.key,
    required this.deliverables,
    required this.minutesRequired,
  });

  final List<Map<String, dynamic>> deliverables;
  final bool minutesRequired;

  @override
  Widget build(BuildContext context) {
    final scheduling = deliverables
        .where(
          (item) =>
              item['deliverable_type'] == 'pre' &&
              item['requirement_timing'] != 'defense',
        )
        .length;
    final defense = deliverables
        .where(
          (item) =>
              item['deliverable_type'] == 'pre' &&
              item['requirement_timing'] == 'defense',
        )
        .length;
    final post = deliverables
        .where((item) => item['deliverable_type'] == 'post')
        .length;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _count(theme, 'Before endorsement', scheduling),
          _count(theme, 'Before defense', defense),
          _count(theme, 'After defense', post),
          if (minutesRequired) _count(theme, 'Signed minutes', 1),
        ],
      ),
    );
  }

  Widget _count(ThemeData theme, String label, int count) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: theme.dividerColor),
    ),
    child: Text(
      '$label: $count',
      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

/// A compact view of the configured files. The editor is supplied by the
/// caller so creation and editing keep their existing save and draft flows.
class StageDeliverableOverview extends StatelessWidget {
  const StageDeliverableOverview({
    super.key,
    required this.items,
    required this.isPost,
    required this.selectedItem,
    required this.onSelect,
    required this.buildEditor,
  });

  final List<Map<String, dynamic>> items;
  final bool isPost;
  final Map<String, dynamic>? selectedItem;
  final ValueChanged<Map<String, dynamic>?> onSelect;
  final Widget Function(Map<String, dynamic> item, int index) buildEditor;

  @override
  Widget build(BuildContext context) {
    final groups = isPost
        ? <(String, List<Map<String, dynamic>>)>[('After defense', items)]
        : <(String, List<Map<String, dynamic>>)>[
            (
              'Before endorsement / scheduling',
              items
                  .where((item) => item['requirement_timing'] != 'defense')
                  .toList(),
            ),
            (
              'Before scheduled defense',
              items
                  .where((item) => item['requirement_timing'] == 'defense')
                  .toList(),
            ),
          ];
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (title, groupItems) in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
            child: Text(
              '$title (${groupItems.length})',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (groupItems.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
              child: Text(
                isPost ? 'No archive files yet.' : 'No files in this group.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final item in groupItems) ...[
            if (identical(item, selectedItem)) ...[
              buildEditor(item, items.indexOf(item) + 1),
              Align(
                alignment: Alignment.centerRight,
                child: DefensysShadcnScope(
                  child: ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    onPressed: () => onSelect(null),
                    child: const Text('Done editing'),
                  ),
                ),
              ),
            ] else
              _DeliverableSummaryRow(
                key: ObjectKey(item),
                item: item,
                isPost: isPost,
                onTap: () => onSelect(item),
              ),
          ],
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _DeliverableSummaryRow extends StatelessWidget {
  const _DeliverableSummaryRow({
    super.key,
    required this.item,
    required this.isPost,
    required this.onTap,
  });

  final Map<String, dynamic> item;
  final bool isPost;
  final VoidCallback onTap;

  String get _format {
    return switch (item['file_format']?.toString() ?? 'any') {
      'pdf' => 'PDF',
      'video' => 'Video',
      'image' => 'Image',
      'presentation' => 'Slides',
      'document' => 'Word document',
      'spreadsheet' => 'Spreadsheet',
      'archive' => 'Archive',
      'audio' => 'Audio',
      _ => 'Any file type',
    };
  }

  String get _summary {
    final parts = <String>[
      _format,
      item['required'] == true ? 'Required' : 'Optional',
    ];
    if (!isPost && item['requirement_timing'] == 'defense') {
      final hours =
          int.tryParse(item['deadline_hours_before']?.toString() ?? '') ?? 24;
      parts.add(
        hours == 0 ? 'At defense start' : '$hours hours before defense',
      );
    }
    if (!isPost && item['is_defense_material'] == true) {
      parts.add('Panelist material');
    }
    if (isPost && item['verdict_condition'] == 'revisions_only') {
      parts.add('Approved with revisions only');
    }
    if (isPost && item['is_restricted'] == true) {
      parts.add('Restricted archive');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final name = item['label']?.toString().trim() ?? '';
    return StageCompactRecordRow(
      title: name.isEmpty ? 'Untitled deliverable' : name,
      summary: _summary,
      icon: isPost ? Icons.inventory_2_outlined : Icons.description_outlined,
      onTap: onTap,
    );
  }
}

/// Shared compact row for student files and system-generated records.
class StageCompactRecordRow extends StatelessWidget {
  const StageCompactRecordRow({
    super.key,
    required this.title,
    required this.summary,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String summary;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: theme.dividerColor),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Edit',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
