import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/utils/universal_file_viewer.dart';
import 'package:defensys/widgets/repository/deliverable_review_navigation.dart';
import 'faculty_requirement_actions.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/repository/deliverable_file_widgets.dart';
import 'package:defensys/widgets/repository/requirement_summary.dart';

/// One row per configured requirement, then the existing per-file review surface.
class FacultyRequirementsViewState {
  String filter = 'all';
  String? selected;
  String? selectedFileKey;
}

class FacultyRequirementsPane extends ConsumerStatefulWidget {
  const FacultyRequirementsPane({
    super.key,
    required this.items,
    required this.buildRequirement,
    this.viewState,
    this.defenseReadiness,
    this.stageLabel = '',
    this.programScope,
    this.onRequestRevision,
  });
  final List<Map<String, dynamic>> items;
  final Widget Function(Map<String, dynamic>) buildRequirement;
  final FacultyRequirementsViewState? viewState;
  final Widget? defenseReadiness;
  final String stageLabel;
  final String? programScope;
  final void Function(Map<String, dynamic> item, Map<String, dynamic> file)?
  onRequestRevision;

  @override
  ConsumerState<FacultyRequirementsPane> createState() =>
      _FacultyRequirementsPaneState();
}

class _FacultyRequirementsPaneState
    extends ConsumerState<FacultyRequirementsPane> {
  late final view = widget.viewState ?? FacultyRequirementsViewState();
  String get filter => view.filter;
  set filter(String value) => view.filter = value;
  String? get selected => view.selected;
  set selected(String? value) => view.selected = value;

  void open(Map<String, dynamic> item, {String? fileKey}) {
    final entries = deliverableReviewEntries(item);
    final first =
        entries.where((entry) {
          final file = entry['file'] as Map?;
          return file != null &&
              const {
                '',
                'pending',
                'pending_review',
                'submitted',
              }.contains('${file['status'] ?? ''}'.toLowerCase());
        }).firstOrNull ??
        entries.where((entry) => entry['file'] is Map).firstOrNull ??
        entries.firstOrNull;
    setState(() {
      selected = identity(item);
      view.selectedFileKey = fileKey ?? first?['key']?.toString();
    });
  }

  Widget requirementLink(Map<String, dynamic> item) => Text(
    '${item['label'] ?? item['name'] ?? 'Deliverable'}',
    key: ValueKey('requirement-link-${identity(item)}'),
    style: DefensysTokens.tableCell.copyWith(
      fontWeight: FontWeight.w600,
      color: DefensysTokens.textPrimaryOf(context),
    ),
  );

  Widget requirementRow(
    Map<String, dynamic> item, {
    required Widget child,
    required bool saving,
  }) => Semantics(
    button: true,
    child: InkWell(
      key: ValueKey('requirement-row-${identity(item)}'),
      onTap: saving ? null : () => open(item),
      hoverColor: DefensysTokens.surfaceHigherOf(context),
      focusColor: DefensysTokens.surfaceHigherOf(context),
      highlightColor: DefensysTokens.borderOf(context),
      child: child,
    ),
  );

  Widget moreActions(Map<String, dynamic> item, bool saving) {
    final currentFiles = ((item['submission'] as Map?)?['files'] as List? ?? [])
        .whereType<Map>()
        .where((file) => file['is_current'] != false)
        .toList();
    final files = !usesGroupedDocumentCard(item) && currentFiles.length > 1
        ? currentFiles.map((file) => <String, dynamic>{'file': file}).toList()
        : deliverableReviewEntries(
            item,
          ).where((entry) => entry['file'] is Map).toList();
    final single = files.length == 1
        ? Map<String, dynamic>.from(files.single['file'] as Map)
        : null;
    final summary = RequirementSummary(item);
    final user = ref.watch(authProvider).user;
    final faculty = user != null && user['role'] != 'student';
    final canReview = faculty && item['can_faculty_review'] == true;
    final status = '${single?['status'] ?? ''}';
    final post = group(item) == 'archive';
    final validTarget =
        !usesGroupedDocumentCard(item) ||
        single?['id'] is int && (single!['id'] as int) > 0;
    final canRequest =
        canReview &&
        single != null &&
        validTarget &&
        widget.onRequestRevision != null &&
        !(post && status == 'accepted') &&
        !const {
          'rejected',
          'Needs Revision',
          'needs_revision',
        }.contains(status);
    return FacultyRequirementActions(
      key: ValueKey('requirement-actions-${identity(item)}'),
      enabled: !saving,
      multipleFiles: files.length > 1,
      onReview: canReview && summary.pending > 0 ? () => open(item) : null,
      onViewFile: files.length > 1
          ? () => open(item)
          : single != null && '${single['file_url'] ?? ''}'.isNotEmpty
          ? () => viewFileInDialog(
              context: context,
              fileUrl: '${single['file_url']}',
              fileName: '${single['file_name'] ?? 'Document'}',
            )
          : null,
      onDetails: () {
        if (single == null) {
          open(item);
          return;
        }
        final submission = item['submission'] as Map? ?? {};
        showDeliverableFileDetails(
          context: context,
          label: '${item['label'] ?? item['name'] ?? 'Deliverable'}',
          stageLabel: widget.stageLabel,
          programScope:
              widget.programScope ??
              ref.read(capstoneDeliverablesProvider).scope,
          file: single,
          status: summary.status,
          uploader:
              (single['uploaded_by_name'] ?? submission['uploaded_by_name'])
                  ?.toString(),
        );
      },
      onRequestRevision: canRequest
          ? () => widget.onRequestRevision!(item, single)
          : null,
    );
  }

  String identity(Map item) =>
      '${item['id'] ?? item['deliverable_id'] ?? item['label']}';
  String group(Map item) =>
      item['type'] == 'post' || item['deliverable_type'] == 'post'
      ? 'archive'
      : item['requirement_timing'] == 'defense'
      ? 'defense'
      : 'required';

  String timingLabel(Map item) => switch (group(item)) {
    'archive' => 'Post-defense archive',
    'defense' => 'Before defense',
    _ => 'Before endorsement',
  };

  Widget timingCell(Map item) => Text(
    timingLabel(item),
    style: DefensysTokens.caption.copyWith(
      color: DefensysTokens.textSecondaryOf(context),
    ),
  );

  @override
  Widget build(BuildContext context) =>
      DefensysShadcnScope(child: Builder(builder: _buildPane));

  Widget _buildPane(BuildContext context) {
    final saving = ref.watch(capstoneDeliverablesProvider).isSaving;
    final active = widget.items
        .where((item) => identity(item) == selected)
        .firstOrNull;
    if (active != null) {
      final activeItemIndex = widget.items.indexOf(active);
      final entries = deliverableReviewEntries(active);
      var entryIndex = entries.indexWhere(
        (entry) => '${entry['key']}' == view.selectedFileKey,
      );
      if (entryIndex < 0) entryIndex = 0;
      final queue = [
        for (final (itemIndex, item) in widget.items.indexed)
          for (final (fileIndex, entry) in deliverableReviewEntries(
            item,
          ).indexed)
            if (entry['file'] is Map)
              {
                'item': item,
                'itemIndex': itemIndex,
                'fileIndex': fileIndex,
                'key': '${entry['key']}',
              },
      ];
      final previous = queue
          .where(
            (entry) =>
                (entry['itemIndex'] as int) < activeItemIndex ||
                entry['itemIndex'] == activeItemIndex &&
                    (entry['fileIndex'] as int) < entryIndex,
          )
          .lastOrNull;
      final next = queue
          .where(
            (entry) =>
                (entry['itemIndex'] as int) > activeItemIndex ||
                entry['itemIndex'] == activeItemIndex &&
                    (entry['fileIndex'] as int) > entryIndex,
          )
          .firstOrNull;
      final queueIndex = queue.indexWhere(
        (entry) =>
            entry['itemIndex'] == activeItemIndex &&
            entry['fileIndex'] == entryIndex,
      );
      void navigate(Map<String, Object?> entry) => open(
        entry['item'] as Map<String, dynamic>,
        fileKey: entry['key'] as String,
      );
      return DeliverableReviewNavigation(
        fileKey: entries.isEmpty ? null : '${entries[entryIndex]['key']}',
        onFileSelected: (key) => setState(() => view.selectedFileKey = key),
        onNextFile: next == null ? null : () => navigate(next),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton.ghost(
                size: ShadButtonSize.sm,
                enabled: !saving,
                onPressed: saving
                    ? null
                    : () => setState(() => selected = null),
                leading: const Icon(Icons.arrow_back, size: 16),
                child: const Text('All deliverables'),
              ),
            ),
            const SizedBox(height: 8),
            if (group(active) == 'defense' && widget.defenseReadiness != null)
              widget.defenseReadiness!,
            widget.buildRequirement(active),
            const SizedBox(height: 12),
            if (queue.length > 1)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    queueIndex < 0
                        ? 'No file uploaded'
                        : 'File ${queueIndex + 1} of ${queue.length}',
                    style: DefensysTokens.caption.copyWith(
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShadButton.ghost(
                        size: ShadButtonSize.sm,
                        enabled: !saving && previous != null,
                        onPressed: saving || previous == null
                            ? null
                            : () => navigate(previous),
                        child: const Text('Previous'),
                      ),
                      ShadButton.outline(
                        size: ShadButtonSize.sm,
                        enabled: !saving && next != null,
                        onPressed: saving || next == null
                            ? null
                            : () => navigate(next),
                        child: const Text('Next file'),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      );
    }
    final rows = widget.items.where((item) {
      final summary = RequirementSummary(item);
      return filter == 'all' ||
          (filter == 'missing' ? summary.missing > 0 : summary.needsAttention);
    }).toList();

    Widget summaryCell(Map<String, dynamic> item) {
      final summary = RequirementSummary(item);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DeliverableStatusBadge(label: summary.status, tone: summary.tone),
          if (summary.detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                summary.detail,
                style: TextStyle(
                  fontSize: 11,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              '${widget.items.length} deliverables',
              style: DefensysTokens.caption.copyWith(
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            ShadSelect<String>(
              key: ValueKey('requirements-filter-$filter'),
              initialValue: filter,
              minWidth: 190,
              maxWidth: 230,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              options: [
                for (final entry in {
                  'all': 'All deliverables (${widget.items.length})',
                  'attention':
                      'Needs attention (${widget.items.where((item) => RequirementSummary(item).needsAttention).length})',
                  'missing':
                      'Missing files (${widget.items.where((item) => RequirementSummary(item).missing > 0).length})',
                }.entries)
                  ShadOption(value: entry.key, child: Text(entry.value)),
              ],
              selectedOptionBuilder: (context, value) => Text(switch (value) {
                'attention' => 'Needs attention (${rows.length})',
                'missing' => 'Missing files (${rows.length})',
                _ => 'All deliverables (${widget.items.length})',
              }, style: const TextStyle(fontSize: 12)),
              onChanged: (value) {
                if (value != null) setState(() => filter = value);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No deliverables match this view.',
              style: TextStyle(color: DefensysTokens.textSecondaryOf(context)),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 640) {
                return Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      for (final item in rows)
                        requirementRow(
                          item,
                          saving: saving,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: DefensysTokens.borderOf(context),
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          requirementLink(item),
                                          const SizedBox(height: 3),
                                          timingCell(item),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    moreActions(item, saving),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: summaryCell(item)),
                                    const SizedBox(width: 12),
                                    Text(
                                      '${RequirementSummary(item).progress} uploaded',
                                      style: DefensysTokens.caption.copyWith(
                                        color: DefensysTokens.textSecondaryOf(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }
              Widget cell(Widget child) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: child,
              );
              Widget desktopRow(List<Widget> cells) => Row(
                children: [
                  Expanded(flex: 30, child: cell(cells[0])),
                  Expanded(flex: 18, child: cell(cells[1])),
                  SizedBox(width: 86, child: cell(cells[2])),
                  Expanded(flex: 24, child: cell(cells[3])),
                  SizedBox(width: 64, child: cell(cells[4])),
                ],
              );
              return Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    ColoredBox(
                      color: DefensysTokens.surfaceHigherOf(context),
                      child: desktopRow([
                        for (final title in [
                          'Deliverable',
                          'Timing',
                          'Uploaded',
                          'Status',
                          'Action',
                        ])
                          Text(
                            title,
                            style: DefensysTokens.tableHeader.copyWith(
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                      ]),
                    ),
                    for (final item in rows)
                      requirementRow(
                        item,
                        saving: saving,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: DefensysTokens.borderOf(context),
                              ),
                            ),
                          ),
                          child: desktopRow([
                            requirementLink(item),
                            timingCell(item),
                            Text(
                              RequirementSummary(item).progress,
                              style: DefensysTokens.caption.copyWith(
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                            ),
                            summaryCell(item),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: moreActions(item, saving),
                            ),
                          ]),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
