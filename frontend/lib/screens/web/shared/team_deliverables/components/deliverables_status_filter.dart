import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import '../deliverables_view_types.dart';

/// A short team-status menu. Exact workflow statuses stay on the team itself.
class DeliverablesStatusFilter extends StatelessWidget {
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

  String _label(TeamTriageFilter filter) =>
      DeliverablesTriageHelper.summaryFilters[filter] ??
      switch (filter) {
        TeamTriageFilter.needsReview => 'Needs review',
        TeamTriageFilter.awaitingEndorsement => 'Awaiting endorsement',
        TeamTriageFilter.readyForDefense =>
          isPit ? 'Ready to schedule' : 'Ready for defense',
        TeamTriageFilter.overdue => 'Missing requirements',
        TeamTriageFilter.replacementConcepts => 'Replacement concepts',
        TeamTriageFilter.adviserReview => 'Concept review',
        TeamTriageFilter.readyRedefense => 'Schedule re-defense',
        TeamTriageFilter.redefenseScheduled => 'Re-defense scheduled',
        TeamTriageFilter.failed => 'Failed / Rejected',
        _ => DeliverablesTriageHelper.workflowFilters[filter]!.$2,
      };

  String _text(TeamTriageFilter filter) =>
      '${_label(filter)} (${counts[filter] ?? 0})';

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final filter in DeliverablesTriageHelper.summaryFilters.keys)
        if (filter == TeamTriageFilter.all ||
            filter == value ||
            (counts[filter] ?? 0) > 0)
          filter,
      // Keep an exact file-review shortcut selected until the user clears it.
      if (!DeliverablesTriageHelper.summaryFilters.containsKey(value)) value,
    ];
    return DefensysShadcnScope(
      child: LayoutBuilder(
        builder: (context, constraints) => Semantics(
          label: 'Status',
          child: ShadSelect<TeamTriageFilter>(
            key: ValueKey(value),
            initialValue: value,
            enabled: onChanged != null,
            minWidth: constraints.maxWidth,
            maxWidth: constraints.maxWidth,
            maxHeight: 320,
            options: [
              for (final filter in visible)
                ShadOption<TeamTriageFilter>(
                  value: filter,
                  child: Text(
                    _text(filter),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
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
                  _text(filter),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            onChanged: (value) {
              if (value != null) onChanged?.call(value);
            },
          ),
        ),
      ),
    );
  }
}
