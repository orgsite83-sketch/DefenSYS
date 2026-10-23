import 'widgets/stage_minutes_settings.dart';
import 'widgets/stage_outcome_settings.dart';
import 'package:defensys/widgets/repository/document_policy_editor.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/academic_period_provider.dart';
import '../../../../services/defense_stages_provider.dart';
import '../../../../services/rubric_engine_provider.dart';
import '../../../../services/unsaved_changes_provider.dart';
import '../../../../services/auth_provider.dart';
import '../../../../services/app/data_refresh_provider.dart';
import '../../../../utils/stage_setup_draft.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../utils/unsaved_changes.dart';
import '../../../../widgets/widgets.dart';
import '../../../../widgets/repository/repository_archive_naming_panel.dart';
import '../../../../widgets/repository/deliverable_timing_fields.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import 'widgets/pipeline_position_selector.dart';
import 'widgets/endorsed_stage_resolution_dialog.dart';
import 'widgets/stage_setup_draft_notice.dart';
import 'widgets/stage_setup_confirmation.dart';
import 'widgets/stage_setup_actions.dart';
import 'widgets/stage_deliverable_overview.dart';
import 'widgets/stage_deliverable_choices.dart';
import 'widgets/stage_deliverable_presets_bar.dart';
import '../widgets/defensys_admin_shell.dart';

class DefenseStageEditorScreen extends ConsumerStatefulWidget {
  final int stageId;
  final int initialTab;
  final Map<String, dynamic>? initialStage;
  final VoidCallback onBack;

  const DefenseStageEditorScreen({
    super.key,
    required this.stageId,
    this.initialTab = 0,
    this.initialStage,
    required this.onBack,
  });

  @override
  ConsumerState<DefenseStageEditorScreen> createState() =>
      _DefenseStageEditorScreenState();
}

