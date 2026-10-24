import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/repository/workflow_status_style.dart';
import 'package:flutter/material.dart';

/// Shared by the desktop team tabs and the narrow-screen team picker.
class FacultyTeamChoiceLabel extends StatelessWidget {
  const FacultyTeamChoiceLabel({
    super.key,
    required this.label,
    this.status,
    this.selected = false,
  });

  final String label;
  final TeamWorkflowStatus? status;
  final bool selected;

  String _shortLabel(TeamWorkflowStatus status) => switch (status.code) {
    'needs_review' => 'Needs review',
    'archive_review_pending' => 'Archive review',
    'concept_review_pending' => 'Concept review',
    'module_confirmation_pending' => 'Confirm modules',
    'shared_acknowledgment_pending' => 'Review shared systems',
    'shared_clearance_pending' => 'Shared papers pending',
    'replacement_concepts_needed' => 'New concepts needed',
    'ready_to_schedule_redefense' => 'Ready for re-defense',
    'awaiting_concept_selection' => 'Concept selection',
    _ => status.label,
  };

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final statusColor = selected
        ? Colors.white.withValues(alpha: 0.9)
        : status == null
        ? DefensysTokens.textSecondaryOf(context)
        : WorkflowStatusStyle.of(context, status.tone).foreground;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? Colors.white
                : DefensysTokens.textPrimaryOf(context),
          ),
        ),
        if (status != null) ...[
          const SizedBox(height: 4),
          Tooltip(
            message: '${status.label}\n${status.nextStep}',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _shortLabel(status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
