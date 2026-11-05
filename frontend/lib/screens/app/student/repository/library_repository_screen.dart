import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../models/repository_library.dart';
import '../../../../models/library_filters.dart';
import '../../../../models/library_topics.dart';
import '../../../../widgets/repository/library_hero.dart';
import '../../../../services/repository_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/repository/library_activity_panel.dart';
import '../../../../widgets/repository/library_components.dart';
import '../../../../widgets/repository/library_discovery.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../widgets/shadcn/defensys_workflow_widgets.dart';
import 'library_project_screen.dart';
import 'library_search_screen.dart';
import 'repository_entry_view.dart';

enum _LibraryView { home, directory, collection }

// Keep library routes inside the workspace so its header and bottom navigation
// remain available while reading project details or searching.
class RepositoryTab extends StatefulWidget {
  const RepositoryTab({super.key});
  @override
  State<RepositoryTab> createState() => _RepositoryNavigatorState();
}

class _RepositoryNavigatorState extends State<RepositoryTab> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
    onPopWithResult: (result) => _navigator.currentState!.pop(result),
    child: Navigator(
      key: _navigator,
      onGenerateRoute: (_) =>
          MaterialPageRoute<void>(builder: (_) => const _RepositoryHome()),
    ),
  );
}

class _RepositoryHome extends ConsumerStatefulWidget {
  const _RepositoryHome();
  @override
  ConsumerState<_RepositoryHome> createState() => _RepositoryTabState();
}

class _RepositoryTabState extends ConsumerState<_RepositoryHome> {
  final _scroll = ScrollController();
  _LibraryView _view = _LibraryView.home;
  LibraryBrowse _browse = LibraryBrowse.projects;
  String _type = '';
  LibraryFilterSelection _selection = const LibraryFilterSelection();
  bool _grid = true;
  String _deliverable = '';
  bool _sortByTitle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() {
    final notifier = ref.read(repositoryProvider.notifier);
    if (_view != _LibraryView.collection) {
      return notifier.fetchForStudent(search: '');
    }
    if (_browse != LibraryBrowse.projects) {
      return notifier.fetchEntries(
        search: '',
        type: '',
        yearLevel: '',
        stage: '',
        academicYear: '',
      );
    }
    return notifier.fetchCatalog(
      filters: {
        if (_type.isNotEmpty) 'type': _type,
        if (_selection.year.isNotEmpty) 'academic_year': _selection.year,
        for (final group in LibraryFilterGroup.values)
          if (_selection.values(group).isNotEmpty)
            group.name: _selection.query(group),
        if (_deliverable.isNotEmpty) 'deliverable': _deliverable,
        if (_sortByTitle) 'sort': 'title',
      },
    );
  }

  void _navigate(_LibraryView view) {
    final wasCollection = _view == _LibraryView.collection;
    setState(() => _view = view);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (wasCollection && view != _LibraryView.collection) _refresh();
  }

  void _collection({
    LibraryBrowse browse = LibraryBrowse.projects,
    String type = '',
    LibraryTag? subject,
  }) {
    _browse = browse;
    _deliverable = '';
    _type = type;
    _selection = subject == null
        ? const LibraryFilterSelection()
        : const LibraryFilterSelection().toggle(
            LibraryFilterGroup.subject,
            subject,
          );
    _navigate(_LibraryView.collection);
    if (ref.read(repositoryProvider).catalog) _refresh();
  }

  Future<void> _open(VaultEntry entry) async {
    await openRepositoryEntry(context, ref, entry);
  }

