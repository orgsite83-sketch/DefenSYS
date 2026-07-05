import 'package:flutter/material.dart';

import '../../../theme/defensys_tokens.dart';

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

    final teamName = team['name'] ?? 'Unknown Team';
    final projectTitle = team['projectTitle'] ?? team['project_title'] ?? '—';
    final systemName = team['system_name'] ?? team['systemName'] ?? '';
    final projectManagerName = team['project_manager_name'] ?? team['projectManagerName'] ?? '';
    final level = team['level'] ?? '—';
    final status = team['status'] ?? 'Pending';
    
    final adviserName = team['adviserName'] ?? (isCapstone ? 'Unassigned' : 'N/A');

    final scheduleStr = schedule != null
        ? '${schedule['date']} — ${schedule['startTime']}'
        : 'Not yet scheduled';
    final roomStr = schedule?['room'] ?? '—';

    final panelGrade = grades?['panelist'] as Map<String, dynamic>?;
    final peerGrade = grades?['peer'] as Map<String, dynamic>?;
    final finalGrade = grades?['finalGrade'];
    final adviserGrade = grades?['adviser'];
    final gradeStatus = grades?['status'] ?? 'pending';
    final peerEvalComplete = studentData?['peerEvalComplete'] == true;
    final myPeerEvalComplete = studentData?['myPeerEvalComplete'] == true;
    final peerEvalEnabled = studentData?['peerEvalEnabled'] == true;

    final weights = (studentData?['weights'] as Map<String, dynamic>?) ??
        {'panel': 80, 'peer': 20};
    final panelW = (weights['panel'] as num?)?.toInt() ?? 80;
    final peerW = (weights['peer'] as num?)?.toInt() ?? 20;
    final isPublished = gradeStatus == 'published';
    final peerPending =
        peerEvalEnabled && !peerEvalComplete && panelGrade != null;

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

    final steps = [
      {'label': 'Team Registered', 'done': true},
      {'label': 'Defense Scheduled', 'done': schedule != null},
      {'label': 'Panel Evaluation', 'done': panelGrade != null},
      if (isCapstone)
        {'label': 'Adviser Grading', 'done': adviserGrade != null},
      {
        'label': peerEvalEnabled && !peerEvalComplete && myPeerEvalComplete
            ? 'Peer Evaluation (your part done)'
            : 'Peer Evaluation',
        'done': peerEvalComplete,
      },
      {'label': 'Grades Published', 'done': gradeStatus == 'published'},
    ];

    int activeIndex = steps.indexWhere((step) => !(step['done'] as bool));
    if (activeIndex == -1) {
      activeIndex = steps.length - 1;
    }

    final scrollContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Team Icon, Name/Level, Status badge
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
                
                // Project panel
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
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
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 2-Column horizontal metadata grid
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isCapstone)
                      Expanded(
                        child: _infoBox(
                          icon: Icons.person_pin_outlined,
                          label: 'Adviser',
                          value: adviserName,
                        ),
                      ),
                    if (isCapstone) const SizedBox(width: 12),
                    Expanded(
                      child: _infoBox(
                        icon: Icons.calendar_today_outlined,
                        label: 'Defense Schedule',
                        value: scheduleStr,
                        subtitle: schedule != null ? roomStr : null,
                      ),
                    ),
                  ],
                ),
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
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Column(
              children: List.generate(steps.length, (index) {
                final step = steps[index];
                return _progressStep(
                  label: step['label'] as String,
                  isCompleted: step['done'] as bool,
                  isActive: index == activeIndex,
                  isLast: index == steps.length - 1,
                );
              }),
            ),
          ),
        ),
        if (!isCapstone) ...[
          const SizedBox(height: 16),
          _sectionHeader('My Grades'),
          const SizedBox(height: 12),
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
        const SizedBox(height: 24),
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

  String _getInitials(String name) {
    if (name.isEmpty) return '—';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length > 1) {
      final first = parts[0];
      final last = parts[parts.length - 1];
      if (first.isNotEmpty && last.isNotEmpty) {
        return (first[0] + last[0]).toUpperCase();
      }
    }
    return name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '—';
  }

  Color _getAvatarColor(String name) {
    final colors = [
      const Color(0xFFE57373),
      const Color(0xFFF06292),
      const Color(0xFFBA68C8),
      const Color(0xFF9575CD),
      const Color(0xFF7986CB),
      const Color(0xFF64B5F6),
      const Color(0xFF4FC3F7),
      const Color(0xFF4DB6AC),
      const Color(0xFF81C784),
      const Color(0xFFAED581),
      const Color(0xFFFFB74D),
      const Color(0xFFFF8A65),
    ];
    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return colors[hash.abs() % colors.length];
  }

  Widget _progressStep({
    required String label,
    required bool isCompleted,
    required bool isActive,
    required bool isLast,
  }) {
    Widget indicatorWidget = isCompleted
        ? const Icon(Icons.check_circle, color: Colors.green, size: 22)
        : isActive
            ? Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: DefensysTokens.maroon, width: 2),
                ),
                child: Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: DefensysTokens.maroon,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              )
            : Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                ),
              );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              indicatorWidget,
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: isCompleted ? Colors.green.shade300 : Colors.grey.shade300,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      color: isCompleted
                          ? DefensysTokens.textPrimary
                          : isActive
                              ? DefensysTokens.maroon
                              : DefensysTokens.textSecondary,
                      fontWeight: (isActive || isCompleted)
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  if (isActive) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Current Stage',
                      style: TextStyle(
                        fontSize: 11,
                        color: DefensysTokens.maroon.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBox({
    required IconData icon,
    required String label,
    required String value,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DefensysTokens.background.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DefensysTokens.border.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: DefensysTokens.maroon),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: DefensysTokens.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DefensysTokens.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberTile(String name, String role) {
    final isLeader = role.toLowerCase().contains('leader');
    final initials = _getInitials(name);
    final avatarColor = _getAvatarColor(name);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: avatarColor.withValues(alpha: 0.15),
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: avatarColor.withValues(alpha: 0.9),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: DefensysTokens.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isLeader)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: DefensysTokens.maroon,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Leader',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
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
          height: 18,
          decoration: BoxDecoration(
            color: DefensysTokens.maroon,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: DefensysTokens.maroon,
          ),
        ),
      ],
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
                  color: accent.withValues(alpha: 0.12),
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
                color: accent.withValues(alpha: 0.12),
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
      color: DefensysTokens.maroon.withValues(alpha: 0.04),
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
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withValues(alpha: 0.4)),
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
}
