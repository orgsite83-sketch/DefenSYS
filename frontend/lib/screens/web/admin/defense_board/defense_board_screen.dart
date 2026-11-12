import 'package:defensys/navigation/workspace_http_context.dart';
import 'package:defensys/theme/program_colors.dart';
import 'package:defensys/widgets/export/report_export_menu.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../widgets/shadcn/defensys_action_menu.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import 'components/schedule_operations_dialog.dart';
import 'components/schedule_group_actions.dart';
import 'components/session_evaluator_access_dialog.dart';
import 'components/schedule_manager_dialog.dart';
import '../grade_center/grade_correction_dialog.dart';
import 'package:flutter/material.dart';
import '../../../../models/defense_workflow_labels.dart';
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
import '../defense_scheduler/dialogs/panelist_pool_dialog.dart';
import '../defense_scheduler/dialogs/team_deliverables_review_dialog.dart';
import '../defense_scheduler/models/schedule_import_models.dart';
import '../grade_center/grade_center_team_detail_screen.dart';
import '../widgets/defensys_admin_shell.dart';
import '../../../../widgets/feedback/empty_state.dart';
import '../../../../widgets/feedback/defensys_skeleton.dart';
import '../../../../widgets/table/defensys_segmented_control.dart';
import '../../../../widgets/minutes/minutes_pdf_dialog.dart';
import '../../../../notifications/minutes_notification_route.dart';
import '../../../../utils/import/schedule_import_draft.dart';
import '../../../../utils/scheduler/defense_scheduler_draft.dart';
import '../../../../utils/scheduler/session_activity.dart';
import '../../../../utils/scheduler/session_period.dart';
import 'components/defense_schedule_bulk_import_view.dart';

int _defenseAttempt(Map<String, dynamic> schedule) {
  final assessment = schedule['assessment'];
  final attempt = assessment is Map ? asInt(assessment['attempt_count']) : null;
  return attempt != null && attempt > 0 ? attempt : 1;
}

class DefenseBoardScreen extends ConsumerStatefulWidget {
  const DefenseBoardScreen({super.key, this.initialBulkImport = false});

  final bool initialBulkImport;

  @override
  ConsumerState<DefenseBoardScreen> createState() => _DefenseBoardScreenState();
}

