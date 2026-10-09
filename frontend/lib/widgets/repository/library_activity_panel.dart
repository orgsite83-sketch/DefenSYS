import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/repository_library.dart';
import '../../screens/app/student/repository/repository_entry_view.dart';
import '../../screens/app/student/repository/library_project_screen.dart';
import '../../services/repository_review_provider.dart';
import '../../theme/defensys_tokens.dart';
import '../../toasts/feedback_toast.dart';
import 'library_components.dart';

class LibraryActivityPanel extends ConsumerStatefulWidget {
  const LibraryActivityPanel({super.key});
  @override
  ConsumerState<LibraryActivityPanel> createState() =>
      _LibraryActivityPanelState();
}

class _LibraryActivityPanelState extends ConsumerState<LibraryActivityPanel> {
  String _tab = 'Recent';
  bool _clearing = false;
  String _time(String? value) {
    final date = DateTime.tryParse(value ?? '');
    return date == null
        ? ''
        : DateFormat('MMM d, h:mm a').format(date.toLocal());
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    final success = await ref
        .read(repositoryReviewServiceProvider)
        .clearReadingHistory();
    if (!mounted) return;
    setState(() => _clearing = false);
    if (!success) {
      showErrorToast(context, 'Could not clear your reading history.');
    }
  }

  void _open(VaultEntry entry) {
    if (entry.documentKind == 'project' && entry.projectEntries.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LibraryProjectScreen(
            project: LibraryProject(entry.groupingKey, entry.projectEntries),
          ),
        ),
      );
    } else {
      showRepositoryEntryDetails(context, ref, entry);
    }
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Builder(builder: (context) => _build(context)),
  );

  Widget _build(BuildContext context) {
    final data = ref.watch(repositoryLibraryActivityProvider);
    final colors = Theme.of(context).colorScheme;
    return ShadCard(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      shadows: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_library_outlined,
                color: DefensysTokens.maroonTextOf(context),
                size: 21,
              ),
              const SizedBox(width: 9),
              const Text(
                'My library',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Your reading and saved project outputs.',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          ShadTabs<String>(
            value: _tab,
            gap: 0,
            onChanged: (tab) => setState(() => _tab = tab),
            tabs: [
              for (final tab in ['Recent', 'Saved', 'Activity'])
                ShadTab(
                  value: tab,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  child: Text(tab, style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 15),
          data.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Column(
              children: [
                const Text('Could not load your library activity.'),
                ShadButton.ghost(
                  onPressed: () =>
                      ref.invalidate(repositoryLibraryActivityProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
            data: (payload) {
              final entries = _tab == 'Saved' ? payload.saved : payload.recent;
              if (_tab == 'Activity') {
                return Column(
                  children: [
                    if (payload.activity.isEmpty)
                      const LibraryEmpty(
                        title: 'No library activity yet',
                        message:
                            'Your saved outputs, ratings, and remarks appear here.',
                      ),
                    for (final item in payload.activity) _activityItem(item),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _tab == 'Saved' ? 'Saved outputs' : 'Recently opened',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_tab == 'Recent' && entries.isNotEmpty)
                        ShadButton.ghost(
                          height: 34,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          onPressed: _clearing ? null : _clear,
                          child: Text(
                            _clearing ? 'Clearing…' : 'Clear history',
                          ),
                        ),
                    ],
                  ),
                  if (entries.isEmpty)
                    LibraryEmpty(
                      title: _tab == 'Saved'
                          ? 'Keep an output for later'
                          : 'Your reading history is clear',
                      message: _tab == 'Saved'
                          ? 'Save a document, poster, or video from its details.'
                          : 'Documents, posters, and videos you open appear here.',
                    ),
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          libraryOutputIcon(entry),
                          color: DefensysTokens.maroonTextOf(context),
                        ),
                        title: Text(
                          entry.displayTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          '${entry.outputLabel} · ${entry.teamName}${_tab == 'Recent' ? '\n${_time(entry.lastOpenedAt)}' : ''}',
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () => _open(entry),
                      ),
                    ),
                ],
              );
            },
          ),
          if (_tab == 'Recent')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 14,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Only you can see this history.',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _activityItem(Map<String, dynamic> item) {
    final raw = item['entry'];
    if (raw is! Map) return const SizedBox.shrink();
    final entry = VaultEntry.fromJson(Map<String, dynamic>.from(raw));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history, size: 19),
      title: Text(
        item['action']?.toString() ?? 'Library activity',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      subtitle: Text(
        '${entry.displayTitle}\n${_time(item['timestamp']?.toString())}',
      ),
      onTap: () => _open(entry),
    );
  }
}
