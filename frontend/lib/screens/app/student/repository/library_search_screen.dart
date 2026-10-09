import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../models/repository_library.dart';
import '../../../../services/repository_review_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/repository/library_components.dart';
import '../../../../widgets/shadcn/defensys_workflow_widgets.dart';
import 'library_project_screen.dart';
import 'repository_entry_view.dart';

class LibrarySearchScreen extends ConsumerStatefulWidget {
  const LibrarySearchScreen({
    super.key,
    this.browse = LibraryBrowse.projects,
    this.type = '',
    this.year = '',
    this.years = const [],
  });
  final LibraryBrowse browse;
  final String type, year;
  final List<String> years;
  @override
  ConsumerState<LibrarySearchScreen> createState() =>
      _LibrarySearchScreenState();
}

class _LibrarySearchScreenState extends ConsumerState<LibrarySearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  late String _type, _year;
  late LibraryBrowse _browse;
  late bool _projects;
  bool _filters = false;
  @override
  void initState() {
    super.initState();
    _browse = widget.browse;
    _projects = _browse == LibraryBrowse.projects;
    _type = widget.type;
    _year = widget.year;
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

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Builder(builder: (context) => _build(context)),
  );

  Widget _build(BuildContext context) {
    final key = (
      search: _query,
      type: _type,
      year: _year,
      documentKind: _browse.value,
    );
    final result = ref.watch(repositoryLibrarySearchProvider(key));
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
                      onPressed: () => setState(() => _filters = !_filters),
                      leading: const Icon(Icons.tune, size: 16),
                      child: const Text('Filter'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LibraryBrowsePicker(
                  value: _browse,
                  onChanged: (value) => setState(() {
                    _browse = value;
                    _projects = value == LibraryBrowse.projects;
                  }),
                ),
                if (_filters) ...[
                  const SizedBox(height: 12),
                  LibraryCategoryPicker(
                    value: _type,
                    onChanged: (value) => setState(() => _type = value),
                  ),
                  const SizedBox(height: 12),
                  WorkflowSelect(
                    label: 'School year',
                    value: _year,
                    searchable: false,
                    options: {
                      '': 'All years',
                      for (final year in widget.years) year: 'SY $year',
                      if (_year.isNotEmpty) _year: 'SY $_year',
                    },
                    onChanged: (value) => setState(() => _year = value),
                  ),
                ],
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
