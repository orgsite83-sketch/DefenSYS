import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../models/repository_library.dart';
import '../../../../models/library_filters.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../services/repository_review_provider.dart';
import '../../../../services/repository_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/repository/library_components.dart';
import '../../../../widgets/repository/library_discovery.dart';
import 'library_project_screen.dart';
import 'repository_entry_view.dart';

class LibrarySearchScreen extends ConsumerStatefulWidget {
  const LibrarySearchScreen({
    super.key,
    this.browse = LibraryBrowse.projects,
    this.type = '',
    this.selection = const LibraryFilterSelection(),
    this.years = const [],
  });
  final LibraryBrowse browse;
  final String type;
  final LibraryFilterSelection selection;
  final List<String> years;
  @override
  ConsumerState<LibrarySearchScreen> createState() =>
      _LibrarySearchScreenState();
}

class _LibrarySearchScreenState extends ConsumerState<LibrarySearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  late String _type;
  late LibraryFilterSelection _selection;
  bool _loadingFilters = false;
  late LibraryBrowse _browse;
  late bool _projects;
  @override
  void initState() {
    super.initState();
    _browse = widget.browse;
    _projects = _browse == LibraryBrowse.projects;
    _type = widget.type;
    _selection = widget.selection;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  List<VaultEntry> get _all =>
      ref.read(repositoryProvider).entries.map(VaultEntry.fromJson).toList();

  LibrarySearchQuery _key({bool facetSource = false}) => (
    search: _query,
    type: _type,
    year: facetSource ? '' : _selection.year,
    documentKind: _browse.value,
    subject: facetSource ? '' : _selection.query(LibraryFilterGroup.subject),
    technology: facetSource
        ? ''
        : _selection.query(LibraryFilterGroup.technology),
    language: facetSource ? '' : _selection.query(LibraryFilterGroup.language),
  );

  Future<void> _filter() async {
    setState(() => _loadingFilters = true);
    final baseKey = _key(facetSource: true);
    List<VaultEntry> entries;
    try {
      entries = _query.isEmpty && _all.isNotEmpty
          ? _all
                .where(
                  (entry) =>
                      (_type.isEmpty || entry.type == _type) &&
                      _browse.matches(entry),
                )
                .toList()
          : await ref.read(repositoryLibrarySearchProvider(baseKey).future);
    } catch (_) {
      if (mounted) {
        showErrorToast(
          context,
          'Could not load the available filters. Please try again.',
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _loadingFilters = false);
    }
    if (!mounted || baseKey != _key(facetSource: true)) return;
    final selection = await showLibraryPanel<LibraryFilterSelection>(
      context,
      title: 'Refine this shelf',
      desktopDialog: true,
      builder: (context) => LibraryFilterPanel(
        entries: entries,
        selection: _selection,
        onApply: (value) => Navigator.pop(context, value),
      ),
    );
    if (mounted && selection != null) setState(() => _selection = selection);
  }

  Future<void> _shelves() async {
    final selection = await showLibraryPanel<LibraryBrowse>(
      context,
      title: 'Browse shelves',
      builder: (context) => SingleChildScrollView(
        child: LibraryShelfDirectory(
          entries: _all,
          onSelected: (shelf) => Navigator.pop(context, shelf),
        ),
      ),
    );
    if (mounted && selection != null) {
      setState(() {
        _browse = selection;
        _projects = selection == LibraryBrowse.projects;
      });
    }
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Builder(builder: (context) => _build(context)),
  );

  Widget _build(BuildContext context) {
    final key = _key();
    final result = ref
        .watch(repositoryLibrarySearchProvider(key))
        .whenData((entries) => entries.where(_selection.matches).toList());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search library'),
        backgroundColor: DefensysTokens.maroon,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShadInput(
                  controller: _controller,
                  autofocus: true,
                  onChanged: _search,
                  placeholder: const Text('Title, team, or topic'),
                  leading: const Icon(Icons.search, size: 18),
                  trailing: ShadButton.ghost(
                    width: 28,
                    height: 28,
                    padding: EdgeInsets.zero,
                    child: const Icon(Icons.close, size: 15),
                    onPressed: () {
                      _controller.clear();
                      _debounce?.cancel();
                      setState(() => _query = '');
                    },
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ShadTabs<bool>(
                        value: _projects,
                        gap: 0,
                        tabs: const [
                          ShadTab(value: true, child: Text('Projects')),
                          ShadTab(value: false, child: Text('Deliverables')),
                        ],
                        onChanged: (value) => setState(() => _projects = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                Row(
                  children: [
                    Expanded(
                      child: result.when(
                        data: (entries) => Text(
                          '${_projects ? LibraryProject.group(entries).length : entries.length} results',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        error: (_, _) => const Text('Search unavailable'),
                        loading: () => const Text('Searching…'),
                      ),
                    ),
                    ShadButton.outline(
                      enabled: !_loadingFilters,
                      onPressed: _loadingFilters ? null : _filter,
                      leading: const Icon(Icons.tune, size: 16),
                      child: Text(_loadingFilters ? 'Loading…' : 'Filter'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ShadButton.ghost(
                  leading: const Icon(Icons.menu_book_outlined, size: 17),
                  trailing: const Icon(Icons.chevron_right, size: 16),
                  onPressed: _shelves,
                  child: Text(_browse.label),
                ),
                const SizedBox(height: 8),
                LibraryCategoryPicker(
                  value: _type,
                  onChanged: (value) => setState(() => _type = value),
                ),
                if (!_selection.isEmpty)
                  LibraryActiveFilters(
                    selection: _selection,
                    entries: _all,
                    onChanged: (value) => setState(() => _selection = value),
                  ),
                const SizedBox(height: 20),
                result.when(
                  data: (entries) => entries.isEmpty
                      ? const LibraryEmpty(
                          title: 'No matching results',
                          message:
                              'Try a different topic, document stage, or school year.',
                        )
                      : LibraryResults(
                          entries: entries,
                          grid: true,
                          projects: _projects
                              ? LibraryProject.group(entries)
                              : null,
                          onOpen: (entry) =>
                              openRepositoryEntry(context, ref, entry),
                          onDetails: (entry) =>
                              showRepositoryEntryDetails(context, ref, entry),
                          onProject: (project) => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  LibraryProjectScreen(project: project),
                            ),
                          ),
                        ),
                  error: (_, _) => Column(
                    children: [
                      const LibraryEmpty(
                        title: 'Could not search the library',
                        message: 'Check your connection and try again.',
                      ),
                      ShadButton.outline(
                        onPressed: () => ref.invalidate(
                          repositoryLibrarySearchProvider(key),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.all(35),
                    child: Center(child: CircularProgressIndicator()),
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
