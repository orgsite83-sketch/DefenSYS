import 'package:flutter/material.dart';

import '../admin/widgets/defensys_admin_shell.dart';

class AdviserDashboardContent extends StatelessWidget {
  final Map<String, dynamic>? data;
  final String facultyName;
  final VoidCallback onOpenDeliverables;
  final VoidCallback onOpenWeeklyReports;
  final VoidCallback onOpenGrading;

  const AdviserDashboardContent({
    super.key,
    required this.data,
    required this.facultyName,
    required this.onOpenDeliverables,
    required this.onOpenWeeklyReports,
    required this.onOpenGrading,
  });

  @override
  Widget build(BuildContext context) {
    final advisedTeams = (data?['advised_teams'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DefensysPageHeader(
          icon: Icons.school_outlined,
          title: 'Project Adviser workspace',
          subtitle: 'Capstone teams you advise this semester.',
        ),
        const SizedBox(height: 8),
        Text(
          'Welcome, $facultyName',
          style: DefensysUi.subtitle.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        const Text(
          'My Advised Teams',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: DefensysUi.textDark,
          ),
        ),
        const SizedBox(height: 12),
        ...advisedTeams.map((team) => _teamCard(team, onOpenDeliverables)),
        if (advisedTeams.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No advised teams yet.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: onOpenDeliverables,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Capstone Deliverables'),
            ),
            OutlinedButton.icon(
              onPressed: onOpenWeeklyReports,
              icon: const Icon(Icons.assignment_outlined),
              label: const Text('Weekly Progress Reports'),
            ),
            OutlinedButton.icon(
              onPressed: onOpenGrading,
              icon: const Icon(Icons.rate_review_rounded),
              label: const Text('Grade Students'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _teamCard(dynamic team, VoidCallback onOpenDeliverables) {
    final map = (team as Map?)?.cast<String, dynamic>() ?? {};
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    map['name']?.toString() ?? 'Team',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    map['projectTitle']?.toString() ?? '',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      map['currentStage']?.toString() ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                map['status']?.toString() ?? '',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onOpenDeliverables,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Deliverables'),
            ),
          ],
        ),
      ),
    );
  }
}
