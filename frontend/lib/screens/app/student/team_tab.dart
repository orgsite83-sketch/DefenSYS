import 'package:flutter/material.dart';

import '../../../theme/defensys_tokens.dart';
import '../../../widgets/student_team_summary_card.dart';

class TeamTab extends StatelessWidget {
  final Map<String, dynamic>? studentData;
  final Future<void> Function()? onRefresh;

  const TeamTab({
    super.key,
    required this.studentData,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final team = studentData?['team'] as Map<String, dynamic>?;
    final schedule = studentData?['schedule'] as Map<String, dynamic>?;
    final members =
        (studentData?['members'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final grades = studentData?['grades'] as Map<String, dynamic>?;
    final isCapstone = team?['isCapstone'] == true;

    if (team == null) {
      final emptyContent = const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group_off, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'No team assigned yet.',
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
              SizedBox(height: 4),
              Text(
                'Contact your administrator.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );

      if (onRefresh == null) return emptyContent;

      return LayoutBuilder(
        builder: (context, constraints) {
          return RefreshIndicator(
            color: DefensysTokens.maroon,
            onRefresh: onRefresh!,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: emptyContent,
              ),
            ),
          );
        },
      );
    }

    final adviserName = team['adviserName'] ?? (isCapstone ? 'Unassigned' : 'N/A');

    final scheduleStr = schedule != null
        ? '${schedule['date']} — ${schedule['startTime']}'
        : 'Not yet scheduled';
    final roomStr = schedule?['room'] ?? '—';

    final panelGrade = grades?['panelist'];
    final adviserGrade = grades?['adviser'];
    final gradeStatus = grades?['status'] ?? 'pending';
    final peerEvalComplete = studentData?['peerEvalComplete'] == true;
    final myPeerEvalComplete = studentData?['myPeerEvalComplete'] == true;
    final peerEvalEnabled = studentData?['peerEvalEnabled'] == true;

    final scrollContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StudentTeamSummaryCard(team: team),
        _sectionHeader('Team Details'),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isCapstone)
                  _infoRow(Icons.person_pin, 'Adviser', adviserName),
                _infoRow(Icons.calendar_today, 'Defense Schedule', scheduleStr),
                if (schedule != null) _infoRow(Icons.room, 'Room', roomStr),
                const Divider(height: 24),
                const Text(
                  'Team Members',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                ...members.map(
                  (m) => _memberTile(
                    m['name'] ?? m['id'] ?? '—',
                    m['isLeader'] == true ? 'Team Leader' : 'Member',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _sectionHeader('Defense Progress'),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _progressStep('Team Registered', true),
                _progressStep('Defense Scheduled', schedule != null),
                _progressStep('Panel Evaluation', panelGrade != null),
                if (isCapstone)
                  _progressStep('Adviser Grading', adviserGrade != null),
                _progressStep(
                  peerEvalEnabled && !peerEvalComplete && myPeerEvalComplete
                      ? 'Peer Evaluation (your part done)'
                      : 'Peer Evaluation',
                  peerEvalComplete,
                ),
                _progressStep('Grades Published', gradeStatus == 'published'),
              ],
            ),
          ),
        ),
      ],
    );

    if (onRefresh == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: scrollContent,
      );
    }

    return RefreshIndicator(
      color: DefensysTokens.maroon,
      onRefresh: onRefresh!,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: scrollContent,
      ),
    );
  }

  Widget _progressStep(String label, bool done) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done ? Colors.green : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: done ? Colors.black87 : Colors.grey,
                fontWeight: done ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: DefensysTokens.maroon),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text(
                value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _memberTile(String name, String role) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.person, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(name, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: DefensysTokens.maroon.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              role,
              style: const TextStyle(fontSize: 11, color: DefensysTokens.maroon),
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
