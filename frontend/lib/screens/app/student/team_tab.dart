import 'package:flutter/material.dart';

const _primaryColor = Color(0xFF7F1D1D);

class TeamTab extends StatelessWidget {
  final Map<String, dynamic>? studentData; // from /api/student-data/<id>
  final Map<String, bool> peerPosted;

  const TeamTab({super.key, required this.studentData, required this.peerPosted});

  @override
  Widget build(BuildContext context) {
    final team     = studentData?['team']     as Map<String, dynamic>?;
    final schedule = studentData?['schedule'] as Map<String, dynamic>?;
    final members  = (studentData?['members'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final grades   = studentData?['grades']   as Map<String, dynamic>?;
    final weights  = (studentData?['weights'] as Map<String, dynamic>?) ?? {'panel': 50, 'adviser': 30, 'peer': 20};
    final isCapstone = team?['isCapstone'] == true;

    if (team == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group_off, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text('No team assigned yet.',
                  style: TextStyle(fontSize: 15, color: Colors.grey)),
              SizedBox(height: 4),
              Text('Contact your administrator.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final teamName    = team['name'] ?? '—';
    final initials    = teamName.toString().split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final projectTitle = team['projectTitle'] ?? '—';
    final adviserName  = team['adviserName'] ?? (isCapstone ? 'Unassigned' : 'N/A');
    final level        = team['level'] ?? '—';
    final status       = team['status'] ?? 'Pending';

    final scheduleStr = schedule != null
        ? '${schedule['date']} — ${schedule['startTime']}'
        : 'Not yet scheduled';
    final roomStr = schedule?['room'] ?? '—';

    final panelGrade   = grades?['panelist'];
    final adviserGrade = grades?['adviser'];
    final peerGrade    = studentData?['myPeerGrade'] as Map<String, dynamic>?; // student's own peer score
    final gradeStatus  = grades?['status'] ?? 'pending';

    final panelW = (weights['panel'] as num?)?.toInt() ?? 50;
    final peerW = (weights['peer'] as num?)?.toInt() ?? 20;

    final allPeerPosted = peerPosted.values.every((v) => v);

    // Compute this student's individual final grade
    dynamic myFinalGrade;
    if (panelGrade != null && peerGrade != null) {
      final panelNorm = (panelGrade['total'] as num) / (panelGrade['max'] as num) * 100;
      final peerNorm  = (peerGrade['avg'] as num) / (peerGrade['max'] as num) * 100;
      myFinalGrade = ((panelNorm * panelW / 100) + (peerNorm * peerW / 100)).roundToDouble() / 10 * 10;
      myFinalGrade = double.parse(myFinalGrade.toStringAsFixed(1));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('My Team Profile'),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: _primaryColor,
                        child: Text(initials,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(teamName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            Row(
                              children: [
                                Icon(isCapstone ? Icons.school : Icons.book, size: 13, color: _primaryColor),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(level,
                                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _statusChip(status),
                    ],
                  ),
                  const Divider(height: 24),
                  _infoRow(Icons.book, 'Project Title', projectTitle),
                  if (isCapstone) _infoRow(Icons.person_pin, 'Adviser', adviserName),
                  _infoRow(Icons.calendar_today, 'Defense Schedule', scheduleStr),
                  if (schedule != null) _infoRow(Icons.room, 'Room', roomStr),
                  const Divider(height: 24),
                  const Text('Team Members',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...members.map((m) => _memberTile(
                    m['name'] ?? m['id'] ?? '—',
                    m['isLeader'] == true ? 'Team Leader' : 'Member',
                  )),
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
                  if (isCapstone) _progressStep('Adviser Grading', adviserGrade != null),
                  _progressStep('Peer Evaluation', allPeerPosted),
                  _progressStep('Grades Published', gradeStatus == 'published'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = status == 'Approved'
        ? Colors.green
        : status == 'Failed'
            ? Colors.red
            : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _progressStep(String label, bool done) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? Colors.green : Colors.grey, size: 20),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  color: done ? Colors.black87 : Colors.grey,
                  fontWeight: done ? FontWeight.w600 : FontWeight.normal)),
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
          Icon(icon, size: 16, color: _primaryColor),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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
              color: _primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(role, style: const TextStyle(fontSize: 11, color: _primaryColor)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Container(width: 4, height: 20,
            decoration: BoxDecoration(color: _primaryColor, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryColor)),
      ],
    );
  }
}
