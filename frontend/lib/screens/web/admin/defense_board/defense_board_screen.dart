import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../config/api_config.dart';
import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/auth_provider.dart';
import '../../../../services/authenticated_client.dart';
import '../../../../services/defense_board_provider.dart';
import '../../../../services/defense_scheduler_provider.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../toasts/feedback_toast.dart';
import '../defense_scheduler/components/team_readiness_tracker.dart';
import '../defense_scheduler/defense_scheduler_screen.dart';
import '../defense_scheduler/dialogs/manual_slot_editor_dialog.dart';
import '../defense_scheduler/dialogs/team_deliverables_review_dialog.dart';
import '../defense_scheduler/dialogs/venue_conflict_dialog.dart';
import '../defense_scheduler/models/schedule_import_models.dart';
import '../grade_center/grade_center_screen.dart';
import '../admin_shell.dart';
import '../grade_center/grade_center_team_detail_screen.dart';
import '../../../../services/grading/grade_center_provider.dart';
import '../widgets/defensys_admin_shell.dart';
import '../../../../widgets/feedback/empty_state.dart';
import '../../faculty/minutes_form_screen.dart';
import '../../../../utils/import/schedule_import_draft.dart';

class DefenseBoardScreen extends ConsumerStatefulWidget {
  const DefenseBoardScreen({super.key});

  @override
  ConsumerState<DefenseBoardScreen> createState() => _DefenseBoardScreenState();
}

class _DefenseBoardScreenState extends ConsumerState<DefenseBoardScreen> {
  final TextEditingController _searchController = TextEditingController();
  int? _selectedMinutesScheduleId;
  bool _showScheduler = false;
  String? _schedulerScope;
  int? _schedulerStageId;
  String? _schedulerEventName;

  // Readiness State
  String _readinessScope = 'capstone';
  int? _selectedReadinessStageId;
  String? _selectedReadinessEventName;
  bool _isSendingReminder = false;

