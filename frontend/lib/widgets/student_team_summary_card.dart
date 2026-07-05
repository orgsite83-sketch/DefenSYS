import 'package:flutter/material.dart';

import '../theme/defensys_tokens.dart';

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
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 6,
                color: isCapstone ? DefensysTokens.maroon : DefensysTokens.techBlue,
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
                              color: (isCapstone ? DefensysTokens.maroon : DefensysTokens.techBlue).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isCapstone ? Icons.school_outlined : Icons.book_outlined,
                              color: isCapstone ? DefensysTokens.maroon : DefensysTokens.techBlue,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  teamName,
                                  style: const TextStyle(
                                    color: DefensysTokens.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  level,
                                  style: const TextStyle(
                                    color: DefensysTokens.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: badgeBorder),
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
                                const SizedBox(width: 6),
                                Text(
                                  status,
                                  style: TextStyle(
                                    color: badgeText,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
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
                          color: DefensysTokens.background.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: DefensysTokens.border.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.assignment_outlined,
                                  color: isCapstone ? DefensysTokens.maroon : DefensysTokens.techBlue,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    projectTitle,
                                    style: const TextStyle(
                                      color: DefensysTokens.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
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
                                    color: isCapstone ? DefensysTokens.maroon : DefensysTokens.techBlue,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'System: $systemName',
                                      style: const TextStyle(
                                        color: DefensysTokens.textPrimary,
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
                                    color: isCapstone ? DefensysTokens.maroon : DefensysTokens.techBlue,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'PM: $projectManagerName',
                                      style: const TextStyle(
                                        color: DefensysTokens.textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const Divider(height: 20, thickness: 1),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.group_outlined,
                                      color: DefensysTokens.textSecondary,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$memberCount ${memberCount == 1 ? 'Member' : 'Members'}',
                                      style: const TextStyle(
                                        color: DefensysTokens.textSecondary,
                                        fontSize: 12,
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
                                          color: DefensysTokens.textSecondary,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            adviserName,
                                            style: const TextStyle(
                                              color: DefensysTokens.textSecondary,
                                              fontSize: 12,
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
