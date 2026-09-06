import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/capstone_deliverables_provider.dart';
import '../../../theme/defensys_tokens.dart';

/// Screen 2: Dedicated Modular Bento Stage Flight Deck.
/// Displays deep-dive operational intelligence, clearance meters, deliverables,
/// defense dispatch, panel evaluation, and peer review for any selected academic stage.
class StageFlightDeckScreen extends ConsumerStatefulWidget {
  final String stageLabel;
  final Map<String, dynamic>? studentData;
  final Future<void> Function()? onRefresh;
  final void Function(int index)? onSelectTab;
  final VoidCallback? onBackToJourney;
  final bool isEmbedded;

  const StageFlightDeckScreen({
    super.key,
    required this.stageLabel,
    required this.studentData,
    this.onRefresh,
    this.onSelectTab,
    this.onBackToJourney,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<StageFlightDeckScreen> createState() =>
      _StageFlightDeckScreenState();
}

class _StageFlightDeckScreenState extends ConsumerState<StageFlightDeckScreen> {
  late String _currentStageLabel;

  @override
  void initState() {
    super.initState();
    _currentStageLabel = widget.stageLabel;
  }

  @override
  void didUpdateWidget(covariant StageFlightDeckScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stageLabel != widget.stageLabel) {
      _currentStageLabel = widget.stageLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final delivState = ref.watch(capstoneDeliverablesProvider);
    final teamData = delivState.teams.firstOrNull;
    final team = widget.studentData?['team'] as Map<String, dynamic>?;
    final isCapstone = team?['isCapstone'] == true;

    // Available stage options dynamically resolved without hardcoding
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

    if (!stageOptions.contains(_currentStageLabel) && stageOptions.isNotEmpty) {
      _currentStageLabel = stageOptions.first;
    }

    final rawActiveStageName = teamData?['current_stage']?.toString() ??
        teamData?['current_defense_stage']?.toString() ??
        teamData?['ready_for_stage']?.toString() ??
        team?['currentStage']?.toString() ??
        team?['readyForStage']?.toString() ??
        widget.studentData?['current_stage']?.toString() ??
        (stageOptions.isNotEmpty ? stageOptions.first : '');

    final activeStageName = stageOptions.any((s) => s.trim().toLowerCase() == rawActiveStageName.trim().toLowerCase())
        ? rawActiveStageName
        : (stageOptions.isNotEmpty ? stageOptions.first : rawActiveStageName);

    final stageInfo = stagesList.firstWhere(
      (s) =>
          s['stage_label']?.toString().trim().toLowerCase() ==
          _currentStageLabel.trim().toLowerCase(),
      orElse: () => <String, dynamic>{},
    );

    final normCurrent = _currentStageLabel.trim().toLowerCase();
    final normActive = activeStageName.trim().toLowerCase();
    final stageIndex =
        stageOptions.indexWhere((s) => s.trim().toLowerCase() == normCurrent);
    final activeIndex =
        stageOptions.indexWhere((s) => s.trim().toLowerCase() == normActive);

    final isOfficiallyComplete = stageInfo['is_officially_complete'] == true ||
        stageInfo['stage_status_detail']?.toString() == 'passed' ||
        stageInfo['stage_progress_status']?.toString() == 'passed' ||
        (stageIndex != -1 && activeIndex != -1 && stageIndex < activeIndex);

    final isActiveStage = (stageIndex != -1 && stageIndex == activeIndex) ||
        (!isOfficiallyComplete &&
            (stageIndex == -1 || activeIndex == -1 || stageIndex <= activeIndex));

    final isUpcoming = !isOfficiallyComplete && !isActiveStage;

    // Schedule info
    final scheduleData = widget.studentData?['schedule'] as Map<String, dynamic>?;
    final scheduleStage = scheduleData != null ? scheduleData['stage']?.toString() : null;
    final isScheduleForThisStage = scheduleStage == null ||
        scheduleStage.trim().toLowerCase() == normCurrent;
    final scheduleDate = isScheduleForThisStage && scheduleData != null ? scheduleData['date']?.toString() : null;
    final scheduleTime = isScheduleForThisStage && scheduleData != null ? scheduleData['startTime']?.toString() : null;
    final roomStr = isScheduleForThisStage && scheduleData != null ? (scheduleData['room']?.toString() ?? '') : '';
    final hasSchedule = scheduleDate != null && scheduleDate.isNotEmpty;

    // Grade info
    final grades = widget.studentData?['grades'] as Map<String, dynamic>?;
    final gradeStage = grades?['stage']?.toString();
    final isGradeForThisStage = gradeStage != null &&
        gradeStage.trim().toLowerCase() == normCurrent;
    final stageGrade = stageInfo['grade'] as Map<String, dynamic>? ??
        (isGradeForThisStage ? grades : null);

    // Deliverables info
    final preItems = (stageInfo['pre'] as List? ?? []).cast<Map<String, dynamic>>();
    final preUploaded = stageInfo['pre_uploaded'] as int? ?? 0;
    final preTotal = stageInfo['pre_total'] as int? ?? (preItems.isNotEmpty ? preItems.length : 3);
    final clearancePercent = preTotal > 0
        ? (preUploaded / preTotal).clamp(0.0, 1.0)
        : (isOfficiallyComplete ? 1.0 : 0.0);

    final members = (widget.studentData?['members'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    final projectTitle = team?['projectTitle']?.toString() ??
        team?['project_title']?.toString() ??
        'Capstone Project';
    final adviserName = team?['adviserName']?.toString() ?? 'Assigned Adviser';

    final flightDeckBody = RefreshIndicator(
      color: DefensysTokens.maroon,
      onRefresh: () async {
        await widget.onRefresh?.call();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Embedded back to journey bar (if embedded inside shell)
            if (widget.isEmbedded) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: InkWell(
                      onTap: widget.onBackToJourney ??
                          () => Navigator.of(context).maybePop(),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: DefensysTokens.maroon.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: DefensysTokens.maroon.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_rounded,
                                size: 15, color: DefensysTokens.maroon),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Back to Defense Journey',
                                style: TextStyle(
                                  color: DefensysTokens.maroon,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isOfficiallyComplete
                          ? const Color(0xFF10B981)
                          : (isActiveStage
                              ? const Color(0xFFE11D48)
                              : const Color(0xFF64748B)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isOfficiallyComplete
                              ? Icons.check_circle_rounded
                              : (isActiveStage
                                  ? Icons.radar_rounded
                                  : Icons.lock_rounded),
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isOfficiallyComplete
                              ? 'CLEARED'
                              : (isActiveStage ? 'ACTIVE' : 'LOCKED'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // 1. TOP CAPSULE STAGE SWITCHER
            _buildCapsuleSwitcher(
              stageOptions: stageOptions,
              activeStageName: activeStageName,
              stagesList: stagesList,
            ),
            const SizedBox(height: 14),

            // 2. STAGE HERO BANNER
            _buildStageHeroBanner(
              projectTitle: projectTitle,
              adviserName: adviserName,
              isOfficiallyComplete: isOfficiallyComplete,
              isActiveStage: isActiveStage,
              isUpcoming: isUpcoming,
              stageGrade: stageGrade,
            ),
            const SizedBox(height: 14),

            // 3. DYNAMIC MODULAR BENTO GRID
            _buildBentoGrid(
              isOfficiallyComplete: isOfficiallyComplete,
              isActiveStage: isActiveStage,
              isUpcoming: isUpcoming,
              clearancePercent: clearancePercent,
              preUploaded: preUploaded,
              preTotal: preTotal,
              preItems: preItems,
              hasSchedule: hasSchedule,
              scheduleDate: scheduleDate,
              scheduleTime: scheduleTime,
              roomStr: roomStr,
              stageGrade: stageGrade,
              members: members,
              isCapstone: isCapstone,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );

    if (widget.isEmbedded) {
      return Container(
        color: const Color(0xFFF8FAFC),
        child: flightDeckBody,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: DefensysTokens.maroon,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          tooltip: 'Back to Expedition Trail',
          onPressed: widget.onBackToJourney ??
              () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentStageLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              isOfficiallyComplete
                  ? 'Stage Cleared • Archive Dossier'
                  : (isActiveStage
                      ? 'Current Stage • Mission Control'
                      : 'Upcoming Stage • Prerequisite Preview'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: isOfficiallyComplete
                  ? const Color(0xFF10B981)
                  : (isActiveStage
                      ? const Color(0xFFE11D48)
                      : const Color(0xFF64748B)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isOfficiallyComplete
                      ? Icons.check_circle_rounded
                      : (isActiveStage
                          ? Icons.radar_rounded
                          : Icons.lock_rounded),
                  size: 13,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  isOfficiallyComplete
                      ? 'CLEARED'
                      : (isActiveStage ? 'ACTIVE' : 'LOCKED'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: flightDeckBody,
    );
  }

  // ─── 1. CAPSULE STAGE SWITCHER ─────────────────────────────────────────────

  Widget _buildCapsuleSwitcher({
    required List<String> stageOptions,
    required String activeStageName,
    required List<Map<String, dynamic>> stagesList,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: stageOptions.map((stage) {
          final isSelected = stage == _currentStageLabel;
          final normStage = stage.trim().toLowerCase();
          final normActive = activeStageName.trim().toLowerCase();
          final stageIdx = stageOptions.indexOf(stage);
          final activeIdx = stageOptions.indexOf(activeStageName);

          final stageInfo = stagesList.firstWhere(
            (s) => s['stage_label']?.toString().trim().toLowerCase() == normStage,
            orElse: () => <String, dynamic>{},
          );

          final isCleared = stageInfo['is_officially_complete'] == true ||
              stageInfo['stage_status_detail']?.toString() == 'passed' ||
              (stageIdx != -1 && activeIdx != -1 && stageIdx < activeIdx);

          final isActive = stageIdx != -1 && stageIdx == activeIdx;

          Color pillBg = Colors.white;
          Color pillBorder = const Color(0xFFE2E8F0);
          Color textColor = DefensysTokens.textSecondary;
          IconData icon = Icons.circle_outlined;
          Color iconColor = DefensysTokens.textSecondary;

          if (isSelected) {
            pillBg = DefensysTokens.maroon;
            pillBorder = DefensysTokens.maroon;
            textColor = Colors.white;
            icon = isCleared
                ? Icons.check_circle_rounded
                : (isActive ? Icons.radar_rounded : Icons.lock_rounded);
            iconColor = Colors.white;
          } else if (isCleared) {
            pillBg = const Color(0xFFF0FDF4);
            pillBorder = const Color(0xFFBBF7D0);
            textColor = const Color(0xFF15803D);
            icon = Icons.check_circle_rounded;
            iconColor = const Color(0xFF16A34A);
          } else if (isActive) {
            pillBg = const Color(0xFFFFF1F2);
            pillBorder = const Color(0xFFFECDD3);
            textColor = DefensysTokens.maroon;
            icon = Icons.radar_rounded;
            iconColor = DefensysTokens.maroon;
          }

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () {
                setState(() {
                  _currentStageLabel = stage;
                });
              },
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: pillBorder, width: isSelected ? 1.5 : 1),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: DefensysTokens.maroon.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: iconColor),
                    const SizedBox(width: 6),
                    Text(
                      stage,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── 2. STAGE HERO BANNER ──────────────────────────────────────────────────

  Widget _buildStageHeroBanner({
    required String projectTitle,
    required String adviserName,
    required bool isOfficiallyComplete,
    required bool isActiveStage,
    required bool isUpcoming,
    required Map<String, dynamic>? stageGrade,
  }) {
    final gradeResult = stageGrade?['result']?.toString().toUpperCase();
    final gradeScore = stageGrade?['final_grade'] ?? stageGrade?['grade'];

    Color headerBg = Colors.white;
    Color borderColor = const Color(0xFFE2E8F0);
    Widget statusChip;

    if (isOfficiallyComplete) {
      headerBg = const Color(0xFFF0FDF4);
      borderColor = const Color(0xFF86EFAC);
      statusChip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF16A34A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          gradeScore != null
              ? 'PASSED • GRADE $gradeScore'
              : (gradeResult != null ? 'PASSED • $gradeResult' : 'PASSED & ARCHIVED'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    } else if (isActiveStage) {
      headerBg = Colors.white;
      borderColor = DefensysTokens.maroon.withValues(alpha: 0.3);
      statusChip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: DefensysTokens.maroon.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DefensysTokens.maroon.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radar_rounded, size: 12, color: DefensysTokens.maroon),
            SizedBox(width: 4),
            Text(
              'ACTIVE MISSION',
              style: TextStyle(
                color: DefensysTokens.maroon,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else {
      headerBg = const Color(0xFFF8FAFC);
      borderColor = const Color(0xFFCBD5E1);
      statusChip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF64748B).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'UPCOMING STAGE • LOCKED',
          style: TextStyle(
            color: Color(0xFF475569),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: headerBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
                'STAGE DOSSIER',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: isOfficiallyComplete
                      ? const Color(0xFF16A34A)
                      : (isActiveStage
                          ? DefensysTokens.maroon
                          : const Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: statusChip),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            projectTitle,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: DefensysTokens.textPrimary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.school_outlined,
                  size: 14, color: DefensysTokens.textSecondary),
              const SizedBox(width: 6),
              Text(
                'Adviser: $adviserName',
                style: const TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 3. MODULAR BENTO GRID ─────────────────────────────────────────────────

  Widget _buildBentoGrid({
    required bool isOfficiallyComplete,
    required bool isActiveStage,
    required bool isUpcoming,
    required double clearancePercent,
    required int preUploaded,
    required int preTotal,
    required List<Map<String, dynamic>> preItems,
    required bool hasSchedule,
    required String? scheduleDate,
    required String? scheduleTime,
    required String roomStr,
    required Map<String, dynamic>? stageGrade,
    required List<Map<String, dynamic>> members,
    required bool isCapstone,
  }) {
    return Column(
      children: [
        // ── TOP ROW: CLEARANCE GAUGE & DEFENSE DISPATCH ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tile 1: Stage Clearance Meter
            Expanded(
              flex: 5,
              child: _buildBentoCard(
                title: 'Clearance Meter',
                icon: Icons.pie_chart_outline_rounded,
                iconColor: isOfficiallyComplete
                    ? const Color(0xFF16A34A)
                    : DefensysTokens.maroon,
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(
                            value: clearancePercent,
                            strokeWidth: 8,
                            backgroundColor: const Color(0xFFF1F5F9),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isOfficiallyComplete
                                  ? const Color(0xFF16A34A)
                                  : DefensysTokens.maroon,
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${(clearancePercent * 100).toInt()}%',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: DefensysTokens.textPrimary,
                              ),
                            ),
                            Text(
                              isOfficiallyComplete ? 'Cleared' : 'Ready',
                              style: const TextStyle(
                                fontSize: 10,
                                color: DefensysTokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isOfficiallyComplete
                          ? 'All requirements archived'
                          : '$preUploaded of $preTotal Deliverables Submitted',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Tile 2: Defense Dispatch
            Expanded(
              flex: 6,
              child: _buildBentoCard(
                title: 'Defense Dispatch',
                icon: Icons.calendar_month_rounded,
                iconColor: const Color(0xFF2563EB),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: hasSchedule
                            ? const Color(0xFFEFF6FF)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: hasSchedule
                              ? const Color(0xFFBFDBFE)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            hasSchedule
                                ? Icons.event_available_rounded
                                : Icons.schedule_rounded,
                            size: 13,
                            color: hasSchedule
                                ? const Color(0xFF2563EB)
                                : DefensysTokens.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              hasSchedule ? 'SCHEDULED' : 'PENDING SCHEDULE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: hasSchedule
                                    ? const Color(0xFF1D4ED8)
                                    : DefensysTokens.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      hasSchedule
                          ? (scheduleTime != null && scheduleTime.isNotEmpty
                              ? '$scheduleDate\n$scheduleTime'
                              : scheduleDate!)
                          : 'Assignment Pending',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: DefensysTokens.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.meeting_room_outlined,
                            size: 13, color: DefensysTokens.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            roomStr.isNotEmpty ? roomStr : 'Venue TBA',
                            style: const TextStyle(
                              fontSize: 11,
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
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── MIDDLE: DELIBERATION RECORD OR DELIVERABLES CHECKLIST ──
        if (isOfficiallyComplete) ...[
          _buildBentoCard(
            title: 'Deliberation Verdict & Grade',
            icon: Icons.emoji_events_rounded,
            iconColor: const Color(0xFFD97706),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'OFFICIAL GRADE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: DefensysTokens.textSecondary,
                          ),
                        ),
                        Text(
                          stageGrade?['final_grade']?.toString() ??
                              stageGrade?['grade']?.toString() ??
                              'Passed',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified_rounded,
                              size: 16, color: Color(0xFF16A34A)),
                          SizedBox(width: 6),
                          Text(
                            'DELIBERATION PASSED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF15803D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => widget.onSelectTab?.call(1),
                  icon: const Icon(Icons.folder_zip_outlined, size: 16),
                  label: const Text('Access Archived Manuscripts & Files'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DefensysTokens.maroon,
                    side: const BorderSide(color: DefensysTokens.maroon),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ] else if (isUpcoming) ...[
          _buildBentoCard(
            title: 'Prerequisite & Unlock Pathway',
            icon: Icons.lock_outline_rounded,
            iconColor: const Color(0xFF64748B),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This defense stage is locked until your team clears the preceding academic stage.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: DefensysTokens.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: Color(0xFF475569)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Requires official passing deliberation and adviser endorsement.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          // Active Stage: Deliverables Checklist
          _buildBentoCard(
            title: 'Required Pre-Defense Deliverables',
            icon: Icons.checklist_rounded,
            iconColor: DefensysTokens.maroon,
            trailing: TextButton(
              onPressed: () => widget.onSelectTab?.call(1),
              child: const Text('Manage Files →',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            child: preItems.isNotEmpty
                ? Column(
                    children: preItems.take(4).map((item) {
                      final label = item['label']?.toString() ?? 'Deliverable';
                      final uploaded = item['uploaded'] == true;
                      final submission = item['submission'] as Map?;
                      final status = submission?['status']?.toString();
                      final isApproved = status == 'approved' || status == 'accepted';
                      final isNeedsRevision = status == 'needs_revision' || status == 'rejected';

                      Color chipBg = const Color(0xFFF1F5F9);
                      Color chipText = DefensysTokens.textSecondary;
                      String statusText = 'Missing';
                      IconData chipIcon = Icons.circle_outlined;

                      if (isApproved) {
                        chipBg = const Color(0xFFDCFCE7);
                        chipText = const Color(0xFF15803D);
                        statusText = 'Approved';
                        chipIcon = Icons.check_circle_rounded;
                      } else if (uploaded) {
                        chipBg = const Color(0xFFEFF6FF);
                        chipText = const Color(0xFF1D4ED8);
                        statusText = 'Submitted';
                        chipIcon = Icons.access_time_filled_rounded;
                      } else if (isNeedsRevision) {
                        chipBg = const Color(0xFFFEE2E2);
                        chipText = const Color(0xFFB91C1C);
                        statusText = 'Needs Revision';
                        chipIcon = Icons.error_rounded;
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(chipIcon, size: 15, color: chipText),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: DefensysTokens.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: chipBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: chipText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  )
                : const Text(
                    'Pre-defense document definitions will load from curriculum rules.',
                    style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondary),
                  ),
          ),
          const SizedBox(height: 12),
        ],

        // ── BOTTOM: TEAM SQUAD & PEER EVALUATION HUB ──
        _buildBentoCard(
          title: 'Team Squad & Peer Review Hub',
          icon: Icons.groups_rounded,
          iconColor: DefensysTokens.maroon,
          child: Column(
            children: members.map((member) {
              final name = member['name']?.toString() ?? 'Teammate';
              final username = member['username']?.toString() ?? '';
              final isLeader = member['isLeader'] == true || member['is_leader'] == true;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          DefensysTokens.maroon.withValues(alpha: 0.1),
                      child: Text(
                        name.isNotEmpty ? name[0] : 'S',
                        style: const TextStyle(
                          fontSize: 11,
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
                                  name,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: DefensysTokens.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isLeader) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7F1D1D),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Leader',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (username.isNotEmpty)
                            Text(
                              username,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: DefensysTokens.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isActiveStage)
                      ElevatedButton(
                        onPressed: () => widget.onSelectTab?.call(1),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DefensysTokens.maroon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text(
                          'Peer Eval ✍️',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─── BENTO CARD CONTAINER HELPER ───────────────────────────────────────────

  Widget _buildBentoCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(icon, size: 15, color: iconColor),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: DefensysTokens.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
