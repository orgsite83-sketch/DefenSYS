import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import '../models/schedule_import_models.dart';

class ScheduleRunContainer extends ConsumerStatefulWidget {
  final DefenseSchedulerState state;
  final String scope;
  final int? stageId;
  final int? rubricId;
  final int? adviserRubricId;
  final int? capstonePeerRubricId;
  final int? peerRubricId;
  final int? documenterId;
  final Set<int> selectedPanelistIds;
  final TextEditingController eventController;
  final TextEditingController panelWeightController;
  final TextEditingController peerWeightController;
  final TextEditingController dateController;
  final TextEditingController timeController;
  final TextEditingController durationController;
  final TextEditingController roomController;
  final TextEditingController pitTemplateController;
  final List<Map<String, dynamic>> planSlots;
  final bool showFinalPreview;
  final bool Function(DefenseSchedulerState state, String scope) canScheduleScope;
  final String Function(DefenseSchedulerState state) scheduleNoticeMessage;
  final ValueChanged<String> onScopeChanged;
  final ValueChanged<int?> onStageChanged;
  final ValueChanged<int?> onRubricChanged;
  final ValueChanged<int?> onAdviserRubricChanged;
  final ValueChanged<int?> onCapstonePeerRubricChanged;
  final ValueChanged<int?> onPeerRubricChanged;
  final ValueChanged<int?>? onDocumenterChanged;
  final ValueChanged<Set<int>> onPanelistsChanged;
  final ValueChanged<List<Map<String, dynamic>>> onPlanSlotsChanged;
  final ValueChanged<bool> onShowFinalPreviewChanged;
  final Future<void> Function() onPrefillCapstoneStageRubrics;
  final Future<void> Function() onPrefillPitEventConfig;

  const ScheduleRunContainer({
    super.key,
    required this.state,
    required this.scope,
    required this.stageId,
    required this.rubricId,
    required this.adviserRubricId,
    required this.capstonePeerRubricId,
    required this.peerRubricId,
    this.documenterId,
    required this.selectedPanelistIds,
    required this.eventController,
    required this.panelWeightController,
    required this.peerWeightController,
    required this.dateController,
    required this.timeController,
    required this.durationController,
    required this.roomController,
    required this.pitTemplateController,
    required this.planSlots,
    required this.showFinalPreview,
    required this.canScheduleScope,
    required this.scheduleNoticeMessage,
    required this.onScopeChanged,
    required this.onStageChanged,
    required this.onRubricChanged,
    required this.onAdviserRubricChanged,
    required this.onCapstonePeerRubricChanged,
    required this.onPeerRubricChanged,
    this.onDocumenterChanged,
    required this.onPanelistsChanged,
    required this.onPlanSlotsChanged,
    required this.onShowFinalPreviewChanged,
    required this.onPrefillCapstoneStageRubrics,
    required this.onPrefillPitEventConfig,
  });

  @override
  ConsumerState<ScheduleRunContainer> createState() =>
      _ScheduleRunContainerState();
}

class _ScheduleRunContainerState extends ConsumerState<ScheduleRunContainer> {
  bool _isGenerating = false;
  bool _isConfirming = false;

  bool _canScheduleCurrentScope() {
    return widget.canScheduleScope(widget.state, widget.scope);
  }

  List<Map<String, dynamic>> _rubricsForScopeAndStage(
    DefenseSchedulerState state,
    String scope,
    int? stageId,
  ) {
    return state.rubrics.where((rubric) {
      if (rubric['scope'] != scope) return false;
      if (scope == 'capstone' && stageId != null) {
        return asInt(rubric['defense_stage_id']) == stageId;
      }
      return true;
    }).toList();
  }

