import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/capstone_deliverables_provider.dart';
import '../../../theme/defensys_tokens.dart';

/// Screen 1: Academic Defense Overview & Milestone Hub.
/// Features a unified top team identity & roster, academic defense milestone stepper,
/// live defense overview (schedule, room, dynamic deliverables, adviser endorsement),
/// and past deliberation grades & results.
class TeamTab extends ConsumerStatefulWidget {
  final Map<String, dynamic>? studentData;
  final Future<void> Function()? onRefresh;
  final void Function(int index)? onSelectTab;

  const TeamTab({
    super.key,
    required this.studentData,
    this.onRefresh,
    this.onSelectTab,
  });

  @override
  ConsumerState<TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends ConsumerState<TeamTab> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.onRefresh == null) return;
      final team = widget.studentData?['team'] as Map<String, dynamic>?;
      if (team == null) return;
      final deliv = ref.read(capstoneDeliverablesProvider);
      if (deliv.stageOptions.isNotEmpty) return;

      final isCapstone = team['isCapstone'] == true;
      final yearLevel = widget.studentData?['year_level']?.toString().trim();

      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
            scope: isCapstone ? 'capstone' : 'pit',
            yearLevel: isCapstone ? null : (yearLevel?.isNotEmpty == true ? yearLevel : null),
          );
    });
  }

  @override
  void didUpdateWidget(TeamTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onRefresh == null) return;
    final oldTeam = oldWidget.studentData?['team'];
    final newTeam = widget.studentData?['team'] as Map<String, dynamic>?;
    final deliv = ref.read(capstoneDeliverablesProvider);
    if ((oldTeam == null && newTeam != null) || (deliv.stageOptions.isEmpty && newTeam != null)) {
      final isCapstone = newTeam['isCapstone'] == true;
      final yearLevel = widget.studentData?['year_level']?.toString().trim();
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
            scope: isCapstone ? 'capstone' : 'pit',
            yearLevel: isCapstone ? null : (yearLevel?.isNotEmpty == true ? yearLevel : null),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final studentData = widget.studentData;
    final onRefresh = widget.onRefresh;
    final onSelectTab = widget.onSelectTab;

    final team = studentData?['team'] as Map<String, dynamic>?;
    final members =
        (studentData?['members'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final studentInfo = studentData?['student'] as Map<String, dynamic>?;
    final isCapstone = team?['isCapstone'] == true;

    if (team == null) {
      final emptyContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.group_off_rounded,
                  size: 48,
                  color: DefensysTokens.maroon,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Team Assigned Yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: DefensysTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'You will see your project details, defense timeline, and teammate roster once an instructor or administrator assigns you to a team.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: DefensysTokens.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              if (onRefresh != null)
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh Status'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DefensysTokens.maroon,
                    side: const BorderSide(color: DefensysTokens.maroon),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

      if (onRefresh == null) return emptyContent;

      return RefreshIndicator(
        color: DefensysTokens.maroon,
        onRefresh: onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: emptyContent,
          ),
        ),
      );
    }

    final delivState = ref.watch(capstoneDeliverablesProvider);
    final teamData = delivState.teams.firstOrNull;

    final teamName = team['name']?.toString() ?? 'Team Project';
    final projectTitle = team['projectTitle']?.toString() ??
        team['project_title']?.toString() ??
        'Untitled Project';
    final systemName =
        team['system_name']?.toString() ?? team['systemName']?.toString() ?? '';
    final semester = team['semester']?.toString() ?? '';
    final schoolYear = team['schoolYear']?.toString() ?? '';
    final adviserName =
        team['adviserName']?.toString() ?? (isCapstone ? 'Unassigned' : 'N/A');

    // Dynamic stage resolution from deliverables provider or studentData
    final backendStageOptions = (widget.studentData?['stage_options'] as List?)
            ?.map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const <String>[];

    final stagesList = (teamData?['stages'] as List? ??
            widget.studentData?['stages'] as List? ??
            [])
        .cast<Map<String, dynamic>>();

    final stagesListOptions = stagesList
        .map((s) => s['stage_label']?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    final stageOptions = delivState.stageOptions.isNotEmpty
        ? delivState.stageOptions
        : (backendStageOptions.isNotEmpty
            ? backendStageOptions
            : stagesListOptions);

    final rawActiveStageName = teamData?['current_stage']?.toString() ??
        teamData?['current_defense_stage']?.toString() ??
        teamData?['ready_for_stage']?.toString() ??
        team['currentStage']?.toString() ??
        team['readyForStage']?.toString() ??
        team['ready_for_stage']?.toString() ??
        widget.studentData?['current_stage']?.toString() ??
        (stageOptions.isNotEmpty ? stageOptions.first : '');

    final activeStageName = stageOptions.any((s) => s.trim().toLowerCase() == rawActiveStageName.trim().toLowerCase())
        ? rawActiveStageName
        : (stageOptions.isNotEmpty ? stageOptions.first : rawActiveStageName);

    final studentFullName = studentInfo?['name']?.toString() ?? 'Student';
    final isStudentLeader = members.any(
      (m) =>
          m['id']?.toString() == studentInfo?['id']?.toString() &&
          (m['isLeader'] == true || m['is_leader'] == true),
    );

    final schedule = studentData?['schedule'] as Map<String, dynamic>?;
    final grades = studentData?['grades'] as Map<String, dynamic>?;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. UNIFIED TOP TEAM & PROJECT CARD (WITH ROSTER & PEER EVALUATION)
        _buildUnifiedTopTeamCard(
          studentFullName: studentFullName,
          isLeader: isStudentLeader,
          teamName: teamName,
          projectTitle: projectTitle,
          systemName: systemName,
          semester: semester,
          schoolYear: schoolYear,
          adviserName: adviserName,
          activeStageName: activeStageName,
          members: members,
          onSelectTab: onSelectTab,
          peerEvalComplete: studentData?['myPeerEvalComplete'] == true ||
              studentData?['peerEvalComplete'] == true,
        ),
        const SizedBox(height: 14),

        // 2. DEFENSE MILESTONE PROGRESS & ROADMAP ACCESS
        _buildMilestoneRoadmapShortcutCard(
          activeStageName: activeStageName,
          stageOptions: stageOptions,
          stagesList: stagesList,
          schedule: schedule,
          isCapstone: isCapstone,
          onSelectTab: onSelectTab,
        ),
        const SizedBox(height: 16),

        // 3. PAST DEFENSE RESULTS & GRADES (DELIBERATION ACCORDIONS)
        _buildPastDefenseResultsSection(
          stageOptions: stageOptions,
          activeStageName: activeStageName,
          stagesList: stagesList,
          grades: grades,
        ),
        const SizedBox(height: 24),
      ],
    );

    if (onRefresh == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: content,
      );
    }

    return RefreshIndicator(
      color: DefensysTokens.maroon,
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: content,
      ),
    );
  }

  // ─── 1. UNIFIED TOP TEAM & PROJECT CARD WITH INTEGRATED ROSTER ─────────────

  Widget _buildUnifiedTopTeamCard({
    required String studentFullName,
    required bool isLeader,
    required String teamName,
    required String projectTitle,
    required String systemName,
    required String semester,
    required String schoolYear,
    required String adviserName,
    required String activeStageName,
    required List<Map<String, dynamic>> members,
    required void Function(int index)? onSelectTab,
    required bool peerEvalComplete,
  }) {
    final firstName = studentFullName.trim().split(' ').first;
    final termText = semester.isNotEmpty && schoolYear.isNotEmpty
        ? '$semester, AY $schoolYear'
        : (schoolYear.isNotEmpty ? 'AY $schoolYear' : '');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Student Greeting + Leader Star + Active Stage Capsule
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          DefensysTokens.maroon.withValues(alpha: 0.1),
                      child: Text(
                        firstName.isNotEmpty ? firstName[0].toUpperCase() : 'S',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: DefensysTokens.maroon,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Hi, $firstName',
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                    color: DefensysTokens.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isLeader) ...[
                                const SizedBox(width: 4),
                                Tooltip(
                                  message: 'Team Leader',
                                  child: Container(
                                    padding: const EdgeInsets.all(2.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B)
                                          .withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFFF59E0B),
                                        width: 1,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.star_rounded,
                                      size: 11,
                                      color: Color(0xFFD97706),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (termText.isNotEmpty)
                            Text(
                              termText,
                              style: const TextStyle(
                                fontSize: 10,
                                color: DefensysTokens.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Active Stage Pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: DefensysTokens.maroon.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.radar_rounded,
                      size: 12,
                      color: DefensysTokens.maroon,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      activeStageName,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: DefensysTokens.maroon,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Project Title & Adviser Info Strip
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.school_rounded,
                  size: 13,
                  color: DefensysTokens.maroon,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${teamName.toUpperCase()} • $projectTitle${adviserName != 'N/A' && adviserName != 'Unassigned' ? ' • Adviser: $adviserName' : ''}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: DefensysTokens.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Row 3: Integrated Team Members Roster & Peer Review Button
          Row(
            children: [
              // Team Roster Label & Avatar Bubbles
              Expanded(
                child: Row(
                  children: [
                    Text(
                      'Members (${members.length}):',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: DefensysTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: members.map((m) {
                            final name = m['name']?.toString() ?? 'S';
                            final isMembLeader = m['isLeader'] == true ||
                                m['is_leader'] == true;
                            final initials = name.isNotEmpty
                                ? name
                                    .split(' ')
                                    .map((e) => e.isNotEmpty ? e[0] : '')
                                    .take(2)
                                    .join()
                                    .toUpperCase()
                                : 'S';

                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Tooltip(
                                message:
                                    '$name ${isMembLeader ? '(Leader)' : ''}',
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    CircleAvatar(
                                      radius: 12,
                                      backgroundColor: isMembLeader
                                          ? const Color(0xFF7F1D1D)
                                          : DefensysTokens.maroon
                                              .withValues(alpha: 0.12),
                                      child: Text(
                                        initials,
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.bold,
                                          color: isMembLeader
                                              ? Colors.white
                                              : DefensysTokens.maroon,
                                        ),
                                      ),
                                    ),
                                    if (isMembLeader)
                                      Positioned(
                                        right: -2,
                                        bottom: -2,
                                        child: Container(
                                          padding: const EdgeInsets.all(1.5),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFF59E0B),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.star,
                                              size: 6.5, color: Colors.white),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Peer Review Action Button
              InkWell(
                onTap: () => onSelectTab?.call(1),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: peerEvalComplete
                        ? const Color(0xFFDCFCE7)
                        : DefensysTokens.maroon.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: peerEvalComplete
                          ? const Color(0xFF86EFAC)
                          : DefensysTokens.maroon.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        peerEvalComplete
                            ? Icons.check_circle_rounded
                            : Icons.rate_review_rounded,
                        size: 11,
                        color: peerEvalComplete
                            ? const Color(0xFF15803D)
                            : DefensysTokens.maroon,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        peerEvalComplete ? 'Peer Eval ✓' : 'Peer Eval →',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: peerEvalComplete
                              ? const Color(0xFF15803D)
                              : DefensysTokens.maroon,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 2. DEFENSE MILESTONE PROGRESS & ROADMAP ACCESS CARD ────────────────────

  Widget _buildMilestoneRoadmapShortcutCard({
    required String activeStageName,
    required List<String> stageOptions,
    required List<Map<String, dynamic>> stagesList,
    required Map<String, dynamic>? schedule,
    required bool isCapstone,
    required void Function(int index)? onSelectTab,
  }) {
    final activeStageIdx = stageOptions.indexWhere(
      (s) => s.trim().toLowerCase() == activeStageName.trim().toLowerCase(),
    );
    final stageNumber = activeStageIdx >= 0 ? activeStageIdx + 1 : 1;
    final totalStages = stageOptions.isNotEmpty ? stageOptions.length : 1;
    final progressFraction = (stageNumber / totalStages).clamp(0.0, 1.0);

    final scheduledDate = schedule?['date']?.toString() ?? schedule?['scheduled_date']?.toString();
    final room = schedule?['room']?.toString();
    final hasSchedule = scheduledDate != null && scheduledDate.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  isCapstone ? Icons.alt_route_rounded : Icons.event_available_rounded,
                  size: 18,
                  color: DefensysTokens.maroon,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isCapstone ? 'Capstone Defense Roadmap' : 'Milestone Roadmap',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: DefensysTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Current: $activeStageName · Stage $stageNumber of $totalStages',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: const Text(
                  'Active Stage',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: DefensysTokens.maroon,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Milestone Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progressFraction,
              minHeight: 6,
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: const AlwaysStoppedAnimation<Color>(DefensysTokens.maroon),
            ),
          ),
          const SizedBox(height: 12),

          // Defense status snippet
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Icon(
                  hasSchedule ? Icons.calendar_today_rounded : Icons.info_outline_rounded,
                  size: 14,
                  color: hasSchedule ? DefensysTokens.maroon : const Color(0xFF64748B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasSchedule
                        ? 'Defense Scheduled: $scheduledDate${room?.isNotEmpty == true ? ' · $room' : ''}'
                        : 'Defense schedule will be posted once assigned by the panel.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: hasSchedule ? FontWeight.w600 : FontWeight.normal,
                      color: hasSchedule ? DefensysTokens.textPrimary : DefensysTokens.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Full-width CTA Button to jump to Stages tab
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                onSelectTab?.call(1);
              },
              icon: const Icon(Icons.alt_route_rounded, size: 16),
              label: const Text(
                'Open Defense Roadmap & Stages →',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: DefensysTokens.maroon,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 4. PAST DEFENSE RESULTS & GRADES (DELIBERATION ACCORDIONS) ────────────

  Widget _buildPastDefenseResultsSection({
    required List<String> stageOptions,
    required String activeStageName,
    required List<Map<String, dynamic>> stagesList,
    required Map<String, dynamic>? grades,
  }) {
    final passedStages = <Map<String, dynamic>>[];

    for (final stage in stagesList) {
      if (stage['is_officially_complete'] == true ||
          stage['stage_status_detail']?.toString() == 'passed' ||
          stage['stage_progress_status']?.toString() == 'passed') {
        passedStages.add(stage);
      }
    }

    // If empty and mock studentData grades are passed, use real grades map
    if (passedStages.isEmpty &&
        grades != null &&
        grades['result']?.toString().toUpperCase() == 'PASSED') {
      passedStages.add({
        'stage_label': grades['stage']?.toString() ?? (stageOptions.isNotEmpty ? stageOptions.first : ''),
        'grade': grades,
        'completed_date': 'Completed',
      });
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.history_edu_rounded,
                  size: 15,
                  color: Color(0xFF16A34A),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Past Defense Results & Grades',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: DefensysTokens.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Passed Stage Scorecard Tiles
          if (passedStages.isNotEmpty) ...[
            ...passedStages.map((stg) {
              final stageName = stg['stage_label']?.toString() ?? 'Stage';
              final gradeMap = stg['grade'] as Map<String, dynamic>?;
              final score = gradeMap?['final_grade'] ??
                  gradeMap?['grade'] ??
                  'Passed';
              final completedDate =
                  stg['completed_date']?.toString() ?? 'Completed';
              final remarks = gradeMap?['remarks']?.toString();

              final presScore = gradeMap?['presentation']?.toString();
              final techScore = gradeMap?['technical']?.toString();
              final qnaScore = gradeMap?['qna']?.toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  tilePadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  shape: const Border(),
                  leading: Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDCFCE7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_rounded,
                      size: 16,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stageName,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: DefensysTokens.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              completedDate,
                              style: const TextStyle(
                                fontSize: 10,
                                color: DefensysTokens.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: Text(
                          'Score: $score (Passed)',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ),
                    ],
                  ),
                  children: [
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 8),
                    // Criteria breakdown if available
                    if (presScore != null ||
                        techScore != null ||
                        qnaScore != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          if (presScore != null)
                            _buildCriteriaScore('Presentation', '$presScore/30'),
                          if (techScore != null)
                            _buildCriteriaScore('Technical', '$techScore/50'),
                          if (qnaScore != null)
                            _buildCriteriaScore('Q&A Defense', '$qnaScore/20'),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    // Feedback / Remarks
                    if (remarks != null && remarks.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          'Panel Feedback: "$remarks"',
                          style: const TextStyle(
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                            color: DefensysTokens.textSecondary,
                          ),
                        ),
                      ),
                    ] else ...[
                      const Center(
                        child: Text(
                          'Official status: Stage passed & endorsed.',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF15803D),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text(
                'No past defense deliberation records on file for this academic year yet.',
                style: TextStyle(
                  fontSize: 11,
                  color: DefensysTokens.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── CRITERIA SCORE HELPER ─────────────────────────────────────────────────

  Widget _buildCriteriaScore(String label, String score) {
    return Column(
      children: [
        Text(
          score,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: DefensysTokens.textPrimary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: DefensysTokens.textSecondary,
          ),
        ),
      ],
    );
  }
}
