import 'package:defensys/theme/program_colors.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/repository_library.dart';
import '../../theme/defensys_tokens.dart';
import 'library_media_preview.dart';

IconData libraryOutputIcon(VaultEntry entry) => switch (entry.outputKind) {
  'poster' => Icons.image_outlined,
  'video' => Icons.smart_display_outlined,
  'other' =>
    entry.isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
  _ => Icons.description_outlined,
};

class LibraryCategoryPicker extends StatelessWidget {
  const LibraryCategoryPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 7,
    runSpacing: 4,
    children: [
      for (final item in const {
        '': 'All projects',
        'capstone': 'Capstone',
        'pit': 'PIT Projects',
      }.entries)
        LibraryChoiceChip(
          label: item.value,
          selected: value == item.key,
          onSelected: () => onChanged(item.key),
        ),
    ],
  );
}

class LibraryChoiceChip extends StatelessWidget {
  const LibraryChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: selected
        ? ShadButton.secondary(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            onPressed: onSelected,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          )
        : ShadButton.ghost(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            onPressed: onSelected,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
  );
}

int libraryColumns(double width) => width >= 900
    ? 4
    : width >= 650
    ? 3
    : 2;

class LibraryResults extends StatelessWidget {
  const LibraryResults({
    super.key,
    required this.entries,
    required this.grid,
    required this.onOpen,
    this.projects,
    this.onProject,
    this.onDetails,
  });
  final List<VaultEntry> entries;
  final bool grid;
  final ValueChanged<VaultEntry> onOpen;
  final List<LibraryProject>? projects;
  final ValueChanged<LibraryProject>? onProject;
  final ValueChanged<VaultEntry>? onDetails;

  @override
  Widget build(BuildContext context) {
    final count = projects?.length ?? entries.length;
    Widget tile(int index) {
      final project = projects?[index];
      return LibraryEntryTile(
        entry: project?.representative ?? entries[index],
        grid: grid,
        project: project,
        onTap: () =>
            project == null ? onOpen(entries[index]) : onProject?.call(project),
        onDetails: project == null && onDetails != null
            ? () => onDetails!(entries[index])
            : null,
      );
    }

    if (!grid) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) => tile(index),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = libraryColumns(constraints.maxWidth);
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final coverWidth =
            (constraints.maxWidth - (columns - 1) * 14) / columns;
        final coverHeight = (coverWidth / .76).clamp(170.0, 320.0);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
            mainAxisExtent: coverHeight + 96 + (scale - 1).clamp(0, 2) * 125,
          ),
          itemBuilder: (_, index) => tile(index),
        );
      },
    );
  }
}

class LibraryEntryTile extends StatelessWidget {
  const LibraryEntryTile({
    super.key,
    required this.entry,
    required this.grid,
    required this.onTap,
    this.project,
    this.onDetails,
  });
  final VaultEntry entry;
  final bool grid;
  final VoidCallback onTap;
  final VoidCallback? onDetails;
  final LibraryProject? project;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = project?.title ?? entry.displayTitle;
    final documentCount =
        project?.entries.where((file) => file.isDocument).length ?? 0;
    final label = project != null
        ? '$documentCount ${documentCount == 1 ? 'document' : 'documents'}'
        : entry.outputLabel;
    final metadata = project != null
        ? [
            if (documentCount > 0) label,
            if (project!.entries.any((file) => file.outputKind == 'poster'))
              'Poster',
            if (project!.entries.any((file) => file.outputKind == 'video'))
              'Video',
            if (project!.entries.any((file) => file.outputKind == 'other'))
              'Other outputs',
          ].join(' · ')
        : '$label · Published';
    final ink = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: grid
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LibraryCover(entry: entry, project: project != null),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.teamName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (onDetails != null) _detailsButton(),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  metadata,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (entry.academicYear != '—' && entry.academicYear.isNotEmpty)
                  Text(
                    'SY ${entry.academicYear}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 82,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(3),
                        bottomLeft: Radius.circular(3),
                        topRight: Radius.circular(6),
                        bottomRight: Radius.circular(6),
                      ),
                      gradient: const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0xFF4C0B06),
                          Color(0xFF6B140D),
                          Color(0xFF7A110A),
                        ],
                        stops: [0.0, 0.12, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 6,
                          offset: const Offset(2, 3),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 6,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 1.2,
                            color: const Color(
                              0xFFD4AF37,
                            ).withValues(alpha: 0.7),
                          ),
                        ),
                        Center(
                          child: Icon(
                            project != null
                                ? Icons.menu_book_rounded
                                : libraryOutputIcon(entry),
                            color: const Color(0xFFFFD387),
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: ProgramColors.of(
                                  context,
                                  scope: entry.type,
                                ).tint,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                project != null
                                    ? ProgramColors.of(
                                        context,
                                        scope: entry.type,
                                      ).label
                                    : entry.outputLabel,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: ProgramColors.of(
                                    context,
                                    scope: entry.type,
                                  ).text,
                                ),
                              ),
                            ),
                            if (entry.academicYear != '—' &&
                                entry.academicYear.isNotEmpty) ...[
                              Text(
                                'SY ${entry.academicYear}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.groups_outlined,
                              size: 13,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${entry.teamName} · $metadata',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if ((project?.overview?.previewText ??
                                entry.previewText)
                            .isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            project?.overview?.previewText ?? entry.previewText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: colors.onSurfaceVariant.withValues(
                                alpha: 0.85,
                              ),
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (onDetails != null)
                    _detailsButton()
                  else
                    const Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ),
    );
    return Semantics(
      button: true,
      label: project != null
          ? 'Open project $title'
          : '${entry.openLabel}: $title, ${entry.outputLabel}',
      child: Tooltip(
        message: title,
        child: Material(
          color: grid ? Colors.transparent : colors.surface,
          borderRadius: BorderRadius.circular(10),
          child: ink,
        ),
      ),
    );
  }

  Widget _detailsButton() => Tooltip(
    message: 'Output details',
    child: ShadButton.ghost(
      width: 28,
      height: 28,
      padding: EdgeInsets.zero,
      onPressed: onDetails,
      child: Semantics(
        label: 'Output details',
        child: const Icon(Icons.more_horiz, size: 18),
      ),
    ),
  );
}

