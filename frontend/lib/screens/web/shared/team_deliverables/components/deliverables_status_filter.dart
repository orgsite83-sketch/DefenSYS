import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import '../deliverables_view_types.dart';

/// A compact status field with a searchable, bounded workflow menu.
class DeliverablesStatusFilter extends StatefulWidget {
  const DeliverablesStatusFilter({
    super.key,
    required this.value,
    required this.counts,
    required this.isPit,
    required this.onChanged,
  });

  final TeamTriageFilter value;
  final Map<TeamTriageFilter, int> counts;
  final bool isPit;
  final ValueChanged<TeamTriageFilter>? onChanged;

  @override
  State<DeliverablesStatusFilter> createState() =>
      _DeliverablesStatusFilterState();
}

class _DeliverablesStatusFilterState extends State<DeliverablesStatusFilter> {
  String _query = '';

  static const _groups = {
    'Requirements': [
      TeamTriageFilter.awaitingFiles,
      TeamTriageFilter.overdue,
      TeamTriageFilter.needsReview,
      TeamTriageFilter.changesRequested,
      TeamTriageFilter.awaitingEndorsement,
      TeamTriageFilter.readyForDefense,
      TeamTriageFilter.notConfigured,
      TeamTriageFilter.onHold,
    ],
    'Concepts': [
      TeamTriageFilter.replacementConcepts,
      TeamTriageFilter.adviserReview,
      TeamTriageFilter.moduleConfirmation,
      TeamTriageFilter.sharedAcknowledgment,
      TeamTriageFilter.sharedClearance,
      TeamTriageFilter.readyRedefense,
      TeamTriageFilter.redefenseScheduled,
    ],
    'Defense': [
      TeamTriageFilter.scheduled,
      TeamTriageFilter.awaitingEvaluation,
      TeamTriageFilter.evaluating,
      TeamTriageFilter.awaitingVerdict,
      TeamTriageFilter.gradingIncomplete,
      TeamTriageFilter.awaitingResults,
      TeamTriageFilter.awaitingCompletion,
      TeamTriageFilter.redefenseRequired,
      TeamTriageFilter.paused,
      TeamTriageFilter.postponed,
      TeamTriageFilter.noShow,
      TeamTriageFilter.cancelled,
    ],
    'Post-defense / Outcomes': [
      TeamTriageFilter.pendingPostDefense,
      TeamTriageFilter.archiveReviewPending,
      TeamTriageFilter.revisionsPending,
      TeamTriageFilter.completed,
      TeamTriageFilter.failed,
      TeamTriageFilter.archived,
    ],
  };

  String _label(TeamTriageFilter filter) => switch (filter) {
    TeamTriageFilter.all => 'All teams',
    TeamTriageFilter.needsReview => 'Needs review',
    TeamTriageFilter.awaitingEndorsement => 'Awaiting endorsement',
    TeamTriageFilter.readyForDefense =>
      widget.isPit ? 'Ready to schedule' : 'Ready for defense',
    TeamTriageFilter.overdue => 'Missing requirements / Overdue',
    TeamTriageFilter.replacementConcepts => 'Replacement concepts',
    TeamTriageFilter.adviserReview => 'Concept review',
    TeamTriageFilter.readyRedefense => 'Schedule re-defense',
    TeamTriageFilter.redefenseScheduled => 'Re-defense scheduled',
    TeamTriageFilter.failed => 'Failed / Rejected',
    _ => DeliverablesTriageHelper.workflowFilters[filter]!.$2,
  };

  Widget _option(TeamTriageFilter filter) => ShadOption<TeamTriageFilter>(
    value: filter,
    child: Text(
      '${_label(filter)} (${widget.counts[filter] ?? 0})',
      style: const TextStyle(fontSize: 13),
      overflow: TextOverflow.ellipsis,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final options = <Widget>[_option(TeamTriageFilter.all)];
    for (final group in _groups.entries) {
      final matches = group.value
          .where(
            (filter) =>
                '${group.key} ${_label(filter)}'.toLowerCase().contains(_query),
          )
          .toList();
      if (matches.isEmpty) continue;
      options.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 5),
          child: Text(
            group.key,
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ),
      );
      options.addAll(matches.map(_option));
    }
    if (options.length == 1 && _query.isNotEmpty) {
      options.add(
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('No matching statuses'),
        ),
      );
    }

    return DefensysShadcnScope(
      child: LayoutBuilder(
        builder: (context, constraints) => Semantics(
          label: 'Status',
          child: ShadSelect<TeamTriageFilter>.withSearch(
            key: ValueKey(widget.value),
            initialValue: widget.value,
            minWidth: constraints.maxWidth,
            maxWidth: constraints.maxWidth,
            maxHeight: 400,
            clearSearchOnClose: true,
            searchPlaceholder: const Text('Search statuses…'),
            searchInputLeading: const Icon(Icons.search, size: 16),
            onSearchChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
            options: options,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: ShadDecoration(
              color: DefensysTokens.surfaceHigherOf(context),
              border: ShadBorder.all(
                color: DefensysTokens.borderOf(context),
                radius: BorderRadius.circular(8),
              ),
            ),
            selectedOptionBuilder: (context, filter) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Status',
                  style: TextStyle(
                    fontSize: 10,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
                Text(
                  '${_label(filter)} (${widget.counts[filter] ?? 0})',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            onChanged: (value) {
              if (value != null) widget.onChanged?.call(value);
            },
          ),
        ),
      ),
    );
  }
}
