import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../models/repository_library.dart';
import '../../../../models/library_filters.dart';
import '../../../../models/library_topics.dart';
import '../../../../widgets/repository/library_hero.dart';
import '../../../../widgets/repository/library_topic_discovery.dart';
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

class RepositoryTab extends ConsumerStatefulWidget {
  const RepositoryTab({super.key});
  @override
  ConsumerState<RepositoryTab> createState() => _RepositoryTabState();
}

class _RepositoryTabState extends ConsumerState<RepositoryTab> {
  final _scroll = ScrollController();
  _LibraryView _view = _LibraryView.home;
  LibraryBrowse _browse = LibraryBrowse.projects;
  String _type = '';
  LibraryFilterSelection _selection = const LibraryFilterSelection();
  bool _grid = true;

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

  Future<void> _refresh() =>
      ref.read(repositoryProvider.notifier).fetchForStudent(search: '');

  void _navigate(_LibraryView view) {
    setState(() => _view = view);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _collection({
    LibraryBrowse browse = LibraryBrowse.projects,
    String type = '',
    LibraryTag? subject,
  }) {
    _browse = browse;
    _type = type;
    _selection = subject == null
        ? const LibraryFilterSelection()
        : const LibraryFilterSelection().toggle(
            LibraryFilterGroup.subject,
            subject,
          );
    _navigate(_LibraryView.collection);
  }

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

  Future<void> _myShelf() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text('My reading shelf'),
            backgroundColor: DefensysTokens.maroon,
            foregroundColor: Colors.white,
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
          browse: home ? LibraryBrowse.outputs : _browse,
          type: home ? '' : _type,
          selection: home ? const LibraryFilterSelection() : _selection,
          years: years,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
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
    for (final topic in LibraryTopicCollection.group(all))
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Icon(
          Icons.topic_outlined,
          color: DefensysTokens.maroonTextOf(context),
        ),
        title: Text(topic.title, style: DefensysTokens.body),
        subtitle: Text(
          '${topic.projects.length} projects · ${topic.entries.length} outputs',
          style: DefensysTokens.caption,
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () =>
            _collection(browse: LibraryBrowse.outputs, subject: topic.tag),
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

  List<Widget> _home(List<VaultEntry> all, bool unavailable) {
    final projects = LibraryProject.group(all);
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final type in ['capstone', 'pit']) ...[
            if (type == 'pit') const SizedBox(width: 12),
            Expanded(
              child: LibraryCollectionCard(
                type: type,
                count: unavailable && all.isEmpty
                    ? null
                    : projects
                          .where(
                            (project) => project.representative.type == type,
                          )
                          .length,
                onTap: () => _collection(type: type),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 22),
      Row(
        children: [
          Expanded(child: Text('Explore by topic', style: _sectionStyle)),
          ShadButton.ghost(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: () => _navigate(_LibraryView.directory),
            trailing: const Icon(Icons.arrow_forward, size: 15),
            child: const Text('Browse all', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
      if (unavailable && all.isEmpty)
        const LibraryShelfLoading()
      else if (all.isEmpty)
        const LibraryEmpty(
          title: 'The collection is growing',
          message:
              'Published research will appear here when it becomes available.',
        )
      else
        for (final topic in LibraryTopicCollection.group(all))
          LibraryTopicRow(
            key: ValueKey('library-topic-${topic.tag.id}'),
            topic: topic,
            onViewAll: () =>
                _collection(browse: LibraryBrowse.outputs, subject: topic.tag),
            onOpen: _open,
            onProject: _project,
            onDetails: (entry) =>
                showRepositoryEntryDetails(context, ref, entry),
          ),
    ];
  }

  List<Widget> _collectionBody(List<VaultEntry> all, bool loading) {
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
    final entries = all.where(matches).toList();
    // A matching project's detail retains every published output, not just the
    // files that happened to match its topic filter.
    final projects = _browse == LibraryBrowse.projects
        ? LibraryProject.group(
            all,
          ).where((project) => project.entries.any(matches)).toList()
        : null;
    final filtered = !_selection.isEmpty;
    return [
      Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${projects?.length ?? entries.length} ${projects != null ? 'projects' : 'outputs'}',
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
          onChanged: (value) => setState(() => _selection = value),
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