class LibraryCover extends StatelessWidget {
  const LibraryCover({super.key, required this.entry, this.project = false});
  final VaultEntry entry;
  final bool project;

  // Keep a project's cover consistent on every shelf and in its detail view.
  Color get _color {
    const palette = [
      Color(0xFF465451),
      Color(0xFF495666),
      Color(0xFF71564E),
      Color(0xFF625D4E),
    ];
    final seed = entry.groupingKey.runes.fold(
      0,
      (value, rune) => (value * 31 + rune) & 0x7fffffff,
    );
    return palette[seed % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    if (!project && !entry.isDocument) {
      return LibraryMediaPreview(entry: entry);
    }
    return Semantics(
      image: true,
      label: 'Cover for ${entry.displayTitle}',
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _color,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(3),
            right: Radius.circular(7),
          ),
          boxShadow: [
            BoxShadow(
              color: _color.withValues(alpha: .14),
              blurRadius: 6,
              offset: const Offset(2, 3),
            ),
          ],
        ),
        child: _textCover(context),
      ),
    );
  }

  Widget _textCover(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 130;
      return Stack(
        children: [
          Positioned(
            left: 6,
            top: 0,
            bottom: 0,
            child: Container(
              width: 2,
              color: Colors.black.withValues(alpha: .18),
            ),
          ),
          Positioned(
            right: 0,
            top: 4,
            bottom: 4,
            child: Container(
              width: 2,
              color: const Color(0xFFEEE6D7).withValues(alpha: .5),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 13 : 18,
              14,
              compact ? 9 : 14,
              14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project
                      ? '${ProgramColors.of(context, scope: entry.type).label.toUpperCase()} PROJECT'
                      : entry.outputLabel.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DefensysTokens.caption.copyWith(
                    color: const Color(0xFFF3DBAF),
                    fontSize: compact ? 9 : 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .6,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 24,
                  height: 1,
                  color: const Color(0xFFF3DBAF).withValues(alpha: .65),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      entry.displayTitle,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: DefensysTokens.sectionTitle.copyWith(
                        color: Colors.white,
                        fontSize: compact ? 12 : 17,
                        height: 1.25,
                        letterSpacing: -.25,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Divider(height: 1, color: Colors.white.withValues(alpha: .3)),
                const SizedBox(height: 8),
                Text(
                  entry.academicYear.isNotEmpty && entry.academicYear != '—'
                      ? 'SY ${entry.academicYear}'
                      : 'USTP Research Library',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DefensysTokens.caption.copyWith(
                    color: const Color(0xFFF4ECE1),
                    fontSize: compact ? 9 : 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class LibraryEmpty extends StatelessWidget {
  const LibraryEmpty({super.key, required this.title, required this.message});
  final String title, message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 15),
    child: Column(
      children: [
        Icon(
          Icons.menu_book_outlined,
          size: 32,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
