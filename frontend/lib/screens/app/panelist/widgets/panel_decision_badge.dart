import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../models/team_workflow_status.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/repository/workflow_status_style.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';

/// Small decision indicators alongside personal evaluation and outcome badges.
class PanelDecisionBadge extends StatelessWidget {
  const PanelDecisionBadge({super.key, required this.status});
  final TeamWorkflowStatus status;

  @override
  Widget build(BuildContext context) {
    final style = WorkflowStatusStyle.of(context, status.tone);
    return DefensysShadcnScope(
      child: ShadBadge.secondary(
        backgroundColor: style.background,
        foregroundColor: style.foreground,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: style.border),
        ),
        child: Text(
          status.label,
          style: TextStyle(
            fontFamily: DefensysTokens.fontFamilyInter,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: style.foreground,
          ),
        ),
      ),
    );
  }
}
