import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/academic_period_provider.dart';
import '../../../services/defense_stages_provider.dart';
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

  void _markDirty() {
    if (_loading || _isDirty) return;
    setState(() => _isDirty = true);
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
      final semester = detail['active_semester'];
      if (semester is Map) {
        _semesterId = _asInt(semester['id']);
      }
    }

    setState(() {
      _loading = false;
      _isDirty = false;
    });
  }

  void _applyStage(Map<String, dynamic> stage) {
    _stage = stage;
    _label.text = stage['label']?.toString() ?? '';
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

    setState(() {
      _saving = true;
      _error = null;
    });

    final stageOk = await ref.read(defenseStagesProvider.notifier).updateStage(
          widget.stageId,
          {
            'label': _label.text.trim(),
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

  void _resetWeights() {
    setState(() {
      _panel.text = '50';
      _adviser.text = '30';
      _peer.text = '20';
    });
  }

  @override
  Widget build(BuildContext context) {
    final semesters = _semesterOptions();
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
                  'Back to Defense Stages',
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
                          decoration: const InputDecoration(labelText: 'Stage name'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _order,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Display order'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _description,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(labelText: 'Description'),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Published stage'),
                          value: _isActive,
                          onChanged: (v) {
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
                          'How Panel, Adviser, and Peer scores combine for this stage. '
                          'Assign rubrics in Defense Scheduler. Defaults are 50 / 30 / 20.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (semesters.isNotEmpty)
                          DropdownButtonFormField<int>(
                            initialValue: _semesterId,
                            decoration: const InputDecoration(labelText: 'Semester'),
                            items: semesters
                                .map(
                                  (sem) => DropdownMenuItem<int>(
                                    value: _asInt(sem['id']),
                                    child: Text(
                                      sem['display_name']?.toString() ??
                                          sem['label']?.toString() ??
                                          'Semester ${sem['id']}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (value) async {
                                    setState(() => _semesterId = value);
                                    await _load();
                                  },
                          ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _panel,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Panel %'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _adviser,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Adviser %'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _peer,
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
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _resetWeights,
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
                      onPressed: () {
                        setState(() {
                          _deliverables.add({
                            'deliverable_id': 'D${_deliverables.length + 1}',
                            'label': '',
                            'deliverable_type': 'pre',
                            'required': true,
                            'display_order': _deliverables.length + 1,
                            'vault_note': '',
                            'vault_file_template': '',
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
                          'Pre-Defense items gate endorsement. Vault items unlock after defense is approved.',
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
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _saving || _weightTotal != 100 ? null : _save,
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

  Widget _deliverableRow(Map<String, dynamic> item, int index) {
    final labelController = item['_labelController'] as TextEditingController? ??
        (item['_labelController'] = TextEditingController(text: item['label']?.toString() ?? ''));
    final templateController = item['_templateController'] as TextEditingController? ??
        (item['_templateController'] = TextEditingController(text: item['vault_file_template']?.toString() ?? ''));

    final isVault = item['deliverable_type'] == 'vault';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'Label',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    item['label'] = v;
                    _markDirty();
                    if (isVault) {
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
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'pre', child: Text('Pre-Defense')),
                    DropdownMenuItem(value: 'vault', child: Text('Vault')),
                  ],
                  onChanged: (v) {
                    setState(() {
                      item['deliverable_type'] = v;
                      if (v == 'vault') {
                        item['required'] = false;
                      } else if (v == 'pre') {
                        item['required'] = true;
                      }
                    });
                    _markDirty();
                  },
                ),
              ),
              Checkbox(
                value: item['required'] == true,
                onChanged: (v) {
                  setState(() => item['required'] = v ?? false);
                  _markDirty();
                },
              ),
              const Text('Required', style: TextStyle(fontSize: 12)),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                onPressed: () {
                  setState(() {
                    final removed = _deliverables.removeAt(index);
                    (removed['_labelController'] as TextEditingController?)?.dispose();
                    (removed['_templateController'] as TextEditingController?)?.dispose();
                  });
                  _markDirty();
                },
              ),
            ],
          ),
          if (isVault) ...[
            const SizedBox(height: 12),
            TextField(
              controller: templateController,
              decoration: const InputDecoration(
                labelText: 'Vault File Template',
                isDense: true,
                border: OutlineInputBorder(),
                hintText: '{year}.{course}.{project}.{stage}.{deliverable}.{semester}',
              ),
              onChanged: (v) {
                setState(() {
                  item['vault_file_template'] = v;
                });
                _markDirty();
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Click to insert: ',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                _variableChip(item, templateController, '{year}'),
                _variableChip(item, templateController, '{course}'),
                _variableChip(item, templateController, '{project}'),
                _variableChip(item, templateController, '{stage}'),
                _variableChip(item, templateController, '{deliverable}'),
                _variableChip(item, templateController, '{semester}'),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Preview: ${_resolvePreview(item['vault_file_template']?.toString() ?? '', item['label']?.toString() ?? '')}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.maroon,
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
        ? '{year}.{course}.{project}.{semester}.pdf'
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

  Widget _variableChip(Map<String, dynamic> item, TextEditingController controller, String variable) {
    return InkWell(
      onTap: () => _insertVariable(item, controller, variable),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          variable,
          style: const TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
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
      item['vault_file_template'] = newText;
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
