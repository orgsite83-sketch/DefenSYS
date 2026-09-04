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
  Timer? _countdownTimer;
  Duration? _timeUntilDefense;
  bool _isDefensePast = false;
  String? _selectedStageForView;

  @override
  void initState() {
    super.initState();
    _startCountdown();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final deliv = ref.read(capstoneDeliverablesProvider);
      if (deliv.teams.isNotEmpty) return;
      if (widget.onRefresh == null) return;

      final team = widget.studentData?['team'] as Map<String, dynamic>?;
      final isCapstone = team?['isCapstone'] == true;
      final yearLevel = widget.studentData?['year_level']?.toString().trim();

      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
            scope: isCapstone ? 'capstone' : 'pit',
            yearLevel: isCapstone ? null : (yearLevel?.isNotEmpty == true ? yearLevel : null),
          );
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _calculateRemainingTime();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _calculateRemainingTime();
        });
      }
    });
  }

  void _calculateRemainingTime() {
    final schedule = widget.studentData?['schedule'] as Map<String, dynamic>?;
    final dateStr = schedule?['date']?.toString();
    final timeStr = schedule?['startTime']?.toString() ?? schedule?['start_time']?.toString();

    if (dateStr == null || dateStr.trim().isEmpty) {
      _timeUntilDefense = null;
      _isDefensePast = false;
      return;
    }

    try {
      DateTime scheduledDate;
      if (timeStr != null && timeStr.contains(':')) {
        final parsedDate = DateTime.parse(dateStr);
        // Try parsing time
        final timeClean = timeStr.toUpperCase().replaceAll('AM', '').replaceAll('PM', '').trim();
        final timeParts = timeClean.split(':');
        int hour = int.tryParse(timeParts[0]) ?? 9;
        final minute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
        if (timeStr.toUpperCase().contains('PM') && hour < 12) hour += 12;
        scheduledDate = DateTime(parsedDate.year, parsedDate.month, parsedDate.day, hour, minute);
      } else {
        scheduledDate = DateTime.parse(dateStr);
      }

      final now = DateTime.now();
      final diff = scheduledDate.difference(now);

      if (diff.isNegative) {
        _isDefensePast = true;
        _timeUntilDefense = Duration.zero;
      } else {
        _isDefensePast = false;
        _timeUntilDefense = diff;
      }
    } catch (_) {
      _timeUntilDefense = null;
      _isDefensePast = false;
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

    // Stage resolution
    final stageOptions = delivState.stageOptions.isNotEmpty
        ? delivState.stageOptions
        : (isCapstone
            ? const ['Project Proposal', 'Colloquium', 'Final Defense']
            : const ['Milestone 1', 'Milestone 2', 'Final Showcase']);

    final activeStageName = teamData?['current_stage']?.toString() ??
        teamData?['current_defense_stage']?.toString() ??
        teamData?['ready_for_stage']?.toString() ??
        team['readyForStage']?.toString() ??
        team['ready_for_stage']?.toString() ??
        (stageOptions.isNotEmpty ? stageOptions.first : 'Project Proposal');

    final studentFullName = studentInfo?['name']?.toString() ?? 'Student';
    final isStudentLeader = members.any(
      (m) =>
          m['id']?.toString() == studentInfo?['id']?.toString() &&
          (m['isLeader'] == true || m['is_leader'] == true),
    );

    final stagesList =
        (teamData?['stages'] as List? ?? []).cast<Map<String, dynamic>>();

    final schedule = studentData?['schedule'] as Map<String, dynamic>?;
    final grades = studentData?['grades'] as Map<String, dynamic>?;

    final selectedStageName = (_selectedStageForView != null &&
            stageOptions.any((s) => s.trim().toLowerCase() == _selectedStageForView!.trim().toLowerCase()))
        ? _selectedStageForView!
        : activeStageName;

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

        // 2. CAPSTONE DEFENSE STAGES (HORIZONTAL PROGRESS STEPPER)
        _buildCapstoneStagesStepper(
          stageOptions: stageOptions,
          activeStageName: activeStageName,
          selectedStageName: selectedStageName,
          stagesList: stagesList,
          grades: grades,
          isCapstone: isCapstone,
          yearLevel: widget.studentData?['year_level']?.toString().trim(),
          onStageSelected: (stage) {
            setState(() {
              _selectedStageForView = stage;
            });
          },
        ),
        const SizedBox(height: 16),

        // 3. STAGE STATUS (DYNAMICALLY DISPLAYS SELECTED STAGE DETAILS)
        _buildStageStatusOverview(
          selectedStageName: selectedStageName,
          activeStageName: activeStageName,
          stageOptions: stageOptions,
          stagesList: stagesList,
          schedule: schedule,
          studentDeliverables: (studentData?['deliverables'] as List?)?.cast<Map<String, dynamic>>() ?? [],
          grades: grades,
          adviserName: adviserName,
          isCapstone: isCapstone,
          yearLevel: widget.studentData?['year_level']?.toString().trim(),
          onResetToActiveStage: () {
            setState(() {
              _selectedStageForView = activeStageName;
            });
          },
        ),
        const SizedBox(height: 16),

        // 4. PAST DEFENSE RESULTS & GRADES (DELIBERATION ACCORDIONS)
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

  // ─── 2. CAPSTONE DEFENSE STAGES (HORIZONTAL STEPPER) ─────────────────────────

  Widget _buildCapstoneStagesStepper({
    required List<String> stageOptions,
    required String activeStageName,
    required String selectedStageName,
    required List<Map<String, dynamic>> stagesList,
    required Map<String, dynamic>? grades,
    required bool isCapstone,
    required String? yearLevel,
    required ValueChanged<String> onStageSelected,
  }) {
    final activeStageIdx = stageOptions.indexWhere(
      (s) => s.trim().toLowerCase() == activeStageName.trim().toLowerCase(),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4.5),
                      decoration: BoxDecoration(
                        color: DefensysTokens.maroon.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.alt_route_rounded,
                        size: 15,
                        color: DefensysTokens.maroon,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'Capstone Defense Stages',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: DefensysTokens.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Stage ${activeStageIdx >= 0 ? activeStageIdx + 1 : 1} of ${stageOptions.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.maroon,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: const [
              Icon(
                Icons.touch_app_outlined,
                size: 11,
                color: DefensysTokens.textSecondary,
              ),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Tap any stage above to inspect its details in Stage Status below',
                  style: TextStyle(
                    fontSize: 10,
                    color: DefensysTokens.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Horizontal Progress Track
          LayoutBuilder(
            builder: (context, constraints) {
              final stepCount = stageOptions.length;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(stepCount * 2 - 1, (index) {
                  // Even index: Milestone Node
                  if (index % 2 == 0) {
                    final stageIdx = index ~/ 2;
                    final stageLabel = stageOptions[stageIdx];
                    final normStage = stageLabel.trim().toLowerCase();
                    final normActive = activeStageName.trim().toLowerCase();
                    final normSelected = selectedStageName.trim().toLowerCase();
                    final isSelected = normStage == normSelected;

                    final stageInfo = stagesList.firstWhere(
                      (s) =>
                          s['stage_label']?.toString().trim().toLowerCase() ==
                          normStage,
                      orElse: () => <String, dynamic>{},
                    );

                    final isCleared =
                        stageInfo['is_officially_complete'] == true ||
                            stageInfo['stage_status_detail']?.toString() ==
                                'passed' ||
                            stageInfo['stage_progress_status']?.toString() ==
                                'passed' ||
                            (stageIdx < activeStageIdx &&
                                activeStageIdx != -1);

                    final isActive = (stageIdx == activeStageIdx) ||
                        (!isCleared &&
                            (stageIdx == 0 || stageIdx <= activeStageIdx));

                    return Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: () {
                          onStageSelected(stageLabel);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Status label
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isCleared)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 2),
                                      child: Icon(
                                        Icons.check_circle_rounded,
                                        size: 9,
                                        color: Color(0xFF15803D),
                                      ),
                                    ),
                                  Text(
                                    isCleared
                                        ? 'Passed'
                                        : (isActive ? 'Current' : 'Upcoming'),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: isCleared
                                          ? const Color(0xFF15803D)
                                          : (isActive
                                              ? DefensysTokens.maroon
                                              : const Color(0xFF94A3B8)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),

                              // Node Circle with Selection Ring
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: isCleared
                                      ? const Color(0xFF16A34A)
                                      : (isActive
                                          ? DefensysTokens.maroon
                                          : const Color(0xFFF1F5F9)),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? (isCleared
                                            ? const Color(0xFF15803D)
                                            : DefensysTokens.maroon)
                                        : (isCleared
                                            ? const Color(0xFF16A34A)
                                            : (isActive
                                                ? DefensysTokens.maroon
                                                : const Color(0xFFCBD5E1))),
                                    width: isSelected ? 3.0 : (isActive ? 2.5 : 1.5),
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: (isCleared
                                                    ? const Color(0xFF16A34A)
                                                    : DefensysTokens.maroon)
                                                .withValues(alpha: 0.45),
                                            blurRadius: 10,
                                            spreadRadius: 2,
                                          ),
                                        ]
                                      : (isActive
                                          ? [
                                              BoxShadow(
                                                color: DefensysTokens.maroon
                                                    .withValues(alpha: 0.35),
                                                blurRadius: 8,
                                                spreadRadius: 1,
                                              ),
                                            ]
                                          : (isCleared
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(0xFF16A34A)
                                                        .withValues(alpha: 0.25),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ]
                                              : null)),
                                ),
                                child: Center(
                                  child: isCleared
                                      ? const Icon(
                                          Icons.check_rounded,
                                          size: 19,
                                          color: Colors.white,
                                        )
                                      : (isActive
                                          ? Text(
                                              '${stageIdx + 1}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.lock_outline_rounded,
                                              size: 14,
                                              color: Color(0xFF94A3B8),
                                            )),
                                ),
                              ),
                              const SizedBox(height: 6),

                              // Stage Title
                              Text(
                                stageLabel,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isSelected
                                      ? FontWeight.w900
                                      : (isActive
                                          ? FontWeight.w800
                                          : (isCleared
                                              ? FontWeight.w700
                                              : FontWeight.w600)),
                                  color: isSelected
                                      ? (isCleared
                                          ? const Color(0xFF15803D)
                                          : DefensysTokens.maroon)
                                      : (isActive
                                          ? DefensysTokens.textPrimary
                                          : (isCleared
                                              ? const Color(0xFF1E293B)
                                              : DefensysTokens.textSecondary)),
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isCleared
                                        ? const Color(0xFFDCFCE7)
                                        : DefensysTokens.maroon
                                            .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isCleared
                                          ? const Color(0xFF86EFAC)
                                          : DefensysTokens.maroon
                                              .withValues(alpha: 0.25),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    'Viewing ↓',
                                    style: TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.bold,
                                      color: isCleared
                                          ? const Color(0xFF15803D)
                                          : DefensysTokens.maroon,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  } else {
                    // Odd index: Connecting track line
                    final stageBeforeIdx = index ~/ 2;
                    final isLineCompleted = stageBeforeIdx < activeStageIdx;

                    return Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 28),
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: isLineCompleted
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    );
                  }
                }),
              );
            },
          ),
        ],
      ),
    );
  }

  // ─── 3. STAGE STATUS (DYNAMICALLY DISPLAYS SELECTED STAGE DETAILS) ─────────

  Widget _buildStageStatusOverview({
    required String selectedStageName,
    required String activeStageName,
    required List<String> stageOptions,
    required List<Map<String, dynamic>> stagesList,
    required Map<String, dynamic>? schedule,
    required List<Map<String, dynamic>> studentDeliverables,
    required Map<String, dynamic>? grades,
    required String adviserName,
    required bool isCapstone,
    required String? yearLevel,
    required VoidCallback onResetToActiveStage,
  }) {
    final normSelected = selectedStageName.trim().toLowerCase();
    final normActive = activeStageName.trim().toLowerCase();

    final selectedIdx = stageOptions.indexWhere(
      (s) => s.trim().toLowerCase() == normSelected,
    );
    final activeIdx = stageOptions.indexWhere(
      (s) => s.trim().toLowerCase() == normActive,
    );

    final stageInfo = stagesList.firstWhere(
      (s) => s['stage_label']?.toString().trim().toLowerCase() == normSelected,
      orElse: () => <String, dynamic>{},
    );

    final isCleared = stageInfo['is_officially_complete'] == true ||
        stageInfo['stage_status_detail']?.toString() == 'passed' ||
        stageInfo['stage_progress_status']?.toString() == 'passed' ||
        (selectedIdx != -1 && activeIdx != -1 && selectedIdx < activeIdx);

    final isActive = (normSelected == normActive);
    final isUpcoming = !isCleared && !isActive;

    // Resolve Grade / Deliberation data for selected stage
    final stageGradeMap = (stageInfo['grade'] as Map<String, dynamic>?) ??
        (grades != null &&
                grades['stage']?.toString().trim().toLowerCase() == normSelected
            ? grades
            : null);

    final finalScore = stageGradeMap?['final_grade'] ??
        stageGradeMap?['grade'] ??
        (isCleared ? (stageInfo['score'] ?? 'Passed') : null);

    final resultStr = stageGradeMap?['result']?.toString() ??
        (isCleared ? 'PASSED' : null);

    final completedDate = stageInfo['completed_date']?.toString() ??
        stageGradeMap?['completed_date']?.toString() ??
        stageGradeMap?['date']?.toString() ??
        'Completed';

    final remarks = stageGradeMap?['remarks']?.toString() ??
        stageInfo['remarks']?.toString();

    final presScore = stageGradeMap?['presentation']?.toString();
    final techScore = stageGradeMap?['technical']?.toString();
    final qnaScore = stageGradeMap?['qna']?.toString();

    // Resolve Deliverables for selected stage
    final rawDeliverables = (stageInfo['deliverables'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        (isActive ? studentDeliverables : []);

    // Resolve Schedule & Venue
    final activeScheduleDate = isActive
        ? (schedule != null ? schedule['date']?.toString() : null)
        : null;
    final dateStr = activeScheduleDate ??
        stageInfo['schedule']?['date']?.toString() ??
        (isCleared ? completedDate : null);

    final activeTime = isActive
        ? (schedule != null
            ? (schedule['startTime']?.toString() ??
                schedule['start_time']?.toString())
            : null)
        : null;
    final timeStr =
        activeTime ?? stageInfo['schedule']?['startTime']?.toString();

    final activeRoom = isActive
        ? (schedule != null ? schedule['room']?.toString() : null)
        : null;
    final roomStr = activeRoom ?? stageInfo['schedule']?['room']?.toString();

    final hasSchedule = dateStr != null && dateStr.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Maroon Header Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: DefensysTokens.maroon,
              borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_note_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Stage Status',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    selectedStageName,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // If viewing a non-active stage, display a clean navigation strip
                if (!isActive) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: isCleared
                          ? const Color(0xFFF0FDF4)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCleared
                            ? const Color(0xFFBBF7D0)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isCleared
                              ? Icons.history_rounded
                              : Icons.lock_clock_rounded,
                          size: 15,
                          color: isCleared
                              ? const Color(0xFF15803D)
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isCleared
                                ? 'Viewing records for passed stage: $selectedStageName'
                                : 'Viewing upcoming milestone: $selectedStageName',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: isCleared
                                  ? const Color(0xFF166534)
                                  : const Color(0xFF475569),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: onResetToActiveStage,
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: isCleared
                                  ? const Color(0xFFDCFCE7)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isCleared
                                    ? const Color(0xFF86EFAC)
                                    : const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: Text(
                              'Current ($activeStageName) →',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: isCleared
                                    ? const Color(0xFF15803D)
                                    : DefensysTokens.maroon,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── CASE 1: CLEARED / COMPLETED STAGE ──
                if (isCleared) ...[
                  // Deliberation Scorecard
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Color(0xFF16A34A),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.verified_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Deliberation Result: ${resultStr ?? 'PASSED'}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Official Grade: ${finalScore ?? 'Passed'} • $completedDate',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF166534),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: const Text(
                            'Passed ✓',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF15803D),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Rubric Criteria Breakdown (if available)
                  if (presScore != null ||
                      techScore != null ||
                      qnaScore != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
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
                    ),
                  ],

                  // Panel Remarks (if available)
                  if (remarks != null && remarks.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.format_quote_rounded,
                            size: 15,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Panel Feedback: "$remarks"',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontStyle: FontStyle.italic,
                                color: DefensysTokens.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 12),
                ]
                // ── CASE 2: ACTIVE STAGE ──
                else if (isActive) ...[
                  // Defense Venue & Schedule Row
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: hasSchedule
                        ? Row(
                            children: [
                              const Icon(
                                Icons.meeting_room_rounded,
                                size: 15,
                                color: DefensysTokens.maroon,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  roomStr?.isNotEmpty == true
                                      ? roomStr!
                                      : 'Room TBA',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: DefensysTokens.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '$dateStr${timeStr != null ? ' • $timeStr' : ''}',
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: DefensysTokens.maroon,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: const [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 14,
                                color: Color(0xFF64748B),
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Defense schedule will be posted once assigned by the panel.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: DefensysTokens.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),

                  // Live Defense Countdown / Schedule State
                  if (hasSchedule &&
                      _timeUntilDefense != null &&
                      !_isDefensePast) ...[
                    const Text(
                      'DEFENSE COUNTDOWN:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: DefensysTokens.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                            child: _buildCountdownDigit(
                                _timeUntilDefense!.inDays, 'Days')),
                        const SizedBox(width: 6),
                        Expanded(
                            child: _buildCountdownDigit(
                                _timeUntilDefense!.inHours % 24, 'Hours')),
                        const SizedBox(width: 6),
                        Expanded(
                            child: _buildCountdownDigit(
                                _timeUntilDefense!.inMinutes % 60, 'Mins')),
                        const SizedBox(width: 6),
                        Expanded(
                            child: _buildCountdownDigit(
                                _timeUntilDefense!.inSeconds % 60, 'Secs')),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 12),
                  ] else if (hasSchedule && _isDefensePast) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.history_rounded,
                              size: 14, color: Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Defense date passed ($dateStr). Awaiting deliberation evaluation.',
                              style: const TextStyle(
                                  fontSize: 10.5, color: Color(0xFF475569)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 12),
                  ],
                ]
                // ── CASE 3: UPCOMING STAGE ──
                else if (isUpcoming) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline_rounded,
                            size: 15, color: Color(0xFF64748B)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Upcoming milestone stage. Deliberation will unlock after passing $activeStageName.',
                            style: const TextStyle(
                              fontSize: 11,
                              color: DefensysTokens.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 12),
                ],

                // Required Deliverables Section for Selected Stage
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        isCleared
                            ? 'Stage Deliverables Cleared'
                            : 'Stage Deliverables',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: DefensysTokens.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.onSelectTab != null) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          ref
                              .read(capstoneDeliverablesProvider.notifier)
                              .fetchDeliverables(
                                scope: isCapstone ? 'capstone' : 'pit',
                                yearLevel: isCapstone
                                    ? null
                                    : (yearLevel?.isNotEmpty == true
                                        ? yearLevel
                                        : null),
                                selectedStage: selectedStageName,
                              );
                          widget.onSelectTab?.call(1);
                        },
                        child: const Text(
                          'Open Roadmap →',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: DefensysTokens.maroon,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                if (rawDeliverables.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: rawDeliverables.map((deliv) {
                      final name = deliv['name']?.toString() ??
                          deliv['title']?.toString() ??
                          deliv['label']?.toString() ??
                          'Document';
                      final status = isCleared
                          ? 'Approved'
                          : (deliv['status']?.toString() ??
                              deliv['submission_status']?.toString() ??
                              'Pending');

                      final isApproved = status.toLowerCase() == 'approved' ||
                          status.toLowerCase() == 'passed';
                      final isSubmitted = status.toLowerCase() == 'submitted' ||
                          status.toLowerCase() == 'uploaded';

                      final chipColor = isApproved
                          ? const Color(0xFF15803D)
                          : (isSubmitted
                              ? const Color(0xFF7F1D1D)
                              : const Color(0xFF64748B));

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: chipColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: DefensysTokens.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      isCleared
                          ? 'All manuscripts & deliverables verified and cleared for this milestone.'
                          : 'No specific deliverables required for this milestone yet.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: DefensysTokens.textSecondary,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 12),

                // Adviser Approval Status Row
                Row(
                  children: [
                    const Icon(
                      Icons.verified_user_rounded,
                      size: 16,
                      color: Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Adviser: $adviserName',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: DefensysTokens.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            isCleared
                                ? 'Official Milestone Endorsed & Completed ✓'
                                : 'Approved & Endorsed for Defense ✓',
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: Color(0xFF15803D),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── DIGIT TILE HELPER ─────────────────────────────────────────────────────

  Widget _buildCountdownDigit(int value, String unit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value.toString().padLeft(2, '0'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: DefensysTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            unit,
            style: const TextStyle(
              fontSize: 8,
              color: DefensysTokens.textSecondary,
              fontWeight: FontWeight.w600,
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
        'stage_label': grades['stage']?.toString() ?? 'Project Proposal',
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
