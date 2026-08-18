import 'package:flutter/material.dart';

import '../../theme/defensys_tokens.dart';

/// Compact team header shown on the student Team tab only.
class StudentTeamSummaryCard extends StatelessWidget {
  final Map<String, dynamic> team;

  const StudentTeamSummaryCard({super.key, required this.team});

  @override
  Widget build(BuildContext context) {
    final teamName = team['name'] ?? 'Unknown Team';
    final projectTitle = team['projectTitle'] ?? team['project_title'] ?? '—';
    final systemName = team['system_name'] ?? team['systemName'] ?? '';
    final projectManagerName = team['project_manager_name'] ?? team['projectManagerName'] ?? '';
    final level = team['level'] ?? '—';
    final status = team['status'] ?? 'Pending';
    final memberCount = team['memberCount'] ?? 0;
    final adviserName = team['adviserName'] ?? 'Unassigned';
    final isCapstone = team['isCapstone'] == true;
    final Color badgeBg;
    final Color badgeText;
    final Color badgeBorder;
    if (status == 'Approved') {
      badgeBg = DefensysTokens.successBg;
      badgeText = DefensysTokens.successText;
      badgeBorder = DefensysTokens.successBorder;
    } else if (status == 'Failed') {
      badgeBg = DefensysTokens.dangerBg;
      badgeText = DefensysTokens.dangerText;
      badgeBorder = DefensysTokens.dangerBorder;
    } else {
      badgeBg = DefensysTokens.warningBg;
      badgeText = DefensysTokens.warningText;
      badgeBorder = DefensysTokens.warningBorder;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: DefensysTokens.surface,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.border, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                color: isCapstone ? DefensysTokens.maroon : DefensysTokens.darkGold,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (isCapstone ? DefensysTokens.maroon : DefensysTokens.darkGold).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                              border: Border.all(
                                color: (isCapstone ? DefensysTokens.maroon : DefensysTokens.darkGold).withValues(alpha: 0.2),
                              ),
                            ),
                            child: Icon(
                              isCapstone ? Icons.school_outlined : Icons.book_outlined,
                              color: isCapstone ? DefensysTokens.maroon : DefensysTokens.darkGold,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  teamName,
                                  style: DefensysTokens.sectionTitle.copyWith(
                                    fontSize: 17,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  level,
                                  style: DefensysTokens.caption,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                              border: Border.all(color: badgeBorder, width: 1.0),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: badgeText,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  status,
                                  style: TextStyle(
                                    color: badgeText,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: DefensysTokens.neutralBg,
                          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                          border: Border.all(
                            color: DefensysTokens.border,
                            width: 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.assignment_outlined,
                                  color: isCapstone ? DefensysTokens.maroon : DefensysTokens.darkGold,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    projectTitle,
                                    style: DefensysTokens.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (systemName.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.layers_outlined,
                                    color: isCapstone ? DefensysTokens.maroon : DefensysTokens.darkGold,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'System: $systemName',
                                      style: DefensysTokens.body.copyWith(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (projectManagerName.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.assignment_ind_outlined,
                                    color: isCapstone ? DefensysTokens.maroon : DefensysTokens.darkGold,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'PM: $projectManagerName',
                                      style: DefensysTokens.body.copyWith(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const Divider(height: 20, thickness: 1.0),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.group_outlined,
                                      color: DefensysTokens.steelGrey,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$memberCount ${memberCount == 1 ? 'Member' : 'Members'}',
                                      style: DefensysTokens.caption.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                if (isCapstone)
                                  Flexible(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        const Icon(
                                          Icons.person_outline,
                                          color: DefensysTokens.steelGrey,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            adviserName,
                                            style: DefensysTokens.caption.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
