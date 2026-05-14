import 'package:flutter/material.dart';
import 'panelist_models.dart';

const _primaryColor = Color(0xFF7F1D1D);

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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _primaryColor,
          child: Text(t.name.split(' ').last[0],
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold)),
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
                    const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text('Defense: ${t.defenseDate}',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 12),
                    Icon(t.isCapstone ? Icons.school : Icons.book,
                        size: 14, color: _primaryColor),
                    const SizedBox(width: 4),
                    Text(t.isCapstone ? 'Capstone' : 'PIT',
                        style: const TextStyle(fontSize: 12, color: _primaryColor)),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: t.members
                      .map((m) => Chip(
                            label: Text(m, style: const TextStyle(fontSize: 11)),
                            avatar: const Icon(Icons.person, size: 14),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: EdgeInsets.zero,
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: Icon(isPosted ? Icons.visibility : Icons.edit, size: 16),
                    label: Text(isPosted ? 'View Grades' : 'Open Grade Sheet'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => onOpenGradeSheet(index),
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
        color: isPosted ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isPosted ? Colors.red : Colors.blue),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isPosted ? Icons.lock : Icons.edit,
              size: 12, color: isPosted ? Colors.red : Colors.blue),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: isPosted ? Colors.red : Colors.blue,
                  fontWeight: FontWeight.bold)),
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
                color: _primaryColor, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: _primaryColor)),
      ],
    );
  }
}
