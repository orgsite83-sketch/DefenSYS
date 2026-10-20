import 'package:flutter/material.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/widgets/repository/deliverable_file_widgets.dart';
import 'package:defensys/widgets/repository/requirement_summary.dart';

/// One row per configured requirement, then the existing per-file review surface.
class FacultyRequirementsViewState {
  String filter = 'all';
  String timing = 'required';
  String? selected;
  int page = 0;
}

class FacultyRequirementsPane extends StatefulWidget {
  const FacultyRequirementsPane({
    super.key,
    required this.items,
    required this.buildRequirement,
    this.viewState,
    this.defenseReadiness,
  });
  final List<Map<String, dynamic>> items;
  final Widget Function(Map<String, dynamic>) buildRequirement;
  final FacultyRequirementsViewState? viewState;
  final Widget? defenseReadiness;

  @override
  State<FacultyRequirementsPane> createState() =>
      _FacultyRequirementsPaneState();
}

class _FacultyRequirementsPaneState extends State<FacultyRequirementsPane> {
  late final view = widget.viewState ?? FacultyRequirementsViewState();
  String get filter => view.filter;
  set filter(String value) => view.filter = value;
  String get timing => view.timing;
  set timing(String value) => view.timing = value;
  String? get selected => view.selected;
  set selected(String? value) => view.selected = value;
  int get page => view.page;
  set page(int value) => view.page = value;
  static const pageSize = 8;

  String identity(Map item) =>
      '${item['id'] ?? item['deliverable_id'] ?? item['label']}';
  String group(Map item) =>
      item['type'] == 'post' || item['deliverable_type'] == 'post'
      ? 'archive'
      : item['requirement_timing'] == 'defense'
      ? 'defense'
      : 'required';

  Widget choice(String label, bool active, VoidCallback action) =>
      ShadButton.secondary(
        size: ShadButtonSize.sm,
        onPressed: action,
        backgroundColor: active
            ? DefensysTokens.surfaceHigherOf(context)
            : Colors.transparent,
        decoration: ShadDecoration(
          border: ShadBorder.all(
            color: active
                ? DefensysTokens.borderOf(context)
                : Colors.transparent,
            radius: BorderRadius.circular(6),
          ),
        ),
        child: Text(label),
      );

  @override
  Widget build(BuildContext context) =>
      DefensysShadcnScope(child: Builder(builder: _buildPane));

  Widget _buildPane(BuildContext context) {
    final active = widget.items
        .where((item) => identity(item) == selected)
        .firstOrNull;
    if (active != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.ghost(
              size: ShadButtonSize.sm,
              onPressed: () => setState(() => selected = null),
              leading: const Icon(Icons.arrow_back, size: 16),
              child: const Text('All deliverables'),
            ),
          ),
          const SizedBox(height: 8),
          widget.buildRequirement(active),
        ],
      );
    }
    final scoped = widget.items.where((item) => group(item) == timing).toList();
    final visible = scoped.where((item) {
      final summary = RequirementSummary(item);
      return filter == 'all' ||
          (filter == 'missing' ? summary.missing > 0 : summary.needsAttention);
    }).toList();
    final pages = (visible.length / pageSize).ceil().clamp(1, 100000);
    final effectivePage = page.clamp(0, pages - 1);
    final rows = visible.skip(effectivePage * pageSize).take(pageSize).toList();
    void open(Map<String, dynamic> item) {
      setState(() => selected = identity(item));
    }

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
        if (widget.items.any((item) => group(item) != 'required')) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in const {
                'required': 'Before endorsement',
                'defense': 'Before defense',
                'archive': 'Post-defense archive',
              }.entries)
                if (entry.key == 'required' ||
                    widget.items.any((item) => group(item) == entry.key))
                  choice(
                    entry.value,
                    timing == entry.key,
                    () => setState(() {
                      timing = entry.key;
                      page = 0;
                      filter = 'all';
                    }),
                  ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in {
              'all': 'All (${scoped.length})',
              'attention':
                  'Needs attention (${scoped.where((item) => RequirementSummary(item).needsAttention).length})',
              'missing':
                  'Missing files (${scoped.where((item) => RequirementSummary(item).missing > 0).length})',
            }.entries)
              choice(
                entry.value,
                filter == entry.key,
                () => setState(() {
                  filter = entry.key;
                  page = 0;
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (timing == 'defense' && widget.defenseReadiness != null) ...[
          widget.defenseReadiness!,
          const SizedBox(height: 12),
        ],
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
              if (constraints.maxWidth < 540) {
                return Column(
                  children: [
                    for (final item in rows)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
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
                            Text(
                              '${item['label'] ?? item['name'] ?? 'Deliverable'}',
                              style: DefensysTokens.body.copyWith(
                                color: DefensysTokens.textPrimaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${RequirementSummary(item).progress} uploaded',
                              style: DefensysTokens.caption.copyWith(
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 6),
                            summaryCell(item),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ShadButton.outline(
                                size: ShadButtonSize.sm,
                                width: 80,
                                onPressed: () => open(item),
                                child: const Text(
                                  'Open',
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              }
              Widget cell(Widget child) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: child,
              );
              return Table(
                columnWidths: const {
                  0: FlexColumnWidth(3),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(2.6),
                  3: FixedColumnWidth(112),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder(
                  horizontalInside: BorderSide(
                    color: DefensysTokens.borderOf(context),
                  ),
                ),
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: DefensysTokens.surfaceHigherOf(context),
                    ),
                    children: [
                      for (final title in [
                        'Deliverable',
                        'Uploaded',
                        'Status',
                        'Action',
                      ])
                        cell(
                          Text(
                            title,
                            style: DefensysTokens.tableHeader.copyWith(
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (final item in rows)
                    TableRow(
                      children: [
                        cell(
                          Text(
                            '${item['label'] ?? item['name'] ?? 'Deliverable'}',
                            style: DefensysTokens.tableCell.copyWith(
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                        ),
                        cell(
                          Text(
                            RequirementSummary(item).progress,
                            style: DefensysTokens.caption.copyWith(
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ),
                        cell(summaryCell(item)),
                        cell(
                          ShadButton.outline(
                            size: ShadButtonSize.sm,
                            width: 80,
                            onPressed: () => open(item),
                            child: const Text(
                              'Open',
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        if (pages > 1)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${effectivePage + 1} / $pages',
                  style: DefensysTokens.caption.copyWith(
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  enabled: effectivePage > 0,
                  onPressed: effectivePage == 0
                      ? null
                      : () => setState(() => page = effectivePage - 1),
                  child: const Text('Previous'),
                ),
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  enabled: effectivePage + 1 < pages,
                  onPressed: effectivePage + 1 >= pages
                      ? null
                      : () => setState(() => page = effectivePage + 1),
                  child: const Text('Next'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
