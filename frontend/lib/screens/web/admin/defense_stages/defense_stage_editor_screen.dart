import 'widgets/stage_minutes_settings.dart';
import 'widgets/stage_outcome_settings.dart';
import 'package:defensys/widgets/repository/document_policy_editor.dart';
import 'package:flutter/material.dart';
import '../../../../widgets/repository/shared_deliverables_editor.dart';
import '../../../../widgets/repository/deliverable_submission_settings.dart';
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
import '../../../../widgets/grading/grading_setup_section.dart';
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
  final int? semesterId;
  final bool readOnly;

  const DefenseStageEditorScreen({
    super.key,
    required this.stageId,
    this.initialTab = 0,
    this.initialStage,
    required this.onBack,
    this.semesterId,
    this.readOnly = false,
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
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int? _semesterId;
  List<Map<String, dynamic>> _deliverables = [];
  List<Map<String, dynamic>> _sharedDeliverables = [];
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
      'is_presentation_only': false,
      'minutes_required': _minutesRequired,
      'concept_config': {..._conceptConfig, if (_conceptConfig['enabled'] == true) 'review_policy': 'always',},
      'qualifying_score': double.tryParse(_qualifyingScore.text.trim()),
      'score_carryover': _scoreCarryover,
      'minutes_deliverable_id': _minutesNumber.text,
      'minutes_deliverable_label': _minutesName.text,
      'deliverables': _deliverables,
      'shared_deliverables': configuredSharedDeliverables(_deliverables, _sharedDeliverables,),
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
      if (mounted) setState(() => _error = 'Could not save your draft. Your setup is still open; please try again.',);
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
      if (mounted) setState(() => _error = 'Could not discard the draft. Please try again.',);
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
      ),);
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
    for (final item in deliverableSetupItems(_deliverables, _sharedDeliverables,)) {
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

    // These reads are independent of the selected semester and stage detail.
    final supportingData = Future.wait([
      ref.read(defenseStagesProvider.notifier).fetchStages(),
      ref.read(rubricEngineProvider.notifier).fetchRubrics(
            scope: 'capstone',
            status: '',
          ),
    ]);
    await ref.read(academicPeriodProvider.notifier).fetchPeriods();
    if (!mounted) return;
    final active = ref.read(academicPeriodProvider).activeSemester;
    _semesterId ??= widget.semesterId ?? _asInt(active?['id']);

    final detail = await ref
        .read(defenseStagesProvider.notifier)
        .fetchStageDetail(widget.stageId, semesterId: _semesterId);

    await supportingData;
    if (!mounted) return;

    if (detail != null) {
      final semester = detail['active_semester'];
      if (semester is Map) {
        _semesterId = _asInt(semester['id']);
      }
    }

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
    final restored = {...?_stage, if (!_structureLocked) ...draft.fields};
    for (final key in ['deliverables', 'shared_deliverables']) {
      restored[key] = restoreProtectedDeliverables(draft.fields[key] ?? restored[key], serverStage?[key],);
    }
    _applyStage(restored);
    // Locks and workflow metadata always come from the server.
    _stage = serverStage;
    final grading = draft.fields['grading_config'];
    if (grading is Map && !_structureLocked) {
      // A saved setup snapshot is not an instruction to undo assignments made
      // in Rubrics since the draft was written. Restore only explicit edits.
      final base = draft.fields['rubric_assignment_base'] as Map? ?? {};
      final changes = draft.fields['rubric_assignment_changes'] as List? ?? [];
      _editedRubricRoles.addAll(changes.whereType<String>().where((role) =>
        base.containsKey(role) && _asInt(base[role]) == _serverRubricIds[role],
        ),);
      _applyWeights(Map<String, dynamic>.from(grading));
      _applyRubricAssignments(Map<String, dynamic>.from(grading), roles: _editedRubricRoles,);
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
    _conceptConfig = Map<String, dynamic>.from(stage['concept_config'] as Map? ?? {},);
    _sharedDeliverables = sharedDeliverableValues(stage['shared_deliverables'] ??
        (_conceptConfig['enabled'] == true ? defaultSharedDeliverables() : []),);
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
      roles: {'panel', 'adviser', 'peer'}.difference(_editedRubricRoles),);
  }

  void _applyRubricAssignments(Map<String, dynamic> grading, {required Set<String> roles,}) {
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

  Future<void> _save() async {
    if (_isLocked) return;
    if (!_structureLocked && StageOutcomeSettings.validateScore(_qualifyingScore.text) != null) {
      setState(() { _activeTab = 1; _error = 'Set a qualifying panel score from 0 to 100%.'; });
      return;
    }
    if (_label.text.trim().isEmpty) {
      setState(() => _error = 'Stage name is required.');
      return;
    }
    if (!_structureLocked && _semesterId == null) {
      setState(() => _error = 'Select a semester for grade weights.');
      return;
    }
    if (!_structureLocked && _weightTotal != 100) {
      setState(() => _error = 'Panel, Adviser, and Peer weights must total 100%.',);
      return;
    }

    // Validate student deliverable labels and archive naming templates.
    final configuredItems = deliverableSetupItems(_deliverables, _sharedDeliverables,);
    for (int i = 0; i < configuredItems.length; i++) {
      final d = configuredItems[i];
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
            if (!_structureLocked) ...{
            'label': _label.text.trim(),
            'code': _code.text.trim(),
            'display_order': _orderPosition,
            'description': _description.text.trim(),
            'is_active': _isActive,
            'is_presentation_only': false,
            'minutes_required': _minutesRequired,
      'concept_config': {..._conceptConfig, if (_conceptConfig['enabled'] == true) 'review_policy': 'always',},
      'qualifying_score': double.tryParse(_qualifyingScore.text.trim()),
      'score_carryover': _scoreCarryover,
            'minutes_deliverable_id': _minutesNumber.text.trim(),
            'minutes_deliverable_label': _minutesName.text.trim(),
            },
            'deliverables': _deliverables,
            'shared_deliverables': configuredSharedDeliverables(_deliverables, _sharedDeliverables,),
            if (endorsedAction != null) 'endorsed_teams_action': endorsedAction,
          },
        );

    final weightsOk = stageOk && (_structureLocked || await ref
        .read(defenseStagesProvider.notifier)
        .updateGradingConfig(widget.stageId, _semesterId!, {
          'panel_weight': int.tryParse(_panel.text.trim()) ?? 0,
          'adviser_weight': int.tryParse(_adviser.text.trim()) ?? 0,
          'peer_weight': int.tryParse(_peer.text.trim()) ?? 0,
          if (_editedRubricRoles.contains('panel')) 'panel_rubric_id': _panelRubricId,
          if (_editedRubricRoles.contains('adviser')) 'adviser_rubric_id': _adviserRubricId,
          if (_editedRubricRoles.contains('peer')) 'peer_rubric_id': _peerRubricId,
        }));

    if (!mounted) return;

    setState(() => _saving = false);

    if (stageOk && weightsOk) {
      try {
        await _clearBrowserDraft();
        _savedDraft = null;
      } catch (_) {
        setState(() => _error = 'Stage saved, but its browser draft could not be removed.',);
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



  Widget _buildPositionSelector() {
    final allStages = ref.watch(defenseStagesProvider).stages;
    final totalStages = allStages.length;
    final currentPos = _orderPosition.clamp(1, totalStages > 0 ? totalStages : 1,);
    final initialOrder = _asInt(_stage?['display_order']);

    // Calculate highest order of completed stages
    int lastCompletedOrder = 0;
    for (int i = 0; i < allStages.length; i++) {
      final s = allStages[i];
      final isStageLocked = s['is_locked'] == true || s['structure_locked'] == true || s['status'] == 'locked';
      if (isStageLocked) {
        final order = _asInt(s['display_order']) ?? (i + 1);
        if (order > lastCompletedOrder) {
          lastCompletedOrder = order;
        }
      }
    }

    final minPosition = _structureLocked
        ? (initialOrder ?? 1)
        : (lastCompletedOrder + 1);

    return PipelinePositionSelector(
      selectedPosition: currentPos,
      totalSlots: totalStages > 0 ? totalStages : 1,
      existingStages: allStages,
      currentStageName: _label.text,
      editing: true,
      initialOrder: initialOrder,
      isLocked: _structureLocked,
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
      widget.readOnly ||
      _stage?['is_locked'] == true || _stage?['status'] == 'locked';
  bool get configuredItemsHaveData =>
      deliverableSetupItems(_deliverables, _sharedDeliverables,).any((row) => row['has_data'] == true);
  bool get _structureLocked => _isLocked || _stage?['structure_locked'] == true;
  String? get _lockReason =>
      _stage?[_isLocked ? 'lock_reason' : 'structure_lock_reason']?.toString();

  String _nextDeliverableId() {
    var number = 1;
    while (_deliverables.any((row) => row['deliverable_id'] == 'D$number')) {
      number++;
    }
    return 'D$number';
  }

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
                  _isLocked ? 'Stage Configuration Locked' : 'Stage Settings Protected',
                  style: TextStyle(
                    color: _isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _isLocked
                      ? (_lockReason ?? 'Configuration is locked because grading has started.')
                      : '${_lockReason ?? 'Stage settings are protected.'} You can still add deliverables and edit unused requirements before grading starts.',
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
    final preDeliverables = deliverableSetupItems(_deliverables, _sharedDeliverables,).where((d) => d['deliverable_type'] == 'pre').toList();
    final postDeliverables = deliverableSetupItems(_deliverables, _sharedDeliverables,).where((d) => d['deliverable_type'] == 'post').toList();

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
              if (_structureLocked) _buildLockedBanner(),
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
                        deliverableCount: deliverableSetupItems(_deliverables, _sharedDeliverables,).length + (_minutesRequired == true ? 1 : 0),
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
                                      readOnly: _structureLocked,
                                      style: TextStyle(color: _textPrimaryColor,),
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
                                      readOnly: _structureLocked,
                                      style: TextStyle(color: _textPrimaryColor,),
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
                              Text('Stage policies', style: Theme.of(context).textTheme.titleSmall,),
                              const SizedBox(height: 4),
                              Text('Enable only the workflows this stage uses.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _textSecondaryColor),),
                              const SizedBox(height: 12),
                              ConceptSettings(value: _conceptConfig, enabled: !_structureLocked, onChanged: (value) {
                                setState(() {
                                  if (_conceptConfig['enabled'] != true && value['enabled'] == true && _sharedDeliverables.isEmpty) {
                                    _sharedDeliverables = defaultSharedDeliverables();
                                    ensureConceptPapers(_deliverables, value, sharedItems: _sharedDeliverables,);
                                    linkNewSharedConceptDefaults(_deliverables, _sharedDeliverables,);
                                  }
                                  _conceptConfig = value;
                                  ensureConceptPapers(_deliverables, value, sharedItems: _sharedDeliverables,);
                                  if (!_deliverables.contains(_selectedDeliverable,)) _selectedDeliverable = null;
                                });
                                _markDirty();
                              },),
                              const SizedBox(height: 20),
                              StageMinutesSettings(
                                requiredMinutes: _minutesRequired, enabled: !_structureLocked,
                                onChanged: (value) { setState(() { _minutesRequired = value; _error = null; }); _markDirty(); },
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                controller: _description,
                                readOnly: _structureLocked,
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
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8,),
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
                                    style: TextStyle(fontSize: 12, color: _textSecondaryColor,),
                                  ),
                                  activeTrackColor: AppColors.maroon,
                                  value: _isActive,
                                  onChanged: _structureLocked
                                      ? null
                                      : (v) {
                                          setState(() => _isActive = v);
                                          _markDirty();
                                        },
                                ),
                              ),
                            ],
                          ),

                          // TAB 1: Grading and rubrics
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              GradingSetupSection(
                                enabled: !_saving && !_structureLocked,
                                canManageRubrics: !_saving && !_savingDraft,
                                onManageRubrics: _openRubrics,
                                resetLabel: 'Reset to 50 / 30 / 20',
                                onReset: () { _resetWeights(); _markDirty(); },
                                roles: [
                                  GradingRoleSetup(role: 'panel', label: 'Panel', weightController: _panel,
                                    rubrics: _getRubricOptions('panel'), rubricId: _panelRubricId, rubricName: _panelRubricName,
                                    onWeightChanged: (_) { setState(() {}); _markDirty(); },
                                    onRubricChanged: (value) {
                                      setState(() { _panelRubricId = value; _editedRubricRoles.add('panel'); });
                                      _markDirty();
                                    },),
                                  GradingRoleSetup(role: 'adviser', label: 'Adviser', weightController: _adviser,
                                    rubrics: _getRubricOptions('adviser'), rubricId: _adviserRubricId, rubricName: _adviserRubricName,
                                    onWeightChanged: (_) { setState(() {}); _markDirty(); },
                                    onRubricChanged: (value) {
                                      setState(() { _adviserRubricId = value; _editedRubricRoles.add('adviser'); });
                                      _markDirty();
                                    },),
                                  GradingRoleSetup(role: 'peer', label: 'Peer', weightController: _peer,
                                    rubrics: _getRubricOptions('peer'), rubricId: _peerRubricId, rubricName: _peerRubricName,
                                    onWeightChanged: (_) { setState(() {}); _markDirty(); },
                                    onRubricChanged: (value) {
                                      setState(() { _peerRubricId = value; _editedRubricRoles.add('peer'); });
                                      _markDirty();
                                    },),
                                ],
                              ),
                              Padding(padding: const EdgeInsets.symmetric(vertical: 24,),
                                child: Divider(height: 1, color: _borderColor),),
                              StageOutcomeSettings(scoreController: _qualifyingScore,
                                scoreCarryover: _scoreCarryover, conceptSelection: _conceptConfig['enabled'] == true,
                                enabled: !_saving && !_structureLocked,
                                onChanged: () { setState(() {}); _markDirty(); },
                                onCarryoverChanged: (v) { setState(() => _scoreCarryover = v); _markDirty(); },),
                            ],
                          ),

                          // TAB 2: Deliverables Split
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              StageDeliverablePresetsBar(
                                existingStages: ref.read(defenseStagesProvider).stages,
                                currentDeliverables: deliverablePresetItems(_deliverables, _sharedDeliverables,),
                                enabled: !_isLocked && !configuredItemsHaveData,
                                onApplyDeliverables: (newDeliverables) {
                                  setState(() {
                                    applyDeliverablePresetItems(newDeliverables, _deliverables, _sharedDeliverables,);
                                    _selectedDeliverable = _deliverables.isNotEmpty ? _deliverables.first : null;
                                    _error = null;
                                  });
                                  _markDirty();
                                },
                              ),
                              StageDeliverableCounts(
                                deliverables: deliverableSetupItems(_deliverables, _sharedDeliverables,),
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
                                onAdd: _isLocked
                                    ? () {}
                                    : () {
                                        setState(() {
                                          final item = <String, dynamic>{
                                            'deliverable_id': _nextDeliverableId(),
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
                                onAdd: _isLocked
                                    ? () {}
                                    : () {
                                        setState(() {
                                          final item = <String, dynamic>{
                                            'deliverable_id': _nextDeliverableId(),
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
                              ),
                              if (_minutesRequired == true) ...[
                                const SizedBox(height: 18),
                                StageMinutesDeliverableCard(
                                  number: _minutesNumber, name: _minutesName, stageName: _label.text, enabled: !_structureLocked,
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
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16,),
                      child: StageSetupActions(
                        children: [
                          TextButton(
                            onPressed: _saving ? null : _handleBack,
                            style: TextButton.styleFrom(
                              foregroundColor: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B),
                              textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13,),
                            ),
                            child: Text(_isLocked ? 'Back to Setup' : 'Cancel'),
                          ),
                          if (!_isLocked) ...[
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: (_saving || _savingDraft) ? null : _saveDraft,
                              icon: const Icon(Icons.save_outlined, size: 16),
                              label: Text(_savingDraft ? 'Saving draft…' : 'Save draft',),
                            ),
                          ],
                          const Spacer(),
                          if (_activeTab > 0) ...[
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() => _activeTab -= 1);
                              },
                              icon: const Icon(Icons.arrow_back_rounded, size: 15,),
                              label: const Text('Back'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _isDark ? DefensysTokens.mistTextPrimary : const Color(0xFF334155),
                                side: BorderSide(color: _borderColor),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10,),
                                textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13,),
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
                              icon: const Icon(Icons.arrow_forward_rounded, size: 15,),
                              label: Text(
                                _activeTab == 0 ? 'Next: Grading & Rubrics' : 'Next: Deliverables',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: _isDark ? DefensysTokens.maroon : AppColors.maroon,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10,),
                                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13,),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (!_isLocked)
                            DefensysSaveButton(
                              onPressed: ((!_structureLocked && hasWeightError) || _savingDraft) ? null : _save,
                              isSaving: _saving,
                              label: 'Save changes',
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8,),
                              decoration: BoxDecoration(
                                color: _inputFillColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _borderColor),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_outline, size: 16, color: _textSecondaryColor,),
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
            icon: Icons.inventory_2_rounded,
            badge: (deliverableCount > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1,),
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
                badge
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
        color: _textSecondaryColor
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
        borderSide: BorderSide(color: _isDark ? const Color(0xFFF87171) : AppColors.maroon, width: 1.5,),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _isDark ? const Color(0xFFF87171) : AppColors.maroon, width: 1.5,),
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
    required VoidCallback onAdd,
    required String emptyPlaceholderText,
    required List<Map<String, dynamic>> items,
    required bool isPost,
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
      key: ValueKey(
        isPost
            ? 'post-defense-deliverables-section'
            : 'pre-defense-deliverables-section',
      ),
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
              border: Border(bottom: BorderSide(color: effectiveBorder)),
            ),
            child: StageDeliverableSectionHeader(
              heading: Row(
                children: [
                  Icon(icon, size: 17, color: effectiveAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: effectiveAccent,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 1,
                              ),
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
                ],
              ),

              action: DefensysShadcnScope(
                child: ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: _isLocked ? null : onAdd,
                  leading: const Icon(Icons.add_rounded, size: 14),
                  child: const Text('Add deliverable'),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                items.isEmpty
                    ? InkWell(
                        onTap: _isLocked ? null : onAdd,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: _inputFillColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _borderColor),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isPost
                                    ? Icons.inventory_2_outlined
                                    : Icons.folder_open_rounded,
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
                        showGroupHeading: true,
                        showReviewHint: false,
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
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                              _deliverableRow(
                                item,
                                isPost,
                                index: index,
                                onDone: () =>
                                    setState(() => _selectedDeliverable = null),
                              ),
                            ],
                          );
                        },
                      ),
              ],
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

  Widget _deliverableRow(
    Map<String, dynamic> item,
    bool isPost, {
    required int index,
    VoidCallback? onDone,
  }) {
    final isLocked = _isLocked || item['is_locked'] == true || item['has_data'] == true;
    final labelController =
        item['_labelController'] as TextEditingController? ??
        (item['_labelController'] = TextEditingController(
          text: item['label']?.toString() ?? '',
        ));
    final templateController =
        item['_templateController'] as TextEditingController? ??
        (item['_templateController'] = TextEditingController(
          text: item['archive_file_template']?.toString() ?? '',
        ));

    const legacyDefault =
        '{year}.{course}.{project}.{stage}.{deliverable}.{semester}';
    if (!isLocked && templateController.text.trim() == legacyDefault) {
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
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
                  onPressed: isLocked
                      ? null
                      : () {
                          setState(() {
                            removeConfiguredDeliverable(
                              item,
                              _deliverables,
                              _sharedDeliverables,
                            );
                            (item['_labelController'] as TextEditingController?)
                                ?.dispose();
                            (item['_templateController']
                                    as TextEditingController?)
                                ?.dispose();
                          });
                          _markDirty();
                        },
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: isLocked ? Colors.grey : AppColors.danger,
                    size: 18,
                  ),
                  tooltip: 'Remove Deliverable #$index',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    hoverColor: AppColors.danger.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (isLocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Text(item['lock_reason']?.toString() ??
                  'This requirement is protected because it has submission history or grading has started.',
                  style: TextStyle(fontSize: 12, color: _textSecondaryColor),),
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
                              'label': label?.isNotEmpty == true
                                  ? label
                                  : 'Concept paper',
                              'file_format': format,
                              'required': req,
                            },
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
                      readOnly: isLocked,
                      decoration: _inputDecoration(
                        labelText: isPost
                            ? 'Post-Defense Deliverable Name *'
                            : 'Pre-Defense Requirement Name *',
                        hintText: isPost
                            ? 'e.g. Final Manuscript PDF, Source Code Zip'
                            : 'e.g. Manuscript Draft, Endorsement Form',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _textPrimaryColor,
                      ),
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
                        enabled: !isLocked,
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
                        enabled: !isLocked,
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

                    final isAdvancedExpanded =
                        item['_expandedAdvanced'] as bool? ?? false;

                    final moreOptionsBtn = DefensysShadcnScope(
                      child: ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: () {
                          setState(() {
                            item['_expandedAdvanced'] = !isAdvancedExpanded;
                          });
                        },
                        leading: Icon(
                          isAdvancedExpanded
                              ? Icons.expand_less_rounded
                              : Icons.tune_rounded,
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
                                children: [
                                  formatField,
                                  requiredField,
                                  moreOptionsBtn,
                                ],
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

                Builder(
                  builder: (context) {
                    final isAdvancedExpanded =
                        item['_expandedAdvanced'] as bool? ?? false;

                    if (!isAdvancedExpanded) return const SizedBox.shrink();

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
                              Icon(
                                Icons.tune_rounded,
                                size: 14,
                                color: _textSecondaryColor,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  isPost
                                      ? 'Post-defense options'
                                      : 'Pre-defense options',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _textPrimaryColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          DeliverableSubmissionPicker(
                            value: deliverableSubmissionAudience(item),
                            enabled: !isLocked,
                            onChanged: (value) {
                              setState(
                                () => setDeliverableSubmissionAudience(
                                  item,
                                  value,
                                  _deliverables,
                                  _sharedDeliverables,
                                ),
                              );
                              _markDirty();
                            },
                          ),
                          const SizedBox(height: 12),
                          Divider(
                            height: 1,
                            color: DefensysTokens.borderOf(context),
                          ),
                          const SizedBox(height: 8),
                          DocumentPolicyEditor(
                            value: Map<String, dynamic>.from(
                              item['file_policy'] as Map? ?? {},
                            ),
                            enabled: !isLocked,
                            allowConcepts:
                                (_conceptConfig['enabled'] == true) &&
                                (!isPost ||
                                    deliverableSubmissionAudience(item) ==
                                        'pm'),
                            deliverableLabel: labelController.text,
                            fileFormat: currentFormat,
                            required: item['required'] == true,
                            onChanged: (value) {
                              setState(() => item['file_policy'] = value);
                              _markDirty();
                            },
                          ),
                          const SizedBox(height: 12),
                          Divider(
                            height: 1,
                            color: DefensysTokens.borderOf(context),
                          ),
                          const SizedBox(height: 10),
                          if (!isPost) ...[
                            DefenseMaterialToggle(
                              value: item['is_defense_material'] == true,
                              enabled: !isLocked,
                              onChanged: (value) {
                                setState(
                                  () => item['is_defense_material'] = value,
                                );
                                _markDirty();
                              },
                            ),
                            const SizedBox(height: 8),
                            const DeliverableTimingFields(),
                          ],
                          if (isPost) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: DefensysShadcnScope(
                                    child: ShadCheckbox(
                                      value: item['is_restricted'] == true,
                                      enabled: !isLocked,
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
                                ),
                                const SizedBox(width: 4),
                                Tooltip(
                                  message:
                                      'Private for faculty and admin records only; hidden from students.',
                                  constraints: const BoxConstraints(
                                    maxWidth: 240,
                                  ),
                                  child: Icon(
                                    Icons.help_outline_rounded,
                                    size: 14,
                                    color: _textSecondaryColor,
                                  ),
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
                              isLocked: isLocked,
                              isPit: false,
                              stageOrEventLabel: _label.text,
                              siblingDeliverables:
                                  deliverableSetupItems(
                                        _deliverables,
                                        _sharedDeliverables,
                                      )
                                      .where(
                                        (d) =>
                                            d['deliverable_type'] ==
                                            (isPost ? 'post' : 'pre'),
                                      )
                                      .toList(),
                              currentIndex:
                                  deliverableSetupItems(
                                        _deliverables,
                                        _sharedDeliverables,
                                      )
                                      .where(
                                        (d) =>
                                            d['deliverable_type'] ==
                                            (isPost ? 'post' : 'pre'),
                                      )
                                      .toList()
                                      .indexOf(item),
                              onChanged: () {
                                item['archive_file_template'] =
                                    templateController.text.trim();
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
      child: Text(message, style: TextStyle(fontSize: 13, color: _textPrimaryColor),),
    );
  }

}