  Future<void> _project(LibraryProject project) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LibraryProjectScreen(project: project)),
    );
  }

  Future<void> _myShelf() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text('My reading shelf'),
            backgroundColor: DefensysTokens.surfaceOf(context),
            foregroundColor: DefensysTokens.textPrimaryOf(context),
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
          ),
          body: const SingleChildScrollView(
            padding: EdgeInsets.all(18),
            child: LibraryActivityPanel(initialTab: 'Saved'),
          ),
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _filters(List<VaultEntry> all) async {
    final selection = await showLibraryPanel<LibraryFilterSelection>(
      context,
      title: 'Refine this collection',
      desktopDialog: true,
      builder: (context) => LibraryFilterPanel(
        serverOptions: ref.read(repositoryProvider).catalog
            ? ref.read(repositoryProvider).options
            : null,
        entries: all
            .where(
              (entry) =>
                  (_type.isEmpty || entry.type == _type) &&
                  _browse.matches(entry),
            )
            .toList(),
        selection: _selection,
        onApply: (value) => Navigator.pop(context, value),
      ),
    );
    if (mounted && selection != null) {
      setState(() {
        _selection = selection;
      });
      if (ref.read(repositoryProvider).catalog) _refresh();
    }
  }

  void _search(List<VaultEntry> all) {
    final home = _view != _LibraryView.collection;
    final years =
        all
            .map((entry) => entry.academicYear)
            .where((year) => year.isNotEmpty && year != '—')
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LibrarySearchScreen(
          browse: home ? LibraryBrowse.projects : _browse,
          type: home ? '' : _type,
          selection: home ? const LibraryFilterSelection() : _selection,
          years: years,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    maroonActions: true,
    neutralActionText: true,
    child: Builder(builder: (context) => _build(context)),
  );

  Widget _savedButton() => Tooltip(
    message: 'My reading shelf',
    child: ShadButton.ghost(
      width: 44,
      height: 44,
      padding: EdgeInsets.zero,
      onPressed: _myShelf,
      child: const Icon(Icons.bookmarks_outlined, size: 20),
    ),
  );

  Widget _build(BuildContext context) {
    final state = ref.watch(repositoryProvider);
    final all = state.entries.map(VaultEntry.fromJson).toList();
    final home = _view == _LibraryView.home;
    final caption = DefensysTokens.caption.copyWith(
      color: DefensysTokens.textSecondaryOf(context),
    );
    return PopScope(
      canPop: home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _navigate(_LibraryView.home);
      },
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (home)
                    const LibraryHero()
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ShadButton.ghost(
                              height: 44,
                              padding: EdgeInsets.zero,
                              leading: const Icon(Icons.arrow_back, size: 16),
                              onPressed: () => _navigate(_LibraryView.home),
                              child: const Text(
                                'Back to library',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                        _savedButton(),
                      ],
                    ),
                    Text(
                      _view == _LibraryView.directory
                          ? 'Browse the repository'
                          : _collectionTitle,
                      style: DefensysTokens.pageTitle.copyWith(
                        fontSize: 26,
                        letterSpacing: -.7,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _view == _LibraryView.directory
                          ? 'Explore a topic or choose a kind of output.'
                          : 'Explore published research in this collection.',
                      style: caption,
                    ),
                  ],
                  if (_view != _LibraryView.directory) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: ShadButton.outline(
                            width: double.infinity,
                            expands: true,
                            height: 48,
                            mainAxisAlignment: MainAxisAlignment.start,
                            leading: const Icon(Icons.search, size: 19),
                            onPressed: () => _search(all),
                            child: Text(
                              home ||
                                      _browse == LibraryBrowse.projects ||
                                      _browse == LibraryBrowse.outputs
                                  ? 'Search projects, teams, topics…'
                                  : 'Search ${_browse.label.toLowerCase()}…',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DefensysTokens.body.copyWith(
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                            ),
                          ),
                        ),
                        if (home) ...[const SizedBox(width: 8), _savedButton()],
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (state.error != null) ...[
                    Text(
                      'Could not refresh the library. Check your connection and try again.',
                      style: caption,
                    ),
                    ShadButton.outline(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (state.error != null && all.isEmpty)
                    const LibraryEmpty(
                      title: 'The library is unavailable',
                      message:
                          'Retry to load the published research collection.',
                    )
                  else if (_view == _LibraryView.directory)
                    if (state.isLoading && all.isEmpty)
                      const LibraryShelfLoading()
                    else
                      ..._directory(all)
                  else if (home)
                    ..._home(all, state.isLoading)
                  else
                    ..._collectionBody(all, state.isLoading),
                  if (home && MediaQuery.sizeOf(context).width < 760)
                    const LibraryAffiliationFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _directory(List<VaultEntry> all) => [
    Text('Browse by topic', style: _sectionStyle),
    const SizedBox(height: 10),
    for (final topic in _topics(all))
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Icon(
          Icons.topic_outlined,
          color: DefensysTokens.textSecondaryOf(context),
        ),
        title: Text(
          topic.key.label,
          style: DefensysTokens.body.copyWith(
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        subtitle: Text(
          '${topic.value} ${topic.value == 1 ? 'project' : 'projects'}',
          style: DefensysTokens.caption.copyWith(
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () =>
            _collection(browse: LibraryBrowse.projects, subject: topic.key),
      ),
    const SizedBox(height: 20),
    Text('Browse by format', style: _sectionStyle),
    const SizedBox(height: 12),
    LibraryShelfDirectory(
      entries: all,
      availableOnly: true,
      onSelected: (browse) => _collection(browse: browse),
    ),
  ];

  String get _collectionTitle {
    if (_browse != LibraryBrowse.projects && _browse != LibraryBrowse.outputs) {
      return _browse.label;
    }
    if (_type == 'capstone') return 'Capstone collection';
    if (_type == 'pit') return 'PIT collection';
    if (_selection.subjects.length == 1) {
      final id = _selection.subjects.first;
      if (id == unspecifiedLibraryTag.id) return 'More research';
      return _selection.label(
        LibraryFilterGroup.subject,
        id,
        ref.read(repositoryProvider).entries.map(VaultEntry.fromJson).toList(),
      );
    }
    return _browse == LibraryBrowse.outputs ? 'All outputs' : 'All projects';
  }

  TextStyle get _sectionStyle => DefensysTokens.sectionTitle.copyWith(
    color: DefensysTokens.textPrimaryOf(context),
  );

  List<MapEntry<LibraryTag, int>> _topics(List<VaultEntry> all) {
    final state = ref.read(repositoryProvider);
    if (state.catalog && state.options['topics'] is List) {
      return (state.options['topics'] as List)
          .whereType<Map>()
          .map(
            (item) => MapEntry(
              LibraryTag(
                id: item['id'].toString(),
                label: item['label'].toString(),
              ),
              (item['projects'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();
    }
    return LibraryTopicCollection.group(
      all,
    ).map((topic) => MapEntry(topic.tag, topic.projects.length)).toList();
  }

  List<Widget> _home(List<VaultEntry> all, bool loading) {
    final topics = _topics(all);
    final projects = LibraryProject.group(all);
    return [
      Row(
        children: [
          Expanded(child: Text('Published projects', style: _sectionStyle)),
          ShadButton.ghost(
            onPressed: () => _navigate(_LibraryView.directory),
            child: const Text('Browse all'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      LibraryCategoryPicker(
        value: _type,
        onChanged: (type) => _collection(type: type),
      ),
      const SizedBox(height: 12),
      if (topics.isNotEmpty)
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: topics.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final topic = topics[index];
              return ShadButton.outline(
                key: ValueKey('library-topic-${topic.key.id}'),
                leading: const Icon(Icons.topic_outlined, size: 16),
                trailing: const Icon(Icons.chevron_right, size: 16),
                onPressed: () => _collection(subject: topic.key),
                child: Text(
                  topic.key.label,
                  style: DefensysTokens.body.copyWith(
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              );
            },
          ),
        ),
      const SizedBox(height: 18),
      if (loading && all.isEmpty)
        const LibraryShelfLoading()
      else if (all.isEmpty)
        const LibraryEmpty(
          title: 'The collection is growing',
          message:
              'Published research will appear here when it becomes available.',
        )
      else
        LibraryResults(
          entries: all,
          projects: projects.take(12).toList(),
          grid: true,
          onOpen: _open,
          onProject: _project,
          onDetails: (entry) => showRepositoryEntryDetails(context, ref, entry),
        ),
      if (projects.isNotEmpty)
        ShadButton.outline(
          width: double.infinity,
          onPressed: () => _collection(),
          child: const Text('Browse all projects'),
        ),
    ];
  }

  List<Widget> _collectionBody(List<VaultEntry> all, bool loading) {
    final state = ref.watch(repositoryProvider);
    final topicProjects =
        _browse == LibraryBrowse.outputs && _selection.subjects.isNotEmpty
        ? LibraryTopicCollection.group(all)
              .where((topic) => _selection.subjects.contains(topic.tag.id))
              .expand((topic) => topic.projects.map((project) => project.key))
              .toSet()
        : null;
    bool matches(VaultEntry entry) =>
        (_type.isEmpty || entry.type == _type) &&
        _selection.matches(
          entry,
          except: topicProjects == null ? null : LibraryFilterGroup.subject,
        ) &&
        (topicProjects == null || topicProjects.contains(entry.groupingKey)) &&
        _browse.matches(entry);
    final matched = state.catalog ? all : all.where(matches).toList();
    final deliverables = LibraryDeliverable.group(matched);
    final entries = matched
        .where(
          (entry) => _deliverable.isEmpty || entry.hasDeliverable(_deliverable),
        )
        .toList();
    // A matching project's detail retains every published output, not just the
    // files that happened to match its topic filter.
    final projects = _browse == LibraryBrowse.projects
        ? LibraryProject.group(all)
              .where(
                (project) =>
                    project.entries.any((entry) => entries.contains(entry)),
              )
              .toList()
        : null;
    if (_sortByTitle) {
      projects?.sort((a, b) {
        final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return title != 0 ? title : a.key.compareTo(b.key);
      });
      entries.sort(
        (a, b) => a.displayTitle.toLowerCase().compareTo(
          b.displayTitle.toLowerCase(),
        ),
      );
    }
    final filtered = !_selection.isEmpty;
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in const {
            '': 'All tracks',
            'capstone': 'Capstone',
            'pit': 'PIT',
          }.entries)
            LibraryChoiceChip(
              label: item.value,
              selected: _type == item.key,
              onSelected: () {
                setState(() => _type = item.key);
                if (state.catalog) _refresh();
              },
            ),
        ],
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 400 ? 270 : 300,
            child: WorkflowSelect(
              label: 'Deliverable',
              value: _deliverable,
              options: {
                '': 'All deliverables',
                if (state.catalog && state.options['deliverables'] is List)
                  for (final item
                      in (state.options['deliverables'] as List)
                          .whereType<Map>())
                    item['key'].toString():
                        (item['display_label'] ?? item['label']).toString()
                else
                  for (final item in deliverables)
                    item.key: item.displayLabel(deliverables),
              },
              onChanged: (value) {
                setState(() => _deliverable = value);
                if (state.catalog) _refresh();
              },
            ),
          ),
          SizedBox(
            width: 180,
            child: WorkflowSelect(
              label: 'Sort',
              searchable: false,
              value: _sortByTitle ? 'title' : 'recent',
              options: const {'recent': 'Recently added', 'title': 'Title A–Z'},
              onChanged: (value) {
                setState(() => _sortByTitle = value == 'title');
                if (state.catalog) _refresh();
              },
            ),
          ),
        ],
      ),
      Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${state.catalog ? state.counts['total'] ?? 0 : projects?.length ?? entries.length} ${projects != null ? 'projects' : 'outputs'}',
            style: DefensysTokens.caption.copyWith(
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          Tooltip(
            message: 'Project covers',
            child: ShadButton.ghost(
              width: 44,
              height: 44,
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _grid = true),
              child: Semantics(
                selected: _grid,
                child: const Icon(Icons.grid_view_rounded, size: 17),
              ),
            ),
          ),
          Tooltip(
            message: 'Compact list',
            child: ShadButton.ghost(
              width: 44,
              height: 44,
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _grid = false),
              child: Semantics(
                selected: !_grid,
                child: const Icon(Icons.view_list_rounded, size: 18),
              ),
            ),
          ),
          ShadButton.outline(
            height: 44,
            leading: const Icon(Icons.tune_rounded, size: 17),
            onPressed: () => _filters(all),
            child: Text(
              filtered ? 'Filters (active)' : 'Filters',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
      if (filtered) ...[
        const SizedBox(height: 10),
        LibraryActiveFilters(
          selection: _selection,
          entries: all,
          onChanged: (value) {
            setState(() => _selection = value);
            if (state.catalog) _refresh();
          },
        ),
      ],
      const SizedBox(height: 16),
      if (loading && all.isEmpty)
        const LibraryShelfLoading()
      else if (entries.isEmpty) ...[
        const LibraryEmpty(
          title: 'No matching outputs',
          message:
              'Try another topic or clear your filters to explore the repository.',
        ),
        ShadButton.outline(
          onPressed: () => _collection(),
          child: const Text('Explore all projects'),
        ),
      ] else
        _results(entries, projects: projects),
      if (state.catalog && state.hasMore) ...[
        const SizedBox(height: 16),
        ShadButton.outline(
          enabled: !state.loadingMore,
          onPressed: state.loadingMore
              ? null
              : () => ref
                    .read(repositoryProvider.notifier)
                    .fetchCatalog(append: true),
          child: Text(
            state.loadingMore ? 'Loading projects…' : 'Load more projects',
          ),
        ),
      ],
    ];
  }

  Widget _results(List<VaultEntry> entries, {List<LibraryProject>? projects}) =>
      Column(
        children: [
          LibraryResults(
            entries: entries,
            grid: _view == _LibraryView.home || _grid,
            projects: projects,
            onOpen: _open,
            onProject: _project,
            onDetails: (entry) =>
                showRepositoryEntryDetails(context, ref, entry),
          ),
          const SizedBox(height: 10),
          Divider(
            height: 3,
            thickness: 2,
            color: DefensysTokens.borderOf(context),
          ),
        ],
      );
}
