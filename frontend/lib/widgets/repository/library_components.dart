import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/repository_library.dart';
import '../../services/authenticated_client.dart';
import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_workflow_widgets.dart';

final _posterBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, file) {
      return ref
          .watch(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile(file);
    });

IconData libraryOutputIcon(VaultEntry entry) => switch (entry.outputKind) {
  'poster' => Icons.image_outlined,
  'video' => Icons.smart_display_outlined,
  'other' =>
    entry.isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
  _ => Icons.description_outlined,
};

class LibraryBrowsePicker extends StatelessWidget {
  const LibraryBrowsePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final LibraryBrowse value;
  final ValueChanged<LibraryBrowse> onChanged;
  @override
  Widget build(BuildContext context) => WorkflowSelect(
    label: 'Show',
    value: value.name,
    searchable: false,
    options: {
      for (final browse in LibraryBrowse.values) browse.name: browse.label,
    },
    onChanged: (name) => onChanged(
      LibraryBrowse.values.firstWhere((browse) => browse.name == name),
    ),
  );
}

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
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            onPressed: onSelected,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          )
        : ShadButton.ghost(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            onPressed: onSelected,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
  );
}

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
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 650
            ? 3
            : 2;
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
            mainAxisExtent: 258 + (scale - 1).clamp(0, 2) * 95,
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
    final label = project != null
        ? '${project!.entries.where((file) => file.isDocument).length} documents'
        : entry.outputLabel;
    final metadata = project != null
        ? [
            label,
            if (project!.entries.any((file) => file.outputKind == 'poster'))
              'Poster',
            if (project!.entries.any((file) => file.outputKind == 'video'))
              'Video',
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
                children: [
                  Container(
                    width: 55,
                    height: 74,
                    decoration: BoxDecoration(
                      color: DefensysTokens.maroon,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Icon(
                      project != null
                          ? Icons.layers_outlined
                          : libraryOutputIcon(entry),
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.teamName,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          metadata,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
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

class LibraryCover extends ConsumerWidget {
  const LibraryCover({super.key, required this.entry, this.project = false});
  final VaultEntry entry;
  final bool project;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = !project && entry.isImage && entry.fileUrl?.isNotEmpty == true
        ? ref.watch(_posterBytesProvider(entry.fileUrl!))
        : null;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DefensysTokens.maroon,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(3),
          right: Radius.circular(9),
        ),
      ),
      child:
          image?.when(
            data: (bytes) => Image.memory(
              bytes,
              fit: BoxFit.contain,
              semanticLabel: '${entry.displayTitle} poster',
            ),
            error: (_, _) => _textCover(context),
            loading: () => _textCover(context),
          ) ??
          _textCover(context),
    );
  }

  Widget _textCover(BuildContext context) => Stack(
    children: [
      Positioned(
        left: 6,
        top: 0,
        bottom: 0,
        child: Container(width: 1, color: const Color(0xFFBD8652)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(17, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  project ? Icons.menu_book_outlined : libraryOutputIcon(entry),
                  size: 13,
                  color: const Color(0xFFFFD387),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    project
                        ? (entry.type == 'pit' ? 'PIT PROJECT' : 'CAPSTONE')
                        : entry.outputLabel.toUpperCase(),
                    maxLines: 2,
                    style: const TextStyle(
                      color: Color(0xFFFFD387),
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  entry.displayTitle,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.17,
                    letterSpacing: -.3,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.teamName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFFFE7D2), fontSize: 11),
            ),
          ],
        ),
      ),
    ],
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
