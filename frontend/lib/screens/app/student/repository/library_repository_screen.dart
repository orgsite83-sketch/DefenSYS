import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';

import '../../../../models/repository_library.dart';
import '../../../../services/repository_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/repository/library_components.dart';
import '../../../../widgets/shadcn/defensys_workflow_widgets.dart';
import 'library_project_screen.dart';
import 'library_search_screen.dart';
import 'repository_entry_view.dart';

class RepositoryTab extends ConsumerStatefulWidget {
  const RepositoryTab({super.key});
  @override
  ConsumerState<RepositoryTab> createState() => _RepositoryTabState();
}

class _RepositoryTabState extends ConsumerState<RepositoryTab> {
  LibraryBrowse _browse = LibraryBrowse.projects;
  String _type = '', _year = '';
  bool _grid = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() =>
      ref.read(repositoryProvider.notifier).fetchForStudent(search: '');
  Future<void> _open(VaultEntry entry) async {
    await openRepositoryEntry(context, ref, entry);
    if (mounted) await _refresh();
  }

  Future<void> _project(LibraryProject project) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LibraryProjectScreen(project: project)),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Builder(builder: (context) => _build(context)),
  );

  Widget _build(BuildContext context) {
    final state = ref.watch(repositoryProvider);
    final all = state.entries.map(VaultEntry.fromJson).toList();
    final years =
        all
            .map((entry) => entry.academicYear)
            .where((year) => year.isNotEmpty && year != '—')
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    final entries = all
        .where(
          (entry) =>
              (_type.isEmpty || entry.type == _type) &&
              (_year.isEmpty || entry.academicYear == _year) &&
              _browse.matches(entry),
        )
        .toList();
    final projects = _browse == LibraryBrowse.projects
        ? LibraryProject.group(entries)
        : null;
    final colors = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'USTP Research Library',
                            style: TextStyle(
                              color: DefensysTokens.maroonTextOf(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _browse == LibraryBrowse.projects
                                ? 'Explore projects'
                                : _browse.label,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -.5,
                                ),
                          ),
                        ],
                      ),
                    ),
                    ShadButton.ghost(
                      width: 36,
                      height: 36,
                      padding: EdgeInsets.zero,
                      onPressed: () => setState(() => _grid = true),
                      child: Semantics(
                        label: 'Project covers',
                        selected: _grid,
                        child: const Icon(Icons.grid_view_rounded, size: 18),
                      ),
                    ),
                    ShadButton.ghost(
                      width: 36,
                      height: 36,
                      padding: EdgeInsets.zero,
                      onPressed: () => setState(() => _grid = false),
                      child: Semantics(
                        label: 'Compact list',
                        selected: !_grid,
                        child: const Icon(Icons.view_list_rounded, size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  'Digital manuscripts, posters, and public project outputs.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 17),
                ShadButton.outline(
                  width: double.infinity,
                  expands: true,
                  height: 46,
                  leading: const Icon(Icons.search, size: 18),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LibrarySearchScreen(
                        browse: _browse,
                        type: _type,
                        year: _year,
                        years: years,
                      ),
                    ),
                  ),
                  child: Text(
                    _browse == LibraryBrowse.projects
                        ? 'Search projects, teams, topics…'
                        : 'Search ${_browse.label.toLowerCase()}…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                  ),
                ),
                const SizedBox(height: 16),
                LibraryBrowsePicker(
                  value: _browse,
                  onChanged: (value) => setState(() => _browse = value),
                ),
                const SizedBox(height: 11),
                LibraryCategoryPicker(
                  value: _type,
                  onChanged: (value) => setState(() => _type = value),
                ),
                if (years.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  WorkflowSelect(
                    label: 'School year',
                    value: years.contains(_year) ? _year : '',
                    searchable: false,
                    options: {
                      '': 'All years',
                      for (final year in years) year: 'SY $year',
                    },
                    onChanged: (value) => setState(() => _year = value),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _browse == LibraryBrowse.projects
                            ? 'Public projects'
                            : 'Public ${_browse.label.toLowerCase()}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${projects?.length ?? entries.length} ${projects != null ? 'projects' : 'outputs'}',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (state.isLoading && all.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (state.error != null) ...[
                  const LibraryEmpty(
                    title: 'Could not load the library',
                    message: 'Check your connection and try again.',
                  ),
                  ShadButton.outline(
                    onPressed: _refresh,
                    child: const Text('Retry'),
                  ),
                ] else if (entries.isEmpty)
                  const LibraryEmpty(
                    title: 'No public outputs found',
                    message:
                        'Try another document stage, project category, or school year.',
                  )
                else
                  LibraryResults(
                    entries: entries,
                    grid: _grid,
                    projects: projects,
                    onOpen: _open,
                    onDetails: (entry) =>
                        showRepositoryEntryDetails(context, ref, entry),
                    onProject: _project,
                  ),
                const SizedBox(height: 18),
                Text(
                  _browse == LibraryBrowse.projects
                      ? 'Open a project to explore its published deliverables.'
                      : 'Select an output to open it directly.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
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
