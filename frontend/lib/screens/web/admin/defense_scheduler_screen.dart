import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../services/defense_scheduler_provider.dart';
import '../../../services/defense_stages_provider.dart';
import '../../../services/capstone_deliverables_provider.dart';
import '../../../config/api_config.dart';
import '../../../services/authenticated_client.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/defense_schedule_import_parser.dart';
import '../../../utils/csv_file_io.dart';
import '../../../widgets/defensys_skeleton.dart';
import '../../../widgets/feedback_toast.dart';
import 'widgets/defensys_admin_shell.dart';

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
  final _trackerSearchController = TextEditingController();

  final Set<int> _selectedPanelistIds = {};
  List<Map<String, dynamic>> _pitDeliverables = [];

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
    _trackerSearchController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(defenseSchedulerProvider);
    _initializeScopeFromState(state);
    final currentStep = _planSlots.isEmpty ? 1 : (_showFinalPreview ? 3 : 2);

    ref.listen(defenseSchedulerProvider, (previous, next) {
      _applySchedulerMode(next, previous: previous);

      final error = next.error;
      if (error != null && error.isNotEmpty && error != previous?.error) {
        showErrorToast(context, error);
      }

      final message = next.message;
      if (message != null &&
          message.isNotEmpty &&
          message != previous?.message) {
        showSuccessToast(context, message);
      }
    });

    final cp = DefensysUi.contentPadding;

    return Scaffold(
      backgroundColor: DefensysUi.bgLight,
      body: RefreshIndicator(
        color: AppColors.maroon,
        onRefresh: () =>
            ref.read(defenseSchedulerProvider.notifier).fetchSchedules(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: cp,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(state),
              const SizedBox(height: 26),
              _buildStepProgress(currentStep),
              const SizedBox(height: 12),
              if (_scheduleNoticeMessage(state).isNotEmpty) ...[
                _buildScheduleNotice(state),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 12),
              if (state.isLoading &&
                  state.schedules.isEmpty &&
                  state.teams.isEmpty) ...[
                DefensysSkeleton.list(count: 4, rowHeight: 64),
              ] else ...[
                if (currentStep == 1) ...[
                  _buildStepOne(state),
                  const SizedBox(height: 20),
                  _buildTeamReadinessTracker(state),
                ],
                if (currentStep == 2) _buildStepTwo(state),
                if (currentStep == 3) _buildStepThree(state),
                const SizedBox(height: 22),
                _buildExistingSchedules(state),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _applySchedulerMode(
    DefenseSchedulerState next, {
    DefenseSchedulerState? previous,
  }) {
    final targetScope = _explicitScopeFromSchedulerState(next);
    if (targetScope.isEmpty) {
      return;
    }
    final modeChanged =
        previous?.schedulerMode != next.schedulerMode ||
        previous?.canSchedulePit != next.canSchedulePit ||
        previous?.canScheduleCapstone != next.canScheduleCapstone;
    if (!modeChanged || targetScope == _scope) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || targetScope == _scope) {
        return;
      }
      setState(() {
        _scopeInitializedFromState = true;
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

  void _initializeScopeFromState(DefenseSchedulerState state) {
    if (_scopeInitializedFromState) {
      return;
    }
    final targetScope = _explicitScopeFromSchedulerState(state);
    if (targetScope.isEmpty) {
      return;
    }
    _scopeInitializedFromState = true;
    if (targetScope == _scope) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || targetScope == _scope) {
        return;
      }
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

  String _explicitScopeFromSchedulerState(DefenseSchedulerState state) {
    if (state.schedulerMode == 'pit' || state.schedulerMode == 'capstone') {
      return state.schedulerMode;
    }
    if (state.canScheduleCapstone) {
      return 'capstone';
    }
    if (state.canSchedulePit) {
      return 'pit';
    }
    return '';
  }

  bool _canScheduleScope(DefenseSchedulerState state, String scope) {
    if (scope == 'pit') {
      return state.canSchedulePit;
    }
    if (scope == 'capstone') {
      return state.canScheduleCapstone;
    }
    return false;
  }

  bool _canScheduleCurrentScope(DefenseSchedulerState state) {
    return _canScheduleScope(state, _scope);
  }

  String _scheduleNoticeMessage(DefenseSchedulerState state) {
    final message = state.operatingMessage?.trim() ?? '';
    if (message.isNotEmpty) {
      return message;
    }
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

  Widget _buildScheduleNotice(DefenseSchedulerState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF92400E),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _scheduleNoticeMessage(state),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(DefenseSchedulerState state) {
    final semesterLabel =
        state.activeSemester?['display_name']?.toString() ??
        'No active semester configured';

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
                    Icons.auto_awesome_mosaic_rounded,
                    color: AppColors.maroon,
                    size: 24,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Defense Scheduler',
                    style: TextStyle(
                      color: AppColors.maroon,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                semesterLabel,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              height: 42,
              child: OutlinedButton.icon(
                onPressed: state.isSaving || !_canScheduleCurrentScope(state)
                    ? null
                    : () => _showManualDialog(state),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Manual Schedule Form'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFD0D5DD)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 0,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 42,
              child: ElevatedButton.icon(
                onPressed: state.isSaving || !_canScheduleCurrentScope(state)
                    ? null
                    : () => _showImportDialog(state),
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('Import Schedule'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.maroon,
                  foregroundColor: AppColors.gold,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 0,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStepProgress(int currentStep) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _stepProgressTile(
              number: 1,
              title: 'Set Up Scheduling Run',
              subtitle: 'Choose the shared inputs for this batch.',
              isActive: currentStep == 1,
              isDone: currentStep > 1,
              isFirst: true,
            ),
          ),
          Expanded(
            child: _stepProgressTile(
              number: 2,
              title: 'Review & Arrange Teams',
              subtitle: 'Waiting for Step 1 plan generation.',
              isActive: currentStep == 2,
              isDone: currentStep > 2,
            ),
          ),
          Expanded(
            child: _stepProgressTile(
              number: 3,
              title: 'Final Schedule Preview',
              subtitle: 'Shown after the schedule plan is generated.',
              isActive: currentStep == 3,
              isDone: false,
              isLast: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepProgressTile({
    required int number,
    required String title,
    required String subtitle,
    required bool isActive,
    required bool isDone,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final Color accent = isActive
        ? AppColors.maroon
        : (isDone ? AppColors.success : const Color(0xFFD0D5DD));

    final Color bg = isActive
        ? const Color(0xFFFDF2F2)
        : (isDone ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC));

    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isFirst ? 14 : 0),
          bottomLeft: Radius.circular(isFirst ? 14 : 0),
          topRight: Radius.circular(isLast ? 14 : 0),
          bottomRight: Radius.circular(isLast ? 14 : 0),
        ),
        border: Border(
          bottom: BorderSide(
            color: accent,
            width: isActive || isDone ? 3 : 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive || isDone
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepOne(DefenseSchedulerState state) {
    final stages = state.defenseStages;
    final stageId = stages.any((stage) => _asInt(stage['id']) == _stageId)
        ? _stageId
        : null;

    final rubricItems = _rubricsForContext(state);
    final rubricId =
        rubricItems.any((rubric) => _asInt(rubric['id']) == _rubricId)
        ? _rubricId
        : null;

    final selectedPanelists = state.panelists.where((panelist) {
      final id = _asInt(panelist['id']);
      return id != null && _selectedPanelistIds.contains(id);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 1120;

        final left = _schedulerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: AppColors.maroon,
                          child: Text(
                            '1',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Step 1: Set Up Scheduling Run',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEECEC),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Required First',
                      style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 20),
              Text(
                _scope == 'pit'
                    ? 'Choose the PIT event, rubrics, date, room, start time, and slot duration for this run. Then generate the plan to prepare consecutive slots.'
                    : 'Choose the shared stage, rubric, date, room, start time, and slot duration for this run. Then generate the plan to prepare consecutive slots.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              if (_scope == 'capstone') ...[
                _labeledField(
                  'Stage *',
                  DropdownButtonFormField<int?>(
                    initialValue: stageId,
                    decoration: _schedulerInputDecoration(),
                    items: stages
                        .map(
                          (stage) => DropdownMenuItem<int?>(
                            value: _asInt(stage['id']),
                            child: Text(stage['label']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (value) async {
                      setState(() {
                        _scope = 'capstone';
                        _stageId = value;
                        _rubricId = null;
                        _adviserRubricId = null;
                        _capstonePeerRubricId = null;
                        _planSlots = [];
                        _showFinalPreview = false;
                      });
                      await _prefillCapstoneStageRubrics();
                    },
                  ),
                ),
              ] else if (_scope == 'pit') ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4E7EC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PIT event setup (this run)',
                        style: TextStyle(
                          color: Color(0xFF344054),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _labeledField(
                        'Event name *',
                        DropdownButtonFormField<String>(
                          value: state.pitEvents.any((e) => e['event_name'] == _eventController.text)
                              ? _eventController.text
                              : null,
                          decoration: _schedulerInputDecoration(
                            hintText: 'Select PIT event',
                          ),
                          items: state.pitEvents.map((e) {
                            final name = e['event_name']?.toString() ?? '';
                            return DropdownMenuItem<String>(
                              value: name,
                              child: Text(name),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              _eventController.text = val;
                              _prefillPitEventConfig();
                              setState(() {});
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _labeledField(
                      'Date *',
                      _scheduleDateField(controller: _dateController),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _labeledField(
                      'Starting Time *',
                      _scheduleTimeField(controller: _timeController),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _labeledField(
                      'Slot Duration (mins) *',
                      TextField(
                        controller: _durationController,
                        keyboardType: TextInputType.number,
                        decoration: _schedulerInputDecoration(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _labeledField(
                'Room / Venue *',
                TextField(
                  controller: _roomController,
                  decoration: _schedulerInputDecoration(
                    hintText: 'Enter room or venue',
                  ),
                ),
              ),
              if (_scope == 'capstone' || _scope == 'pit') ...[
                const SizedBox(height: 20),
                Container(
                  key: ValueKey('stage-info-$_scope-${_scope == 'capstone' ? _stageId : _eventController.text.trim()}'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF9FAFB),
                    border: Border(
                      top: BorderSide(color: Color(0xFFE5E7EB)),
                      bottom: BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _softBadge(
                        _scope == 'capstone'
                            ? 'Stage: ${_stageLabel(state)}'
                            : 'Event: ${_eventController.text.trim().isEmpty ? "None" : _eventController.text.trim()}',
                        const Color(0xFFDCFCE7),
                        const Color(0xFF166534),
                      ),
                      _softBadge(
                        'Ready Teams: ${_readyTeamsCount(state)}',
                        _readyTeamsCount(state) > 0
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFFEF3C7),
                        _readyTeamsCount(state) > 0
                            ? const Color(0xFF166534)
                            : const Color(0xFFB45309),
                      ),
                      _softBadge(
                        'Blocked: 0',
                        const Color(0xFFFEF3C7),
                        const Color(0xFFB45309),
                      ),
                      _softBadge(
                        'Already Scheduled: ${_count(state, 'scheduled')}',
                        const Color(0xFFDBEAFE),
                        const Color(0xFF1D4ED8),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ] else
                const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Step 1 Action',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Generate the schedule plan after completing the run setup and panel selection.\nThis unlocks the team review workspace.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed:
                        state.isSaving || !_canScheduleCurrentScope(state)
                        ? null
                        : _generatePlan,
                    icon: const Icon(Icons.bolt_rounded, size: 18),
                    label: const Text('Generate Schedule Plan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.maroon,
                      foregroundColor: AppColors.gold,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        final right = _schedulerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.groups_2_rounded,
                    color: AppColors.maroon,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Panel Set',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Included in this scheduling run and applied to every generated row.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD0D5DD)),
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: const Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Search panelists...',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (state.panelists.isEmpty)
                const Text(
                  'No faculty panelists found. Assign panelist roles in User Management first.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                )
              else
                ...state.panelists.map((panelist) {
                  final id = _asInt(panelist['id']);
                  final selected =
                      id != null && _selectedPanelistIds.contains(id);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: id == null
                          ? null
                          : () {
                              setState(() {
                                if (selected) {
                                  _selectedPanelistIds.remove(id);
                                } else {
                                  _selectedPanelistIds.add(id);
                                }
                                _planSlots = [];
                                _showFinalPreview = false;
                              });
                            },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFFEF2F2)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? AppColors.maroon
                                : const Color(0xFFD0D5DD),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: selected,
                              activeColor: AppColors.maroon,
                              onChanged: id == null
                                  ? null
                                  : (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedPanelistIds.add(id);
                                        } else {
                                          _selectedPanelistIds.remove(id);
                                        }
                                        _planSlots = [];
                                        _showFinalPreview = false;
                                      });
                                    },
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    panelist['name']?.toString() ?? '',
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${panelist['username'] ?? ''} · Panelist',
                                    style: const TextStyle(
                                      color: AppColors.maroon,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              if (selectedPanelists.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'The selected panel is applied to every generated row in this batch. Row-level validation will still catch adviser or overlap conflicts for specific teams.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        );

        if (narrow) {
          return Column(children: [left, const SizedBox(height: 18), right]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: left),
            const SizedBox(width: 18),
            Expanded(flex: 1, child: right),
          ],
        );
      },
    );
  }

  Widget _buildStepTwo(DefenseSchedulerState state) {
    return _schedulerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.rule_folder_outlined,
                color: AppColors.maroon,
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Step 2: Review & Arrange Teams',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Review the generated schedule slots. Remove any teams you want to exclude from this batch.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                _planTableHeader(const [
                  '#',
                  'Team',
                  'Stage',
                  'Date',
                  'Time Slot',
                  'Room',
                  'Panel',
                  'Action',
                ]),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _planSlots.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) {
                        newIndex -= 1;
                      }
                      final item = _planSlots.removeAt(oldIndex);
                      _planSlots.insert(newIndex, item);
                      _recalculatePlanSlots();
                    });
                  },
                  itemBuilder: (context, index) {
                    final slot = _planSlots[index];
                    return _planTableRow(
                      key: ValueKey('${slot['team_id']}-$index'),
                      index: index,
                      team: slot['team_name']?.toString() ?? '',
                      stage: slot['stage_label']?.toString() ?? '',
                      date: slot['scheduled_date']?.toString() ?? '',
                      time:
                          '${_shortTime(slot['start_time'])} - ${_shortTime(slot['end_time'])}',
                      room: slot['room']?.toString() ?? '',
                      panel:
                          slot['panelist_names']?.toString().isNotEmpty == true
                          ? slot['panelist_names']?.toString() ?? ''
                          : _panelNamesFromSelection(state),
                      onDelete: () {
                        setState(() {
                          _planSlots.removeAt(index);
                          _recalculatePlanSlots();
                        });
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _planSlots = [];
                    _showFinalPreview = false;
                  });
                },
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFD0D5DD)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _planSlots.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _showFinalPreview = true;
                        });
                      },
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Review & Confirm'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.maroon,
                  foregroundColor: AppColors.gold,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepThree(DefenseSchedulerState state) {
    final stageText = _scope == 'pit'
        ? _eventController.text.trim()
        : _stageLabel(state);
    final selectedPanel = _panelNamesFromSelection(state);

    return _schedulerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.visibility_outlined,
                color: AppColors.maroon,
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Step 3: Final Schedule Preview',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Review the final schedule before saving. This cannot be undone.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1320,
              child: Row(
                children: [
                  Expanded(
                    child: _summaryInfoCard(
                      'STAGE',
                      stageText,
                      Icons.event_note_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _summaryInfoCard(
                      'DATE',
                      _dateController.text.trim(),
                      Icons.calendar_today_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _summaryInfoCard(
                      'ROOM',
                      _roomController.text.trim(),
                      Icons.meeting_room_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _summaryInfoCard(
                      'SLOT',
                      '${_durationController.text.trim()} mins each',
                      Icons.timelapse_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _summaryInfoCard(
                      'PANEL',
                      selectedPanel,
                      Icons.groups_2_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _summaryInfoCard(
                      'TEAMS',
                      '${_planSlots.length} teams',
                      Icons.group_outlined,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: [
                _planTableHeader(const [
                  '#',
                  'Team',
                  'Stage / Event',
                  'Date',
                  'Time Slot',
                  'Room',
                  'Panel',
                ]),
                ...List.generate(_planSlots.length, (index) {
                  final slot = _planSlots[index];
                  return _finalPreviewRow(
                    index: index,
                    team: slot['team_name']?.toString() ?? '',
                    stage: slot['stage_label']?.toString() ?? stageText,
                    date: slot['scheduled_date']?.toString() ?? '',
                    time:
                        '${_shortTime(slot['start_time'])} - ${_shortTime(slot['end_time'])}',
                    room: slot['room']?.toString() ?? '',
                    panel: slot['panelist_names']?.toString().isNotEmpty == true
                        ? slot['panelist_names']?.toString() ?? ''
                        : selectedPanel,
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _showFinalPreview = false;
                  });
                },
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFD0D5DD)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: state.isSaving ? null : _confirmPlan,
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: const Text('Confirm & Save Schedule'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.maroon,
                  foregroundColor: AppColors.gold,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _schedulerCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _labeledField(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  InputDecoration _schedulerInputDecoration({
    Widget? suffixIcon,
    String? hintText,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      hintText: hintText,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.maroon, width: 1.2),
      ),
    );
  }

  Widget _softBadge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _planTableHeader(List<String> headers) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
        ),
      ),
      child: Row(
        children: headers.map((header) {
          final flex = switch (header) {
            '#' => 1,
            'Action' => 1,
            'Date' => 2,
            'Time Slot' => 2,
            'Room' => 2,
            'Panel' => 2,
            'Stage' => 2,
            'Stage / Event' => 2,
            _ => 3,
          };
          return Expanded(
            flex: flex,
            child: Text(
              header,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _planTableRow({
    required Key key,
    required int index,
    required String team,
    required String stage,
    required String date,
    required String time,
    required String room,
    required String panel,
    required VoidCallback onDelete,
  }) {
    return Container(
      key: key,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.drag_indicator_rounded, color: Color(0xFF98A2B3)),
            const SizedBox(width: 10),
            SizedBox(
              width: 24,
              child: Text(
                '${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                team,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(flex: 2, child: Text(stage)),
            Expanded(flex: 2, child: Text(date)),
            Expanded(flex: 2, child: Text(time)),
            Expanded(flex: 2, child: Text(room)),
            Expanded(flex: 2, child: Text(panel)),
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_rounded, color: Colors.blue),
                  tooltip: 'Remove',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _finalPreviewRow({
    required int index,
    required String team,
    required String stage,
    required String date,
    required String time,
    required String room,
    required String panel,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Expanded(flex: 1, child: Text('${index + 1}')),
          Expanded(
            flex: 3,
            child: Text(
              team,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(flex: 3, child: Text(stage)),
          Expanded(flex: 2, child: Text(date)),
          Expanded(flex: 2, child: Text(time)),
          Expanded(flex: 2, child: Text(room)),
          Expanded(flex: 2, child: Text(panel)),
        ],
      ),
    );
  }

  Widget _summaryInfoCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.maroon),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value.isEmpty ? '—' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  String _panelNamesFromSelection(DefenseSchedulerState state) {
    final names = state.panelists
        .where((panelist) {
          final id = _asInt(panelist['id']);
          return id != null && _selectedPanelistIds.contains(id);
        })
        .map((panelist) => panelist['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    if (names.isEmpty) {
      return '—';
    }

    return names.join(', ');
  }

  Future<void> _generatePlan() async {
    final schedulerState = ref.read(defenseSchedulerProvider);
    if (!_canScheduleCurrentScope(schedulerState)) {
      _showSnack(_scheduleNoticeMessage(schedulerState));
      return;
    }

    final payload = _basePayload();
    if (payload == null) {
      return;
    }

    final ok = await ref
        .read(defenseSchedulerProvider.notifier)
        .generatePlan(payload);
    if (!mounted || !ok) {
      return;
    }

    setState(() {
      _planSlots = ref
          .read(defenseSchedulerProvider)
          .generatedSlots
          .map((slot) => Map<String, dynamic>.from(slot))
          .toList();
      _showFinalPreview = false;
      _recalculatePlanSlots();
    });
  }

  Future<void> _confirmPlan() async {
    final payload = _basePayload();
    if (payload == null || _planSlots.isEmpty) {
      return;
    }

    payload['slots'] = _planSlots
        .map((slot) => {'team_id': _asInt(slot['team_id'])})
        .toList();

    final ok = await ref
        .read(defenseSchedulerProvider.notifier)
        .confirmPlan(payload);
    if (!mounted || !ok) {
      return;
    }

    setState(() {
      _planSlots = [];
      _showFinalPreview = false;
    });
  }

  Map<String, dynamic>? _basePayload() {
    final schedulerState = ref.read(defenseSchedulerProvider);
    if (!_canScheduleCurrentScope(schedulerState)) {
      _showSnack(_scheduleNoticeMessage(schedulerState));
      return null;
    }

    final date = _dateController.text.trim();
    final time = _timeController.text.trim();
    final room = _roomController.text.trim();

    if (_scope == 'capstone' && _stageId == null) {
      _showSnack('Select a defense stage.');
      return null;
    }

    if (_scope == 'capstone') {
      if (_validCapstoneRubricId(schedulerState, _rubricId, 'panel') == null ||
          _validCapstoneRubricId(schedulerState, _adviserRubricId, 'adviser') == null ||
          _validCapstoneRubricId(schedulerState, _capstonePeerRubricId, 'peer') == null) {
        _showSnack('Please configure stage rubrics in the Defense Stages tab first.');
        return null;
      }
    }

    if (_scope == 'pit' && _eventController.text.trim().isEmpty) {
      _showSnack('Enter a PIT event name.');
      return null;
    }

    if (_scope == 'pit') {
      if (_validRubricId(ref.read(defenseSchedulerProvider)) == null ||
          _validPeerRubricId(ref.read(defenseSchedulerProvider)) == null) {
        _showSnack('Please configure event rubrics in the PIT Events tab first.');
        return null;
      }
      if (_pitWeightTotal() != 100) {
        _showSnack('Panel and peer weights must total 100%.');
        return null;
      }
    }

    if (date.isEmpty || time.isEmpty || room.isEmpty) {
      _showSnack('Date, time, and room are required.');
      return null;
    }

    if (_selectedPanelistIds.isEmpty) {
      _showSnack('Select at least one panelist.');
      return null;
    }

    final payload = {
      'scope': _scope,
      'defense_stage_id': _scope == 'capstone' ? _stageId : null,
      'event_name': _scope == 'pit' ? _eventController.text.trim() : '',
      'rubric_id': _validRubricId(ref.read(defenseSchedulerProvider)),
      'scheduled_date': date,
      'start_time': time,
      'slot_duration': int.tryParse(_durationController.text.trim()) ?? 60,
      'room': room,
      'panelist_ids': _selectedPanelistIds.toList(),
    };
    if (_scope == 'pit') {
      payload['peer_rubric_id'] = _validPeerRubricId(
        ref.read(defenseSchedulerProvider),
      );
      payload['panel_weight'] =
          int.tryParse(_panelWeightController.text.trim()) ?? 80;
      payload['peer_weight'] =
          int.tryParse(_peerWeightController.text.trim()) ?? 20;
      payload['vault_file_template'] = _pitTemplateController.text.trim();
    }
    return payload;
  }

  int _pitWeightTotal() {
    final panel = int.tryParse(_panelWeightController.text.trim()) ?? 0;
    final peer = int.tryParse(_peerWeightController.text.trim()) ?? 0;
    return panel + peer;
  }

  Future<void> _prefillPitEventConfig() async {
    if (_scope != 'pit') {
      return;
    }
    final eventName = _eventController.text.trim();
    if (eventName.length < 3) {
      return;
    }
    final semesterId = _asInt(
      ref.read(defenseSchedulerProvider).activeSemester?['id'],
    );
    final config = await ref
        .read(defenseSchedulerProvider.notifier)
        .fetchPitEventConfig(eventName: eventName, semesterId: semesterId);
    if (!mounted || config == null) {
      return;
    }
    for (final d in _pitDeliverables) {
      (d['_labelController'] as TextEditingController?)?.dispose();
      (d['_vaultNoteController'] as TextEditingController?)?.dispose();
    }
    setState(() {
      _rubricId = _asInt(config['panel_rubric_id']) ?? _rubricId;
      _peerRubricId = _asInt(config['peer_rubric_id']) ?? _peerRubricId;
      _panelWeightController.text = config['panel_weight']?.toString() ?? '80';
      _peerWeightController.text = config['peer_weight']?.toString() ?? '20';
      _pitTemplateController.text =
          config['vault_file_template']?.toString() ?? '';
      _pitDeliverables = [];
      if (config['deliverables'] is List) {
        for (final d in config['deliverables']) {
          _pitDeliverables.add({
            'deliverable_id': d['deliverable_id']?.toString() ?? '',
            'label': d['label']?.toString() ?? '',
            'required': d['required'] == true,
            'vault_note': d['vault_note']?.toString() ?? '',
            'display_order': _asInt(d['display_order']) ?? 1,
          });
        }
      }
    });
  }

  Future<void> _showManualDialog(DefenseSchedulerState state) async {
    if (!_canScheduleCurrentScope(state)) {
      _showSnack(_scheduleNoticeMessage(state));
      return;
    }

    String scope = _scope;
    int? stageId = _stageId;
    int? teamId;
    int? rubricId = _rubricId;
    int? adviserRubricId = _adviserRubricId;
    int? capstonePeerRubricId = _capstonePeerRubricId;
    int? peerRubricId = _peerRubricId;
    final panelWeight = TextEditingController(
      text: _panelWeightController.text,
    );
    final peerWeight = TextEditingController(text: _peerWeightController.text);

    final event = TextEditingController(text: _eventController.text);
    final vaultFileTemplate = TextEditingController(
      text: _pitTemplateController.text,
    );
    final date = TextEditingController(text: _dateController.text);
    final time = TextEditingController(text: _timeController.text);
    final duration = TextEditingController(text: _durationController.text);
    final room = TextEditingController(text: _roomController.text);
    final panelIds = <int>{..._selectedPanelistIds};

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final teams = _teamsForScope(state, scope);
            final contextRubrics = _rubricsForScopeAndStage(
              state,
              scope,
              stageId,
            );
            final panelRubrics = contextRubrics
                .where(
                  (rubric) => rubric['evaluation_type']?.toString() == 'panel',
                )
                .toList();
            final adviserRubrics = contextRubrics
                .where(
                  (rubric) =>
                      rubric['evaluation_type']?.toString() == 'adviser',
                )
                .toList();
            final capstonePeerRubrics = contextRubrics
                .where(
                  (rubric) => rubric['evaluation_type']?.toString() == 'peer',
                )
                .toList();

            final peerRubrics = _peerRubricsForContext(state);
            final validRubric =
                panelRubrics.any((item) => _asInt(item['id']) == rubricId)
                ? rubricId
                : null;
            final validAdviserRubric =
                adviserRubrics.any(
                  (item) => _asInt(item['id']) == adviserRubricId,
                )
                ? adviserRubricId
                : null;
            final validCapstonePeerRubric =
                capstonePeerRubrics.any(
                  (item) => _asInt(item['id']) == capstonePeerRubricId,
                )
                ? capstonePeerRubricId
                : null;
            final validPeerRubric =
                peerRubrics.any((item) => _asInt(item['id']) == peerRubricId)
                ? peerRubricId
                : null;

            final validTeam = teams.any((item) => _asInt(item['id']) == teamId)
                ? teamId
                : null;

            return AlertDialog(
              title: const Text('Manual Schedule Form'),
              content: SizedBox(
                width: 680,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: scope,
                              decoration: const InputDecoration(
                                labelText: 'Scope',
                              ),
                              items: _allowedScopeItems(state),
                              onChanged: (value) {
                                setDialogState(() {
                                  scope = value ?? scope;
                                  stageId = null;
                                  teamId = null;
                                  rubricId = null;
                                  adviserRubricId = null;
                                  capstonePeerRubricId = null;
                                  peerRubricId = null;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int?>(
                              initialValue: validTeam,
                              decoration: const InputDecoration(
                                labelText: 'Team',
                              ),
                              items: teams
                                  .map(
                                    (team) => DropdownMenuItem<int?>(
                                      value: _asInt(team['id']),
                                      child: Text(
                                        team['name']?.toString() ?? '',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setDialogState(() {
                                  teamId = value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (scope == 'capstone')
                        DropdownButtonFormField<int?>(
                          initialValue: stageId,
                          decoration: const InputDecoration(
                            labelText: 'Defense Stage',
                          ),
                          items: state.defenseStages
                              .map(
                                (stage) => DropdownMenuItem<int?>(
                                  value: _asInt(stage['id']),
                                  child: Text(stage['label']?.toString() ?? ''),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              stageId = value;
                              rubricId = null;
                              adviserRubricId = null;
                              capstonePeerRubricId = null;
                            });
                          },
                        )
                      else ...[
                        DropdownButtonFormField<String>(
                          value: state.pitEvents.any((e) => e['event_name'] == event.text)
                              ? event.text
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'PIT Event Name',
                          ),
                          items: state.pitEvents.map((e) {
                            final name = e['event_name']?.toString() ?? '';
                            return DropdownMenuItem<String>(
                              value: name,
                              child: Text(name),
                            );
                          }).toList(),
                          onChanged: (val) async {
                            if (val != null) {
                              event.text = val;
                              final eventName = val.trim();
                              final semesterId = _asInt(
                                ref
                                    .read(defenseSchedulerProvider)
                                    .activeSemester?['id'],
                              );
                              final config = await ref
                                  .read(defenseSchedulerProvider.notifier)
                                  .fetchPitEventConfig(
                                    eventName: eventName,
                                    semesterId: semesterId,
                                  );
                              if (config != null) {
                                setDialogState(() {
                                  rubricId =
                                      _asInt(config['panel_rubric_id']) ??
                                      rubricId;
                                  peerRubricId =
                                      _asInt(config['peer_rubric_id']) ??
                                      peerRubricId;
                                  panelWeight.text =
                                      config['panel_weight']?.toString() ??
                                      '80';
                                  peerWeight.text =
                                      config['peer_weight']?.toString() ?? '20';
                                  vaultFileTemplate.text =
                                      config['vault_file_template']
                                          ?.toString() ??
                                      '';
                                });
                              }
                            } else {
                              setDialogState(() {});
                            }
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _scheduleDateField(
                              controller: date,
                              onSelected: () => setDialogState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Date',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _scheduleTimeField(
                              controller: time,
                              onSelected: () => setDialogState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Start Time',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: room,
                              decoration: const InputDecoration(
                                labelText: 'Room',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: duration,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Duration',
                                suffixText: 'mins',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Panelists (${panelIds.length})',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: state.panelists.map((panelist) {
                          final id = _asInt(panelist['id']);
                          final selected = id != null && panelIds.contains(id);

                          return FilterChip(
                            selected: selected,
                            label: Text(panelist['name']?.toString() ?? ''),
                            onSelected: id == null
                                ? null
                                : (value) {
                                    setDialogState(() {
                                      if (value) {
                                        panelIds.add(id);
                                      } else {
                                        panelIds.remove(id);
                                      }
                                    });
                                  },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Save Schedule'),
                ),
              ],
            );
          },
        );
      },
    );

    final eventText = event.text.trim();
    final panelWeightText = panelWeight.text.trim();
    final peerWeightText = peerWeight.text.trim();
    final dateText = date.text.trim();
    final timeText = time.text.trim();
    final durationText = duration.text.trim();
    final roomText = room.text.trim();

    event.dispose();
    vaultFileTemplate.dispose();
    panelWeight.dispose();
    peerWeight.dispose();
    date.dispose();
    time.dispose();
    duration.dispose();
    room.dispose();

    if (!mounted || saved != true) {
      return;
    }

    if (teamId == null || panelIds.isEmpty) {
      _showSnack('Team and panelists are required.');
      return;
    }

    if (scope == 'capstone') {
      if (stageId == null) {
        _showSnack('Select a defense stage.');
        return;
      }
      setState(() {
        _scope = scope;
        _stageId = stageId;
      });
    } else {
      if (eventText.isEmpty) {
        _showSnack('Enter a PIT event name.');
        return;
      }
      setState(() {
        _scope = scope;
        _eventController.text = eventText;
      });
    }

    final schedulePayload = {
      'scope': scope,
      'team_id': teamId,
      'defense_stage_id': scope == 'capstone' ? stageId : null,
      'event_name': scope == 'pit' ? eventText : '',
      'rubric_id': rubricId,
      'scheduled_date': dateText,
      'start_time': timeText,
      'slot_duration': int.tryParse(durationText) ?? 60,
      'room': roomText,
      'panelist_ids': panelIds.toList(),
    };
    if (scope == 'pit') {
      schedulePayload['peer_rubric_id'] = peerRubricId;
      schedulePayload['panel_weight'] = int.tryParse(panelWeightText) ?? 80;
      schedulePayload['peer_weight'] = int.tryParse(peerWeightText) ?? 20;
      schedulePayload['vault_file_template'] = vaultFileTemplate.text.trim();
    }
    await ref
        .read(defenseSchedulerProvider.notifier)
        .createSchedule(schedulePayload);
  }



  Future<void> _prefillCapstoneStageRubrics() async {
    if (_scope != 'capstone' || _stageId == null) {
      return;
    }
    final semesterId = _asInt(
      ref.read(defenseSchedulerProvider).activeSemester?['id'],
    );
    if (semesterId == null) {
      return;
    }
    final detail = await ref
        .read(defenseStagesProvider.notifier)
        .fetchStageDetail(_stageId!, semesterId: semesterId);
    if (!mounted || detail == null) {
      return;
    }
    final grading = detail['grading_config'];
    if (grading is! Map) {
      return;
    }
    setState(() {
      _rubricId = _asInt(grading['panel_rubric_id']) ?? _rubricId;
      _adviserRubricId =
          _asInt(grading['adviser_rubric_id']) ?? _adviserRubricId;
      _capstonePeerRubricId =
          _asInt(grading['peer_rubric_id']) ?? _capstonePeerRubricId;
    });
  }

  Future<Map<String, int?>> _stageRubricIds(int stageId) async {
    final semesterId = _asInt(
      ref.read(defenseSchedulerProvider).activeSemester?['id'],
    );
    if (semesterId == null) {
      return {};
    }
    final detail = await ref
        .read(defenseStagesProvider.notifier)
        .fetchStageDetail(stageId, semesterId: semesterId);
    final grading = detail?['grading_config'];
    if (grading is! Map) {
      return {};
    }
    return {
      'panel': _asInt(grading['panel_rubric_id']),
      'adviser': _asInt(grading['adviser_rubric_id']),
      'peer': _asInt(grading['peer_rubric_id']),
    };
  }

  Future<void> _showImportDialog(DefenseSchedulerState state) async {
    if (!_canScheduleCurrentScope(state)) {
      _showSnack(_scheduleNoticeMessage(state));
      return;
    }

    final importScope = _scope;
    final isPit = importScope == 'pit';

    ParsedScheduleImport? parsed;
    String? fileName;
    int? importStageId = isPit ? null : _stageId;
    String importEventName = isPit ? _eventController.text.trim() : '';
    int? panelRubricId = _rubricId;
    int? adviserRubricId = _adviserRubricId;
    int? peerRubricId = isPit ? _peerRubricId : _capstonePeerRubricId;
    int panelWeight = int.tryParse(_panelWeightController.text) ?? 80;
    int peerWeight = int.tryParse(_peerWeightController.text) ?? 20;
    final dateController = TextEditingController(text: _dateController.text);
    final roomController = TextEditingController(text: _roomController.text);
    final durationController = TextEditingController(
      text: _durationController.text,
    );
    var rubricLoading = false;
    var importBusy = false;
    var importErrors = <String>[];

    Future<void> loadStageRubrics(
      int? stageId,
      void Function(void Function()) setDialogState,
    ) async {
      if (stageId == null) {
        return;
      }
      setDialogState(() => rubricLoading = true);
      final ids = await _stageRubricIds(stageId);
      if (!mounted) {
        return;
      }
      setDialogState(() {
        panelRubricId = ids['panel'] ?? panelRubricId;
        adviserRubricId = ids['adviser'] ?? adviserRubricId;
        peerRubricId = ids['peer'] ?? peerRubricId;
        rubricLoading = false;
      });
    }

    Future<void> loadPitEventConfig(
      String eventName,
      void Function(void Function()) setDialogState,
    ) async {
      if (eventName.trim().isEmpty) {
        return;
      }
      setDialogState(() => rubricLoading = true);
      final semesterId = _asInt(state.activeSemester?['id']);
      final config = await ref
          .read(defenseSchedulerProvider.notifier)
          .fetchPitEventConfig(eventName: eventName, semesterId: semesterId);
      if (!mounted) {
        return;
      }
      setDialogState(() {
        if (config != null) {
          panelRubricId = _asInt(config['panel_rubric_id']) ?? panelRubricId;
          peerRubricId = _asInt(config['peer_rubric_id']) ?? peerRubricId;
          panelWeight = int.tryParse(config['panel_weight']?.toString() ?? '') ?? panelWeight;
          peerWeight = int.tryParse(config['peer_weight']?.toString() ?? '') ?? peerWeight;
        }
        rubricLoading = false;
      });
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final previewRows = parsed == null
                ? <_ScheduleImportPreviewRow>[]
                : _buildScheduleImportPreviewRows(
                    parsed!,
                    state,
                    scope: importScope,
                    stageId: importStageId,
                    eventName: importEventName,
                    date: dateController.text,
                    room: roomController.text,
                    fallbackDuration:
                        int.tryParse(durationController.text.trim()) ?? 60,
                    panelRubricId: panelRubricId,
                    adviserRubricId: adviserRubricId,
                    peerRubricId: peerRubricId,
                    panelWeight: panelWeight,
                    peerWeight: peerWeight,
                  );
            final readyRows = previewRows.where((row) => row.ready).toList();
            final issueRows = previewRows.length - readyRows.length;

            Future<void> pickFile() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: const ['xlsx', 'csv'],
                withData: true,
              );
              if (result == null || result.files.isEmpty) {
                return;
              }
              final file = result.files.single;
              final bytes = file.bytes;
              if (bytes == null) {
                setDialogState(() {
                  importErrors = ['Could not read the selected file.'];
                });
                return;
              }

              final imported = parseScheduleImportFile(
                bytes: bytes,
                filename: file.name,
              );
              final detectedStage = isPit
                  ? null
                  : (_matchStageId(imported.stage, state) ??
                      _matchStageId(
                        imported.rows
                            .map((row) => row.stage)
                            .firstWhere(
                              (value) => value.isNotEmpty,
                              orElse: () => '',
                            ),
                        state,
                      ));
              final detectedEvent = isPit
                  ? (_matchEventName(imported.stage, state) ??
                      _matchEventName(
                        imported.rows
                            .map((row) => row.stage)
                            .firstWhere(
                              (value) => value.isNotEmpty,
                              orElse: () => '',
                            ),
                        state,
                      ))
                  : null;
              final detectedDate = _normalizeImportDate(
                imported.date ??
                    imported.rows
                        .map((row) => row.date)
                        .firstWhere(
                          (value) => value.isNotEmpty,
                          orElse: () => '',
                        ),
              );
              final detectedRoom =
                  imported.room ??
                  imported.rows
                      .map((row) => row.room)
                      .firstWhere(
                        (value) => value.isNotEmpty,
                        orElse: () => '',
                      );
              final firstDuration = imported.rows
                  .map((row) => row.slotDuration)
                  .firstWhere((value) => value != null, orElse: () => null);

              setDialogState(() {
                parsed = imported;
                fileName = file.name;
                importErrors = imported.rows.isEmpty
                    ? ['No schedule rows were detected. Check the headers.']
                    : [];
                if (!isPit) {
                  importStageId = detectedStage ?? importStageId;
                } else {
                  importEventName = detectedEvent ?? importEventName;
                }
                if (detectedDate.isNotEmpty) {
                  dateController.text = detectedDate;
                }
                if (detectedRoom.trim().isNotEmpty) {
                  roomController.text = detectedRoom.trim();
                }
                if (firstDuration != null) {
                  durationController.text = firstDuration.toString();
                }
              });
              if (isPit) {
                if (importEventName.isNotEmpty) {
                  await loadPitEventConfig(importEventName, setDialogState);
                }
              } else if (detectedStage != null) {
                await loadStageRubrics(detectedStage, setDialogState);
              }
            }

            Future<void> importReadyRows() async {
              if (readyRows.isEmpty) {
                setDialogState(() {
                  importErrors = ['No ready rows to import yet.'];
                });
                return;
              }
              final payloads = readyRows
                  .map((row) => row.toPayload())
                  .toList(growable: false);
              setDialogState(() {
                importBusy = true;
                importErrors = [];
              });
              final result = await ref
                  .read(defenseSchedulerProvider.notifier)
                  .importSchedules(payloads);
              if (!mounted) {
                return;
              }
              final created = result['created'] as int? ?? 0;
              final errors =
                  (result['errors'] as List?)?.cast<String>() ??
                  const <String>[];
              setDialogState(() {
                importBusy = false;
                importErrors = errors;
              });
              if (created > 0 && errors.isEmpty) {
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
              }
            }

            return Dialog(
              insetPadding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.86,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 20, 12),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.upload_file_rounded,
                              color: AppColors.maroon,
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isPit ? 'Import PIT Schedule' : 'Import Defense Schedule',
                                    style: TextStyle(
                                      color: AppColors.maroon,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'Upload the admin schedule template, review matches, then import ready rows.',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: importBusy
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildImportUploadPanel(
                                fileName: fileName,
                                onPickFile: pickFile,
                                isPit: isPit,
                              ),
                              const SizedBox(height: 18),
                              _buildImportContextPanel(
                                state,
                                scope: importScope,
                                stageId: importStageId,
                                eventName: importEventName,
                                dateController: dateController,
                                roomController: roomController,
                                durationController: durationController,
                                panelRubricId: panelRubricId,
                                peerRubricId: peerRubricId,
                                rubricLoading: rubricLoading,
                                rowsDetected: previewRows.length,
                                readyRows: readyRows.length,
                                issueRows: issueRows,
                                onStageChanged: (value) async {
                                  setDialogState(() {
                                    importStageId = value;
                                    panelRubricId = null;
                                    adviserRubricId = null;
                                    peerRubricId = null;
                                  });
                                  await loadStageRubrics(value, setDialogState);
                                },
                                onEventChanged: (value) async {
                                  setDialogState(() {
                                    importEventName = value ?? '';
                                    panelRubricId = null;
                                    peerRubricId = null;
                                  });
                                  if (value != null && value.isNotEmpty) {
                                    await loadPitEventConfig(value, setDialogState);
                                  }
                                },
                                onContextChanged: () => setDialogState(() {}),
                              ),
                              if (importErrors.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                _buildImportErrorBox(importErrors),
                              ],
                              const SizedBox(height: 18),
                              _buildImportPreviewTable(previewRows),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                issueRows > 0
                                    ? 'Resolve $issueRows blocking issue${issueRows == 1 ? '' : 's'} before importing all rows.'
                                    : '${readyRows.length} ready row${readyRows.length == 1 ? '' : 's'} can be imported.',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: importBusy
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              onPressed:
                                  state.isSaving ||
                                      readyRows.isEmpty ||
                                      importBusy
                                  ? null
                                  : importReadyRows,
                              icon: const Icon(Icons.file_upload_outlined),
                              label: const Text('Import Ready Rows'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.maroon,
                                foregroundColor: AppColors.gold,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    dateController.dispose();
    roomController.dispose();
    durationController.dispose();
  }

  Widget _buildImportUploadPanel({
    required String? fileName,
    required Future<void> Function() onPickFile,
    required bool isPit,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Icon(
              Icons.table_chart_outlined,
              color: AppColors.maroon,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName ?? (isPit ? 'Upload the PIT schedule template' : 'Upload the admin schedule template'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Supported files: .xlsx and .csv. Merged-cell-style team blocks are grouped automatically.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () async {
                      if (isPit) {
                        await downloadTextFile(
                          filename: 'defensys-pit-defense-schedule-template.csv',
                          content: '3rd Year Expo,,,,,,,,,\n'
                              'May 18, 2026,,,,,,,,,\n'
                              'SMART ROOM,,,,,,,,,\n'
                              'Time,Team Name,Project,Adviser,Team Members,Chair,Panel Member 1,Panel Member 2,Panel Member 3,Documenter\n'
                              '9:00AM-9:30AM,TechVision,Eventify,"RAY AN J. QUINON","DOMINGUEZ, Noel R.",Daga-ang,Neri,Undag,Ocampo,Camarista\n'
                              ',,,,"DAGO-OC, Evan John S.",,,,,\n'
                              ',,,,"PINGKIAN, El Jane",,,,,\n'
                              ',,,,"DIU, Sciemon Jed",,,,,\n'
                              '9:30AM-10:00AM,Techpro,Campus Tutoring to FMCP,"RAY AN J. QUINON","CABANTAC, John Mike B.",Daga-ang,Neri,Undag,Ocampo,Camarista\n'
                              ',,,,"BLASE, Jendy D.",,,,,\n'
                              ',,,,"NAQUIRA, Brexie Lyca D.",,,,,\n',
                        );
                      } else {
                        await downloadTextFile(
                          filename: 'defensys-capstone-defense-schedule-template.csv',
                          content: 'REDEFENSE - Capstone Project and Research 1,,,,,,,,,\n'
                              'May 18, 2026,,,,,,,,,\n'
                              'SMART ROOM,,,,,,,,,\n'
                              'Time,Team Name,Capstone Project,Adviser,Team Members,Chair,Panel Member 1,Panel Member 2,Panel Member 3,Documenter\n'
                              '9:00AM-9:30AM,TechVision,Eventify,"RAY AN J. QUINON","DOMINGUEZ, Noel R.",Daga-ang,Neri,Undag,Ocampo,Camarista\n'
                              ',,,,"DAGO-OC, Evan John S.",,,,,\n'
                              ',,,,"PINGKIAN, El Jane",,,,,\n'
                              ',,,,"DIU, Sciemon Jed",,,,,\n'
                              '9:30AM-10:00AM,Techpro,Campus Tutoring to FMCP,"RAY AN J. QUINON","CABANTAC, John Mike B.",Daga-ang,Neri,Undag,Ocampo,Camarista\n'
                              ',,,,"BLASE, Jendy D.",,,,,\n'
                              ',,,,"NAQUIRA, Brexie Lyca D.",,,,,\n',
                        );
                      }
                    },
                    child: Text(
                      'Download sample CSV template',
                      style: TextStyle(
                        color: AppColors.maroon,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPickFile,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(fileName == null ? 'Upload File' : 'Replace File'),
          ),
        ],
      ),
    );
  }

  Widget _buildImportContextPanel(
    DefenseSchedulerState state, {
    required String scope,
    required int? stageId,
    required String eventName,
    required TextEditingController dateController,
    required TextEditingController roomController,
    required TextEditingController durationController,
    required int? panelRubricId,
    required int? peerRubricId,
    required bool rubricLoading,
    required int rowsDetected,
    required int readyRows,
    required int issueRows,
    required ValueChanged<int?> onStageChanged,
    required ValueChanged<String?> onEventChanged,
    required VoidCallback onContextChanged,
  }) {
    final isPit = scope == 'pit';
    final stageItems = state.defenseStages
        .map(
          (stage) => DropdownMenuItem<int?>(
            value: _asInt(stage['id']),
            child: Text(stage['label']?.toString() ?? ''),
          ),
        )
        .toList();
    final rubricName = _rubricName(state, panelRubricId);
    final peerRubricName = isPit ? _peerRubricName(state, peerRubricId) : '';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Detected Context',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: isPit
                    ? _labeledField(
                        'PIT Event',
                        DropdownButtonFormField<String>(
                          value: state.pitEvents.any((e) => e['event_name'] == eventName)
                              ? eventName
                              : null,
                          decoration: _schedulerInputDecoration(
                            hintText: 'Select PIT event',
                          ),
                          items: state.pitEvents.map((e) {
                            final name = e['event_name']?.toString() ?? '';
                            return DropdownMenuItem<String>(
                              value: name,
                              child: Text(name),
                            );
                          }).toList(),
                          onChanged: onEventChanged,
                        ),
                      )
                    : _labeledField(
                        'Stage',
                        DropdownButtonFormField<int?>(
                          initialValue: stageId,
                          decoration: _schedulerInputDecoration(
                            hintText: 'Select stage if not detected',
                          ),
                          items: stageItems,
                          onChanged: onStageChanged,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _labeledField(
                  'Date',
                  _scheduleDateField(
                    controller: dateController,
                    onSelected: onContextChanged,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _labeledField(
                  'Default duration',
                  TextField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    decoration: _schedulerInputDecoration(),
                    onChanged: (_) => onContextChanged(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _labeledField(
                  'Default room',
                  TextField(
                    controller: roomController,
                    decoration: _schedulerInputDecoration(
                      hintText: 'Use only if rows have no room',
                    ),
                    onChanged: (_) => onContextChanged(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _importMetric('Rows detected', rowsDetected.toString()),
              _importMetric('Ready', readyRows.toString(), success: true),
              _importMetric(
                'Needs attention',
                issueRows.toString(),
                warning: issueRows > 0,
              ),
              _importMetric(
                'Panel rubric',
                rubricLoading
                    ? 'Loading...'
                    : (rubricName.isEmpty ? 'Missing' : rubricName),
                warning: rubricName.isEmpty && !rubricLoading,
              ),
              if (isPit)
                _importMetric(
                  'Peer rubric',
                  rubricLoading
                      ? 'Loading...'
                      : (peerRubricName.isEmpty ? 'Missing' : peerRubricName),
                  warning: peerRubricName.isEmpty && !rubricLoading,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _importMetric(
    String label,
    String value, {
    bool success = false,
    bool warning = false,
  }) {
    final bg = success
        ? const Color(0xFFECFDF3)
        : warning
        ? const Color(0xFFFFF7ED)
        : const Color(0xFFF8FAFC);
    final fg = success
        ? const Color(0xFF027A48)
        : warning
        ? const Color(0xFFB45309)
        : AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _buildImportErrorBox(List<String> errors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: errors
            .take(4)
            .map(
              (error) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  error,
                  style: const TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildImportPreviewTable(List<_ScheduleImportPreviewRow> rows) {
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: const Center(
          child: Text(
            'Upload a file to preview schedule rows.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          columns: const [
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Time')),
            DataColumn(label: Text('Team')),
            DataColumn(label: Text('Project')),
            DataColumn(label: Text('Chair')),
            DataColumn(label: Text('Panel Members')),
            DataColumn(label: Text('Documenter')),
            DataColumn(label: Text('Room')),
            DataColumn(label: Text('Issues')),
          ],
          rows: rows.map((row) {
            final issueText = row.issues.isNotEmpty
                ? row.issues.join('; ')
                : row.warnings.join('; ');
            return DataRow(
              color: WidgetStateProperty.all(
                row.ready ? Colors.white : const Color(0xFFFFFBEB),
              ),
              cells: [
                DataCell(
                  _importStatusChip(row.ready ? 'Ready' : 'Needs attention'),
                ),
                DataCell(Text(row.timeLabel)),
                DataCell(Text(row.teamLabel)),
                DataCell(Text(row.projectLabel)),
                DataCell(Text(row.chairLabel)),
                DataCell(Text(row.panelLabel)),
                DataCell(Text(row.documenterLabel)),
                DataCell(Text(row.room)),
                DataCell(
                  SizedBox(
                    width: 320,
                    child: Text(
                      issueText.isEmpty ? '-' : issueText,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: row.issues.isNotEmpty
                            ? const Color(0xFFB42318)
                            : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _importStatusChip(String label) {
    final ready = label == 'Ready';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: ready ? const Color(0xFFECFDF3) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: ready ? const Color(0xFF027A48) : const Color(0xFFB45309),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  List<_ScheduleImportPreviewRow> _buildScheduleImportPreviewRows(
    ParsedScheduleImport parsed,
    DefenseSchedulerState state, {
    required String scope,
    required int? stageId,
    required String eventName,
    required String date,
    required String room,
    required int fallbackDuration,
    required int? panelRubricId,
    required int? adviserRubricId,
    required int? peerRubricId,
    required int panelWeight,
    required int peerWeight,
  }) {
    final isPit = scope == 'pit';
    return parsed.rows.map((source) {
      final issues = <String>[];
      final warnings = <String>[];
      final rowDate = _normalizeImportDate(source.date).isNotEmpty
          ? _normalizeImportDate(source.date)
          : date.trim();
      final rowRoom = source.room.trim().isNotEmpty
          ? source.room.trim()
          : room.trim();
      final duration = source.slotDuration ?? fallbackDuration;
      final teamMatch = _matchTeam(source, state, scope: scope);
      final panelistMatches = <_ImportNameMatch>[];

      final chairMatch = _matchPanelist(source.chair, state);
      if (source.chair.trim().isNotEmpty) {
        panelistMatches.add(chairMatch);
      }
      for (final name in source.panelMembers) {
        panelistMatches.add(_matchPanelist(name, state));
      }

      if (isPit) {
        if (eventName.trim().isEmpty) {
          issues.add('Select a PIT event.');
        }
        if (panelRubricId == null) {
          issues.add('Panel rubric is missing.');
        }
        if (peerRubricId == null) {
          issues.add('Peer rubric is missing.');
        }
      } else {
        if (stageId == null) {
          issues.add('Select a defense stage.');
        }
        if (panelRubricId == null ||
            adviserRubricId == null ||
            peerRubricId == null) {
          issues.add('Stage grading rubrics are incomplete.');
        }
      }
      if (rowDate.isEmpty) {
        issues.add('Date is missing.');
      }
      if (rowRoom.isEmpty) {
        issues.add('Room is missing.');
      }
      if (source.startTime.isEmpty) {
        issues.add('Time could not be parsed.');
      }
      if (duration < 15) {
        issues.add('Slot duration must be at least 15 minutes.');
      }
      if (teamMatch.id == null) {
        issues.add(teamMatch.message);
      } else if (teamMatch.message.isNotEmpty) {
        warnings.add(teamMatch.message);
      }
      final panelistIds = <int>[];
      for (final match in panelistMatches) {
        if (match.id == null) {
          issues.add(match.message);
        } else if (!panelistIds.contains(match.id)) {
          panelistIds.add(match.id!);
        }
      }
      if (panelistIds.isEmpty) {
        issues.add('At least one chair or panel member is required.');
      }
      if (source.documenter.trim().isNotEmpty) {
        warnings.add(
          'Documenter is shown for review but is not assigned as a grading panelist yet.',
        );
      }

      return _ScheduleImportPreviewRow(
        source: source,
        scope: scope,
        teamId: teamMatch.id,
        panelistIds: panelistIds,
        stageId: stageId,
        eventName: eventName,
        panelRubricId: panelRubricId,
        peerRubricId: peerRubricId,
        panelWeight: panelWeight,
        peerWeight: peerWeight,
        date: rowDate,
        room: rowRoom,
        duration: duration,
        issues: issues,
        warnings: warnings,
      );
    }).toList();
  }

  _ImportNameMatch _matchTeam(
    ParsedScheduleImportRow row,
    DefenseSchedulerState state, {
    String scope = 'capstone',
  }) {
    final name = _normalizeName(row.teamName);
    final project = _normalizeName(row.projectTitle);
    final teams = _teamsForScope(state, scope);
    final byName = teams.where((team) {
      return _normalizeName(team['name']?.toString() ?? '') == name;
    }).toList();
    if (byName.length == 1) {
      final storedProject = byName.first['project_title']?.toString() ?? '';
      if (project.isNotEmpty && _normalizeName(storedProject) != project) {
        return _ImportNameMatch(
          id: _asInt(byName.first['id']),
          message: 'Project title differs from the stored team project.',
        );
      }
      return _ImportNameMatch(id: _asInt(byName.first['id']));
    }
    if (byName.length > 1) {
      return const _ImportNameMatch(message: 'Multiple teams match this name.');
    }
    if (project.isNotEmpty) {
      final byProject = teams.where((team) {
        return _normalizeName(team['project_title']?.toString() ?? '') ==
            project;
      }).toList();
      if (byProject.length == 1) {
        return _ImportNameMatch(
          id: _asInt(byProject.first['id']),
          message: 'Matched by project title because team name was not found.',
        );
      }
    }
    return _ImportNameMatch(message: 'Team "${row.teamName}" was not found.');
  }

  _ImportNameMatch _matchPanelist(String rawName, DefenseSchedulerState state) {
    final name = _normalizeName(rawName);
    if (name.isEmpty) {
      return const _ImportNameMatch(message: 'Panelist name is missing.');
    }
    final exact = state.panelists.where((panelist) {
      return _normalizeName(panelist['name']?.toString() ?? '') == name ||
          _normalizeName(panelist['username']?.toString() ?? '') == name;
    }).toList();
    if (exact.length == 1) {
      return _ImportNameMatch(id: _asInt(exact.first['id']));
    }
    if (exact.length > 1) {
      return _ImportNameMatch(message: 'Panelist "$rawName" is ambiguous.');
    }

    final lastNameMatches = state.panelists.where((panelist) {
      final display = panelist['name']?.toString() ?? '';
      final parts = display.trim().split(RegExp(r'\s+'));
      final last = parts.isEmpty ? '' : parts.last;
      return _normalizeName(last) == name;
    }).toList();
    if (lastNameMatches.length == 1) {
      return _ImportNameMatch(id: _asInt(lastNameMatches.first['id']));
    }
    if (lastNameMatches.length > 1) {
      return _ImportNameMatch(
        message: 'Panelist "$rawName" matches multiple faculty.',
      );
    }
    return _ImportNameMatch(message: 'Panelist "$rawName" was not found.');
  }

  int? _matchStageId(String? rawStage, DefenseSchedulerState state) {
    final stage = _normalizeName(rawStage ?? '');
    if (stage.isEmpty) {
      return null;
    }
    for (final item in state.defenseStages) {
      if (_normalizeName(item['label']?.toString() ?? '') == stage) {
        return _asInt(item['id']);
      }
    }
    return null;
  }

  String? _matchEventName(String? rawEvent, DefenseSchedulerState state) {
    final event = _normalizeName(rawEvent ?? '');
    if (event.isEmpty) {
      return null;
    }
    for (final item in state.pitEvents) {
      final eventName = item['event_name']?.toString() ?? '';
      if (_normalizeName(eventName) == event) {
        return eventName;
      }
    }
    return null;
  }

  String _rubricName(DefenseSchedulerState state, int? rubricId) {
    if (rubricId == null) {
      return '';
    }
    for (final rubric in state.rubrics) {
      if (_asInt(rubric['id']) == rubricId) {
        return rubric['name']?.toString() ?? '';
      }
    }
    return '';
  }

  String _peerRubricName(DefenseSchedulerState state, int? rubricId) {
    if (rubricId == null) {
      return '';
    }
    for (final rubric in state.peerRubrics) {
      if (_asInt(rubric['id']) == rubricId) {
        return rubric['name']?.toString() ?? '';
      }
    }
    // Fallback: check regular rubrics list too
    for (final rubric in state.rubrics) {
      if (_asInt(rubric['id']) == rubricId) {
        return rubric['name']?.toString() ?? '';
      }
    }
    return '';
  }

  String _normalizeImportDate(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return '';
    }
    final parsed = DateTime.tryParse(text);
    if (parsed != null) {
      return _formatScheduleDate(parsed);
    }
    final humanParsed = _parseHumanDate(text);
    if (humanParsed != null) {
      return _formatScheduleDate(humanParsed);
    }
    final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$').firstMatch(text);
    if (match == null) {
      return text;
    }
    final month = int.tryParse(match.group(1) ?? '') ?? 1;
    final day = int.tryParse(match.group(2) ?? '') ?? 1;
    var year = int.tryParse(match.group(3) ?? '') ?? DateTime.now().year;
    if (year < 100) {
      year += 2000;
    }
    return _formatScheduleDate(DateTime(year, month, day));
  }

  DateTime? _parseHumanDate(String text) {
    final cleaned = text.trim().toLowerCase().replaceAll(',', '');
    final months = {
      'january': 1, 'jan': 1,
      'february': 2, 'feb': 2,
      'march': 3, 'mar': 3,
      'april': 4, 'apr': 4,
      'may': 5,
      'june': 6, 'jun': 6,
      'july': 7, 'jul': 7,
      'august': 8, 'aug': 8,
      'september': 9, 'sep': 9, 'sept': 9,
      'october': 10, 'oct': 10,
      'november': 11, 'nov': 11,
      'december': 12, 'dec': 12,
    };
    
    final match1 = RegExp(r'^([a-z]+)\s+(\d{1,2})\s+(\d{4})$').firstMatch(cleaned);
    if (match1 != null) {
      final monthStr = match1.group(1);
      final day = int.tryParse(match1.group(2) ?? '');
      final year = int.tryParse(match1.group(3) ?? '');
      final month = months[monthStr];
      if (month != null && day != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    final match2 = RegExp(r'^(\d{1,2})\s+([a-z]+)\s+(\d{4})$').firstMatch(cleaned);
    if (match2 != null) {
      final day = int.tryParse(match2.group(1) ?? '');
      final monthStr = match2.group(2);
      final year = int.tryParse(match2.group(3) ?? '');
      final month = months[monthStr];
      if (month != null && day != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }

  String _normalizeName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  List<Map<String, dynamic>> _capstoneRubricsForEval(
    DefenseSchedulerState state,
    String evaluationType,
  ) {
    return _rubricsForScopeAndStage(state, 'capstone', _stageId)
        .where(
          (rubric) => rubric['evaluation_type']?.toString() == evaluationType,
        )
        .toList();
  }

  int? _validCapstoneRubricId(
    DefenseSchedulerState state,
    int? rubricId,
    String evaluationType,
  ) {
    final rubrics = _capstoneRubricsForEval(state, evaluationType);
    return rubrics.any((rubric) => _asInt(rubric['id']) == rubricId)
        ? rubricId
        : null;
  }

  List<Map<String, dynamic>> _rubricsForContext(DefenseSchedulerState state) {
    return _rubricsForScopeAndStage(state, _scope, _stageId);
  }

  List<Map<String, dynamic>> _rubricsForScopeAndStage(
    DefenseSchedulerState state,
    String scope,
    int? stageId,
  ) {
    return state.rubrics.where((rubric) {
      if (rubric['scope'] != scope) {
        return false;
      }
      if (scope == 'capstone' && stageId != null) {
        return _asInt(rubric['defense_stage_id']) == stageId;
      }
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> _teamsForScope(
    DefenseSchedulerState state,
    String scope,
  ) {
    return state.teams.where((team) {
      final level = team['level']?.toString() ?? '';
      return scope == 'pit'
          ? level.contains('PIT')
          : level.contains('Capstone');
    }).toList();
  }

  List<DropdownMenuItem<String>> _allowedScopeItems(
    DefenseSchedulerState state,
  ) {
    final scopes = <String>[
      if (state.canScheduleCapstone) 'capstone',
      if (state.canSchedulePit) 'pit',
    ];
    final values = scopes.isNotEmpty ? scopes : state.allowedScopes;
    return values
        .where((scope) => scope == 'capstone' || scope == 'pit')
        .map(
          (scope) => DropdownMenuItem<String>(
            value: scope,
            child: Text(scope == 'pit' ? 'PIT' : 'Capstone'),
          ),
        )
        .toList();
  }

  int? _validRubricId(DefenseSchedulerState state) {
    final rubrics = _rubricsForContext(state);
    return rubrics.any((rubric) => _asInt(rubric['id']) == _rubricId)
        ? _rubricId
        : null;
  }

  List<Map<String, dynamic>> _peerRubricsForContext(
    DefenseSchedulerState state,
  ) {
    return state.peerRubrics
        .where((rubric) => rubric['scope'] == 'pit')
        .toList();
  }

  int? _validPeerRubricId(DefenseSchedulerState state) {
    final rubrics = _peerRubricsForContext(state);
    return rubrics.any((rubric) => _asInt(rubric['id']) == _peerRubricId)
        ? _peerRubricId
        : null;
  }

  String _stageLabel(DefenseSchedulerState state) {
    for (final stage in state.defenseStages) {
      if (_asInt(stage['id']) == _stageId) {
        return stage['label']?.toString() ?? 'Stage';
      }
    }
    return 'Stage';
  }

  DateTime _parseScheduleDate(String text) {
    final parsed = DateTime.tryParse(text.trim());
    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  TimeOfDay _parseScheduleTime(String text) {
    final parts = text.trim().split(':');
    final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 8;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  String _formatScheduleDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatScheduleTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickScheduleDate({
    TextEditingController? controller,
    VoidCallback? onSelected,
  }) async {
    final target = controller ?? _dateController;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _parseScheduleDate(target.text),
      firstDate: today,
      lastDate: DateTime(now.year + 3, now.month, now.day),
    );
    if (picked == null) {
      return;
    }
    target.text = _formatScheduleDate(picked);
    onSelected?.call();
    if (controller == null && mounted) {
      setState(() {});
    }
  }

  Future<void> _pickScheduleTime({
    TextEditingController? controller,
    VoidCallback? onSelected,
  }) async {
    final target = controller ?? _timeController;
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseScheduleTime(target.text),
    );
    if (picked == null) {
      return;
    }
    target.text = _formatScheduleTime(picked);
    onSelected?.call();
    if (controller == null && mounted) {
      setState(() {
        if (_planSlots.isNotEmpty) {
          _recalculatePlanSlots();
        }
      });
    }
  }

  Widget _scheduleDateField({
    required TextEditingController controller,
    VoidCallback? onSelected,
    InputDecoration? decoration,
  }) {
    Future<void> pick() =>
        _pickScheduleDate(controller: controller, onSelected: onSelected);

    return TextField(
      controller: controller,
      readOnly: true,
      onTap: pick,
      decoration:
          decoration ??
          _schedulerInputDecoration(
            suffixIcon: IconButton(
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              onPressed: pick,
              tooltip: 'Pick date',
            ),
          ),
    );
  }

  Widget _scheduleTimeField({
    required TextEditingController controller,
    VoidCallback? onSelected,
    InputDecoration? decoration,
  }) {
    Future<void> pick() =>
        _pickScheduleTime(controller: controller, onSelected: onSelected);

    return TextField(
      controller: controller,
      readOnly: true,
      onTap: pick,
      decoration:
          decoration ??
          _schedulerInputDecoration(
            suffixIcon: IconButton(
              icon: const Icon(Icons.access_time_outlined, size: 18),
              onPressed: pick,
              tooltip: 'Pick time',
            ),
          ),
    );
  }

  void _recalculatePlanSlots() {
    final start = _timeToMinutes(_timeController.text.trim());
    final duration = int.tryParse(_durationController.text.trim()) ?? 60;

    _planSlots = _planSlots.asMap().entries.map((entry) {
      final index = entry.key;
      final slot = Map<String, dynamic>.from(entry.value);
      slot['slot'] = index + 1;
      slot['start_time'] = _minutesToTime(start + duration * index);
      slot['end_time'] = _minutesToTime(start + duration * (index + 1));
      return slot;
    }).toList();
  }

  int _timeToMinutes(String value) {
    final parts = value.split(':');
    final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 8;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return hour * 60 + minute;
  }

  String _minutesToTime(int minutes) {
    final hour = (minutes ~/ 60) % 24;
    final minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  String _shortTime(dynamic value) {
    final text = value?.toString() ?? '';
    return text.length >= 5 ? text.substring(0, 5) : text;
  }

  void _showSnack(String message) {
    showValidationToast(context, message);
  }

  Widget _buildExistingSchedules(DefenseSchedulerState state) {
    final activeSchedules = state.schedules
        .where((s) => s['status'] == 'scheduled')
        .toList();

    if (activeSchedules.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.event_available, color: AppColors.maroon, size: 22),
            SizedBox(width: 8),
            Text(
              'Active Schedules',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.maroon,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activeSchedules.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final schedule = activeSchedules[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                leading: CircleAvatar(
                  backgroundColor: AppColors.maroon.withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.event,
                    color: AppColors.maroon,
                    size: 20,
                  ),
                ),
                title: Text(
                  schedule['team_name'] ?? 'Unknown Team',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${schedule['stage_label']} • ${schedule['scheduled_date']} ${schedule['start_time']} • ${schedule['room']}',
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.cancel_outlined,
                        color: Colors.orange,
                      ),
                      tooltip: 'Cancel Schedule',
                      onPressed: () => _cancelSchedule(schedule['id']),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                      ),
                      tooltip: 'Mark as Done',
                      onPressed: () => _markScheduleAsDone(schedule['id']),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _cancelSchedule(int scheduleId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Schedule?'),
        content: const Text(
          'This will cancel the defense schedule. Panelists will no longer see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref
          .read(defenseSchedulerProvider.notifier)
          .updateStatus(scheduleId, 'cancelled');
    }
  }

  Future<void> _markScheduleAsDone(int scheduleId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Done?'),
        content: const Text('This will mark the defense as completed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Yes, Mark Done'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref
          .read(defenseSchedulerProvider.notifier)
          .updateStatus(scheduleId, 'done');
    }
  }

  int _readyTeamsCount(DefenseSchedulerState state) {
    // If plan slots are generated, show that count
    if (_planSlots.isNotEmpty) {
      return _planSlots.length;
    }

    // Otherwise, count teams endorsed for the selected stage
    if (_scope == 'capstone' && _stageId != null) {
      final selectedStage = state.defenseStages.firstWhere(
        (stage) => _asInt(stage['id']) == _stageId,
        orElse: () => <String, dynamic>{},
      );
      final stageLabel = selectedStage['label']?.toString() ?? '';

      if (stageLabel.isNotEmpty) {
        return state.teams.where((team) {
          final readyForStage = team['ready_for_stage']?.toString() ?? '';
          final teamLevel = team['level']?.toString() ?? '';
          final isCapstone = teamLevel.toLowerCase().contains('capstone');
          return isCapstone && readyForStage == stageLabel;
        }).length;
      }
    } else if (_scope == 'pit') {
      final eventName = _eventController.text.trim();
      if (eventName.isNotEmpty) {
        return state.teams.where((team) {
          final readyForStage = team['ready_for_stage']?.toString() ?? '';
          final teamLevel = team['level']?.toString() ?? '';
          final isPit = teamLevel.toLowerCase().contains('pit');
          return isPit && readyForStage == eventName;
        }).length;
      }
    }

    return 0;
  }

  int _count(DefenseSchedulerState state, String key) {
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

  void _insertVariable(TextEditingController controller, String variable) {
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.start;
    final end = selection.end;

    if (start < 0 || end < 0) {
      final newText = text + variable;
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    } else {
      final newText = text.replaceRange(start, end, variable);
      final newCursorOffset = start + variable.length;
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newCursorOffset),
      );
    }
  }

  String _slugify(String text) {
    return text
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s\-_]'), '')
        .replaceAll(RegExp(r'[\s_]+'), '-');
  }

  String _resolvePitPreview(String template, String eventName) {
    if (template.isEmpty) {
      return '3rdYear.PIT301.Project-Alpha.1stSemester.pdf';
    }

    final slugifiedEvent = eventName.trim().isEmpty
        ? 'PIT-Event'
        : _slugify(eventName);

    String result = template
        .replaceAll('{year}', '3rdYear')
        .replaceAll('{course}', 'PIT301')
        .replaceAll('{project}', 'Project-Alpha')
        .replaceAll('{event}', slugifiedEvent)
        .replaceAll('{stage}', slugifiedEvent)
        .replaceAll('{semester}', '1stSemester');

    if (!result.toLowerCase().endsWith('.pdf')) {
      result = '$result.pdf';
    }
    return result;
  }

  Widget _buildTeamReadinessTracker(DefenseSchedulerState state) {
    final activeStageOrEventName = _scope == 'capstone'
        ? _stageLabel(state)
        : _eventController.text.trim();

    final teams = _teamsForScope(state, _scope).where((team) {
      final query = _trackerSearchController.text.toLowerCase().trim();
      if (query.isEmpty) return true;
      final name = (team['name']?.toString() ?? '').toLowerCase();
      final project = (team['project_title']?.toString() ?? '').toLowerCase();
      return name.contains(query) || project.contains(query);
    }).toList();

    return _schedulerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.checklist_rtl_rounded,
                color: AppColors.maroon,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text(
                'Team Readiness Tracker',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              // Search input
              Container(
                width: 260,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD0D5DD)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _trackerSearchController,
                        decoration: const InputDecoration(
                          hintText: 'Search teams...',
                          hintStyle: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_trackerSearchController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _trackerSearchController.clear();
                          setState(() {});
                        },
                        child: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Monitor team deliverable completeness. Teams must have all required pre-defense deliverables accepted by their instructor before they are ready for scheduling.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          if (teams.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: Text(
                _trackerSearchController.text.isEmpty
                    ? 'No teams found for the active scope.'
                    : 'No teams match your search query.',
                style: const TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
              ),
            )
          else
            Table(
              columnWidths: const {
                0: FlexColumnWidth(3), // Team/Project
                1: FlexColumnWidth(1.5), // Section
                2: FlexColumnWidth(2), // Status
                3: FlexColumnWidth(2.5), // Actions
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                // Table Header
                TableRow(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF9FAFB),
                    border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                  ),
                  children: [
                    _tableHeaderCell('TEAM & PROJECT TITLE'),
                    _tableHeaderCell('SECTION'),
                    _tableHeaderCell('READINESS STATUS'),
                    _tableHeaderCell('ACTIONS'),
                  ],
                ),
                // Table Rows
                ...teams.map((team) {
                  final isReady = team['ready_for_stage'] == activeStageOrEventName && activeStageOrEventName.isNotEmpty;
                  final readyForStage = team['ready_for_stage']?.toString() ?? '';
                  final statusText = isReady
                      ? 'Ready'
                      : (readyForStage.isNotEmpty
                          ? 'Endorsed for $readyForStage'
                          : 'Awaiting Endorsement');

                  return TableRow(
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
                    ),
                    children: [
                      // Team Name / Title
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              team['name']?.toString() ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              team['project_title']?.toString() ?? '-',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Section
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                        child: Text(
                          team['section']?.toString().isNotEmpty == true
                              ? team['section']!.toString()
                              : 'No Section',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      // Status Badge
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isReady ? Colors.green : Colors.amber,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isReady ? Colors.green.shade800 : Colors.amber.shade900,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Actions
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                        child: Row(
                          children: [
                            TextButton.icon(
                              onPressed: activeStageOrEventName.isEmpty
                                  ? null
                                  : () => _showTeamDeliverablesReview(context, team, activeStageOrEventName),
                              icon: const Icon(Icons.folder_open_rounded, size: 16),
                              label: const Text('Review Files'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.maroon,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!isReady)
                              TextButton.icon(
                                onPressed: _isSendingReminder || activeStageOrEventName.isEmpty
                                    ? null
                                    : () => _sendReminder(team['id'], activeStageOrEventName),
                                icon: const Icon(Icons.notification_important_rounded, size: 16),
                                label: const Text('Remind'),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFFD97706),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tableHeaderCell(String label) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF6B7280),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  void _showTeamDeliverablesReview(BuildContext context, Map<String, dynamic> team, String stageLabel) {
    ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
          scope: _scope,
          selectedStage: stageLabel,
        );

    showDialog(
      context: context,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final delState = ref.watch(capstoneDeliverablesProvider);
            final teamData = delState.teams.firstWhere(
              (t) => _asInt(t['id']) == _asInt(team['id']),
              orElse: () => <String, dynamic>{},
            );

            final stageData = teamData['selected_stage'] as Map? ?? {};
            final deliverables = stageData['deliverables'] as List? ?? [];

            return AlertDialog(
              title: Text('${team['name']} - Deliverables Review'),
              content: SizedBox(
                width: 600,
                height: 400,
                child: delState.isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.maroon))
                    : deliverables.isEmpty
                        ? const Center(child: Text('No deliverables configured for this stage.'))
                        : ListView.separated(
                            itemCount: deliverables.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              final d = deliverables[index];
                              final label = d['label'] ?? '';
                              final required = d['required'] == true;
                              final type = d['type'] ?? '';
                              final uploaded = d['uploaded'] == true;
                              final submission = d['submission'] as Map?;

                              Color statusColor = Colors.grey;
                              String statusText = 'Not Submitted';
                              if (uploaded && submission != null) {
                                final status = submission['status']?.toString() ?? 'pending';
                                if (status == 'accepted') {
                                  statusColor = Colors.green;
                                  statusText = 'Accepted';
                                } else if (status == 'rejected') {
                                  statusColor = Colors.red;
                                  statusText = 'Rejected';
                                } else {
                                  statusColor = Colors.orange;
                                  statusText = 'Pending Review';
                                }
                              }

                              return ListTile(
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ),
                                    if (required) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEECEC),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Required',
                                          style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text('Type: ${type == 'pre' ? 'Pre-Defense' : 'Vault File'}', style: const TextStyle(fontSize: 12)),
                                    if (uploaded &&
                                        submission != null &&
                                        submission['feedback'] != null &&
                                        submission['feedback'].toString().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Feedback: ${submission['feedback']}',
                                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.red),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: statusColor),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _sendReminder(dynamic teamId, String stageLabel) async {
    setState(() => _isSendingReminder = true);
    try {
      final client = ref.read(authenticatedHttpClientProvider);
      final url = '${ApiConfig.teamsUrl}/$teamId/remind/';
      final response = await client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'stage_label': stageLabel}),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          showSuccessToast(context, 'Reminder notification successfully sent.');
        }
      } else {
        final body = jsonDecode(response.body);
        final err = body['detail'] ?? body['message'] ?? 'Failed to send reminder';
        if (mounted) {
          showErrorToast(context, err.toString());
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
}

class _ScheduleImportPreviewRow {
  const _ScheduleImportPreviewRow({
    required this.source,
    required this.scope,
    required this.teamId,
    required this.panelistIds,
    required this.stageId,
    required this.eventName,
    required this.panelRubricId,
    required this.peerRubricId,
    required this.panelWeight,
    required this.peerWeight,
    required this.date,
    required this.room,
    required this.duration,
    required this.issues,
    required this.warnings,
  });

  final ParsedScheduleImportRow source;
  final String scope;
  final int? teamId;
  final List<int> panelistIds;
  final int? stageId;
  final String eventName;
  final int? panelRubricId;
  final int? peerRubricId;
  final int panelWeight;
  final int peerWeight;
  final String date;
  final String room;
  final int duration;
  final List<String> issues;
  final List<String> warnings;

  bool get ready => issues.isEmpty;

  String get timeLabel {
    if (source.startTime.isEmpty) {
      return source.time.isEmpty ? '-' : source.time;
    }
    if (source.endTime.isEmpty) {
      return source.startTime;
    }
    return '${source.startTime} - ${source.endTime}';
  }

  String get teamLabel => source.teamName.isEmpty ? '-' : source.teamName;
  String get projectLabel =>
      source.projectTitle.isEmpty ? '-' : source.projectTitle;
  String get chairLabel => source.chair.isEmpty ? '-' : source.chair;
  String get panelLabel =>
      source.panelMembers.isEmpty ? '-' : source.panelMembers.join(', ');
  String get documenterLabel =>
      source.documenter.isEmpty ? '-' : source.documenter;

  Map<String, dynamic> toPayload() {
    if (scope == 'pit') {
      return {
        'scope': 'pit',
        'team_id': teamId,
        'event_name': eventName,
        'rubric_id': panelRubricId,
        'peer_rubric_id': peerRubricId,
        'panel_weight': panelWeight,
        'peer_weight': peerWeight,
        'scheduled_date': date,
        'start_time': source.startTime,
        'slot_duration': duration,
        'room': room,
        'panelist_ids': panelistIds,
      };
    }
    return {
      'scope': 'capstone',
      'team_id': teamId,
      'defense_stage_id': stageId,
      'event_name': '',
      'rubric_id': panelRubricId,
      'scheduled_date': date,
      'start_time': source.startTime,
      'slot_duration': duration,
      'room': room,
      'panelist_ids': panelistIds,
    };
  }
}

class _ImportNameMatch {
  const _ImportNameMatch({this.id, this.message = ''});

  final int? id;
  final String message;
}
