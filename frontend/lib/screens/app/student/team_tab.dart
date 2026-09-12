import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/capstone_deliverables_provider.dart';
import '../../../theme/defensys_tokens.dart';

/// Screen 1: Academic Defense Overview & Student Team Workspace.
/// Features clean, professional white surfaces, crisp hairline borders,
/// direct deep-linking quick actions (Repository & Peer Eval sub-tab),
/// the "Upcoming PIT Event" (or "Current Defense Stage") spotlight,
/// and an interactive team roster list.
class TeamTab extends ConsumerStatefulWidget {
  final Map<String, dynamic>? studentData;
  final Future<void> Function()? onRefresh;
  final void Function(int index, {int? subTabIndex})? onSelectTab;

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
    final semester = team['semester']?.toString() ?? '';
    final schoolYear = team['schoolYear']?.toString() ?? '';
    final section = team['section']?.toString() ??
        widget.studentData?['section']?.toString() ??
        '';
    final yearLevel = team['yearLevel']?.toString() ??
        widget.studentData?['year_level']?.toString() ??
        '';
    final adviserName =
        team['adviserName']?.toString() ?? (isCapstone ? 'Unassigned' : 'N/A');

    // Dynamic stage resolution
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

    final schedule = studentData?['schedule'] as Map<String, dynamic>?;
    final grades = studentData?['grades'] as Map<String, dynamic>?;

