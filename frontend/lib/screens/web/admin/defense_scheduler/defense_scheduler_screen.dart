import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/config/api_config.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/screens/web/admin/admin_shell.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/services/defense_stages_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/defensys_skeleton.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/utils/scheduler/defense_scheduler_draft.dart';
import 'package:defensys/services/app/unsaved_changes_provider.dart';

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
  int _currentStep = 1;

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

  int? _selectedChairId;
  Set<int> _selectedExternalIds = {};
  List<Map<String, dynamic>> _serializedSessions = [];
  Timer? _draftDebounce;
  DateTime? _lastDraftSavedAt;
  bool _hasRestoredDraft = false;
  late final UnsavedChangesNotifier _unsavedNotifier;
  late final UnsavedChangesSaveDraftNotifier _unsavedDraftNotifier;

  @override
  void dispose() {
    _draftDebounce?.cancel();
    releaseUnsavedChangesAfterFrame(_unsavedNotifier, _unsavedDraftNotifier);
    _roomController.removeListener(_scheduleDraftSave);
    _dateController.removeListener(_scheduleDraftSave);
    _timeController.removeListener(_scheduleDraftSave);
    _durationController.removeListener(_scheduleDraftSave);
    _eventController.removeListener(_scheduleDraftSave);
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
    _unsavedNotifier = ref.read(unsavedChangesProvider.notifier);
    _unsavedDraftNotifier = ref.read(unsavedChangesSaveDraftProvider.notifier);
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
    _roomController.addListener(_scheduleDraftSave);
    _dateController.addListener(_scheduleDraftSave);
    _timeController.addListener(_scheduleDraftSave);
    _durationController.addListener(_scheduleDraftSave);
    _eventController.addListener(_scheduleDraftSave);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
      if (!mounted) return;
      await _checkDraft();
      if (!mounted) return;
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

  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    final dirty = _hasUnsavedConfiguration();
    ref.read(unsavedChangesProvider.notifier).setDirty(dirty);
    if (dirty) {
      ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(() async {
        await _persistDraft();
        return true;
      });
    } else {
      ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
    }
    _draftDebounce = Timer(const Duration(milliseconds: 600), () {
      _persistDraft();
    });
  }

  Future<void> _persistDraft({bool showToast = false}) async {
    final semesterId = asInt(ref.read(defenseSchedulerProvider).activeSemester?['id']);
    final draft = DefenseSchedulerDraft(
      scope: _scope,
      savedAt: DateTime.now(),
      semesterId: semesterId,
      stageId: _stageId,
      eventName: _eventController.text.trim(),
      rubricId: _rubricId,
      adviserRubricId: _adviserRubricId,
      capstonePeerRubricId: _capstonePeerRubricId,
      peerRubricId: _peerRubricId,
      panelWeight: _panelWeightController.text.trim(),
      peerWeight: _peerWeightController.text.trim(),
      pitTemplate: _pitTemplateController.text.trim(),
      documenterId: _documenterId,
      selectedPanelistIds: _selectedPanelistIds.toList(),
      selectedChairId: _selectedChairId,
      externalIds: _selectedExternalIds.toList(),
      sessions: _serializedSessions,
      planSlots: _planSlots,
      showFinalPreview: _showFinalPreview,
    );
    if (!draft.hasContent) return;
    await saveDefenseSchedulerDraft(draft);
    if (mounted) {
      setState(() => _lastDraftSavedAt = draft.savedAt);
      if (showToast) {
        showSuccessToast(context, 'Schedule draft saved.');
      }
    }
  }

  Future<void> _checkDraft() async {
    final semesterId = asInt(ref.read(defenseSchedulerProvider).activeSemester?['id']);
    final draft = await loadDefenseSchedulerDraft(scope: _scope, semesterId: semesterId);
    if (!mounted || draft == null) return;

    setState(() {
      _lastDraftSavedAt = draft.savedAt;
      if (draft.stageId != null) _stageId = draft.stageId;
      if (draft.eventName.isNotEmpty) _eventController.text = draft.eventName;
      if (draft.rubricId != null) _rubricId = draft.rubricId;
      if (draft.adviserRubricId != null) _adviserRubricId = draft.adviserRubricId;
      if (draft.capstonePeerRubricId != null) _capstonePeerRubricId = draft.capstonePeerRubricId;
      if (draft.peerRubricId != null) _peerRubricId = draft.peerRubricId;
      if (draft.panelWeight.isNotEmpty) _panelWeightController.text = draft.panelWeight;
      if (draft.peerWeight.isNotEmpty) _peerWeightController.text = draft.peerWeight;
      if (draft.pitTemplate.isNotEmpty) _pitTemplateController.text = draft.pitTemplate;
      if (draft.documenterId != null) _documenterId = draft.documenterId;
      _selectedPanelistIds.clear();
      _selectedPanelistIds.addAll(draft.selectedPanelistIds);
      _selectedChairId = draft.selectedChairId;
      _selectedExternalIds = draft.externalIds.toSet();
      _serializedSessions = List.from(draft.sessions);
      _planSlots = List.from(draft.planSlots);
      _showFinalPreview = draft.showFinalPreview;
      if (_serializedSessions.isNotEmpty) {
        final first = _serializedSessions.first;
        final roomText = first['room']?.toString() ?? '';
        if (roomText.isNotEmpty) _roomController.text = roomText;
        final dateText = first['date']?.toString() ?? '';
        if (dateText.isNotEmpty) _dateController.text = dateText;
        final startText = first['start']?.toString() ?? '';
        if (startText.isNotEmpty) _timeController.text = startText;
        final durText = first['duration']?.toString() ?? '';
        if (durText.isNotEmpty) _durationController.text = durText;
      }
      _currentStep = draft.showFinalPreview ? 3 : (draft.planSlots.isNotEmpty ? 2 : 1);
      _hasRestoredDraft = true;
    });
  }

  Future<void> _discardDraft() async {
    _draftDebounce?.cancel();
    ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
    ref.read(unsavedChangesProvider.notifier).setDirty(false);
    final semesterId = asInt(ref.read(defenseSchedulerProvider).activeSemester?['id']);
    await clearDefenseSchedulerDraft(scope: _scope, semesterId: semesterId);
    if (!mounted) return;
    setState(() {
      _hasRestoredDraft = false;
      _lastDraftSavedAt = null;
      _planSlots = [];
      _showFinalPreview = false;
      _currentStep = 1;
      _serializedSessions = [];
      _selectedPanelistIds.clear();
      _selectedChairId = null;
      _selectedExternalIds.clear();
      _roomController.clear();
      _timeController.text = '08:00';
      _durationController.text = '60';
      _dateController.text = DateTime.now().toIso8601String().substring(0, 10);
    });
    showSuccessToast(context, 'Schedule draft discarded.');
  }

  bool _hasUnsavedConfiguration() {
    if (_planSlots.isNotEmpty) return true;
    if (_roomController.text.trim().isNotEmpty) return true;
    for (final s in _serializedSessions) {
      final teamIds = (s['team_ids'] as List?) ?? [];
      final room = s['room']?.toString().trim() ?? '';
      if (teamIds.isNotEmpty || room.isNotEmpty) return true;
    }
    return false;
  }

  String _formatSavedAt(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _handleBackRequested() async {
    _draftDebounce?.cancel();
    final isDirty = _planSlots.isNotEmpty || _hasUnsavedConfiguration();
    if (!isDirty) {
      widget.onBack?.call();
      return;
    }

    final totalAssigned = _planSlots.length;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        return AlertDialog(
          surfaceTintColor: Colors.transparent,
          backgroundColor: isDark ? DefensysTokens.mistSurface : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Unsaved Defense Schedule',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                totalAssigned > 0
                    ? 'You have an arranged schedule with $totalAssigned assigned ${totalAssigned == 1 ? 'team' : 'teams'} that has not been saved or published yet.'
                    : 'You have session details configured that have not been generated or published yet.',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? DefensysTokens.textSecondaryDark : DefensysTokens.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Would you like to save this draft to resume later, or discard your changes and return to Defense Operations?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? DefensysTokens.textPrimaryDark : DefensysTokens.textPrimary,
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, 'cancel'),
                  child: const Text('Keep Editing'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: DefensysTokens.danger,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, 'discard'),
                  child: const Text('Discard & Exit'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? DefensysTokens.saveActionBg : const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(dialogContext, 'save_draft'),
                  icon: const Icon(Icons.bookmark_border_rounded, size: 16),
                  label: const Text('Save Draft & Exit'),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (action == 'discard') {
      final semesterId = asInt(ref.read(defenseSchedulerProvider).activeSemester?['id']);
      await clearDefenseSchedulerDraft(scope: _scope, semesterId: semesterId);
      if (mounted) widget.onBack?.call();
    } else if (action == 'save_draft') {
      await _persistDraft();
      if (mounted) {
        showSuccessToast(context, 'Schedule draft saved. You can resume anytime.');
        widget.onBack?.call();
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
      final targetStageId =
          state.currentCapstoneStageId ?? asInt(stages.first['id']);

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

    final currentStep = _currentStep;

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

    ref.listen<DefensysAdminSection>(
      activeAdminSectionProvider,
      (previous, next) {
        if (next == DefensysAdminSection.scheduling) {
          ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
        }
      },
    );

    final activeStageOrEventName = _scope == 'capstone'
        ? _stageLabel(state)
        : _eventController.text.trim();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleBackRequested();
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? DefensysTokens.mistBackground : DefensysUi.bgLight,
        body: RefreshIndicator(
          color: AppColors.maroon,
          onRefresh: () =>
              ref.read(defenseSchedulerProvider.notifier).fetchSchedules(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: MediaQuery.sizeOf(context).width < 640
                ? const EdgeInsets.fromLTRB(16, 20, 16, 24)
                : DefensysUi.contentPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SchedulerToolbar(
                  state: state,
                  onBack: _handleBackRequested,
                ),
                if (_hasRestoredDraft && _lastDraftSavedAt != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF8FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFBFDBFE),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.history_rounded,
                          color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'In-progress draft restored from ${_formatSavedAt(_lastDraftSavedAt!)}. Continue editing or discard.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF1E40AF),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _discardDraft,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          ),
                          child: const Text('Discard Draft'),
                        ),
                      ],
                    ),
                  ),
                ],
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
                    currentStep: _currentStep,
                    onStepChanged: (step) {
                      setState(() {
                        _currentStep = step;
                        _showFinalPreview = step == 3;
                      });
                      _scheduleDraftSave();
                    },
                    canScheduleScope: _canScheduleScope,
                    scheduleNoticeMessage: _scheduleNoticeMessage,
                    initialSessions: _serializedSessions,
                    onSessionsChanged: (sessions) {
                      _serializedSessions = sessions;
                      _scheduleDraftSave();
                    },
                    initialChairId: _selectedChairId,
                    onChairChanged: (id) {
                      _selectedChairId = id;
                      _scheduleDraftSave();
                    },
                    initialExternalIds: _selectedExternalIds,
                    onExternalIdsChanged: (ids) {
                      _selectedExternalIds = ids;
                      _scheduleDraftSave();
                    },
                    onSuccess: () async {
                      _draftDebounce?.cancel();
                      ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
                      ref.read(unsavedChangesProvider.notifier).setDirty(false);
                      final semesterId = asInt(ref.read(defenseSchedulerProvider).activeSemester?['id']);
                      await clearDefenseSchedulerDraft(scope: _scope, semesterId: semesterId);
                      if (mounted) {
                        widget.onBack?.call();
                      }
                    },
                    onScopeChanged: (val) {
                      setState(() => _scope = val);
                      _scheduleDraftSave();
                    },
                    onStageChanged: (val) {
                      setState(() => _stageId = val);
                      _scheduleDraftSave();
                    },
                    onRubricChanged: (val) {
                      setState(() => _rubricId = val);
                      _scheduleDraftSave();
                    },
                    onAdviserRubricChanged: (val) {
                      setState(() => _adviserRubricId = val);
                      _scheduleDraftSave();
                    },
                    onCapstonePeerRubricChanged: (val) {
                      setState(() => _capstonePeerRubricId = val);
                      _scheduleDraftSave();
                    },
                    onPeerRubricChanged: (val) {
                      setState(() => _peerRubricId = val);
                      _scheduleDraftSave();
                    },
                    onDocumenterChanged: (val) {
                      setState(() => _documenterId = val);
                      _scheduleDraftSave();
                    },
                    onPanelistsChanged: (val) {
                      setState(() {
                        _selectedPanelistIds.clear();
                        _selectedPanelistIds.addAll(val);
                      });
                      _scheduleDraftSave();
                    },
                    onPlanSlotsChanged: (val) {
                      setState(() => _planSlots = val);
                      _scheduleDraftSave();
                    },
                    onShowFinalPreviewChanged: (val) {
                      setState(() => _showFinalPreview = val);
                      _scheduleDraftSave();
                    },
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
      ),
    );
  }
}
