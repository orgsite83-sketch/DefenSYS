import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';

class StageDeliverableSectionHeader extends StatelessWidget {
  const StageDeliverableSectionHeader({
    super.key,
    required this.heading,
    this.action,
  });

  final Widget heading;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 600) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: heading),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      );
    },
  );
}

class StageDeliverableGroupHeader extends StatelessWidget {
  const StageDeliverableGroupHeader({
    super.key,
    required this.title,
    required this.description,
    required this.count,
    required this.addLabel,
    required this.onAdd,
    this.showAdd = true,
  });

  final String title;
  final String description;
  final int count;
  final String addLabel;
  final VoidCallback? onAdd;
  final bool showAdd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: StageDeliverableSectionHeader(
      heading: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              Text(
                '($count)',
                style: TextStyle(
                  fontSize: 13,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ),
      action: showAdd
          ? DefensysShadcnScope(
              child: ShadButton.outline(
                size: ShadButtonSize.sm,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                onPressed: onAdd,
                leading: const Icon(Icons.add, size: 14),
                child: Text(addLabel, style: const TextStyle(fontSize: 12)),
              ),
            )
          : null,
    ),
  );
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
    final pre = deliverables
        .where((item) => item['deliverable_type'] == 'pre')
        .length;
    final post = deliverables
        .where((item) => item['deliverable_type'] == 'post')
        .length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _count(context, 'Pre-defense', pre),
          _count(context, 'Post-defense', post),
          if (minutesRequired) _count(context, 'Signed minutes', 1),
        ],
      ),
    );
  }

  Widget _count(BuildContext context, String label, int count) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceOf(context),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: DefensysTokens.borderOf(context)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x06000000),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
      ],
    ),
    child: Text(
      '$label: $count',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: DefensysTokens.textSecondaryOf(context),
      ),
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
    this.showDoneEditingButton = true,
    this.showGroupHeading = true,
    this.showReviewHint = true,
    this.emptyText,
  });

  final List<Map<String, dynamic>> items;
  final bool isPost;
  final Map<String, dynamic>? selectedItem;
  final ValueChanged<Map<String, dynamic>?> onSelect;
  final Widget Function(Map<String, dynamic> item, int index) buildEditor;
  final bool showDoneEditingButton;
  final bool showGroupHeading;
  final bool showReviewHint;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final groups = <(String, List<Map<String, dynamic>>)>[
      (isPost ? 'Post-defense files' : 'Pre-defense files', items),
    ];
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (title, groupItems) in groups) ...[
          if (showGroupHeading)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
              child: Text(
                '$title (${groupItems.length})',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: DefensysTokens.textSecondaryOf(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (showReviewHint && !isPost && groupItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
              child: Text(
                'Required files need faculty acceptance before endorsement and scheduling.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ),
          if (groupItems.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
              child: Text(
                emptyText ??
                    (isPost
                        ? 'No archive files yet.'
                        : 'No files in this group.'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ),
          for (final item in groupItems) ...[
            if (identical(item, selectedItem)) ...[
              buildEditor(item, items.indexOf(item) + 1),
              if (showDoneEditingButton)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: DefensysShadcnScope(
                      child: ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: () => onSelect(null),
                        leading: const Icon(Icons.check_rounded, size: 14),
                        child: const Text('Done editing'),
                      ),
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
    if (!isPost && item['is_defense_material'] == true) {
      parts.add('Panelist material');
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
      readOnly: item['is_locked'] == true || item['has_data'] == true,
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
    this.readOnly = false,
  });

  final String title;
  final String summary;
  final IconData icon;
  final VoidCallback onTap;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: DefensysTokens.surfaceOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: DefensysTokens.backgroundOf(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  readOnly ? 'View' : 'Edit',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
