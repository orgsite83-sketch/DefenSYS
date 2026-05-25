import 'package:flutter/material.dart';

import '../theme/defensys_tokens.dart';

/// Compact team header shown on the student Team tab only.
class StudentTeamSummaryCard extends StatelessWidget {
  final Map<String, dynamic> team;

  const StudentTeamSummaryCard({super.key, required this.team});

  @override
  Widget build(BuildContext context) {
    final teamName = team['name'] ?? 'Unknown Team';
    final projectTitle = team['projectTitle'] ?? '—';
    final level = team['level'] ?? '—';
    final status = team['status'] ?? 'Pending';
    final memberCount = team['memberCount'] ?? 0;
    final adviserName = team['adviserName'] ?? 'Unassigned';
    final isCapstone = team['isCapstone'] == true;

    final statusColor = status == 'Approved'
        ? Colors.green
        : status == 'Failed'
            ? Colors.red
            : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [DefensysTokens.maroon, DefensysTokens.maroon.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: DefensysTokens.maroon.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isCapstone ? Icons.school : Icons.book,
                    color: Colors.white,
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
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        level,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.assignment, color: Colors.white70, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          projectTitle,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.people, color: Colors.white70, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '$memberCount ${memberCount == 1 ? 'Member' : 'Members'}',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                      if (isCapstone)
                        Flexible(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const Icon(Icons.person_pin, color: Colors.white70, size: 16),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  adviserName,
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
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
    );
  }
}
