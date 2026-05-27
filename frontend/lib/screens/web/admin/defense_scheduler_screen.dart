import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/defense_scheduler_provider.dart';
import '../../../services/defense_stages_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../../theme/app_theme.dart';
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
  final _roomController = TextEditingController(text: 'Room 301');

  final Set<int> _selectedPanelistIds = {};

  String _scope = 'capstone';
  int? _stageId;
  int? _rubricId;
  int? _adviserRubricId;
  int? _capstonePeerRubricId;
  int? _peerRubricId;
  bool _showFinalPreview = false;
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
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _dateController.text = DateTime.now().toIso8601String().substring(0, 10);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Check if user is PIT Lead and set scope accordingly
      final dashState = ref.read(dashboardProvider('faculty'));
      final roles =
          (dashState.data?['roles'] as Map?)?.cast<String, dynamic>() ?? {};

      if (roles['pit_lead'] == true && roles['adviser'] != true) {
        // PIT Lead only (not also an adviser) - default to PIT scope
        setState(() {
          _scope = 'pit';
        });
      }

      ref.read(defenseSchedulerProvider.notifier).fetchSchedules();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(defenseSchedulerProvider);
    final currentStep = _planSlots.isEmpty ? 1 : (_showFinalPreview ? 3 : 2);

    ref.listen(defenseSchedulerProvider, (previous, next) {
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

              const SizedBox(height: 12),
              if (state.isLoading &&
                  state.schedules.isEmpty &&
                  state.teams.isEmpty) ...[
                DefensysSkeleton.list(count: 4, rowHeight: 64),
              ] else ...[
                if (currentStep == 1) _buildStepOne(state),
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
                onPressed: state.isSaving
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
                onPressed: state.isSaving ? null : _generatePlan,
                icon: const Icon(Icons.bolt_rounded, size: 18),
                label: const Text('Generate Schedule Plan'),
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
              const Text(
                'Choose the shared stage, rubric, date, room, start time, and slot duration for this run. Then generate the plan to prepare consecutive slots.',
                style: TextStyle(
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
                const SizedBox(height: 14),
                _labeledField(
                  'Panel rubric *',
                  DropdownButtonFormField<int?>(
                    initialValue: _validCapstoneRubricId(
                      state,
                      _rubricId,
                      'panel',
                    ),
                    decoration: _schedulerInputDecoration(),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Select panel rubric'),
                      ),
                      ..._capstoneRubricsForEval(state, 'panel').map(
                        (rubric) => DropdownMenuItem<int?>(
                          value: _asInt(rubric['id']),
                          child: Text(rubric['name']?.toString() ?? ''),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _rubricId = value),
                  ),
                ),
                const SizedBox(height: 14),
                _labeledField(
                  'Adviser rubric *',
                  DropdownButtonFormField<int?>(
                    initialValue: _validCapstoneRubricId(
                      state,
                      _adviserRubricId,
                      'adviser',
                    ),
                    decoration: _schedulerInputDecoration(),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Select adviser rubric'),
                      ),
                      ..._capstoneRubricsForEval(state, 'adviser').map(
                        (rubric) => DropdownMenuItem<int?>(
                          value: _asInt(rubric['id']),
                          child: Text(rubric['name']?.toString() ?? ''),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _adviserRubricId = value),
                  ),
                ),
                const SizedBox(height: 14),
                _labeledField(
                  'Peer rubric *',
                  DropdownButtonFormField<int?>(
                    initialValue: _validCapstoneRubricId(
                      state,
                      _capstonePeerRubricId,
                      'peer',
                    ),
                    decoration: _schedulerInputDecoration(),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Select peer rubric'),
                      ),
                      ..._capstoneRubricsForEval(state, 'peer').map(
                        (rubric) => DropdownMenuItem<int?>(
                          value: _asInt(rubric['id']),
                          child: Text(rubric['name']?.toString() ?? ''),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _capstonePeerRubricId = value),
                  ),
                ),
              ] else ...[
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
                        TextField(
                          controller: _eventController,
                          decoration: _schedulerInputDecoration(
                            hintText: 'e.g. 2nd Year PIT Expo',
                          ),
                          onChanged: (_) => _prefillPitEventConfig(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _labeledField(
                              'Panel rubric *',
                              DropdownButtonFormField<int?>(
                                initialValue: rubricId,
                                decoration: _schedulerInputDecoration(),
                                items: [
                                  const DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text('Select panel rubric'),
                                  ),
                                  ...rubricItems.map(
                                    (rubric) => DropdownMenuItem<int?>(
                                      value: _asInt(rubric['id']),
                                      child: Text(
                                        rubric['name']?.toString() ?? '',
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _rubricId = value;
                                  });
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _labeledField(
                              'Peer rubric *',
                              DropdownButtonFormField<int?>(
                                initialValue: _validPeerRubricId(state),
                                decoration: _schedulerInputDecoration(),
                                items: [
                                  const DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text('Select peer rubric'),
                                  ),
                                  ..._peerRubricsForContext(state).map(
                                    (rubric) => DropdownMenuItem<int?>(
                                      value: _asInt(rubric['id']),
                                      child: Text(
                                        rubric['name']?.toString() ?? '',
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _peerRubricId = value;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _labeledField(
                              'Panel %',
                              TextField(
                                controller: _panelWeightController,
                                keyboardType: TextInputType.number,
                                decoration: _schedulerInputDecoration(),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _labeledField(
                              'Peer %',
                              TextField(
                                controller: _peerWeightController,
                                keyboardType: TextInputType.number,
                                decoration: _schedulerInputDecoration(),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Padding(
                            padding: const EdgeInsets.only(top: 22),
                            child: Text(
                              'Total ${_pitWeightTotal()}%',
                              style: TextStyle(
                                color: _pitWeightTotal() == 100
                                    ? const Color(0xFF027A48)
                                    : const Color(0xFFB42318),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.only(left: 2),
                  child: Text(
                    'Panel and peer rubrics define criteria only. The split above applies to all teams in this event.',
                    style: TextStyle(
                      color: Color(0xFF98A2B3),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
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
                  decoration: _schedulerInputDecoration(),
                ),
              ),
              if (_scope == 'capstone') ...[
                const SizedBox(height: 20),
                Container(
                  key: ValueKey('stage-info-$_stageId'),
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
                        'Stage: ${_stageLabel(state)}',
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
                    onPressed: state.isSaving ? null : _generatePlan,
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

    if (_scope == 'capstone') {
      final synced = await _syncCapstoneStageRubrics();
      if (!synced) {
        return;
      }
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
    final date = _dateController.text.trim();
    final time = _timeController.text.trim();
    final room = _roomController.text.trim();

    if (_scope == 'capstone' && _stageId == null) {
      _showSnack('Select a defense stage.');
      return null;
    }

    if (_scope == 'capstone') {
      final schedulerState = ref.read(defenseSchedulerProvider);
      if (_validCapstoneRubricId(schedulerState, _rubricId, 'panel') == null) {
        _showSnack('Select a panel rubric.');
        return null;
      }
      if (_validCapstoneRubricId(schedulerState, _adviserRubricId, 'adviser') ==
          null) {
        _showSnack('Select an adviser rubric.');
        return null;
      }
      if (_validCapstoneRubricId(
            schedulerState,
            _capstonePeerRubricId,
            'peer',
          ) ==
          null) {
        _showSnack('Select a peer rubric.');
        return null;
      }
    }

    if (_scope == 'pit' && _eventController.text.trim().isEmpty) {
      _showSnack('Enter a PIT event name.');
      return null;
    }

    if (_scope == 'pit') {
      if (_validRubricId(ref.read(defenseSchedulerProvider)) == null) {
        _showSnack('Select a panel rubric.');
        return null;
      }
      if (_validPeerRubricId(ref.read(defenseSchedulerProvider)) == null) {
        _showSnack('Select a peer rubric.');
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
    setState(() {
      _rubricId = _asInt(config['panel_rubric_id']) ?? _rubricId;
      _peerRubricId = _asInt(config['peer_rubric_id']) ?? _peerRubricId;
      _panelWeightController.text = config['panel_weight']?.toString() ?? '80';
      _peerWeightController.text = config['peer_weight']?.toString() ?? '20';
    });
  }

  Future<void> _showManualDialog(DefenseSchedulerState state) async {
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
                              items: const [
                                DropdownMenuItem(
                                  value: 'capstone',
                                  child: Text('Capstone'),
                                ),
                                DropdownMenuItem(
                                  value: 'pit',
                                  child: Text('PIT'),
                                ),
                              ],
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
                      else
                        TextField(
                          controller: event,
                          decoration: const InputDecoration(
                            labelText: 'PIT Event Name',
                          ),
                        ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int?>(
                        initialValue: validRubric,
                        decoration: const InputDecoration(
                          labelText: 'Panel Rubric',
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Select panel rubric'),
                          ),
                          ...panelRubrics.map(
                            (rubric) => DropdownMenuItem<int?>(
                              value: _asInt(rubric['id']),
                              child: Text(rubric['name']?.toString() ?? ''),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            rubricId = value;
                          });
                        },
                      ),
                      if (scope == 'capstone') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int?>(
                          initialValue: validAdviserRubric,
                          decoration: const InputDecoration(
                            labelText: 'Adviser Rubric',
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Select adviser rubric'),
                            ),
                            ...adviserRubrics.map(
                              (rubric) => DropdownMenuItem<int?>(
                                value: _asInt(rubric['id']),
                                child: Text(rubric['name']?.toString() ?? ''),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              adviserRubricId = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int?>(
                          initialValue: validCapstonePeerRubric,
                          decoration: const InputDecoration(
                            labelText: 'Peer Rubric',
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Select peer rubric'),
                            ),
                            ...capstonePeerRubrics.map(
                              (rubric) => DropdownMenuItem<int?>(
                                value: _asInt(rubric['id']),
                                child: Text(rubric['name']?.toString() ?? ''),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              capstonePeerRubricId = value;
                            });
                          },
                        ),
                      ],
                      if (scope == 'pit') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int?>(
                          initialValue: validPeerRubric,
                          decoration: const InputDecoration(
                            labelText: 'Peer Rubric',
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Select peer rubric'),
                            ),
                            ...peerRubrics.map(
                              (rubric) => DropdownMenuItem<int?>(
                                value: _asInt(rubric['id']),
                                child: Text(rubric['name']?.toString() ?? ''),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              peerRubricId = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: panelWeight,
                                decoration: const InputDecoration(
                                  labelText: 'Panel %',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: peerWeight,
                                decoration: const InputDecoration(
                                  labelText: 'Peer %',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
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
      if (rubricId == null) {
        _showSnack('Select a panel rubric.');
        return;
      }
      if (adviserRubricId == null) {
        _showSnack('Select an adviser rubric.');
        return;
      }
      if (capstonePeerRubricId == null) {
        _showSnack('Select a peer rubric.');
        return;
      }

      final semesterId = _asInt(
        ref.read(defenseSchedulerProvider).activeSemester?['id'],
      );
      if (semesterId == null) {
        _showSnack('No active semester for rubric assignment.');
        return;
      }
      final synced = await ref
          .read(defenseStagesProvider.notifier)
          .updateGradingConfig(stageId!, semesterId, {
            'panel_rubric_id': rubricId,
            'adviser_rubric_id': adviserRubricId,
            'peer_rubric_id': capstonePeerRubricId,
          });
      if (!mounted || !synced) {
        return;
      }
      setState(() {
        _scope = scope;
        _stageId = stageId;
        _rubricId = rubricId;
        _adviserRubricId = adviserRubricId;
        _capstonePeerRubricId = capstonePeerRubricId;
      });
    } else {
      if (eventText.isEmpty) {
        _showSnack('Enter a PIT event name.');
        return;
      }
      if (rubricId == null) {
        _showSnack('Select a panel rubric.');
        return;
      }
      if (peerRubricId == null) {
        _showSnack('Select a peer rubric.');
        return;
      }
      final manualPanelWeight = int.tryParse(panelWeightText) ?? 0;
      final manualPeerWeight = int.tryParse(peerWeightText) ?? 0;
      if (manualPanelWeight + manualPeerWeight != 100) {
        _showSnack('Panel and peer weights must total 100%.');
        return;
      }
      setState(() {
        _scope = scope;
        _eventController.text = eventText;
        _rubricId = rubricId;
        _peerRubricId = peerRubricId;
        _panelWeightController.text = manualPanelWeight.toString();
        _peerWeightController.text = manualPeerWeight.toString();
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
    }
    await ref
        .read(defenseSchedulerProvider.notifier)
        .createSchedule(schedulePayload);
  }

  Future<bool> _syncCapstoneStageRubrics() async {
    if (_scope != 'capstone' || _stageId == null) {
      return true;
    }
    final semesterId = _asInt(
      ref.read(defenseSchedulerProvider).activeSemester?['id'],
    );
    if (semesterId == null) {
      _showSnack('No active semester for rubric assignment.');
      return false;
    }
    return ref
        .read(defenseStagesProvider.notifier)
        .updateGradingConfig(_stageId!, semesterId, {
          'panel_rubric_id': _rubricId,
          'adviser_rubric_id': _adviserRubricId,
          'peer_rubric_id': _capstonePeerRubricId,
        });
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
}
