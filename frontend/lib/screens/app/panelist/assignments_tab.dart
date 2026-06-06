import 'package:flutter/material.dart';

import '../../../theme/defensys_tokens.dart';
import 'panelist_models.dart';

class AssignmentsTab extends StatelessWidget {
  final List<TeamData> teams;
  final void Function(int teamIndex) onOpenGradeSheet;

  const AssignmentsTab({
    super.key,
    required this.teams,
    required this.onOpenGradeSheet,
  });

  @override
  Widget build(BuildContext context) {
    if (teams.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('My Panel Assignments'),
          const SizedBox(height: 48),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.assignment_outlined,
                  size: 48,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No panel assignments yet.',
                  style: TextStyle(color: Colors.grey, fontSize: 15),
                ),
                const SizedBox(height: 8),
                const Text(
                  "You'll see teams here once you're assigned to a defense panel.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader('My Panel Assignments'),
        const SizedBox(height: 12),
        ...teams.asMap().entries.map((e) => _teamCard(e.key, e.value)),
      ],
    );
  }

  Widget _teamCard(int index, TeamData t) {
    final isPosted = t.isPosted;
    final hasValidScope = t.hasValidScope;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: DefensysTokens.maroon,
          child: Text(
            t.name.split(' ').last[0],
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          t.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(t.project, style: const TextStyle(fontSize: 12)),
        trailing: _statusBadge(isPosted ? 'Posted' : 'Draft'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Defense: ${t.defenseDate}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      hasValidScope
                          ? (t.isCapstone ? Icons.school : Icons.book)
                          : Icons.error_outline,
                      size: 14,
                      color: hasValidScope
                          ? DefensysTokens.maroon
                          : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      t.scopeLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: hasValidScope
                            ? DefensysTokens.maroon
                            : Colors.orange.shade800,
                        fontWeight: hasValidScope
                            ? FontWeight.normal
                            : FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (!hasValidScope) ...[
                  const SizedBox(height: 8),
                  Text(
                    'This assignment is missing its schedule scope. Ask an admin to repair the schedule before grading.',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: t.members
                      .map(
                        (m) => Chip(
                          label: Text(m, style: const TextStyle(fontSize: 11)),
                          avatar: const Icon(Icons.person, size: 14),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: EdgeInsets.zero,
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: Icon(
                      isPosted ? Icons.visibility : Icons.edit,
                      size: 16,
                    ),
                    label: Text(isPosted ? 'View Grades' : 'Open Grade Sheet'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DefensysTokens.maroon,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: hasValidScope
                        ? () => onOpenGradeSheet(index)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String label) {
    final isPosted = label == 'Posted';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isPosted
            ? Colors.red.withValues(alpha: 0.1)
            : Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isPosted ? Colors.red : Colors.blue),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPosted ? Icons.lock : Icons.edit,
            size: 12,
            color: isPosted ? Colors.red : Colors.blue,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isPosted ? Colors.red : Colors.blue,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: DefensysTokens.maroon,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: DefensysTokens.maroon,
          ),
        ),
      ],
    );
  }
}
