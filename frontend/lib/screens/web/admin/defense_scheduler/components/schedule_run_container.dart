import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'scheduler_people_picker.dart';

import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import '../models/schedule_import_models.dart';
import '../dialogs/panelist_pool_dialog.dart';
import '../../user_management/external_evaluators/external_evaluator_views.dart';
import 'package:defensys/services/admin/external_evaluator_provider.dart';

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
  final bool Function(DefenseSchedulerState state, String scope)
  canScheduleScope;
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
  int? _selectedChairId;
  Set<int> _externalIds = {};
  DateTime? _guestExpiry;

  int? get _effectiveChairId {
    if (_selectedChairId != null &&
        widget.selectedPanelistIds.contains(_selectedChairId)) {
      return _selectedChairId;
    }
    return widget.selectedPanelistIds.isNotEmpty
        ? widget.selectedPanelistIds.first
        : null;
  }

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
        .where(
          (rubric) => rubric['evaluation_type']?.toString() == evaluationType,
        )
        .toList();
  }

  int? _validCapstoneRubricId(int? rubricId, String evaluationType) {
    final rubrics = _capstoneRubricsForEval(evaluationType);
    return rubrics.any((rubric) => asInt(rubric['id']) == rubricId)
        ? rubricId
        : null;
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

    final effectiveChair = _effectiveChairId;
    final payload = <String, dynamic>{
      'scope': widget.scope,
      'defense_stage_id': widget.scope == 'capstone' ? widget.stageId : null,
      'event_name': widget.scope == 'pit'
          ? widget.eventController.text.trim()
          : '',
      'rubric_id': _validRubricId(),
      'scheduled_date': date,
      'start_time': time,
      'slot_duration':
          int.tryParse(widget.durationController.text.trim()) ?? 60,
      'room': room,
      'panelist_ids': widget.selectedPanelistIds.toList(),
      'external_evaluator_ids': _externalIds.toList(),
      if (_guestExpiry != null)
        'guest_access_expires_at': _guestExpiry!.toUtc().toIso8601String(),
      if (effectiveChair != null) 'chair_panelist_id': effectiveChair,
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
      showSuccessToast(
        context,
        'Generated ${generated.length} schedule slots.',
      );
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
      await GuestInvitationDialog.show(
        context,
        ref.read(defenseSchedulerProvider).createdInvitations,
      );
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textPrimary =>
      _isDark ? DefensysTokens.mistTextPrimary : AppColors.textPrimary;
  Color get _textSecondary =>
      _isDark ? DefensysTokens.mistTextSecondary : AppColors.textSecondary;

  Widget _schedulerCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistSurface : Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.borderOf(context)),
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
          style: TextStyle(
            color: _isDark
                ? DefensysTokens.mistTextSecondary
                : const Color(0xFF344054),
            fontSize: 13,
            fontWeight: FontWeight.w500,
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
      hintStyle: TextStyle(
        color: _isDark
            ? DefensysTokens.mistTextSecondary.withValues(alpha: 0.6)
            : const Color(0xFF98A2B3),
        fontSize: 14,
      ),
      filled: true,
      fillColor: DefensysTokens.surfaceOf(context),
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        borderSide: BorderSide(
          color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFD0D5DD),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        borderSide: BorderSide(
          color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFD0D5DD),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        borderSide: BorderSide(color: _textPrimary, width: 1.5),
      ),
    );
  }

  Widget _softBadge(String text, Color bg, Color fg) {
    Color effectiveBg = bg;
    Color effectiveFg = fg;
    if (_isDark) {
      if (fg == const Color(0xFF175CD3)) {
        effectiveBg = const Color(0xFF1E3A8A).withValues(alpha: 0.35);
        effectiveFg = const Color(0xFF93C5FD);
      } else if (fg == const Color(0xFF027A48)) {
        effectiveBg = const Color(0xFF064E3B).withValues(alpha: 0.35);
        effectiveFg = const Color(0xFF6EE7B7);
      } else if (fg == const Color(0xFF92400E) ||
          fg == const Color(0xFFB45309)) {
        effectiveBg = const Color(0xFF78350F).withValues(alpha: 0.35);
        effectiveFg = const Color(0xFFFCD34D);
      } else if (fg == const Color(0xFFB42318) ||
          fg == const Color(0xFFEF4444) ||
          fg == const Color(0xFFF04438)) {
        effectiveBg = const Color(0xFF7F1D1D).withValues(alpha: 0.35);
        effectiveFg = const Color(0xFFFCA5A5);
      } else {
        effectiveBg = DefensysTokens.mistInputFill;
        effectiveFg = DefensysTokens.mistTextSecondary;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: effectiveFg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
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
                colorScheme: _isDark
                    ? const ColorScheme.dark(
                        primary: AppColors.maroon,
                        onPrimary: Colors.white,
                        surface: DefensysTokens.mistSurface,
                        onSurface: DefensysTokens.mistTextPrimary,
                      )
                    : const ColorScheme.light(
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
          style: TextStyle(color: _textPrimary, fontSize: 14),
          decoration: _schedulerInputDecoration(
            suffixIcon: Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: _isDark
                  ? DefensysTokens.mistTextSecondary
                  : const Color(0xFF667085),
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
                colorScheme: _isDark
                    ? const ColorScheme.dark(
                        primary: AppColors.maroon,
                        onPrimary: Colors.white,
                        surface: DefensysTokens.mistSurface,
                        onSurface: DefensysTokens.mistTextPrimary,
                      )
                    : const ColorScheme.light(
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
          style: TextStyle(color: _textPrimary, fontSize: 14),
          decoration: _schedulerInputDecoration(
            suffixIcon: Icon(
              Icons.access_time_outlined,
              size: 18,
              color: _isDark
                  ? DefensysTokens.mistTextSecondary
                  : const Color(0xFF667085),
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
          color: _isDark
              ? const Color(0xFF7F1D1D).withValues(alpha: 0.25)
              : const Color(0xFFFEF3F2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECDCA),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 16,
              color: _isDark
                  ? const Color(0xFFF87171)
                  : const Color(0xFFD92D20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This stage is marked officially complete. Scheduling new defenses for this stage is disabled.',
                style: TextStyle(
                  color: _isDark
                      ? const Color(0xFFFCA5A5)
                      : const Color(0xFFB42318),
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
          color: _isDark
              ? const Color(0xFF78350F).withValues(alpha: 0.25)
              : const Color(0xFFFFFAEB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isDark ? const Color(0xFF78350F) : const Color(0xFFFEDF89),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 16,
              color: _isDark
                  ? const Color(0xFFFBBF24)
                  : const Color(0xFFDC6803),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No teams are currently ready for ${targetStage['label'] ?? 'this stage'}. Teams must have pre-defense deliverables approved by their instructor.',
                style: TextStyle(
                  color: _isDark
                      ? const Color(0xFFFCD34D)
                      : const Color(0xFFB54708),
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

  Widget _setupHeading(String title, String description, {Widget? trailing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(color: _textSecondary, fontSize: 12, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildStepOne(DefenseSchedulerState state) {
    final stages = state.defenseStages;
    final stageId = stages.any((stage) => asInt(stage['id']) == widget.stageId)
        ? widget.stageId
        : null;
    final selectedPanelists = state.selectablePanelists
        .where(
          (person) => widget.selectedPanelistIds.contains(asInt(person['id'])),
        )
        .toList();
    final availableDocumenters = state.documenters
        .where(
          (person) => !widget.selectedPanelistIds.contains(asInt(person['id'])),
        )
        .toList();
    final busy = _isGenerating || _isConfirming;
    final readyCount = _getReadyTeamsCount(state);

    void changePanelists(Set<int> ids) {
      if (ids.contains(widget.documenterId)) {
        widget.onDocumenterChanged?.call(null);
      }
      if (!ids.contains(_selectedChairId)) {
        setState(() => _selectedChairId = null);
      }
      widget.onPanelistsChanged(ids);
    }

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _setupHeading(
          'Schedule details',
          'Set the shared timing and venue for this batch.',
        ),
        const SizedBox(height: 20),
        if (widget.scope == 'capstone') ...[
          _labeledField(
            'Stage *',
            LayoutBuilder(
              builder: (context, constraints) => ShadSelect<int>(
                key: ValueKey('stage-$stageId'),
                initialValue: stageId,
                enabled: !busy,
                minWidth: constraints.maxWidth,
                maxWidth: constraints.maxWidth,
                placeholder: const Text('Select a defense stage'),
                options: [
                  for (final stage in stages)
                    if (asInt(stage['id']) != null)
                      ShadOption<int>(
                        value: asInt(stage['id'])!,
                        child: Text(stage['label']?.toString() ?? ''),
                      ),
                ],
                selectedOptionBuilder: (_, id) => Text(
                  stages
                          .firstWhere(
                            (stage) => asInt(stage['id']) == id,
                          )['label']
                          ?.toString() ??
                      '',
                  overflow: TextOverflow.ellipsis,
                ),
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
          ),
          _buildStageWarnings(state),
        ] else ...[
          _labeledField(
            'Event name *',
            LayoutBuilder(
              builder: (context, constraints) => ShadSelect<String>(
                key: ValueKey('event-${widget.eventController.text}'),
                initialValue:
                    state.pitEvents.any(
                      (event) =>
                          event['event_name'] == widget.eventController.text,
                    )
                    ? widget.eventController.text
                    : null,
                enabled: !busy,
                minWidth: constraints.maxWidth,
                maxWidth: constraints.maxWidth,
                placeholder: const Text('Select PIT event'),
                options: [
                  for (final event in state.pitEvents)
                    ShadOption<String>(
                      value: event['event_name']?.toString() ?? '',
                      child: Text(event['event_name']?.toString() ?? ''),
                    ),
                ],
                selectedOptionBuilder: (_, value) =>
                    Text(value, overflow: TextOverflow.ellipsis),
                onChanged: (value) {
                  if (value == null) return;
                  widget.eventController.text = value;
                  widget.onPrefillPitEventConfig();
                  setState(() {});
                },
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _setupFieldPair(
          _labeledField(
            'Date *',
            _scheduleDateField(controller: widget.dateController),
          ),
          _labeledField(
            'Start time *',
            _scheduleTimeField(controller: widget.timeController),
          ),
        ),
        const SizedBox(height: 20),
        _setupFieldPair(
          _labeledField(
            'Slot duration (minutes) *',
            ShadInput(
              controller: widget.durationController,
              enabled: !busy,
              keyboardType: TextInputType.number,
            ),
          ),
          _labeledField(
            'Room / venue *',
            ShadInput(
              controller: widget.roomController,
              enabled: !busy,
              placeholder: const Text('e.g. Lab 3'),
            ),
          ),
        ),
      ],
    );

    final people = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _setupHeading(
          'Faculty panelists *',
          state.canApprovePanelists
              ? 'New faculty are approved when you confirm the schedule.'
              : 'Choose eligible faculty or request approval in the pool.',
          trailing: const PanelistPoolButton(compact: true),
        ),
        const SizedBox(height: 12),
        SchedulerPeoplePicker(
          key: const ValueKey('faculty-panelist-picker'),
          people: state.selectablePanelists,
          selected: widget.selectedPanelistIds,
          onChanged: changePanelists,
          placeholder: 'Choose faculty panelists',
          enabled: !busy,
          emptyMessage:
              'No eligible faculty. Manage the pool to request approval.',
          detailBuilder: (person) {
            final id = asInt(person['id']);
            return state.canApprovePanelists &&
                    id != null &&
                    !state.isEligiblePanelist(id)
                ? 'Approval included on confirmation'
                : 'Eligible panelist';
          },
        ),
        if (state.selectablePanelists.isEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'No eligible faculty. Manage the pool to request approval.',
            style: TextStyle(color: _textSecondary, fontSize: 12),
          ),
        ],
        if (selectedPanelists.isNotEmpty) ...[
          const SizedBox(height: 16),
          _labeledField(
            'Presiding panel chair',
            LayoutBuilder(
              builder: (context, constraints) => ShadSelect<int>(
                key: const ValueKey('presiding-panel-chair'),
                initialValue: _effectiveChairId,
                enabled: !busy,
                minWidth: constraints.maxWidth,
                maxWidth: constraints.maxWidth,
                maxHeight: 240,
                options: [
                  for (final person in selectedPanelists)
                    ShadOption<int>(
                      value: asInt(person['id'])!,
                      child: Text(schedulerPersonName(person)),
                    ),
                ],
                selectedOptionBuilder: (_, id) => Text(
                  schedulerPersonName(
                    selectedPanelists.firstWhere(
                      (person) => asInt(person['id']) == id,
                    ),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                onChanged: (id) => setState(() => _selectedChairId = id),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Issues the official stage verdict.',
            style: TextStyle(color: _textSecondary, fontSize: 12),
          ),
        ],
        ExternalEvaluatorSelector(
          compact: true,
          selected: _externalIds,
          onChanged: (ids) => setState(() => _externalIds = ids),
          expiry: _guestExpiry,
          onExpiryChanged: (expiry) => setState(() => _guestExpiry = expiry),
          enabled: !busy,
        ),
        if (widget.scope == 'capstone') ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Divider(height: 1, color: DefensysTokens.borderOf(context)),
          ),
          _setupHeading(
            'Documenter',
            'Optional. Records the minutes for this batch.',
          ),
          const SizedBox(height: 12),
          SchedulerPeoplePicker(
            key: const ValueKey('documenter-picker'),
            people: availableDocumenters,
            selected: {if (widget.documenterId != null) widget.documenterId!},
            onChanged: (ids) =>
                widget.onDocumenterChanged?.call(ids.firstOrNull),
            placeholder: 'Choose a documenter',
            multiple: false,
            enabled: !busy && widget.onDocumenterChanged != null,
            emptyMessage:
                'No available documenters. Panelists cannot record minutes.',
          ),
          if (availableDocumenters.isEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'No available documenters. A panelist cannot also record minutes.',
              style: TextStyle(color: _textSecondary, fontSize: 12),
            ),
          ],
        ],
      ],
    );

    return _schedulerCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 880) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    details,
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Divider(
                        height: 1,
                        color: DefensysTokens.borderOf(context),
                      ),
                    ),
                    people,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 32),
                      child: details,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.only(left: 32),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: DefensysTokens.borderOf(context),
                          ),
                        ),
                      ),
                      child: people,
                    ),
                  ),
                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Divider(height: 1, color: DefensysTokens.borderOf(context)),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final summary = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$readyCount ${readyCount == 1 ? 'team' : 'teams'} ready to schedule',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.scope == 'pit' ? 'PIT' : 'Capstone'} batch / '
                    '${selectedPanelists.length} faculty / ${_externalIds.length} external',
                    style: TextStyle(color: _textSecondary, fontSize: 12),
                  ),
                ],
              );
              final action = ShadButton(
                onPressed: busy ? null : _generatePlan,
                leading: _isGenerating
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _isDark
                              ? DefensysTokens.textPrimary
                              : DefensysTokens.surface,
                        ),
                      )
                    : null,
                trailing: _isGenerating
                    ? null
                    : const Icon(LucideIcons.arrowRight, size: 16),
                child: Text(
                  _isGenerating ? 'Generating plan...' : 'Generate plan',
                ),
              );
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [summary, const SizedBox(height: 16), action],
                );
              }
              return Row(
                children: [
                  Expanded(child: summary),
                  const SizedBox(width: 16),
                  action,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _setupFieldPair(Widget first, Widget second) => LayoutBuilder(
    builder: (_, constraints) => constraints.maxWidth < 360
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 20), second],
          )
        : Row(
            children: [
              Expanded(child: first),
              const SizedBox(width: 16),
              Expanded(child: second),
            ],
          ),
  );

  Widget _planTableHeader(List<String> headers) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(
          bottom: BorderSide(
            color: _isDark
                ? DefensysTokens.mistBorder
                : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: headers
            .map(
              (h) => Expanded(
                child: Text(
                  h,
                  style: TextStyle(
                    color: _isDark
                        ? DefensysTokens.mistTextSecondary
                        : const Color(0xFF475467),
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
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: _isDark
                ? DefensysTokens.mistBorder.withValues(alpha: 0.5)
                : const Color(0xFFF1F5F9),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              team,
              style: TextStyle(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              stage,
              style: TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$date $time',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              room,
              style: TextStyle(
                color: _textSecondary,
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
              style: TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: Color(0xFFF04438),
            ),
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
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: _isDark
                ? DefensysTokens.mistBorder.withValues(alpha: 0.5)
                : const Color(0xFFF1F5F9),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              team,
              style: TextStyle(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              stage,
              style: TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$date $time',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              room,
              style: TextStyle(
                color: _textSecondary,
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
              style: TextStyle(
                color: _textSecondary,
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
    final effectiveChair = _effectiveChairId;
    final names = state.selectablePanelists
        .where((p) {
          final id = asInt(p['id']);
          return id != null && widget.selectedPanelistIds.contains(id);
        })
        .map((p) {
          final id = asInt(p['id']);
          final name =
              p['name']?.toString() ??
              p['full_name']?.toString() ??
              p['username']?.toString() ??
              '';
          if (id == effectiveChair) {
            return '👑 $name (Chair)';
          }
          return name;
        })
        .where((n) => n.isNotEmpty)
        .toList();
    names.addAll(
      ref
          .read(externalEvaluatorProvider)
          .approved
          .where((e) => _externalIds.contains(e['id']))
          .map((e) => '${e['name']} (External)'),
    );
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
              Expanded(
                child: Row(
                  children: [
                    const CircleAvatar(
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
                    const SizedBox(width: 10),
                    Text(
                      'Step 2: Review & Arrange Teams',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: _textPrimary,
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
          Divider(height: 1, color: _isDark ? DefensysTokens.mistBorder : null),
          const SizedBox(height: 16),
          Text(
            'Review the generated slot sequence. You can reorder teams or remove individual slots before finalizing.',
            style: TextStyle(
              color: _textSecondary,
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
                stage:
                    slot['stage_label']?.toString() ??
                    slot['event_name']?.toString() ??
                    'Stage',
                date: slot['scheduled_date']?.toString() ?? '',
                time: slot['start_time']?.toString() ?? '',
                room: slot['room']?.toString() ?? '',
                panel: _panelNamesFromSelection(state),
                onDelete: () {
                  final copy = List<Map<String, dynamic>>.from(
                    widget.planSlots,
                  );
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
                  backgroundColor: _isDark
                      ? DefensysTokens.mistInputFill
                      : Colors.white,
                  foregroundColor: _isDark
                      ? DefensysTokens.mistTextPrimary
                      : AppColors.textPrimary,
                  side: BorderSide(
                    color: _isDark
                        ? DefensysTokens.mistBorder
                        : const Color(0xFFCBD5E1),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
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
              Expanded(
                child: Row(
                  children: [
                    const CircleAvatar(
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
                    const SizedBox(width: 10),
                    Text(
                      'Step 3: Final Schedule Preview',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: _textPrimary,
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
          Divider(height: 1, color: _isDark ? DefensysTokens.mistBorder : null),
          const SizedBox(height: 16),
          Text(
            'Final verification. Confirm all details below. Click "Publish & Save Schedule" to persist these slots.',
            style: TextStyle(
              color: _textSecondary,
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
                stage:
                    slot['stage_label']?.toString() ??
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
                  backgroundColor: _isDark
                      ? DefensysTokens.mistInputFill
                      : Colors.white,
                  foregroundColor: _isDark
                      ? DefensysTokens.mistTextPrimary
                      : AppColors.textPrimary,
                  side: BorderSide(
                    color: _isDark
                        ? DefensysTokens.mistBorder
                        : const Color(0xFFCBD5E1),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
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
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: Text(
                  _isConfirming
                      ? 'Saving Schedule...'
                      : 'Publish & Save Schedule',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
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

    if (currentStep == 1) {
      return SchedulerShadcnScope(child: _buildStepOne(widget.state));
    }
    if (currentStep == 2) return _buildStepTwo(widget.state);
    return _buildStepThree(widget.state);
  }
}

// Alias for convenience
typedef ScheduleContainer = ScheduleRunContainer;