class _DefenseBoardScreenState extends ConsumerState<DefenseBoardScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showScheduler = false;
  String? _schedulerScope;
  int? _schedulerStageId;
  String? _schedulerEventName;

  // Readiness State
  int? _selectedReadinessStageId;
  String? _selectedReadinessEventName;
  bool _isSendingReminder = false;
  bool _showMoreFilters = false;
  bool _showOpenSessionsInfo = false;
  bool _assignmentsView = false;

  // Session Accordion & Pagination State
  final Set<String> _collapsedSessions = {};
  final Map<String, int> _sessionPages = {};
  String? _plannerDate;
  String? _plannerSessionId;
  String? _plannerScope;
  String? _lastPlannerRoute;
  bool _plannerInitialized = false;
  bool _hasImportDraft = false;
  bool _hasSchedulerDraft = false;
  ScheduleImportDraft? _savedImportDraft;
  bool _showScheduleBulkImport = false;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _surfaceColor =>
      _isDark ? DefensysTokens.mistSurface : Colors.white;
  Color get _panelBgColor =>
      _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC);
  Color get _borderColor =>
      _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0);
  Color get _textPrimaryColor =>
      _isDark ? DefensysTokens.textPrimaryDark : AppColors.textPrimary;
  Color get _textSecondaryColor =>
      _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary;

  @override
  void initState() {
    super.initState();
    if (widget.initialBulkImport) {
      _showScheduleBulkImport = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _plannerInitialized = true;
      ref
          .read(defenseBoardProvider.notifier)
          .fetchBoard(
            scope: _plannerDate != null
                ? (_plannerScope ?? '')
                : (_plannerScope ??
                      _effectiveBoardScope(ref.read(defenseBoardProvider))),
            stage: _plannerDate == null ? null : '',
            status: _plannerDate == null ? null : '',
            search: _plannerDate == null ? null : '',
          );
      ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
      _checkImportDraft();
      _checkSchedulerDraft();
    });
  }

  @override
  void didUpdateWidget(covariant DefenseBoardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialBulkImport != oldWidget.initialBulkImport) {
      _showScheduleBulkImport = widget.initialBulkImport;
    }
  }

  int? _lastPanelistRequest;
  int? _lastMinutesRequest;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (GoRouter.maybeOf(context) == null) return;
    final uri = GoRouterState.of(context).uri;
    final plannerKey =
        '${uri.queryParameters['date'] ?? ''}|${uri.queryParameters['session'] ?? ''}|${uri.queryParameters['scope'] ?? ''}';
    if (plannerKey != _lastPlannerRoute) {
      final wasPlannerFocused = _plannerDate != null;
      _lastPlannerRoute = plannerKey;
      final rawDate = uri.queryParameters['date'];
      _plannerDate = rawDate != null && DateTime.tryParse(rawDate) != null
          ? rawDate
          : null;
      _plannerSessionId = _plannerDate == null
          ? null
          : uri.queryParameters['session'];
      final scope = uri.queryParameters['scope'];
      _plannerScope = scope == 'pit' || scope == 'capstone' ? scope : null;
      if (_plannerInitialized) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref
              .read(defenseBoardActiveViewProvider.notifier)
              .setView(DefenseOperationsView.schedules);
          // Returning from another branch must not reset retained board filters.
          if (_plannerDate == null &&
              !wasPlannerFocused &&
              (_plannerScope == null ||
                  _plannerScope ==
                      _effectiveBoardScope(ref.read(defenseBoardProvider)))) {
            return;
          }
          ref
              .read(defenseBoardProvider.notifier)
              .fetchBoard(
                scope: _plannerScope ?? '',
                stage: '',
                status: '',
                search: '',
                adviser: '',
                section: '',
              );
        });
      }
    }
    final minutesId = int.tryParse(uri.queryParameters['minutes'] ?? '');
    if (minutesId != _lastMinutesRequest) {
      _lastMinutesRequest = minutesId;
      if (minutesId != null && minutesId > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _openNotificationMinutes(minutesId, uri),
        );
      }
    }
    final id = int.tryParse(uri.queryParameters['panelistRequest'] ?? '');
    if (id == _lastPanelistRequest) return;
    _lastPanelistRequest = id;
    if (id == null || id < 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await PanelistPoolDialog.show(context, initialRequestId: id);
      if (mounted &&
          GoRouterState.of(context).uri.queryParameters['panelistRequest'] ==
              '$id') {
        context.go('/faculty/defense-board');
      }
    });
  }

  Future<void> _checkImportDraft() async {
    final user = ref.read(authProvider).user;
    final isAdmin = isAdminWorkspace(user);
    final isPitLead = user?['is_pit_lead'] == true;
    if (!isAdmin && !isPitLead) return;
    final scope = _effectiveBoardScope(ref.read(defenseBoardProvider));
    if (!_canScheduleScope(scope)) return;
    final draft = await loadScheduleImportDraft(
      scope: scope,
      semesterId: asInt(
        ref.read(defenseSchedulerProvider).activeSemester?['id'],
      ),
    );
    if (mounted &&
        scope == _effectiveBoardScope(ref.read(defenseBoardProvider))) {
      setState(() {
        _savedImportDraft = (draft != null && draft.parsed.rows.isNotEmpty)
            ? draft
            : null;
        _hasImportDraft = _savedImportDraft != null;
      });
    }
  }

  Future<void> _checkSchedulerDraft() async {
    final user = ref.read(authProvider).user;
    final isAdmin = isAdminWorkspace(user);
    final isPitLead = user?['is_pit_lead'] == true;
    if (!isAdmin && !isPitLead) return;
    final scope = _effectiveBoardScope(ref.read(defenseBoardProvider));
    if (!_canScheduleScope(scope)) return;
    final draft = await loadDefenseSchedulerDraft(
      scope: scope,
      semesterId: asInt(
        ref.read(defenseSchedulerProvider).activeSemester?['id'],
      ),
    );
    if (mounted &&
        scope == _effectiveBoardScope(ref.read(defenseBoardProvider))) {
      setState(() {
        _hasSchedulerDraft = draft != null && draft.hasContent;
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
    if (_showScheduleBulkImport) {
      final user = ref.watch(authProvider).user;
      final isAdmin = isAdminWorkspace(user);
      final effectiveScope = isAdmin ? 'capstone' : 'pit';

      return DefenseScheduleBulkImportView(
        scope: effectiveScope,
        initialStageId: _schedulerStageId ?? _selectedReadinessStageId,
        initialEventName: _schedulerEventName,
        onBack: () {
          setState(() {
            _showScheduleBulkImport = false;
          });
          _checkImportDraft();
          ref.read(defenseBoardProvider.notifier).fetchBoard();
          ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
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
          _checkSchedulerDraft();
          ref.read(defenseBoardProvider.notifier).fetchBoard();
          ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
        },
      );
    }

    final state = ref.watch(defenseBoardProvider);
    final schedState = ref.watch(defenseSchedulerProvider);
    final currentView = ref.watch(defenseBoardActiveViewProvider);
    final effectiveReadinessScope = _effectiveBoardScope(state);

    // Determine active stage/event name
    String activeStageName = '';
    if (effectiveReadinessScope == 'capstone') {
      if (schedState.defenseStages.isNotEmpty) {
        final stageExists =
            _selectedReadinessStageId != null &&
            schedState.defenseStages.any(
              (stg) => asInt(stg['id']) == _selectedReadinessStageId,
            );
        if (!stageExists) {
          final firstWithReady = schedState.defenseStages.firstWhere((stg) {
            final label = stg['label']?.toString() ?? '';
            return teamsForScope(
              schedState,
              'capstone',
            ).any((t) => isTeamStageReady(t, label));
          }, orElse: () => schedState.defenseStages.first);
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
        final eventExists =
            _selectedReadinessEventName != null &&
            _selectedReadinessEventName!.isNotEmpty &&
            schedState.pitEvents.any(
              (evt) =>
                  (evt['event_name']?.toString() ?? '').toLowerCase() ==
                  _selectedReadinessEventName!.toLowerCase(),
            );
        if (!eventExists) {
          final firstWithReady = schedState.pitEvents.firstWhere((evt) {
            final name = evt['event_name']?.toString() ?? '';
            return teamsForScope(
              schedState,
              'pit',
            ).any((t) => isTeamStageReady(t, name));
          }, orElse: () => schedState.pitEvents.first);
          _selectedReadinessEventName =
              firstWithReady['event_name']?.toString() ?? '';
        }
        activeStageName = _selectedReadinessEventName ?? '';
      }
    }

    final scopeTeams = teamsForScope(schedState, effectiveReadinessScope);
    final readyTeamsForActiveStage = scopeTeams
        .where(
          (t) =>
              activeStageName.isNotEmpty &&
              isTeamStageReady(t, activeStageName),
        )
        .toList();
    final completedTeamsForActiveStage = scopeTeams
        .where(
          (t) =>
              activeStageName.isNotEmpty &&
              isTeamStageCompleted(t, activeStageName),
        )
        .toList();
    final pendingTeamsForActiveStage = scopeTeams
        .where(
          (t) =>
              activeStageName.isNotEmpty &&
              getTeamStageStatus(t, activeStageName) == 'pending',
        )
        .toList();

    final totalReadyAcrossAllStages = scopeTeams.where((t) {
      final readyStage = t['ready_for_stage']?.toString() ?? '';
      return readyStage.isNotEmpty && isTeamStageReady(t, readyStage);
    }).length;

    final cp = MediaQuery.sizeOf(context).width < 600
        ? const EdgeInsets.fromLTRB(16, 20, 16, 24)
        : DefensysUi.contentPadding;

    return DefensysShadcnScope(
      child: Scaffold(
        backgroundColor: _isDark
            ? DefensysTokens.mistBackground
            : DefensysUi.bgLight,
        body: RefreshIndicator(
          color: AppColors.maroon,
          onRefresh: () async {
            await Future.wait([
              ref.read(defenseBoardProvider.notifier).fetchBoard(),
              ref.read(defenseSchedulerProvider.notifier).fetchSchedules(),
            ]);
          },
          child: CustomScrollView(
            key: const PageStorageKey('defense-operations-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(cp.left, cp.top, cp.right, 16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(
                        state,
                        effectiveReadinessScope,
                        readyTeamsForActiveStage.length,
                        currentView,
                      ),
                      if (_savedImportDraft != null) ...[
                        const SizedBox(height: 16),
                        _buildDraftResumeBanner(),
                      ],
                      const SizedBox(height: 20),
                      if (_canSwitchBoardScope &&
                          !(_plannerDate != null && _plannerScope == null)) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _buildScopeTabs(state),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buildViewSwitcher(scopeTeams, currentView),
                      const SizedBox(height: 20),
                      if (currentView == DefenseOperationsView.schedules) ...[
                        _buildReadinessCalloutBanner(totalReadyAcrossAllStages),
                      ] else ...[
                        _buildReadinessSummary(
                          scopeTeams.length,
                          readyTeamsForActiveStage.length,
                          completedTeamsForActiveStage.length,
                          pendingTeamsForActiveStage.length,
                        ),
                        if (schedState.error != null) ...[
                          const SizedBox(height: 12),
                          _buildLoadError(
                            schedState.error!,
                            () => ref
                                .read(defenseSchedulerProvider.notifier)
                                .fetchSchedules(),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              if (currentView == DefenseOperationsView.schedules) ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(cp.left, 0, cp.right, cp.bottom),
                  sliver: SliverToBoxAdapter(
                    child: _buildSessionsWorkspace(state),
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
                            title: 'Deliverables & readiness',
                            subtitle:
                                'Review requirements and endorsements before scheduling.',
                            stageSelector: _buildStagePillsRow(
                              schedState,
                              effectiveReadinessScope,
                              activeStageName,
                            ),
                            headerAction: null,
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
      ),
    );
  }

  Widget _buildViewSwitcher(
    List<Map<String, dynamic>> readinessTeams,
    DefenseOperationsView currentView,
  ) {
    final ready = readinessTeams.where((team) {
      final stage = team['ready_for_stage']?.toString() ?? '';
      return stage.isNotEmpty && isTeamStageReady(team, stage);
    }).length;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Wrap(
        spacing: 20,
        children: [
          for (final view in DefenseOperationsView.values)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: currentView == view
                        ? DefensysTokens.maroonOf(context)
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Semantics(
                selected: currentView == view,
                child: ShadButton.ghost(
                  key: ValueKey('board-view-${view.name}'),
                  foregroundColor: currentView == view
                      ? DefensysTokens.maroonTextOf(context)
                      : _textSecondaryColor,
                  onPressed: () => ref
                      .read(defenseBoardActiveViewProvider.notifier)
                      .setView(view),
                  child: Text(
                    view == DefenseOperationsView.schedules
                        ? 'Schedules'
                        : 'Readiness${ready > 0 ? ' · $ready ready' : ''}',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDraftResumeBanner() {
    if (_savedImportDraft == null) return const SizedBox.shrink();
    final rowCount = _savedImportDraft!.parsed.rows.length;
    final timeStr = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(_savedImportDraft!.savedAt));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _isDark
            ? const Color(0xFF1E3A8A).withValues(alpha: 0.12)
            : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isDark
              ? const Color(0xFF2563EB).withValues(alpha: 0.5)
              : const Color(0xFF93C5FD),
        ),
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
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _isDark
                    ? const Color(0xFF93C5FD)
                    : const Color(0xFF1E3A8A),
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
              final scope = _effectiveBoardScope(
                ref.read(defenseBoardProvider),
              );
              await clearScheduleImportDraft(
                scope: scope,
                semesterId: asInt(
                  ref.read(defenseSchedulerProvider).activeSemester?['id'],
                ),
              );
              await _checkImportDraft();
              if (mounted) {
                showInfoToast(context, 'Schedule import draft discarded.');
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: BorderSide(
                color: _isDark
                    ? const Color(0xFF991B1B)
                    : const Color(0xFFFCA5A5),
              ),
              backgroundColor: _isDark
                  ? DefensysTokens.mistSurface
                  : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 15,
              color: Color(0xFFDC2626),
            ),
            label: const Text(
              'Discard',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFFDC2626),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadinessCalloutBanner(int readyCount) {
    if (readyCount <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$readyCount ${readyCount == 1 ? 'team' : 'teams'} ready to schedule',
            style: DefensysTokens.subtitle.copyWith(color: _textSecondaryColor),
          ),
          ShadButton.link(
            onPressed: () => ref
                .read(defenseBoardActiveViewProvider.notifier)
                .setView(DefenseOperationsView.readiness),
            child: const Text('Review readiness'),
          ),
        ],
      ),
    );
  }

  Widget _buildStagePillsRow(
    DefenseSchedulerState schedState,
    String scope,
    String activeStageName,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _isDark
                ? DefensysTokens.mistSurface
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: _textSecondaryColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    scope == 'capstone'
                        ? 'Target Capstone Defense Milestone:'
                        : 'Target PIT Event:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _textSecondaryColor,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (scope == 'capstone') ...[
                if (schedState.defenseStages.isEmpty)
                  Text(
                    'No defense stages configured. Go to Defense Stages Setup to create milestones.',
                    style: TextStyle(fontSize: 12, color: _textSecondaryColor),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: schedState.defenseStages.map((stage) {
                      final stageId = asInt(stage['id']);
                      final stageLabel = stage['label']?.toString() ?? '';
                      final isSelected =
                          stageId == _selectedReadinessStageId ||
                          (stageId == null && stageLabel == activeStageName);

                      final readyCountForStage = teamsForScope(
                        schedState,
                        'capstone',
                      ).where((t) => isTeamStageReady(t, stageLabel)).length;
                      final completedCountForStage =
                          teamsForScope(schedState, 'capstone')
                              .where((t) => isTeamStageCompleted(t, stageLabel))
                              .length;
                      final pendingCountForStage =
                          teamsForScope(schedState, 'capstone')
                              .where(
                                (t) =>
                                    getTeamStageStatus(t, stageLabel) ==
                                    'pending',
                              )
                              .length;
                      final stageTeamCount = teamsForScope(
                        schedState,
                        'capstone',
                      ).length;
                      final awaitingCompletionCount =
                          teamsForScope(schedState, 'capstone')
                              .where(
                                (t) =>
                                    getTeamStageStatus(t, stageLabel) ==
                                    'awaiting_completion',
                              )
                              .length;

                      String badgeText;
                      Color badgeColor;
                      Color badgeTextColor;

                      if (readyCountForStage > 0) {
                        badgeText = '$readyCountForStage ready';
                        badgeColor = _isDark
                            ? const Color(0xFF064E3B).withValues(alpha: 0.5)
                            : const Color(0xFFDEF7EC);
                        badgeTextColor = _isDark
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFF03543F);
                      } else if (stageTeamCount > 0 &&
                          completedCountForStage == stageTeamCount) {
                        badgeText = 'Complete';
                        badgeColor = _isDark
                            ? const Color(0xFF064E3B).withValues(alpha: 0.5)
                            : const Color(0xFFDEF7EC);
                        badgeTextColor = _isDark
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFF03543F);
                      } else {
                        badgeText = awaitingCompletionCount > 0
                            ? '$awaitingCompletionCount awaiting completion'
                            : pendingCountForStage > 0
                            ? '$pendingCountForStage pending'
                            : '${stageTeamCount - completedCountForStage} in progress';
                        badgeColor = _isDark
                            ? const Color(0xFF78350F).withValues(alpha: 0.5)
                            : const Color(0xFFFEF3C7);
                        badgeTextColor = _isDark
                            ? const Color(0xFFFDE68A)
                            : const Color(0xFF92400E);
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
                  Text(
                    'No PIT events configured for this term.',
                    style: TextStyle(fontSize: 12, color: _textSecondaryColor),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: schedState.pitEvents.map((evt) {
                      final eventName = evt['event_name']?.toString() ?? '';
                      final isSelected = eventName == activeStageName;
                      final readyCountForEvent = teamsForScope(
                        schedState,
                        'pit',
                      ).where((t) => isTeamStageReady(t, eventName)).length;
                      final completedCountForEvent = teamsForScope(
                        schedState,
                        'pit',
                      ).where((t) => isTeamStageCompleted(t, eventName)).length;
                      final pendingCountForEvent =
                          teamsForScope(schedState, 'pit')
                              .where(
                                (t) =>
                                    getTeamStageStatus(t, eventName) ==
                                    'pending',
                              )
                              .length;
                      final eventTeamCount = teamsForScope(
                        schedState,
                        'pit',
                      ).length;

                      String badgeText;
                      Color badgeColor;
                      Color badgeTextColor;

                      if (readyCountForEvent > 0) {
                        badgeText = '$readyCountForEvent ready';
                        badgeColor = _isDark
                            ? const Color(0xFF064E3B).withValues(alpha: 0.5)
                            : const Color(0xFFDEF7EC);
                        badgeTextColor = _isDark
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFF03543F);
                      } else if (eventTeamCount > 0 &&
                          completedCountForEvent == eventTeamCount) {
                        badgeText = 'Complete';
                        badgeColor = _isDark
                            ? const Color(0xFF064E3B).withValues(alpha: 0.5)
                            : const Color(0xFFDEF7EC);
                        badgeTextColor = _isDark
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFF03543F);
                      } else {
                        badgeText = pendingCountForEvent > 0
                            ? '$pendingCountForEvent pending'
                            : '${eventTeamCount - completedCountForEvent} in progress';
                        badgeColor = _isDark
                            ? const Color(0xFF78350F).withValues(alpha: 0.5)
                            : const Color(0xFFFEF3C7);
                        badgeTextColor = _isDark
                            ? const Color(0xFFFDE68A)
                            : const Color(0xFF92400E);
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
          color: isSelected
              ? AppColors.maroon
              : (_isDark ? DefensysTokens.mistInputFill : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.maroon : _borderColor,
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
                color: isSelected ? Colors.white : _textPrimaryColor,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.2)
                    : badgeColor,
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

  Widget _buildReadinessSummary(
    int totalScopeTeams,
    int readyCount,
    int completedCount,
    int pendingCount,
  ) => Wrap(
    spacing: 24,
    runSpacing: 8,
    children: [
      Text(
        '$totalScopeTeams ${totalScopeTeams == 1 ? 'team' : 'teams'}',
        style: DefensysTokens.body.copyWith(color: _textPrimaryColor),
      ),
      Text(
        '$readyCount ready to schedule',
        style: DefensysTokens.subtitle.copyWith(color: _textSecondaryColor),
      ),
      Text(
        '$completedCount completed this stage',
        style: DefensysTokens.subtitle.copyWith(color: _textSecondaryColor),
      ),
      Text(
        '$pendingCount pending',
        style: DefensysTokens.subtitle.copyWith(color: _textSecondaryColor),
      ),
    ],
  );

  Widget _buildHeader(
    DefenseBoardState state,
    String effectiveReadinessScope,
    int readyCount,
    DefenseOperationsView currentView,
  ) {
    final canSchedule = _canScheduleScope(effectiveReadinessScope);
    final readiness = currentView == DefenseOperationsView.readiness;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Defense Operations',
          style: DefensysTokens.pageTitle.copyWith(color: _textPrimaryColor),
        ),
        const SizedBox(height: 6),
        Text(
          state.activeSemester?['display_name']?.toString() ??
              'Defense schedules and readiness',
          style: DefensysTokens.subtitle.copyWith(color: _textSecondaryColor),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!readiness)
          ReportExportMenu(
            reportId: 'defense-schedules',
            params: {
              if (state.scope.isNotEmpty) 'scope': state.scope,
              if (state.stage.isNotEmpty) 'stage': state.stage,
              if (state.status.isNotEmpty) 'status': state.status,
              if (state.adviser.isNotEmpty) 'adviser': state.adviser,
              if (state.section.isNotEmpty) 'section': state.section,
              if (state.search.isNotEmpty) 'search': state.search,
            },
          ),
        if (canSchedule) ...[
          DefensysActionMenu(
            label: 'Scheduling options',
            triggerLabel: 'Scheduling options',
            triggerIcon: LucideIcons.chevronDown,
            enabled: !state.isSaving,
            items: [
              DefensysMenuItem(
                label: 'Manual schedule',
                icon: LucideIcons.calendarDays,
                onPressed: _openManualScheduleDialog,
              ),
              DefensysMenuItem(
                label: _hasImportDraft
                    ? 'Resume import draft'
                    : 'Import schedule',
                icon: LucideIcons.upload,
                onPressed: _openImportScheduleDialog,
              ),
            ],
          ),
          ShadButton(
            key: const ValueKey('board-generate-schedule'),
            enabled: !state.isSaving,
            backgroundColor: DefensysTokens.maroonOf(context),
            hoverBackgroundColor: DefensysTokens.maroonOf(
              context,
            ).withValues(alpha: .9),
            foregroundColor: Colors.white,
            leading: const Icon(LucideIcons.calendarPlus, size: 16),
            onPressed: () => _openScheduler(
              scope: effectiveReadinessScope,
              stageId: readiness ? _selectedReadinessStageId : null,
              eventName: readiness ? _selectedReadinessEventName : null,
            ),
            child: Text(
              readiness && readyCount > 0
                  ? 'Schedule $readyCount ready ${readyCount == 1 ? 'team' : 'teams'}'
                  : _hasSchedulerDraft
                  ? 'Resume schedule draft'
                  : 'Generate schedule',
            ),
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 800
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title),
                const SizedBox(width: 16),
                actions,
              ],
            ),
    );
  }

  Widget _buildSessionsWorkspace(DefenseBoardState state) {
    return Container(
      key: const ValueKey('board-sessions-workspace'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: Border.all(color: _borderColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final title = Text(
                      'Defense sessions',
                      style: DefensysTokens.sectionTitle.copyWith(
                        color: _textPrimaryColor,
                      ),
                    );
                    return constraints.maxWidth < 520
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              title,
                              const SizedBox(height: 10),
                              _buildManageSchedulesButton(state),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: title),
                              _buildManageSchedulesButton(state),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 8),
                _buildDefenseSummary(state),
                const SizedBox(height: 12),
                _buildFilterBar(state),
                if (_plannerDate != null) _buildPlannerContext(),
                if (state.error != null) ...[
                  const SizedBox(height: 12),
                  _buildLoadError(
                    state.error!,
                    () => ref.read(defenseBoardProvider.notifier).fetchBoard(),
                  ),
                ],
              ],
            ),
          ),
          Container(
            key: const ValueKey('board-sessions-body'),
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600 ? 10 : 16,
            ),
            decoration: BoxDecoration(
              color: _surfaceColor,
              border: Border(top: BorderSide(color: _borderColor)),
            ),
            child: state.isLoading
                ? _buildLoadingState()
                : _plannerSchedules(state.schedules).isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: _buildEmptyBoard(),
                  )
                : _buildBoardSection(state),
          ),
        ],
      ),
    );
  }

  Map<String, int> _progressCounts(List<dynamic> schedules) {
    final counts = <String, int>{};
    for (final schedule in schedules) {
      final status =
          (schedule['display_status'] ?? schedule['status'] ?? 'scheduled')
              .toString();
      counts.update(status, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  Widget _buildDefenseSummary(DefenseBoardState state) {
    if (state.isLoading) {
      return Text(
        'Loading defenses…',
        style: DefensysTokens.subtitle.copyWith(color: _textSecondaryColor),
      );
    }
    if (state.error != null && state.schedules.isEmpty) {
      return const SizedBox.shrink();
    }
    final schedules = _plannerSchedules(state.schedules);
    final counts = _progressCounts(schedules);
    final total = state.counts['scope_total'];
    final count = schedules.length;
    final sessions = _groupSchedules(schedules).length;
    final description = total is num && total > count
        ? 'Showing $count of $total ${total == 1 ? 'defense' : 'defenses'}'
        : '$count ${count == 1 ? 'defense' : 'defenses'} shown';
    final pending = counts['pending_post_defense'] ?? 0;
    final evaluation =
        (counts['evaluating'] ?? 0) +
        (counts['ongoing'] ?? 0) +
        (counts['awaiting_evaluation'] ?? 0);
    final decisions =
        (counts['awaiting_verdict'] ?? 0) +
        (counts['awaiting_concept_selection'] ?? 0);
    final followUp = [
      'grading_incomplete',
      'awaiting_completion',
      'revisions_pending',
      'changes_requested',
      'needs_review',
      'redefense_required',
    ].fold<int>(0, (sum, status) => sum + (counts[status] ?? 0));
    final information = [
      if (pending > 0)
        '$pending ${pending == 1 ? 'defense has' : 'defenses have'} post-defense requirements remaining',
      if (evaluation > 0)
        '$evaluation ${evaluation == 1 ? 'defense needs' : 'defenses need'} panel evaluation',
      if (decisions > 0)
        '$decisions ${decisions == 1 ? 'defense awaits' : 'defenses await'} a decision',
      if (followUp > 0)
        '$followUp ${followUp == 1 ? 'defense needs' : 'defenses need'} follow-up',
    ];
    return Column(
      key: const ValueKey('board-defense-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$sessions ${sessions == 1 ? 'session' : 'sessions'} · $description',
          style: DefensysTokens.subtitle.copyWith(color: _textSecondaryColor),
        ),
        if (information.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 15, color: _textSecondaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${information.join('; ')}.',
                  style: DefensysTokens.subtitle.copyWith(
                    color: _textSecondaryColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildFilterBar(DefenseBoardState state) {
    final isPit = _effectiveBoardScope(state) == 'pit';
    final moreCount = [
      state.adviser,
      state.section,
    ].where((value) => value.isNotEmpty).length;
    final hasFilters = [
      state.search,
      state.stage,
      state.status,
      state.adviser,
      state.section,
    ].any((value) => value.isNotEmpty);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final narrow = constraints.maxWidth < 520;
        final fieldWidth = narrow ? constraints.maxWidth : 220.0;
        final filters = Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildStageOrEventDropdown(state, fieldWidth),
            _buildStatusDropdown(state, fieldWidth),
            ShadButton.outline(
              key: const ValueKey('board-more-filters'),
              leading: const Icon(LucideIcons.slidersHorizontal, size: 16),
              trailing: Icon(
                _showMoreFilters
                    ? LucideIcons.chevronUp
                    : LucideIcons.chevronDown,
                size: 14,
              ),
              onPressed: () =>
                  setState(() => _showMoreFilters = !_showMoreFilters),
              child: Text(
                'More filters${moreCount > 0 ? ' ($moreCount)' : ''}',
              ),
            ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact) ...[
              _buildSearchField(state, double.infinity),
              const SizedBox(height: 10),
              filters,
            ] else
              Row(
                children: [
                  Expanded(child: _buildSearchField(state, null)),
                  const SizedBox(width: 10),
                  filters,
                ],
              ),
            if (_showMoreFilters) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: isPit
                    ? _buildSectionDropdown(
                        state,
                        narrow ? constraints.maxWidth : 300,
                      )
                    : _buildAdviserDropdown(
                        state,
                        narrow ? constraints.maxWidth : 300,
                      ),
              ),
            ],
            if (hasFilters) const SizedBox(height: 12),
            if (hasFilters)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (hasFilters)
                    ShadButton.ghost(
                      onPressed: () {
                        _searchController.clear();
                        ref
                            .read(defenseBoardProvider.notifier)
                            .fetchBoard(
                              search: '',
                              stage: '',
                              status: '',
                              adviser: '',
                              section: '',
                            );
                      },
                      child: const Text('Clear filters'),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildFilterSelect({
    required String label,
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onChanged,
    double? width,
  }) => SizedBox(
    width: width,
    child: LayoutBuilder(
      builder: (context, constraints) => Semantics(
        label: label,
        child: ShadSelect<String>(
          key: ValueKey('board-filter-$label-$value'),
          initialValue: options.containsKey(value) ? value : '',
          minWidth: constraints.maxWidth,
          maxWidth: constraints.maxWidth,
          maxHeight: 280,
          options: options.entries.map(
            (entry) => ShadOption(
              value: entry.key,
              child: Text(
                entry.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          selectedOptionBuilder: (context, selected) => Text(
            options[selected] ?? label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onChanged: (selected) {
            if (selected != null) onChanged(selected);
          },
        ),
      ),
    ),
  );

  Widget _buildManageSchedulesButton(DefenseBoardState state) {
    final user = ref.read(authProvider).user;
    if (!(isAdminWorkspace(user) || user?['is_pit_lead'] == true)) {
      return const SizedBox.shrink();
    }
    return DefensysShadcnScope(
      child: ShadButton.outline(
        enabled: !state.isSaving,
        leading: const Icon(LucideIcons.slidersHorizontal, size: 16),
        onPressed: () => showScheduleManager(
          context,
          defenseType: _effectiveBoardScope(state),
        ),
        child: const Text('Manage schedules'),
      ),
    );
  }

  bool get _canSwitchBoardScope {
    final user = ref.read(authProvider).user;
    return isAdminWorkspace(user);
  }

  String _effectiveBoardScope(DefenseBoardState state) {
    final user = ref.read(authProvider).user;
    final isAdmin = isAdminWorkspace(user);
    if (!isAdmin && user?['is_pit_lead'] == true) return 'pit';
    return state.scope == 'pit' ? 'pit' : 'capstone';
  }

  bool _canScheduleScope(String scope) {
    final user = ref.read(authProvider).user;
    final isAdmin = isAdminWorkspace(user);
    return scope == 'capstone'
        ? isAdmin
        : !isAdmin && user?['is_pit_lead'] == true;
  }

  Widget _buildScopeTabs(DefenseBoardState state) {
    return DefensysSegmentedControl<String>(
      value: _effectiveBoardScope(state),
      height: 50 + (MediaQuery.textScalerOf(context).scale(13) - 13) * 2,
      items: const [
        DefensysSegmentItem(
          value: 'capstone',
          label: 'Capstone',
          icon: Icons.school_rounded,
        ),
        DefensysSegmentItem(
          value: 'pit',
          label: 'PIT',
          icon: Icons.alt_route_rounded,
        ),
      ],
      onChanged: (scope) {
        _searchController.clear();
        setState(() {
          _savedImportDraft = null;
          _hasImportDraft = false;
          _hasSchedulerDraft = false;
          _showMoreFilters = false;
        });
        ref
            .read(defenseBoardProvider.notifier)
            .fetchBoard(
              scope: scope,
              stage: '',
              status: '',
              adviser: '',
              section: '',
              search: '',
            );
        _checkImportDraft();
        _checkSchedulerDraft();
      },
    );
  }

  Widget _buildAdviserDropdown(DefenseBoardState state, double? width) {
    final options = <String, String>{'': 'All advisers'};
    for (final adviser in state.advisers) {
      final id = adviser['id']?.toString() ?? '';
      final name = adviser['name']?.toString() ?? '';
      if (id.isNotEmpty && name.isNotEmpty) options[id] = name;
    }
    return _buildFilterSelect(
      label: 'Adviser',
      value: state.adviser,
      width: width,
      options: options,
      onChanged: (value) =>
          ref.read(defenseBoardProvider.notifier).fetchBoard(adviser: value),
    );
  }

  Widget _buildSectionDropdown(DefenseBoardState state, double? width) {
    final options = <String, String>{'': 'All sections'};
    for (final section in state.sections) {
      final name = section['name']?.toString() ?? '';
      if (name.isNotEmpty) options[name] = name;
    }
    return _buildFilterSelect(
      label: 'Section',
      value: state.section,
      width: width,
      options: options,
      onChanged: (value) =>
          ref.read(defenseBoardProvider.notifier).fetchBoard(section: value),
    );
  }

  Widget _buildCollapseAllButton(DefenseBoardState state) {
    final keys = _groupSchedules(
      _plannerSchedules(state.schedules),
    ).map((group) => group.key).toSet();
    final collapsed = keys.isNotEmpty && _collapsedSessions.containsAll(keys);
    return ShadButton.ghost(
      leading: Icon(
        collapsed ? LucideIcons.chevronsUpDown : LucideIcons.chevronsDownUp,
        size: 16,
      ),
      onPressed: keys.isEmpty
          ? null
          : () => setState(() {
              if (collapsed) {
                _collapsedSessions.removeAll(keys);
              } else {
                _collapsedSessions.addAll(keys);
              }
            }),
      enabled: keys.isNotEmpty,
      child: Text(collapsed ? 'Expand all' : 'Collapse all'),
    );
  }

  Widget _buildStageOrEventDropdown(DefenseBoardState state, double? width) {
    final pit = _effectiveBoardScope(state) == 'pit';
    final scheduler = ref.watch(defenseSchedulerProvider);
    final labels = <String>{
      ...state.stageOptions,
      ...state.schedules
          .where((schedule) => schedule['scope'] == _effectiveBoardScope(state))
          .map((schedule) => schedule['stage_label']?.toString() ?? ''),
      if (pit)
        ...scheduler.pitEvents.map(
          (event) => event['event_name']?.toString() ?? '',
        ),
      if (!pit)
        ...scheduler.defenseStages.map(
          (stage) => stage['label']?.toString() ?? '',
        ),
      if (state.stage.isNotEmpty) state.stage,
    }..remove('');
    final sorted = labels.toList()..sort();
    return _buildFilterSelect(
      label: pit ? 'Event' : 'Stage',
      value: state.stage,
      width: width,
      options: {
        '': pit ? 'All events' : 'All stages',
        for (final label in sorted) label: label,
      },
      onChanged: (value) =>
          ref.read(defenseBoardProvider.notifier).fetchBoard(stage: value),
    );
  }

  Widget _buildStatusDropdown(DefenseBoardState state, double? width) {
    final statuses = <String>{
      ...state.statuses,
      if (state.status.isNotEmpty) state.status,
    };
    return _buildFilterSelect(
      label: 'Status',
      value: state.status,
      width: width,
      options: {
        '': 'All statuses',
        for (final status in statuses) status: _statusLabel(status),
      },
      onChanged: (value) =>
          ref.read(defenseBoardProvider.notifier).fetchBoard(status: value),
    );
  }

  Widget _buildSearchField(DefenseBoardState state, double? width) => SizedBox(
    width: width,
    child: ShadInput(
      controller: _searchController,
      placeholder: const Text('Search teams or rooms'),
      leading: const Icon(LucideIcons.search, size: 16),
      textInputAction: TextInputAction.search,
      trailing: _searchController.text.isEmpty
          ? null
          : ShadButton.ghost(
              width: 28,
              height: 28,
              padding: EdgeInsets.zero,
              onPressed: () {
                _searchController.clear();
                ref.read(defenseBoardProvider.notifier).fetchBoard(search: '');
              },
              child: const Icon(
                LucideIcons.x,
                size: 14,
                semanticLabel: 'Clear search',
              ),
            ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (value) => ref
          .read(defenseBoardProvider.notifier)
          .fetchBoard(search: value.trim()),
    ),
  );

  List<Map<String, dynamic>> _plannerSchedules(
    List<Map<String, dynamic>> schedules,
  ) {
    if (_plannerDate == null) return schedules;
    final canonical = schedules
        .where(
          (schedule) =>
              schedule['session_id']?.toString() == _plannerSessionId ||
              schedule['legacy_session_id']?.toString() == _plannerSessionId,
        )
        .map((schedule) => schedule['session_id']?.toString())
        .toSet();
    return schedules.where((schedule) {
      if (schedule['scheduled_date']?.toString() != _plannerDate) return false;
      if (_plannerSessionId != null &&
          !canonical.contains(schedule['session_id']?.toString())) {
        return false;
      }
      return true;
    }).toList();
  }

  Widget _buildPlannerContext() {
    final day = DateTime.tryParse(_plannerDate!);
    final label = day == null
        ? _plannerDate!
        : '${day.month}/${day.day}/${day.year}';
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 17,
            color: _textSecondaryColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _plannerSessionId == null
                  ? 'Schedule for $label'
                  : 'Session scheduled for $label',
              style: TextStyle(
                color: _textPrimaryColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => context.go(GoRouterState.of(context).uri.path),
            child: const Text('Show all schedules'),
          ),
        ],
      ),
    );
  }

  static const _openSessionsExplanation =
      'Includes defenses with unfinished evaluation or follow-up requirements, even when their scheduled date has passed.';

  Widget _buildTableViewSwitch() => DefensysShadcnScope(
    maroonActions: true,
    neutralActionText: true,
    child: SizedBox(
      width: 370,
      child: ShadTabs<String>(
        key: const ValueKey('board-table-view'),
        value: _assignmentsView ? 'assignments' : 'progress',
        tabBarAlignment: Alignment.centerLeft,
        scrollable: false,
        gap: 0,
        onChanged: (value) =>
            setState(() => _assignmentsView = value == 'assignments'),
        tabs: [
          for (final entry in {
            'progress': 'Progress',
            'assignments': 'Assignments',
          }.entries)
            ShadTab<String>(
              key: ValueKey('board-view-${entry.key}'),
              value: entry.key,
              content: const SizedBox.shrink(),
              child: Flexible(
                child: Text(
                  entry.value,
                  style: const TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _buildBoardSection(DefenseBoardState state) {
    final visibleSchedules = _plannerSchedules(state.schedules);
    if (visibleSchedules.isEmpty) {
      return _buildEmptyBoard();
    }

    final now = DateTime.now();
    final groups = _groupSchedules(visibleSchedules)
      ..sort((a, b) {
        // Within the same automatic plan, show its configured windows in time
        // order. Keep existing activity/import ordering for independent plans.
        final batch = a.schedules.first['batch_id'];
        final activity = sessionActivity(a.schedules, now: now);
        if (batch != null &&
            batch == b.schedules.first['batch_id'] &&
            activity != SessionActivity.past &&
            activity == sessionActivity(b.schedules, now: now) &&
            DefenseSessionWindow.fromJson(a.schedules.first).isConfigured &&
            DefenseSessionWindow.fromJson(b.schedules.first).isConfigured) {
          return '${a.scheduledDate} ${a.schedules.first['session_start_time']}'
              .compareTo(
                '${b.scheduledDate} ${b.schedules.first['session_start_time']}',
              );
        }
        final result = compareSessionActivity(
          a.schedules,
          b.schedules,
          now: now,
        );
        return result != 0 ? result : a.key.compareTo(b.key);
      });
    final sections = <SessionActivity, Map<String, List<_SessionGroup>>>{};
    for (final group in groups) {
      final anchor = group.schedules.first;
      final stageKey =
          '${group.scope}|${anchor['semester_id']}|${group.scope == 'pit' ? group.stageLabel.toLowerCase() : anchor['defense_stage_id'] ?? group.stageLabel}';
      final stages = sections.putIfAbsent(
        sessionActivity(group.schedules, now: now),
        () => {},
      );
      stages.putIfAbsent(stageKey, () => []).add(group);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [_buildTableViewSwitch(), _buildCollapseAllButton(state)],
        ),
        const SizedBox(height: 4),
        for (final section in sections.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        section.key.label,
                        key: ValueKey('session-section-${section.key.name}'),
                        style: DefensysTokens.sectionTitle.copyWith(
                          color: _textPrimaryColor,
                        ),
                      ),
                    ),
                    if (section.key == SessionActivity.active)
                      Tooltip(
                        message: _openSessionsExplanation,
                        child: ShadButton.ghost(
                          key: const ValueKey('board-open-sessions-info'),
                          width: 32,
                          height: 32,
                          padding: EdgeInsets.zero,
                          onPressed: () => setState(
                            () =>
                                _showOpenSessionsInfo = !_showOpenSessionsInfo,
                          ),
                          child: Icon(
                            LucideIcons.info,
                            size: 15,
                            semanticLabel: 'About open sessions',
                            color: _textSecondaryColor,
                          ),
                        ),
                      ),
                  ],
                ),
                if (section.key == SessionActivity.active &&
                    _showOpenSessionsInfo)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _openSessionsExplanation,
                      style: DefensysTokens.subtitle.copyWith(
                        color: _textSecondaryColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (final stageGroups in section.value.values)
            _buildStageSection(stageGroups, state, section.key),
        ],
      ],
    );
  }

  Widget _buildStageSection(
    List<_SessionGroup> groups,
    DefenseBoardState state,
    SessionActivity activity,
  ) {
    final first = groups.first;
    final anchor = first.schedules.first;
    final stageId = first.scope == 'pit'
        ? first.stageLabel.toLowerCase()
        : anchor['defense_stage_id'] ?? first.stageLabel;
    return Container(
      key: ValueKey(
        'board-stage-${activity.name}-${first.scope}-${anchor['semester_id']}-$stageId',
      ),
      margin: const EdgeInsets.only(bottom: DefensysTokens.spacingXl),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(
          color: _isDark
              ? DefensysTokens.mistBorder
              : DefensysTokens.neutralBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _borderColor)),
            ),
            child: StageScheduleHeader(
              padding: const EdgeInsets.symmetric(
                horizontal: DefensysTokens.spacingLg,
                vertical: DefensysTokens.spacingSm,
              ),
              schedule:
                  groups
                      .expand((group) => group.schedules)
                      .where(
                        (schedule) =>
                            schedule['can_edit'] != false &&
                            schedule['status'] == 'scheduled',
                      )
                      .firstOrNull ??
                  anchor,
              sessionCount: groups.length,
              canManage:
                  _canManageSession(first) &&
                  (first.scope == 'pit' ||
                      _asInt(anchor['defense_stage_id']) != null),
              isSaving: state.isSaving,
            ),
          ),
          for (var index = 0; index < groups.length; index++) ...[
            if (index > 0)
              Divider(height: 1, thickness: 1, color: _borderColor),
            _buildSessionCard(groups[index], state),
          ],
        ],
      ),
    );
  }

  List<_SessionGroup> _groupSchedules(List<dynamic> rawSchedules) {
    final Map<String, _SessionGroup> groupMap = {};

    for (final item in rawSchedules) {
      if (item is! Map<String, dynamic>) continue;

      final stageLabel = item['stage_label']?.toString() ?? 'Unspecified Stage';
      final date = item['scheduled_date']?.toString() ?? 'TBD';
      final room = item['room']?.toString() ?? 'TBD';
      final scope = item['scope']?.toString() ?? 'capstone';

      final key =
          '${item['session_id'] ?? item['batch_id']}|$scope|${item['semester_id']}';

      if (!groupMap.containsKey(key)) {
        groupMap[key] = _SessionGroup(
          key: key,
          stageLabel: stageLabel,
          scheduledDate: date,
          room: room,
          scope: scope,
          schedules: [],
        );
      }
      groupMap[key]!.schedules.add(item);
    }

    // Sort schedules inside each group by start_time
    for (final group in groupMap.values) {
      if (group.schedules.map((s) => s['room']).toSet().length > 1) {
        group.room = 'Multiple rooms';
      }
      if (group.schedules.map((s) => s['scheduled_date']).toSet().length > 1) {
        group.scheduledDate = 'Multiple dates';
      }
      group.schedules.sort((a, b) {
        final tA = '${a['scheduled_date']} ${a['start_time']}';
        final tB = '${b['scheduled_date']} ${b['start_time']}';
        return tA.compareTo(tB);
      });
    }

    return groupMap.values.toList();
  }

  Widget _buildSessionCard(_SessionGroup group, DefenseBoardState state) {
    final isCollapsed =
        _plannerSessionId != null &&
            group.schedules.any(
              (schedule) =>
                  schedule['session_id']?.toString() == _plannerSessionId ||
                  schedule['legacy_session_id']?.toString() ==
                      _plannerSessionId,
            )
        ? false
        : _collapsedSessions.contains(group.key);

    return Column(
      key: ValueKey('board-session-${group.key}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSessionHeader(group, isCollapsed),
        if (!isCollapsed)
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < (_assignmentsView ? 900 : 820)) {
                return _buildCompactTeamList(group, state);
              }
              return _buildDesktopTeamTable(group, state);
            },
          ),
      ],
    );
  }

  bool _canManageSchedule(Map<String, dynamic> schedule) {
    final user = ref.read(authProvider).user;
    return isAdminWorkspace(user) ||
        (user?['is_pit_lead'] == true && schedule['can_manage'] == true);
  }

  bool _canManageSession(_SessionGroup group) {
    return group.schedules.isNotEmpty &&
        group.schedules.every(_canManageSchedule);
  }

  Widget _buildSessionHeader(_SessionGroup group, bool isCollapsed) {
    final pit = group.scope == 'pit';
    final repeatTeams = pit
        ? 0
        : group.schedules
              .where((schedule) => _defenseAttempt(schedule) > 1)
              .length;
    final date = DateTime.tryParse(group.scheduledDate);
    final dateLabel = date == null
        ? group.scheduledDate
        : DateFormat('d MMM yyyy').format(date);
    final count = group.schedules.length;
    final window = DefenseSessionWindow.fromJson(group.schedules.first);
    final timeLabel = window.isConfigured
        ? window.timeRange
        : _actualSessionRange(group);
    return Container(
      padding: const EdgeInsets.all(DefensysTokens.spacingMd),
      decoration: BoxDecoration(
        border: isCollapsed
            ? null
            : Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ShadButton.ghost(
                  key: ValueKey('session-toggle-${group.key}'),
                  height: 0,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  onPressed: () => setState(() {
                    if (isCollapsed) {
                      _collapsedSessions.remove(group.key);
                    } else {
                      _collapsedSessions.add(group.key);
                    }
                  }),
                  trailing: Icon(
                    isCollapsed
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronUp,
                    size: 16,
                  ),
                  child: Expanded(
                    child: Text(
                      '${window.isConfigured ? '${window.label} · ' : ''}$dateLabel · ${group.room} · $count ${count == 1 ? 'team' : 'teams'}',
                      textAlign: TextAlign.start,
                      style: DefensysTokens.body.copyWith(
                        color: _textPrimaryColor,
                      ),
                    ),
                  ),
                ),
              ),
              if (_canManageSession(group)) ...[
                const SizedBox(width: 8),
                _sessionActionMenu(group),
              ],
            ],
          ),
          if (timeLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              timeLabel,
              style: DefensysTokens.subtitle.copyWith(
                color: _textSecondaryColor,
              ),
            ),
          ],
          if (isCollapsed) ...[
            const SizedBox(height: 8),
            Text(
              _progressCounts(group.schedules).entries
                  .map(
                    (entry) =>
                        '${entry.value} ${_statusLabel(entry.key).toLowerCase()}',
                  )
                  .join(' · '),
              style: DefensysTokens.subtitle.copyWith(
                color: _textSecondaryColor,
              ),
            ),
          ],
          if (repeatTeams > 0) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: _attemptBadge(
                repeatTeams == count ? 'Re-defense' : '$repeatTeams re-defense',
                key: ValueKey('session-attempt-${group.key}'),
              ),
            ),
          ],
          if (_canManageSession(group) &&
              group.schedules.any(
                (schedule) => schedule['latest_change'] != null,
              )) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ScheduleChangesButton(schedules: group.schedules),
            ),
          ],
        ],
      ),
    );
  }

  String _actualSessionRange(_SessionGroup group) {
    final starts =
        group.schedules
            .map(
              (schedule) => DateTime.tryParse(
                '${schedule['scheduled_date']} ${schedule['start_time']}',
              ),
            )
            .whereType<DateTime>()
            .toList()
          ..sort();
    final ends =
        group.schedules
            .map((schedule) {
              final start = DateTime.tryParse(
                '${schedule['scheduled_date']} ${schedule['start_time']}',
              );
              final minutes = _asInt(schedule['slot_duration']);
              return start == null || minutes == null
                  ? null
                  : start.add(Duration(minutes: minutes));
            })
            .whereType<DateTime>()
            .toList()
          ..sort();
    if (starts.isEmpty || ends.isEmpty) return '';
    final sameDay = DateUtils.isSameDay(starts.first, ends.last);
    final format = DateFormat(sameDay ? 'h:mm a' : 'MMM d, h:mm a');
    return '${format.format(starts.first)}–${format.format(ends.last)}';
  }

  Widget _attemptBadge(String label, {Key? key}) => DefensysShadcnScope(
    child: ShadBadge.outline(
      key: key,
      backgroundColor: DefensysTokens.surfaceHigherOf(context),
      foregroundColor: _textSecondaryColor,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: DefensysTokens.fontFamilyInter,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

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
            (safePage + 1) * pageSize > totalTeams
                ? totalTeams
                : (safePage + 1) * pageSize,
          )
        : group.schedules;

    if (_assignmentsView) {
      return _buildAssignmentRows(
        group,
        state,
        paginatedSchedules,
        compact: false,
        page: safePage,
        totalPages: totalPages,
        totalTeams: totalTeams,
      );
    }

    return Column(
      children: [
        // Sub-table Header (Refined Uppercase Small-Caps)
        Container(
          height: 38,
          decoration: BoxDecoration(
            color: _panelBgColor,
            border: Border(bottom: BorderSide(color: _borderColor, width: 1)),
          ),
          child: Row(
            children: [
              const _HeaderCell('Time slot', flex: 2),
              _HeaderCell('Team & project', flex: isPit ? 7 : 5),
              const _HeaderCell('Progress', flex: 4),
              if (!isPit) const _HeaderCell('Minutes', flex: 2),
              const _HeaderCell('Actions', flex: 1),
            ],
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: paginatedSchedules.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, thickness: 1, color: _borderColor),
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
                    flex: 2,
                    child: Text(
                      _slotTimeRange(schedule),
                      style: DefensysTokens.tableCell.copyWith(
                        color: _textPrimaryColor,
                      ),
                    ),
                  ),
                  _BodyCell(
                    flex: isPit ? 7 : 5,
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
                            style: TextStyle(
                              fontFamily: DefensysTokens.fontFamilyInter,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _textPrimaryColor,
                            ),
                          ),
                          if (!isPit && _defenseAttempt(schedule) > 1) ...[
                            const SizedBox(height: 4),
                            _attemptBadge(
                              'Re-defense · Attempt ${_defenseAttempt(schedule)}',
                              key: ValueKey(
                                'defense-attempt-${schedule['id']}',
                              ),
                            ),
                          ],
                          if (projectTitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              projectTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: DefensysTokens.fontFamilyInter,
                                fontSize: 12,
                                color: _textSecondaryColor,
                              ),
                            ),
                          ],
                          if (!isPit && adviserName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.person_outline_rounded,
                                  size: 12,
                                  color: _textSecondaryColor,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    'Adviser: $adviserName',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily:
                                          DefensysTokens.fontFamilyInter,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _textSecondaryColor,
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
                                Icon(
                                  Icons.school_outlined,
                                  size: 12,
                                  color: _textSecondaryColor,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'Section: $section',
                                  style: TextStyle(
                                    fontFamily: DefensysTokens.fontFamilyInter,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _textSecondaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  _BodyCell(flex: 4, child: _progressCell(schedule)),
                  if (!isPit)
                    _BodyCell(flex: 2, child: _minutesStatusChip(schedule)),
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
          _buildTablePagination(
            group.key,
            safePage,
            totalPages,
            totalTeams,
            pageSize,
          ),
      ],
    );
  }

  Widget _assignmentPanel(Map<String, dynamic> schedule) {
    final panel =
        (schedule['panelists'] as List? ?? []).whereType<Map>().toList()..sort(
          (a, b) => (b['is_chair'] == true ? 1 : 0).compareTo(
            a['is_chair'] == true ? 1 : 0,
          ),
        );
    final external = (schedule['external_evaluators'] as List? ?? [])
        .whereType<Map>()
        .toList();
    return Column(
      key: ValueKey('assignment-panel-${schedule['id']}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (panel.isEmpty && external.isEmpty)
          Text(
            'No panel assigned',
            style: DefensysTokens.tableCell.copyWith(
              color: _textSecondaryColor,
            ),
          ),
        for (final person in panel)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: person['is_chair'] == true
                ? Wrap(
                    spacing: 6,
                    runSpacing: 3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        person['name']?.toString() ?? 'Unnamed panelist',
                        style: DefensysTokens.tableCell.copyWith(
                          color: _textPrimaryColor,
                        ),
                      ),
                      _attemptBadge('Chair'),
                    ],
                  )
                : Text(
                    person['name']?.toString() ?? 'Unnamed panelist',
                    style: DefensysTokens.tableCell.copyWith(
                      color: _textSecondaryColor,
                    ),
                  ),
          ),
        for (final person in external)
          Text(
            '${person['name'] ?? 'External evaluator'} (External)',
            style: DefensysTokens.tableCell.copyWith(
              color: _textSecondaryColor,
            ),
          ),
      ],
    );
  }

  Widget _assignmentDocumenter(Map<String, dynamic> schedule) {
    final name = schedule['documenter_name']?.toString().trim() ?? '';
    return Text(
      name.isEmpty ? 'Unassigned' : name,
      key: ValueKey('assignment-documenter-${schedule['id']}'),
      style: DefensysTokens.tableCell.copyWith(
        color: name.isEmpty ? _textSecondaryColor : _textPrimaryColor,
      ),
    );
  }

  Widget _buildAssignmentRows(
    _SessionGroup group,
    DefenseBoardState state,
    List<Map<String, dynamic>> schedules, {
    required bool compact,
    required int page,
    required int totalPages,
    required int totalTeams,
  }) {
    final pit = group.scope == 'pit';
    Widget identity(Map<String, dynamic> schedule) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _showDefenseDetailsDialog(schedule, group),
          child: Text(
            schedule['team_name']?.toString() ?? 'Unnamed team',
            style: DefensysTokens.body.copyWith(
              color: _textPrimaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (!pit && _defenseAttempt(schedule) > 1) ...[
          const SizedBox(height: 4),
          _attemptBadge(
            'Re-defense · Attempt ${_defenseAttempt(schedule)}',
            key: ValueKey('defense-attempt-${schedule['id']}'),
          ),
        ],
      ],
    );
    return Column(
      key: ValueKey('assignment-records-${group.key}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: _panelBgColor,
              border: Border(bottom: BorderSide(color: _borderColor)),
            ),
            child: Row(
              children: [
                const _HeaderCell('Time slot', flex: 2),
                const _HeaderCell('Team', flex: 3),
                _HeaderCell('Panel', flex: pit ? 7 : 5),
                if (!pit) const _HeaderCell('Documenter', flex: 3),
                const _HeaderCell('Actions', flex: 1),
              ],
            ),
          ),
        for (final schedule in schedules)
          Container(
            padding: compact
                ? const EdgeInsets.all(16)
                : const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _borderColor)),
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _slotTimeRange(schedule),
                              style: DefensysTokens.tableCell.copyWith(
                                color: _textSecondaryColor,
                              ),
                            ),
                          ),
                          _rowActionButtons(state, schedule, group),
                        ],
                      ),
                      identity(schedule),
                      const SizedBox(height: 12),
                      Text(
                        'Panel',
                        style: DefensysTokens.caption.copyWith(
                          color: _textSecondaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _assignmentPanel(schedule),
                      if (!pit) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Documenter',
                          style: DefensysTokens.caption.copyWith(
                            color: _textSecondaryColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _assignmentDocumenter(schedule),
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _BodyCell(
                        flex: 2,
                        child: Text(
                          _slotTimeRange(schedule),
                          style: DefensysTokens.tableCell.copyWith(
                            color: _textPrimaryColor,
                          ),
                        ),
                      ),
                      _BodyCell(flex: 3, child: identity(schedule)),
                      _BodyCell(
                        flex: pit ? 7 : 5,
                        child: _assignmentPanel(schedule),
                      ),
                      if (!pit)
                        _BodyCell(
                          flex: 3,
                          child: _assignmentDocumenter(schedule),
                        ),
                      _BodyCell(
                        flex: 1,
                        child: _rowActionButtons(state, schedule, group),
                      ),
                    ],
                  ),
          ),
        if (totalTeams > 10)
          _buildTablePagination(group.key, page, totalPages, totalTeams, 10),
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
      decoration: BoxDecoration(
        color: _panelBgColor,
        border: Border(top: BorderSide(color: _borderColor, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing $startIdx–$endIdx of $totalTeams teams',
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _textSecondaryColor,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.chevron_left_rounded,
                  size: 18,
                  color: _textSecondaryColor,
                ),
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
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _textPrimaryColor,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: _textSecondaryColor,
                ),
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
            (safePage + 1) * pageSize > totalTeams
                ? totalTeams
                : (safePage + 1) * pageSize,
          )
        : group.schedules;

    if (_assignmentsView) {
      return _buildAssignmentRows(
        group,
        state,
        paginatedSchedules,
        compact: true,
        page: safePage,
        totalPages: totalPages,
        totalTeams: totalTeams,
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          ...paginatedSchedules.map((schedule) {
            final teamName =
                schedule['team_name']?.toString() ?? 'Unnamed Team';
            final projectTitle = schedule['project_title']?.toString() ?? '';
            final adviserName = schedule['adviser_name']?.toString() ?? '';
            final section = schedule['section']?.toString() ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: _borderColor)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 480;
                      final identity = InkWell(
                        onTap: () => _showDefenseDetailsDialog(schedule, group),
                        borderRadius: BorderRadius.circular(4),
                        child: Text(
                          teamName,
                          maxLines: narrow ? null : 1,
                          overflow: narrow ? null : TextOverflow.ellipsis,
                          style: DefensysTokens.body.copyWith(
                            color: _textPrimaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Text(
                                _slotTimeRange(schedule),
                                style: DefensysTokens.tableCell.copyWith(
                                  color: _textPrimaryColor,
                                ),
                              ),
                              const SizedBox(width: 16),
                              if (narrow)
                                const Spacer()
                              else
                                Expanded(child: identity),
                              _rowActionButtons(state, schedule, group),
                            ],
                          ),
                          if (narrow) ...[const SizedBox(height: 6), identity],
                        ],
                      );
                    },
                  ),
                  if (!isPit && _defenseAttempt(schedule) > 1) ...[
                    const SizedBox(height: 4),
                    _attemptBadge(
                      'Re-defense · Attempt ${_defenseAttempt(schedule)}',
                      key: ValueKey('defense-attempt-${schedule['id']}'),
                    ),
                  ],
                  if (projectTitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      projectTitle,
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 12,
                        color: _textSecondaryColor,
                      ),
                    ),
                  ],
                  if (!isPit && adviserName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 13,
                          color: _textSecondaryColor,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Adviser: $adviserName',
                            style: TextStyle(
                              fontFamily: DefensysTokens.fontFamilyInter,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _textSecondaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (isPit && section.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.school_outlined,
                          size: 13,
                          color: _textSecondaryColor,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Section: $section',
                            style: TextStyle(
                              fontFamily: DefensysTokens.fontFamilyInter,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _textSecondaryColor,
                            ),
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
                      _progressCell(schedule),
                      if (!isPit)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Minutes: ',
                              style: DefensysTokens.caption.copyWith(
                                color: _textSecondaryColor,
                              ),
                            ),
                            _minutesStatusChip(schedule),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),
          if (totalTeams > pageSize)
            _buildTablePagination(
              group.key,
              safePage,
              totalPages,
              totalTeams,
              pageSize,
            ),
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
    final isAdmin = isAdminWorkspace(user);
    final isSchedulePit = schedule['scope'] == 'pit';
    final canManage = _canManageSchedule(schedule);
    final editable =
        schedule['can_edit'] != false &&
        !const ['done', 'archived'].contains(schedule['status']) &&
        schedule['grade_status'] != 'published';
    final gradeId = _asInt(schedule['grade_id']);
    final canReschedule = editable && schedule['can_reschedule'] != false;
    void edit(String task) =>
        showScheduleOperationsDialog(context, schedule, tab: task);
    return DefensysActionMenu(
      key: ValueKey('defense-actions-${schedule['id']}'),
      label: 'More actions for ${schedule['team_name']}',
      enabled: !state.isSaving,
      items: [
        DefensysMenuItem(
          label: 'View details',
          icon: LucideIcons.info,
          onPressed: () => _showDefenseDetailsDialog(schedule, group),
        ),
        DefensysMenuItem(
          label: 'Review deliverables',
          icon: LucideIcons.folderCheck,
          onPressed: () => TeamDeliverablesReviewDialog.show(
            context,
            ref,
            team: {
              'id': schedule['team_id'] ?? schedule['id'],
              'name': schedule['team_name'] ?? 'Team',
            },
            stageLabel: group.stageLabel,
            scope:
                schedule['scope']?.toString() ??
                (isSchedulePit ? 'pit' : 'capstone'),
          ),
        ),
        DefensysMenuItem(
          label: 'Evaluation & grades',
          icon: LucideIcons.clipboardList,
          onPressed: () => _openEvaluationAndGrades(schedule),
        ),
        if (isAdmin && gradeId != null)
          DefensysMenuItem(
            label: 'Correct a score',
            icon: LucideIcons.pencil,
            onPressed: () => showGradeCorrectionDialog(context, gradeId),
          ),
        if (canManage) ...[
          DefensysMenuItem(
            label: 'View change history',
            icon: LucideIcons.history,
            onPressed: () =>
                showScheduleHistory(context, _asInt(schedule['id'])!),
          ),
          const Divider(height: 9),
          DefensysMenuItem(
            label: 'Edit panel',
            icon: LucideIcons.users,
            onPressed: editable ? () => edit('panel') : null,
          ),
          if (!isSchedulePit)
            DefensysMenuItem(
              label: 'Change documenter',
              icon: LucideIcons.filePenLine,
              onPressed: editable ? () => edit('documenter') : null,
            ),
          DefensysMenuItem(
            label: 'Change room',
            icon: LucideIcons.mapPin,
            hint: canReschedule
                ? null
                : 'Recorded evaluations keep their original room and time.',
            onPressed: canReschedule ? () => edit('room') : null,
          ),
          DefensysMenuItem(
            label: 'Reschedule defense',
            icon: LucideIcons.calendarClock,
            hint: canReschedule
                ? null
                : 'Recorded evaluations keep their original room and time.',
            onPressed: canReschedule ? () => edit('time') : null,
          ),
          const Divider(height: 9),
          DefensysMenuItem(
            label:
                schedule['operation_state'] != null &&
                        schedule['operation_state'] != 'normal' ||
                    schedule['status'] == 'cancelled'
                ? 'Resume defense'
                : 'Pause defense',
            icon: LucideIcons.circlePause,
            onPressed: editable
                ? () => edit(
                    schedule['operation_state'] != null &&
                                schedule['operation_state'] != 'normal' ||
                            schedule['status'] == 'cancelled'
                        ? 'normal'
                        : 'paused',
                  )
                : null,
          ),
          DefensysMenuItem(
            label: 'Postpone defense',
            icon: LucideIcons.clock,
            onPressed: editable ? () => edit('postponed') : null,
          ),
          DefensysMenuItem(
            label: 'Mark as no-show',
            icon: LucideIcons.userX,
            onPressed: editable ? () => edit('no_show') : null,
          ),
          DefensysMenuItem(
            label: 'Cancel defense',
            icon: LucideIcons.circleX,
            onPressed: editable ? () => edit('cancelled') : null,
          ),
          const Divider(height: 9),
          DefensysMenuItem(
            label: 'Delete schedule',
            icon: LucideIcons.trash2,
            destructive: true,
            hint: schedule['can_delete'] == true
                ? null
                : (schedule['deletion_blockers'] as List? ??
                          ['Recorded activity protects this schedule.'])
                      .join(' '),
            onPressed: schedule['can_delete'] == true
                ? () => edit('delete')
                : null,
          ),
        ],
      ],
    );
  }

  Widget _sessionActionMenu(_SessionGroup group) {
    final anchor =
        group.schedules.where((s) => s['status'] == 'scheduled').firstOrNull ??
        group.schedules.first;
    return ScheduleGroupActions(
      key: ValueKey('session-actions-${group.key}'),
      schedule: anchor,
      enabled: !ref.watch(defenseBoardProvider).isSaving,
      onEvaluatorAccess:
          group.schedules.any(
            (s) => (s['external_evaluators'] as List? ?? []).isNotEmpty,
          )
          ? () => SessionEvaluatorAccessDialog.show(
              context,
              group.schedules
                  .map((s) => _asInt(s['id']))
                  .whereType<int>()
                  .toSet(),
            )
          : null,
    );
  }

  void _showDefenseDetailsDialog(
    Map<String, dynamic> schedule,
    _SessionGroup group,
  ) {
    final isPit = group.scope == 'pit';
    final accentColor = isPit ? ProgramColors.pit : ProgramColors.capstone;
    final teamName = schedule['team_name']?.toString() ?? 'Unnamed Team';
    final projectTitle =
        schedule['project_title']?.toString() ?? 'No title provided';
    final teamLevel = schedule['team_level']?.toString() ?? '';
    final adviserName = schedule['adviser_name']?.toString() ?? '';
    final section = schedule['section']?.toString() ?? '';
    final leaderName = schedule['leader_name']?.toString() ?? '';
    final rubricName =
        schedule['rubric_name']?.toString() ?? 'Default Evaluation Rubric';
    final status =
        (schedule['display_status']?.toString() ??
                schedule['status']?.toString() ??
                'scheduled')
            .toLowerCase();
    final slotTimeRange = _slotTimeRange(schedule);
    final panelNames = _panelistNames(schedule);
    final documenterName = schedule['documenter_name']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: _surfaceColor,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: _surfaceColor,
                  border: Border(
                    bottom: BorderSide(color: _borderColor),
                    left: BorderSide(
                      color: ProgramColors.of(context, isCapstone: !isPit).text,
                      width: 4,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(
                          alpha: _isDark ? 0.2 : 0.10,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isPit ? 'PIT' : 'CAPSTONE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: ProgramColors.of(
                            context,
                            isCapstone: !isPit,
                          ).text,
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
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _textPrimaryColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${schedule['scheduled_date']} • $slotTimeRange • ${schedule['room']}',
                            style: TextStyle(
                              fontSize: 12,
                              color: _textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: _textSecondaryColor,
                      ),
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
                          color: _panelBgColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.groups_rounded,
                                  size: 18,
                                  color: _textSecondaryColor,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    teamName,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: _textPrimaryColor,
                                    ),
                                  ),
                                ),
                                if (teamLevel.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _surfaceColor,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: _borderColor),
                                    ),
                                    child: Text(
                                      teamLevel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _textPrimaryColor,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              projectTitle,
                              style: TextStyle(
                                fontSize: 13,
                                color: _textSecondaryColor,
                                height: 1.4,
                              ),
                            ),
                            if (adviserName.isNotEmpty ||
                                section.isNotEmpty ||
                                leaderName.isNotEmpty) ...[
                              Divider(height: 20, color: _borderColor),
                              Wrap(
                                spacing: 18,
                                runSpacing: 6,
                                children: [
                                  if (adviserName.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.person_outline_rounded,
                                          size: 14,
                                          color: _textSecondaryColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Adviser: $adviserName',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _textPrimaryColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (section.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.school_outlined,
                                          size: 14,
                                          color: _textSecondaryColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Section: $section',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _textPrimaryColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (leaderName.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.star_outline_rounded,
                                          size: 14,
                                          color: _textSecondaryColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Leader: $leaderName',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _textPrimaryColor,
                                          ),
                                        ),
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
                      Text(
                        'DEFENSE COMMITTEE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: _textSecondaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _surfaceColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _borderColor),
                        ),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.people_outline_rounded,
                                  size: 16,
                                  color: _textSecondaryColor,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Panelists: ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _textPrimaryColor,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    panelNames,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _textPrimaryColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!isPit) ...[
                              Divider(height: 18, color: _borderColor),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.edit_note_rounded,
                                    size: 16,
                                    color: _textSecondaryColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Documenter: ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _textPrimaryColor,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      documenterName.isNotEmpty
                                          ? documenterName
                                          : 'Unassigned',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: documenterName.isEmpty
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: documenterName.isEmpty
                                            ? DefensysTokens.warningText
                                            : _textPrimaryColor,
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
                                color: _panelBgColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'CURRENT STATUS',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: _textSecondaryColor,
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
                                color: _panelBgColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'EVALUATION RUBRIC',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: _textSecondaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    rubricName,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _textPrimaryColor,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _panelBgColor,
                  border: Border(top: BorderSide(color: _borderColor)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!isPit) ...[
                      OutlinedButton.icon(
                        icon: const Icon(Icons.description_outlined, size: 15),
                        label: const Text('Preview minutes PDF'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _textPrimaryColor,
                          side: BorderSide(color: _borderColor),
                          backgroundColor: _surfaceColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          final scheduleId = _asInt(schedule['id']);
                          if (scheduleId != null) {
                            _previewMinutes(schedule);
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
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

  Widget _progressCell(Map<String, dynamic> schedule) {
    final status = (schedule['display_status'] ?? schedule['status'] ?? '')
        .toString();
    final assessment = schedule['assessment'];
    String? detail;
    if (assessment is Map) {
      final required = _asInt(assessment['panel_evaluators_required']);
      final submitted = _asInt(assessment['panel_evaluators_submitted']);
      if (required != null &&
          required > 0 &&
          submitted != null &&
          const [
            'scheduled',
            'awaiting_evaluation',
            'evaluating',
            'ongoing',
            'awaiting_verdict',
            'awaiting_concept_selection',
          ].contains(status)) {
        detail = '$submitted/$required panel evaluations submitted';
      } else if (status == 'pending_post_defense' &&
          assessment['post_defense_complete'] == false) {
        detail = 'Required post-defense files incomplete';
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statusChip(status),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(
            detail,
            style: DefensysTokens.caption.copyWith(color: _textSecondaryColor),
          ),
        ],
      ],
    );
  }

  Widget _statusChip(String status) {
    final normalized = status.toLowerCase();

    Color bg;
    Color fg;
    IconData iconData;
    String text;

    switch (normalized) {
      case 'paused':
      case 'postponed':
      case 'no_show':
        bg = _isDark
            ? const Color(0xFF78350F).withValues(alpha: 0.12)
            : DefensysTokens.warningBg;
        fg = _isDark ? const Color(0xFFFDE68A) : DefensysTokens.warningText;
        iconData = Icons.pause_circle_outline;
        text = normalized == 'paused'
            ? 'Interrupted'
            : normalized == 'postponed'
            ? 'Postponed'
            : 'No-show';
        break;
      case 'changes_requested':
      case 'needs_review':
      case 'awaiting_completion':
      case 'revisions_pending':
      case 'grading_incomplete':
      case 'pending_post_defense':
      case 'awaiting_endorsement':
      case 'ready_to_schedule_redefense':
      case 'redefense_required':
      case 'for_redefense':
        bg = _isDark
            ? const Color(0xFF78350F).withValues(alpha: 0.12)
            : DefensysTokens.warningBg;
        fg = _isDark ? const Color(0xFFFDE68A) : DefensysTokens.warningText;
        iconData = Icons.play_circle_rounded;
        text = _statusLabel(normalized);
        break;
      case 'evaluating':
      case 'ongoing':
      case 'awaiting_evaluation':
      case 'awaiting_verdict':
      case 'awaiting_concept_selection':
        bg = _isDark
            ? DefensysTokens.infoText.withValues(alpha: 0.12)
            : DefensysTokens.infoBg;
        fg = _isDark ? const Color(0xFF93C5FD) : DefensysTokens.infoText;
        iconData = Icons.pending_outlined;
        text = _statusLabel(normalized);
        break;
      case 'completed':
        bg = _isDark
            ? const Color(0xFF064E3B).withValues(alpha: 0.12)
            : DefensysTokens.successBg;
        fg = _isDark ? const Color(0xFF6EE7B7) : DefensysTokens.successText;
        iconData = Icons.check_circle_rounded;
        text = 'Completed';
        break;
      case 'cancelled':
      case 'failed':
      case 'project_rejected':
        bg = _isDark
            ? const Color(0xFF7F1D1D).withValues(alpha: 0.12)
            : DefensysTokens.dangerBg;
        fg = _isDark ? const Color(0xFFFCA5A5) : DefensysTokens.dangerText;
        iconData = Icons.cancel_rounded;
        text = _statusLabel(normalized);
        break;
      case 'archived':
        bg = _isDark ? DefensysTokens.mistInputFill : DefensysTokens.archivedBg;
        fg = _isDark
            ? DefensysTokens.textSecondaryDark
            : DefensysTokens.archivedText;
        iconData = Icons.archive_rounded;
        text = 'Archived';
        break;
      default:
        bg = _surfaceColor;
        fg = _textSecondaryColor;
        iconData = Icons.schedule_rounded;
        text = _statusLabel(normalized);
    }

    return DefensysShadcnScope(
      child: ShadBadge.outline(
        backgroundColor: bg,
        foregroundColor: fg,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconData, size: 12, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyBoard() {
    final state = ref.read(defenseBoardProvider);
    if (state.error != null) return const SizedBox.shrink();
    final filtered =
        _plannerDate != null ||
        [
          state.search,
          state.stage,
          state.status,
          state.adviser,
          state.section,
        ].any((value) => value.isNotEmpty);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DefensysEmptyState(
        icon: Icons.table_chart_outlined,
        title: filtered ? 'No matching defenses' : 'No defenses scheduled',
        description: filtered
            ? 'Try another search or clear the filters to see more defenses.'
            : 'Scheduled defenses will appear here for the selected program.',
        size: DefensysEmptyStateSize.standard,
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      padding: const EdgeInsets.all(20),
      child: Semantics(
        label: 'Loading defenses',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DefensysSkeleton.box(
              width: 180,
              height: 18,
              color: DefensysTokens.surfaceHigherOf(context),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < 3; i++) ...[
              DefensysSkeleton.box(
                height: 56,
                color: DefensysTokens.surfaceHigherOf(context),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadError(String message, VoidCallback retry) =>
      ShadAlert.destructive(
        title: const Text('Couldn’t load defenses'),
        description: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 8),
            ShadButton.outline(onPressed: retry, child: const Text('Retry')),
          ],
        ),
      );

  Future<void> _openManualScheduleDialog() async {
    final user = ref.read(authProvider).user;
    final isAdmin = isAdminWorkspace(user);
    final isPitLead = user?['is_pit_lead'] == true;
    if (!isAdmin && !isPitLead) return;

    final schedNotifier = ref.read(defenseSchedulerProvider.notifier);
    await schedNotifier.fetchSchedules();
    final schedState = ref.read(defenseSchedulerProvider);
    final scope = _effectiveBoardScope(ref.read(defenseBoardProvider));

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

  void _openImportScheduleDialog() {
    final user = ref.read(authProvider).user;
    final isAdmin = isAdminWorkspace(user);
    final isPitLead = user?['is_pit_lead'] == true;
    if (!isAdmin && !isPitLead) return;
    if (!_canScheduleScope(
      _effectiveBoardScope(ref.read(defenseBoardProvider)),
    )) {
      return;
    }

    setState(() {
      _showScheduleBulkImport = true;
    });

    ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
  }

  void _openScheduler({String? scope, int? stageId, String? eventName}) {
    final user = ref.read(authProvider).user;
    final isAdmin = isAdminWorkspace(user);
    final isPitLead = user?['is_pit_lead'] == true;
    if (!isAdmin && !isPitLead) return;
    if (!_canScheduleScope(
      scope ?? _effectiveBoardScope(ref.read(defenseBoardProvider)),
    )) {
      return;
    }

    setState(() {
      _schedulerScope =
          scope ?? _effectiveBoardScope(ref.read(defenseBoardProvider));
      _schedulerStageId = stageId;
      _schedulerEventName = eventName;
      _showScheduler = true;
    });
  }

  String _panelistNames(Map<String, dynamic> schedule) {
    final panelists = schedule['panelists'] as List? ?? [];
    final names = panelists
        .whereType<Map>()
        .map((panelist) {
          final name = panelist['name']?.toString() ?? '';
          return name.isNotEmpty && panelist['is_chair'] == true
              ? '$name (Chair)'
              : name;
        })
        .where((name) => name.isNotEmpty)
        .toList();
    names.addAll(
      (schedule['external_evaluators'] as List? ?? []).whereType<Map>().map(
        (e) => '${e['name']} (External)',
      ),
    );
    return names.isEmpty ? 'No panel assigned' : names.join(', ');
  }

  String _shortTime(dynamic value) {
    final text = value?.toString() ?? '';
    return text.length >= 5 ? text.substring(0, 5) : text;
  }

  String _slotTimeRange(Map<String, dynamic> schedule) {
    final start = _shortTime(schedule['start_time']);
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(start);
    final duration = _asInt(schedule['slot_duration']);
    if (match == null || duration == null || duration <= 0) return start;

    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return start;

    final endMinutes = hour * 60 + minute + duration;
    final endHour = (endMinutes ~/ 60) % 24;
    final endMinute = endMinutes % 60;
    final end =
        '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';
    return '$start–$end${endMinutes >= 24 * 60 ? ' next day' : ''}';
  }

  String _statusLabel(String status) {
    return defenseProgressLabel(status);
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Future<void> _previewMinutes(Map<String, dynamic> schedule) async {
    final scheduleId = _asInt(schedule['id']);
    if (scheduleId == null) return;
    final user = ref.read(authProvider).user;
    final isAdmin = isAdminWorkspace(user);
    final signed = await MinutesPdfDialog.show(
      context,
      scheduleId: scheduleId,
      finalized: schedule['minutes_status'] == 'completed',
      teamName:
          '${schedule['team_name'] ?? 'Defense'} · ${schedule['stage_label'] ?? 'Minutes'}',
      allowChairmanSigning:
          isAdmin &&
          schedule['status'] != 'cancelled' &&
          schedule['minutes_status'] == 'adviser_signed',
    );
    if (!mounted || signed != true) return;
    await ref
        .read(defenseBoardProvider.notifier)
        .fetchBoard(
          successMessage:
              'Signed as chairman successfully. Official minutes PDF generated.',
        );
  }

  Future<void> _openNotificationMinutes(int scheduleId, Uri requestUri) async {
    bool stillHere() => mounted && GoRouterState.of(context).uri == requestUri;
    if (!stillHere()) return;
    try {
      final schedule = await fetchMinutesNotificationSchedule(
        ref.read(authenticatedHttpClientProvider),
        scheduleId,
        workspace: 'operations',
      );
      if (!stillHere()) return;
      await _previewMinutes(schedule);
    } catch (error) {
      if (mounted && stillHere()) showErrorToast(context, error.toString());
    } finally {
      if (mounted && stillHere()) {
        final query = Map<String, String>.from(requestUri.queryParameters)
          ..remove('minutes');
        context.replace(requestUri.replace(queryParameters: query).toString());
      }
    }
  }

  Widget _minutesStatusChip(Map<String, dynamic> schedule) {
    final status = schedule['minutes_status']?.toString();
    final scheduleId = _asInt(schedule['id']);
    if (scheduleId == null || schedule['scope'] != 'capstone') {
      return const SizedBox.shrink();
    }

    if (schedule['minutes_required'] == false &&
        status == null &&
        schedule['documenter'] == null) {
      return Text(
        'Not required',
        style: TextStyle(fontSize: 12, color: _textSecondaryColor),
      );
    }
    final label = switch (status) {
      'draft' => 'Draft',
      'submitted' => 'Awaiting adviser',
      'adviser_signed' => 'Awaiting chairman',
      'completed' => 'Finalized',
      _ => 'Not started',
    };
    return ShadButton.link(
      height: 0,
      padding: const EdgeInsets.symmetric(vertical: 6),
      foregroundColor: status == 'completed'
          ? (_isDark ? const Color(0xFF6EE7B7) : DefensysTokens.successText)
          : _textSecondaryColor,
      onPressed: () => _previewMinutes(schedule),
      child: Flexible(
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: DefensysTokens.fontFamilyInter,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  void _openEvaluationAndGrades(Map<String, dynamic> schedule) {
    final gradeId = asInt(schedule['grade_id']);
    if (gradeId == null || gradeId <= 0) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => DefensysShadcnScope(
          child: ShadDialog(
            title: const Text('Evaluation unavailable'),
            description: const Text(
              'An evaluation record is not available for this defense attempt. Refresh the schedules to check for an update.',
            ),
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
              ShadButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  ref.read(defenseBoardProvider.notifier).fetchBoard();
                },
                child: const Text('Refresh schedules'),
              ),
            ],
          ),
        ),
      );
      return;
    }
    final uri = GoRouterState.of(context).uri;
    final isLocked =
        schedule['grade_status'] == 'published' ||
        const ['completed', 'done', 'archived'].contains(schedule['status']);
    if (uri.path.startsWith('/admin/') || uri.path.startsWith('/faculty/')) {
      context.go(
        BoardEvaluationRoutes.detail(
          faculty: uri.path.startsWith('/faculty/'),
          gradeId: gradeId,
          locked: isLocked,
          boardUri: uri,
          program: _effectiveBoardScope(ref.read(defenseBoardProvider)),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GradeCenterTeamDetailScreen(
            gradeId: gradeId,
            isLocked: isLocked,
            returnToBoard: true,
            onBack: () => Navigator.pop(context),
          ),
        ),
      );
    }
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final int flex;

  const _HeaderCell(this.text, {required this.flex});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: text == 'Actions' ? 8 : 16),
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontFamily: DefensysTokens.fontFamilyInter,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: isDark
                ? DefensysTokens.textSecondaryDark
                : DefensysTokens.steelGrey,
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
  String scheduledDate;
  String room;
  final String scope;
  final List<Map<String, dynamic>> schedules;

  _SessionGroup({
    required this.key,
    required this.stageLabel,
    required this.scheduledDate,
    required this.room,
    required this.scope,
    required this.schedules,
  });
}
