import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';

import '../../../../models/repository_library.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/repository/library_components.dart';
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
                Text(
                  entry.type == 'pit' ? 'PIT PROJECT' : 'CAPSTONE',
                  style: TextStyle(
                    color: DefensysTokens.maroonTextOf(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  project.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${entry.teamName} · SY ${entry.academicYear}',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 13),
                ShadButton.outline(
                  onPressed: _saving ? null : () => _save(saved),
                  leading: Icon(
                    saved
                        ? Icons.bookmark_added_outlined
                        : Icons.bookmark_add_outlined,
                  ),
                  child: Text(saved ? 'Project saved' : 'Save project'),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Project overview',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 10),
                if (source != null)
                  ShadCard(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    shadows: const [],
                    child: Column(
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
                              child: Text(
                                _expanded ? 'Show less' : 'Read more',
                              ),
                            ),
                            ShadButton.ghost(
                              onPressed: () =>
                                  openRepositoryEntry(context, ref, source),
                              child: const Text('Open source document'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  const Text('Explore this project’s published outputs below.'),
                const SizedBox(height: 25),
                Text(
                  'Public deliverables (${project.entries.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
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
                      child: Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 5,
                          ),
                          leading: Icon(
                            libraryOutputIcon(file),
                            color: DefensysTokens.maroon,
                          ),
                          title: Text(
                            file.outputLabel,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text('${file.stage} · Published'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              showRepositoryEntryDetails(context, ref, file),
                        ),
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
