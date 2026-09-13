import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/academic_period_provider.dart';
import '../../../../services/defense_stages_provider.dart';
import '../../../../services/rubric_engine_provider.dart';
import '../../../../services/unsaved_changes_provider.dart';
import '../../../../theme/app_theme.dart';
import '../../../../utils/unsaved_changes.dart';
import '../../../../widgets/widgets.dart';
import '../../../../widgets/repository/repository_archive_naming_panel.dart';
import 'widgets/pipeline_position_selector.dart';
import 'widgets/endorsed_stage_resolution_dialog.dart';
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
  final _panel = TextEditingController(text: '50');
  final _adviser = TextEditingController(text: '30');
  final _peer = TextEditingController(text: '20');

  int _orderPosition = 1;
  late int _activeTab;
  bool _isActive = true;
  bool _isPresentationOnly = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int? _semesterId;
  List<Map<String, dynamic>> _deliverables = [];
  Map<String, dynamic>? _stage;
  bool _isDirty = false;
  UnsavedChangesNotifier? _unsavedNotifier;

  int? _panelRubricId;
  String? _panelRubricName;
  int? _adviserRubricId;
  String? _adviserRubricName;
  int? _peerRubricId;
  String? _peerRubricName;

  void _markDirty() {
    if (_loading || _isDirty) return;
    setState(() => _isDirty = true);
    _unsavedNotifier?.setDirty(true);
  }

  void _clearDirty() {
    if (mounted) {
      setState(() => _isDirty = false);
    }
    _unsavedNotifier?.setDirty(false);
  }

  Future<void> _handleBack() async {
    await guardUnsavedExit(
      context,
      isDirty: _isDirty,
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
    _activeTab = widget.initialTab.clamp(0, 2);
    if (widget.initialStage != null) {
      _applyStage(widget.initialStage!);
    }
    _attachFieldListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _detachFieldListeners();
    _label.dispose();
    _code.dispose();
    _description.dispose();
    _panel.dispose();
    _adviser.dispose();
    _peer.dispose();
    for (final item in _deliverables) {
      (item['_labelController'] as TextEditingController?)?.dispose();
      (item['_templateController'] as TextEditingController?)?.dispose();
    }
    _unsavedNotifier?.setDirty(false);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

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
      }
    }

    setState(() {
      _loading = false;
      _isDirty = false;
    });
    _unsavedNotifier?.setDirty(false);
  }

  void _applyStage(Map<String, dynamic> stage) {
    _stage = stage;
    _label.text = stage['label']?.toString() ?? '';
    _code.text = stage['code']?.toString() ?? '';
    _description.text = stage['description']?.toString() ?? '';
    _orderPosition = _asInt(stage['display_order']) ?? 1;
    _isActive = stage['is_active'] != false;
    _isPresentationOnly = stage['is_presentation_only'] == true;
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
    _panelRubricId = _asInt(grading['panel_rubric_id']);
    _panelRubricName = grading['panel_rubric_name']?.toString();
    _adviserRubricId = _asInt(grading['adviser_rubric_id']);
    _adviserRubricName = grading['adviser_rubric_name']?.toString();
    _peerRubricId = _asInt(grading['peer_rubric_id']);
    _peerRubricName = grading['peer_rubric_name']?.toString();
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

  Future<void> _save() async {
    if (_isLocked) return;
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
          setState(() => _error = 'Deliverable label cannot be empty (item ${i + 1}).');
          return;
        }
        if (d['deliverable_type'] == 'post') {
          final tpl = (d['archive_file_template'] ?? '').toString().trim();
          final count = RegExp(r'\{[a-zA-Z0-9_]+\}').allMatches(tpl).length;
          if (count > 3) {
            setState(() => _error = 'Template for "$labelVal" exceeds the limit of 3 variables ($count used). Phone file names have character limits.');
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
            'deliverables': _isPresentationOnly ? [] : _deliverables,
            if (endorsedAction != null) 'endorsed_teams_action': endorsedAction,
          },
        );

    final weightsOk = await ref
        .read(defenseStagesProvider.notifier)
        .updateGradingConfig(widget.stageId, _semesterId!, {
          'panel_weight': int.tryParse(_panel.text.trim()) ?? 0,
          'adviser_weight': int.tryParse(_adviser.text.trim()) ?? 0,
          'peer_weight': int.tryParse(_peer.text.trim()) ?? 0,
          'panel_rubric_id': _panelRubricId,
          'adviser_rubric_id': _adviserRubricId,
          'peer_rubric_id': _peerRubricId,
        });

    if (!mounted) return;

    setState(() => _saving = false);

    if (stageOk && weightsOk) {
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
      return scopeMatch && semMatch && evalMatch && publishedMatch;
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
      final assignedStageId = _asInt(r['defense_stage_id']);
      final assignedStageLabel = r['defense_stage_label']?.toString();
      final isAssignedToOther = assignedStageId != null && assignedStageId != widget.stageId;

      if (isAssignedToOther) {
        return DropdownMenuItem<int>(
          value: id,
          enabled: false,
          child: Text(
            '${r['name']} (Assigned to: ${assignedStageLabel ?? "Another Stage"})',
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      }

      return DropdownMenuItem<int>(
        value: id,
        child: Text(r['name']?.toString() ?? ''),
      );
    }).toList();

    // If currentId is set but not in options, add fallback item
    if (currentId != null && !items.any((item) => item.value == currentId)) {
      items.add(DropdownMenuItem<int>(
        value: currentId,
        child: Text(currentName ?? 'Rubric #$currentId'),
      ));
    }

    // Always allow unselecting
    items.insert(
      0,
      const DropdownMenuItem<int>(
        value: null,
        child: Text('None (No Rubric)'),
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
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.task_alt_rounded, color: Color(0xFF1D4ED8), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Defense Stage Completed (Read-Only)',
                  style: TextStyle(
                    color: Color(0xFF1E40AF),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _lockReason ??
                      'This defense stage is completed and preserved because defenses have been scheduled or officially completed for this semester.',
                  style: const TextStyle(
                    color: Color(0xFF1D4ED8),
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
      return const ColoredBox(
        color: Color(0xFFF3F4F6),
        child: Center(
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
        color: const Color(0xFFF3F4F6),
        child: SingleChildScrollView(
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
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    size: 16,
                    color: DefensysUi.primaryMaroon,
                  ),
                  label: const Text(
                    'Back to Defense Stages Setup',
                    style: TextStyle(
                      fontFamily: DefensysUi.fontFamily,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: DefensysUi.primaryMaroon,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DefensysUi.primaryMaroon,
                    side: const BorderSide(color: DefensysUi.primaryMaroon),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_isLocked) _buildLockedBanner(),
              if (_error != null) ...[
                _notice(_error!, warning: true),
                const SizedBox(height: 14),
              ],

              // Main Tabbed Editor Card
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
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
                        deliverableCount: _deliverables.length,
                        isPresentationOnly: _isPresentationOnly,
                        onTabSelected: (tab) => setState(() => _activeTab = tab),
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),

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
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: _buildPositionSelector(),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _description,
                                readOnly: _isLocked,
                                minLines: 2,
                                maxLines: 4,
                                decoration: _inputDecoration(
                                  labelText: 'Stage Description (Optional)',
                                  hintText: 'Provide brief guidance or objectives for this defense milestone...',
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'Published Stage',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'When active, this stage is part of the live capstone defense sequence.',
                                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.pie_chart_outline_rounded, size: 18, color: AppColors.maroon),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Role Weight Distribution',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFFE2E8F0)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF475569)),
                                              const SizedBox(width: 5),
                                              Text(
                                                activeSemesterName,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF475569),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'How Panel, Adviser, and Peer scores combine for this defense milestone. Defaults are 50 / 30 / 20.',
                                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
                                            decoration: _inputDecoration(
                                              labelText: 'Panel %',
                                              hintText: '50',
                                              prefixIcon: const Icon(Icons.gavel_rounded, size: 16, color: AppColors.maroon),
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
                                          foregroundColor: const Color(0xFF475569),
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
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.assignment_outlined, size: 18, color: AppColors.maroon),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Evaluation Rubrics Attachment',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const Spacer(),
                                            OutlinedButton.icon(
                                              onPressed: () => context.push(AdminRoutes.rubrics),
                                              icon: const Icon(Icons.open_in_new_rounded, size: 14),
                                              label: const Text('Manage Evaluation Rubrics'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: AppColors.maroon,
                                                side: const BorderSide(color: Color(0xFFCBD5E1)),
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
                                        const Text(
                                          'Assign published Capstone rubrics to evaluate each role (optional; can attach later before defense scheduling).',
                                          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                                        ),
                                        if (hasNoRubricsAtAll) ...[
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFFBEB),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFFFDE68A)),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFB45309)),
                                                const SizedBox(width: 10),
                                                const Expanded(
                                                  child: Text(
                                                    'No published Capstone rubrics found for this semester. Create and publish rubrics in Evaluation Rubrics so they can be attached here.',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Color(0xFF92400E),
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                ElevatedButton.icon(
                                                  onPressed: () => context.push(AdminRoutes.rubrics),
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
                                          initialValue: _panelRubricId,
                                          decoration: _inputDecoration(
                                            labelText: 'Panel Rubric',
                                            prefixIcon: const Icon(Icons.gavel_rounded, size: 16, color: AppColors.maroon),
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
                                                  });
                                                  _markDirty();
                                                },
                                        ),
                                        const SizedBox(height: 14),
                                        DropdownButtonFormField<int>(
                                          initialValue: _adviserRubricId,
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
                                                  });
                                                  _markDirty();
                                                },
                                        ),
                                        const SizedBox(height: 14),
                                        DropdownButtonFormField<int>(
                                          initialValue: _peerRubricId,
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
                                                  });
                                                  _markDirty();
                                                },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
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
                                _buildDeliverableSection(
                                  title: 'Pre-Defense Gatekeepers',
                                  subtitle: 'Submissions required before adviser endorsement and defense scheduling.',
                                  icon: Icons.folder_open_rounded,
                                  accentColor: const Color(0xFF2563EB),
                                  bgHeaderColor: const Color(0xFFEFF6FF),
                                  borderColor: const Color(0xFFBFDBFE),
                                  count: preDeliverables.length,
                                  buttonText: 'Add Pre-Defense',
                                  onAdd: _isLocked
                                      ? () {}
                                      : () {
                                          setState(() {
                                            _deliverables.add({
                                              'deliverable_id': 'D${_deliverables.length + 1}',
                                              'label': '',
                                              'deliverable_type': 'pre',
                                              'required': true,
                                              'display_order': _deliverables.length + 1,
                                              'archive_note': '',
                                              'archive_file_template': '',
                                              'is_restricted': false,
                                              'is_defense_material': false,
                                              'verdict_condition': 'all_pass',
                                              'file_format': 'any',
                                            });
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
                                  accentColor: AppColors.maroon,
                                  bgHeaderColor: const Color(0xFFFFF1F2),
                                  borderColor: const Color(0xFFFECDD3),
                                  count: postDeliverables.length,
                                  buttonText: 'Add Post-Defense',
                                  onAdd: _isLocked
                                      ? () {}
                                      : () {
                                          setState(() {
                                            _deliverables.add({
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
                                            });
                                          });
                                          _markDirty();
                                        },
                                  emptyPlaceholderText: 'No post-defense deliverables configured yet. (e.g. Final Manuscript PDF, Source Code Zip, Demo Video)',
                                  items: postDeliverables,
                                  isPost: true,
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
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: _saving ? null : _handleBack,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF64748B),
                              textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            child: Text(_isLocked ? 'Back to Setup' : 'Cancel'),
                          ),
                          const Spacer(),
                          if (_activeTab > 0) ...[
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() => _activeTab -= 1);
                              },
                              icon: const Icon(Icons.arrow_back_rounded, size: 15),
                              label: const Text('Back'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF334155),
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
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
                                backgroundColor: AppColors.maroon,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (!_isLocked)
                            DefensysSaveButton(
                              onPressed: hasWeightError ? null : _save,
                              isSaving: _saving,
                              label: 'Save changes',
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_outline, size: 16, color: Color(0xFF64748B)),
                                  SizedBox(width: 6),
                                  Text(
                                    'Read-Only Mode',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
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
        color: const Color(0xFFF1F5F9),
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
            badge: isPresentationOnly
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: activeTab == 2
                          ? Colors.white.withValues(alpha: 0.25)
                          : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: activeTab == 2 ? Colors.white.withValues(alpha: 0.4) : const Color(0xFFBFDBFE),
                      ),
                    ),
                    child: Text(
                      'Oral / Demo',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: activeTab == 2 ? Colors.white : const Color(0xFF1D4ED8),
                      ),
                    ),
                  )
                : (deliverableCount > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: activeTab == 2
                              ? Colors.white.withValues(alpha: 0.25)
                              : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$deliverableCount',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: activeTab == 2 ? Colors.white : AppColors.textPrimary,
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
                color: isSelected ? Colors.white : const Color(0xFF64748B),
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
                    color: isSelected ? Colors.white : const Color(0xFF334155),
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
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      hintStyle: const TextStyle(
        fontSize: 12.5,
        color: Color(0xFF94A3B8),
      ),
      helperStyle: const TextStyle(
        fontSize: 11,
        color: Color(0xFF64748B),
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.maroon, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.maroon, width: 1.5),
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
        color: isValid ? const Color(0xFFF8FAFC) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isValid ? const Color(0xFFE2E8F0) : const Color(0xFFFECACA),
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
                    color: isValid ? const Color(0xFF059669) : AppColors.danger,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isValid ? 'Balanced Allocation (100%)' : 'Allocation Error: Must Total 100%',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isValid ? const Color(0xFF059669) : AppColors.danger,
                    ),
                  ),
                ],
              ),
              Text(
                'Total: $total%',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: isValid ? const Color(0xFF059669) : AppColors.danger,
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
              color: const Color(0xFFE2E8F0),
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
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textPrimary,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
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
              const Icon(Icons.tune_rounded, size: 18, color: AppColors.maroon),
              const SizedBox(width: 8),
              const Text(
                'Stage Submission Mode',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _submissionModeCard(
                  title: 'Document Submissions Required',
                  description:
                      'Standard defense milestone. Requires student files for endorsement and archiving.',
                  icon: Icons.description_rounded,
                  selected: !_isPresentationOnly,
                  onTap: _isLocked
                      ? null
                      : () {
                          if (_isPresentationOnly) {
                            setState(() => _isPresentationOnly = false);
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
                      'Oral defense, pitch, or expo only — no student file uploads required.',
                  icon: Icons.co_present_rounded,
                  selected: _isPresentationOnly,
                  onTap: _isLocked
                      ? null
                      : () {
                          if (!_isPresentationOnly) {
                            setState(() => _isPresentationOnly = true);
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? (title.contains('Presentation')
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFFAF5FF))
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? (title.contains('Presentation')
                    ? const Color(0xFF22C55E)
                    : AppColors.maroon)
                : const Color(0xFFE2E8F0),
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
                  ? (title.contains('Presentation')
                      ? const Color(0xFF16A34A)
                      : AppColors.maroon)
                  : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 15, color: AppColors.textPrimary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
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
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Color(0xFF15803D),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Presentation / Demo Mode Active',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF14532D),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'This milestone does not require document submissions.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF166534),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '• Students will not be prompted to upload manuscripts or archive files for this stage.\n'
            '• Advisers can endorse teams directly based on verbal presentation or demo readiness.\n'
            '• Administrators can schedule defenses freely once endorsed.',
            style: TextStyle(
              fontSize: 12.5,
              color: Color(0xFF166534),
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
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bgHeaderColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: accentColor),
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
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count item${count == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: accentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isLocked)
                  OutlinedButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 14),
                    label: Text(buttonText),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: items.isEmpty
                ? InkWell(
                    onTap: _isLocked ? null : onAdd,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isPost ? Icons.inventory_2_outlined : Icons.folder_open_rounded,
                            size: 16,
                            color: const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              emptyPlaceholderText,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: items
                        .asMap()
                        .entries
                        .map((entry) => _deliverableRow(entry.value, isPost, index: entry.key + 1))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _deliverableRow(Map<String, dynamic> item, bool isPost, {required int index}) {
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

    final accentColor = isPost ? AppColors.maroon : const Color(0xFF2563EB);
    final currentFormat = (item['file_format']?.toString().isNotEmpty == true)
        ? item['file_format'].toString()
        : 'any';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Distinct Item Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(9),
                topRight: Radius.circular(9),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    '#$index',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    labelController.text.trim().isNotEmpty
                        ? 'Deliverable #$index • ${labelController.text.trim()}'
                        : 'Deliverable #$index',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
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
                // Primary Row: Name Input + Format Dropdown + Required Checkbox
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: labelController,
                        readOnly: _isLocked,
                        decoration: _inputDecoration(
                          labelText: isPost ? 'Post-Defense Deliverable Name *' : 'Pre-Defense Requirement Name *',
                          hintText: isPost
                              ? 'e.g. Final Manuscript PDF, Source Code Zip'
                              : 'e.g. Manuscript Draft, Endorsement Form',
                        ),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        onChanged: (v) {
                          item['label'] = v.trim();
                          _markDirty();
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: currentFormat,
                          isDense: true,
                          borderRadius: BorderRadius.circular(8),
                          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                          items: _deliverableFormatDropdownItems(),
                          onChanged: _isLocked
                              ? null
                              : (val) {
                                  setState(() {
                                    item['file_format'] = val ?? 'any';
                                  });
                                  _markDirty();
                                },
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: item['required'] == true,
                            activeColor: accentColor,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onChanged: _isLocked
                                ? null
                                : (v) {
                                    setState(() => item['required'] = v == true);
                                    _markDirty();
                                  },
                          ),
                          const SizedBox(width: 2),
                          const Text(
                            'Required',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!isPost) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: item['is_defense_material'] == true,
                        activeColor: const Color(0xFF2563EB),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: _isLocked
                            ? null
                            : (v) {
                                setState(() {
                                  item['is_defense_material'] = v == true;
                                });
                                _markDirty();
                              },
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Defense Material (Visible to Defense Panelists)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Tooltip(
                        message: 'Evaluated by defense panelists (uncheck for administrative forms).',
                        constraints: BoxConstraints(maxWidth: 240),
                        child: Icon(Icons.help_outline_rounded, size: 14, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
                if (isPost) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: item['is_restricted'] == true,
                        activeColor: AppColors.maroon,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: _isLocked
                            ? null
                            : (v) {
                                setState(() {
                                  item['is_restricted'] = v == true;
                                });
                                _markDirty();
                              },
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Restricted (Private Institutional Archive)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Tooltip(
                        message: 'Private for faculty and admin records only; hidden from students.',
                        constraints: BoxConstraints(maxWidth: 240),
                        child: Icon(Icons.help_outline_rounded, size: 14, color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      const Icon(Icons.rule_rounded, size: 15, color: AppColors.maroon),
                      const SizedBox(width: 6),
                      const Text(
                        'Submission Rule:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: item['verdict_condition']?.toString() == 'revisions_only' ? 'revisions_only' : 'all_pass',
                            isDense: true,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            items: const [
                              DropdownMenuItem(
                                value: 'all_pass',
                                child: Text('Required for All Passing Teams'),
                              ),
                              DropdownMenuItem(
                                value: 'revisions_only',
                                child: Text('Only for Approved with Revisions'),
                              ),
                            ],
                            onChanged: _isLocked
                                ? null
                                : (val) {
                                    setState(() {
                                      item['verdict_condition'] = val ?? 'all_pass';
                                    });
                                    _markDirty();
                                  },
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Tooltip(
                        message:
                            '• All Passing: Required for all teams that pass the defense (e.g., Final Manuscript).\n'
                            '• Revisions Only: Only required if the team passed with revisions (e.g., Revision Matrix).',
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        textStyle: TextStyle(fontSize: 12, color: Colors.white, height: 1.35),
                        constraints: BoxConstraints(maxWidth: 320),
                        child: Icon(Icons.help_outline_rounded, size: 14, color: AppColors.textSecondary),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  // Smart Enterprise Repository Archiving Panel
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
          ),
        ],
      ),
    );
  }

  List<DropdownMenuItem<String>> _deliverableFormatDropdownItems() {
    return const [
      DropdownMenuItem(
        value: 'any',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.all_inclusive, size: 14, color: Colors.blueGrey),
            SizedBox(width: 6),
            Text('Any File Type'),
          ],
        ),
      ),
      DropdownMenuItem(
        value: 'pdf',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_outlined, size: 14, color: Color(0xFFEF4444)),
            SizedBox(width: 6),
            Text('PDF Document (.pdf)'),
          ],
        ),
      ),
      DropdownMenuItem(
        value: 'video',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library_outlined, size: 14, color: Color(0xFF8B5CF6)),
            SizedBox(width: 6),
            Text('Video (.mp4, .mov)'),
          ],
        ),
      ),
      DropdownMenuItem(
        value: 'image',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, size: 14, color: Color(0xFF06B6D4)),
            SizedBox(width: 6),
            Text('Image / Poster (.png, .jpg)'),
          ],
        ),
      ),
      DropdownMenuItem(
        value: 'presentation',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.slideshow_outlined, size: 14, color: Color(0xFFEA580C)),
            SizedBox(width: 6),
            Text('Slides (.pptx, .ppt)'),
          ],
        ),
      ),
      DropdownMenuItem(
        value: 'document',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 14, color: Color(0xFF2563EB)),
            SizedBox(width: 6),
            Text('Word / Doc (.docx, .doc)'),
          ],
        ),
      ),
      DropdownMenuItem(
        value: 'spreadsheet',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_chart_outlined, size: 14, color: Color(0xFF10B981)),
            SizedBox(width: 6),
            Text('Spreadsheet (.xlsx, .csv)'),
          ],
        ),
      ),
      DropdownMenuItem(
        value: 'archive',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_zip_outlined, size: 14, color: Color(0xFF64748B)),
            SizedBox(width: 6),
            Text('Archive (.zip, .rar)'),
          ],
        ),
      ),
      DropdownMenuItem(
        value: 'audio',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.audiotrack_outlined, size: 14, color: Color(0xFFF43F5E)),
            SizedBox(width: 6),
            Text('Audio (.mp3, .wav)'),
          ],
        ),
      ),
    ];
  }

  Widget _notice(String message, {bool warning = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFFBEB) : const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: warning ? const Color(0xFFF59E0B) : const Color(0xFFBAE6FD),
        ),
      ),
      child: Text(message, style: const TextStyle(fontSize: 13)),
    );
  }

}