class _DefenseStageEditorScreenState
    extends ConsumerState<DefenseStageEditorScreen> {
  final _label = TextEditingController();
  final _code = TextEditingController();
  final _description = TextEditingController();
  final _minutesNumber = TextEditingController(text: 'MINUTES');
  final _minutesName = TextEditingController();
  bool _minutesRequired = false;
  Map<String, dynamic> _conceptConfig = {};
  final _qualifyingScore = TextEditingController();
  String _scoreCarryover = 'reassess';
  final _panel = TextEditingController(text: '50');
  final _adviser = TextEditingController(text: '30');
  final _peer = TextEditingController(text: '20');

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _surfaceColor => _isDark ? DefensysTokens.mistSurface : Colors.white;
  Color get _panelBgColor => _isDark ? DefensysTokens.mistPanel : const Color(0xFFF8FAFC);
  Color get _inputFillColor => _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC);
  Color get _borderColor => _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0);
  Color get _textPrimaryColor => _isDark ? DefensysTokens.textPrimaryDark : AppColors.textPrimary;
  Color get _textSecondaryColor => _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary;

  int _orderPosition = 1;
  late int _activeTab;
  bool _isActive = true;
  bool _isPresentationOnly = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int? _semesterId;
  List<Map<String, dynamic>> _deliverables = [];
  Map<String, dynamic>? _selectedDeliverable;
  bool _minutesExpanded = false;
  Map<String, dynamic>? _stage;
  bool _isDirty = false;
  bool _savingDraft = false;
  StageSetupDraftStore? _draftStore;
  StageSetupDraft? _savedDraft;
  UnsavedChangesNotifier? _unsavedNotifier;
  UnsavedChangesSaveDraftNotifier? _unsavedDraftNotifier;

  int? _panelRubricId;
  String? _panelRubricName;
  int? _adviserRubricId;
  String? _adviserRubricName;
  int? _peerRubricId;
  String? _peerRubricName;
  final Set<String> _editedRubricRoles = {};
  final Map<String, int?> _serverRubricIds = {};
  bool _editorVisible = false;
  bool _refreshingRubrics = false;

  void _markDirty() {
    if (_loading || _isDirty) return;
    setState(() => _isDirty = true);
    if (TickerMode.of(context)) {
      _unsavedNotifier?.setDirty(true);
      _unsavedDraftNotifier?.setCallback(_saveDraft);
    }
  }

  StageSetupDraft _snapshotDraft() => StageSetupDraft(
    tab: _activeTab,
    fields: {
      'label': _label.text,
      'code': _code.text,
      'description': _description.text,
      'display_order': _orderPosition,
      'is_active': _isActive,
      'is_presentation_only': _isPresentationOnly,
      'minutes_required': _minutesRequired,
      'concept_config': {..._conceptConfig, if (_conceptConfig['enabled'] == true) 'review_policy': 'always'},
      'qualifying_score': double.tryParse(_qualifyingScore.text.trim()),
      'score_carryover': _scoreCarryover,
      'minutes_deliverable_id': _minutesNumber.text,
      'minutes_deliverable_label': _minutesName.text,
      'deliverables': _deliverables,
      'rubric_assignment_changes': _editedRubricRoles.toList(),
      'rubric_assignment_base': _serverRubricIds,
      'grading_config': {
        'panel_weight': _panel.text,
        'adviser_weight': _adviser.text,
        'peer_weight': _peer.text,
        'panel_rubric_id': _panelRubricId,
        'panel_rubric_name': _panelRubricName,
        'adviser_rubric_id': _adviserRubricId,
        'adviser_rubric_name': _adviserRubricName,
        'peer_rubric_id': _peerRubricId,
        'peer_rubric_name': _peerRubricName,
      },
    },
  );

  Future<bool> _saveDraft() async {
    if (_saving || _savingDraft || _isLocked || _loading) return false;
    setState(() => _savingDraft = true);
    try {
      if (_draftStore == null) throw StateError('Account is unavailable.');
      final snapshot = _snapshotDraft();
      await _draftStore!.save(snapshot);
      if (!mounted) return true;
      setState(() => _savedDraft = snapshot);
      _clearDirty();
      return true;
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save your draft. Your setup is still open; please try again.');
      return false;
    } finally {
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  Future<void> _openRubrics() async {
    if (_isLocked || await _saveDraft()) {
      if (mounted) context.go(AdminRoutes.rubrics);
    }
  }

  Future<void> _discardDraft() async {
    if (_saving || _savingDraft || _savedDraft == null) return;
    final discard = await showStageSetupConfirmation(
      context,
      title: 'Discard stage setup draft?',
      description: 'The draft will be removed and this editor will reload the saved stage configuration.',
      confirmLabel: 'Discard draft',
      destructive: true,
    );
    if (!discard || !mounted) return;
    try {
      await _clearBrowserDraft();
      if (!mounted) return;
      setState(() => _savedDraft = null);
      _clearDirty();
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not discard the draft. Please try again.');
    }
  }

  Future<void> _clearBrowserDraft() async {
    final store = _draftStore;
    if (store == null) return;
    await store.clear();
    final creationStore = store.forStage(null);
    final creationDraft = await creationStore.load();
    if (_asInt(creationDraft?.fields['created_stage_id']) == widget.stageId) {
      await creationStore.clear();
    }
  }

  void _clearDirty() {
    if (mounted) {
      setState(() => _isDirty = false);
    }
    if (mounted && TickerMode.of(context)) {
      _unsavedNotifier?.setDirty(false);
      _unsavedDraftNotifier?.setCallback(null);
    }
  }

  Future<void> _handleBack() async {
    await guardUnsavedExit(
      context,
      isDirty: _isDirty,
      onSaveDraft: _saveDraft,
      onExit: () {
        _clearDirty();
        widget.onBack();
      },
    );
  }

  void _attachFieldListeners() {
    for (final controller in [
      _label,
      _code,
      _description,
      _minutesNumber,
      _minutesName,
      _panel,
      _adviser,
      _peer,
    ]) {
      controller.removeListener(_markDirty);
      controller.addListener(_markDirty);
    }
  }

  void _detachFieldListeners() {
    for (final controller in [
      _label,
      _code,
      _description,
      _minutesNumber,
      _minutesName,
      _panel,
      _adviser,
      _peer,
    ]) {
      controller.removeListener(_markDirty);
    }
  }

  @override
  void initState() {
    super.initState();
    _unsavedNotifier = ref.read(unsavedChangesProvider.notifier);
    _unsavedDraftNotifier = ref.read(unsavedChangesSaveDraftProvider.notifier);
    _activeTab = widget.initialTab.clamp(0, 2);
    if (widget.initialStage != null) {
      _applyStage(widget.initialStage!);
    }
    _attachFieldListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.of(context);
    if (visible && !_editorVisible && !_loading) {
      _scheduleRubricRefresh();
    }
    _editorVisible = visible;
  }

  void _scheduleRubricRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editorVisible) _refreshRubricAssignments();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _refreshRubricAssignments() async {
    if (_loading || _saving || _refreshingRubrics) return;
    _refreshingRubrics = true;
    try {
      final detail = await ref.read(defenseStagesProvider.notifier)
          .fetchStageDetail(widget.stageId, semesterId: _semesterId);
      if (!mounted || detail?['grading_config'] is! Map) return;
      setState(() => _syncServerRubricAssignments(
        Map<String, dynamic>.from(detail!['grading_config'] as Map),
      ));
    } finally {
      _refreshingRubrics = false;
    }
  }

  @override
  void dispose() {
    _detachFieldListeners();
    _label.dispose();
    _code.dispose();
    _description.dispose();
    _minutesNumber.dispose();
    _minutesName.dispose();
    _qualifyingScore.dispose();
    _panel.dispose();
    _adviser.dispose();
    _peer.dispose();
    for (final item in _deliverables) {
      (item['_labelController'] as TextEditingController?)?.dispose();
      (item['_templateController'] as TextEditingController?)?.dispose();
    }
    releaseUnsavedChangesAfterFrame(_unsavedNotifier, _unsavedDraftNotifier);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _editedRubricRoles.clear();
    _serverRubricIds.clear();

    await ref.read(academicPeriodProvider.notifier).fetchPeriods();
    final active = ref.read(academicPeriodProvider).activeSemester;
    _semesterId ??= _asInt(active?['id']);

    await ref.read(defenseStagesProvider.notifier).fetchStages();

    final detail = await ref
        .read(defenseStagesProvider.notifier)
        .fetchStageDetail(widget.stageId, semesterId: _semesterId);

    if (detail != null) {
      final semester = detail['active_semester'];
      if (semester is Map) {
        _semesterId = _asInt(semester['id']);
      }
    }

    // Load Capstone rubrics (published ones are filtered client-side for dropdowns)
    await ref.read(rubricEngineProvider.notifier).fetchRubrics(
          scope: 'capstone',
          status: '',
        );

    if (!mounted) return;

    if (detail != null) {
      final stage = detail['stage'];
      if (stage is Map) {
        _applyStage(Map<String, dynamic>.from(stage));
      }
      final grading = detail['grading_config'];
      if (grading is Map) {
        _applyWeights(Map<String, dynamic>.from(grading));
        _syncServerRubricAssignments(Map<String, dynamic>.from(grading));
      }
    }

    final user = ref.read(authProvider).user;
    final userId = user?['id']?.toString() ?? user?['username']?.toString();
    _draftStore = userId == null ? null : StageSetupDraftStore(
      userId: userId,
      semesterId: _semesterId,
      stageId: widget.stageId,
    );
    try {
      _savedDraft = _isLocked ? null : await _draftStore?.load();
    } catch (_) {
      _savedDraft = null;
    }
    if (!mounted) return;
    if (_savedDraft != null) _restoreDraft(_savedDraft!);

    setState(() {
      _loading = false;
      _isDirty = false;
    });
    if (TickerMode.of(context)) {
      _unsavedNotifier?.setDirty(false);
      _unsavedDraftNotifier?.setCallback(null);
    }
  }

  void _restoreDraft(StageSetupDraft draft) {
    final serverStage = _stage;
    _applyStage({...?_stage, ...draft.fields});
    // Locks and workflow metadata always come from the server.
    _stage = serverStage;
    final grading = draft.fields['grading_config'];
    if (grading is Map) {
      // A saved setup snapshot is not an instruction to undo assignments made
      // in Rubrics since the draft was written. Restore only explicit edits.
      final base = draft.fields['rubric_assignment_base'] as Map? ?? {};
      final changes = draft.fields['rubric_assignment_changes'] as List? ?? [];
      _editedRubricRoles.addAll(changes.whereType<String>().where((role) =>
        base.containsKey(role) && _asInt(base[role]) == _serverRubricIds[role]));
      _applyWeights(Map<String, dynamic>.from(grading));
      _applyRubricAssignments(Map<String, dynamic>.from(grading), roles: _editedRubricRoles);
    }
    _activeTab = draft.tab;
  }

  void _applyStage(Map<String, dynamic> stage) {
    _stage = stage;
    _label.text = stage['label']?.toString() ?? '';
    _code.text = stage['code']?.toString() ?? '';
    _description.text = stage['description']?.toString() ?? '';
    _orderPosition = _asInt(stage['display_order']) ?? 1;
    _isActive = stage['is_active'] != false;
    _isPresentationOnly = stage['is_presentation_only'] == true;
    _conceptConfig = Map<String, dynamic>.from(stage['concept_config'] as Map? ?? {});
    _qualifyingScore.text = stage['qualifying_score']?.toString() ?? '';
    _scoreCarryover = stage['score_carryover']?.toString() ?? _conceptConfig['score_carryover']?.toString() ?? 'reassess';
    _minutesRequired = stage['minutes_required'] == true;
    _minutesNumber.text = stage['minutes_deliverable_id']?.toString() ?? 'MINUTES';
    _minutesName.text = stage['minutes_deliverable_label']?.toString() ?? '';
    final delivs = stage['deliverables'];
    if (delivs is List) {
      _deliverables = delivs
          .whereType<Map>()
          .map((d) => Map<String, dynamic>.from(d))
          .toList();
    }
  }

  void _applyWeights(Map<String, dynamic> grading) {
    _panel.text = grading['panel_weight']?.toString() ?? '50';
    _adviser.text = grading['adviser_weight']?.toString() ?? '30';
    _peer.text = grading['peer_weight']?.toString() ?? '20';
  }

  void _syncServerRubricAssignments(Map<String, dynamic> grading) {
    for (final role in ['panel', 'adviser', 'peer']) {
      final id = _asInt(grading['${role}_rubric_id']);
      // A newer assignment in Rubrics supersedes an older setup draft.
      if (_serverRubricIds[role] != id) _editedRubricRoles.remove(role);
      _serverRubricIds[role] = id;
    }
    _applyRubricAssignments(grading,
      roles: {'panel', 'adviser', 'peer'}.difference(_editedRubricRoles));
  }

  void _applyRubricAssignments(Map<String, dynamic> grading, {required Set<String> roles}) {
    if (roles.contains('panel')) {
      _panelRubricId = _asInt(grading['panel_rubric_id']);
      _panelRubricName = grading['panel_rubric_name']?.toString();
    }
    if (roles.contains('adviser')) {
      _adviserRubricId = _asInt(grading['adviser_rubric_id']);
      _adviserRubricName = grading['adviser_rubric_name']?.toString();
    }
    if (roles.contains('peer')) {
      _peerRubricId = _asInt(grading['peer_rubric_id']);
      _peerRubricName = grading['peer_rubric_name']?.toString();
    }
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  int get _weightTotal {
    final p = int.tryParse(_panel.text.trim()) ?? 0;
    final a = int.tryParse(_adviser.text.trim()) ?? 0;
    final r = int.tryParse(_peer.text.trim()) ?? 0;
    return p + a + r;
  }

  List<Map<String, dynamic>> _semesterOptions() {
    final options = <Map<String, dynamic>>[];
    for (final year in ref.read(academicPeriodProvider).schoolYears) {
      final semesters = year['semesters'];
      if (semesters is! List) continue;
      for (final sem in semesters) {
        if (sem is Map) {
          options.add(Map<String, dynamic>.from(sem));
        }
      }
    }
    return options;
  }

  Future<void> _saveOutcomePolicy() async {
    if (StageOutcomeSettings.validateScore(_qualifyingScore.text) != null) {
      setState(() => _error = 'Set a qualifying panel score from 0 to 100%.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    final ok = await ref.read(defenseStagesProvider.notifier).updateStage(widget.stageId, {
      'qualifying_score': double.parse(_qualifyingScore.text.trim()), 'score_carryover': _scoreCarryover,
    });
    if (!mounted) return;
    setState(() { _saving = false; if (!ok) _error = ref.read(defenseStagesProvider).error; });
    if (ok) { _clearDirty(); await _load(); }
  }

  Future<void> _save() async {
    if (_isLocked) return;
    if (StageOutcomeSettings.validateScore(_qualifyingScore.text) != null) {
      setState(() { _activeTab = 1; _error = 'Set a qualifying panel score from 0 to 100%.'; });
      return;
    }
    if (_label.text.trim().isEmpty) {
      setState(() => _error = 'Stage name is required.');
      return;
    }
    if (_semesterId == null) {
      setState(() => _error = 'Select a semester for grade weights.');
      return;
    }
    if (_weightTotal != 100) {
      setState(() => _error = 'Panel, Adviser, and Peer weights must total 100%.');
      return;
    }

    // Validate deliverables labels & archive naming templates (only in Document-Gated mode)
    if (!_isPresentationOnly) {
      for (int i = 0; i < _deliverables.length; i++) {
        final d = _deliverables[i];
        final labelVal = d['label']?.toString().trim() ?? '';
        if (labelVal.isEmpty) {
          setState(() {
            _activeTab = 2;
            _selectedDeliverable = d;
            _error = 'Enter a name for this deliverable.';
          });
          return;
        }
        if (d['deliverable_type'] == 'post') {
          final tpl = (d['archive_file_template'] ?? '').toString().trim();
          final count = RegExp(r'\{[a-zA-Z0-9_]+\}').allMatches(tpl).length;
          if (count > 3) {
            setState(() {
              _activeTab = 2;
              _selectedDeliverable = d;
              _error = 'Use at most 3 variables in the archive file name for "$labelVal".';
            });
            return;
          }
        }
      }
    }

    final initialOrder = _asInt(_stage?['display_order']);
    final endorsedCount = _asInt(_stage?['endorsed_teams_count']) ?? 0;
    String? endorsedAction;

    if (initialOrder != null && initialOrder != _orderPosition && endorsedCount > 0) {
      endorsedAction = await showEndorsedStageResolutionDialog(
        context: context,
        stageLabel: _label.text.trim().isEmpty ? (_stage?['label']?.toString() ?? 'Stage') : _label.text.trim(),
        endorsedCount: endorsedCount,
        targetPosition: _orderPosition,
      );
      if (!mounted || endorsedAction == null) {
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final stageOk = await ref.read(defenseStagesProvider.notifier).updateStage(
          widget.stageId,
          {
            'label': _label.text.trim(),
            'code': _code.text.trim(),
            'display_order': _orderPosition,
            'description': _description.text.trim(),
            'is_active': _isActive,
            'is_presentation_only': _isPresentationOnly,
            'minutes_required': _minutesRequired,
      'concept_config': {..._conceptConfig, if (_conceptConfig['enabled'] == true) 'review_policy': 'always'},
      'qualifying_score': double.tryParse(_qualifyingScore.text.trim()),
      'score_carryover': _scoreCarryover,
            'minutes_deliverable_id': _minutesNumber.text.trim(),
            'minutes_deliverable_label': _minutesName.text.trim(),
            'deliverables': _isPresentationOnly ? [] : _deliverables,
            if (endorsedAction != null) 'endorsed_teams_action': endorsedAction,
          },
        );

    final weightsOk = stageOk && await ref
        .read(defenseStagesProvider.notifier)
        .updateGradingConfig(widget.stageId, _semesterId!, {
          'panel_weight': int.tryParse(_panel.text.trim()) ?? 0,
          'adviser_weight': int.tryParse(_adviser.text.trim()) ?? 0,
          'peer_weight': int.tryParse(_peer.text.trim()) ?? 0,
          if (_editedRubricRoles.contains('panel')) 'panel_rubric_id': _panelRubricId,
          if (_editedRubricRoles.contains('adviser')) 'adviser_rubric_id': _adviserRubricId,
          if (_editedRubricRoles.contains('peer')) 'peer_rubric_id': _peerRubricId,
        });

    if (!mounted) return;

    setState(() => _saving = false);

    if (stageOk && weightsOk) {
      try {
        await _clearBrowserDraft();
        _savedDraft = null;
      } catch (_) {
        setState(() => _error = 'Stage saved, but its browser draft could not be removed.');
        return;
      }
      _clearDirty();
      await ref.read(defenseStagesProvider.notifier).fetchStages();
      if (mounted) widget.onBack();
      return;
    }

    setState(() {
      _error = ref.read(defenseStagesProvider).error ??
          'Failed to save stage or grade weights.';
    });
  }

  List<Map<String, dynamic>> _getRubricOptions(String evaluationType) {
    final rubrics = ref.watch(rubricEngineProvider).rubrics;
    return rubrics.where((r) {
      final scopeMatch = r['scope'] == 'capstone';
      final semMatch = _asInt(r['semester_id']) == _semesterId;
      final evalMatch = r['evaluation_type'] == evaluationType;
      final publishedMatch = r['status'] == 'published';
      final assignedStageId = _asInt(r['defense_stage_id']);
      final stageMatch = assignedStageId == null || assignedStageId == widget.stageId;
      final available = r['is_locked'] != true || assignedStageId == widget.stageId;
      return scopeMatch && semMatch && evalMatch && publishedMatch && stageMatch && available;
    }).toList();
  }

  List<DropdownMenuItem<int>> _buildRubricDropdownItems(
    String evaluationType,
    int? currentId,
    String? currentName,
  ) {
    final options = _getRubricOptions(evaluationType);
    final items = options.map((r) {
      final id = _asInt(r['id']);
      return DropdownMenuItem<int>(
        value: id,
        child: Text(
          r['name']?.toString() ?? '',
          style: TextStyle(
            color: _textPrimaryColor,
          ),
        ),
      );
    }).toList();

    // If currentId is set but not in options, add fallback item
    if (currentId != null && !items.any((item) => item.value == currentId)) {
      items.add(DropdownMenuItem<int>(
        value: currentId,
        enabled: false,
        child: Text(
          currentName ?? 'Rubric #$currentId',
          style: TextStyle(
            color: _textPrimaryColor,
          ),
        ),
      ));
    }

    // Always allow unselecting
    items.insert(
      0,
      DropdownMenuItem<int>(
        value: null,
        child: Text(
          'None (No Rubric)',
          style: TextStyle(
            color: _textSecondaryColor,
          ),
        ),
      ),
    );

    return items;
  }

  Widget _buildPositionSelector() {
    final allStages = ref.watch(defenseStagesProvider).stages;
    final totalStages = allStages.length;
    final currentPos = _orderPosition.clamp(1, totalStages > 0 ? totalStages : 1);
    final initialOrder = _asInt(_stage?['display_order']);

    // Calculate highest order of completed stages
    int lastCompletedOrder = 0;
    for (int i = 0; i < allStages.length; i++) {
      final s = allStages[i];
      final isStageLocked = s['is_locked'] == true || s['status'] == 'locked';
      if (isStageLocked) {
        final order = _asInt(s['display_order']) ?? (i + 1);
        if (order > lastCompletedOrder) {
          lastCompletedOrder = order;
        }
      }
    }

    final minPosition = _isLocked
        ? (initialOrder ?? 1)
        : (lastCompletedOrder + 1);

    return PipelinePositionSelector(
      selectedPosition: currentPos,
      totalSlots: totalStages > 0 ? totalStages : 1,
      existingStages: allStages,
      currentStageName: _label.text,
      editing: true,
      initialOrder: initialOrder,
      isLocked: _isLocked,
      minPosition: minPosition,
      lockReason: _lockReason,
      onPositionChanged: (val) {
        if (val != _orderPosition) {
          setState(() => _orderPosition = val);
          _markDirty();
        }
      },
    );
  }

  void _resetWeights() {
    setState(() {
      _panel.text = '50';
      _adviser.text = '30';
      _peer.text = '20';
    });
  }

  bool get _isLocked =>
      _stage?['is_locked'] == true || _stage?['status'] == 'locked';
  String? get _lockReason => _stage?['lock_reason']?.toString();

  Widget _buildLockedBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _isDark
            ? const Color(0xFF1E3A8A).withValues(alpha: 0.25)
            : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isDark
              ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
              : const Color(0xFFBFDBFE),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.task_alt_rounded,
            color: _isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stage Configuration Locked',
                  style: TextStyle(
                    color: _isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _lockReason ??
                      'Configuration is protected because this stage has scheduled defenses, recorded grades, or has been officially finalized for this semester.',
                  style: TextStyle(
                    color: _isDark ? const Color(0xFFBFDBFE) : const Color(0xFF1D4ED8),
                    fontSize: 12.5,
                    height: 1.35,
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

  @override
  Widget build(BuildContext context) {
    ref.listen(dataRefreshProvider, (previous, next) {
      if (previous?[DataArea.defenseStages] != next[DataArea.defenseStages] &&
          _editorVisible) {
        _scheduleRubricRefresh();
      }
    });
    final semesters = _semesterOptions();
    final activePeriod = ref.read(academicPeriodProvider).activeSemester;
    final activeSemObj = semesters.firstWhere(
      (s) => _asInt(s['id']) == _semesterId,
      orElse: () => activePeriod ?? (semesters.isNotEmpty ? semesters.first : {}),
    );
    final activeSemesterName = activeSemObj['display_name']?.toString() ??
        activeSemObj['label']?.toString() ??
        (_semesterId != null ? 'Semester $_semesterId' : 'No Active Semester');
    final stageTitle = _stage?['label']?.toString() ?? 'Edit Defense Stage';

    if (_loading) {
      return ColoredBox(
        color: _isDark ? DefensysTokens.mistBackground : const Color(0xFFF3F4F6),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.maroon),
        ),
      );
    }

    final panelVal = int.tryParse(_panel.text.trim()) ?? 0;
    final adviserVal = int.tryParse(_adviser.text.trim()) ?? 0;
    final peerVal = int.tryParse(_peer.text.trim()) ?? 0;
    final hasWeightError = (panelVal + adviserVal + peerVal) != 100;
    final preDeliverables = _deliverables.where((d) => d['deliverable_type'] == 'pre').toList();
    final postDeliverables = _deliverables.where((d) => d['deliverable_type'] == 'post').toList();

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: ColoredBox(
        color: _isDark ? DefensysTokens.mistBackground : const Color(0xFFF3F4F6),
        child: SingleChildScrollView(
          key: ValueKey('stage-editor-step-$_activeTab'),
          padding: DefensysUi.contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DefensysPageHeader(
                icon: Icons.layers_rounded,
                title: stageTitle,
                subtitle: 'Configure lifecycle sequence, role grading weights, and submission requirements.',
                actions: OutlinedButton.icon(
                  onPressed: _saving ? null : _handleBack,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    size: 16,
                    color: _isDark ? const Color(0xFFF87171) : DefensysUi.primaryMaroon,
                  ),
                  label: Text(
                    'Back to Defense Stages Setup',
                    style: TextStyle(
                      fontFamily: DefensysUi.fontFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _isDark ? const Color(0xFFF87171) : DefensysUi.primaryMaroon,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _isDark ? const Color(0xFFF87171) : DefensysUi.primaryMaroon,
                    side: BorderSide(
                      color: _isDark ? const Color(0xFFF87171).withValues(alpha: 0.6) : DefensysUi.primaryMaroon,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_isLocked) _buildLockedBanner(),
              if (_savedDraft != null && !_isLocked) ...[
                StageSetupDraftNotice(
                  title: 'Stage setup draft saved',
                  onDiscard: _discardDraft,
                ),
                const SizedBox(height: 14),
              ],
              if (_error != null) ...[
                _notice(_error!, warning: true),
                const SizedBox(height: 14),
              ],

              // Main Tabbed Editor Card
              Container(
                decoration: BoxDecoration(
                  color: _surfaceColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _borderColor),
                  boxShadow: _isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Segmented Tab Bar Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      child: _buildTabBar(
                        activeTab: _activeTab,
                        hasWeightError: hasWeightError,
                        deliverableCount: (_isPresentationOnly ? 0 : _deliverables.length) + (_minutesRequired == true ? 1 : 0),
                        isPresentationOnly: _isPresentationOnly,
                        onTabSelected: (tab) => setState(() => _activeTab = tab),
                      ),
                    ),
                    Divider(height: 1, color: _borderColor),

                    // Tab Content
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: IndexedStack(
                        index: _activeTab,
                        children: [
                          // TAB 0: Stage Details
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: _label,
                                      readOnly: _isLocked,
                                      style: TextStyle(color: _textPrimaryColor),
                                      decoration: _inputDecoration(
                                        labelText: 'Stage Name',
                                        hintText: 'e.g. Concept Proposal, Colloquium, Final Defense',
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: _code,
                                      readOnly: _isLocked,
                                      style: TextStyle(color: _textPrimaryColor),
                                      decoration: _inputDecoration(
                                        labelText: 'Stage Code',
                                        hintText: 'e.g. CAPS101',
                                        helperText: 'Unique system identifier',
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _panelBgColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _borderColor),
                                ),
                                child: _buildPositionSelector(),
                              ),
                              const SizedBox(height: 16),
                              Text('Stage policies', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 4),
                              Text('Enable only the workflows this stage uses.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _textSecondaryColor)),
                              const SizedBox(height: 12),
                              ConceptSettings(value: _conceptConfig, enabled: !_isLocked, onChanged: (value) {
                                setState(() => _conceptConfig = value); _markDirty();
                              }),
                              const SizedBox(height: 20),
                              StageMinutesSettings(
                                requiredMinutes: _minutesRequired, enabled: !_isLocked,
                                onChanged: (value) { setState(() { _minutesRequired = value; _error = null; }); _markDirty(); },
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                controller: _description,
                                readOnly: _isLocked,
                                minLines: 2,
                                maxLines: 4,
                                style: TextStyle(color: _textPrimaryColor),
                                decoration: _inputDecoration(
                                  labelText: 'Stage Description (Optional)',
                                  hintText: 'Provide brief guidance or objectives for this defense milestone...',
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _panelBgColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _borderColor),
                                ),
                                child: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    'Published Stage',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: _textPrimaryColor,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'When active, this stage is part of the live capstone defense sequence.',
                                    style: TextStyle(fontSize: 12, color: _textSecondaryColor),
                                  ),
                                  activeTrackColor: AppColors.maroon,
                                  value: _isActive,
                                  onChanged: _isLocked
                                      ? null
                                      : (v) {
                                          setState(() => _isActive = v);
                                          _markDirty();
                                        },
                                ),
                              ),
                            ],
                          ),

                          // TAB 1: Grading Composition & Evaluation Rubrics
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1. Role Score Distribution Card
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: _panelBgColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _borderColor),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.pie_chart_outline_rounded,
                                          size: 18,
                                          color: _isDark ? const Color(0xFFF87171) : AppColors.maroon,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Role Weight Distribution',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: _textPrimaryColor,
                                          ),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _inputFillColor,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: _borderColor),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.calendar_today_rounded,
                                                size: 12,
                                                color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569),
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                activeSemesterName,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'How Panel, Adviser, and Peer scores combine for this defense milestone. Defaults are 50 / 30 / 20.',
                                      style: TextStyle(fontSize: 13, color: _textSecondaryColor),
                                    ),
                                    const SizedBox(height: 16),
                                    _buildWeightDistributionBar(panelVal, adviserVal, peerVal),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _panel,
                                            readOnly: _isLocked,
                                            keyboardType: TextInputType.number,
                                            style: TextStyle(color: _textPrimaryColor),
                                            decoration: _inputDecoration(
                                              labelText: 'Panel %',
                                              hintText: '50',
                                              prefixIcon: Icon(
                                                Icons.gavel_rounded,
                                                size: 16,
                                                color: _isDark ? const Color(0xFFF87171) : AppColors.maroon,
                                              ),
                                            ),
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: TextField(
                                            controller: _adviser,
                                            readOnly: _isLocked,
                                            keyboardType: TextInputType.number,
                                            style: TextStyle(color: _textPrimaryColor),
                                            decoration: _inputDecoration(
                                              labelText: 'Adviser %',
                                              hintText: '30',
                                              prefixIcon: const Icon(Icons.school_rounded, size: 16, color: Color(0xFFD97706)),
                                            ),
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: TextField(
                                            controller: _peer,
                                            readOnly: _isLocked,
                                            keyboardType: TextInputType.number,
                                            style: TextStyle(color: _textPrimaryColor),
                                            decoration: _inputDecoration(
                                              labelText: 'Peer %',
                                              hintText: '20',
                                              prefixIcon: const Icon(Icons.people_outline_rounded, size: 16, color: Color(0xFF0D9488)),
                                            ),
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: _isLocked ? null : _resetWeights,
                                        icon: const Icon(Icons.restore_rounded, size: 15),
                                        label: const Text('Reset to standard 50 / 30 / 20'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF475569),
                                          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 2. Evaluation Rubrics Attachment Card
                              Builder(
                                builder: (context) {
                                  final panelOpts = _getRubricOptions('panel');
                                  final adviserOpts = _getRubricOptions('adviser');
                                  final peerOpts = _getRubricOptions('peer');
                                  final hasNoRubricsAtAll = panelOpts.isEmpty &&
                                      adviserOpts.isEmpty &&
                                      peerOpts.isEmpty;

                                  return Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: _panelBgColor,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: _borderColor),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.assignment_outlined,
                                              size: 18,
                                              color: _isDark ? const Color(0xFFF87171) : AppColors.maroon,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Evaluation Rubrics Attachment',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: _textPrimaryColor,
                                              ),
                                            ),
                                            const Spacer(),
                                            OutlinedButton.icon(
                                              onPressed: _savingDraft ? null : _openRubrics,
                                              icon: const Icon(Icons.open_in_new_rounded, size: 14),
                                              label: const Text('Manage Evaluation Rubrics'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: _isDark ? const Color(0xFFF87171) : AppColors.maroon,
                                                side: BorderSide(
                                                  color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFCBD5E1),
                                                ),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Assign published Capstone rubrics to evaluate each role (optional; can attach later before defense scheduling).',
                                          style: TextStyle(fontSize: 12.5, color: _textSecondaryColor),
                                        ),
                                        if (hasNoRubricsAtAll) ...[
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: _isDark
                                                  ? const Color(0xFF78350F).withValues(alpha: 0.25)
                                                  : const Color(0xFFFFFBEB),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: _isDark
                                                    ? const Color(0xFFD97706).withValues(alpha: 0.4)
                                                    : const Color(0xFFFDE68A),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.warning_amber_rounded,
                                                  size: 18,
                                                  color: _isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    'No available published Capstone rubrics for this stage. Create and publish rubrics in Evaluation Rubrics so they can be attached here.',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: _isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E),
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                ElevatedButton.icon(
                                                  onPressed: _savingDraft ? null : _openRubrics,
                                                  icon: const Icon(Icons.add_rounded, size: 14),
                                                  label: const Text('Create Rubrics'),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: const Color(0xFFB45309),
                                                    foregroundColor: Colors.white,
                                                    elevation: 0,
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 16),
                                        DropdownButtonFormField<int>(
                                          key: ValueKey('panel-rubric-$_panelRubricId'),
                                          initialValue: _panelRubricId,
                                          dropdownColor: _surfaceColor,
                                          style: TextStyle(color: _textPrimaryColor, fontSize: 13),
                                          decoration: _inputDecoration(
                                            labelText: 'Panel Rubric',
                                            prefixIcon: Icon(
                                              Icons.gavel_rounded,
                                              size: 16,
                                              color: _isDark ? const Color(0xFFF87171) : AppColors.maroon,
                                            ),
                                          ),
                                          items: _buildRubricDropdownItems(
                                            'panel',
                                            _panelRubricId,
                                            _panelRubricName,
                                          ),
                                          onChanged: (_saving || _isLocked)
                                              ? null
                                              : (value) {
                                                  setState(() {
                                                    _panelRubricId = value;
                                                    _editedRubricRoles.add('panel');
                                                  });
                                                  _markDirty();
                                                },
                                        ),
                                        const SizedBox(height: 14),
                                        DropdownButtonFormField<int>(
                                          key: ValueKey('adviser-rubric-$_adviserRubricId'),
                                          initialValue: _adviserRubricId,
                                          dropdownColor: _surfaceColor,
                                          style: TextStyle(color: _textPrimaryColor, fontSize: 13),
                                          decoration: _inputDecoration(
                                            labelText: 'Adviser Rubric',
                                            prefixIcon: const Icon(Icons.school_rounded, size: 16, color: Color(0xFFD97706)),
                                          ),
                                          items: _buildRubricDropdownItems(
                                            'adviser',
                                            _adviserRubricId,
                                            _adviserRubricName,
                                          ),
                                          onChanged: (_saving || _isLocked)
                                              ? null
                                              : (value) {
                                                  setState(() {
                                                    _adviserRubricId = value;
                                                    _editedRubricRoles.add('adviser');
                                                  });
                                                  _markDirty();
                                                },
                                        ),
                                        const SizedBox(height: 14),
                                        DropdownButtonFormField<int>(
                                          key: ValueKey('peer-rubric-$_peerRubricId'),
                                          initialValue: _peerRubricId,
                                          dropdownColor: _surfaceColor,
                                          style: TextStyle(color: _textPrimaryColor, fontSize: 13),
                                          decoration: _inputDecoration(
                                            labelText: 'Peer Rubric',
                                            prefixIcon: const Icon(Icons.people_outline_rounded, size: 16, color: Color(0xFF0D9488)),
                                          ),
                                          items: _buildRubricDropdownItems(
                                            'peer',
                                            _peerRubricId,
                                            _peerRubricName,
                                          ),
                                          onChanged: (_saving || _isLocked)
                                              ? null
                                              : (value) {
                                                  setState(() {
                                                    _peerRubricId = value;
                                                    _editedRubricRoles.add('peer');
                                                  });
                                                  _markDirty();
                                                },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              StageOutcomeSettings(scoreController: _qualifyingScore,
                                scoreCarryover: _scoreCarryover, conceptSelection: _conceptConfig['enabled'] == true,
                                enabled: !_saving,
                                onChanged: () { setState(() {}); _markDirty(); },
                                onCarryoverChanged: (v) { setState(() => _scoreCarryover = v); _markDirty(); }),
                              if (_isLocked) ...[
                                const SizedBox(height: 12),
                                const Text('Outcome settings apply to new hearings. Existing hearings keep their recorded policy.'),
                                TextButton(onPressed: _saving ? null : _saveOutcomePolicy,
                                  child: const Text('Save outcome settings')),
                              ],
                            ],
                          ),

                          // TAB 2: Deliverables Split
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSubmissionModeSelector(),
                              if (_isPresentationOnly)
                                _buildPresentationOnlyInfoBanner()
                              else ...[
                                StageDeliverablePresetsBar(
                                  existingStages: ref.read(defenseStagesProvider).stages,
                                  currentDeliverables: _deliverables,
                                  enabled: !_isLocked,
                                  onApplyDeliverables: (newDeliverables) {
                                    setState(() {
                                      _deliverables.clear();
                                      _deliverables.addAll(newDeliverables);
                                      _selectedDeliverable = _deliverables.isNotEmpty ? _deliverables.first : null;
                                      _error = null;
                                    });
                                    _markDirty();
                                  },
                                ),
                                StageDeliverableCounts(
                                  deliverables: _deliverables,
                                  minutesRequired: _minutesRequired == true,
                                ),
                                _buildDeliverableSection(
                                  title: 'Pre-Defense Requirements',
                                  subtitle: 'Required files need faculty acceptance before endorsement and scheduling.',
                                  icon: Icons.folder_open_rounded,
                                  accentColor: const Color(0xFF0F172A),
                                  bgHeaderColor: const Color(0xFFF8FAFC),
                                  borderColor: const Color(0xFFE2E8F0),
                                  count: preDeliverables.length,
                                  buttonText: 'Add Pre-Defense',
                                  onAdd: _isLocked
                                      ? () {}
                                      : () {
                                          setState(() {
                                            final item = <String, dynamic>{
                                              'deliverable_id': 'D${_deliverables.length + 1}',
                                              'label': '',
                                              'deliverable_type': 'pre',
                                              'requirement_timing': 'scheduling',
                                              'deadline_hours_before': 24,
                                              'required': true,
                                              'display_order': _deliverables.length + 1,
                                              'archive_note': '',
                                              'archive_file_template': '',
                                              'is_restricted': false,
                                              'is_defense_material': false,
                                              'verdict_condition': 'all_pass',
                                              'file_format': 'any',
                                            };
                                            _deliverables.add(item);
                                            _selectedDeliverable = item;
                                            _minutesExpanded = false;
                                          });
                                          _markDirty();
                                        },
                                  emptyPlaceholderText: 'No pre-defense gatekeepers configured yet. (e.g. Proposal Manuscript Draft, Similarity Report)',
                                  items: preDeliverables,
                                  isPost: false,
                                ),
                                const SizedBox(height: 18),
                                _buildDeliverableSection(
                                  title: 'Post-Defense Requirements & Archive',
                                  subtitle: 'Deliverables required for milestone clearance and repository archiving.',
                                  icon: Icons.inventory_2_rounded,
                                  accentColor: const Color(0xFF0F172A),
                                  bgHeaderColor: const Color(0xFFF8FAFC),
                                  borderColor: const Color(0xFFE2E8F0),
                                  count: postDeliverables.length,
                                  buttonText: 'Add Post-Defense',
                                  onAdd: _isLocked
                                      ? () {}
                                      : () {
                                          setState(() {
                                            final item = <String, dynamic>{
                                              'deliverable_id': 'D${_deliverables.length + 1}',
                                              'label': '',
                                              'deliverable_type': 'post',
                                              'required': true,
                                              'display_order': _deliverables.length + 1,
                                              'archive_note': '',
                                              'archive_file_template': postDeliverables.isEmpty ? '{project}' : '{project}_{deliverable}',
                                              'is_restricted': false,
                                              'is_defense_material': false,
                                              'verdict_condition': 'all_pass',
                                              'file_format': 'any',
                                            };
                                            _deliverables.add(item);
                                            _selectedDeliverable = item;
                                            _minutesExpanded = false;
                                          });
                                          _markDirty();
                                        },
                                  emptyPlaceholderText: 'No post-defense deliverables configured yet. (e.g. Final Manuscript PDF, Source Code Zip, Demo Video)',
                                  items: postDeliverables,
                                  isPost: true,
                                  stageDefaultNamingWidget: postDeliverables.length >= 2
                                      ? _buildStageDefaultNamingDropdown(postDeliverables)
                                      : null,
                                ),
                              ],
                              if (_minutesRequired == true) ...[
                                const SizedBox(height: 18),
                                StageMinutesDeliverableCard(
                                  number: _minutesNumber, name: _minutesName, stageName: _label.text, enabled: !_isLocked,
                                  expanded: _minutesExpanded,
                                  onToggle: () => setState(() {
                                    _minutesExpanded = !_minutesExpanded;
                                    if (_minutesExpanded) _selectedDeliverable = null;
                                  }),
                                  onConfigure: () => setState(() => _activeTab = 0),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),

                    // Pinned Navigation & Action Footer
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: StageSetupActions(
                        children: [
                          TextButton(
                            onPressed: _saving ? null : _handleBack,
                            style: TextButton.styleFrom(
                              foregroundColor: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
                              textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            child: Text(_isLocked ? 'Back to Setup' : 'Cancel'),
                          ),
                          if (!_isLocked) ...[
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: (_saving || _savingDraft) ? null : _saveDraft,
                              icon: const Icon(Icons.save_outlined, size: 16),
                              label: Text(_savingDraft ? 'Saving draft…' : 'Save draft'),
                            ),
                          ],
                          const Spacer(),
                          if (_activeTab > 0) ...[
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() => _activeTab -= 1);
                              },
                              icon: const Icon(Icons.arrow_back_rounded, size: 15),
                              label: const Text('Back'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF334155),
                                side: BorderSide(color: _borderColor),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (_activeTab < 2) ...[
                            FilledButton.icon(
                              onPressed: () {
                                setState(() => _activeTab += 1);
                              },
                              iconAlignment: IconAlignment.end,
                              icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                              label: Text(
                                _activeTab == 0 ? 'Next: Grading & Rubrics' : 'Next: Deliverables',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: _isDark ? DefensysTokens.maroon : AppColors.maroon,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (!_isLocked)
                            DefensysSaveButton(
                              onPressed: (hasWeightError || _savingDraft) ? null : _save,
                              isSaving: _saving,
                              label: 'Save changes',
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: _inputFillColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _borderColor),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_outline, size: 16, color: _textSecondaryColor),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Read-Only Mode',
                                    style: TextStyle(
                                      color: _textSecondaryColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar({
    required int activeTab,
    required bool hasWeightError,
    required int deliverableCount,
    required bool isPresentationOnly,
    required void Function(int) onTabSelected,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _buildTabItem(
            index: 0,
            label: '1. Stage Details',
            icon: Icons.alt_route_rounded,
            isSelected: activeTab == 0,
            onTap: () => onTabSelected(0),
          ),
          const SizedBox(width: 4),
          _buildTabItem(
            index: 1,
            label: '2. Grading & Rubrics',
            icon: Icons.balance_rounded,
            badge: hasWeightError
                ? Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
            isSelected: activeTab == 1,
            onTap: () => onTabSelected(1),
          ),
          const SizedBox(width: 4),
          _buildTabItem(
            index: 2,
            label: '3. Deliverables',
            icon: isPresentationOnly ? Icons.campaign_rounded : Icons.inventory_2_rounded,
            badge: (deliverableCount > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: activeTab == 2
                              ? Colors.white.withValues(alpha: 0.25)
                              : (_isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$deliverableCount',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: activeTab == 2
                                ? Colors.white
                                : (_isDark ? DefensysTokens.mistTextPrimary : AppColors.textPrimary),
                          ),
                        ),
                      )
                    : null),
            isSelected: activeTab == 2,
            onTap: () => onTabSelected(2),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem({
    required int index,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    Widget? badge,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.maroon : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.maroon.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected
                    ? Colors.white
                    : (_isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : (_isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF334155)),
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                badge,
              ],
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String labelText,
    String? hintText,
    String? helperText,
    String? errorText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      errorText: errorText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      isDense: true,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: _textSecondaryColor,
      ),
      hintStyle: TextStyle(
        fontSize: 12.5,
        color: _isDark ? DefensysTokens.textSecondaryDark.withValues(alpha: 0.6) : const Color(0xFF94A3B8),
      ),
      helperStyle: TextStyle(
        fontSize: 11,
        color: _textSecondaryColor,
      ),
      filled: true,
      fillColor: _inputFillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _isDark ? const Color(0xFFF87171) : AppColors.maroon, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _isDark ? const Color(0xFFF87171) : AppColors.maroon, width: 1.5),
      ),
    );
  }

  Widget _buildWeightDistributionBar(int panel, int adviser, int peer) {
    final total = panel + adviser + peer;
    final isValid = total == 100;

    final pFlex = (panel > 0) ? panel : 0;
    final aFlex = (adviser > 0) ? adviser : 0;
    final peFlex = (peer > 0) ? peer : 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isValid
            ? (_isDark ? DefensysTokens.mistInputFill : const Color(0xFFF8FAFC))
            : (_isDark ? const Color(0xFF7F1D1D).withValues(alpha: 0.25) : const Color(0xFFFEF2F2)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isValid
              ? _borderColor
              : (_isDark ? const Color(0xFFEF4444).withValues(alpha: 0.4) : const Color(0xFFFECACA)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isValid ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                    size: 15,
                    color: isValid
                        ? (_isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                        : (_isDark ? const Color(0xFFF87171) : AppColors.danger),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isValid ? 'Balanced Allocation (100%)' : 'Allocation Error: Must Total 100%',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isValid
                          ? (_isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                          : (_isDark ? const Color(0xFFF87171) : AppColors.danger),
                    ),
                  ),
                ],
              ),
              Text(
                'Total: $total%',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: isValid
                      ? (_isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                      : (_isDark ? const Color(0xFFF87171) : AppColors.danger),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 10,
              width: double.infinity,
              color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
              child: (total > 0)
                  ? Row(
                      children: [
                        if (pFlex > 0)
                          Flexible(
                            flex: pFlex,
                            child: Container(
                              color: AppColors.maroon,
                              height: double.infinity,
                            ),
                          ),
                        if (aFlex > 0)
                          Flexible(
                            flex: aFlex,
                            child: Container(
                              color: const Color(0xFFD97706),
                              height: double.infinity,
                            ),
                          ),
                        if (peFlex > 0)
                          Flexible(
                            flex: peFlex,
                            child: Container(
                              color: const Color(0xFF0D9488),
                              height: double.infinity,
                            ),
                          ),
                      ],
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLegendItem('Panel', '$panel%', AppColors.maroon),
              _buildLegendItem('Adviser', '$adviser%', const Color(0xFFD97706)),
              _buildLegendItem('Peer', '$peer%', const Color(0xFF0D9488)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 11.5,
            color: _textSecondaryColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11.5,
            color: _textPrimaryColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildSubmissionModeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: _panelBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
        boxShadow: _isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 18,
                color: _isDark ? const Color(0xFFF87171) : AppColors.maroon,
              ),
              const SizedBox(width: 8),
              Text(
                'Will students submit files for this stage?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _textPrimaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _submissionModeCard(
                  title: 'Student file submissions',
                  description:
                      'Configure pre-defense requirements and post-defense submissions.',
                  icon: Icons.description_rounded,
                  selected: !_isPresentationOnly,
                  onTap: _isLocked
                      ? null
                      : () {
                          if (_isPresentationOnly) {
                            setState(() {
                              _isPresentationOnly = false;
                              _selectedDeliverable = null;
                            });
                            _markDirty();
                          }
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _submissionModeCard(
                  title: 'Presentation / Demo Only',
                  description:
                      'Students present without uploading deliverables. Minutes are configured in Stage Details.',
                  icon: Icons.co_present_rounded,
                  selected: _isPresentationOnly,
                  onTap: _isLocked
                      ? null
                      : () async {
                          if (!_isPresentationOnly) {
                            if (_deliverables.isNotEmpty) {
                              final confirmed = await confirmRemoveStageDeliverables(
                                context, _deliverables.length,
                              );
                              if (!confirmed || !mounted) return;
                            }
                            setState(() {
                              _isPresentationOnly = true;
                              _selectedDeliverable = null;
                            });
                            _markDirty();
                          }
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _submissionModeCard({
    required String title,
    required String description,
    required IconData icon,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final isPres = title.contains('Presentation');
    final activeBg = isPres
        ? (_isDark ? const Color(0xFF064E3B).withValues(alpha: 0.3) : const Color(0xFFF0FDF4))
        : (_isDark ? const Color(0xFF4C0519).withValues(alpha: 0.35) : const Color(0xFFFAF5FF));
    final activeBorder = isPres
        ? (_isDark ? const Color(0xFF10B981) : const Color(0xFF22C55E))
        : (_isDark ? const Color(0xFFF87171) : AppColors.maroon);
    final activeIconColor = isPres
        ? (_isDark ? const Color(0xFF34D399) : const Color(0xFF16A34A))
        : (_isDark ? const Color(0xFFF87171) : AppColors.maroon);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? activeBg : _inputFillColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? activeBorder : _borderColor,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: selected
                  ? activeIconColor
                  : (_isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF94A3B8)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 15, color: _textPrimaryColor),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _textPrimaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _textSecondaryColor,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresentationOnlyInfoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF064E3B).withValues(alpha: 0.25) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isDark ? const Color(0xFF059669).withValues(alpha: 0.4) : const Color(0xFFBBF7D0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isDark ? const Color(0xFF064E3B).withValues(alpha: 0.5) : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.campaign_rounded,
                  color: _isDark ? const Color(0xFF34D399) : const Color(0xFF15803D),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Presentation / Demo Mode Active',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _isDark ? const Color(0xFF6EE7B7) : const Color(0xFF14532D),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'This milestone does not require document submissions.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _isDark ? const Color(0xFFA7F3D0) : const Color(0xFF166534),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '• Students will not be prompted to upload manuscripts or archive files for this stage.\n'
            '• Advisers can endorse teams directly based on verbal presentation or demo readiness.\n'
            '• Administrators can schedule defenses freely once endorsed.',
            style: TextStyle(
              fontSize: 12.5,
              color: _isDark ? const Color(0xFFA7F3D0) : const Color(0xFF166534),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliverableSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color bgHeaderColor,
    required Color borderColor,
    required int count,
    required String buttonText,
    required VoidCallback onAdd,
    required String emptyPlaceholderText,
    required List<Map<String, dynamic>> items,
    required bool isPost,
    Widget? stageDefaultNamingWidget,
  }) {
    final effectiveAccent = _isDark
        ? (isPost ? const Color(0xFFF87171) : const Color(0xFF60A5FA))
        : accentColor;
    final effectiveBgHeader = _isDark
        ? (isPost
            ? const Color(0xFF7F1D1D).withValues(alpha: 0.25)
            : const Color(0xFF1E3A8A).withValues(alpha: 0.25))
        : bgHeaderColor;
    final effectiveBorder = _isDark
        ? (isPost
            ? const Color(0xFFEF4444).withValues(alpha: 0.35)
            : const Color(0xFF3B82F6).withValues(alpha: 0.35))
        : borderColor;

    return Container(
      decoration: BoxDecoration(
        color: _panelBgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: effectiveBgHeader,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: effectiveBorder)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: effectiveAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: effectiveAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(
                              color: effectiveAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count item${count == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: effectiveAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: _textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isLocked)
                  DefensysShadcnScope(
                    child: ShadButton.outline(
                      size: ShadButtonSize.sm,
                      onPressed: onAdd,
                      leading: const Icon(Icons.add, size: 14),
                      child: Text(buttonText),
                    ),
                  ),
              ],
            ),
          ),
          if (stageDefaultNamingWidget != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: stageDefaultNamingWidget,
            ),
          ],
          Padding(
            padding: const EdgeInsets.all(12),
            child: items.isEmpty
                ? InkWell(
                    onTap: _isLocked ? null : onAdd,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: _inputFillColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isPost ? Icons.inventory_2_outlined : Icons.folder_open_rounded,
                            size: 16,
                            color: _textSecondaryColor,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              emptyPlaceholderText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _textSecondaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : StageDeliverableOverview(
                    items: items,
                    isPost: isPost,
                    selectedItem: _selectedDeliverable,
                    onSelect: (item) => setState(() {
                      _selectedDeliverable = item;
                      if (item != null) _minutesExpanded = false;
                      _error = null;
                    }),
                    showDoneEditingButton: false,
                    buildEditor: (item, index) {
                      final validationError = _deliverableErrorFor(item);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (validationError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                validationError,
                                style: TextStyle(color: Theme.of(context).colorScheme.error),
                              ),
                            ),
                          _deliverableRow(
                            item,
                            isPost,
                            index: index,
                            onDone: () => setState(() => _selectedDeliverable = null),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String? _deliverableErrorFor(Map<String, dynamic> item) {
    final error = _error;
    if (!identical(item, _selectedDeliverable) || error == null) return null;
    if (error.startsWith('Enter a name') &&
        (item['label']?.toString().trim().isEmpty ?? true)) {
      return error;
    }
    if (error.startsWith('Use at most') &&
        RegExp(r'\{[a-zA-Z0-9_]+\}')
                .allMatches(item['archive_file_template']?.toString() ?? '')
                .length >
            3) {
      return error;
    }
    return null;
  }

  Widget _buildStageDefaultNamingDropdown(List<Map<String, dynamic>> postDeliverables) {
    const presets = {
      '{project}_{deliverable}': 'Project + Deliverable (Recommended)',
      '{project}': 'Project Only',
      '{year}_{course}_{project}_{deliverable}': 'Academic Standard',
      '{stage}_{project}_{deliverable}': 'Stage Specific',
      '{semester}_{project}_{deliverable}': 'Semester Standard',
    };

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _isDark
            ? const Color(0xFF1E3A8A).withValues(alpha: 0.15)
            : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isDark
              ? const Color(0xFF3B82F6).withValues(alpha: 0.3)
              : const Color(0xFFBFDBFE),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 15,
                color: _isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Apply Naming Pattern to All Post-Defense Deliverables',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF),
                    fontFamily: DefensysTokens.fontFamily,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: presets.entries.map((entry) {
              final isProjectOnly = entry.key == '{project}';
              final hasCollisionRisk = isProjectOnly && postDeliverables.length >= 2;
              return InkWell(
                onTap: _isLocked
                    ? null
                    : () {
                        setState(() {
                          for (final d in postDeliverables) {
                            final ctrl = d['_templateController'] as TextEditingController?;
                            if (ctrl != null) {
                              ctrl.text = entry.key;
                            }
                            d['archive_file_template'] = entry.key;
                          }
                        });
                        _markDirty();
                      },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: hasCollisionRisk
                        ? (_isDark ? const Color(0xFF78350F).withValues(alpha: 0.3) : const Color(0xFFFEFCE8))
                        : _surfaceColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: hasCollisionRisk
                          ? (_isDark ? const Color(0xFFD97706) : const Color(0xFFFDE68A))
                          : _borderColor,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasCollisionRisk) ...[
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 13,
                          color: _isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: hasCollisionRisk
                              ? (_isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E))
                              : _textPrimaryColor,
                          fontFamily: DefensysTokens.fontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (postDeliverables.length >= 2) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: _isDark ? const Color(0xFF71717A) : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '"Project + Deliverable" is recommended when you have multiple deliverables to avoid filename conflicts.',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: _textSecondaryColor,
                      fontFamily: DefensysTokens.fontFamily,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _deliverableRow(Map<String, dynamic> item, bool isPost, {required int index, VoidCallback? onDone}) {
    final labelController = item['_labelController'] as TextEditingController? ??
        (item['_labelController'] = TextEditingController(text: item['label']?.toString() ?? ''));
    final templateController = item['_templateController'] as TextEditingController? ??
        (item['_templateController'] = TextEditingController(
          text: item['archive_file_template']?.toString() ?? '',
        ));

    const legacyDefault = '{year}.{course}.{project}.{stage}.{deliverable}.{semester}';
    if (templateController.text.trim() == legacyDefault) {
      templateController.text = '';
      item['archive_file_template'] = '';
    }

    final currentFormat = (item['file_format']?.toString().isNotEmpty == true)
        ? item['file_format'].toString()
        : 'any';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isDark ? _borderColor : const Color(0xFFE2E8F0),
        ),
        boxShadow: _isDark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x06000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Distinct Item Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _inputFillColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(9),
                topRight: Radius.circular(9),
              ),
              border: Border(bottom: BorderSide(color: _borderColor)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Text(
                    '#$index',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    labelController.text.trim().isNotEmpty
                        ? 'Deliverable #$index • ${labelController.text.trim()}'
                        : 'Deliverable #$index',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _textPrimaryColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isLocked
                      ? null
                      : () {
                          setState(() {
                            _deliverables.remove(item);
                            (item['_labelController'] as TextEditingController?)?.dispose();
                            (item['_templateController'] as TextEditingController?)?.dispose();
                          });
                          _markDirty();
                        },
                  icon: Icon(Icons.delete_outline_rounded, color: _isLocked ? Colors.grey : AppColors.danger, size: 18),
                  tooltip: 'Remove Deliverable #$index',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    hoverColor: AppColors.danger.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ),
          ),

          // 2. Card Content Body
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    void syncPolicySlot() {
                      final policy = item['file_policy'];
                      if (policy is Map && policy['mode'] == 'concepts') {
                        final slots = policy['slots'] as List? ?? [];
                        final label = (item['label'] as String?)?.trim();
                        final format = item['file_format'] as String? ?? 'pdf';
                        final req = item['required'] == true;
                        if (slots.isEmpty) {
                          policy['slots'] = [
                            {
                              'key': 'paper',
                              'label': label?.isNotEmpty == true ? label : 'Concept paper',
                              'file_format': format,
                              'required': req,
                            }
                          ];
                        } else {
                          for (final s in slots) {
                            if (s is Map) {
                              s['file_format'] = format;
                              s['required'] = req;
                              if (label?.isNotEmpty == true) s['label'] = label;
                            }
                          }
                        }
                      }
                    }

                    final nameField = TextFormField(
                        controller: labelController,
                        readOnly: _isLocked,
                        decoration: _inputDecoration(
                          labelText: isPost ? 'Post-Defense Deliverable Name *' : 'Pre-Defense Requirement Name *',
                          hintText: isPost
                              ? 'e.g. Final Manuscript PDF, Source Code Zip'
                              : 'e.g. Manuscript Draft, Endorsement Form',
                        ),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textPrimaryColor),
                        onChanged: (v) {
                          item['label'] = v.trim();
                          syncPolicySlot();
                          _markDirty();
                          setState(() {});
                        },
                      );
                    final formatField = SizedBox(
                      width: 210,
                      child: StageFileFormatPicker(
                        value: currentFormat,
                        enabled: !_isLocked,
                        onChanged: (val) {
                          setState(() {
                            item['file_format'] = val;
                            syncPolicySlot();
                          });
                          _markDirty();
                        },
                      ),
                    );
                    final requiredField = DefensysShadcnScope(
                      child: ShadCheckbox(
                        value: item['required'] == true,
                        enabled: !_isLocked,
                        label: const Text('Required'),
                        onChanged: (value) {
                          setState(() {
                            item['required'] = value;
                            syncPolicySlot();
                          });
                          _markDirty();
                        },
                      ),
                    );

                    final hasAdvancedSettings = isPost
                        ? (item['is_restricted'] == true ||
                            (item['archive_file_template'] != null &&
                                item['archive_file_template'].toString().trim().isNotEmpty &&
                                item['archive_file_template'] != '{project}' &&
                                item['archive_file_template'] != '{project}_{deliverable}'))
                        : (item['is_defense_material'] == true);
                    final isAdvancedExpanded = item['_expandedAdvanced'] as bool? ?? hasAdvancedSettings;

                    final moreOptionsBtn = DefensysShadcnScope(
                      child: ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: () {
                          setState(() {
                            item['_expandedAdvanced'] = !isAdvancedExpanded;
                          });
                        },
                        leading: Icon(
                          isAdvancedExpanded ? Icons.expand_less_rounded : Icons.tune_rounded,
                          size: 14,
                        ),
                        child: Text(
                          isAdvancedExpanded ? 'Fewer options' : 'More options',
                        ),
                      ),
                    );

                    return constraints.maxWidth < 620
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              nameField,
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [formatField, requiredField, moreOptionsBtn],
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: nameField),
                              const SizedBox(width: 10),
                              formatField,
                              const SizedBox(width: 10),
                              requiredField,
                              const SizedBox(width: 6),
                              moreOptionsBtn,
                            ],
                          );
                  },
                ),

                DocumentPolicyEditor(
                  value: Map<String, dynamic>.from(item['file_policy'] as Map? ?? {}),
                  enabled: !_isLocked,
                  allowConcepts: !isPost && _conceptConfig['enabled'] == true,
                  deliverableLabel: labelController.text,
                  fileFormat: currentFormat,
                  required: item['required'] == true,
                  onChanged: (value) {
                    setState(() => item['file_policy'] = value);
                    _markDirty();
                  },
                ),

                Builder(
                  builder: (context) {
                    final hasAdvancedSettings = isPost
                        ? (item['is_restricted'] == true ||
                            (item['archive_file_template'] != null &&
                                item['archive_file_template'].toString().trim().isNotEmpty &&
                                item['archive_file_template'] != '{project}' &&
                                item['archive_file_template'] != '{project}_{deliverable}'))
                        : (item['is_defense_material'] == true);
                    final isAdvancedExpanded = item['_expandedAdvanced'] as bool? ?? hasAdvancedSettings;

                    if (!isAdvancedExpanded) {
                      final summaryText = isPost
                          ? '${item['required'] == true ? 'Required' : 'Optional'} after defense${item['is_restricted'] == true ? ' · Restricted archive' : ''}'
                          : 'Faculty review before scheduling${item['is_defense_material'] == true ? ' · Panel material' : ''}';
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _inputFillColor,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: _borderColor),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.info_outline_rounded, size: 12, color: _textSecondaryColor),
                                  const SizedBox(width: 5),
                                  Text(
                                    summaryText,
                                    style: TextStyle(fontSize: 11, color: _textPrimaryColor, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _inputFillColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.tune_rounded, size: 14, color: _textSecondaryColor),
                              const SizedBox(width: 6),
                              Text(
                                isPost ? 'Post-defense options' : 'Panel access',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _textPrimaryColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (!isPost) ...[
                            DefenseMaterialToggle(
                              value: item['is_defense_material'] == true,
                              enabled: !_isLocked,
                              onChanged: (value) {
                                setState(() => item['is_defense_material'] = value);
                                _markDirty();
                              },
                            ),
                            const SizedBox(height: 8),
                            const DeliverableTimingFields(),
                          ],
                          if (isPost) ...[
                            Row(
                              children: [
                                DefensysShadcnScope(
                                  child: ShadCheckbox(
                                    value: item['is_restricted'] == true,
                                    enabled: !_isLocked,
                                    onChanged: (v) {
                                      setState(() {
                                        item['is_restricted'] = v;
                                      });
                                      _markDirty();
                                    },
                                    label: Text(
                                      'Restricted (Private Institutional Archive)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _textPrimaryColor,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Tooltip(
                                  message: 'Private for faculty and admin records only; hidden from students.',
                                  constraints: const BoxConstraints(maxWidth: 240),
                                  child: Icon(Icons.help_outline_rounded, size: 14, color: _textSecondaryColor),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            const StagePostDefenseReviewNotice(),
                            const SizedBox(height: 10),
                            RepositoryArchiveNamingPanel(
                              templateController: templateController,
                              deliverableLabel: labelController.text,
                              fileFormat: currentFormat,
                              isLocked: _isLocked,
                              isPit: false,
                              stageOrEventLabel: _label.text,
                              siblingDeliverables: _deliverables.where((d) => d['deliverable_type'] == (isPost ? 'post' : 'pre')).toList(),
                              currentIndex: _deliverables.where((d) => d['deliverable_type'] == (isPost ? 'post' : 'pre')).toList().indexOf(item),
                              onChanged: () {
                                item['archive_file_template'] = templateController.text.trim();
                                setState(() {});
                                _markDirty();
                              },
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                if (onDone != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: DefensysShadcnScope(
                      child: ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: onDone,
                        leading: const Icon(Icons.check_rounded, size: 14),
                        child: const Text('Done editing'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(String message, {bool warning = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warning
            ? (_isDark ? const Color(0xFF78350F).withValues(alpha: 0.3) : const Color(0xFFFFFBEB))
            : (_isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.3) : const Color(0xFFF0F9FF)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: warning
              ? (_isDark ? const Color(0xFFF59E0B).withValues(alpha: 0.5) : const Color(0xFFF59E0B))
              : (_isDark ? const Color(0xFF38BDF8).withValues(alpha: 0.5) : const Color(0xFFBAE6FD)),
        ),
      ),
      child: Text(message, style: TextStyle(fontSize: 13, color: _textPrimaryColor)),
    );
  }

}
