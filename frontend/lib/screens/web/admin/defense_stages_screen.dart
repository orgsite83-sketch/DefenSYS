import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/defense_stages_provider.dart';
import '../../../theme/app_theme.dart';
import 'defense_stage_editor_screen.dart';
import 'widgets/defensys_admin_shell.dart';

class DefenseStagesScreen extends ConsumerStatefulWidget {
  const DefenseStagesScreen({super.key});

  @override
  ConsumerState<DefenseStagesScreen> createState() =>
      _DefenseStagesScreenState();
}

class _DefenseStagesScreenState extends ConsumerState<DefenseStagesScreen> {
  bool _stageEditorOpen = false;
  int? _editingStageId;
  Map<String, dynamic>? _editingStage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(defenseStagesProvider.notifier).fetchStages();
    });
  }

  void _openStageEditor(Map<String, dynamic> stage) {
    final stageId = _asInt(stage['id']);
    if (stageId == null) return;
    setState(() {
      _stageEditorOpen = true;
      _editingStageId = stageId;
      _editingStage = stage;
    });
  }

  void _closeStageEditor() {
    setState(() {
      _stageEditorOpen = false;
      _editingStageId = null;
      _editingStage = null;
    });
    ref.read(defenseStagesProvider.notifier).fetchStages();
  }

  @override
  Widget build(BuildContext context) {
    if (_stageEditorOpen && _editingStageId != null) {
      return DefenseStageEditorScreen(
        key: ValueKey(_editingStageId),
        stageId: _editingStageId!,
        initialStage: _editingStage,
        onBack: _closeStageEditor,
      );
    }

    final state = ref.watch(defenseStagesProvider);

    return RefreshIndicator(
      color: AppColors.maroon,
      onRefresh: () => ref.read(defenseStagesProvider.notifier).fetchStages(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(state),
            const SizedBox(height: 26),
            _buildLifecycleInfo(state),
            if (state.error != null) ...[
              const SizedBox(height: 14),
              _buildNotice(
                icon: Icons.error_outline,
                text: state.error!,
                color: AppColors.danger,
              ),
            ],
            if (state.message != null) ...[
              const SizedBox(height: 14),
              _buildNotice(
                icon: Icons.check_circle_outline,
                text: state.message!,
                color: AppColors.success,
              ),
            ],
            const SizedBox(height: 22),
            if (state.isLoading)
              _buildLoadingState()
            else
              _buildStageDirectory(state),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(DefenseStagesState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.layers_rounded, color: AppColors.maroon, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Defense Stages',
                    style: TextStyle(
                      color: AppColors.maroon,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                'Manage the master list of academic defense stages for future scheduler configuration.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              height: 42,
              child: OutlinedButton.icon(
                onPressed: state.isSaving
                    ? null
                    : () => ref
                          .read(defenseStagesProvider.notifier)
                          .fetchStages(),
                icon: const Icon(Icons.auto_awesome, size: 17),
                label: const Text('Defense Scheduler'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFD7DDE8)),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            SizedBox(
              height: 42,
              child: ElevatedButton.icon(
                onPressed: state.isSaving ? null : () => _showStageDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Stage'),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: AppColors.maroon,
                  foregroundColor: AppColors.gold,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLifecycleInfo(DefenseStagesState state) {
    final total = _count(state, 'total');
    final published = _count(state, 'active');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _softChip(
                'Total Stages: $total',
                const Color(0xFFF8FAFC),
                AppColors.textPrimary,
                const Color(0xFFD7DDE8),
              ),
              _softChip(
                'Published: $published',
                const Color(0xFFDDF5E8),
                const Color(0xFF047857),
                const Color(0xFFA7F3D0),
              ),
              _softChip(
                'Scheduler uses published stages',
                const Color(0xFFDCEAFE),
                const Color(0xFF1D4ED8),
                const Color(0xFFBFDBFE),
                chipMaxWidth: null,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Stages follow a Draft → Published → Locked lifecycle. Configure deliverables in Draft, then Publish to make a stage available in the scheduler. Once a defense is scheduled against a stage, it becomes Locked and read-only.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageDirectory(DefenseStagesState state) {
    if (state.stages.isEmpty) {
      return _buildEmptyState();
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Row(
              children: const [
                Expanded(
                  child: Text(
                    'Stage Directory',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  'Order by display order',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE6E8EF)),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 980) {
                return _buildStageCards(state);
              }

              return SizedBox(
                width: constraints.maxWidth,
                child: _buildStageTable(state),
              );
            },
          ),
        ],
      ),
    );
  }

  static const _tableLine = Color(0xFFE5E7EB);

  Widget _buildStageTable(DefenseStagesState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stageTableHeaderRow(),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _tableLine),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Column(
                children: [
                  for (var i = 0; i < state.stages.length; i++)
                    _stageTableDataRow(state, state.stages[i], i),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stageTableHeaderRow() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _tableLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _stageThFixed('ORDER', 64, maxLines: 1),
          Expanded(flex: 26, child: _stageTh('NAME')),
          Expanded(flex: 15, child: _stageTh('CODE')),
          Expanded(flex: 17, child: _stageTh('PREVIOUS STAGE')),
          _stageThFixed('DELIVERABLES', 118),
          _stageThFixed('STATUS', 128),
          _stageThFixed('ACTIONS', 184),
        ],
      ),
    );
  }

  Widget _stageTh(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _stageThFixed(String text, double width, {int maxLines = 2}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.45,
            height: 1.15,
          ),
        ),
      ),
    );
  }

  Widget _stageTableDataRow(
    DefenseStagesState state,
    Map<String, dynamic> stage,
    int index,
  ) {
    final zebra = index.isOdd;
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: BoxDecoration(
        color: zebra ? const Color(0xFFFAFAFA) : Colors.white,
        border: index > 0
            ? const Border(top: BorderSide(color: _tableLine))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _stageTdFixed(64, _orderTableBadge(stage['display_order'])),
          Expanded(
            flex: 26,
            child: _stageTd(_stageNameCell(stage)),
          ),
          Expanded(
            flex: 15,
            child: _stageTd(
              _codeTag(stage['code']?.toString() ?? ''),
            ),
          ),
          Expanded(
            flex: 17,
            child: _stageTd(_previousStageCell(stage)),
          ),
          _stageTdFixed(
            118,
            Text(
              '${_deliverablesCount(stage)} deliverables',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
          _stageTdFixed(128, _statusChip(stage)),
          _stageTdFixedActions(184, _buildStageActions(state, stage)),
        ],
      ),
    );
  }

  Widget _stageTd(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
  }

  Widget _stageTdFixed(double width, Widget child) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  /// Actions column: center the control cluster so Edit / Publish / Delete align with each other and the row.
  Widget _stageTdFixedActions(double width, Widget child) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Align(alignment: Alignment.center, child: child),
      ),
    );
  }

  Widget _orderTableBadge(dynamic value) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _tableLine),
      ),
      child: Text(
        value?.toString() ?? '',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildStageCards(DefenseStagesState state) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: state.stages.map((stage) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFCFCFE),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6E8EF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _orderTableBadge(stage['display_order']),
                    const SizedBox(width: 12),
                    Expanded(child: _stageNameCell(stage)),
                    _statusChip(stage),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _codeTag(stage['code']?.toString() ?? ''),
                    _softChip(
                      '${_deliverablesCount(stage)} deliverables',
                      const Color(0xFFF8FAFC),
                      AppColors.textPrimary,
                      const Color(0xFFD7DDE8),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _previousStageCell(stage),
                const SizedBox(height: 12),
                _buildStageActions(state, stage),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _stageNameCell(Map<String, dynamic> stage) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          stage['label']?.toString() ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          stage['description']?.toString() ?? 'Defense stage master entry.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            height: 1.25,
          ),
        ),
      ],
    );
  }

  Widget _previousStageCell(Map<String, dynamic> stage) {
    final previous = stage['previous_stage_label']?.toString();

    if (previous == null || previous.isEmpty) {
      return const Text(
        'Start stage',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          previous,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          stage['previous_stage_code']?.toString() ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }

  Widget _buildStageActions(
    DefenseStagesState state,
    Map<String, dynamic> stage,
  ) {
    final stageId = _asInt(stage['id']);
    final status = _stageStatus(stage);
    final locked = status == 'locked';
    final published = status == 'published';

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!locked)
          OutlinedButton.icon(
            onPressed: state.isSaving || stageId == null
                ? null
                : () => _openStageEditor(stage),
            icon: const Icon(Icons.edit_outlined, size: 15),
            label: const Text('Edit'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: Color(0xFFD7DDE8)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        if (locked)
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.lock, size: 14),
            label: const Text('Locked'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        else if (!published)
          OutlinedButton.icon(
            onPressed: state.isSaving || stageId == null
                ? null
                : () => ref
                      .read(defenseStagesProvider.notifier)
                      .updateStage(stageId, {
                        'label': stage['label'],
                        'display_order': stage['display_order'],
                        'description': stage['description'] ?? '',
                        'is_active': true,
                      }),
            icon: const Icon(Icons.send_rounded, size: 15),
            label: const Text('Publish'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF047857),
              side: const BorderSide(color: Color(0xFFA7F3D0)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        if (!locked)
          IconButton(
            tooltip: 'Delete stage',
            style: IconButton.styleFrom(
              foregroundColor: AppColors.danger,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: state.isSaving || stageId == null
                ? null
                : () => _confirmDelete(
                    stageId,
                    stage['label']?.toString() ?? 'stage',
                  ),
            icon: const Icon(Icons.delete_outline, size: 19),
          ),
      ],
    );
  }

  Future<void> _showStageDialog([Map<String, dynamic>? stage]) async {
    final editing = stage != null;
    final label = TextEditingController(
      text: stage?['label']?.toString() ?? '',
    );
    final description = TextEditingController(
      text: stage?['description']?.toString() ?? '',
    );
    final order = TextEditingController(
      text:
          stage?['display_order']?.toString() ??
          _nextDisplayOrder(ref.read(defenseStagesProvider)).toString(),
    );
    var isActive = stage?['is_active'] != false;
    
    // Get deliverables from stage
    List<Map<String, dynamic>> deliverables = [];
    if (stage != null && stage['deliverables'] != null) {
      final delivsList = stage['deliverables'];
      if (delivsList is List) {
        deliverables = delivsList
            .map((d) => Map<String, dynamic>.from(d as Map))
            .toList();
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(editing ? 'Edit Defense Stage' : 'Add Defense Stage'),
              content: SizedBox(
                width: 720,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: label,
                        decoration: const InputDecoration(
                          labelText: 'Stage Name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: order,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Display Order',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: description,
                        minLines: 2,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // Deliverables Section
                      Row(
                        children: [
                          const Icon(Icons.inventory_2, size: 18, color: AppColors.maroon),
                          const SizedBox(width: 8),
                          const Text(
                            'Deliverables',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: () {
                              setDialogState(() {
                                deliverables.add({
                                  'deliverable_id': 'D${deliverables.length + 1}',
                                  'label': '',
                                  'deliverable_type': 'pre',
                                  'required': true,
                                  'display_order': deliverables.length + 1,
                                  'vault_note': '',
                                });
                              });
                            },
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Deliverable'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F9FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBAE6FD)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Color(0xFF0369A1)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Pre-Defense items gate endorsement. Vault items unlock after defense is approved.',
                                style: TextStyle(
                                  color: Color(0xFF0369A1),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Deliverables List - removed height constraint, using shrinkWrap
                      deliverables.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: const Center(
                                child: Text(
                                  'No deliverables yet. Click "Add Deliverable" to create one.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                          : Column(
                              children: deliverables.asMap().entries.map((entry) {
                                return _buildDeliverableRow(
                                  entry.value,
                                  entry.key,
                                  deliverables,
                                  setDialogState,
                                );
                              }).toList(),
                            ),
                      
                      const SizedBox(height: 20),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Published stage'),
                        value: isActive,
                        onChanged: (value) {
                          setDialogState(() {
                            isActive = value;
                          });
                        },
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
                ElevatedButton.icon(
                  onPressed: label.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.save, size: 18),
                  label: Text(editing ? 'Save Changes' : 'Add Stage'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.maroon,
                    foregroundColor: AppColors.gold,
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || saved != true) {
      return;
    }

    final payload = {
      'label': label.text.trim(),
      'display_order':
          int.tryParse(order.text.trim()) ??
          _nextDisplayOrder(ref.read(defenseStagesProvider)),
      'description': description.text.trim(),
      'is_active': isActive,
      'deliverables': deliverables,
    };

    if (editing) {
      await ref
          .read(defenseStagesProvider.notifier)
          .updateStage(_asInt(stage['id'])!, payload);
    } else {
      await ref.read(defenseStagesProvider.notifier).addStage(payload);
    }

    label.dispose();
    description.dispose();
    order.dispose();
  }

  Widget _buildDeliverableRow(
    Map<String, dynamic> item,
    int index,
    List<Map<String, dynamic>> deliverables,
    void Function(void Function()) setDialogState,
  ) {
    final labelController = TextEditingController(text: item['label']?.toString() ?? '');
    
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
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
                  onChanged: (value) {
                    item['label'] = value;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    'deliverable_type_${index}_${item['deliverable_type']}',
                  ),
                  initialValue:
                      item['deliverable_type']?.toString() ?? 'pre',
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'pre', child: Text('Pre-Defense')),
                    DropdownMenuItem(value: 'vault', child: Text('Vault')),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      item['deliverable_type'] = value;
                      if (value == 'vault') {
                        item['required'] = false;
                      } else if (value == 'pre') {
                        item['required'] = true;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: item['required'] == true,
                      onChanged: (value) {
                        setDialogState(() {
                          item['required'] = value;
                        });
                      },
                    ),
                    const Flexible(
                      child: Text(
                        'Required',
                        style: TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                tooltip: 'Delete deliverable',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: () {
                  setDialogState(() {
                    deliverables.removeAt(index);
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(int stageId, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Defense Stage'),
        content: Text(
          'Delete $label? Future modules will no longer see it as a scheduler option.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    await ref.read(defenseStagesProvider.notifier).deleteStage(stageId);
  }

  Widget _codeTag(String code) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        code,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: 'monospace',
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _statusChip(Map<String, dynamic> stage) {
    final status = _stageStatus(stage);

    if (status == 'locked') {
      return _softChip(
        'Locked',
        const Color(0xFFDCEAFE),
        const Color(0xFF1D4ED8),
        const Color(0xFFBFDBFE),
        icon: Icons.lock,
      );
    }

    if (status == 'published') {
      return _softChip(
        'Published',
        const Color(0xFFDDF5E8),
        const Color(0xFF047857),
        const Color(0xFFA7F3D0),
        icon: Icons.check_circle,
      );
    }

    return _softChip(
      'Draft',
      const Color(0xFFFEF3C7),
      const Color(0xFFB45309),
      const Color(0xFFFDE68A),
      icon: Icons.auto_fix_high,
    );
  }

  Widget _softChip(
    String label,
    Color background,
    Color foreground,
    Color border, {
    IconData? icon,
    double? chipMaxWidth = 120,
  }) {
    return Container(
      constraints: chipMaxWidth != null
          ? BoxConstraints(maxWidth: chipMaxWidth)
          : const BoxConstraints(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      width: double.infinity,
      height: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EF)),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.maroon),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EF)),
      ),
      child: const Column(
        children: [
          Icon(Icons.layers_outlined, size: 44, color: AppColors.textSecondary),
          SizedBox(height: 10),
          Text(
            'No defense stages found',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Add a stage to build the scheduler stage chain.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  String _stageStatus(Map<String, dynamic> stage) {
    final rawStatus = stage['status']?.toString().toLowerCase();

    if (rawStatus == 'locked' || stage['is_locked'] == true) {
      return 'locked';
    }

    if (rawStatus == 'published' || stage['is_active'] == true) {
      return 'published';
    }

    return 'draft';
  }

  int _deliverablesCount(Map<String, dynamic> stage) {
    final possible = [
      stage['deliverables_count'],
      stage['deliverable_count'],
      stage['deliverables'],
    ];

    for (final value in possible) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }

    return 0;
  }

  int _nextDisplayOrder(DefenseStagesState state) {
    var maxOrder = 0;

    for (final stage in state.stages) {
      final order = _asInt(stage['display_order']) ?? 0;
      if (order > maxOrder) {
        maxOrder = order;
      }
    }

    return maxOrder + 1;
  }

  int _count(DefenseStagesState state, String key) {
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
