import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import '../panelist_models.dart';

/// The project and presenting roster stay ahead of the rubric so evaluators
/// can identify the defense before entering scores.
class DefenseTeamSummary extends StatelessWidget {
  const DefenseTeamSummary({
    super.key,
    required this.team,
    this.showDetailsInitially = false,
    this.previewMode = false,
  });
  final TeamData team;
  final bool showDetailsInitially;
  final bool previewMode;

  String _initials(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    return String.fromCharCodes([
      words.first.runes.first,
      if (words.length > 1) words.last.runes.first,
    ]).toUpperCase();
  }

  Widget _detail(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(
          icon,
          size: 17,
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _member(BuildContext context, TeamMember member) {
    final progress = team.progressFor(member.id);
    final individual = team.targetType != 'team' && progress.required > 0;
    final accent = DefensysTokens.maroonOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: CircleAvatar(
              radius: 18,
              backgroundColor: member.isLeader
                  ? accent.withValues(alpha: .10)
                  : DefensysTokens.surfaceHigherOf(context),
              child: Text(
                _initials(member.name),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: member.isLeader
                      ? DefensysTokens.maroonTextOf(context)
                      : DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (member.isLeader) 'Team leader',
                    if (individual)
                      'Individual: ${progress.label}'
                    else if (!member.isLeader)
                      'Team member',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          if (individual && progress.complete) ...[
            const SizedBox(width: 8),
            Semantics(
              label: 'Individual scores complete',
              child: Icon(
                Icons.check_circle_outline_rounded,
                size: 18,
                color: DefensysTokens.isDark(context)
                    ? const Color(0xFF6EE7B7)
                    : DefensysTokens.successText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _composition(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceHigherOf(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: DefensysTokens.maroonTextOf(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Panel evaluations account for ${team.panelWeight}% of the final stage grade. Panelist scores are combined.',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = DefensysTokens.maroonOf(context);
    final surface = DefensysTokens.surfaceOf(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        color: surface,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.school_outlined,
                          size: 20,
                          color: DefensysTokens.maroonTextOf(context),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              team.scopeLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: DefensysTokens.maroonTextOf(context),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Attempt #${team.attemptCount}',
                              style: TextStyle(
                                fontSize: 11,
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ShadBadge.outline(
                        child: Text(
                          team.isChair ? 'Panel Chair' : 'Panelist',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 17),
                  Text(
                    team.project.isNotEmpty
                        ? team.project
                        : 'Project title unavailable',
                    style: TextStyle(
                      fontSize: 21,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.45,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  if (team.scheduledDate != null) ...[
                    const SizedBox(height: 7),
                    Text(
                      DateFormat(
                        'EEEE, MMM d, yyyy',
                      ).format(team.scheduledDate!),
                      style: TextStyle(
                        fontSize: 12,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                  if (previewMode) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        _previewMeta(
                          context,
                          Icons.school_outlined,
                          team.displayStage,
                        ),
                        _previewMeta(
                          context,
                          Icons.schedule_outlined,
                          team.formattedTime,
                        ),
                        _previewMeta(
                          context,
                          Icons.place_outlined,
                          team.displayRoom,
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    team.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                  const Divider(height: 24),
                  ExpansionTile(
                    key: PageStorageKey(
                      'team-details-${team.scheduleId}-${team.evaluationContext}-$showDetailsInitially',
                    ),
                    initiallyExpanded: showDetailsInitially,
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Team details & presenting members',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${team.memberDetails.length}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                    children: [
                      const SizedBox(height: 8),
                      _detail(
                        context,
                        Icons.person_outline_rounded,
                        team.displaySupervisorLabel,
                        team.displaySupervisor,
                      ),
                      if (team.section.isNotEmpty || team.level.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (team.section.isNotEmpty)
                              Expanded(
                                child: _detail(
                                  context,
                                  Icons.groups_outlined,
                                  'Section',
                                  team.section,
                                ),
                              ),
                            if (team.section.isNotEmpty &&
                                team.level.isNotEmpty)
                              const SizedBox(width: 12),
                            if (team.level.isNotEmpty)
                              Expanded(
                                child: _detail(
                                  context,
                                  Icons.school_outlined,
                                  'Year level',
                                  team.level,
                                ),
                              ),
                          ],
                        ),
                      ],
                      const Divider(height: 24),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Presenting members',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      for (final member in team.memberDetails)
                        _member(context, member),
                      if (team.memberDetails.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No presenting members listed.'),
                        ),
                      const SizedBox(height: 12),
                      if (!previewMode) _composition(context),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewMeta(BuildContext context, IconData icon, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: DefensysTokens.textSecondaryOf(context)),
      const SizedBox(width: 5),
      Text(
        value,
        style: TextStyle(
          fontSize: 11,
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
    ],
  );
}
