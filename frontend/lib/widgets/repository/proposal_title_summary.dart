import 'package:flutter/material.dart';
import '../../theme/defensys_tokens.dart';
import 'shared_concept_review.dart';
import '../../models/team_workflow_status.dart';
import 'workflow_status_style.dart';

bool hasOpenConceptProposals(Map? workflow) =>
    workflow != null &&
    workflow['enabled'] != false &&
    conceptRows(workflow['concepts']).isNotEmpty &&
    !const {
      'approved',
      'approved_with_revisions',
      'failed',
      'project_rejected',
    }.contains(workflow['status']);

/// Read-only proposal slots shared by team summaries and deliverable headings.
class ProposalTitleSummary extends StatelessWidget {
  const ProposalTitleSummary({
    super.key,
    required this.rows,
    this.title = 'Concept proposals',
    this.systems = false,
    this.collapsible = false,
    this.showHeading = true,
    this.fontSize = 14,
    this.selectedKey = '',
  });
  final List<Map<String, dynamic>> rows;
  final String title;
  final bool systems;
  final bool collapsible;
  final bool showHeading;
  final double fontSize;
  final String selectedKey;

  @override
  Widget build(BuildContext context) {
    final provided = rows
        .where((r) => '${r['title'] ?? ''}'.trim().isNotEmpty)
        .length;
    final heading = '$title · $provided of ${rows.length} titles provided';
    final selectedStyle = WorkflowStatusStyle.of(
      context,
      WorkflowStatusTone.success,
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, row) in rows.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    systems
                        ? 'System ${systemLetter(row['key'])}'
                        : 'Concept ${int.tryParse('${row['key']}'.replaceFirst('c', '')) ?? index + 1}',
                    style: TextStyle(
                      fontSize: fontSize - 1,
                      fontWeight: FontWeight.w600,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${row['title'] ?? ''}'.trim().isEmpty
                            ? 'Pending proposal'
                            : '${row['title']}',
                        style: TextStyle(
                          fontSize: fontSize,
                          height: 1.45,
                          fontStyle: '${row['title'] ?? ''}'.trim().isEmpty
                              ? FontStyle.italic
                              : FontStyle.normal,
                          color: '${row['title'] ?? ''}'.trim().isEmpty
                              ? DefensysTokens.textSecondaryOf(context)
                              : DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                      if (selectedKey.isNotEmpty && row['key'] == selectedKey)
                        Container(
                          key: ValueKey('selected-proposal-$selectedKey'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: selectedStyle.background,
                            border: Border.all(color: selectedStyle.border),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_rounded,
                                size: 13,
                                color: selectedStyle.foreground,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Selected',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: selectedStyle.foreground,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    final label = Text(
      heading,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: DefensysTokens.maroonTextOf(context),
      ),
    );
    if (collapsible) {
      return ExpansionTile(
        key: ValueKey('proposal-title-dropdown-$title'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        dense: true,
        visualDensity: VisualDensity.compact,
        shape: const Border(),
        collapsedShape: const Border(),
        title: label,
        children: [content],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeading) ...[label, const SizedBox(height: 2)],
        content,
      ],
    );
  }
}

/// Title completion is preparation progress, separate from faculty approval.
class ProposalTitleProgressBadge extends StatelessWidget {
  const ProposalTitleProgressBadge({super.key, required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final provided = rows
        .where((r) => '${r['title'] ?? ''}'.trim().isNotEmpty)
        .length;
    final incomplete = provided < rows.length;
    final style = WorkflowStatusStyle.of(
      context,
      incomplete ? WorkflowStatusTone.attention : WorkflowStatusTone.active,
    );
    return Container(
      key: const ValueKey('proposal-title-progress-status'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: style.background,
        border: Border.all(color: style.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            incomplete ? Icons.hourglass_top_rounded : Icons.list_alt_rounded,
            size: 15,
            color: style.foreground,
          ),
          const SizedBox(width: 6),
          Text(
            '$provided of ${rows.length} titles provided',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: style.foreground,
            ),
          ),
        ],
      ),
    );
  }
}
