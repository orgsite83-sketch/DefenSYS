import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import '../panelist_models.dart';

/// The project and presenting roster stay ahead of the rubric so evaluators
/// can identify the defense before entering scores.
class DefenseTeamSummary extends StatelessWidget {
  const DefenseTeamSummary({super.key, required this.team});
  final TeamData team;

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
    final weights = <String, int>{
      'Panel': team.panelWeight,
      'Peer': team.peerWeight,
      if (team.isCapstone && team.adviserWeight > 0)
        'Adviser': team.adviserWeight,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceHigherOf(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Grade composition',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final weight in weights.entries)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${weight.value}%',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.4,
                          color: weight.key == 'Panel'
                              ? DefensysTokens.maroonTextOf(context)
                              : DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        weight.key,
                        style: TextStyle(
                          fontSize: 11,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
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
        border: Border.all(
          color: Color.alphaBlend(
            accent.withValues(alpha: .12),
            DefensysTokens.borderOf(context),
          ),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(accent.withValues(alpha: .045), surface),
            surface,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: DefensysTokens.isDark(context) ? .12 : .035,
            ),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 3, color: accent),
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
                  const SizedBox(height: 18),
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
                        if (team.section.isNotEmpty && team.level.isNotEmpty)
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
                  const Divider(height: 30),
                  ExpansionTile(
                    key: PageStorageKey(
                      'presenting-members-${team.scheduleId}-${team.evaluationContext}',
                    ),
                    initiallyExpanded: true,
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Presenting members',
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
                      for (final member in team.memberDetails)
                        _member(context, member),
                      if (team.memberDetails.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No presenting members listed.'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _composition(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
