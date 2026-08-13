import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/academic_period_provider.dart';
import '../../../services/defense_stages_provider.dart';
import '../../../services/rubric_engine_provider.dart';
import '../../../services/unsaved_changes_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/unsaved_changes.dart';
import 'widgets/defensys_admin_shell.dart';

class DefenseStageEditorScreen extends ConsumerStatefulWidget {
  final int stageId;
  final Map<String, dynamic>? initialStage;
  final VoidCallback onBack;

  const DefenseStageEditorScreen({
    super.key,
    required this.stageId,
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
  final _order = TextEditingController();
  final _panel = TextEditingController(text: '50');
  final _adviser = TextEditingController(text: '30');
  final _peer = TextEditingController(text: '20');

  bool _isActive = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int? _semesterId;
  List<Map<String, dynamic>> _deliverables = [];
  Map<String, dynamic>? _stage;
  bool _isDirty = false;

  int? _panelRubricId;
  String? _panelRubricName;
  int? _adviserRubricId;
  String? _adviserRubricName;
  int? _peerRubricId;
  String? _peerRubricName;

  void _markDirty() {
    if (_loading || _isDirty) return;
    setState(() => _isDirty = true);
    ref.read(unsavedChangesProvider.notifier).setDirty(true);
  }

  Future<void> _handleBack() async {
    await guardUnsavedExit(
      context,
      isDirty: _isDirty,
      onExit: widget.onBack,
    );
  }

  void _attachFieldListeners() {
    for (final controller in [
      _label,
      _code,
      _description,
      _order,
      _panel,
      _adviser,
      _peer,
    ]) {
      controller.removeListener(_markDirty);
      controller.addListener(_markDirty);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialStage != null) {
      _applyStage(widget.initialStage!);
    }
    _attachFieldListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _label.dispose();
    _code.dispose();
    _description.dispose();
    _order.dispose();
    _panel.dispose();
    _adviser.dispose();
    _peer.dispose();
    for (final item in _deliverables) {
      (item['_labelController'] as TextEditingController?)?.dispose();
      (item['_templateController'] as TextEditingController?)?.dispose();
    }
    super.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(unsavedChangesProvider.notifier).setDirty(false);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    await ref.read(academicPeriodProvider.notifier).fetchPeriods();
    final active = ref.read(academicPeriodProvider).activeSemester;
    _semesterId ??= _asInt(active?['id']);

    final detail = await ref
        .read(defenseStagesProvider.notifier)
        .fetchStageDetail(widget.stageId, semesterId: _semesterId);

    if (detail != null) {
      final semester = detail['active_semester'];
      if (semester is Map) {
        _semesterId = _asInt(semester['id']);
      }
    }

    // Load Capstone published rubrics
    await ref.read(rubricEngineProvider.notifier).fetchRubrics(
          scope: 'capstone',
          status: 'published',
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
    ref.read(unsavedChangesProvider.notifier).setDirty(false);
  }

  void _applyStage(Map<String, dynamic> stage) {
    _stage = stage;
    _label.text = stage['label']?.toString() ?? '';
    _code.text = stage['code']?.toString() ?? '';
    _description.text = stage['description']?.toString() ?? '';
    _order.text = stage['display_order']?.toString() ?? '1';
    _isActive = stage['is_active'] != false;
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

    // Validate deliverables labels
    for (int i = 0; i < _deliverables.length; i++) {
      final labelVal = _deliverables[i]['label']?.toString().trim() ?? '';
      if (labelVal.isEmpty) {
        setState(() => _error = 'Deliverable label cannot be empty (item ${i + 1}).');
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
            'display_order': int.tryParse(_order.text.trim()) ?? 1,
            'description': _description.text.trim(),
            'is_active': _isActive,
            'deliverables': _deliverables,
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
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_rounded, color: Color(0xFFD97706), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Defense Stage Locked (Read-Only)',
                  style: TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _lockReason ??
                      'This defense stage is locked because defenses have been scheduled or officially completed for this semester.',
                  style: const TextStyle(
                    color: Color(0xFFB45309),
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
    final total = _weightTotal;
    final stageTitle = _stage?['label']?.toString() ?? 'Edit Defense Stage';

    if (_loading) {
      return const ColoredBox(
        color: Color(0xFFF3F4F6),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.maroon),
        ),
      );
    }

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
              subtitle: 'Stage details, grade composition, and deliverables.',
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
                  _sectionCard(
                    title: 'Stage details',
                    icon: Icons.layers_rounded,
                    child: Column(
                      children: [
                        TextField(
                          controller: _label,
                          readOnly: _isLocked,
                          decoration: const InputDecoration(labelText: 'Stage name'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _code,
                          readOnly: _isLocked,
                          decoration: const InputDecoration(
                            labelText: 'Stage code',
                            helperText: 'Unique stage identifier'
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _order,
                          readOnly: _isLocked,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Stage order'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _description,
                          readOnly: _isLocked,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(labelText: 'Description'),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Published stage'),
                          value: _isActive,
                          onChanged: _isLocked
                              ? null
                              : (v) {
                                  setState(() => _isActive = v);
                                  _markDirty();
                                },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionCard(
                    title: 'Grade composition',
                    icon: Icons.balance_rounded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'How Panel, Adviser, and Peer scores combine for this stage, '
                          'and their assigned rubrics. Defaults are 50 / 30 / 20.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Semester',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  activeSemesterName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.maroon.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Active',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.maroon,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _panel,
                                readOnly: _isLocked,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Panel %'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _adviser,
                                readOnly: _isLocked,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Adviser %'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _peer,
                                readOnly: _isLocked,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Peer %'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Total: $total%${total == 100 ? '' : ' — must equal 100%'}',
                          style: TextStyle(
                            color: total == 100 ? AppColors.success : AppColors.danger,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F9FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBAE6FD)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Color(0xFF0284C7)),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Note: Assigning rubrics now is optional. You can leave them as "None" and attach published rubrics later before scheduling defenses.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF0369A1),
                                    fontWeight: FontWeight.w500,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<int>(
                          initialValue: _panelRubricId,
                          decoration: const InputDecoration(
                            labelText: 'Panel Rubric',
                            isDense: true,
                            border: OutlineInputBorder(),
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
                          decoration: const InputDecoration(
                            labelText: 'Adviser Rubric',
                            isDense: true,
                            border: OutlineInputBorder(),
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
                          decoration: const InputDecoration(
                            labelText: 'Peer Rubric',
                            isDense: true,
                            border: OutlineInputBorder(),
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
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _isLocked ? null : _resetWeights,
                          icon: const Icon(Icons.restore, size: 16),
                          label: const Text('Reset to 50 / 30 / 20'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionCard(
                    title: 'Deliverables',
                    icon: Icons.inventory_2_outlined,
                    trailing: OutlinedButton.icon(
                      onPressed: _isLocked
                          ? null
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
                                });
                              });
                              _markDirty();
                            },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add deliverable'),
                    ),
                    child: Column(
                      children: [
                        _notice(
                          'Pre-Defense items gate endorsement. Post-Defense items unlock after defense is officially complete.',
                        ),
                        const SizedBox(height: 12),
                        if (_deliverables.isEmpty)
                          const Text(
                            'No deliverables yet.',
                            style: TextStyle(color: AppColors.textSecondary),
                          )
                        else
                          ..._deliverables.asMap().entries.map(
                                (e) => _deliverableRow(e.value, e.key),
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _saving ? null : _handleBack,
                        child: Text(_isLocked ? 'Back' : 'Cancel'),
                      ),
                      const Spacer(),
                      if (!_isLocked)
                        FilledButton.icon(
                          onPressed: (_saving || _weightTotal != 100) ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.maroon,
                            foregroundColor: AppColors.gold,
                          ),
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save, size: 18),
                          label: Text(_saving ? 'Saving…' : 'Save changes'),
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
          ],
        ),
      ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: DefensysUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.maroon, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String labelText,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      hintStyle: const TextStyle(
        fontSize: 13,
        color: Colors.grey,
      ),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
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

  Widget _deliverableRow(Map<String, dynamic> item, int index) {
    final labelController = item['_labelController'] as TextEditingController? ??
        (item['_labelController'] = TextEditingController(text: item['label']?.toString() ?? ''));
    final templateController = item['_templateController'] as TextEditingController? ??
        (item['_templateController'] = TextEditingController(text: item['archive_file_template']?.toString() ?? ''));

    final isPost = item['deliverable_type'] == 'post';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: TextFormField(
                  controller: labelController,
                  readOnly: _isLocked,
                  decoration: _inputDecoration(
                    labelText: 'Name / Label',
                    hintText: 'e.g. Concept Paper PDF',
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (v) {
                    item['label'] = v.trim();
                    _markDirty();
                    if (isPost) {
                      setState(() {});
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: item['deliverable_type']?.toString() ?? 'pre',
                  decoration: _inputDecoration(labelText: 'Type'),
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  items: const [
                    DropdownMenuItem(value: 'pre', child: Text('Pre-Defense', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'post', child: Text('Post-Defense', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: _isLocked
                      ? null
                      : (v) {
                          if (v != null) {
                            setState(() {
                              item['deliverable_type'] = v;
                              if (v == 'post' || v == 'pre') {
                                item['required'] = true;
                              }
                            });
                            _markDirty();
                          }
                        },
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: item['required'] == true,
                      activeColor: AppColors.maroon,
                      onChanged: _isLocked
                          ? null
                          : (v) {
                              setState(() => item['required'] = v == true);
                              _markDirty();
                            },
                    ),
                    const Text(
                      'Required',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: _isLocked
                    ? null
                    : () {
                        setState(() {
                          final removed = _deliverables.removeAt(index);
                          (removed['_labelController'] as TextEditingController?)?.dispose();
                          (removed['_templateController'] as TextEditingController?)?.dispose();
                        });
                        _markDirty();
                      },
                icon: Icon(Icons.delete_outline_rounded, color: _isLocked ? Colors.grey : AppColors.danger),
                style: IconButton.styleFrom(
                  hoverColor: _isLocked ? Colors.grey.shade100 : AppColors.danger.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
          if (isPost) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: item['is_restricted'] == true,
                  activeColor: AppColors.maroon,
                  onChanged: _isLocked
                      ? null
                      : (v) {
                          setState(() {
                            item['is_restricted'] = v == true;
                          });
                          _markDirty();
                        },
                ),
                const Text(
                  'Restricted (Private in Archive)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: templateController,
                        readOnly: _isLocked,
                        decoration: _inputDecoration(
                          labelText: 'Archive Naming Template',
                          hintText: 'e.g. {year}.{course}.{project}.{stage}.{deliverable}.{semester}',
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (v) {
                          setState(() {
                            item['archive_file_template'] = v.trim();
                          });
                          _markDirty();
                        },
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Note: If left blank, the project title will be used as default.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: ['{year}', '{course}', '{project}', '{stage}', '{deliverable}', '{semester}']
                            .map((varName) => ActionChip(
                                  label: Text(
                                    varName,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  labelStyle: TextStyle(color: _isLocked ? Colors.grey : AppColors.maroon),
                                  backgroundColor: AppColors.maroon.withValues(alpha: 0.05),
                                  side: BorderSide(color: AppColors.maroon.withValues(alpha: 0.15)),
                                  padding: EdgeInsets.zero,
                                  onPressed: _isLocked
                                      ? null
                                      : () => _insertVariable(item, templateController, varName),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.maroon.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.maroon.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.remove_red_eye_outlined, size: 14, color: AppColors.maroon),
                            const SizedBox(width: 6),
                            const Text(
                              'Filename Preview',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.maroon,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          _resolvePreview(item['archive_file_template']?.toString() ?? '', item['label']?.toString() ?? ''),
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: AppColors.maroon,
                          ),
                        ),
                      ],
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

  String _resolvePreview(String template, String deliverableLabel) {
    final cleanTemplate = template.trim();
    final finalTemplate = cleanTemplate.isEmpty 
        ? '{project}.pdf'
        : cleanTemplate;

    String slugify(String val) {
      return val.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    }

    String deliverableSlug(String val) {
      if (val.trim().isEmpty) return 'DeliverableLabel';
      final words = val.trim().split(RegExp(r'\s+'));
      final capitalized = words.map((w) {
        if (w.isEmpty) return '';
        return w[0].toUpperCase() + w.substring(1).toLowerCase();
      }).join('');
      return slugify(capitalized);
    }

    final year = '3rdYear';
    final course = 'CAP301';
    final project = 'ProjectTitle';
    final stage = slugify(_label.text.trim().isEmpty ? 'StageLabel' : _label.text.trim());
    final deliverable = deliverableSlug(deliverableLabel);
    final semester = '2ndSemester';

    var resolved = finalTemplate
        .replaceAll('{year}', year)
        .replaceAll('{course}', course)
        .replaceAll('{project}', project)
        .replaceAll('{stage}', stage)
        .replaceAll('{deliverable}', deliverable)
        .replaceAll('{semester}', semester);

    if (!resolved.toLowerCase().endsWith('.pdf')) {
      resolved += '.pdf';
    }

    return resolved;
  }


  void _insertVariable(Map<String, dynamic> item, TextEditingController controller, String variable) {
    final text = controller.text;
    final selection = controller.selection;
    
    String newText;
    int newCursorPosition;

    if (selection.isValid) {
      final start = selection.start;
      final end = selection.end;
      newText = text.replaceRange(start, end, variable);
      newCursorPosition = start + variable.length;
    } else {
      newText = text + variable;
      newCursorPosition = newText.length;
    }

    setState(() {
      controller.text = newText;
      controller.selection = TextSelection.collapsed(offset: newCursorPosition);
      item['archive_file_template'] = newText;
    });
    _markDirty();
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
