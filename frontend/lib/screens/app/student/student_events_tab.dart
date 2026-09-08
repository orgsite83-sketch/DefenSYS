import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/capstone_deliverables_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../../theme/defensys_tokens.dart';
import 'peer_eval_tab.dart';
import 'student_deliverables_tab.dart';

class StudentEventsTab extends ConsumerStatefulWidget {
  final bool isCapstone;
  final Map<String, dynamic>? studentData;
  final ValueNotifier<int>? subTabNotifier;

  const StudentEventsTab({
    super.key,
    required this.isCapstone,
    required this.studentData,
    this.subTabNotifier,
  });

  @override
  ConsumerState<StudentEventsTab> createState() => _StudentEventsTabState();
}

class _StudentEventsTabState extends ConsumerState<StudentEventsTab>
    with SingleTickerProviderStateMixin {
  late TabController _subTabController;
  int _activeSubIndex = 0;
  Timer? _countdownTimer;
  Duration? _timeUntilDefense;
  bool _isDefensePast = false;
  String? _selectedStageForView;

  String? get _studentYearLevel {
    final y = widget.studentData?['year_level']?.toString().trim();
    return (y != null && y.isNotEmpty) ? y : null;
  }

  @override
  void initState() {
    super.initState();
    final initialIdx = (widget.subTabNotifier?.value ?? 0).clamp(0, 2);
    _subTabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialIdx,
    );
    _activeSubIndex = initialIdx;
    _subTabController.addListener(() {
      if (_subTabController.index != _activeSubIndex) {
        setState(() {
          _activeSubIndex = _subTabController.index;
        });
      }
    });

    widget.subTabNotifier?.addListener(_onSubTabNotifierChanged);
    _startCountdown();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
            scope: widget.isCapstone ? 'capstone' : 'pit',
            yearLevel: widget.isCapstone ? null : _studentYearLevel,
          );
    });
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
    final stages = (widget.studentData?['stages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final currentStageLabel = widget.studentData?['current_stage']?.toString().trim().toLowerCase();
    final targetStage = _selectedStageForView?.trim().toLowerCase() ?? currentStageLabel;

    Map<String, dynamic>? activeSchedule;
    final topSchedule = widget.studentData?['schedule'] as Map<String, dynamic>? ??
        widget.studentData?['defense_schedule'] as Map<String, dynamic>?;

    if (topSchedule != null &&
        (targetStage == null || topSchedule['stage']?.toString().trim().toLowerCase() == targetStage)) {
      activeSchedule = topSchedule;
    } else if (targetStage != null && stages.isNotEmpty) {
      final matchedStage = stages.firstWhere(
        (s) => s['stage_label']?.toString().trim().toLowerCase() == targetStage,
        orElse: () => <String, dynamic>{},
      );
      if (matchedStage['schedule'] is Map) {
        activeSchedule = Map<String, dynamic>.from(matchedStage['schedule'] as Map);
      }
    }

    final dateStr = activeSchedule?['date']?.toString() ?? activeSchedule?['scheduled_date']?.toString();
    final timeStr = activeSchedule?['startTime']?.toString() ?? activeSchedule?['start_time']?.toString();

    if (dateStr == null || dateStr.trim().isEmpty) {
      _timeUntilDefense = null;
      _isDefensePast = false;
      return;
    }

    try {
      DateTime scheduledDate;
      if (timeStr != null && timeStr.contains(':')) {
        final parsedDate = DateTime.parse(dateStr);
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

  void _onSubTabNotifierChanged() {
    final target = widget.subTabNotifier?.value;
    if (target != null && target >= 0 && target < 3 && _subTabController.index != target) {
      _subTabController.animateTo(target);
      setState(() {
        _activeSubIndex = target;
      });
    }
  }

  @override
  void didUpdateWidget(covariant StudentEventsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subTabNotifier != widget.subTabNotifier) {
      oldWidget.subTabNotifier?.removeListener(_onSubTabNotifierChanged);
      widget.subTabNotifier?.addListener(_onSubTabNotifierChanged);
    }
  }

  @override
  void dispose() {
    widget.subTabNotifier?.removeListener(_onSubTabNotifierChanged);
    _countdownTimer?.cancel();
    _subTabController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
            scope: widget.isCapstone ? 'capstone' : 'pit',
            yearLevel: widget.isCapstone ? null : _studentYearLevel,
          ),
      ref.read(dashboardProvider('student').notifier).fetchDashboardData(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final delivState = ref.watch(capstoneDeliverablesProvider);
    final isCapstone = widget.isCapstone;

    final backendStageOptions = (widget.studentData?['stage_options'] as List?)
            ?.map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const <String>[];
    final stageOptions = delivState.stageOptions.isNotEmpty
        ? delivState.stageOptions
        : backendStageOptions;

    final team = widget.studentData?['team'] as Map<String, dynamic>?;
    final scheduleData = widget.studentData?['schedule'] as Map<String, dynamic>? ??
        widget.studentData?['defense_schedule'] as Map<String, dynamic>?;
    final grades = widget.studentData?['grades'] as Map<String, dynamic>?;

    final peerEvalAllowed = widget.studentData?['peerEvalEnabled'] == true;
    final teammates = (widget.studentData?['members'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where(
          (m) =>
              m['id']?.toString() !=
              widget.studentData?['student']?['id']?.toString(),
        )
        .toList();

    final teamData = delivState.teams.firstOrNull;
    final stagesList = (teamData?['stages'] as List? ?? widget.studentData?['stages'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    final rawActiveStageName = teamData?['current_stage']?.toString() ??
        teamData?['current_defense_stage']?.toString() ??
        teamData?['ready_for_stage']?.toString() ??
        team?['currentStage']?.toString() ??
        team?['readyForStage']?.toString() ??
        team?['ready_for_stage']?.toString() ??
        widget.studentData?['current_stage']?.toString() ??
        (stageOptions.isNotEmpty ? stageOptions.first : '');

    final activeStageName = stageOptions.any(
            (s) => s.trim().toLowerCase() == rawActiveStageName.trim().toLowerCase())
        ? rawActiveStageName
        : (stageOptions.isNotEmpty ? stageOptions.first : rawActiveStageName);

    final selectedStage = (_selectedStageForView != null &&
            stageOptions.any((s) =>
                s.trim().toLowerCase() == _selectedStageForView!.trim().toLowerCase()))
        ? _selectedStageForView!
        : (delivState.selectedStage.isNotEmpty &&
                stageOptions.any((s) =>
                    s.trim().toLowerCase() ==
                    delivState.selectedStage.trim().toLowerCase()))
            ? delivState.selectedStage
            : (activeStageName.isNotEmpty
                ? activeStageName
                : (stageOptions.firstOrNull ?? ''));

    final isSelectedStageActive =
        selectedStage.trim().toLowerCase() == activeStageName.trim().toLowerCase();
    final selectedStageIndex = stageOptions
        .indexWhere((s) => s.trim().toLowerCase() == selectedStage.trim().toLowerCase());
    final activeStageIndex = stageOptions
        .indexWhere((s) => s.trim().toLowerCase() == activeStageName.trim().toLowerCase());

    final adviserName = team?['adviserName']?.toString() ??
        team?['adviser_name']?.toString() ??
        (isCapstone ? 'Unassigned' : 'N/A');

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: RefreshIndicator(
        color: DefensysTokens.maroon,
        onRefresh: _refreshAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. CAPSTONE DEFENSE STAGES (HORIZONTAL PROGRESS STEPPER AT THE TOP)
              if (delivState.isLoading && stageOptions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(color: DefensysTokens.maroon),
                  ),
                )
              else if (stageOptions.isNotEmpty) ...[
                // Outstanding Post-Defense Action Required Banner
                Builder(
                  builder: (context) {
                    final stageWithPending = StudentTaskBadgeHelper
                        .firstStageWithPendingPostDeliverables(stagesList);
                    if (stageWithPending == null) return const SizedBox.shrink();
                    return _buildPendingPostActionBanner(
                      pendingStageInfo: stageWithPending,
                      selectedStageName: selectedStage,
                      onStageSelected: (stage) {
                        setState(() {
                          _selectedStageForView = stage;
                          _calculateRemainingTime();
                        });
                        ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
                              scope: isCapstone ? 'capstone' : 'pit',
                              yearLevel: isCapstone ? null : _studentYearLevel,
                              selectedStage: stage,
                            );
                      },
                    );
                  },
                ),
                _buildCapstoneStagesStepper(
                  stageOptions: stageOptions,
                  activeStageName: activeStageName,
                  selectedStageName: selectedStage,
                  stagesList: stagesList,
                  grades: grades,
                  isCapstone: isCapstone,
                  onStageSelected: (stage) {
                    setState(() {
                      _selectedStageForView = stage;
                      _calculateRemainingTime();
                    });
                    ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
                          scope: isCapstone ? 'capstone' : 'pit',
                          yearLevel: isCapstone ? null : _studentYearLevel,
                          selectedStage: stage,
                        );
                  },
                ),
                const SizedBox(height: 12),

                // Contextual Notice Banner (Archive for past stages, Upcoming info for future stages)
                if (!isSelectedStageActive && activeStageName.isNotEmpty) ...[
                  Builder(
                    builder: (context) {
                      final isPastStage = selectedStageIndex != -1 &&
                          activeStageIndex != -1 &&
                          selectedStageIndex < activeStageIndex;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isPastStage
                              ? const Color(0xFFFFFBEB)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isPastStage
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isPastStage
                                  ? Icons.history_rounded
                                  : Icons.lock_clock_rounded,
                              size: 16,
                              color: isPastStage
                                  ? const Color(0xFFB45309)
                                  : const Color(0xFF475569),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isPastStage
                                    ? (StudentTaskBadgeHelper.hasPendingPostDeliverables(
                                            stagesList.firstWhere(
                                          (s) =>
                                              s['stage_label']?.toString().trim().toLowerCase() ==
                                              selectedStage.trim().toLowerCase(),
                                          orElse: () => <String, dynamic>{},
                                        ))
                                        ? 'Viewing "$selectedStage": Post-defense deliverables are pending upload below'
                                        : 'Viewing past milestone archive for "$selectedStage"')
                                    : 'Upcoming Stage: "$selectedStage" (Deliverables open after $activeStageName)',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: isPastStage
                                      ? const Color(0xFF92400E)
                                      : const Color(0xFF334155),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedStageForView = activeStageName;
                                  _calculateRemainingTime();
                                });
                                ref
                                    .read(capstoneDeliverablesProvider.notifier)
                                    .fetchDeliverables(
                                      scope: isCapstone ? 'capstone' : 'pit',
                                      yearLevel: isCapstone ? null : _studentYearLevel,
                                      selectedStage: activeStageName,
                                    );
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: isPastStage
                                      ? const Color(0xFFFEF3C7)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isPastStage
                                        ? const Color(0xFFF59E0B)
                                            .withValues(alpha: 0.4)
                                        : const Color(0xFF94A3B8)
                                            .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  'Current ($activeStageName) →',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: isPastStage
                                        ? const Color(0xFFB45309)
                                        : DefensysTokens.maroon,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],

              // 2. SUB-TABS: SCHEDULE, DELIVERABLES, PEER EVAL (DRIVEN DYNAMICALLY BY SELECTED STAGE)
              Builder(
                builder: (context) {
                  final hasPendingDeliverables = delivState.hasPendingDeliverables;
                  final hasPendingPeer =
                      StudentTaskBadgeHelper.hasPendingPeerEval(widget.studentData);

                  return Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TabBar(
                      controller: _subTabController,
                      onTap: (index) {
                        if (_activeSubIndex != index) {
                          setState(() {
                            _activeSubIndex = index;
                          });
                        }
                      },
                      isScrollable: false,
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelPadding: EdgeInsets.zero,
                      indicator: BoxDecoration(
                        color: DefensysTokens.maroon,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: DefensysTokens.textSecondary,
                      labelStyle:
                          const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                      unselectedLabelStyle:
                          const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
                      padding: const EdgeInsets.all(3),
                      dividerColor: Colors.transparent,
                      tabs: [
                        const Tab(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.calendar_today_rounded, size: 13),
                                SizedBox(width: 4),
                                Text('Schedule'),
                              ],
                            ),
                          ),
                        ),
                        Tab(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.folder_outlined, size: 13),
                                const SizedBox(width: 4),
                                const Text('Deliverables'),
                                if (hasPendingDeliverables) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 1),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        Tab(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.star_outline_rounded, size: 13),
                                const SizedBox(width: 4),
                                const Text('Peer Eval'),
                                if (hasPendingPeer) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 1),
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
                },
              ),

              const SizedBox(height: 16),

              // 3. ACTIVE SUB-TAB VIEW (STAGE STATUS / DELIVERABLES / PEER EVAL)
              Builder(
                builder: (context) {
                  switch (_activeSubIndex) {
                    case 0:
                      return _buildScheduleTab(
                        selectedStageName: selectedStage,
                        activeStageName: activeStageName,
                        stageOptions: stageOptions,
                        stagesList: stagesList,
                        schedule: scheduleData,
                        grades: grades,
                        team: team,
                        adviserName: adviserName,
                        isCapstone: isCapstone,
                      );
                    case 1:
                      return StudentDeliverablesTab(
                        isCapstone: isCapstone,
                        studentData: widget.studentData,
                        isEmbedded: true,
                        hideHeader: true,
                      );
                    case 2:
                      final stageInfo = stagesList.firstWhere(
                        (s) =>
                            s['stage_label']?.toString().trim().toLowerCase() ==
                            selectedStage.trim().toLowerCase(),
                        orElse: () => <String, dynamic>{},
                      );
                      final rawSubmissions = (stageInfo['my_peer_submissions'] as List? ??
                              (widget.studentData?['myPeerSubmissions'] as List? ?? []))
                          .cast<Map<String, dynamic>>();
                      final stageMySubmissions = rawSubmissions.where((sub) {
                        final subStage = sub['stage']?.toString();
                        if (subStage == null || subStage.isEmpty) {
                          return isSelectedStageActive;
                        }
                        return subStage.trim().toLowerCase() ==
                            selectedStage.trim().toLowerCase();
                      }).toList();

                      final stagePeerCriteria = (stageInfo['peer_criteria'] as List? ??
                              (isSelectedStageActive
                                  ? (widget.studentData?['peerCriteria'] as List? ?? [])
                                  : []))
                          .cast<Map<String, dynamic>>();
                      final stagePeerEvalAllowed = isSelectedStageActive && peerEvalAllowed;
                      final stageHideHistory = !isSelectedStageActive && stageMySubmissions.isEmpty;

                      return PeerEvalTab(
                        isCapstone: isCapstone,
                        peerEvalAllowed: stagePeerEvalAllowed,
                        teammates: teammates,
                        peerCriteria: stagePeerCriteria,
                        myPeerSubmissions: stageMySubmissions,
                        studentId: widget.studentData?['student']?['id']?.toString() ?? '',
                        teamId: team?['id']?.toString() ?? '',
                        peerWeight:
                            (widget.studentData?['weights']?['peer'] as num?)?.toInt() ?? 20,
                        onPeerSubmitted: _refreshAll,
                        onRefresh: _refreshAll,
                        isEmbedded: true,
                        hideHistory: stageHideHistory,
                        stage: selectedStage,
                      );
                    default:
                      return const SizedBox.shrink();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── ACTION REQUIRED BANNER (PENDING POST-DEFENSE DELIVERABLES) ───────────

  Widget _buildPendingPostActionBanner({
    required Map<String, dynamic> pendingStageInfo,
    required String selectedStageName,
    required ValueChanged<String> onStageSelected,
  }) {
    final pendingStageLabel = pendingStageInfo['stage_label']?.toString() ?? '';
    final pendingCount =
        StudentTaskBadgeHelper.pendingPostDeliverablesCount(pendingStageInfo);
    if (pendingCount <= 0 || pendingStageLabel.isEmpty) return const SizedBox.shrink();

    final isPendingCurrentSelected = pendingStageLabel.trim().toLowerCase() ==
        selectedStageName.trim().toLowerCase();

    final gradeData = (pendingStageInfo['grade'] as Map<String, dynamic>?) ??
        (pendingStageInfo['grade'] is Map ? Map<String, dynamic>.from(pendingStageInfo['grade'] as Map) : null);
    final verdict = gradeData?['verdict']?.toString() ?? pendingStageInfo['verdict']?.toString();
    final verdictRemarks = gradeData?['verdict_remarks']?.toString();
    final revisionDeadline = gradeData?['revision_deadline']?.toString();
    final isRevisions = verdict == 'approved_with_revisions';

    final themeColor = isRevisions ? const Color(0xFFD97706) : const Color(0xFF2563EB);
    final bgColor = isRevisions ? const Color(0xFFFFFBEB) : const Color(0xFFEFF6FF);
    final borderColor = isRevisions ? const Color(0xFFFDE68A) : const Color(0xFFBFDBFE);
    final iconBgColor = isRevisions ? const Color(0xFFF59E0B) : const Color(0xFF3B82F6);

    final titleText = isRevisions ? 'Revisions & Compliance Required' : 'Post-Defense Requirements Due';
    final descText = isRevisions
        ? '$pendingStageLabel defense was approved with revisions. Please address the panel directives and upload the $pendingCount required post-defense deliverable${pendingCount > 1 ? 's' : ''}.'
        : '$pendingStageLabel defense passed! Please submit the $pendingCount required final deliverable${pendingCount > 1 ? 's' : ''} to complete this milestone.';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: themeColor.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconBgColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isRevisions ? Icons.assignment_late_rounded : Icons.task_alt_rounded,
              color: themeColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      titleText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: themeColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: themeColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$pendingCount file${pendingCount > 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (revisionDeadline != null && revisionDeadline.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule_rounded, size: 10, color: themeColor),
                            const SizedBox(width: 3),
                            Text(
                              'Due: $revisionDeadline',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: themeColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  descText,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isRevisions ? const Color(0xFF92400E) : const Color(0xFF1E3A8A),
                    height: 1.3,
                  ),
                ),
                if (isRevisions && verdictRemarks != null && verdictRemarks.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.format_quote_rounded, size: 14, color: Color(0xFFD97706)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Panel Directives: "$verdictRemarks"',
                            style: const TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF78350F),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    if (!isPendingCurrentSelected) {
                      onStageSelected(pendingStageLabel);
                    }
                    if (_subTabController.index != 1) {
                      _subTabController.animateTo(1);
                      setState(() {
                        _activeSubIndex = 1;
                      });
                    }
                  },
                  icon: const Icon(Icons.upload_file_rounded, size: 14),
                  label: Text(
                    isPendingCurrentSelected && _activeSubIndex == 1
                        ? 'Viewing Deliverables Below'
                        : (isRevisions ? 'Upload $pendingStageLabel Revisions' : 'Upload $pendingStageLabel Files'),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── HORIZONTAL PROGRESS STEPPER AT THE TOP ───────────────────────────────

  Widget _buildCapstoneStagesStepper({
    required List<String> stageOptions,
    required String activeStageName,
    required String selectedStageName,
    required List<Map<String, dynamic>> stagesList,
    required Map<String, dynamic>? grades,
    required bool isCapstone,
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
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: DefensysTokens.maroon.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(
                        isCapstone ? Icons.alt_route_rounded : Icons.event_available_rounded,
                        size: 16,
                        color: DefensysTokens.maroon,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isCapstone ? 'Capstone Defense Stages' : 'Milestone Stages',
                        style: const TextStyle(
                          fontSize: 14,
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
                size: 11.5,
                color: DefensysTokens.textSecondary,
              ),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Tap any stage above to inspect its details in the tabs below',
                  style: TextStyle(
                    fontSize: 10.5,
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
                    final normSelected = selectedStageName.trim().toLowerCase();
                    final isSelected = normStage == normSelected;

                    final stageInfo = stagesList.firstWhere(
                      (s) =>
                          s['stage_label']?.toString().trim().toLowerCase() ==
                          normStage,
                      orElse: () => <String, dynamic>{},
                    );

                    final isCleared = stageInfo['is_officially_complete'] == true ||
                        stageInfo['stage_status_detail']?.toString() == 'passed' ||
                        stageInfo['stage_progress_status']?.toString() == 'passed' ||
                        (stageIdx < activeStageIdx && activeStageIdx != -1);

                    final isActive = (stageIdx == activeStageIdx) ||
                        (!isCleared && (stageIdx == 0 || stageIdx <= activeStageIdx));

                    final hasPendingPost =
                        StudentTaskBadgeHelper.hasPendingPostDeliverables(stageInfo);
                    final gradeData = (stageInfo['grade'] as Map<String, dynamic>?) ??
                        (stageInfo['grade'] is Map ? Map<String, dynamic>.from(stageInfo['grade'] as Map) : null);
                    final verdict = gradeData?['verdict']?.toString() ?? stageInfo['verdict']?.toString();

                    final isForRedefense = verdict == 'for_redefense';
                    final isRevisionsDue = isCleared && hasPendingPost && verdict == 'approved_with_revisions';
                    final isRequirementsDue = isCleared && hasPendingPost && !isRevisionsDue && !isForRedefense;
                    final isStagePassed = isCleared && !hasPendingPost && !isForRedefense;

                    String statusLabel;
                    Color statusColor;
                    IconData? statusIcon;
                    if (isForRedefense) {
                      statusLabel = 'For Re-defense';
                      statusColor = const Color(0xFFDC2626);
                      statusIcon = Icons.replay_rounded;
                    } else if (isRevisionsDue) {
                      statusLabel = 'Revisions Due';
                      statusColor = const Color(0xFFD97706);
                      statusIcon = Icons.pending_actions_rounded;
                    } else if (isRequirementsDue) {
                      statusLabel = 'Requirements Due';
                      statusColor = const Color(0xFF2563EB);
                      statusIcon = Icons.assignment_late_rounded;
                    } else if (isStagePassed) {
                      statusLabel = 'Passed';
                      statusColor = const Color(0xFF15803D);
                      statusIcon = Icons.check_circle_rounded;
                    } else {
                      statusLabel = isActive ? 'Current' : 'Upcoming';
                      statusColor = isActive ? DefensysTokens.maroon : const Color(0xFF94A3B8);
                      statusIcon = null;
                    }

                    Color nodeBg;
                    Color nodeBorder;
                    if (isForRedefense) {
                      nodeBg = const Color(0xFFEF4444);
                      nodeBorder = const Color(0xFFDC2626);
                    } else if (isRevisionsDue) {
                      nodeBg = const Color(0xFFF59E0B);
                      nodeBorder = const Color(0xFFD97706);
                    } else if (isRequirementsDue) {
                      nodeBg = const Color(0xFF3B82F6);
                      nodeBorder = const Color(0xFF2563EB);
                    } else if (isStagePassed) {
                      nodeBg = const Color(0xFF16A34A);
                      nodeBorder = const Color(0xFF15803D);
                    } else {
                      nodeBg = isActive ? DefensysTokens.maroon : const Color(0xFFF1F5F9);
                      nodeBorder = isActive ? DefensysTokens.maroon : const Color(0xFFCBD5E1);
                    }

                    Widget nodeInner;
                    if (isForRedefense) {
                      nodeInner = const Icon(Icons.replay_rounded, size: 18, color: Colors.white);
                    } else if (isRevisionsDue) {
                      nodeInner = const Icon(Icons.pending_actions_rounded, size: 18, color: Colors.white);
                    } else if (isRequirementsDue) {
                      nodeInner = const Icon(Icons.upload_file_rounded, size: 18, color: Colors.white);
                    } else if (isStagePassed) {
                      nodeInner = const Icon(Icons.check_rounded, size: 19, color: Colors.white);
                    } else if (isActive) {
                      nodeInner = Text('${stageIdx + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white));
                    } else {
                      nodeInner = const Icon(Icons.lock_outline_rounded, size: 14, color: Color(0xFF94A3B8));
                    }

                    return Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: () {
                          onStageSelected(stageLabel);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Status label
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (statusIcon != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 2),
                                      child: Icon(
                                        statusIcon,
                                        size: 9,
                                        color: statusColor,
                                      ),
                                    ),
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: statusColor,
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
                                  color: nodeBg,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? nodeBorder : nodeBg,
                                    width: isSelected ? 3.0 : (isActive ? 2.5 : 1.5),
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: nodeBorder.withValues(alpha: 0.45),
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
                                                    color: nodeBorder.withValues(alpha: 0.25),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ]
                                              : null)),
                                ),
                                child: Center(child: nodeInner),
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
                                      ? statusColor
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
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Viewing',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      color: statusColor,
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

  // ─── RICH STAGE STATUS / SCHEDULE SUB-TAB ─────────────────────────────────

  Widget _buildScheduleTab({
    required String selectedStageName,
    required String activeStageName,
    required List<String> stageOptions,
    required List<Map<String, dynamic>> stagesList,
    required Map<String, dynamic>? schedule,
    required Map<String, dynamic>? grades,
    required Map<String, dynamic>? team,
    required String adviserName,
    required bool isCapstone,
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
    final isStageEndorsed = stageInfo['endorsed'] == true;
    final isEndorsedOrCleared = isCleared || isStageEndorsed;

    // Resolve Grade / Deliberation data
    final stageGradeMap = (stageInfo['grade'] as Map<String, dynamic>?) ??
        (grades != null && grades['stage']?.toString().trim().toLowerCase() == normSelected
            ? grades
            : null);

    final finalScore = stageGradeMap?['final_grade'] ??
        stageGradeMap?['grade'] ??
        (isCleared ? (stageInfo['score'] ?? 'Passed') : null);

    final resultStr =
        stageGradeMap?['result']?.toString() ?? (isCleared ? 'PASSED' : null);

    final completedDate = stageInfo['completed_date']?.toString() ??
        stageGradeMap?['completed_date']?.toString() ??
        stageGradeMap?['date']?.toString() ??
        'Completed';

    final remarks = stageGradeMap?['remarks']?.toString() ??
        stageInfo['remarks']?.toString();

    final presScore = stageGradeMap?['presentation']?.toString();
    final techScore = stageGradeMap?['technical']?.toString();
    final qnaScore = stageGradeMap?['qna']?.toString();

    // Resolve Schedule & Venue strictly for selected stage
    final isTopScheduleForStage = schedule != null &&
        schedule['stage']?.toString().trim().toLowerCase() == normSelected;
    final stageSchedule = isTopScheduleForStage
        ? schedule
        : (stageInfo['schedule'] as Map<String, dynamic>?);

    final scheduledDate = stageSchedule?['date']?.toString() ??
        stageSchedule?['scheduled_date']?.toString();
    final startTime = stageSchedule?['startTime']?.toString() ??
        stageSchedule?['start_time']?.toString();
    final room = stageSchedule?['room']?.toString();
    final panelists = (stageSchedule?['panelists'] as List?) ?? [];
    final documenter = (stageSchedule?['documenter'] as Map?) ?? {};

    final hasSchedule = scheduledDate != null && scheduledDate.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isCleared
                      ? const Color(0xFF16A34A).withValues(alpha: 0.1)
                      : DefensysTokens.maroon.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isCleared
                      ? Icons.verified_rounded
                      : Icons.calendar_month_rounded,
                  color: isCleared ? const Color(0xFF15803D) : DefensysTokens.maroon,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Defense Status for $selectedStageName',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: DefensysTokens.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isCleared
                          ? 'Milestone Cleared & Evaluated'
                          : (isActive ? 'Active Stage Deliberation' : 'Upcoming Stage'),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isCleared
                            ? const Color(0xFF15803D)
                            : DefensysTokens.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Builder(builder: (context) {
                final stageVerdict = stageGradeMap?['verdict']?.toString();
                final hasPendingPostSelected = StudentTaskBadgeHelper.hasPendingPostDeliverables(stageInfo);
                String hBadgeText;
                Color hBadgeBg;
                Color hBadgeBorder;
                Color hBadgeFg;

                if (stageVerdict == 'for_redefense') {
                  hBadgeText = 'For Re-defense';
                  hBadgeBg = const Color(0xFFFEF2F2);
                  hBadgeBorder = const Color(0xFFFECACA);
                  hBadgeFg = const Color(0xFFDC2626);
                } else if (stageVerdict == 'approved_with_revisions' && hasPendingPostSelected) {
                  hBadgeText = 'Revisions Due';
                  hBadgeBg = const Color(0xFFFFFBEB);
                  hBadgeBorder = const Color(0xFFFDE68A);
                  hBadgeFg = const Color(0xFFD97706);
                } else if (hasPendingPostSelected) {
                  hBadgeText = 'Requirements Due';
                  hBadgeBg = const Color(0xFFEFF6FF);
                  hBadgeBorder = const Color(0xFFBFDBFE);
                  hBadgeFg = const Color(0xFF2563EB);
                } else if (isCleared) {
                  hBadgeText = 'Passed ✓';
                  hBadgeBg = const Color(0xFFDCFCE7);
                  hBadgeBorder = const Color(0xFF86EFAC);
                  hBadgeFg = const Color(0xFF15803D);
                } else {
                  hBadgeText = isActive ? 'Current' : 'Upcoming';
                  hBadgeBg = isActive ? const Color(0xFFFEF2F2) : const Color(0xFFF1F5F9);
                  hBadgeBorder = isActive ? const Color(0xFFFCA5A5) : const Color(0xFFCBD5E1);
                  hBadgeFg = isActive ? DefensysTokens.maroon : const Color(0xFF64748B);
                }

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: hBadgeBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: hBadgeBorder),
                  ),
                  child: Text(
                    hBadgeText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: hBadgeFg,
                    ),
                  ),
                );
              }),
            ],
          ),
          const Divider(height: 24, color: Color(0xFFE2E8F0)),

          // ── CASE 1: CLEARED / PASSED STAGE ──
          if (isCleared) ...[
            Builder(builder: (context) {
              final verdictVal = stageGradeMap?['verdict']?.toString();
              final isWithRevs = verdictVal == 'approved_with_revisions';
              final deadlineStr = stageGradeMap?['revision_deadline']?.toString();
              final cBg = isWithRevs ? const Color(0xFFFFFBEB) : const Color(0xFFF0FDF4);
              final cBorder = isWithRevs ? const Color(0xFFFDE68A) : const Color(0xFFBBF7D0);
              final cFg = isWithRevs ? const Color(0xFFD97706) : const Color(0xFF16A34A);
              final cText = isWithRevs ? const Color(0xFF92400E) : const Color(0xFF15803D);
              final cSubText = isWithRevs ? const Color(0xFFB45309) : const Color(0xFF166534);

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cFg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isWithRevs ? Icons.assignment_late_rounded : Icons.verified_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Deliberation Result: ${resultStr ?? (isWithRevs ? 'APPROVED WITH REVISIONS' : 'PASSED')}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: cText,
                                  ),
                                ),
                              ),
                              if (deadlineStr != null && deadlineStr.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: cBorder),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.schedule_rounded, size: 10, color: cFg),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Due: $deadlineStr',
                                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: cFg),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Official Grade: ${finalScore ?? 'Passed'} • $completedDate',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: cSubText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),

            // Rubric Criteria Breakdown (if scores exist)
            if (presScore != null || techScore != null || qnaScore != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    if (presScore != null)
                      Expanded(child: _buildCriteriaScore('Presentation', '$presScore/30')),
                    if (techScore != null)
                      Expanded(child: _buildCriteriaScore('Technical', '$techScore/50')),
                    if (qnaScore != null)
                      Expanded(child: _buildCriteriaScore('Q&A Defense', '$qnaScore/20')),
                  ],
                ),
              ),
            ],

            // Panel Remarks Feedback (if remarks exist)
            if (remarks != null && remarks.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
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
                      size: 16,
                      color: Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Panel Feedback: "$remarks"',
                        style: const TextStyle(
                          fontSize: 11,
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
            if (hasSchedule) ...[
              _scheduleMetaRow(Icons.calendar_month_outlined, 'Date & Time',
                  '$scheduledDate${startTime != null ? ' at $startTime' : ''}'),
              const SizedBox(height: 10),
              _scheduleMetaRow(Icons.location_on_outlined, 'Room / Venue',
                  room?.isNotEmpty == true ? room! : 'Room TBA'),

              if (panelists.isNotEmpty) ...[
                const SizedBox(height: 10),
                _scheduleMetaRow(
                  Icons.people_outline_rounded,
                  'Defense Panelists',
                  panelists.map((p) => p['name'] ?? p['username'] ?? 'Panelist').join(', '),
                ),
              ],

              if (documenter.isNotEmpty) ...[
                const SizedBox(height: 10),
                _scheduleMetaRow(
                  Icons.edit_note_rounded,
                  'Assigned Documenter',
                  documenter['name']?.toString() ?? documenter['username']?.toString() ?? '—',
                ),
              ],

              const SizedBox(height: 14),

              // Countdown / Passed State
              if (_timeUntilDefense != null && !_isDefensePast) ...[
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
                    Expanded(child: _buildCountdownDigit(_timeUntilDefense!.inDays, 'Days')),
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
              ] else if (_isDefensePast) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.history_rounded, size: 16, color: Color(0xFF64748B)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Defense date passed ($scheduledDate). Awaiting deliberation evaluation.',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.event_available_outlined, size: 36, color: Colors.grey.shade400),
                    const SizedBox(height: 10),
                    Text(
                      'Defense schedule will be posted once assigned.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Schedule will appear here once finalized.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
          ]

          // ── CASE 3: UPCOMING STAGE ──
          else if (isUpcoming) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 22, color: Color(0xFF64748B)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Upcoming Milestone: $selectedStageName',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: DefensysTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Defense scheduling, deliverables, and deliberation will unlock after successfully completing $activeStageName.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: DefensysTokens.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Adviser Endorsement Row
          Row(
            children: [
              Icon(
                isEndorsedOrCleared
                    ? Icons.verified_user_rounded
                    : Icons.pending_outlined,
                size: 16,
                color: isEndorsedOrCleared
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFD97706),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adviser: $adviserName',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: DefensysTokens.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      isCleared
                          ? 'Milestone Endorsed & Completed ✓'
                          : (isStageEndorsed
                              ? 'Approved & Endorsed for Defense ✓'
                              : 'Awaiting Adviser Endorsement'),
                      style: TextStyle(
                        fontSize: 10,
                        color: isEndorsedOrCleared
                            ? const Color(0xFF15803D)
                            : const Color(0xFFB45309),
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
    );
  }

  Widget _scheduleMetaRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: DefensysTokens.maroon),
        const SizedBox(width: 10),
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownDigit(int value, String unit) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value.toString().padLeft(2, '0'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: DefensysTokens.maroon,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            unit.toUpperCase(),
            style: const TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCriteriaScore(String label, String score) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          score,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: DefensysTokens.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            color: DefensysTokens.textSecondary,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