  // Session Accordion & Pagination State
  final Set<String> _collapsedSessions = {};
  final Map<String, int> _sessionPages = {};
  bool _hasImportDraft = false;
  ScheduleImportDraft? _savedImportDraft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(defenseBoardProvider.notifier).fetchBoard();
      ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
      _checkImportDraft();
    });
  }

  Future<void> _checkImportDraft() async {
    final user = ref.read(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;
    if (!isAdmin && !isPitLead) return;
    final scope = isAdmin ? 'capstone' : 'pit';
    final draft = await loadScheduleImportDraft(scope: scope);
    if (mounted) {
      setState(() {
        _savedImportDraft = (draft != null && draft.parsed.rows.isNotEmpty) ? draft : null;
        _hasImportDraft = _savedImportDraft != null;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _sendReminder(dynamic teamId, String stageLabel) async {
    setState(() => _isSendingReminder = true);
    try {
      final client = ref.read(authenticatedHttpClientProvider);
      final url = '${ApiConfig.teamsUrl}/$teamId/remind/';
      final response = await client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: '{"stage_label": "$stageLabel"}',
      );

      if (response.statusCode == 200) {
        if (mounted) {
          showSuccessToast(context, 'Reminder notification successfully sent.');
        }
      } else {
        if (mounted) {
          showErrorToast(context, 'Failed to send reminder.');
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Connection error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingReminder = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedMinutesScheduleId != null) {
      return MinutesFormScreen(
        scheduleId: _selectedMinutesScheduleId!,
        onBack: () {
          setState(() {
            _selectedMinutesScheduleId = null;
          });
          ref.read(defenseBoardProvider.notifier).fetchBoard();
        },
      );
    }

    if (_showScheduler) {
      return DefenseSchedulerScreen(
        initialScope: _schedulerScope,
        initialStageId: _schedulerStageId,
        initialEventName: _schedulerEventName,
        onBack: () {
          setState(() {
            _showScheduler = false;
            _schedulerScope = null;
            _schedulerStageId = null;
            _schedulerEventName = null;
          });
          ref.read(defenseBoardProvider.notifier).fetchBoard();
          ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
        },
      );
    }

    final state = ref.watch(defenseBoardProvider);
    ref.listen<DefensysAdminSection>(
      activeAdminSectionProvider,
      (previous, next) {
        if (next == DefensysAdminSection.defenseBoard) {
          ref.read(defenseBoardProvider.notifier).fetchBoard();
          ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
        }
      },
    );
    final schedState = ref.watch(defenseSchedulerProvider);
    final currentView = ref.watch(defenseBoardActiveViewProvider);
    final user = ref.watch(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;

    final effectiveReadinessScope = isPitLead && !isAdmin ? 'pit' : _readinessScope;

    // Determine active stage/event name
    String activeStageName = '';
    if (effectiveReadinessScope == 'capstone') {
      if (schedState.defenseStages.isNotEmpty) {
        if (_selectedReadinessStageId == null) {
          final firstWithReady = schedState.defenseStages.firstWhere(
            (stg) {
              final label = stg['label']?.toString() ?? '';
              return teamsForScope(schedState, 'capstone').any((t) => isTeamStageReady(t, label));
            },
            orElse: () => schedState.defenseStages.first,
          );
          _selectedReadinessStageId = asInt(firstWithReady['id']);
        }
        final stageObj = schedState.defenseStages.firstWhere(
          (stg) => asInt(stg['id']) == _selectedReadinessStageId,
          orElse: () => schedState.defenseStages.first,
        );
        activeStageName = stageObj['label']?.toString() ?? '';
      }
    } else {
      if (schedState.pitEvents.isNotEmpty) {
        if (_selectedReadinessEventName == null || _selectedReadinessEventName!.isEmpty) {
          final firstWithReady = schedState.pitEvents.firstWhere(
            (evt) {
              final name = evt['event_name']?.toString() ?? '';
              return teamsForScope(schedState, 'pit').any((t) => isTeamStageReady(t, name));
            },
            orElse: () => schedState.pitEvents.first,
          );
          _selectedReadinessEventName = firstWithReady['event_name']?.toString() ?? '';
        }
        activeStageName = _selectedReadinessEventName ?? '';
      }
    }

    final scopeTeams = teamsForScope(schedState, effectiveReadinessScope);
    final readyTeamsForActiveStage = scopeTeams
        .where((t) => activeStageName.isNotEmpty && isTeamStageReady(t, activeStageName))
        .toList();
    final completedTeamsForActiveStage = scopeTeams
        .where((t) => activeStageName.isNotEmpty && isTeamStageCompleted(t, activeStageName))
        .toList();
    final pendingTeamsForActiveStage = scopeTeams
        .where((t) =>
            activeStageName.isNotEmpty &&
            !isTeamStageReady(t, activeStageName) &&
            !isTeamStageCompleted(t, activeStageName) &&
            !isTeamStageScheduled(t, activeStageName))
        .toList();

    final totalReadyAcrossAllStages = schedState.teams
        .where((t) {
          final readyStage = t['ready_for_stage']?.toString() ?? '';
          return readyStage.isNotEmpty && isTeamStageReady(t, readyStage);
        })
        .length;

    final cp = DefensysUi.contentPadding;

    return Scaffold(
      backgroundColor: DefensysUi.bgLight,
      body: RefreshIndicator(
        color: AppColors.maroon,
        onRefresh: () async {
          await Future.wait([
            ref.read(defenseBoardProvider.notifier).fetchBoard(),
            ref.read(defenseSchedulerProvider.notifier).fetchSchedules(),
          ]);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(cp.left, cp.top, cp.right, 22),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(
                      state,
                      schedState,
                      effectiveReadinessScope,
                      activeStageName,
                      readyTeamsForActiveStage.length,
                      currentView,
                    ),
                    if (_savedImportDraft != null) ...[
                      const SizedBox(height: 16),
                      _buildDraftResumeBanner(),
                    ],
                    const SizedBox(height: 20),
                    _buildViewSwitcher(state, schedState, currentView),
                    const SizedBox(height: 20),
                    if (currentView == DefenseOperationsView.schedules) ...[
                      _buildReadinessCalloutBanner(totalReadyAcrossAllStages),
                      _buildSummaryCards(state),
                      const SizedBox(height: 22),
                      _buildFilterBar(state),
                    ] else ...[
                      _buildReadinessSummaryCards(
                        schedState,
                        activeStageName,
                        scopeTeams.length,
                        readyTeamsForActiveStage.length,
                        completedTeamsForActiveStage.length,
                        pendingTeamsForActiveStage.length,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (currentView == DefenseOperationsView.schedules) ...[
              if (state.isLoading)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: SizedBox.expand(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(cp.left, 0, cp.right, cp.bottom),
                      child: _buildLoadingState(),
                    ),
                  ),
                )
              else if (state.schedules.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: SizedBox.expand(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(cp.left, 0, cp.right, cp.bottom),
                      child: _buildEmptyBoard(),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(cp.left, 0, cp.right, cp.bottom),
                  sliver: SliverToBoxAdapter(
                    child: _buildBoardSection(state),
                  ),
                ),
            ] else ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(cp.left, 0, cp.right, cp.bottom),
                sliver: SliverToBoxAdapter(
                  child: schedState.isLoading && schedState.teams.isEmpty
                      ? _buildLoadingState()
                      : TeamReadinessTracker(
                          state: schedState,
                          scope: effectiveReadinessScope,
                          activeStageOrEventName: activeStageName,
                          title: 'Cohort Deliverables & Readiness Queue',
                          subtitle:
                              'Monitor deliverable completeness and instructor endorsements across sections. Teams marked "Ready" have met all pre-defense requirements and are eligible for scheduling.',
                          stageSelector: _buildStagePillsRow(
                            schedState,
                            effectiveReadinessScope,
                            activeStageName,
                          ),
                          headerAction: readyTeamsForActiveStage.isNotEmpty
                              ? ElevatedButton.icon(
                                  onPressed: () => _openScheduler(
                                    scope: effectiveReadinessScope,
                                    stageId: _selectedReadinessStageId,
                                    eventName: _selectedReadinessEventName,
                                  ),
                                  icon: const Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 15,
                                    color: AppColors.gold,
                                  ),
                                  label: Text(
                                    'Schedule ${readyTeamsForActiveStage.length} Ready ${readyTeamsForActiveStage.length == 1 ? 'Team' : 'Teams'}',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.maroon,
                                    foregroundColor: Colors.white,
                                    elevation: 1,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                )
                              : null,
                          onReviewTeamDeliverables: (team, stageLabel) =>
                              TeamDeliverablesReviewDialog.show(
                            context,
                            ref,
                            team: team,
                            stageLabel: stageLabel,
                            scope: effectiveReadinessScope,
                          ),
                          onSendReminder: _sendReminder,
                          isSendingReminder: _isSendingReminder,
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildViewSwitcher(
    DefenseBoardState state,
    DefenseSchedulerState schedState,
    DefenseOperationsView currentView,
  ) {
    final scheduleCount = _count(state, 'all');
    final totalReady = schedState.teams
        .where((t) {
          final readyStage = t['ready_for_stage']?.toString() ?? '';
          return readyStage.isNotEmpty && isTeamStageReady(t, readyStage);
        })
        .length;
    final totalCompleted = schedState.teams
        .where((t) => ((t['completed_stages'] as List<dynamic>?) ?? []).isNotEmpty)
        .length;
    final totalPending = schedState.teams.length - totalReady;

    String readinessBadge;
    Color badgeColor;
    Color badgeTextColor;

    if (totalReady > 0) {
      readinessBadge = '$totalReady Ready';
      badgeColor = const Color(0xFFDEF7EC);
      badgeTextColor = const Color(0xFF03543F);
    } else if (totalCompleted > 0) {
      readinessBadge = 'Complete';
      badgeColor = const Color(0xFFDEF7EC);
      badgeTextColor = const Color(0xFF03543F);
    } else {
      readinessBadge = '$totalPending Pending';
      badgeColor = const Color(0xFFFEF3C7);
      badgeTextColor = const Color(0xFF92400E);
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _viewTabButton(
            title: 'Defense Schedules',
            icon: Icons.calendar_month_rounded,
            countBadge: '$scheduleCount',
            badgeColor: const Color(0xFFE2E8F0),
            badgeTextColor: const Color(0xFF334155),
            isSelected: currentView == DefenseOperationsView.schedules,
            onTap: () => ref
                .read(defenseBoardActiveViewProvider.notifier)
                .setView(DefenseOperationsView.schedules),
          ),
          _viewTabButton(
            title: 'Pre-Defense Readiness Queue',
            icon: Icons.checklist_rtl_rounded,
            countBadge: readinessBadge,
            badgeColor: badgeColor,
            badgeTextColor: badgeTextColor,
            isSelected: currentView == DefenseOperationsView.readiness,
            onTap: () => ref
                .read(defenseBoardActiveViewProvider.notifier)
                .setView(DefenseOperationsView.readiness),
          ),
        ],
      ),
    );
  }

  Widget _viewTabButton({
    required String title,
    required IconData icon,
    required String countBadge,
    required Color badgeColor,
    required Color badgeTextColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 17,
              color: isSelected ? AppColors.maroon : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? AppColors.maroon : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? badgeColor : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                countBadge,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? badgeTextColor : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftResumeBanner() {
    if (_savedImportDraft == null) return const SizedBox.shrink();
    final rowCount = _savedImportDraft!.parsed.rows.length;
    final timeStr = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(_savedImportDraft!.savedAt),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF93C5FD)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.pending_actions_rounded,
            color: Color(0xFF2563EB),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Unfinished schedule import draft — $rowCount staged ${rowCount == 1 ? 'slot' : 'slots'} · Saved at $timeStr',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E3A8A),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _openImportScheduleDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text(
              'Resume Draft',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final user = ref.read(authProvider).user;
              final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
              final scope = isAdmin ? 'capstone' : 'pit';
              await clearScheduleImportDraft(scope: scope);
              await _checkImportDraft();
              if (mounted) {
                showInfoToast(context, 'Schedule import draft discarded.');
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0xFFFCA5A5)),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 15, color: Color(0xFFDC2626)),
            label: const Text(
              'Discard',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadinessCalloutBanner(int readyCount) {
    if (readyCount <= 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_rounded,
            color: Color(0xFF059669),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$readyCount ${readyCount == 1 ? 'team has' : 'teams have'} met all deliverable requirements and ${readyCount == 1 ? 'is' : 'are'} ready for defense scheduling.',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF065F46),
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: () {
              ref
                  .read(defenseBoardActiveViewProvider.notifier)
                  .setView(DefenseOperationsView.readiness);
            },
            icon: const Icon(Icons.arrow_forward_rounded, size: 15, color: Color(0xFF047857)),
            label: const Text(
              'Open Readiness Queue',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF047857),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStagePillsRow(DefenseSchedulerState schedState, String scope, String activeStageName) {
    final user = ref.read(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 16, color: Color(0xFF64748B)),
                  const SizedBox(width: 6),
                  const Text(
                    'Target Defense Milestone / Event:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Spacer(),
                  if (isAdmin) ...[
                    Container(
                      height: 28,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _scopeMiniPill('Capstone', 'capstone', scope == 'capstone'),
                          _scopeMiniPill('PIT', 'pit', scope == 'pit'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              if (scope == 'capstone') ...[
                if (schedState.defenseStages.isEmpty)
                  const Text(
                    'No defense stages configured. Go to Defense Stages Setup to create milestones.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: schedState.defenseStages.map((stage) {
                      final stageId = asInt(stage['id']);
                      final stageLabel = stage['label']?.toString() ?? '';
                      final isSelected = stageId == _selectedReadinessStageId ||
                          (stageId == null && stageLabel == activeStageName);

                      final readyCountForStage = teamsForScope(schedState, 'capstone')
                          .where((t) => isTeamStageReady(t, stageLabel))
                          .length;
                      final completedCountForStage = teamsForScope(schedState, 'capstone')
                          .where((t) => isTeamStageCompleted(t, stageLabel))
                          .length;
                      final pendingCountForStage = teamsForScope(schedState, 'capstone')
                          .where((t) =>
                              !isTeamStageReady(t, stageLabel) &&
                              !isTeamStageCompleted(t, stageLabel) &&
                              !isTeamStageScheduled(t, stageLabel))
                          .length;

                      String badgeText;
                      Color badgeColor;
                      Color badgeTextColor;

                      if (readyCountForStage > 0) {
                        badgeText = '$readyCountForStage ready';
                        badgeColor = const Color(0xFFDEF7EC);
                        badgeTextColor = const Color(0xFF03543F);
                      } else if (completedCountForStage > 0) {
                        badgeText = 'Complete';
                        badgeColor = const Color(0xFFDEF7EC);
                        badgeTextColor = const Color(0xFF03543F);
                      } else {
                        badgeText = '$pendingCountForStage pending';
                        badgeColor = const Color(0xFFFEF3C7);
                        badgeTextColor = const Color(0xFF92400E);
                      }

                      return _stageFilterPill(
                        label: stageLabel,
                        badgeText: badgeText,
                        badgeColor: badgeColor,
                        badgeTextColor: badgeTextColor,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            _selectedReadinessStageId = stageId;
                          });
                        },
                      );
                    }).toList(),
                  ),
              ] else ...[
                if (schedState.pitEvents.isEmpty)
                  const Text(
                    'No PIT events configured for this term.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: schedState.pitEvents.map((evt) {
                      final eventName = evt['event_name']?.toString() ?? '';
                      final isSelected = eventName == activeStageName;
                      final readyCountForEvent = teamsForScope(schedState, 'pit')
                          .where((t) => isTeamStageReady(t, eventName))
                          .length;
                      final completedCountForEvent = teamsForScope(schedState, 'pit')
                          .where((t) => isTeamStageCompleted(t, eventName))
                          .length;
                      final pendingCountForEvent = teamsForScope(schedState, 'pit')
                          .where((t) =>
                              !isTeamStageReady(t, eventName) &&
                              !isTeamStageCompleted(t, eventName) &&
                              !isTeamStageScheduled(t, eventName))
                          .length;

                      String badgeText;
                      Color badgeColor;
                      Color badgeTextColor;

                      if (readyCountForEvent > 0) {
                        badgeText = '$readyCountForEvent ready';
                        badgeColor = const Color(0xFFDEF7EC);
                        badgeTextColor = const Color(0xFF03543F);
                      } else if (completedCountForEvent > 0) {
                        badgeText = 'Complete';
                        badgeColor = const Color(0xFFDEF7EC);
                        badgeTextColor = const Color(0xFF03543F);
                      } else {
                        badgeText = '$pendingCountForEvent pending';
                        badgeColor = const Color(0xFFFEF3C7);
                        badgeTextColor = const Color(0xFF92400E);
                      }

                      return _stageFilterPill(
                        label: eventName,
                        badgeText: badgeText,
                        badgeColor: badgeColor,
                        badgeTextColor: badgeTextColor,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            _selectedReadinessEventName = eventName;
                          });
                        },
                      );
                    }).toList(),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _stageFilterPill({
    required String label,
    required String badgeText,
    required Color badgeColor,
    required Color badgeTextColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.maroon : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.maroon : const Color(0xFFCBD5E1),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.maroon.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.2) : badgeColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : badgeTextColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scopeMiniPill(String label, String value, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          _readinessScope = value;
          _selectedReadinessStageId = null;
          _selectedReadinessEventName = null;
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? AppColors.maroon : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildReadinessSummaryCards(
    DefenseSchedulerState schedState,
    String activeStageName,
    int totalScopeTeams,
    int readyCount,
    int completedCount,
    int pendingCount,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1100;

        final cards = [
          _buildSummaryCard(
            icon: Icons.groups_rounded,
            iconColor: const Color(0xFF475569),
            label: 'Total Enrolled Teams',
            value: totalScopeTeams,
          ),
          _buildSummaryCard(
            icon: Icons.check_circle_rounded,
            iconColor: const Color(0xFF10B981),
            label: 'Ready for Scheduling',
            value: readyCount,
          ),
          _buildSummaryCard(
            icon: Icons.task_alt_rounded,
            iconColor: const Color(0xFF059669),
            label: 'Completed Milestone',
            value: completedCount,
          ),
          _buildSummaryCard(
            icon: Icons.pending_actions_rounded,
            iconColor: const Color(0xFFF59E0B),
            label: 'Pending Endorsements',
            value: pendingCount,
          ),
        ];

        if (compact) {
          return Column(
            children: cards
                .map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: c,
                    ))
                .toList(),
          );
        }

        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 14),
            Expanded(child: cards[1]),
            const SizedBox(width: 14),
            Expanded(child: cards[2]),
            const SizedBox(width: 14),
            Expanded(child: cards[3]),
          ],
        );
      },
    );
  }

  Widget _buildHeader(
    DefenseBoardState state,
    DefenseSchedulerState schedState,
    String effectiveReadinessScope,
    String activeStageName,
    int readyCount,
    DefenseOperationsView currentView,
  ) {
    final user = ref.watch(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;
    final canSchedule = isAdmin || isPitLead;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.view_agenda_outlined,
                    color: AppColors.maroon,
                    size: 24,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Defense Operations',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: AppColors.maroon,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                state.activeSemester?['display_name']?.toString() ??
                    'Live defense schedule, room timetable, and session operations.',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (canSchedule) ...[
          const SizedBox(width: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Tertiary / Quick Direct Action: Manual Schedule Form
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: _openManualScheduleDialog,
                  style: OutlinedButton.styleFrom(
                    elevation: 0,
                    foregroundColor: const Color(0xFF334155),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    backgroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(
                    Icons.edit_calendar_outlined,
                    size: 16,
                    color: Color(0xFF64748B),
                  ),
                  label: const Text(
                    'Manual Schedule',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ),
              // Secondary / File Ingestion Action: Import Schedule (Warm Amber Pill)
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: _openImportScheduleDialog,
                  style: OutlinedButton.styleFrom(
                    elevation: 0,
                    foregroundColor: const Color(0xFF92400E),
                    side: const BorderSide(color: Color(0xFFFCD34D)),
                    backgroundColor: const Color(0xFFFFFBEB),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(
                    Icons.upload_file_rounded,
                    size: 16,
                    color: Color(0xFFB45309),
                  ),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Import Schedule',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Color(0xFF92400E),
                        ),
                      ),
                      if (_hasImportDraft) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFB45309),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'DRAFT',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Primary Hero CTA: Generate Schedule (Academic Maroon + Gold Accent)
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (currentView == DefenseOperationsView.readiness && readyCount > 0) {
                      _openScheduler(
                        scope: effectiveReadinessScope,
                        stageId: _selectedReadinessStageId,
                        eventName: _selectedReadinessEventName,
                      );
                    } else {
                      _openScheduler();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    elevation: 1,
                    shadowColor: AppColors.maroon.withValues(alpha: 0.3),
                    backgroundColor: AppColors.maroon,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: AppColors.gold,
                  ),
                  label: Text(
                    currentView == DefenseOperationsView.readiness && readyCount > 0
                        ? 'Schedule $readyCount Ready ${readyCount == 1 ? 'Team' : 'Teams'}'
                        : 'Generate Schedule',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryCards(DefenseBoardState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1100;

        if (compact) {
          return Column(
            children: [
              _buildSummaryCard(
                icon: Icons.event,
                iconColor: const Color(0xFF7C3AED),
                label: 'Total Schedules',
                value: _count(state, 'all'),
              ),
              const SizedBox(height: 14),
              _buildSummaryCard(
                icon: Icons.access_time_filled,
                iconColor: const Color(0xFF2563EB),
                label: 'Upcoming',
                value: _count(state, 'scheduled'),
              ),
              const SizedBox(height: 14),
              _buildSummaryCard(
                icon: Icons.play_circle_fill_rounded,
                iconColor: const Color(0xFFD97706),
                label: 'Ongoing',
                value: _count(state, 'ongoing'),
              ),
              const SizedBox(height: 14),
              _buildSummaryCard(
                icon: Icons.check_circle,
                iconColor: const Color(0xFF0F9D58),
                label: 'Completed',
                value: _count(state, 'done'),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.event,
                iconColor: const Color(0xFF7C3AED),
                label: 'Total Schedules',
                value: _count(state, 'all'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.access_time_filled,
                iconColor: const Color(0xFF2563EB),
                label: 'Upcoming',
                value: _count(state, 'scheduled'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.play_circle_fill_rounded,
                iconColor: const Color(0xFFD97706),
                label: 'Ongoing',
                value: _count(state, 'ongoing'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.check_circle,
                iconColor: const Color(0xFF0F9D58),
                label: 'Completed',
                value: _count(state, 'done'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required int value,
    String? customValueText,
  }) {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customValueText ?? '$value',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(DefenseBoardState state) {
    final showStageOrEventFilter = state.scope.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isStacked = constraints.maxWidth < 1100;
          final isPit = state.scope == 'pit';

          if (isStacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildScopeTabs(state),
                      const SizedBox(width: 10),
                      _buildCollapseAllButton(state),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (!isPit)
                      Expanded(child: _buildAdviserDropdown(state, null))
                    else
                      Expanded(child: _buildSectionDropdown(state, null)),
                    const SizedBox(width: 10),
                    if (showStageOrEventFilter) ...[
                      Expanded(child: _buildStageOrEventDropdown(state, null)),
                      const SizedBox(width: 10),
                    ],
                    Expanded(child: _buildStatusDropdown(state, null)),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSearchField(state, double.infinity),
              ],
            );
          }

          return Row(
            children: [
              _buildScopeTabs(state),
              const SizedBox(width: 14),
              if (!isPit) ...[
                _buildAdviserDropdown(state, 175),
                const SizedBox(width: 10),
              ] else ...[
                _buildSectionDropdown(state, 165),
                const SizedBox(width: 10),
              ],
              if (showStageOrEventFilter) ...[
                _buildStageOrEventDropdown(state, 150),
                const SizedBox(width: 10),
              ],
              _buildStatusDropdown(state, 140),
              const SizedBox(width: 10),
              Expanded(child: _buildSearchField(state, null)),
              const SizedBox(width: 10),
              _buildCollapseAllButton(state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScopeTabs(DefenseBoardState state) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildScopeTabItem(
            state: state,
            label: 'All Defenses',
            scopeValue: '',
            icon: Icons.grid_view_rounded,
          ),
          _buildScopeTabItem(
            state: state,
            label: 'Capstone',
            scopeValue: 'capstone',
            icon: Icons.school_rounded,
          ),
          _buildScopeTabItem(
            state: state,
            label: 'PIT',
            scopeValue: 'pit',
            icon: Icons.alt_route_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildScopeTabItem({
    required DefenseBoardState state,
    required String label,
    required String scopeValue,
    required IconData icon,
  }) {
    final isSelected = state.scope == scopeValue;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(defenseBoardProvider.notifier).fetchBoard(
                stage: '',
                status: state.status,
                scope: scopeValue,
                adviser: '',
                section: '',
                search: _searchController.text.trim(),
              );
        },
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected
                ? const [
                    BoxShadow(
                      color: Color(0x0F000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? AppColors.maroon : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? AppColors.maroon : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdviserDropdown(DefenseBoardState state, double? width) {
    final Map<String, String> adviserMap = {};
    for (final adv in state.advisers) {
      final id = adv['id']?.toString() ?? '';
      final name = adv['name']?.toString() ?? '';
      final count = adv['count']?.toString() ?? '0';
      if (id.isNotEmpty && name.isNotEmpty) {
        adviserMap[id] = '$name ($count)';
      }
    }

    if (adviserMap.isEmpty) {
      final Map<String, int> counts = {};
      for (final s in state.schedules) {
        final advName = s['adviser_name']?.toString() ?? '';
        final advId = s['adviser_id']?.toString() ?? '';
        if (advName.isNotEmpty) {
          counts[advName] = (counts[advName] ?? 0) + 1;
          adviserMap[advId.isNotEmpty ? advId : advName] = '$advName (${counts[advName]})';
        }
      }
    }

    final currentValue = adviserMap.containsKey(state.adviser) ? state.adviser : '';

    return SizedBox(
      width: width,
      height: 48,
      child: DropdownButtonFormField<String>(
        key: ValueKey('adviser_filter_${state.scope}'),
        initialValue: currentValue,
        decoration: _inputDecoration(
          prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.textSecondary, size: 18),
        ),
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(12),
        isExpanded: true,
        items: [
          const DropdownMenuItem<String>(
            value: '',
            child: Text(
              'All Advisers',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          ...adviserMap.entries.map(
            (entry) => DropdownMenuItem<String>(
              value: entry.key,
              child: Text(
                entry.value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
        onChanged: (value) {
          ref.read(defenseBoardProvider.notifier).fetchBoard(
                stage: state.stage,
                status: state.status,
                scope: state.scope,
                adviser: value ?? '',
                section: state.section,
                search: _searchController.text.trim(),
              );
        },
      ),
    );
  }

  Widget _buildSectionDropdown(DefenseBoardState state, double? width) {
    final Map<String, String> sectionMap = {};
    for (final sec in state.sections) {
      final name = sec['name']?.toString() ?? '';
      final count = sec['count']?.toString() ?? '0';
      if (name.isNotEmpty) {
        sectionMap[name] = '$name ($count)';
      }
    }

    if (sectionMap.isEmpty) {
      final Map<String, int> counts = {};
      for (final s in state.schedules) {
        final secName = s['section']?.toString() ?? '';
        if (secName.isNotEmpty) {
          counts[secName] = (counts[secName] ?? 0) + 1;
          sectionMap[secName] = '$secName (${counts[secName]})';
        }
      }
    }

    final currentValue = sectionMap.containsKey(state.section) ? state.section : '';

    return SizedBox(
      width: width,
      height: 48,
      child: DropdownButtonFormField<String>(
        key: ValueKey('section_filter_${state.scope}'),
        initialValue: currentValue,
        decoration: _inputDecoration(
          prefixIcon: const Icon(Icons.school_outlined, color: AppColors.textSecondary, size: 18),
        ),
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(12),
        isExpanded: true,
        items: [
          const DropdownMenuItem<String>(
            value: '',
            child: Text(
              'All Sections',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          ...sectionMap.entries.map(
            (entry) => DropdownMenuItem<String>(
              value: entry.key,
              child: Text(
                entry.value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
        onChanged: (value) {
          ref.read(defenseBoardProvider.notifier).fetchBoard(
                stage: state.stage,
                status: state.status,
                scope: state.scope,
                adviser: state.adviser,
                section: value ?? '',
                search: _searchController.text.trim(),
              );
        },
      ),
    );
  }

  Widget _buildCollapseAllButton(DefenseBoardState state) {
    final groups = _groupSchedules(state.schedules);
    final allKeys = groups.map((g) => g.key).toSet();
    final isAllCollapsed = allKeys.isNotEmpty && _collapsedSessions.containsAll(allKeys);

    return OutlinedButton.icon(
      icon: Icon(
        isAllCollapsed ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
        size: 16,
        color: DefensysTokens.textDark,
      ),
      label: Text(
        isAllCollapsed ? 'Expand All' : 'Collapse All',
        style: const TextStyle(
          fontFamily: DefensysTokens.fontFamilyInter,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: DefensysTokens.textDark,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        backgroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: () {
        setState(() {
          if (isAllCollapsed) {
            _collapsedSessions.clear();
          } else {
            _collapsedSessions.addAll(allKeys);
          }
        });
      },
    );
  }

  Widget _buildStageOrEventDropdown(DefenseBoardState state, double? width) {
    final isPit = state.scope == 'pit';
    final defaultLabel = isPit ? 'All Events' : 'All Stages';
    final icon = isPit ? Icons.event_rounded : Icons.layers_outlined;

    final Set<String> scopeOptions = {};

    for (final schedule in state.schedules) {
      final itemScope = schedule['scope']?.toString() ?? 'capstone';
      final stageLabel = schedule['stage_label']?.toString();
      if (stageLabel != null && stageLabel.isNotEmpty) {
        if (state.scope.isEmpty || itemScope == state.scope) {
          scopeOptions.add(stageLabel);
        }
      }
    }

    if (scopeOptions.isEmpty && state.stageOptions.isNotEmpty) {
      scopeOptions.addAll(state.stageOptions);
    }

    final List<String> options = scopeOptions.toList()..sort();
    final currentValue = options.contains(state.stage) ? state.stage : '';

    return SizedBox(
      width: width,
      height: 48,
      child: DropdownButtonFormField<String>(
        key: ValueKey('stage_or_event_${state.scope}'),
        initialValue: currentValue,
        decoration: _inputDecoration(
          prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
        ),
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(12),
        isExpanded: true,
        items: [
          DropdownMenuItem<String>(
            value: '',
            child: Text(
              defaultLabel,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          ...options.map(
            (opt) => DropdownMenuItem<String>(
              value: opt,
              child: Text(
                opt,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
        onChanged: (value) {
          ref.read(defenseBoardProvider.notifier).fetchBoard(
                stage: value ?? '',
                status: state.status,
                scope: state.scope,
                adviser: state.adviser,
                section: state.section,
                search: _searchController.text.trim(),
              );
        },
      ),
    );
  }

  Widget _buildStatusDropdown(DefenseBoardState state, double? width) {
    final statuses = state.statuses.toSet().toList();
    final currentValue = statuses.contains(state.status)
        ? state.status
        : '';

    return SizedBox(
      width: width,
      height: 48,
      child: DropdownButtonFormField<String>(
        initialValue: currentValue,
        decoration: _inputDecoration(
          prefixIcon: const Icon(Icons.filter_list_rounded, color: AppColors.textSecondary, size: 18),
        ),
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(12),
        isExpanded: true,
        items: [
          const DropdownMenuItem<String>(
            value: '',
            child: Text('All Statuses', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          ...statuses.map(
            (status) => DropdownMenuItem<String>(
              value: status,
              child: Text(_statusLabel(status), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
        onChanged: (value) {
          ref.read(defenseBoardProvider.notifier).fetchBoard(
                stage: state.stage,
                status: value ?? '',
                scope: state.scope,
                adviser: state.adviser,
                section: state.section,
                search: _searchController.text.trim(),
              );
        },
      ),
    );
  }

  Widget _buildSearchField(DefenseBoardState state, double? width) {
    return SizedBox(
      width: width,
      height: 48,
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        decoration: _inputDecoration(
          hintText: 'Search team or room...',
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textSecondary),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(defenseBoardProvider.notifier).fetchBoard(
                          stage: state.stage,
                          status: state.status,
                          scope: state.scope,
                          adviser: state.adviser,
                          section: state.section,
                          search: '',
                        );
                  },
                )
              : null,
        ),
        onSubmitted: (value) {
          ref.read(defenseBoardProvider.notifier).fetchBoard(
                stage: state.stage,
                status: state.status,
                scope: state.scope,
                adviser: state.adviser,
                section: state.section,
                search: value.trim(),
              );
        },
      ),
    );
  }

  Widget _buildBoardSection(DefenseBoardState state) {
    if (state.schedules.isEmpty) {
      return _buildEmptyBoard();
    }

    final groups = _groupSchedules(state.schedules);

    return Column(
      children: groups.map((group) => _buildSessionCard(group, state)).toList(),
    );
  }

  List<_SessionGroup> _groupSchedules(List<dynamic> rawSchedules) {
    final Map<String, _SessionGroup> groupMap = {};

    for (final item in rawSchedules) {
      if (item is! Map<String, dynamic>) continue;

      final stageLabel = item['stage_label']?.toString() ?? 'Unspecified Stage';
      final date = item['scheduled_date']?.toString() ?? 'TBD';
      final room = item['room']?.toString() ?? 'TBD';
      final panel = _panelistNames(item);
      final documenter = item['documenter_name']?.toString() ?? '';
      final scope = item['scope']?.toString() ?? 'capstone';

      final key = '$stageLabel|$date|$room|$panel|$documenter';

      if (!groupMap.containsKey(key)) {
        groupMap[key] = _SessionGroup(
          key: key,
          stageLabel: stageLabel,
          scheduledDate: date,
          room: room,
          panelNames: panel,
          documenterName: documenter,
          scope: scope,
          schedules: [],
        );
      }
      groupMap[key]!.schedules.add(item);
    }

    // Sort schedules inside each group by start_time
    for (final group in groupMap.values) {
      group.schedules.sort((a, b) {
        final tA = a['start_time']?.toString() ?? '';
        final tB = b['start_time']?.toString() ?? '';
        return tA.compareTo(tB);
      });
    }

    return groupMap.values.toList();
  }

  Widget _buildSessionCard(_SessionGroup group, DefenseBoardState state) {
    final isCollapsed = _collapsedSessions.contains(group.key);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSessionHeader(group, isCollapsed),
          if (!isCollapsed)
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 900) {
                  return _buildCompactTeamList(group, state);
                }
                return _buildDesktopTeamTable(group, state);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSessionHeader(_SessionGroup group, bool isCollapsed) {
    final isPit = group.scope == 'pit';
    final accentColor = isPit ? const Color(0xFF0284C7) : DefensysTokens.maroon;
    final isDocUnassigned = group.documenterName.isEmpty;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          setState(() {
            if (_collapsedSessions.contains(group.key)) {
              _collapsedSessions.remove(group.key);
            } else {
              _collapsedSessions.add(group.key);
            }
          });
        },
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFEDF2F7), width: 1),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Accent Bar (solid colored indicator)
                Container(
                  width: 4,
                  color: accentColor,
                ),
                // Main Header Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row 1: Scope Pill + Stage Title + Date/Venue Capsule + Team Count + Chevron
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Scope Pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isPit ? 'PIT' : 'CAPSTONE',
                                style: TextStyle(
                                  fontFamily: DefensysTokens.fontFamilyInter,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: accentColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Stage Label
                            Text(
                              group.stageLabel,
                              style: const TextStyle(
                                fontFamily: DefensysTokens.fontFamilyInter,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: DefensysTokens.textPrimary,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(width: 14),
                            // Date & Venue Capsule
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.calendar_today_rounded,
                                    size: 13,
                                    color: DefensysTokens.steelGrey,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    group.scheduledDate,
                                    style: const TextStyle(
                                      fontFamily: DefensysTokens.fontFamilyInter,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: DefensysTokens.textDark,
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Text(
                                      '•',
                                      style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.place_rounded,
                                    size: 14,
                                    color: DefensysTokens.steelGrey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    group.room,
                                    style: const TextStyle(
                                      fontFamily: DefensysTokens.fontFamilyInter,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: DefensysTokens.textDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            // Team count badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: accentColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${group.schedules.length} ${group.schedules.length == 1 ? 'Team' : 'Teams'}',
                                    style: const TextStyle(
                                      fontFamily: DefensysTokens.fontFamilyInter,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: DefensysTokens.textDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Chevron Toggle Indicator
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                isCollapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded,
                                size: 18,
                                color: DefensysTokens.steelGrey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Row 2: Panel and Documenter together in natural reading order
                        Wrap(
                          spacing: 18,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // Panel Tag & Names
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'PANEL',
                                    style: TextStyle(
                                      fontFamily: DefensysTokens.fontFamilyInter,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: DefensysTokens.steelGrey,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  group.panelNames.isNotEmpty ? group.panelNames : 'No panel assigned',
                                  style: const TextStyle(
                                    fontFamily: DefensysTokens.fontFamilyInter,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: DefensysTokens.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            if (!isPit) ...[
                              const Text(
                                '•',
                                style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'DOCUMENTER',
                                      style: TextStyle(
                                        fontFamily: DefensysTokens.fontFamilyInter,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: DefensysTokens.steelGrey,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isDocUnassigned ? DefensysTokens.warningBg : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isDocUnassigned ? DefensysTokens.warningBorder : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Text(
                                      isDocUnassigned ? 'Unassigned' : group.documenterName,
                                      style: TextStyle(
                                        fontFamily: DefensysTokens.fontFamilyInter,
                                        fontSize: 12,
                                        fontWeight: isDocUnassigned ? FontWeight.w600 : FontWeight.w500,
                                        color: isDocUnassigned ? DefensysTokens.warningText : DefensysTokens.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopTeamTable(_SessionGroup group, DefenseBoardState state) {
    final isPit = group.scope == 'pit';
    const pageSize = 10;
    final totalTeams = group.schedules.length;
    final totalPages = (totalTeams / pageSize).ceil();
    final currentPage = _sessionPages[group.key] ?? 0;
    final safePage = currentPage >= totalPages ? 0 : currentPage;

    final paginatedSchedules = totalTeams > pageSize
        ? group.schedules.sublist(
            safePage * pageSize,
            (safePage + 1) * pageSize > totalTeams ? totalTeams : (safePage + 1) * pageSize,
          )
        : group.schedules;

    return Column(
      children: [
        // Sub-table Header (Refined Uppercase Small-Caps)
        Container(
          height: 38,
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(
              bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
            ),
          ),
          child: Row(
            children: [
              const _HeaderCell('TIME SLOT', flex: 1),
              _HeaderCell('TEAM & PROJECT TITLE', flex: isPit ? 5 : 4),
              if (!isPit) const _HeaderCell('MINUTES', flex: 2),
              const _HeaderCell('EVALUATION', flex: 2),
              const _HeaderCell('STATUS', flex: 2),
              const _HeaderCell('DETAILS', flex: 1),
            ],
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: paginatedSchedules.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
          itemBuilder: (context, index) {
            final schedule = paginatedSchedules[index];
            final projectTitle = schedule['project_title']?.toString() ?? '';
            final adviserName = schedule['adviser_name']?.toString() ?? '';
            final section = schedule['section']?.toString() ?? '';

            return Container(
              constraints: const BoxConstraints(minHeight: 68),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  _BodyCell(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: DefensysTokens.steelGrey,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _shortTime(schedule['start_time']),
                            style: const TextStyle(
                              fontFamily: DefensysTokens.fontFamilyInter,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: DefensysTokens.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _BodyCell(
                    flex: isPit ? 5 : 4,
                    child: InkWell(
                      onTap: () => _showDefenseDetailsDialog(schedule, group),
                      borderRadius: BorderRadius.circular(4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            schedule['team_name']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: DefensysTokens.fontFamilyInter,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: DefensysTokens.textPrimary,
                            ),
                          ),
                          if (projectTitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              projectTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: DefensysTokens.fontFamilyInter,
                                fontSize: 12,
                                color: DefensysTokens.textSecondary,
                              ),
                            ),
                          ],
                          if (!isPit && adviserName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_outline_rounded, size: 12, color: DefensysTokens.steelGrey),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    'Adviser: $adviserName',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: DefensysTokens.fontFamilyInter,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: DefensysTokens.steelGrey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else if (isPit && section.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.school_outlined, size: 12, color: DefensysTokens.steelGrey),
                                const SizedBox(width: 3),
                                Text(
                                  'Section: $section',
                                  style: const TextStyle(
                                    fontFamily: DefensysTokens.fontFamilyInter,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: DefensysTokens.steelGrey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (!isPit)
                    _BodyCell(
                      flex: 2,
                      child: _minutesStatusChip(schedule),
                    ),
                  _BodyCell(
                    flex: 2,
                    child: _evaluationChip(schedule),
                  ),
                  _BodyCell(
                    flex: 2,
                    child: _statusChip(
                      schedule['display_status']?.toString() ??
                          schedule['status']?.toString() ??
                          '',
                    ),
                  ),
                  _BodyCell(
                    flex: 1,
                    child: _rowActionButtons(state, schedule, group),
                  ),
                ],
              ),
            );
          },
        ),
        if (totalTeams > pageSize)
          _buildTablePagination(group.key, safePage, totalPages, totalTeams, pageSize),
      ],
    );
  }

  Widget _buildTablePagination(
    String groupKey,
    int currentPage,
    int totalPages,
    int totalTeams,
    int pageSize,
  ) {
    final startIdx = currentPage * pageSize + 1;
    final endIdx = (currentPage + 1) * pageSize > totalTeams
        ? totalTeams
        : (currentPage + 1) * pageSize;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing $startIdx–$endIdx of $totalTeams teams',
            style: const TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: DefensysTokens.steelGrey,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 18),
                splashRadius: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: currentPage > 0
                    ? () {
                        setState(() {
                          _sessionPages[groupKey] = currentPage - 1;
                        });
                      }
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Page ${currentPage + 1} of $totalPages',
                  style: const TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textDark,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
                splashRadius: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: currentPage < totalPages - 1
                    ? () {
                        setState(() {
                          _sessionPages[groupKey] = currentPage + 1;
                        });
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactTeamList(_SessionGroup group, DefenseBoardState state) {
    final isPit = group.scope == 'pit';
    const pageSize = 10;
    final totalTeams = group.schedules.length;
    final totalPages = (totalTeams / pageSize).ceil();
    final currentPage = _sessionPages[group.key] ?? 0;
    final safePage = currentPage >= totalPages ? 0 : currentPage;

    final paginatedSchedules = totalTeams > pageSize
        ? group.schedules.sublist(
            safePage * pageSize,
            (safePage + 1) * pageSize > totalTeams ? totalTeams : (safePage + 1) * pageSize,
          )
        : group.schedules;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          ...paginatedSchedules.map((schedule) {
            final teamName = schedule['team_name']?.toString() ?? 'Unnamed Team';
            final projectTitle = schedule['project_title']?.toString() ?? '';
            final adviserName = schedule['adviser_name']?.toString() ?? '';
            final section = schedule['section']?.toString() ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE9EDF4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Text(
                          _shortTime(schedule['start_time']),
                          style: const TextStyle(
                            fontFamily: DefensysTokens.fontFamilyInter,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () => _showDefenseDetailsDialog(schedule, group),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              teamName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: DefensysTokens.fontFamilyInter,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: DefensysTokens.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      _rowActionButtons(state, schedule, group),
                    ],
                  ),
                  if (projectTitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      projectTitle,
                      style: const TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 12,
                        color: DefensysTokens.textSecondary,
                      ),
                    ),
                  ],
                  if (!isPit && adviserName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_outline_rounded, size: 13, color: DefensysTokens.steelGrey),
                        const SizedBox(width: 4),
                        Text(
                          'Adviser: $adviserName',
                          style: const TextStyle(
                            fontFamily: DefensysTokens.fontFamilyInter,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DefensysTokens.steelGrey,
                          ),
                        ),
                      ],
                    ),
                  ] else if (isPit && section.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.school_outlined, size: 13, color: DefensysTokens.steelGrey),
                        const SizedBox(width: 4),
                        Text(
                          'Section: $section',
                          style: const TextStyle(
                            fontFamily: DefensysTokens.fontFamilyInter,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DefensysTokens.steelGrey,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _statusChip(
                        schedule['display_status']?.toString() ??
                            schedule['status']?.toString() ??
                            '',
                      ),
                      if (!isPit) _minutesStatusChip(schedule),
                      _evaluationChip(schedule),
                    ],
                  ),
                ],
              ),
            );
          }),
          if (totalTeams > pageSize)
            _buildTablePagination(group.key, safePage, totalPages, totalTeams, pageSize),
        ],
      ),
    );
  }

  Widget _rowActionButtons(
    DefenseBoardState state,
    Map<String, dynamic> schedule,
    _SessionGroup group,
  ) {
    final user = ref.watch(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;
    final isSchedulePit = schedule['scope'] == 'pit';
    final canDelete = isAdmin || (isPitLead && isSchedulePit);

    final currentStatus = (schedule['display_status']?.toString() ??
            schedule['status']?.toString() ??
            '')
        .toLowerCase();
    final isScheduled = !['ongoing', 'done', 'completed', 'archived'].contains(currentStatus);
    final scheduleId = _asInt(schedule['id']);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'View Defense Details',
          splashRadius: 18,
          iconSize: 18,
          color: DefensysTokens.steelGrey,
          style: IconButton.styleFrom(
            hoverColor: const Color(0xFFF1F5F9),
          ),
          onPressed: () => _showDefenseDetailsDialog(schedule, group),
          icon: const Icon(Icons.info_outline_rounded),
        ),
        if (canDelete && isScheduled)
          IconButton(
            tooltip: 'Delete schedule',
            splashRadius: 18,
            iconSize: 18,
            color: const Color(0xFFEF4444),
            style: IconButton.styleFrom(
              hoverColor: const Color(0xFFFEE2E2),
            ),
            onPressed: state.isSaving || scheduleId == null
                ? null
                : () => _confirmDelete(
                    scheduleId,
                    schedule['team_name']?.toString() ?? 'schedule',
                  ),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
      ],
    );
  }

  void _showDefenseDetailsDialog(Map<String, dynamic> schedule, _SessionGroup group) {
    final isPit = group.scope == 'pit';
    final accentColor = isPit ? const Color(0xFF0284C7) : DefensysTokens.maroon;
    final teamName = schedule['team_name']?.toString() ?? 'Unnamed Team';
    final projectTitle = schedule['project_title']?.toString() ?? 'No title provided';
    final teamLevel = schedule['team_level']?.toString() ?? '';
    final adviserName = schedule['adviser_name']?.toString() ?? '';
    final section = schedule['section']?.toString() ?? '';
    final leaderName = schedule['leader_name']?.toString() ?? '';
    final rubricName = schedule['rubric_name']?.toString() ?? 'Default Evaluation Rubric';
    final status = (schedule['display_status']?.toString() ?? schedule['status']?.toString() ?? 'scheduled').toLowerCase();
    final startTime = _shortTime(schedule['start_time']);
    final slotDuration = schedule['slot_duration']?.toString() ?? '60';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: const BorderSide(color: Color(0xFFE2E8F0)),
                    left: BorderSide(color: accentColor, width: 4),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isPit ? 'PIT' : 'CAPSTONE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: accentColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.stageLabel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: DefensysTokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${group.scheduledDate} • $startTime ($slotDuration min) • ${group.room}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: DefensysTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: DefensysTokens.steelGrey),
                      onPressed: () => Navigator.pop(ctx),
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),
              // Body Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Team & Project Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.groups_rounded, size: 18, color: DefensysTokens.steelGrey),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    teamName,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: DefensysTokens.textPrimary,
                                    ),
                                  ),
                                ),
                                if (teamLevel.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: Text(
                                      teamLevel,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: DefensysTokens.textDark,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              projectTitle,
                              style: const TextStyle(
                                fontSize: 13,
                                color: DefensysTokens.textSecondary,
                                height: 1.4,
                              ),
                            ),
                            if (adviserName.isNotEmpty || section.isNotEmpty || leaderName.isNotEmpty) ...[
                              const Divider(height: 20, color: Color(0xFFE2E8F0)),
                              Wrap(
                                spacing: 18,
                                runSpacing: 6,
                                children: [
                                  if (adviserName.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.person_outline_rounded, size: 14, color: DefensysTokens.steelGrey),
                                        const SizedBox(width: 4),
                                        Text('Adviser: $adviserName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DefensysTokens.textDark)),
                                      ],
                                    ),
                                  if (section.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.school_outlined, size: 14, color: DefensysTokens.steelGrey),
                                        const SizedBox(width: 4),
                                        Text('Section: $section', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DefensysTokens.textDark)),
                                      ],
                                    ),
                                  if (leaderName.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_outline_rounded, size: 14, color: DefensysTokens.steelGrey),
                                        const SizedBox(width: 4),
                                        Text('Leader: $leaderName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DefensysTokens.textDark)),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Defense Committee Section
                      const Text(
                        'DEFENSE COMMITTEE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: DefensysTokens.steelGrey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.people_outline_rounded, size: 16, color: DefensysTokens.steelGrey),
                                const SizedBox(width: 8),
                                const Text(
                                  'Panelists: ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: DefensysTokens.textDark,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    group.panelNames.isNotEmpty ? group.panelNames : 'None assigned',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: DefensysTokens.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!isPit) ...[
                              const Divider(height: 18, color: Color(0xFFF1F5F9)),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.edit_note_rounded, size: 16, color: DefensysTokens.steelGrey),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Documenter: ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: DefensysTokens.textDark,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      group.documenterName.isNotEmpty ? group.documenterName : 'Unassigned',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: group.documenterName.isEmpty ? FontWeight.w600 : FontWeight.w500,
                                        color: group.documenterName.isEmpty ? DefensysTokens.warningText : DefensysTokens.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Meta Grid: Status & Rubric
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'CURRENT STATUS',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: DefensysTokens.steelGrey,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _statusChip(status),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'EVALUATION RUBRIC',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: DefensysTokens.steelGrey,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    rubricName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: DefensysTokens.textDark,
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
                ),
              ),
              // Footer Actions
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!isPit) ...[
                      OutlinedButton.icon(
                        icon: const Icon(Icons.description_outlined, size: 15),
                        label: const Text('Open Minutes'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DefensysTokens.textDark,
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          final scheduleId = _asInt(schedule['id']);
                          if (scheduleId != null) {
                            setState(() => _selectedMinutesScheduleId = scheduleId);
                          }
                        },
                      ),
                      const SizedBox(width: 10),
                    ],
                    ElevatedButton.icon(
                      icon: const Icon(Icons.grading_rounded, size: 15),
                      label: const Text('Evaluation & Grades'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openEvaluationAndGrades(schedule);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final normalized = status.toLowerCase();

    Color bg;
    Color fg;
    Color border;
    IconData iconData;
    String text;

    switch (normalized) {
      case 'ongoing':
        bg = DefensysTokens.warningBg;
        fg = DefensysTokens.warningText;
        border = DefensysTokens.warningBorder;
        iconData = Icons.play_circle_rounded;
        text = 'Ongoing';
        break;
      case 'done':
      case 'completed':
        bg = DefensysTokens.successBg;
        fg = DefensysTokens.successText;
        border = DefensysTokens.successBorder;
        iconData = Icons.check_circle_rounded;
        text = 'Completed';
        break;
      case 'cancelled':
        bg = DefensysTokens.dangerBg;
        fg = DefensysTokens.dangerText;
        border = DefensysTokens.dangerBorder;
        iconData = Icons.cancel_rounded;
        text = 'Cancelled';
        break;
      case 'archived':
        bg = DefensysTokens.archivedBg;
        fg = DefensysTokens.archivedText;
        border = DefensysTokens.archivedBorder;
        iconData = Icons.archive_rounded;
        text = 'Archived';
        break;
      default:
        bg = DefensysTokens.infoBg;
        fg = DefensysTokens.infoText;
        border = DefensysTokens.infoBorder;
        iconData = Icons.schedule_rounded;
        text = 'Scheduled';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyBoard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: DefensysEmptyState(
        icon: Icons.table_chart_outlined,
        title: 'No Defense Schedules Found',
        description:
            'There are no defense hearings matching the selected criteria or active term.',
        size: DefensysEmptyStateSize.standard,
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EF)),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.maroon),
      ),
    );
  }



  InputDecoration _inputDecoration({String? hintText, Widget? prefixIcon, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      hintStyle: const TextStyle(color: AppColors.textSecondary),
      filled: true,
      fillColor: const Color(0xFFFBFCFE),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD7DDE8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.maroon),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD7DDE8)),
      ),
    );
  }

  Future<void> _openManualScheduleDialog() async {
    final user = ref.read(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;
    if (!isAdmin && !isPitLead) return;

    final schedNotifier = ref.read(defenseSchedulerProvider.notifier);
    await schedNotifier.fetchSchedules();
    final schedState = ref.read(defenseSchedulerProvider);
    final scope = isAdmin ? 'capstone' : 'pit';

    if (!mounted) return;

    await ManualSlotEditorDialog.show(
      context,
      ref,
      state: schedState,
      initialScope: scope,
      initialStageId: null,
      initialRubricId: null,
      initialAdviserRubricId: null,
      initialCapstonePeerRubricId: null,
      initialPeerRubricId: null,
      initialSelectedPanelistIds: {},
      initialDocumenterId: null,
      initialEvent: '',
      initialPitTemplate: '',
      initialDate: '',
      initialTime: '08:00',
      initialDuration: '60',
      initialRoom: '',
      initialPanelWeight: '80',
      initialPeerWeight: '20',
      canScheduleScope: (s, sc) {
        if (sc == 'capstone') return isAdmin && s.canScheduleCapstone;
        if (sc == 'pit') return isPitLead && !isAdmin && s.canSchedulePit;
        return false;
      },
      scheduleNoticeMessage: (s) {
        if (isAdmin) {
          return 'Scheduling Capstone defenses is strictly reserved for Administrators.';
        }
        if (isPitLead) {
          return 'PIT scheduling is strictly managed by the PIT Lead.';
        }
        return 'Defense scheduling is restricted.';
      },
    );

    if (!mounted) return;
    ref.read(defenseBoardProvider.notifier).fetchBoard();
  }

  Future<void> _openImportScheduleDialog() async {
    final user = ref.read(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;
    if (!isAdmin && !isPitLead) return;

    final schedNotifier = ref.read(defenseSchedulerProvider.notifier);
    await schedNotifier.fetchSchedules();
    final schedState = ref.read(defenseSchedulerProvider);
    final scope = isAdmin ? 'capstone' : 'pit';

    if (!mounted) return;

    await ScheduleImportDialog.show(
      context,
      ref,
      state: schedState,
      scope: scope,
      initialStageId: null,
      initialEventName: '',
      initialRubricId: null,
      initialAdviserRubricId: null,
      initialPeerRubricId: null,
      initialCapstonePeerRubricId: null,
      initialDate: '',
      initialRoom: '',
      initialDuration: '60',
      initialPanelWeight: '80',
      initialPeerWeight: '20',
      canScheduleScope: (s, sc) {
        if (sc == 'capstone') return isAdmin && s.canScheduleCapstone;
        if (sc == 'pit') return isPitLead && !isAdmin && s.canSchedulePit;
        return false;
      },
      scheduleNoticeMessage: (s) {
        if (isAdmin) {
          return 'Scheduling Capstone defenses is strictly reserved for Administrators.';
        }
        if (isPitLead) {
          return 'PIT scheduling is strictly managed by the PIT Lead.';
        }
        return 'Defense scheduling is restricted.';
      },
    );

    if (!mounted) return;
    await _checkImportDraft();
    ref.read(defenseBoardProvider.notifier).fetchBoard();
  }

  void _openScheduler({String? scope, int? stageId, String? eventName}) {
    final user = ref.read(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;
    if (!isAdmin && !isPitLead) return;

    setState(() {
      _schedulerScope = scope;
      _schedulerStageId = stageId;
      _schedulerEventName = eventName;
      _showScheduler = true;
    });
  }

  Future<void> _confirmDelete(int scheduleId, String teamName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Schedule'),
          content: Text('Delete schedule for $teamName?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;
    await ref.read(defenseBoardProvider.notifier).deleteSchedule(scheduleId);
  }

  String _panelistNames(Map<String, dynamic> schedule) {
    final panelists = schedule['panelists'];
    if (panelists is! List || panelists.isEmpty) {
      return 'No panel assigned';
    }

    return panelists
        .whereType<Map>()
        .map((panelist) => panelist['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .join(', ');
  }

  String _shortTime(dynamic value) {
    final text = value?.toString() ?? '';
    return text.length >= 5 ? text.substring(0, 5) : text;
  }

  String _statusLabel(String status) {
    if (status.isEmpty) return '';
    return status[0].toUpperCase() + status.substring(1);
  }

  int _count(DefenseBoardState state, String key) {
    final value = state.counts[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Widget _minutesStatusChip(Map<String, dynamic> schedule) {
    final status = schedule['minutes_status']?.toString();
    final scheduleId = _asInt(schedule['id']);
    if (scheduleId == null || schedule['scope'] != 'capstone') {
      return const SizedBox.shrink();
    }

    String label = 'No Minutes';
    Color bg = const Color(0xFFF1F5F9);
    Color fg = const Color(0xFF64748B);
    Color border = const Color(0xFFE2E8F0);
    IconData icon = Icons.description_outlined;

    if (status == 'draft') {
      label = 'Draft';
      bg = const Color(0xFFFFFBEB);
      fg = const Color(0xFFB45309);
      border = const Color(0xFFFDE68A);
      icon = Icons.edit_note_rounded;
    } else if (status == 'submitted') {
      label = 'Submitted';
      bg = const Color(0xFFEFF6FF);
      fg = const Color(0xFF1D4ED8);
      border = const Color(0xFFBFDBFE);
      icon = Icons.send_rounded;
    } else if (status == 'adviser_signed') {
      label = 'Adviser Signed';
      bg = const Color(0xFFFAF5FF);
      fg = const Color(0xFF7E22CE);
      border = const Color(0xFFE9D5FF);
      icon = Icons.draw_rounded;
    } else if (status == 'completed') {
      label = 'Completed';
      bg = const Color(0xFFECFDF5);
      fg = const Color(0xFF047857);
      border = const Color(0xFFA7F3D0);
      icon = Icons.task_alt_rounded;
    }

    return InkWell(
      onTap: () {
        setState(() {
          _selectedMinutesScheduleId = scheduleId;
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.open_in_new_rounded, size: 10, color: fg),
          ],
        ),
      ),
    );
  }

  void _openEvaluationAndGrades(Map<String, dynamic> schedule) {
    final location = GoRouterState.of(context).uri.path;
    final isAdmin = location.startsWith('/admin/');
    final isFaculty = location.startsWith('/faculty/');

    int? gradeId = asInt(schedule['grade_id']);

    // Fallback: lookup in gradeCenterProvider state if not directly in schedule map
    if (gradeId == null) {
      final gcState = ref.read(gradeCenterProvider);
      final schedId = asInt(schedule['id']);
      final teamId = asInt(schedule['team_id']);
      final stageLabel = schedule['stage_label']?.toString() ??
          schedule['defense_stage_label']?.toString() ??
          '';

      for (final g in gcState.grades) {
        if (schedId != null && asInt(g['schedule_id']) == schedId) {
          gradeId = asInt(g['id']);
          break;
        }
        if (teamId != null &&
            asInt(g['team_id']) == teamId &&
            stageLabel.isNotEmpty &&
            g['stage_label']?.toString().toLowerCase() ==
                stageLabel.toLowerCase()) {
          gradeId = asInt(g['id']);
          break;
        }
      }
    }

    final isLocked = (schedule['grade_status']?.toString() ?? '') == 'published' ||
        (schedule['status']?.toString() ?? '').toLowerCase() == 'completed' ||
        (schedule['status']?.toString() ?? '').toLowerCase() == 'done';

    if (gradeId != null) {
      if (isAdmin) {
        context.push('${AdminRoutes.gradeDetail(gradeId)}?locked=${isLocked ? 1 : 0}');
        return;
      } else if (isFaculty) {
        context.push('${FacultyRoutes.gradeDetail(gradeId)}?locked=${isLocked ? 1 : 0}');
        return;
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GradeCenterTeamDetailScreen(
              gradeId: gradeId!,
              isLocked: isLocked,
              onBack: () => Navigator.pop(context),
            ),
          ),
        );
        return;
      }
    }

    if (isAdmin) {
      context.go(AdminRoutes.gradeCenter);
    } else if (isFaculty) {
      context.go(FacultyRoutes.gradeCenter);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GradeCenterScreen()),
      );
    }
  }

  Widget _evaluationChip(Map<String, dynamic> schedule) {
    final status = (schedule['display_status']?.toString() ??
            schedule['status']?.toString() ??
            '')
        .toLowerCase();
    final isDone = ['done', 'completed'].contains(status);

    final Color bg = isDone ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC);
    final Color fg = isDone ? const Color(0xFFB45309) : DefensysTokens.textSecondary;
    final Color border =
        isDone ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0);
    final String label = isDone ? 'View Evaluation' : 'Evaluation & Grades';

    return InkWell(
      onTap: () => _openEvaluationAndGrades(schedule),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isDone ? Icons.star_rounded : Icons.grading_rounded,
              size: 13,
              color: fg,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.arrow_forward_ios_rounded, size: 9, color: fg),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final int flex;

  const _HeaderCell(this.text, {required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: DefensysTokens.fontFamilyInter,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: DefensysTokens.steelGrey,
          ),
        ),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  final Widget child;
  final int flex;

  const _BodyCell({required this.child, required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}

class _SessionGroup {
  final String key;
  final String stageLabel;
  final String scheduledDate;
  final String room;
  final String panelNames;
  final String documenterName;
  final String scope;
  final List<Map<String, dynamic>> schedules;

  _SessionGroup({
    required this.key,
    required this.stageLabel,
    required this.scheduledDate,
    required this.room,
    required this.panelNames,
    required this.documenterName,
    required this.scope,
    required this.schedules,
  });
}

