import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/admin/panelist_requests_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';

class PanelistRequestsView extends ConsumerStatefulWidget {
  const PanelistRequestsView({
    super.key,
    required this.reviewed,
    required this.onOpen,
  });
  final bool reviewed;
  final ValueChanged<int> onOpen;
  @override
  ConsumerState<PanelistRequestsView> createState() =>
      _PanelistRequestsViewState();
}

class _PanelistRequestsViewState extends ConsumerState<PanelistRequestsView> {
  Timer? _debounce;
  String get _selection => widget.reviewed ? 'reviewed' : 'pending';
  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        ref
            .read(panelistRequestsProvider(_selection).notifier)
            .fetch(search: query.trim());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(panelistRequestsProvider(_selection));
    final secondary = DefensysTokens.textSecondaryOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShadInput(
          key: ValueKey('request-search-$_selection'),
          placeholder: const Text('Search faculty or requester'),
          leading: const Icon(LucideIcons.search, size: 16),
          onChanged: _search,
        ),
        const SizedBox(height: 14),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: DefensysTokens.danger,
                    ),
                  ),
                ),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () => ref
                      .read(panelistRequestsProvider(_selection).notifier)
                      .fetch(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        Expanded(
          child: state.loading && state.items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    if (state.items.isEmpty &&
                        state.error == null &&
                        !state.loading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 44),
                        child: Column(
                          children: [
                            Icon(
                              widget.reviewed
                                  ? LucideIcons.history
                                  : LucideIcons.inbox,
                              size: 28,
                              color: secondary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              state.search.isNotEmpty
                                  ? 'No matching requests'
                                  : widget.reviewed
                                  ? 'No reviewed requests yet'
                                  : 'All requests reviewed',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.reviewed
                                  ? 'Approval and decline decisions appear here.'
                                  : 'New PIT lead nominations appear here.',
                              style: TextStyle(fontSize: 12, color: secondary),
                            ),
                          ],
                        ),
                      ),
                    for (final item in state.items)
                      Container(
                        key: ValueKey('panelist-request-${item['id']}'),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: DefensysTokens.borderOf(context),
                            ),
                          ),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final status =
                                item['status']?.toString() ?? 'pending';
                            final details = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['faculty_name']?.toString() ??
                                      'Faculty member',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: DefensysTokens.textPrimaryOf(
                                      context,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'Requested by ${item['requested_by_name']} · ${item['pit_year']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: secondary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  (widget.reviewed
                                              ? item['review_note']
                                              : item['reason'])
                                          ?.toString() ??
                                      '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.5,
                                    color: secondary,
                                  ),
                                ),
                              ],
                            );
                            final actions = Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                ShadBadge.outline(
                                  child: Text(
                                    status == 'pending'
                                        ? 'Awaiting approval'
                                        : status == 'approved'
                                        ? 'Approved'
                                        : 'Declined',
                                  ),
                                ),
                                ShadButton.outline(
                                  size: ShadButtonSize.sm,
                                  onPressed: () => widget.onOpen(
                                    (item['id'] as num).toInt(),
                                  ),
                                  trailing: const Icon(
                                    LucideIcons.arrowRight,
                                    size: 14,
                                  ),
                                  child: Text(
                                    status == 'pending'
                                        ? 'Review request'
                                        : 'View decision',
                                  ),
                                ),
                              ],
                            );
                            return constraints.maxWidth < 680
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      details,
                                      const SizedBox(height: 12),
                                      actions,
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(child: details),
                                      const SizedBox(width: 20),
                                      actions,
                                    ],
                                  );
                          },
                        ),
                      ),
                    if (state.nextPage != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: ShadButton.ghost(
                          enabled: !state.loadingMore,
                          onPressed: state.loadingMore
                              ? null
                              : () => ref
                                    .read(
                                      panelistRequestsProvider(
                                        _selection,
                                      ).notifier,
                                    )
                                    .fetch(more: true),
                          child: Text(
                            state.loadingMore
                                ? 'Loading…'
                                : 'Load more requests',
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        if (state.total > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${state.items.length} of ${state.total} requests',
              style: TextStyle(fontSize: 11, color: secondary),
            ),
          ),
      ],
    );
  }
}
