import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../../models/repository_library.dart';
import '../../../../navigation/library_navigation.dart';
import '../../../../models/library_filters.dart';
import '../../../../models/library_topics.dart';
import '../../../../widgets/repository/library_hero.dart';
import '../../../../services/repository_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/repository/library_activity_panel.dart';
import '../../../../widgets/repository/library_components.dart';
import '../../../../widgets/repository/library_discovery.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import 'library_project_screen.dart';
import 'library_search_screen.dart';
import 'repository_entry_view.dart';

enum _LibraryView { home, directory, collection }

// Keep library routes inside the workspace so its header and bottom navigation
// remain available while reading project details or searching.
class RepositoryTab extends StatefulWidget {
  const RepositoryTab({super.key, this.routed = false, this.isActive = true});
  final bool routed;
  final bool isActive;
  @override
  State<RepositoryTab> createState() => _RepositoryNavigatorState();
}

class _RepositoryNavigatorState extends State<RepositoryTab> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => widget.routed
      ? const _RepositoryHome()
      : NavigatorPopHandler<Object?>(
          enabled: widget.isActive,
          onPopWithResult: (result) =>
              _navigator.currentState!.maybePop(result),
          child: Navigator(
            key: _navigator,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const _RepositoryHome(),
            ),
          ),
        );
}

class _RepositoryHome extends ConsumerStatefulWidget {
  const _RepositoryHome({
    this.view = _LibraryView.home,
    this.browse = LibraryBrowse.projects,
    this.type = '',
    this.selection = const LibraryFilterSelection(),
  });
  final _LibraryView view;
  final LibraryBrowse browse;
  final String type;
  final LibraryFilterSelection selection;
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
    _view = widget.view;
    _browse = widget.browse;
    _type = widget.type;
    _selection = widget.selection;
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

  bool _navigate(_LibraryView view) {
    final router = GoRouter.maybeOf(context);
    if (router != null &&
        router.routeInformationProvider.value.uri.path.startsWith(
          studentLibraryPath,
        )) {
      if (view == _LibraryView.home) {
        // Pop just this screen. This also restores the previous collection's
        // filters and scroll position instead of adding another history entry.
        context.pop();
      } else {
        pushLibraryPage<void>(
          context,
          page: view.name,
          builder: (_) => _RepositoryHome(
            view: view,
            browse: _browse,
            type: _type,
            selection: _selection,
          ),
        ).then((_) {
          if (mounted) _refresh();
        });
      }
      return true;
    }
    final wasCollection = _view == _LibraryView.collection;
    setState(() => _view = view);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (wasCollection && view != _LibraryView.collection) _refresh();
    return false;
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
    final routed = _navigate(_LibraryView.collection);
    if (!routed && ref.read(repositoryProvider).catalog) _refresh();
  }

  Future<void> _open(VaultEntry entry) async {
    await openRepositoryEntry(context, ref, entry);
  }

  Future<void> _project(LibraryProject project) async {
    await pushLibraryPage<void>(
      context,
      page: 'project',
      builder: (_) => LibraryProjectScreen(project: project),
    );
  }

  Future<void> _myShelf() async {
    await pushLibraryPage<void>(
      context,
      page: 'saved',
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
    );
    if (mounted) await _refresh();
  }

  Future<void> _filters(List<VaultEntry> all) async {
    final state = ref.read(repositoryProvider);
    final deliverables = LibraryDeliverable.group(all);
    final selection = await showLibraryPanel<LibraryCollectionFilters>(
      context,
      title: 'Filter and sort',
      desktopDialog: true,
      builder: (context) => LibraryFilterPanel(
        serverOptions: ref.read(repositoryProvider).catalog
            ? ref.read(repositoryProvider).options
            : null,
        entries: all.where((entry) => _browse.matches(entry)).toList(),
        selection: _selection,
        collection: LibraryCollectionFilters(
          selection: _selection,
          type: _type,
          deliverable: _deliverable,
          sortByTitle: _sortByTitle,
        ),
        deliverables: {
          if (state.catalog && state.options['deliverables'] is List)
            for (final item
                in (state.options['deliverables'] as List).whereType<Map>())
              item['key'].toString(): (item['display_label'] ?? item['label'])
                  .toString()
          else
            for (final item in deliverables)
              item.key: item.displayLabel(deliverables),
        },
        onApply: (_) {},
        onApplyCollection: (value) => Navigator.pop(context, value),
      ),
    );
    if (mounted && selection != null) {
      setState(() {
        _selection = selection.selection;
        _type = selection.type;
        _deliverable = selection.deliverable;
        _sortByTitle = selection.sortByTitle;
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
    pushLibraryPage<void>(
      context,
      page: 'search',
      builder: (_) => LibrarySearchScreen(
        browse: home ? LibraryBrowse.projects : _browse,
        type: home ? '' : _type,
        selection: home ? const LibraryFilterSelection() : _selection,
        years: years,
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
      canPop: home || GoRouter.maybeOf(context) != null,
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
                                'Back',
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
                    if (_view == _LibraryView.directory) ...[
                      const SizedBox(height: 7),
                      Text(
                        'Explore a topic or choose a kind of output.',
                        style: caption,
                      ),
                    ],
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
                  const SizedBox(height: 16),
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
    final filterCount = LibraryCollectionFilters(
      selection: _selection,
      type: _type,
      deliverable: _deliverable,
      sortByTitle: _sortByTitle,
    ).count;
    final filtered = !_selection.isEmpty;
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              '${state.catalog ? state.counts['total'] ?? 0 : projects?.length ?? entries.length} ${projects != null ? 'projects' : 'outputs'}',
              style: DefensysTokens.caption.copyWith(
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ),
          Tooltip(
            message: _grid ? 'Compact list' : 'Project covers',
            child: ShadButton.ghost(
              width: 44,
              height: 44,
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => _grid = !_grid),
              child: Icon(
                _grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ShadButton.outline(
            height: 44,
            leading: const Icon(Icons.tune_rounded, size: 17),
            onPressed: () => _filters(all),
            child: Text(
              filterCount == 0 ? 'Filters' : 'Filters ($filterCount)',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
      if (_deliverable.isNotEmpty || _sortByTitle) ...[
        const SizedBox(height: 6),
        Text(
          [
            if (_deliverable.isNotEmpty)
              LibraryDeliverable.group(all)
                      .where((item) => item.key == _deliverable)
                      .firstOrNull
                      ?.displayLabel(LibraryDeliverable.group(all)) ??
                  'Selected deliverable',
            if (_sortByTitle) 'Title A?Z',
          ].join(' ? '),
          style: DefensysTokens.caption.copyWith(
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ],
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
