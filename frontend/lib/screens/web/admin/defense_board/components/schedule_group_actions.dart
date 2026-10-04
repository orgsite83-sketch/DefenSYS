import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_action_menu.dart';
import 'schedule_operations_dialog.dart';

/// Each group has three choices; the editor contains its detailed tasks.
class ScheduleGroupActions extends StatelessWidget {
  const ScheduleGroupActions({
    super.key,
    required this.schedule,
    this.target = 'session',
    this.enabled = true,
  });
  final Map<String, dynamic> schedule;
  final String target;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final stage = target == 'stage';
    void open(String tab) => showScheduleOperationsDialog(
      context,
      schedule,
      target: target,
      tab: tab,
    );
    return DefensysActionMenu(
      label: stage
          ? 'Stage actions for ${schedule['stage_label']}'
          : 'More actions for this session',
      triggerLabel: stage ? 'Stage actions' : null,
      enabled: enabled,
      items: [
        DefensysMenuItem(
          label: stage ? 'Edit stage schedules' : 'Edit session',
          icon: LucideIcons.pencil,
          onPressed: () => open('edit'),
        ),
        DefensysMenuItem(
          label: stage ? 'Change stage status' : 'Change status',
          icon: LucideIcons.circlePause,
          onPressed: () => open('status'),
        ),
        DefensysMenuItem(
          label: 'Delete schedules',
          icon: LucideIcons.trash2,
          destructive: true,
          onPressed: () => open('delete'),
        ),
      ],
    );
  }
}

class StageScheduleHeader extends StatelessWidget {
  const StageScheduleHeader({
    super.key,
    required this.schedule,
    required this.sessionCount,
    required this.canManage,
    this.isSaving = false,
  });
  final Map<String, dynamic> schedule;
  final int sessionCount;
  final bool canManage, isSaving;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          LucideIcons.layers,
          size: 19,
          color: DefensysTokens.textSecondaryOf(context),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${schedule['stage_label'] ?? 'Defense schedules'}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${schedule['scope'] == 'pit' ? 'PIT event' : 'Capstone stage'} · $sessionCount ${sessionCount == 1 ? 'session' : 'sessions'} shown',
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