    // Calculate deliverables file count
    final deliverables = (studentData?['deliverables'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    int fileCount = 0;
    for (final d in deliverables) {
      final files = d['files'] as List?;
      if (files != null && files.isNotEmpty) {
        fileCount += files.length;
      } else if (d['file_url'] != null || d['file_name'] != null) {
        fileCount += 1;
      }
    }
    if (fileCount == 0 && deliverables.isNotEmpty) {
      fileCount = deliverables.length;
    }

    final peerEvalComplete = studentData?['myPeerEvalComplete'] == true ||
        studentData?['peerEvalComplete'] == true;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. TEAM & PROJECT OVERVIEW (CLEAN WHITE CARD)
        _buildTeamHeaderCard(
          teamName: teamName,
          projectTitle: projectTitle,
          isCapstone: isCapstone,
          yearLevel: yearLevel,
          section: section,
          semester: semester,
          schoolYear: schoolYear,
          adviserName: adviserName,
        ),
        const SizedBox(height: 12),

        // 2. DIRECT ACTION SHORTCUTS (REPOSITORY & PEER EVAL SUB-TAB)
        _buildQuickActionCards(
          fileCount: fileCount,
          peerEvalComplete: peerEvalComplete,
          onSelectTab: onSelectTab,
        ),
        const SizedBox(height: 12),

        // 3. UPCOMING PIT EVENT (OR CURRENT DEFENSE STAGE)
        _buildUpcomingEventCard(
          activeStageName: activeStageName,
          schedule: schedule,
          grades: grades,
          isCapstone: isCapstone,
          onSelectTab: onSelectTab,
        ),
        const SizedBox(height: 12),

        // 4. TEAM MEMBERS ROSTER
        _buildTeamRosterCard(
          members: members,
          studentInfo: studentInfo,
          peerEvalComplete: peerEvalComplete,
          onSelectTab: onSelectTab,
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

  // ─── 1. TEAM & PROJECT OVERVIEW CARD ───────────────────────────────────────

  Widget _buildTeamHeaderCard({
    required String teamName,
    required String projectTitle,
    required bool isCapstone,
    required String yearLevel,
    required String section,
    required String semester,
    required String schoolYear,
    required String adviserName,
  }) {
    final monogram = _extractTeamMonogram(teamName);
    final termText = semester.isNotEmpty && schoolYear.isNotEmpty
        ? '$semester, AY $schoolYear'
        : (schoolYear.isNotEmpty ? 'AY $schoolYear' : '');

    final scopeLabel = isCapstone
        ? 'Capstone Project'
        : (yearLevel.isNotEmpty ? '$yearLevel PIT' : 'PIT Project');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: DefensysTokens.maroon.withValues(alpha: 0.2),
                  ),
                ),
                child: Center(
                  child: Text(
                    monogram,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: DefensysTokens.maroon,
                      letterSpacing: 0.5,
                    ),
                  ),
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
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: DefensysTokens.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      projectTitle,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: DefensysTokens.textSecondary,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: isCapstone
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isCapstone
                        ? const Color(0xFF86EFAC)
                        : const Color(0xFFFDE68A),
                  ),
                ),
                child: Text(
                  scopeLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isCapstone
                        ? const Color(0xFF15803D)
                        : const Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.school_outlined,
                      size: 13,
                      color: DefensysTokens.steelGrey,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '${section.isNotEmpty ? '$section · ' : ''}$termText',
                        style: const TextStyle(
                          fontSize: 11,
                          color: DefensysTokens.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.person_outline_rounded,
                    size: 14,
                    color: DefensysTokens.steelGrey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    adviserName != 'N/A' && adviserName != 'Unassigned'
                        ? 'Adviser: $adviserName'
                        : (isCapstone ? 'Adviser: Unassigned' : 'PIT Faculty Lead'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: DefensysTokens.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 2. QUICK ACTION SHORTCUTS (DIRECT DEEP NAVIGATION) ───────────────────

  Widget _buildQuickActionCards({
    required int fileCount,
    required bool peerEvalComplete,
    required void Function(int index, {int? subTabIndex})? onSelectTab,
  }) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => onSelectTab?.call(2), // Directly opens Tab 2 (Repository)
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.folder_outlined,
                      size: 18,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Repository',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: DefensysTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          fileCount > 0 ? '$fileCount Files' : 'Deliverables',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: DefensysTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 11,
                    color: DefensysTokens.steelGrey,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: () => onSelectTab?.call(1, subTabIndex: 2), // Directly opens Tab 1, Sub-tab 2 (Peer Eval)
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.rate_review_outlined,
                      size: 18,
                      color: DefensysTokens.maroon,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Peer Eval',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: DefensysTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          peerEvalComplete ? 'Completed ✓' : 'Review Peers',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: peerEvalComplete ? const Color(0xFF15803D) : DefensysTokens.maroon,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 11,
                    color: DefensysTokens.steelGrey,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── 3. UPCOMING PIT EVENT / CURRENT DEFENSE STAGE ─────────────────────────

  Widget _buildUpcomingEventCard({
    required String activeStageName,
    required Map<String, dynamic>? schedule,
    required Map<String, dynamic>? grades,
    required bool isCapstone,
    required void Function(int index, {int? subTabIndex})? onSelectTab,
  }) {
    final scheduledDate = schedule?['date']?.toString() ?? schedule?['scheduled_date']?.toString();
    final startTime = schedule?['start_time']?.toString() ?? schedule?['time']?.toString();
    final room = schedule?['room']?.toString();
    final hasSchedule = scheduledDate != null && scheduledDate.trim().isNotEmpty;
    final panelChair = schedule?['chair']?.toString() ?? schedule?['panel_chair']?.toString();
    final isPassed = grades != null && grades['result']?.toString().toUpperCase() == 'PASSED';

    String monthLabel = 'DATE';
    String dayLabel = '—';
    if (hasSchedule) {
      try {
        if (scheduledDate.contains('-')) {
          final parts = scheduledDate.split('-');
          if (parts.length == 3) {
            final m = int.tryParse(parts[1]) ?? 1;
            const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
            monthLabel = (m >= 1 && m <= 12) ? months[m - 1] : 'DATE';
            dayLabel = parts[2].split(' ')[0];
          }
        } else if (scheduledDate.contains('/')) {
          final parts = scheduledDate.split('/');
          if (parts.length == 3) {
            final m = int.tryParse(parts[0]) ?? 1;
            const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
            monthLabel = (m >= 1 && m <= 12) ? months[m - 1] : 'DATE';
            dayLabel = parts[1];
          }
        }
      } catch (_) {}
    }

    final cardTitle = isCapstone ? 'Current Defense Stage' : 'Upcoming PIT Event';

    return InkWell(
      onTap: () => onSelectTab?.call(1, subTabIndex: 0), // Directly opens Tab 1, Sub-tab 0 (Schedule)
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  cardTitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: DefensysTokens.textPrimary,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'View Details',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.maroon,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 12,
                      color: DefensysTokens.maroon,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (hasSchedule)
                  Container(
                    width: 48,
                    height: 52,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 2.5),
                          decoration: const BoxDecoration(
                            color: DefensysTokens.maroon,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
                          ),
                          child: Text(
                            monthLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              dayLabel,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: DefensysTokens.textPrimary,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: 46,
                    height: 46,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.event_note_outlined,
                      color: DefensysTokens.steelGrey,
                      size: 22,
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeStageName.isNotEmpty ? activeStageName : (isCapstone ? 'Concept Proposal' : 'Milestone Pitch'),
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: DefensysTokens.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      if (isPassed)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Cleared ✓  Score: ${grades['final_grade'] ?? grades['grade'] ?? 'Passed'}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF15803D),
                            ),
                          ),
                        )
                      else if (hasSchedule)
                        Text(
                          '${startTime?.isNotEmpty == true ? '$startTime · ' : ''}${room?.isNotEmpty == true ? room : 'Room TBA'}${panelChair != null ? ' · Chair: $panelChair' : ''}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: DefensysTokens.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      else
                        const Text(
                          'Preparation Phase · Awaiting schedule assignment',
                          style: TextStyle(
                            fontSize: 11,
                            color: DefensysTokens.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: DefensysTokens.steelGrey,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isCapstone
                        ? 'Evaluation: Panel Deliberation, Adviser Endorsement & Peer Reviews'
                        : 'Evaluation Formula: 80% Panel Deliberation · 20% Peer Review',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: DefensysTokens.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── 4. TEAM MEMBERS ROSTER LIST ───────────────────────────────────────────

  Widget _buildTeamRosterCard({
    required List<Map<String, dynamic>> members,
    required Map<String, dynamic>? studentInfo,
    required bool peerEvalComplete,
    required void Function(int index, {int? subTabIndex})? onSelectTab,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.group_outlined,
                    size: 16,
                    color: DefensysTokens.maroon,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Team Members (${members.length})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: DefensysTokens.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: peerEvalComplete
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  peerEvalComplete ? 'All Evaluated ✓' : 'Reviews Pending',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: peerEvalComplete ? const Color(0xFF15803D) : DefensysTokens.maroon,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No teammates listed yet.',
                style: TextStyle(fontSize: 11, color: DefensysTokens.textSecondary),
              ),
            )
          else
            ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: members.length,
              separatorBuilder: (context, index) => const Divider(
                height: 14,
                thickness: 0.8,
                color: Color(0xFFF1F5F9),
              ),
              itemBuilder: (context, index) {
                final m = members[index];
                final name = m['name']?.toString().trim() ?? 'Student';
                final isLeader = m['isLeader'] == true || m['is_leader'] == true;
                final username = m['username']?.toString() ?? m['id']?.toString() ?? '—';
                final isCurrent = m['id']?.toString() == studentInfo?['id']?.toString() ||
                    m['username']?.toString() == studentInfo?['username']?.toString();

                final initials = name.isNotEmpty
                    ? name.split(' ').where((w) => w.isNotEmpty).map((e) => e[0]).take(2).join().toUpperCase()
                    : 'S';

                return Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: isLeader
                          ? const Color(0xFF7F1D1D)
                          : DefensysTokens.maroon.withValues(alpha: 0.1),
                      child: Text(
                        initials,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isLeader ? Colors.white : DefensysTokens.maroon,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: DefensysTokens.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isCurrent)
                                const Text(
                                  ' (You)',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: DefensysTokens.steelGrey,
                                  ),
                                ),
                              if (isLeader) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFFDE68A)),
                                  ),
                                  child: const Text(
                                    'Leader',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'ID: $username',
                            style: const TextStyle(
                              fontSize: 10,
                              color: DefensysTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Self',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                            color: DefensysTokens.textSecondary,
                          ),
                        ),
                      )
                    else
                      InkWell(
                        onTap: () => onSelectTab?.call(1, subTabIndex: 2), // Directly opens Tab 1, Sub-tab 2 (Peer Eval)
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: DefensysTokens.maroon.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: DefensysTokens.maroon.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.edit_note_rounded,
                                size: 12,
                                color: DefensysTokens.maroon,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Evaluate',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: DefensysTokens.maroon,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  // ─── HELPER: EXTRACT TEAM MONOGRAM ─────────────────────────────────────────

  static String _extractTeamMonogram(String name) {
    final clean = name.replaceFirst(RegExp(r'^Team\s+', caseSensitive: false), '').trim();
    if (clean.isEmpty) return 'TM';
    final parts = clean.split(RegExp(r'[\s\-_]+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final matches = RegExp(r'[A-Z]').allMatches(clean).map((m) => m.group(0)!).toList();
    if (matches.length >= 2) {
      return '${matches[0]}${matches[1]}'.toUpperCase();
    }
    return clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
  }
}
