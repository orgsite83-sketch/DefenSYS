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
  String _type = '', _year = '', _topic = '';
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

    // Aggregate popular topics across published entries
    final allTopics = <String, int>{};
    for (final entry in all) {
      for (final t in entry.topics) {
        final clean = t.trim();
        if (clean.isNotEmpty) {
          allTopics[clean] = (allTopics[clean] ?? 0) + 1;
        }
      }
    }
    final popularTopics = allTopics.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final entries = all
        .where(
          (entry) =>
              (_type.isEmpty || entry.type == _type) &&
              (_year.isEmpty || entry.academicYear == _year) &&
              (_topic.isEmpty || entry.topics.contains(_topic)) &&
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
                const SizedBox(height: 6),
                Text(
                  'Digital manuscripts, posters, and public project outputs.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 14),
                LibraryCategoryPicker(
                  value: _type,
                  onChanged: (value) => setState(() => _type = value),
                ),
                if (_topic.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() => _topic = ''),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: DefensysTokens.maroon.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: DefensysTokens.maroon.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '#$_topic',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: DefensysTokens.maroonTextOf(context),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.close_rounded,
                            size: 13,
                            color: DefensysTokens.maroonTextOf(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                LibraryBrowsePicker(
                  value: _browse,
                  onChanged: (value) => setState(() => _browse = value),
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
                // Popular Topics Explorer Rail
                if (popularTopics.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        Icons.local_fire_department_outlined,
                        size: 14,
                        color: DefensysTokens.goldOf(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Popular Topics',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 30,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: popularTopics.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          final isAll = _topic.isEmpty;
                          return InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => setState(() => _topic = ''),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: isAll
                                    ? DefensysTokens.maroon
                                    : colors.onSurface.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                'All topics',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isAll
                                      ? Colors.white
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        }
                        final topic = popularTopics[index - 1];
                        final isSelected = _topic == topic.key;
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => setState(() {
                            _topic = isSelected ? '' : topic.key;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? DefensysTokens.maroon
                                  : colors.onSurface.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? DefensysTokens.maroon
                                    : colors.onSurface.withOpacity(0.08),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '#${topic.key}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : colors.onSurface,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.white.withOpacity(0.2)
                                        : colors.onSurface.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${topic.value}',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? Colors.white
                                          : colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                // Spotlight banner when on default overview
                if (projects != null &&
                    projects.isNotEmpty &&
                    _browse == LibraryBrowse.projects &&
                    _type.isEmpty &&
                    _year.isEmpty &&
                    _topic.isEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          DefensysTokens.maroon.withOpacity(0.06),
                          colors.surface,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: DefensysTokens.maroon.withOpacity(0.18),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: DefensysTokens.maroon,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFFFD387),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                runSpacing: 2,
                                children: [
                                  Text(
                                    'FEATURED RESEARCH',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.6,
                                      color:
                                          DefensysTokens.maroonTextOf(context),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFFFD387,
                                      ).withOpacity(0.25),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Text(
                                      'Curated',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFB45309),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                projects.first.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${projects.first.representative.teamName} · ${projects.first.entries.length} Published Deliverables',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                          ),
                          onPressed: () => _project(projects.first),
                          tooltip: 'Open featured project',
                        ),
                      ],
                    ),
                  ),
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
