import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/repository_library.dart';
import '../../models/library_filters.dart';
import '../../theme/defensys_tokens.dart';
import '../../theme/program_colors.dart';
import '../defensys_skeleton.dart';
import '../shadcn/defensys_shadcn_scope.dart';
export 'library_filter_panel.dart';

Future<T?> showLibraryPanel<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  bool desktopDialog = false,
}) {
  final desktop = desktopDialog && MediaQuery.sizeOf(context).width >= 760;
  Widget frame(BuildContext context) {
    final media = MediaQuery.of(context);
    final height =
        ((media.size.height - media.viewInsets.bottom - media.padding.top) * .9)
            .clamp(260.0, 760.0);
    return DefensysShadcnScope(
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              desktop ? 28 : 20,
              desktop ? 20 : 12,
              desktop ? 28 : 20,
              20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!desktop) ...[
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: DefensysTokens.borderOf(context),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: DefensysTokens.dialogTitle.copyWith(
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Close panel',
                      child: ShadButton.ghost(
                        width: 44,
                        height: 44,
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context),
                        child: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(child: Builder(builder: builder)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  if (desktop) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: DefensysTokens.surfaceOf(context),
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: frame(context),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    backgroundColor: DefensysTokens.surfaceOf(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: frame(context),
    ),
  );
}

class LibraryCollectionCard extends StatelessWidget {
  const LibraryCollectionCard({
    super.key,
    required this.type,
    required this.count,
    required this.onTap,
  });
  final String type;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final program = ProgramColors.of(context, scope: type);
    final title = type == 'capstone' ? 'Capstone' : 'PIT projects';
    return Semantics(
      button: true,
      label: 'Browse $title collection',
      child: Material(
        color: DefensysTokens.surfaceOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // A small group of book spines marks a research collection.
                    for (var index = 0; index < 3; index++)
                      Transform.rotate(
                        angle: index == 2 ? -.16 : 0,
                        child: Container(
                          width: 7,
                          height: 22 + index * 2,
                          margin: const EdgeInsets.only(right: 3),
                          decoration: BoxDecoration(
                            color: program.text.withValues(
                              alpha: .55 + index * .2,
                            ),
                            borderRadius: BorderRadius.circular(1),
                          ),
                          child: Align(
                            alignment: const Alignment(0, -.5),
                            child: Container(height: 1, color: program.tint),
                          ),
                        ),
                      ),
                    const Spacer(),
                    Icon(Icons.north_east, size: 16, color: program.text),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: DefensysTokens.body.copyWith(
                    color: DefensysTokens.textPrimaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  count == null
                      ? 'Explore research'
                      : '$count ${count == 1 ? 'project' : 'projects'}',
                  style: DefensysTokens.caption.copyWith(
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LibraryShelfDirectory extends StatelessWidget {
  const LibraryShelfDirectory({
    super.key,
    required this.entries,
    required this.onSelected,
    this.availableOnly = false,
  });
  final List<VaultEntry> entries;
  final ValueChanged<LibraryBrowse> onSelected;
  final bool availableOnly;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final shelf in LibraryBrowse.values.where(
        (shelf) => !availableOnly || entries.any(shelf.matches),
      )) ...[
        Divider(height: 1, color: DefensysTokens.borderOf(context)),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 5,
          ),
          leading: Icon(switch (shelf) {
            LibraryBrowse.projects => Icons.local_library_outlined,
            LibraryBrowse.posters => Icons.image_outlined,
            LibraryBrowse.videos => Icons.smart_display_outlined,
            LibraryBrowse.other => Icons.inventory_2_outlined,
            _ => Icons.menu_book_outlined,
          }, color: DefensysTokens.maroonTextOf(context)),
          title: Text(
            shelf.label,
            style: DefensysTokens.body.copyWith(
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          subtitle: Text(
            _count(shelf),
            style: DefensysTokens.caption.copyWith(
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => onSelected(shelf),
        ),
      ],
    ],
  );

  String _count(LibraryBrowse shelf) {
    final matches = entries.where(shelf.matches).toList();
    if (shelf == LibraryBrowse.projects) {
      final count = LibraryProject.group(matches).length;
      return '$count ${count == 1 ? 'project' : 'projects'}';
    }
    return '${matches.length} ${matches.length == 1 ? 'output' : 'outputs'}';
  }
}

class LibraryActiveFilters extends StatelessWidget {
  const LibraryActiveFilters({
    super.key,
    required this.selection,
    required this.entries,
    required this.onChanged,
  });
  final LibraryFilterSelection selection;
  final List<VaultEntry> entries;
  final ValueChanged<LibraryFilterSelection> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      if (selection.year.isNotEmpty)
        InputChip(
          label: Text('SY ${selection.year}'),
          onDeleted: () => onChanged(selection.copyWith(year: '')),
        ),
      for (final group in LibraryFilterGroup.values)
        for (final id in selection.values(group))
          InputChip(
            label: Text(selection.label(group, id, entries)),
            onDeleted: () => onChanged(selection.remove(group, id)),
          ),
      if (!selection.isEmpty)
        ShadButton.ghost(
          height: 36,
          onPressed: () => onChanged(const LibraryFilterSelection()),
          child: const Text('Clear filters', style: TextStyle(fontSize: 12)),
        ),
    ],
  );
}

class LibraryProjectTags extends StatelessWidget {
  const LibraryProjectTags({super.key, required this.entry});
  final VaultEntry entry;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final group in LibraryFilterGroup.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.label,
                style: DefensysTokens.caption.copyWith(
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                (entry.libraryTags[group.name] ?? []).isEmpty
                    ? 'Not specified'
                    : entry.libraryTags[group.name]!
                          .map(
                            (tag) =>
                                '${tag.label}${tag.status == 'proposed' ? ' (proposed)' : ''}',
                          )
                          .join(' · '),
                style: DefensysTokens.body.copyWith(
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class LibraryShelfLoading extends StatelessWidget {
  const LibraryShelfLoading({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading research collection',
    child: Row(
      children: [
        for (var index = 0; index < 2; index++) ...[
          if (index > 0) const SizedBox(width: 14),
          Expanded(
            child: AspectRatio(
              aspectRatio: .76,
              child: DefensysSkeleton.box(
                height: double.infinity,
                borderRadius: 4,
                color: DefensysTokens.surfaceHigherOf(context),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