  int _getReadyTeamsCount(DefenseSchedulerState state) {
    final activeScopeTeams = teamsForScope(state, widget.scope);

    String activeStageOrEvent = '';
    if (widget.scope == 'capstone') {
      if (widget.stageId != null) {
        final stage = state.defenseStages.firstWhere(
          (s) => asInt(s['id']) == widget.stageId,
          orElse: () => <String, dynamic>{},
        );
        activeStageOrEvent = stage['label']?.toString() ?? '';
      }
    } else {
      activeStageOrEvent = widget.eventController.text.trim();
    }

    return activeScopeTeams.where((team) {
      final readyForStage = team['ready_for_stage']?.toString() ?? '';
      if (readyForStage.isEmpty) return false;
      if (activeStageOrEvent.isNotEmpty) {
        return readyForStage.toLowerCase() == activeStageOrEvent.toLowerCase();
      }
      return true;
    }).length;
  }

  List<Map<String, dynamic>> _rubricsForContext() {
    return _rubricsForScopeAndStage(widget.state, widget.scope, widget.stageId);
  }

  List<Map<String, dynamic>> _capstoneRubricsForEval(String evaluationType) {
    return _rubricsForScopeAndStage(widget.state, 'capstone', widget.stageId)
        .where((rubric) => rubric['evaluation_type']?.toString() == evaluationType)
        .toList();
  }

  int? _validCapstoneRubricId(int? rubricId, String evaluationType) {
    final rubrics = _capstoneRubricsForEval(evaluationType);
    return rubrics.any((rubric) => asInt(rubric['id']) == rubricId) ? rubricId : null;
  }

  int? _validRubricId() {
    final rubrics = _rubricsForContext();
    return rubrics.any((rubric) => asInt(rubric['id']) == widget.rubricId)
        ? widget.rubricId
        : null;
  }

  int? _validPeerRubricId() {
    final rubrics = widget.state.peerRubrics
        .where((rubric) => rubric['scope'] == 'pit')
        .toList();
    return rubrics.any((rubric) => asInt(rubric['id']) == widget.peerRubricId)
        ? widget.peerRubricId
        : null;
  }

  int _pitWeightTotal() {
    if (widget.scope != 'pit') return 100;
    final panel = int.tryParse(widget.panelWeightController.text.trim()) ?? 0;
    final peer = int.tryParse(widget.peerWeightController.text.trim()) ?? 0;
    return panel + peer;
  }

  void _recalculatePlanSlots(List<Map<String, dynamic>> slots) {
    if (slots.isEmpty) return;
    final date = widget.dateController.text.trim();
    final time = widget.timeController.text.trim();
    final duration = int.tryParse(widget.durationController.text.trim()) ?? 60;

    DateTime baseDate;
    try {
      baseDate = DateTime.tryParse(date) ?? DateTime.now();
    } catch (_) {
      baseDate = DateTime.now();
    }

    int baseHour = 8;
    int baseMinute = 0;
    final timeParts = time.split(':');
    if (timeParts.length >= 2) {
      baseHour = int.tryParse(timeParts[0]) ?? 8;
      baseMinute = int.tryParse(timeParts[1]) ?? 0;
    }

    int currentStartMinutes = baseHour * 60 + baseMinute;

    for (int i = 0; i < slots.length; i++) {
      final startMins = currentStartMinutes + (i * duration);
      final endMins = startMins + duration;

      final startH = (startMins ~/ 60).toString().padLeft(2, '0');
      final startM = (startMins % 60).toString().padLeft(2, '0');
      final endH = (endMins ~/ 60).toString().padLeft(2, '0');
      final endM = (endMins % 60).toString().padLeft(2, '0');

      slots[i]['scheduled_date'] = formatScheduleDate(baseDate);
      slots[i]['start_time'] = '$startH:$startM';
      slots[i]['end_time'] = '$endH:$endM';
    }
  }

