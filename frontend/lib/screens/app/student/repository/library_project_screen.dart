import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';

import '../../../../models/repository_library.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../theme/program_colors.dart';
import '../../../../widgets/repository/library_components.dart';
import '../../../../widgets/repository/library_discovery.dart';
import '../../../../services/repository_review_provider.dart';
import '../../../../toasts/feedback_toast.dart';
import 'repository_entry_view.dart';

class LibraryProjectScreen extends ConsumerStatefulWidget {
  const LibraryProjectScreen({super.key, required this.project});
  final LibraryProject project;
  @override
  ConsumerState<LibraryProjectScreen> createState() =>
      _LibraryProjectScreenState();
}

class _LibraryProjectScreenState extends ConsumerState<LibraryProjectScreen> {
  String _category = 'All';
  bool _expanded = false;
  bool _saving = false;
  Future<void> _save(bool saved) async {
    setState(() => _saving = true);
    final item = await ref
        .read(repositoryReviewServiceProvider)
        .updateShelfProgress(
          targetId: 'project:${widget.project.key}',
          isSaved: !saved,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (item == null) {
      showErrorToast(context, 'Could not update your saved project.');
    }
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Builder(builder: (context) => _build(context)),
  );

  Widget _build(BuildContext context) {
    final project = widget.project;
    final entry = project.representative;
    final source = project.overview;
    final colors = Theme.of(context).colorScheme;
    final saved =
        ref
            .watch(repositoryLibraryActivityProvider)
            .asData
            ?.value
            .saved
            .any((item) => item.id == 'project:${project.key}') ??
        false;
    final shown = project.entries
        .where(
          (file) => switch (_category) {
            'Documents' => file.isDocument,
            'Posters' => file.outputKind == 'poster',
            'Videos' => file.outputKind == 'video',
            _ => true,
          },
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Project details'),
        backgroundColor: DefensysTokens.maroon,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final coverWidth = constraints.maxWidth < 400
                        ? 88.0
                        : 128.0;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: coverWidth,
                          height: coverWidth / .68,
                          child: LibraryCover(entry: entry, project: true),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${ProgramColors.of(context, scope: entry.type).label} project',
                                style: DefensysTokens.caption.copyWith(
                                  color: ProgramColors.of(
                                    context,
                                    scope: entry.type,
                                  ).text,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Semantics(
                                header: true,
                                child: Text(
                                  project.title,
                                  style: DefensysTokens.pageTitle.copyWith(
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                entry.teamName,
                                style: DefensysTokens.caption.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              if (entry.academicYear.isNotEmpty &&
                                  entry.academicYear != '—')
                                Text(
                                  'SY ${entry.academicYear}',
                                  style: DefensysTokens.caption.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 22),
                ShadButton.outline(
                  width: double.infinity,
                  enabled: !_saving,
                  onPressed: _saving ? null : () => _save(saved),
                  leading: Icon(
                    saved
                        ? Icons.bookmark_added_outlined
                        : Icons.bookmark_add_outlined,
                  ),
                  child: Text(
                    _saving
                        ? 'Saving…'
                        : saved
                        ? 'Saved to My shelf'
                        : 'Save to My shelf',
                  ),
                ),
                const SizedBox(height: 24),
                LibraryProjectTags(entry: entry),
                const SizedBox(height: 14),
                Text(
                  'About this research',
                  style: DefensysTokens.sectionTitle.copyWith(
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                if (source != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.overviewLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        source.previewText,
                        maxLines: _expanded ? null : 6,
                        overflow: _expanded ? null : TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.6),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Source: ${source.outputLabel}${source.overviewPage != null ? ' · p. ${source.overviewPage}' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      Wrap(
                        spacing: 10,
                        children: [
                          ShadButton.ghost(
                            onPressed: () =>
                                setState(() => _expanded = !_expanded),
                            child: Text(_expanded ? 'Show less' : 'Read more'),
                          ),
                          ShadButton.ghost(
                            onPressed: () =>
                                openRepositoryEntry(context, ref, source),
                            child: const Text('Open source document'),
                          ),
                        ],
                      ),
                    ],
                  )
                else
                  const Text('Explore this project’s published outputs below.'),
                const SizedBox(height: 25),
                Text(
                  'Available outputs (${project.entries.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                if (project.entries.length > 4)
                  Wrap(
                    spacing: 7,
                    runSpacing: 4,
                    children: [
                      for (final label in [
                        'All',
                        'Documents',
                        'Posters',
                        'Videos',
                      ])
                        LibraryChoiceChip(
                          label: label,
                          selected: _category == label,
                          onSelected: () => setState(() => _category = label),
                        ),
                    ],
                  ),
                const SizedBox(height: 15),
                if (shown.isEmpty)
                  const LibraryEmpty(
                    title: 'No outputs in this category',
                    message: 'Choose another category to explore this project.',
                  )
                else
                  ...shown.map(
                    (file) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Divider(color: DefensysTokens.borderOf(context)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                libraryOutputIcon(file),
                                size: 20,
                                color: DefensysTokens.maroonTextOf(context),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  file.outputLabel,
                                  style: DefensysTokens.body.copyWith(
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                              Tooltip(
                                message: 'Output details',
                                child: ShadButton.ghost(
                                  width: 44,
                                  height: 44,
                                  padding: EdgeInsets.zero,
                                  onPressed: () => showRepositoryEntryDetails(
                                    context,
                                    ref,
                                    file,
                                  ),
                                  child: const Icon(Icons.more_horiz, size: 18),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${file.stage} · Published',
                            style: DefensysTokens.caption.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ShadButton.outline(
                            width: double.infinity,
                            leading: Icon(libraryOutputIcon(file), size: 17),
                            onPressed: () =>
                                openRepositoryEntry(context, ref, file),
                            child: Text(file.openLabel),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
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
