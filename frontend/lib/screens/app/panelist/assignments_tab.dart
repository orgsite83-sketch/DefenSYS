import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../theme/defensys_tokens.dart';
import 'panelist_models.dart';

class AssignmentsTab extends StatelessWidget {
  final List<TeamData> teams;
  final void Function(int teamIndex) onOpenGradeSheet;
  final Future<void> Function()? onRefresh;

  const AssignmentsTab({
    super.key,
    required this.teams,
    required this.onOpenGradeSheet,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (teams.isEmpty) {
      content = ListView(
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
    } else {
      // Separate teams into Capstone and PIT or show grouped list
      final capstoneTeams = <MapEntry<int, TeamData>>[];
      final pitTeams = <MapEntry<int, TeamData>>[];
      final otherTeams = <MapEntry<int, TeamData>>[];

      for (var entry in teams.asMap().entries) {
        if (entry.value.scope == 'capstone') {
          capstoneTeams.add(entry);
        } else if (entry.value.scope == 'pit') {
          pitTeams.add(entry);
        } else {
          otherTeams.add(entry);
        }
      }

      final hasMultipleCategories = (capstoneTeams.isNotEmpty && pitTeams.isNotEmpty);

      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader(
            'My Panel Assignments',
            subtitle: '${teams.length} ${teams.length == 1 ? 'Team' : 'Teams'} Assigned',
          ),
          const SizedBox(height: 16),

          if (hasMultipleCategories) ...[
            if (capstoneTeams.isNotEmpty) ...[
              _categoryHeader('Capstone Defenses', Icons.school, DefensysTokens.maroon),
              const SizedBox(height: 8),
              ...capstoneTeams.map((e) => _teamCard(e.key, e.value)),
              const SizedBox(height: 16),
            ],
            if (pitTeams.isNotEmpty) ...[
              _categoryHeader('PIT Expos & Events', Icons.badge, const Color(0xFF006666)),
              const SizedBox(height: 8),
              ...pitTeams.map((e) => _teamCard(e.key, e.value)),
              const SizedBox(height: 16),
            ],
            if (otherTeams.isNotEmpty) ...[
              _categoryHeader('Other Assignments', Icons.folder, Colors.grey.shade700),
              const SizedBox(height: 8),
              ...otherTeams.map((e) => _teamCard(e.key, e.value)),
            ],
          ] else ...[
            ...teams.asMap().entries.map((e) => _teamCard(e.key, e.value)),
          ],
        ],
      );
    }

    if (onRefresh == null) return content;
    return RefreshIndicator(
      color: DefensysTokens.maroon,
      onRefresh: onRefresh!,
      child: content,
    );
  }

  Widget _teamCard(int index, TeamData t) {
    final isPosted = t.isPosted;
    final hasValidScope = t.hasValidScope;
    final isLockedByDate = t.isLockedByDate;
    final isCapstone = t.scope == 'capstone';

    // Theme color based on scope
    final scopeColor = !hasValidScope
        ? Colors.orange.shade800
        : (isCapstone ? DefensysTokens.maroon : const Color(0xFF006666));

    final scopeBgColor = !hasValidScope
        ? Colors.orange.shade50
        : (isCapstone ? DefensysTokens.maroon.withValues(alpha: 0.08) : const Color(0xFF006666).withValues(alpha: 0.08));

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: scopeColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Banner with Scope & Stage Badge + Evaluation Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: scopeBgColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Event / Stage Pill + Chair Indicator
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: scopeColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasValidScope
                                ? (isCapstone ? Icons.school : Icons.badge)
                                : Icons.warning_amber_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            t.scopeLabel.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (t.isChair) ...[
                      const SizedBox(width: 6),
                      _chairBadge(),
                    ],
                  ],
                ),

                // Verdict Badge + Status Badge (Draft, Posted, Scheduled)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (t.hasVerdict) ...[
                      _verdictBadge(t.verdict),
                      const SizedBox(width: 6),
                    ],
                    isLockedByDate
                        ? _statusBadge('Scheduled')
                        : _statusBadge(isPosted ? 'Posted' : 'Draft'),
                  ],
                ),
              ],
            ),
          ),

          // Main Card Info (Team Name, Project, Schedule callout)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: scopeColor,
                      child: Text(
                        t.name.split(' ').last[0],
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.project,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade800,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Surfaced Schedule & Venue Row (Visible without expanding)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event, size: 16, color: scopeColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          t.defenseDate.isEmpty || t.defenseDate == 'Unscheduled'
                              ? 'Schedule Pending'
                              : t.defenseDate,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (!hasValidScope) ...[
                  const SizedBox(height: 8),
                  Text(
                    '⚠️ Missing schedule scope. Ask an admin to repair the schedule before grading.',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],

                // Expandable Details (Members & Full Controls)
                Theme(
                  data: ThemeData(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      'Team Members (${t.members.length})',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: t.members
                              .map(
                                (m) => Chip(
                                  label: Text(m, style: const TextStyle(fontSize: 11)),
                                  avatar: const Icon(Icons.person, size: 14),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Primary CTA Action Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: Icon(
                      isLockedByDate
                          ? Icons.lock_outline
                          : (isPosted ? Icons.visibility : Icons.edit_note),
                      size: 18,
                    ),
                    label: Text(
                      isLockedByDate
                          ? 'Grading Locked until ${t.scheduledDate != null ? DateFormat('MMMM d, yyyy').format(t.scheduledDate!) : 'scheduled date'}'
                          : (isPosted ? 'View Submitted Grades' : 'Open Grade Sheet'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLockedByDate ? Colors.grey.shade400 : scopeColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    onPressed: hasValidScope && !isLockedByDate
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
    final isScheduled = label == 'Scheduled';

    final badgeColor = isPosted
        ? Colors.green.shade700
        : isScheduled
            ? Colors.orange.shade800
            : Colors.blue.shade700;

    final badgeBg = isPosted
        ? Colors.green.shade50
        : isScheduled
            ? Colors.orange.shade50
            : Colors.blue.shade50;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPosted
                ? Icons.check_circle_outline
                : isScheduled
                    ? Icons.access_time
                    : Icons.edit,
            size: 12,
            color: badgeColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: badgeColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chairBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gavel_rounded, size: 11, color: Color(0xFF92400E)),
          SizedBox(width: 3),
          Text(
            'CHAIR',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF92400E),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _verdictBadge(String? verdict) {
    if (verdict == null || verdict.isEmpty) return const SizedBox.shrink();
    final isApproved = verdict == 'approved';
    final isRevisions = verdict == 'approved_with_revisions';
    final isForRedefense = verdict == 'for_redefense';

    final Color color = isApproved
        ? const Color(0xFF10B981)
        : isRevisions
            ? const Color(0xFFD97706)
            : isForRedefense
                ? const Color(0xFFEF4444)
                : Colors.grey;

    final String label = isApproved
        ? 'APPROVED'
        : isRevisions
            ? 'REVISIONS'
            : isForRedefense
                ? 'RE-DEFENSE'
                : verdict.toUpperCase();

    final IconData icon = isApproved
        ? Icons.check_circle
        : isRevisions
            ? Icons.edit_calendar
            : isForRedefense
                ? Icons.replay_rounded
                : Icons.info_outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {String? subtitle}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
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
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
      ],
    );
  }

  Widget _categoryHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(color: color.withValues(alpha: 0.2), thickness: 1),
          ),
        ],
      ),
    );
  }
}