  Map<String, dynamic>? _basePayload() {
    if (!_canScheduleCurrentScope()) {
      showValidationToast(context, widget.scheduleNoticeMessage(widget.state));
      return null;
    }

    final date = widget.dateController.text.trim();
    final time = widget.timeController.text.trim();
    final room = widget.roomController.text.trim();

    if (widget.scope == 'capstone' && widget.stageId == null) {
      showValidationToast(context, 'Select a defense stage.');
      return null;
    }

    if (widget.scope == 'capstone') {
      if (_validCapstoneRubricId(widget.rubricId, 'panel') == null ||
          _validCapstoneRubricId(widget.adviserRubricId, 'adviser') == null ||
          _validCapstoneRubricId(widget.capstonePeerRubricId, 'peer') == null) {
        showValidationToast(
          context,
          'Please configure stage rubrics in the Defense Stages Setup tab first.',
        );
        return null;
      }
    }

    if (widget.scope == 'pit' && widget.eventController.text.trim().isEmpty) {
      showValidationToast(context, 'Enter a PIT event name.');
      return null;
    }

    if (widget.scope == 'pit') {
      if (_validRubricId() == null || _validPeerRubricId() == null) {
        showValidationToast(
          context,
          'Please configure event rubrics in the PIT Events Setup tab first.',
        );
        return null;
      }
      if (_pitWeightTotal() != 100) {
        showValidationToast(context, 'Panel and peer weights must total 100%.');
        return null;
      }
    }

    if (date.isEmpty || time.isEmpty || room.isEmpty) {
      showValidationToast(context, 'Date, time, and room are required.');
      return null;
    }

    if (widget.selectedPanelistIds.isEmpty) {
      showValidationToast(context, 'Select at least one panelist.');
      return null;
    }

    final payload = <String, dynamic>{
      'scope': widget.scope,
      'defense_stage_id': widget.scope == 'capstone' ? widget.stageId : null,
      'event_name': widget.scope == 'pit' ? widget.eventController.text.trim() : '',
      'rubric_id': _validRubricId(),
      'scheduled_date': date,
      'start_time': time,
      'slot_duration': int.tryParse(widget.durationController.text.trim()) ?? 60,
      'room': room,
      'panelist_ids': widget.selectedPanelistIds.toList(),
      if (widget.scope == 'capstone' && widget.documenterId != null)
        'documenter_id': widget.documenterId,
    };

    if (widget.scope == 'pit') {
      payload['peer_rubric_id'] = _validPeerRubricId();
      payload['panel_weight'] =
          int.tryParse(widget.panelWeightController.text.trim()) ?? 80;
      payload['peer_weight'] =
          int.tryParse(widget.peerWeightController.text.trim()) ?? 20;
    }
    return payload;
  }

  Future<void> _generatePlan() async {
    if (!_canScheduleCurrentScope()) {
      showValidationToast(context, widget.scheduleNoticeMessage(widget.state));
      return;
    }

    final payload = _basePayload();
    if (payload == null) return;

    setState(() => _isGenerating = true);
    try {
      final ok = await ref
          .read(defenseSchedulerProvider.notifier)
          .generatePlan(payload);
      if (!mounted || !ok) return;

      final generated = ref
          .read(defenseSchedulerProvider)
          .generatedSlots
          .map((slot) => Map<String, dynamic>.from(slot))
          .toList();

      _recalculatePlanSlots(generated);
      widget.onPlanSlotsChanged(generated);
      widget.onShowFinalPreviewChanged(false);
      showSuccessToast(context, 'Generated ${generated.length} schedule slots.');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _confirmPlan() async {
    final payload = _basePayload();
    if (payload == null || widget.planSlots.isEmpty) return;

    payload['slots'] = widget.planSlots
        .map((slot) => {'team_id': asInt(slot['team_id'])})
        .toList();

    setState(() => _isConfirming = true);
    try {
      final ok = await ref
          .read(defenseSchedulerProvider.notifier)
          .confirmPlan(payload);
      if (!mounted || !ok) return;

      widget.onPlanSlotsChanged([]);
      widget.onShowFinalPreviewChanged(false);
      showSuccessToast(context, 'Schedule plan successfully saved.');
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  Widget _schedulerCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEAECF0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08101828),
            blurRadius: 8,
            offset: Offset(0, 2),
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
            color: Color(0xFF344054),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  InputDecoration _schedulerInputDecoration({
    Widget? suffixIcon,
    String? hintText,
  }) {
    return InputDecoration(
      isDense: true,
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFF98A2B3), fontSize: 14),
      filled: true,
      fillColor: Colors.white,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        borderSide: const BorderSide(color: AppColors.maroon, width: 1.5),
      ),
    );
  }

