import 'package:flutter/material.dart';

import '../../../theme/defensys_tokens.dart';

/// Read-only grade summary for PIT students (replaces Weekly Report tab).
class MyGradesTab extends StatelessWidget {
  final Map<String, dynamic>? studentData;

  const MyGradesTab({super.key, required this.studentData});

  @override
  Widget build(BuildContext context) {
    final team = studentData?['team'] as Map<String, dynamic>?;
    final schedule = studentData?['schedule'] as Map<String, dynamic>?;
    final grades = studentData?['grades'] as Map<String, dynamic>?;
    final weights = (studentData?['weights'] as Map<String, dynamic>?) ??
        {'panel': 80, 'peer': 20};

    if (team == null) {
      return const Center(
        child: Text(
          'No team assigned yet.',
          style: TextStyle(color: Colors.grey, fontSize: 15),
        ),
      );
    }

    final panelGrade = grades?['panelist'] as Map<String, dynamic>?;
    final peerGrade = grades?['peer'] as Map<String, dynamic>?;
    final finalGrade = grades?['finalGrade'];
    final gradeStatus = grades?['status']?.toString() ?? 'pending';
    final panelW = (weights['panel'] as num?)?.toInt() ?? 80;
    final peerW = (weights['peer'] as num?)?.toInt() ?? 20;
    final isPublished = gradeStatus == 'published';
    final peerEvalComplete = studentData?['peerEvalComplete'] == true;
    final peerEvalEnabled = studentData?['peerEvalEnabled'] == true;
    final peerPending =
        peerEvalEnabled && !peerEvalComplete && panelGrade != null;

    final scheduleStr = schedule != null
        ? '${schedule['date']} · ${schedule['startTime']}'
        : null;
    final room = schedule?['room']?.toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('My Grades'),
          const SizedBox(height: 12),
          if (scheduleStr != null) ...[
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.event, color: DefensysTokens.maroon),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PIT Defense',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            scheduleStr,
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                          if (room != null && room.isNotEmpty)
                            Text(
                              'Room $room',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _scoreCard(
            title: 'Panel Score',
            subtitle: '$panelW% of final grade',
            value: panelGrade,
            accent: DefensysTokens.maroon,
          ),
          const SizedBox(height: 12),
          _scoreCard(
            title: 'Peer Score',
            subtitle: peerPending
                ? 'Pending — all teammates must finish peer evaluation'
                : '$peerW% of final grade',
            value: peerPending ? null : peerGrade,
            accent: DefensysTokens.gold,
            pendingLabel: peerPending ? 'Pending' : null,
          ),
          const SizedBox(height: 12),
          _finalCard(
            finalGrade: finalGrade,
            isPublished: isPublished,
            panelW: panelW,
            peerW: peerW,
          ),
          const SizedBox(height: 16),
          Text(
            peerPending
                ? 'Your team is still completing peer evaluation. Final grades '
                    'will appear after everyone has submitted.'
                : 'Grades appear after panel evaluation and peer evaluation are '
                    'complete. Contact your PIT Lead if something looks wrong.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _scoreCard({
    required String title,
    required String subtitle,
    required Map<String, dynamic>? value,
    required Color accent,
    String? pendingLabel,
  }) {
    if (pendingLabel != null) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.hourglass_empty, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Text(
                pendingLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final hasScore = value != null && value['total'] != null;
    final total = (value?['total'] as num?)?.toDouble();
    final max = (value?['max'] as num?)?.toDouble() ?? 100;
    final pct = hasScore && max > 0 ? (total! / max * 100) : null;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.grade, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (pct != null)
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: accent,
                ),
              )
            else
              const Text(
                '—',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _finalCard({
    required dynamic finalGrade,
    required bool isPublished,
    required int panelW,
    required int peerW,
  }) {
    final hasFinal = finalGrade != null;
    final fg = hasFinal ? (finalGrade as num).toDouble() : null;
    final passed = fg != null && fg >= 75;
    final statusColor = !hasFinal
        ? Colors.grey
        : passed
            ? Colors.green
            : Colors.red;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      color: DefensysTokens.maroon.withOpacity(0.04),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Final Grade',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  hasFinal ? fg!.toStringAsFixed(1) : '—',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 12),
                if (hasFinal)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withOpacity(0.4)),
                    ),
                    child: Text(
                      passed ? 'Passed' : 'Failed',
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isPublished
                  ? 'Published · Panel ($panelW%) + Peer ($peerW%)'
                  : 'Not published yet · Panel ($panelW%) + Peer ($peerW%)',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
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
