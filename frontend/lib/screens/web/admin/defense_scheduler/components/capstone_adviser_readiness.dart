import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/widgets/repository/workflow_status_style.dart';
import '../models/capstone_planning_draft.dart';

class CapstoneReadinessBadge extends StatelessWidget {
  const CapstoneReadinessBadge({
    super.key,
    required this.status,
    required this.label,
  });
  final String status, label;

  @override
  Widget build(BuildContext context) {
    final ready = status == 'ready' || status == 'ready_for_redefense';
    final pending =
        status == 'partial' ||
        status == 'blocked' ||
        status == 'preparing_redefense';
    final style = WorkflowStatusStyle.of(
      context,
      ready
          ? WorkflowStatusTone.success
          : pending
          ? WorkflowStatusTone.attention
          : WorkflowStatusTone.neutral,
    );
    return ShadBadge.outline(
      backgroundColor: style.background,
      foregroundColor: style.foreground,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: DefensysTokens.fontFamilyInter,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Read-only statuses from endorsement and schedule records, never a status editor.
class CapstoneAdviserReadiness extends StatefulWidget {
  const CapstoneAdviserReadiness({
    super.key,
    required this.group,
    required this.stageId,
  });
  final CapstoneAdviserGroup group;
  final int? stageId;
  @override
  State<CapstoneAdviserReadiness> createState() =>
      _CapstoneAdviserReadinessState();
}

class _CapstoneAdviserReadinessState extends State<CapstoneAdviserReadiness> {
  final _controller = ShadPopoverController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = CapstoneReadinessSummary(
      widget.group.teams,
      widget.stageId,
    );
    final teams = widget.group.teams
        .where((team) => capstoneTeamNeedsScheduling(team, widget.stageId))
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: math.min(420, constraints.maxWidth),
        child: ShadPopover(
          controller: _controller,
          popover: (context) => SizedBox(
            width: math.min(450, MediaQuery.sizeOf(context).width - 64),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.group.name} · Team readiness',
                      style: const TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      summary.counts,
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 12,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final team in teams) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${team['name']}',
                                  style: const TextStyle(
                                    fontFamily: DefensysTokens.fontFamilyInter,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  capstoneTeamReadiness(
                                            team,
                                            widget.stageId,
                                          )['endorsed'] ==
                                          true
                                      ? 'Endorsed'
                                      : 'Not endorsed',
                                  style: TextStyle(
                                    fontFamily: DefensysTokens.fontFamilyInter,
                                    fontSize: 12,
                                    color: DefensysTokens.textSecondaryOf(
                                      context,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: CapstoneReadinessBadge(
                              status:
                                  '${capstoneTeamReadiness(team, widget.stageId)['status']}',
                              label:
                                  '${capstoneTeamReadiness(team, widget.stageId)['label']}',
                            ),
                          ),
                        ],
                      ),
                      if (team != teams.last) const Divider(height: 24),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'Updates automatically from team endorsements and defense schedules.',
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 12,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          child: ShadButton.outline(
            width: double.infinity,
            onPressed: _controller.toggle,
            child: SizedBox(
              width: math.max(0, math.min(420, constraints.maxWidth) - 34),
              child: Row(
                children: [
                  const Icon(Icons.groups_outlined, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Team readiness · ${summary.counts}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
