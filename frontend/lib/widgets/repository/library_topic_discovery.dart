import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/library_topics.dart';
import '../../models/repository_library.dart';
import '../../theme/defensys_tokens.dart';
import 'library_components.dart';

class LibraryTopicRow extends StatefulWidget {
  const LibraryTopicRow({
    super.key,
    required this.topic,
    required this.onViewAll,
    required this.onOpen,
    required this.onProject,
    required this.onDetails,
  });
  final LibraryTopicCollection topic;
  final VoidCallback onViewAll;
  final ValueChanged<VaultEntry> onOpen, onDetails;
  final ValueChanged<LibraryProject> onProject;
  @override
  State<LibraryTopicRow> createState() => _LibraryTopicRowState();
}

class _LibraryTopicRowState extends State<LibraryTopicRow> {
  final _scroll = ScrollController();
  bool _back = false, _next = false;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_sync);
  }

  void _sync() {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final back = _scroll.offset > 1;
    final next = _scroll.offset < _scroll.position.maxScrollExtent - 1;
    if (mounted && (back != _back || next != _next)) {
      setState(() {
        _back = back;
        _next = next;
      });
    }
  }

  void _move(int direction) {
    if (!_scroll.hasClients) return;
    final delta = _scroll.position.viewportDimension * .88 * direction;
    _scroll.animateTo(
      (_scroll.offset + delta).clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.topic.previewEntries;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.topic.title,
                  style: DefensysTokens.sectionTitle.copyWith(
                    color: colors.onSurface,
                  ),
                ),
              ),
              ShadButton.ghost(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: widget.onViewAll,
                trailing: const Icon(Icons.arrow_forward, size: 15),
                child: Text(
                  'View all',
                  style: DefensysTokens.caption.copyWith(
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  ((constraints.maxWidth - 14) /
                          (constraints.maxWidth < 650 ? 2.12 : 4.15))
                      .clamp(122.0, 226.0);
              final height = (width / .76).clamp(156.0, 240.0);
              final textExtra =
                  (MediaQuery.textScalerOf(context).scale(14) / 14 - 1).clamp(
                    0.0,
                    2.0,
                  ) *
                  110;
              return NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _sync();
                  });
                  return false;
                },
                child: SizedBox(
                  height: height + 132 + textExtra,
                  child: ListView.separated(
                    key: PageStorageKey('topic-${widget.topic.tag.id}'),
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final project = widget.topic.projects.firstWhere(
                        (project) => project.key == entry.groupingKey,
                      );
                      return SizedBox(
                        width: width,
                        child: LibraryDiscoveryOutput(
                          entry: entry,
                          previewHeight: height,
                          onOpen: () => widget.onOpen(entry),
                          onProject: () => widget.onProject(project),
                          onDetails: () => widget.onDetails(entry),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.topic.projects.length} ${widget.topic.projects.length == 1 ? 'project' : 'projects'} · ${widget.topic.entries.length} outputs',
                  style: DefensysTokens.caption.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Previous ${widget.topic.title} outputs',
                onPressed: _back ? () => _move(-1) : null,
                icon: const Icon(Icons.chevron_left, size: 21),
              ),
              IconButton(
                tooltip: 'Next ${widget.topic.title} outputs',
                onPressed: _next ? () => _move(1) : null,
                icon: const Icon(Icons.chevron_right, size: 21),
              ),
            ],
          ),
          Divider(color: DefensysTokens.borderOf(context)),
        ],
      ),
    );
  }
}

class LibraryDiscoveryOutput extends StatelessWidget {
  const LibraryDiscoveryOutput({
    super.key,
    required this.entry,
    required this.previewHeight,
    required this.onOpen,
    required this.onProject,
    required this.onDetails,
  });
  final VaultEntry entry;
  final double previewHeight;
  final VoidCallback onOpen, onProject, onDetails;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: '${entry.openLabel}: ${entry.displayTitle}',
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: previewHeight,
                  child: LibraryCover(entry: entry),
                ),
                const SizedBox(height: 8),
                Text(
                  entry.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DefensysTokens.body.copyWith(
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${entry.outputLabel} · ${entry.extension.toUpperCase()}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DefensysTokens.caption.copyWith(
            fontSize: 11,
            color: colors.onSurfaceVariant,
          ),
        ),
        Text(
          entry.teamName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DefensysTokens.caption.copyWith(
            fontSize: 11,
            color: colors.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ShadButton.ghost(
                  height: 40,
                  padding: EdgeInsets.zero,
                  onPressed: onProject,
                  child: Text(
                    'View project',
                    style: DefensysTokens.caption.copyWith(
                      color: DefensysTokens.maroonTextOf(context),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Output details',
              onPressed: onDetails,
              icon: const Icon(Icons.more_horiz, size: 18),
            ),
          ],
        ),
      ],
    );
  }
}
