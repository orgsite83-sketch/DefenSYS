import 'package:defensys/theme/program_colors.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/repository_library.dart';
import '../../services/authenticated_client.dart';
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
                          color: Colors.black.withOpacity(0.14),
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
                            color: const Color(0xFFD4AF37).withOpacity(0.7),
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
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: ProgramColors.of(context, scope: entry.type).tint,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                project != null
                                    ? (entry.type == 'pit' ? 'PIT' : 'CAPSTONE')
                                    : entry.outputLabel,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: ProgramColors.of(context, scope: entry.type).text,
                                ),
                              ),
                            ),
                            if (entry.academicYear != '—' &&
                                entry.academicYear.isNotEmpty) ...[
                              const SizedBox(width: 6),
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
                              color: colors.onSurfaceVariant.withOpacity(0.85),
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
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          bottomLeft: Radius.circular(4),
          topRight: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0xFF252C35), // deep spine hinge
            const Color(0xFF34404E), // crease shadow
            const Color(0xFF475569), // neutral cover; track identity stays in its badge
            const Color(0xFF526174), // subtle surface illumination
          ],
          stops: [0.0, 0.05, 0.16, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 10,
            offset: const Offset(3, 5),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 2,
            offset: const Offset(1, 1),
          ),
        ],
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
      // Embossed gold spine hinge line
      Positioned(
        left: 8,
        top: 0,
        bottom: 0,
        child: Container(
          width: 1.2,
          color: const Color(0xFFD4AF37).withOpacity(0.7),
        ),
      ),
      // Spine crease shadow
      Positioned(
        left: 10,
        top: 0,
        bottom: 0,
        child: Container(
          width: 2.0,
          color: Colors.black.withOpacity(0.22),
        ),
      ),
      // Simulated page paper edge on right
      Positioned(
        right: 0,
        top: 4,
        bottom: 4,
        child: Container(
          width: 2.0,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED).withOpacity(0.35),
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(2),
            ),
          ),
        ),
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
