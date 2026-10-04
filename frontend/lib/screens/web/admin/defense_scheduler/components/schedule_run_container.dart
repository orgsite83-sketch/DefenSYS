import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'scheduler_people_picker.dart';
import 'scheduler_session_editor.dart';
import 'scheduler_team_picker.dart';
import '../models/schedule_session_draft.dart';

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
  late final List<ScheduleSessionDraft> _sessions;
  int _nextSession = 2;

  @override
  void initState() {
    super.initState();
    _sessions = [
      ScheduleSessionDraft(
        key: 'session-1',
        date: widget.dateController,
        start: widget.timeController,
        duration: widget.durationController,
        room: widget.roomController,
        ownsFields: false,
      ),
    ];
  }

  @override
  void dispose() {
    for (final session in _sessions) {
      session.dispose();
    }
    super.dispose();
  }

  void _addSession() {
    final previous = _sessions.last;
    final date = DateTime.tryParse(previous.date.text);
    final draft = ScheduleSessionDraft(
      key: 'session-${_nextSession++}',
      date: TextEditingController(
        text: date == null
            ? previous.date.text
            : formatScheduleDate(date.add(const Duration(days: 1))),
      ),
      start: TextEditingController(text: previous.start.text),
      end: previous.end.text,
      duration: TextEditingController(text: previous.duration.text),
      room: TextEditingController(text: previous.room.text),
    );
    for (final block in draft.blocks.skip(1)) {
      block.dispose();
    }
    draft.blocks.removeRange(1, draft.blocks.length);
    draft.blocks.addAll(
      previous.blocks
          .skip(1)
          .map(
            (block) => ScheduleSessionBlock(
              start: TextEditingController(text: block.start.text),
              end: TextEditingController(text: block.end.text),
            ),
          ),
    );
    setState(() => _sessions.add(draft));
  }

  void _addTimeBlock(ScheduleSessionDraft session) {
    final start = scheduleTimeMinutes(session.blocks.last.end.text);
    final duration = int.tryParse(session.duration.text) ?? 60;
    if (start < 0 ||
        duration < 15 ||
        duration > 240 ||
        start + duration > 1439) {
      showValidationToast(
        context,
        'Adjust the last block to leave room for another time block.',
      );
      return;
    }
    setState(
      () => session.blocks.add(
        ScheduleSessionBlock(
          start: TextEditingController(text: scheduleTimeLabel(start)),
          end: TextEditingController(text: scheduleTimeLabel(start + duration)),
        ),
      ),
    );
  }

  int get _unassignedCount =>
      widget.planSlots.where((slot) => slot['session_key'] == null).length;

  void _updatePlan(List<Map<String, dynamic>> slots) {
    for (final session in _sessions) {
      session.teamIds = {
        for (final slot in slots)
          if ((slot['session_key'] ?? slot['requested_session_key']) ==
                  session.key &&
              asInt(slot['team_id']) != null)
            asInt(slot['team_id'])!,
      };
    }
    _recalculatePlanSlots(slots);
    widget.onPlanSlotsChanged(slots);
  }

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

  List<Map<String, dynamic>> _eligibleTeams(DefenseSchedulerState state) {
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

    if (activeStageOrEvent.isEmpty) return [];
    final pitConfig = state.pitEvents.firstWhere(
      (event) =>
          event['event_name']?.toString().toLowerCase() ==
          activeStageOrEvent.toLowerCase(),
      orElse: () => <String, dynamic>{},
    );
    final hasPrerequisites =
        widget.scope == 'capstone' ||
        (pitConfig['deliverables'] as List? ?? []).any(
          (item) => item['deliverable_type'] == 'pre',
        );
    return activeScopeTeams.where((team) {
      final alreadyScheduled = state.schedules.any(
        (schedule) =>
            asInt(schedule['team_id'] ?? schedule['team']?['id']) ==
                asInt(team['id']) &&
            (widget.scope == 'capstone'
                ? asInt(schedule['defense_stage_id']) == widget.stageId &&
                      schedule['status'] == 'scheduled'
                : (schedule['event_name']?.toString() ?? '').toLowerCase() ==
                          activeStageOrEvent.toLowerCase() &&
                      (schedule['status'] == 'scheduled' ||
                          schedule['status'] == 'done')),
      );
      if (alreadyScheduled) return false;
      return hasPrerequisites
          ? isTeamStageReady(team, activeStageOrEvent)
          : !isTeamStageScheduled(team, activeStageOrEvent) &&
                !isTeamStageCompleted(team, activeStageOrEvent);
    }).toList();
  }

  int _getReadyTeamsCount(DefenseSchedulerState state) =>
      _eligibleTeams(state).length;

  Future<void> _chooseSessionTeams(
    ScheduleSessionDraft session,
    int number,
  ) async {
    final chosen = await SchedulerTeamPicker.show(
      context,
      teams: _eligibleTeams(widget.state),
      selected: session.teamIds,
      assignedElsewhere: {
        for (int i = 0; i < _sessions.length; i++)
          if (_sessions[i] != session)
            for (final id in _sessions[i].teamIds) id: 'Session ${i + 1}',
      },
      sessionNumber: number,
    );
    if (chosen != null && mounted) setState(() => session.teamIds = chosen);
  }

  Widget _sessionTeamSelection(ScheduleSessionDraft session, int number) {
    final names = widget.state.teams
        .where((team) => session.teamIds.contains(asInt(team['id'])))
        .map((team) => team['name']?.toString() ?? 'Team')
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Teams for this session *',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            ShadButton.outline(
              key: ValueKey('choose-session-teams-${session.key}'),
              onPressed: _isGenerating || _isConfirming
                  ? null
                  : () => _chooseSessionTeams(session, number),
              child: const Text('Choose teams'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          names.isEmpty
              ? 'Choose teams individually or select an adviser’s advisees.'
              : names.join(', '),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ],
    );
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
    final arranged = arrangeSessionSlots(
      slots,
      _sessions.map((session) => session.toPayload()).toList(),
    );
    slots
      ..clear()
      ..addAll(arranged);
  }

  Map<String, dynamic>? _basePayload() {
    if (!_canScheduleCurrentScope()) {
      showValidationToast(context, widget.scheduleNoticeMessage(widget.state));
      return null;
    }

    final first = _sessions.first;
    final date = first.date.text.trim();
    final time = first.start.text.trim();
    final room = first.room.text.trim();

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

    for (int i = 0; i < _sessions.length; i++) {
      final session = _sessions[i];
      final duration = int.tryParse(session.duration.text) ?? 0;
      int previousEnd = -1;
      final validBlocks = session.blocks.every((block) {
        final start = scheduleTimeMinutes(block.start.text);
        final end = scheduleTimeMinutes(block.end.text);
        final valid =
            start >= 0 && start >= previousEnd && end - start >= duration;
        previousEnd = end;
        return valid;
      });
      if (DateTime.tryParse(session.date.text) == null ||
          session.room.text.trim().isEmpty ||
          !validBlocks ||
          duration < 15 ||
          duration > 240 ||
          session.capacity < 1) {
        showValidationToast(
          context,
          'Session ${i + 1}: choose a date, room, 15–240 minute slots, and ordered time blocks that each fit a complete slot.',
        );
        return null;
      }
      if (session.customStaff && session.panelists.isEmpty) {
        showValidationToast(
          context,
          'Session ${i + 1}: select at least one faculty panelist.',
        );
        return null;
      }
    }

    if (_sessions.every((session) => session.teamIds.isEmpty)) {
      showValidationToast(
        context,
        'Choose at least one team for your sessions.',
      );
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
      'slot_duration': int.tryParse(first.duration.text.trim()) ?? 60,
      'room': room,
      'panelist_ids': widget.selectedPanelistIds.toList(),
      'external_evaluator_ids': _externalIds.toList(),
      if (_guestExpiry != null)
        'guest_access_expires_at': _guestExpiry!.toUtc().toIso8601String(),
      if (effectiveChair != null) 'chair_panelist_id': effectiveChair,
      if (widget.scope == 'capstone' && widget.documenterId != null)
        'documenter_id': widget.documenterId,
      'sessions': _sessions.map((session) => session.toPayload()).toList(),
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
        '${generated.where((slot) => slot['session_key'] != null).length} teams assigned · ${generated.where((slot) => slot['session_key'] == null).length} remaining.',
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _confirmPlan() async {
    if (_unassignedCount > 0) {
      showValidationToast(
        context,
        'Assign all teams to a session or remove them from this plan before confirming.',
      );
      return;
    }
    final payload = _basePayload();
    if (payload == null || widget.planSlots.isEmpty) return;

    payload['slots'] = widget.planSlots
        .map(
          (slot) => {
            'team_id': asInt(slot['team_id']),
            'session_key': slot['session_key'],
            'scheduled_date': slot['scheduled_date'],
            'start_time': slot['start_time'],
            'slot_duration': slot['slot_duration'],
            'room': slot['room'],
          },
        )
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
      onTap: _isGenerating || _isConfirming
          ? null
          : () async {
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
                  final copy = List<Map<String, dynamic>>.from(
                    widget.planSlots,
                  );
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
      onTap: _isGenerating || _isConfirming
          ? null
          : () async {
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
                  final copy = List<Map<String, dynamic>>.from(
                    widget.planSlots,
                  );
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
          'A session groups teams on one day. Use time blocks to set breaks.',
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
                  for (final session in _sessions) {
                    session.teamIds.clear();
                  }
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
                  for (final session in _sessions) {
                    session.teamIds.clear();
                  }
                  widget.onPlanSlotsChanged([]);
                  widget.onShowFinalPreviewChanged(false);
                  widget.eventController.text = value;
                  widget.onPrefillPitEventConfig();
                  setState(() {});
                },
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        for (int i = 0; i < _sessions.length; i++)
          SchedulerSessionEditor(
            key: ValueKey(_sessions[i].key),
            draft: _sessions[i],
            number: i + 1,
            faculty: state.selectablePanelists,
            documenters: state.documenters,
            externals: ref.watch(externalEvaluatorProvider).approved,
            capstone: widget.scope == 'capstone',
            enabled: !busy,
            dateField: (controller) =>
                _scheduleDateField(controller: controller),
            timeField: (controller) =>
                _scheduleTimeField(controller: controller),
            teamSelection: _sessionTeamSelection(_sessions[i], i + 1),
            onAddBlock: () => _addTimeBlock(_sessions[i]),
            onRemoveBlock: (index) {
              final removed = _sessions[i].blocks.removeAt(index);
              setState(() {});
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => removed.dispose(),
              );
            },
            onChanged: () => setState(() {}),
            onRemove: i == 0
                ? null
                : () {
                    final removed = _sessions.removeAt(i);
                    setState(() {});
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => removed.dispose(),
                    );
                  },
            onCustomize: () => setState(() {
              final session = _sessions[i];
              session.customStaff = !session.customStaff;
              if (session.customStaff) {
                session.panelists = Set.of(widget.selectedPanelistIds);
                session.chair = _effectiveChairId;
                session.externals = Set.of(_externalIds);
                session.documenter = widget.scope == 'capstone'
                    ? widget.documenterId
                    : null;
              }
            }),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.outline(
            key: const ValueKey('add-schedule-session'),
            onPressed: busy ? null : _addSession,
            leading: const Icon(Icons.add, size: 16),
            child: const Text('Add session'),
          ),
        ),
      ],
    );

    final people = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _setupHeading(
          'Shared staff defaults',
          'Used by sessions unless you customize their staff.',
        ),
        const SizedBox(height: 20),
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
                    '${_sessions.fold<int>(0, (total, session) => total + session.teamIds.length)} selected / '
                    '${_sessions.fold<int>(0, (total, session) => total + session.capacity)} slots available',
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
        children: [
          for (int i = 0; i < headers.length; i++)
            if (i == 0 || headers[i] == 'Actions')
              SizedBox(
                width: i == 0 ? 32 : 120,
                child: Text(
                  headers[i],
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              Expanded(
                child: Text(
                  headers[i],
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
        ],
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
    Widget? moveAction,
    Widget? dragAction,
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
          if (moveAction != null) moveAction,
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: Color(0xFFF04438),
            ),
            onPressed: onDelete,
            tooltip: 'Remove slot',
          ),
          if (dragAction != null) dragAction,
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

  String _panelNamesFromSelection(
    DefenseSchedulerState state, [
    ScheduleSessionDraft? session,
  ]) {
    final custom = session?.customStaff == true;
    final ids = custom ? session!.panelists : widget.selectedPanelistIds;
    final effectiveChair = custom
        ? (session!.chair ?? ids.firstOrNull)
        : _effectiveChairId;
    final names = state.selectablePanelists
        .where((p) {
          final id = asInt(p['id']);
          return id != null && ids.contains(id);
        })
        .map((p) {
          final id = asInt(p['id']);
          final name =
              p['name']?.toString() ??
              p['full_name']?.toString() ??
              p['username']?.toString() ??
              '';
          if (id == effectiveChair) {
            return '$name (Chair)';
          }
          return name;
        })
        .where((n) => n.isNotEmpty)
        .toList();
    names.addAll(
      ref
          .read(externalEvaluatorProvider)
          .approved
          .where(
            (e) =>
                (custom ? session!.externals : _externalIds).contains(e['id']),
          )
          .map((e) => '${e['name']} (External)'),
    );
    if (names.isEmpty) return 'No panelists assigned';
    return names.join(', ');
  }

  Widget _moveTeamMenu(Map<String, dynamic> slot) => PopupMenuButton<String>(
    key: ValueKey('move-team-${slot['team_id']}'),
    tooltip: 'Move team to session',
    icon: const Icon(Icons.drive_file_move_outline, size: 18),
    onSelected: (key) {
      final copy = widget.planSlots
          .map((s) => Map<String, dynamic>.from(s))
          .toList();
      final moved = copy.firstWhere((s) => s['team_id'] == slot['team_id']);
      moved['session_key'] = key == 'unassigned' ? null : key;
      moved['requested_session_key'] = moved['session_key'];
      _updatePlan(copy);
    },
    itemBuilder: (_) => [
      for (int i = 0; i < _sessions.length; i++)
        PopupMenuItem(
          value: _sessions[i].key,
          enabled:
              slot['session_key'] != _sessions[i].key &&
              widget.planSlots
                      .where((s) => s['session_key'] == _sessions[i].key)
                      .length <
                  _sessions[i].capacity,
          child: Text(
            'Session ${i + 1} · ${_sessions[i].date.text} · ${_sessions[i].start.text}',
          ),
        ),
      PopupMenuItem(
        value: 'unassigned',
        enabled: slot['session_key'] != null,
        child: const Text('Unassigned'),
      ),
    ],
  );

  Widget _sessionPlanGroup(
    DefenseSchedulerState state,
    ScheduleSessionDraft? session, {
    bool preview = false,
  }) {
    final indices = [
      for (int i = 0; i < widget.planSlots.length; i++)
        if (widget.planSlots[i]['session_key'] == session?.key) i,
    ];
    if (session == null && indices.isEmpty) return const SizedBox.shrink();
    final number = session == null ? 0 : _sessions.indexOf(session) + 1;
    final panel = session == null
        ? 'Assign a session to set staff'
        : _panelNamesFromSelection(state, session);
    final docId = session?.customStaff == true
        ? session!.documenter
        : widget.documenterId;
    final documenters = state.documenters.where((p) => asInt(p['id']) == docId);
    final docName = documenters.isEmpty
        ? 'Unassigned'
        : schedulerPersonName(documenters.first);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                session == null ? 'Unassigned teams' : 'Session $number',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                session == null
                    ? '${indices.length} ${indices.length == 1 ? 'team needs' : 'teams need'} a session'
                    : '${indices.length} / ${session.capacity} slots',
                style: TextStyle(color: _textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (session != null) ...[
            Text(
              '${session.date.text} · ${session.timeWindowLabel} · ${session.room.text}',
              style: TextStyle(color: _textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '$panel${widget.scope == 'capstone' ? ' · Documenter: $docName' : ''}',
              style: TextStyle(color: _textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (_, constraints) {
              final wide = constraints.maxWidth >= 800;
              Widget row(int index) {
                final slot = widget.planSlots[indices[index]];
                final team = slot['team_name']?.toString() ?? 'Team';
                final stage = slot['stage_label']?.toString() ?? 'Stage';
                final date = slot['scheduled_date']?.toString() ?? '';
                final time = session == null
                    ? 'Unassigned'
                    : '${slot['start_time']}–${slot['end_time']}';
                void remove() {
                  final copy = List<Map<String, dynamic>>.from(widget.planSlots)
                    ..removeAt(indices[index]);
                  _updatePlan(copy);
                }

                final key = ValueKey('session-team-${slot['team_id']}');
                if (!wide) {
                  return Container(
                    key: key,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: DefensysTokens.borderOf(context),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${index + 1}. $team',
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$stage · $time',
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!preview) ...[
                          _moveTeamMenu(slot),
                          IconButton(
                            onPressed: remove,
                            tooltip: 'Remove slot',
                            icon: const Icon(Icons.delete_outline, size: 18),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                if (preview) {
                  return KeyedSubtree(
                    key: key,
                    child: _finalPreviewRow(
                      index: index,
                      team: team,
                      stage: stage,
                      date: date,
                      time: time,
                      room: slot['room']?.toString() ?? '',
                      panel: panel,
                    ),
                  );
                }
                return _planTableRow(
                  key: key,
                  index: index,
                  team: team,
                  stage: stage,
                  date: date,
                  time: time,
                  room: slot['room']?.toString() ?? '',
                  panel: panel,
                  onDelete: remove,
                  moveAction: _moveTeamMenu(slot),
                  dragAction: ReorderableDragStartListener(
                    index: index,
                    child: Tooltip(
                      message: 'Drag to reorder team',
                      child: SizedBox(
                        width: 24,
                        child: Icon(
                          Icons.drag_handle,
                          size: 18,
                          color: _textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    _planTableHeader([
                      '#',
                      'Team Name',
                      'Stage / Event',
                      'Date & Time',
                      'Room',
                      'Assigned Panel',
                      if (!preview) 'Actions',
                    ]),
                  if (indices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No teams assigned.',
                        style: TextStyle(color: _textSecondary),
                      ),
                    )
                  else if (preview) ...[
                    for (int i = 0; i < indices.length; i++) row(i),
                  ] else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: indices.length,
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) {
                          newIndex--;
                        }
                        final copy = widget.planSlots
                            .map((s) => Map<String, dynamic>.from(s))
                            .toList();
                        final ordered = [
                          for (final index in indices) copy[index],
                        ];
                        ordered.insert(newIndex, ordered.removeAt(oldIndex));
                        for (int i = 0; i < indices.length; i++) {
                          copy[indices[i]] = ordered[i];
                        }
                        _updatePlan(copy);
                      },
                      itemBuilder: (_, index) => wide
                          ? row(index)
                          : ReorderableDelayedDragStartListener(
                              key: ValueKey(
                                'drag-team-${widget.planSlots[indices[index]]['team_id']}',
                              ),
                              index: index,
                              child: row(index),
                            ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _planStepHeading(
    int step,
    String title,
    String badge,
    Color background,
    Color foreground,
  ) => LayoutBuilder(
    builder: (_, constraints) {
      final heading = Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.maroon,
            child: Text(
              '$step',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
          ),
        ],
      );
      final status = _softBadge(badge, background, foreground);
      return constraints.maxWidth < 650
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, const SizedBox(height: 10), status],
            )
          : Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: 16),
                status,
              ],
            );
    },
  );

  Widget _buildStepTwo(DefenseSchedulerState state) {
    return _schedulerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _planStepHeading(
            2,
            'Step 2: Review & Arrange Teams',
            '${widget.planSlots.length - _unassignedCount} assigned · $_unassignedCount remaining',
            const Color(0xFFEFF8FF),
            const Color(0xFF175CD3),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: _isDark ? DefensysTokens.mistBorder : null),
          const SizedBox(height: 16),
          Text(
            'Reorder teams within a session or move them to another session with space. Add sessions in Step 1 if more time is needed.',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          for (final session in _sessions) _sessionPlanGroup(state, session),
          _sessionPlanGroup(state, null),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 14,
            runSpacing: 12,
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
              ElevatedButton.icon(
                onPressed: _unassignedCount > 0
                    ? null
                    : () => widget.onShowFinalPreviewChanged(true),
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
          _planStepHeading(
            3,
            'Step 3: Final Schedule Preview',
            'Ready to Save',
            const Color(0xFFECFDF3),
            const Color(0xFF027A48),
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
          for (final session in _sessions)
            _sessionPlanGroup(state, session, preview: true),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 14,
            runSpacing: 12,
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
