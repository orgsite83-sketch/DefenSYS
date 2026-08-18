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

    final gradeStatus = grades?['status'] ?? 'pending';
    final isPublished = grades?['is_published'] == true || gradeStatus == 'published';
    final hasPanel = grades?['has_panel_evaluated'] == true || grades?['panelist'] != null;
    final hasAdviser = grades?['has_adviser_graded'] == true || grades?['adviser'] != null;
    final peerEvalComplete = studentData?['peerEvalComplete'] == true || grades?['has_peer_completed'] == true;
    final myPeerEvalComplete = studentData?['myPeerEvalComplete'] == true;
    final peerEvalEnabled = studentData?['peerEvalEnabled'] == true;
    final stageName = grades?['stage'] ?? (schedule?['stage'] ?? (team['readyForStage'] ?? team['ready_for_stage'] ?? 'Defense Stage'));
    final result = grades?['result']?.toString().toUpperCase();

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
      {'label': 'Panel Evaluation', 'done': hasPanel},
      if (isCapstone)
        {'label': 'Adviser Grading', 'done': hasAdviser},
      {
        'label': peerEvalEnabled && !peerEvalComplete && myPeerEvalComplete
            ? 'Peer Evaluation (your part done)'
            : 'Peer Evaluation',
        'done': peerEvalComplete,
      },
      {'label': 'Evaluation Deliberation', 'done': isPublished},
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
        const SizedBox(height: 16),
        _sectionHeader('Defense Evaluation Status'),
        const SizedBox(height: 12),
        _defenseStatusCard(
          stageName: stageName.toString(),
          isPublished: isPublished,
          result: result,
          hasPanel: hasPanel,
          hasAdviser: hasAdviser,
          peerEvalComplete: peerEvalComplete,
          peerEvalEnabled: peerEvalEnabled,
          isCapstone: isCapstone,
        ),
        const SizedBox(height: 14),
        _officialGradeNotice(isCapstone: isCapstone),
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

  Widget _defenseStatusCard({
    required String stageName,
    required bool isPublished,
    required String? result,
    required bool hasPanel,
    required bool hasAdviser,
    required bool peerEvalComplete,
    required bool peerEvalEnabled,
    required bool isCapstone,
  }) {
    final bool isPassed = result == 'PASSED';
    final bool isFailed = result == 'FAILED' || result == 'RE-DEFENSE';

    final Color statusColor;
    final String statusLabel;
    final IconData statusIcon;

    if (isPublished) {
      if (isPassed) {
        statusColor = Colors.green;
        statusLabel = 'Stage Cleared · Passed';
        statusIcon = Icons.check_circle_outline;
      } else if (isFailed) {
        statusColor = const Color(0xFFD97706);
        statusLabel = 'Re-Defense Required';
        statusIcon = Icons.replay_circle_filled_outlined;
      } else {
        statusColor = DefensysTokens.maroon;
        statusLabel = 'Deliberation Complete';
        statusIcon = Icons.task_alt;
      }
    } else if (hasPanel) {
      statusColor = const Color(0xFF2563EB);
      statusLabel = 'Panel Evaluation Completed';
      statusIcon = Icons.rate_review_outlined;
    } else {
      statusColor = DefensysTokens.textSecondary;
      statusLabel = 'Pending Defense Schedule';
      statusIcon = Icons.hourglass_top_outlined;
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stage & Status Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stageName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: DefensysTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            // Evaluation Milestones
            _milestoneRow(
              title: 'Panel Defense Evaluation',
              isDone: hasPanel,
              accent: DefensysTokens.maroon,
            ),
            const SizedBox(height: 10),
            _milestoneRow(
              title: 'Team Peer Evaluation',
              isDone: peerEvalComplete,
              inProgress: peerEvalEnabled && !peerEvalComplete,
              accent: DefensysTokens.gold,
            ),
            if (isCapstone) ...[
              const SizedBox(height: 10),
              _milestoneRow(
                title: 'Project Adviser Evaluation',
                isDone: hasAdviser,
                accent: DefensysTokens.maroon,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _milestoneRow({
    required String title,
    required bool isDone,
    bool inProgress = false,
    required Color accent,
  }) {
    return Row(
      children: [
        Icon(
          isDone
              ? Icons.check_circle
              : inProgress
                  ? Icons.hourglass_top
                  : Icons.radio_button_unchecked,
          size: 18,
          color: isDone
              ? Colors.green
              : inProgress
                  ? DefensysTokens.gold
                  : Colors.grey.shade400,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isDone ? FontWeight.w600 : FontWeight.normal,
              color: isDone ? DefensysTokens.textPrimary : DefensysTokens.textSecondary,
            ),
          ),
        ),
        Text(
          isDone
              ? 'Completed'
              : inProgress
                  ? 'In Progress'
                  : 'Pending',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: isDone
                ? Colors.green
                : inProgress
                    ? DefensysTokens.gold
                    : Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Widget _officialGradeNotice({required bool isCapstone}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DefensysTokens.maroon.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DefensysTokens.maroon.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined, size: 20, color: DefensysTokens.maroon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Official Grade Inquiries & Audit',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.maroon,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isCapstone
                      ? 'To preserve academic confidentiality, detailed score breakdowns and peer evaluations are restricted. You may request an official Grade & Evaluation Audit Card through your Capstone Adviser or the Department Chairman.'
                      : 'To preserve academic confidentiality, detailed score breakdowns and peer evaluations are restricted. You may request an official Grade & Evaluation Audit Card through your Course Instructor, PIT Lead, or the Department Chairman.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: DefensysTokens.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
