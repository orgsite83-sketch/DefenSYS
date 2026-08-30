import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/config/api_config.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/defensys_skeleton.dart';
import 'package:defensys/toasts/feedback_toast.dart';

import 'components/schedule_run_container.dart';
import 'components/scheduler_toolbar.dart';
import 'components/team_readiness_tracker.dart';
import 'dialogs/team_deliverables_review_dialog.dart';
import 'models/schedule_import_models.dart';

class DefenseSchedulerScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final String? initialScope;
  final int? initialStageId;
  final String? initialEventName;

  const DefenseSchedulerScreen({
    super.key,
    this.onBack,
    this.initialScope,
    this.initialStageId,
    this.initialEventName,
  });

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
  int? _documenterId;
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
    if (widget.initialScope != null) {
      _scope = widget.initialScope!;
      _scopeInitializedFromState = true;
    }
    if (widget.initialStageId != null) {
      _stageId = widget.initialStageId;
    }
    if (widget.initialEventName != null && widget.initialEventName!.isNotEmpty) {
      _eventController.text = widget.initialEventName!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
      if (_scope == 'capstone' && _stageId != null) {
        _prefillCapstoneStageRubrics();
      } else if (_scope == 'pit' && _eventController.text.isNotEmpty) {
        _prefillPitEventConfig();
      }
    });
  }

  bool _canScheduleScope(DefenseSchedulerState state, String scope) {
    final user = ref.read(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;

    if (scope == 'capstone') {
      return isAdmin && state.canScheduleCapstone;
    }
    if (scope == 'pit') {
      return isPitLead && !isAdmin && state.canSchedulePit;
    }
    return false;
  }

  bool _canScheduleCurrentScope(DefenseSchedulerState state) {
    return _canScheduleScope(state, _scope);
  }

  String _scheduleNoticeMessage(DefenseSchedulerState state) {
    final user = ref.watch(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;

    if (!isAdmin && !isPitLead) {
      return 'Defense scheduling is restricted to Administrators (Capstone) and PIT Leads (PIT).';
    }

    final message = state.operatingMessage?.trim() ?? '';
    if (message.isNotEmpty) return message;
    if (_scope == 'pit' && isAdmin) {
      return 'PIT scheduling is strictly managed by the PIT Lead.';
    }
    if (!_canScheduleCurrentScope(state) &&
        (state.schedulerMode == 'pit' || _scope == 'pit')) {
      return 'PIT scheduling is closed for this term.';
    }
    if (!_canScheduleCurrentScope(state) &&
        (state.schedulerMode == 'capstone' || _scope == 'capstone')) {
      return 'Scheduling Capstone defenses is strictly reserved for Administrators.';
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

  Future<void> _prefillPitEventConfig() async {
    if (_scope != 'pit') return;
    final eventName = _eventController.text.trim();
    if (eventName.length < 3) return;

    final semesterId = asInt(
      ref.read(defenseSchedulerProvider).activeSemester?['id'],
    );
    final config = await ref
        .read(defenseSchedulerProvider.notifier)
        .fetchPitEventConfig(eventName: eventName, semesterId: semesterId);
    if (!mounted || config == null) return;

    setState(() {
      _rubricId = asInt(config['panel_rubric_id']) ?? _rubricId;
      _peerRubricId = asInt(config['peer_rubric_id']) ?? _peerRubricId;
      _panelWeightController.text = config['panel_weight']?.toString() ?? '80';
      _peerWeightController.text = config['peer_weight']?.toString() ?? '20';
      _pitTemplateController.text =
          (config['archive_file_template'] ?? config['vault_file_template'])?.toString() ?? '';
    });
  }

  Future<void> _prefillCapstoneStageRubrics() async {
    if (_scope != 'capstone' || _stageId == null) return;
    final semesterId = asInt(
      ref.read(defenseSchedulerProvider).activeSemester?['id'],
    );
    if (semesterId == null) return;

    final detail = await ref
        .read(defenseStagesProvider.notifier)
        .fetchStageDetail(_stageId!, semesterId: semesterId);
    if (!mounted || detail == null) return;

    final grading = detail['grading_config'];
    if (grading is! Map) return;

    setState(() {
      _rubricId = asInt(grading['panel_rubric_id']) ?? _rubricId;
      _adviserRubricId = asInt(grading['adviser_rubric_id']) ?? _adviserRubricId;
      _capstonePeerRubricId = asInt(grading['peer_rubric_id']) ?? _capstonePeerRubricId;
    });
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
    final user = ref.read(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;

    String targetScope = '';
    if (isAdmin) {
      targetScope = 'capstone';
    } else if (isPitLead) {
      targetScope = 'pit';
    } else if (state.schedulerMode == 'pit' ||
        state.schedulerMode == 'capstone') {
      targetScope = state.schedulerMode;
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
            _prefillCapstoneStageRubrics();
          }
        });
      }
    }

    if (_scope == 'pit' && _eventController.text.isEmpty && state.pitEvents.isNotEmpty) {
      final firstEvent = state.pitEvents.first['event_name']?.toString() ?? '';
      if (firstEvent.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _eventController.text.isEmpty) {
            setState(() {
              _eventController.text = firstEvent;
            });
            _prefillPitEventConfig();
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
                onBack: widget.onBack,
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
                ScheduleRunContainer(
                  state: state,
                  scope: _scope,
                  stageId: _stageId,
                  rubricId: _rubricId,
                  adviserRubricId: _adviserRubricId,
                  capstonePeerRubricId: _capstonePeerRubricId,
                  peerRubricId: _peerRubricId,
                  documenterId: _documenterId,
                  selectedPanelistIds: _selectedPanelistIds,
                  eventController: _eventController,
                  panelWeightController: _panelWeightController,
                  peerWeightController: _peerWeightController,
                  dateController: _dateController,
                  timeController: _timeController,
                  durationController: _durationController,
                  roomController: _roomController,
                  pitTemplateController: _pitTemplateController,
                  planSlots: _planSlots,
                  showFinalPreview: _showFinalPreview,
                  canScheduleScope: _canScheduleScope,
                  scheduleNoticeMessage: _scheduleNoticeMessage,
                  onScopeChanged: (val) => setState(() => _scope = val),
                  onStageChanged: (val) => setState(() => _stageId = val),
                  onRubricChanged: (val) => setState(() => _rubricId = val),
                  onAdviserRubricChanged: (val) => setState(() => _adviserRubricId = val),
                  onCapstonePeerRubricChanged: (val) => setState(() => _capstonePeerRubricId = val),
                  onPeerRubricChanged: (val) => setState(() => _peerRubricId = val),
                  onDocumenterChanged: (val) => setState(() => _documenterId = val),
                  onPanelistsChanged: (val) => setState(() {
                    _selectedPanelistIds.clear();
                    _selectedPanelistIds.addAll(val);
                  }),
                  onPlanSlotsChanged: (val) => setState(() => _planSlots = val),
                  onShowFinalPreviewChanged: (val) => setState(() => _showFinalPreview = val),
                  onPrefillCapstoneStageRubrics: _prefillCapstoneStageRubrics,
                  onPrefillPitEventConfig: _prefillPitEventConfig,
                ),
                if (currentStep == 1) ...[
                  const SizedBox(height: 20),
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
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
