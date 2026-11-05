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
import '../../../../services/repository_provider.dart';
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
  String? _deliverable;
  int _fileLimit = 20;
  bool _expanded = false;
  bool _saving = false;
  LibraryProject? _loaded;
  bool _loading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    if (widget.project.representative.catalogSummary) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadProject());
      _loading = true;
    }
  }

  Future<void> _loadProject() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final rows = await ref
          .read(repositoryProvider.notifier)
          .fetchProject(widget.project.key);
      final projects = LibraryProject.group(
        rows.map(VaultEntry.fromJson).toList(),
      );
      if (!mounted) return;
      setState(() {
        _loaded = projects.firstWhere((item) => item.key == widget.project.key);
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not load this project’s materials.';
        });
      }
    }
  }

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
    maroonActions: true,
    neutralActionText: true,
    child: Builder(builder: (context) => _build(context)),
  );

  Widget _build(BuildContext context) {
    final project = _loaded ?? widget.project;
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
    final deliverables = project.deliverables;
    final selectedKey =
        _deliverable ?? (deliverables.isEmpty ? '' : deliverables.first.key);
    final selected = deliverables
        .where((item) => item.key == selectedKey)
        .firstOrNull;
    final shown = (selected?.entries ?? <VaultEntry>[])
        .take(_fileLimit)
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
                                  color: DefensysTokens.textSecondaryOf(
                                    context,
                                  ),
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
                  'Research materials (${entry.catalogSummary ? entry.projectOutputCount : project.entries.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                if (!_loading && _loadError == null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in deliverables)
                        LibraryChoiceChip(
                          label:
                              '${item.displayLabel(deliverables)} (${item.entries.length})',
                          selected: item.key == selectedKey,
                          onSelected: () => setState(() {
                            _deliverable = item.key;
                            _fileLimit = 20;
                          }),
                        ),
                    ],
                  ),
                const SizedBox(height: 15),
                if (_loading)
                  const LibraryShelfLoading()
                else if (_loadError != null) ...[
                  Text(_loadError!),
                  ShadButton.outline(
                    onPressed: _loadProject,
                    child: const Text('Retry'),
                  ),
                ] else if (shown.isEmpty)
                  const LibraryEmpty(
                    title: 'No published materials',
                    message:
                        'Choose another deliverable to explore this project.',
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
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  file.fileName,
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
                if ((selected?.entries.length ?? 0) > shown.length)
                  ShadButton.outline(
                    onPressed: () => setState(() => _fileLimit += 20),
                    child: const Text('Load more files'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