  Widget _softBadge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _scheduleDateField({required TextEditingController controller}) {
    return InkWell(
      onTap: () async {
        final currentText = controller.text.trim();
        DateTime initialDate = DateTime.now();
        if (currentText.isNotEmpty) {
          initialDate = DateTime.tryParse(currentText) ?? DateTime.now();
        }

        final picked = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: AppColors.maroon,
                  onPrimary: Colors.white,
                  onSurface: AppColors.textPrimary,
                ),
              ),
              child: child!,
            );
          },
        );

        if (picked != null) {
          controller.text = formatScheduleDate(picked);
          if (widget.planSlots.isNotEmpty) {
            final copy = List<Map<String, dynamic>>.from(widget.planSlots);
            _recalculatePlanSlots(copy);
            widget.onPlanSlotsChanged(copy);
          }
          setState(() {});
        }
      },
      child: IgnorePointer(
        child: TextFormField(
          controller: controller,
          decoration: _schedulerInputDecoration(
            suffixIcon: const Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: Color(0xFF667085),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scheduleTimeField({required TextEditingController controller}) {
    return InkWell(
      onTap: () async {
        final currentText = controller.text.trim();
        TimeOfDay initialTime = const TimeOfDay(hour: 8, minute: 0);
        if (currentText.isNotEmpty) {
          final parts = currentText.split(':');
          if (parts.length >= 2) {
            final h = int.tryParse(parts[0]);
            final m = int.tryParse(parts[1]);
            if (h != null && m != null) {
              initialTime = TimeOfDay(hour: h, minute: m);
            }
          }
        }

        final picked = await showTimePicker(
          context: context,
          initialTime: initialTime,
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: AppColors.maroon,
                  onPrimary: Colors.white,
                  onSurface: AppColors.textPrimary,
                ),
              ),
              child: child!,
            );
          },
        );

        if (picked != null) {
          final hh = picked.hour.toString().padLeft(2, '0');
          final mm = picked.minute.toString().padLeft(2, '0');
          controller.text = '$hh:$mm';
          if (widget.planSlots.isNotEmpty) {
            final copy = List<Map<String, dynamic>>.from(widget.planSlots);
            _recalculatePlanSlots(copy);
            widget.onPlanSlotsChanged(copy);
          }
          setState(() {});
        }
      },
      child: IgnorePointer(
        child: TextFormField(
          controller: controller,
          decoration: _schedulerInputDecoration(
            suffixIcon: const Icon(
              Icons.access_time_outlined,
              size: 18,
              color: Color(0xFF667085),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStageWarnings(DefenseSchedulerState state) {
    if (widget.scope != 'capstone' || widget.stageId == null) {
      return const SizedBox.shrink();
    }
    final stages = state.defenseStages;
    final targetStage = stages.firstWhere(
      (s) => asInt(s['id']) == widget.stageId,
      orElse: () => <String, dynamic>{},
    );
    if (targetStage.isEmpty) return const SizedBox.shrink();

    final readyTeamsCount = state.teams.where((team) {
      final readyForStage = team['ready_for_stage']?.toString() ?? '';
      final teamLevel = team['level']?.toString() ?? '';
      final isCapstone = teamLevel.toLowerCase().contains('capstone');
      return isCapstone && readyForStage == targetStage['label'];
    }).length;

    final isOfficiallyComplete = targetStage['is_officially_complete'] == true;

    if (isOfficiallyComplete) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3F2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFECDCA)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 16, color: Color(0xFFD92D20)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This stage is marked officially complete. Scheduling new defenses for this stage is disabled.',
                style: const TextStyle(
                  color: Color(0xFFB42318),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (readyTeamsCount == 0) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFAEB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFEDF89)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFDC6803)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No teams are currently ready for ${targetStage['label'] ?? 'this stage'}. Teams must have pre-defense deliverables approved by their instructor.',
                style: const TextStyle(
                  color: Color(0xFFB54708),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _summaryInfoCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: AppColors.maroon),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
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
    final stageId = stages.any((stage) => asInt(stage['id']) == widget.stageId)
        ? widget.stageId
        : null;

    final selectedPanelists = state.panelists.where((panelist) {
      final id = asInt(panelist['id']);
      return id != null && widget.selectedPanelistIds.contains(id);
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
                          'Step 1: Set Up Defense Schedule',
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
                widget.scope == 'pit'
                    ? 'Choose the PIT event, date, room, start time, and slot duration for this batch. Then generate the plan to prepare consecutive slots.'
                    : 'Choose the shared stage, date, room, start time, and slot duration for this batch. Then generate the plan to prepare consecutive slots.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              if (widget.scope == 'capstone') ...[
                _labeledField(
                  'Stage *',
                  DropdownButtonFormField<int?>(
                    value: stageId,
                    decoration: _schedulerInputDecoration(),
                    items: stages
                        .map(
                          (stage) => DropdownMenuItem<int?>(
                            value: asInt(stage['id']),
                            child: Text(stage['label']?.toString() ?? ''),
                          ),
                        )
                        .toList(),
                    onChanged: (value) async {
                      widget.onScopeChanged('capstone');
                      widget.onStageChanged(value);
                      widget.onRubricChanged(null);
                      widget.onAdviserRubricChanged(null);
                      widget.onCapstonePeerRubricChanged(null);
                      widget.onPlanSlotsChanged([]);
                      widget.onShowFinalPreviewChanged(false);
                      await widget.onPrefillCapstoneStageRubrics();
                    },
                  ),
                ),
                _buildStageWarnings(state),
              ] else if (widget.scope == 'pit') ...[
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
                        'PIT event setup (this batch)',
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
                          value: state.pitEvents.any((e) => e['event_name'] == widget.eventController.text)
                              ? widget.eventController.text
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
                              widget.eventController.text = val;
                              widget.onPrefillPitEventConfig();
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
                      _scheduleDateField(controller: widget.dateController),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _labeledField(
                      'Start time *',
                      _scheduleTimeField(controller: widget.timeController),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _labeledField(
                      'Slot Duration (mins) *',
                      TextFormField(
                        controller: widget.durationController,
                        keyboardType: TextInputType.number,
                        decoration: _schedulerInputDecoration(),
                        onChanged: (_) {
                          if (widget.planSlots.isNotEmpty) {
                            final copy = List<Map<String, dynamic>>.from(widget.planSlots);
                            _recalculatePlanSlots(copy);
                            widget.onPlanSlotsChanged(copy);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _labeledField(
                      'Room / Venue *',
                      TextFormField(
                        controller: widget.roomController,
                        decoration: _schedulerInputDecoration(
                          hintText: 'e.g. Lab 3',
                        ),
                        onChanged: (_) {
                          if (widget.planSlots.isNotEmpty) {
                            final copy = List<Map<String, dynamic>>.from(widget.planSlots);
                            for (final s in copy) {
                              s['room'] = widget.roomController.text.trim();
                            }
                            widget.onPlanSlotsChanged(copy);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.scope == 'capstone') ...[
                const SizedBox(height: 18),
                _labeledField(
                  'Documenter (Optional)',
                  DropdownButtonFormField<int?>(
                    value: widget.state.documenters.any((doc) => asInt(doc['id']) == widget.documenterId && !widget.selectedPanelistIds.contains(asInt(doc['id'])))
                        ? widget.documenterId
                        : null,
                    decoration: _schedulerInputDecoration(
                      hintText: 'Select Documenter (Optional)',
                    ),
                    dropdownColor: Colors.white,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('— Select Documenter (Optional) —'),
                      ),
                      ...widget.state.documenters
                          .where((doc) => !widget.selectedPanelistIds.contains(asInt(doc['id'])))
                          .map(
                            (doc) => DropdownMenuItem<int?>(
                              value: asInt(doc['id']),
                              child: Text(doc['name']?.toString() ?? ''),
                            ),
                          ),
                    ],
                    onChanged: (val) => widget.onDocumenterChanged?.call(val),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isGenerating ? null : _generatePlan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.maroon,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.auto_awesome, size: 20),
                  label: Text(
                    _isGenerating ? 'Generating Plan...' : 'Generate Schedule Plan',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        final right = Column(
          children: [
            _schedulerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Available Panelists (*)',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Select panelists to assign to generated slots.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _softBadge(
                        '${widget.selectedPanelistIds.length} selected',
                        const Color(0xFFF2F4F7),
                        const Color(0xFF344054),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          final allIds = state.panelists
                              .map((p) => asInt(p['id']))
                              .whereType<int>()
                              .toSet();
                          widget.onPanelistsChanged(allIds);
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Select All',
                          style: TextStyle(
                            color: AppColors.maroon,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => widget.onPanelistsChanged({}),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Clear All',
                          style: TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: state.panelists.map((panelist) {
                          final id = asInt(panelist['id']);
                          final name = panelist['name']?.toString() ??
                              panelist['full_name']?.toString() ??
                              panelist['username']?.toString() ??
                              'Panelist';
                          final selected = id != null &&
                              widget.selectedPanelistIds.contains(id);

                          return FilterChip(
                            label: Text(
                              name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    selected ? FontWeight.w700 : FontWeight.w500,
                                color: selected
                                    ? AppColors.maroon
                                    : const Color(0xFF344054),
                              ),
                            ),
                            selected: selected,
                            onSelected: id == null
                                ? null
                                : (val) {
                                    final copy = Set<int>.from(
                                      widget.selectedPanelistIds,
                                    );
                                    if (val) {
                                      copy.add(id);
                                    } else {
                                      copy.remove(id);
                                    }
                                    widget.onPanelistsChanged(copy);
                                  },
                            backgroundColor: const Color(0xFFF8FAFC),
                            selectedColor: const Color(0xFFFEECEC),
                            checkmarkColor: AppColors.maroon,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: selected
                                    ? AppColors.maroon
                                    : const Color(0xFFE2E8F0),
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
            const SizedBox(height: 16),
            _schedulerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Schedule Overview',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _summaryInfoCard(
                    'Target Scope',
                    widget.scope.toUpperCase(),
                    Icons.layers_outlined,
                  ),
                  const SizedBox(height: 10),
                  _summaryInfoCard(
                    'Selected Panelists',
                    '${selectedPanelists.length} assigned',
                    Icons.people_outline,
                  ),
                  const SizedBox(height: 10),
                  _summaryInfoCard(
                    'Ready Teams',
                    '${_getReadyTeamsCount(state)} teams ready',
                    Icons.check_circle_outline,
                  ),
                ],
              ),
            ),
          ],
        );

        if (narrow) {
          return Column(
            children: [
              left,
              const SizedBox(height: 20),
              right,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: left),
            const SizedBox(width: 20),
            Expanded(flex: 2, child: right),
          ],
        );
      },
    );
  }

  Widget _planTableHeader(List<String> headers) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: headers
            .map(
              (h) => Expanded(
                child: Text(
                  h,
                  style: const TextStyle(
                    color: Color(0xFF475467),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
            .toList(),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              team,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              stage,
              style: const TextStyle(
                color: Color(0xFF475467),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$date $time',
              style: const TextStyle(
                color: Color(0xFF475467),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              room,
              style: const TextStyle(
                color: Color(0xFF475467),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              panel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF475467),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFF04438)),
            onPressed: onDelete,
            tooltip: 'Remove slot',
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              team,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              stage,
              style: const TextStyle(
                color: Color(0xFF475467),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$date $time',
              style: const TextStyle(
                color: Color(0xFF475467),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              room,
              style: const TextStyle(
                color: Color(0xFF475467),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              panel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF475467),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _panelNamesFromSelection(DefenseSchedulerState state) {
    final names = state.panelists
        .where((p) {
          final id = asInt(p['id']);
          return id != null && widget.selectedPanelistIds.contains(id);
        })
        .map((p) => p['name']?.toString() ?? p['full_name']?.toString() ?? p['username']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return 'No panelists assigned';
    return names.join(', ');
  }

  Widget _buildStepTwo(DefenseSchedulerState state) {
    return _schedulerCard(
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
                        '2',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Step 2: Review & Arrange Teams',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              _softBadge(
                '${widget.planSlots.length} slots prepared',
                const Color(0xFFEFF8FF),
                const Color(0xFF175CD3),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 16),
          const Text(
            'Review the generated slot sequence. You can reorder teams or remove individual slots before finalizing.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          _planTableHeader(const [
            '#',
            'Team Name',
            'Stage / Event',
            'Date & Time',
            'Room',
            'Assigned Panel',
            'Actions',
          ]),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.planSlots.length,
            onReorder: (oldIndex, newIndex) {
              final copy = List<Map<String, dynamic>>.from(widget.planSlots);
              if (newIndex > oldIndex) newIndex -= 1;
              final item = copy.removeAt(oldIndex);
              copy.insert(newIndex, item);
              _recalculatePlanSlots(copy);
              widget.onPlanSlotsChanged(copy);
            },
            itemBuilder: (context, index) {
              final slot = widget.planSlots[index];
              return _planTableRow(
                key: ValueKey(slot['team_id'] ?? index),
                index: index,
                team: slot['team_name']?.toString() ?? 'Team',
                stage: slot['stage_label']?.toString() ??
                    slot['event_name']?.toString() ??
                    'Stage',
                date: slot['scheduled_date']?.toString() ?? '',
                time: slot['start_time']?.toString() ?? '',
                room: slot['room']?.toString() ?? '',
                panel: _panelNamesFromSelection(state),
                onDelete: () {
                  final copy = List<Map<String, dynamic>>.from(widget.planSlots);
                  copy.removeAt(index);
                  _recalculatePlanSlots(copy);
                  widget.onPlanSlotsChanged(copy);
                },
              );
            },
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  widget.onPlanSlotsChanged([]);
                  widget.onShowFinalPreviewChanged(false);
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text(
                  'Back to Step 1',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 14),
              ElevatedButton.icon(
                onPressed: () => widget.onShowFinalPreviewChanged(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.maroon,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text(
                  'Proceed to Final Preview',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepThree(DefenseSchedulerState state) {
    return _schedulerCard(
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
                        '3',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Step 3: Final Schedule Preview',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              _softBadge(
                'Ready to Save',
                const Color(0xFFECFDF3),
                const Color(0xFF027A48),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 16),
          const Text(
            'Final verification. Confirm all details below. Click "Publish & Save Schedule" to persist these slots.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          _planTableHeader(const [
            '#',
            'Team Name',
            'Stage / Event',
            'Date & Time',
            'Room',
            'Assigned Panel',
          ]),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.planSlots.length,
            itemBuilder: (context, index) {
              final slot = widget.planSlots[index];
              return _finalPreviewRow(
                index: index,
                team: slot['team_name']?.toString() ?? 'Team',
                stage: slot['stage_label']?.toString() ??
                    slot['event_name']?.toString() ??
                    'Stage',
                date: slot['scheduled_date']?.toString() ?? '',
                time: slot['start_time']?.toString() ?? '',
                room: slot['room']?.toString() ?? '',
                panel: _panelNamesFromSelection(state),
              );
            },
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => widget.onShowFinalPreviewChanged(false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text(
                  'Back to Step 2',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 14),
              ElevatedButton.icon(
                onPressed: _isConfirming ? null : _confirmPlan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.maroon,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                icon: _isConfirming
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: Text(
                  _isConfirming ? 'Saving Schedule...' : 'Publish & Save Schedule',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentStep = widget.planSlots.isEmpty
        ? 1
        : (widget.showFinalPreview ? 3 : 2);

    if (currentStep == 1) return _buildStepOne(widget.state);
    if (currentStep == 2) return _buildStepTwo(widget.state);
    return _buildStepThree(widget.state);
  }
}

// Alias for convenience
typedef ScheduleContainer = ScheduleRunContainer;
