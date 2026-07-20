import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/config/api_config.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/defensys_skeleton.dart';
import 'package:defensys/widgets/feedback_toast.dart';

import 'components/scheduler_calendar_view.dart';
import 'components/scheduler_toolbar.dart';
import 'components/team_readiness_tracker.dart';
import 'dialogs/manual_slot_editor_dialog.dart';
import 'dialogs/team_deliverables_review_dialog.dart';
import 'dialogs/venue_conflict_dialog.dart';
import 'models/schedule_import_models.dart';

class DefenseSchedulerScreen extends ConsumerStatefulWidget {
  const DefenseSchedulerScreen({super.key});

  @override
  ConsumerState<DefenseSchedulerScreen> createState() =>
      _DefenseSchedulerScreenState();
}

class _DefenseSchedulerScreenState
    extends ConsumerState<DefenseSchedulerScreen> {
  final _eventController = TextEditingController();
  final _panelWeightController = TextEditingController(text: '80');
  final _peerWeightController = TextEditingController(text: '20');
  final _dateController = TextEditingController();
  final _timeController = TextEditingController(text: '08:00');
  final _durationController = TextEditingController(text: '60');
  final _roomController = TextEditingController();
  final _pitTemplateController = TextEditingController();

  final Set<int> _selectedPanelistIds = {};
  final List<Map<String, dynamic>> _pitDeliverables = [];

  String _scope = 'capstone';
  int? _stageId;
  int? _rubricId;
  int? _adviserRubricId;
  int? _capstonePeerRubricId;
  int? _peerRubricId;
  bool _showFinalPreview = false;
  bool _scopeInitializedFromState = false;
  bool _isSendingReminder = false;
  List<Map<String, dynamic>> _planSlots = [];

  @override
  void dispose() {
    _eventController.dispose();
    _panelWeightController.dispose();
    _peerWeightController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _durationController.dispose();
    _roomController.dispose();
    _pitTemplateController.dispose();
    for (final d in _pitDeliverables) {
      (d['_labelController'] as TextEditingController?)?.dispose();
      (d['_vaultNoteController'] as TextEditingController?)?.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _dateController.text = DateTime.now().toIso8601String().substring(0, 10);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
    });
  }

  bool _canScheduleScope(DefenseSchedulerState state, String scope) {
    if (scope == 'pit') return state.canSchedulePit;
    if (scope == 'capstone') return state.canScheduleCapstone;
    return false;
  }

  bool _canScheduleCurrentScope(DefenseSchedulerState state) {
    return _canScheduleScope(state, _scope);
  }

  String _scheduleNoticeMessage(DefenseSchedulerState state) {
    final message = state.operatingMessage?.trim() ?? '';
    if (message.isNotEmpty) return message;
    if (!_canScheduleCurrentScope(state) &&
        (state.schedulerMode == 'pit' || _scope == 'pit')) {
      return 'PIT scheduling is closed for this term.';
    }
    if (!_canScheduleCurrentScope(state) &&
        (state.schedulerMode == 'capstone' || _scope == 'capstone')) {
      return 'Scheduling is not available for this workspace.';
    }
    return '';
  }

  String _stageLabel(DefenseSchedulerState state) {
    for (final stage in state.defenseStages) {
      if (asInt(stage['id']) == _stageId) {
        return stage['label']?.toString() ?? 'Stage';
      }
    }
    return 'Stage';
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
          showErrorToast(context, 'Failed to send reminder');
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

  void _initializeScopeFromState(DefenseSchedulerState state) {
    if (_scopeInitializedFromState) return;
    String targetScope = '';
    if (state.schedulerMode == 'pit' || state.schedulerMode == 'capstone') {
      targetScope = state.schedulerMode;
    } else if (state.canScheduleCapstone) {
      targetScope = 'capstone';
    } else if (state.canSchedulePit) {
      targetScope = 'pit';
    }

    if (targetScope.isEmpty) return;
    _scopeInitializedFromState = true;
    if (targetScope == _scope) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || targetScope == _scope) return;
      setState(() {
        _scope = targetScope;
        _stageId = null;
        _rubricId = null;
        _adviserRubricId = null;
        _capstonePeerRubricId = null;
        _peerRubricId = null;
        _planSlots = [];
        _showFinalPreview = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(defenseSchedulerProvider);
    _initializeScopeFromState(state);

    final stages = state.defenseStages;
    if (_scope == 'capstone' && _stageId == null && stages.isNotEmpty) {
      int? targetStageId;
      for (final stage in stages) {
        final isComplete = stage['is_officially_complete'] == true;
        if (isComplete) continue;
        final stageLabel = stage['label']?.toString() ?? '';
        final hasReadyTeams = state.teams.any((team) {
          final readyForStage = team['ready_for_stage']?.toString() ?? '';
          final teamLevel = team['level']?.toString() ?? '';
          final isCapstone = teamLevel.toLowerCase().contains('capstone');
          return isCapstone && readyForStage == stageLabel;
        });
        if (hasReadyTeams) {
          targetStageId = asInt(stage['id']);
          break;
        }
      }
      targetStageId ??= asInt(stages.first['id']);

      if (targetStageId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _stageId == null) {
            setState(() {
              _stageId = targetStageId;
            });
          }
        });
      }
    }

    final currentStep = _planSlots.isEmpty ? 1 : (_showFinalPreview ? 3 : 2);

    ref.listen(defenseSchedulerProvider, (previous, next) {
      final error = next.error;
      if (error != null && error.isNotEmpty && error != previous?.error) {
        showErrorToast(context, error);
      }
      final message = next.message;
      if (message != null && message.isNotEmpty && message != previous?.message) {
        showSuccessToast(context, message);
      }
    });

    final activeStageOrEventName = _scope == 'capstone'
        ? _stageLabel(state)
        : _eventController.text.trim();

    return Scaffold(
      backgroundColor: DefensysUi.bgLight,
      body: RefreshIndicator(
        color: AppColors.maroon,
        onRefresh: () =>
            ref.read(defenseSchedulerProvider.notifier).fetchSchedules(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: DefensysUi.contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SchedulerToolbar(
                state: state,
                canSchedule: _canScheduleCurrentScope(state),
                onOpenManualDialog: () => ManualSlotEditorDialog.show(
                  context,
                  ref,
                  state: state,
                  initialScope: _scope,
                  initialStageId: _stageId,
                  initialRubricId: _rubricId,
                  initialAdviserRubricId: _adviserRubricId,
                  initialCapstonePeerRubricId: _capstonePeerRubricId,
                  initialPeerRubricId: _peerRubricId,
                  initialSelectedPanelistIds: _selectedPanelistIds,
                  initialEvent: _eventController.text,
                  initialPitTemplate: _pitTemplateController.text,
                  initialDate: _dateController.text,
                  initialTime: _timeController.text,
                  initialDuration: _durationController.text,
                  initialRoom: _roomController.text,
                  initialPanelWeight: _panelWeightController.text,
                  initialPeerWeight: _peerWeightController.text,
                  canScheduleScope: _canScheduleScope,
                  scheduleNoticeMessage: _scheduleNoticeMessage,
                ),
                onOpenImportDialog: () => ScheduleImportDialog.show(
                  context,
                  ref,
                  state: state,
                  scope: _scope,
                  initialStageId: _stageId,
                  initialEventName: _eventController.text,
                  initialRubricId: _rubricId,
                  initialAdviserRubricId: _adviserRubricId,
                  initialPeerRubricId: _peerRubricId,
                  initialCapstonePeerRubricId: _capstonePeerRubricId,
                  initialDate: _dateController.text,
                  initialRoom: _roomController.text,
                  initialDuration: _durationController.text,
                  initialPanelWeight: _panelWeightController.text,
                  initialPeerWeight: _peerWeightController.text,
                  canScheduleScope: _canScheduleScope,
                  scheduleNoticeMessage: _scheduleNoticeMessage,
                ),
              ),
              const SizedBox(height: 26),
              SchedulerStepProgress(currentStep: currentStep),
              const SizedBox(height: 12),
              if (_scheduleNoticeMessage(state).isNotEmpty) ...[
                SchedulerNoticeBanner(
                  message: _scheduleNoticeMessage(state),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 12),
              if (state.isLoading &&
                  state.schedules.isEmpty &&
                  state.teams.isEmpty) ...[
                DefensysSkeleton.list(count: 4, rowHeight: 64),
              ] else ...[
                TeamReadinessTracker(
                  state: state,
                  scope: _scope,
                  activeStageOrEventName: activeStageOrEventName,
                  onReviewTeamDeliverables: (team, stageLabel) =>
                      TeamDeliverablesReviewDialog.show(
                    context,
                    ref,
                    team: team,
                    stageLabel: stageLabel,
                    scope: _scope,
                  ),
                  onSendReminder: _sendReminder,
                  isSendingReminder: _isSendingReminder,
                ),
                const SizedBox(height: 22),
                SchedulerCalendarView(state: state),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
