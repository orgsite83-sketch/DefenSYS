import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../navigation/admin_route_paths.dart';
import '../../../services/defense_stages_provider.dart';
import '../../../services/academic_period_provider.dart';
import '../../../services/rubric_engine_provider.dart';
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
    if (GoRouterState.of(context).uri.path == AdminRoutes.defenseStages) {
      context.push(AdminRoutes.defenseStageEdit(stageId));
      return;
    }
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
    ref.listen<DefenseStagesState>(
      defenseStagesProvider,
      (previous, next) {
        if (next.error != null && next.error != previous?.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.error!),
              backgroundColor: AppColors.danger,
            ),
          );
        }
        if (next.message != null && next.message != previous?.message) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.message!),
              backgroundColor: AppColors.success,
            ),
          );
        }
      },
    );

    final onAdminList =
        GoRouterState.of(context).uri.path == AdminRoutes.defenseStages;

    if (!onAdminList && _stageEditorOpen && _editingStageId != null) {
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

    // Fetch periods for grade composition weights
    await ref.read(academicPeriodProvider.notifier).fetchPeriods();
    // Fetch capstone published rubrics
    await ref.read(rubricEngineProvider.notifier).fetchRubrics(
          scope: 'capstone',
          status: 'published',
        );

    final semesters = <Map<String, dynamic>>[];
    for (final year in ref.read(academicPeriodProvider).schoolYears) {
      final sems = year['semesters'];
      if (sems is! List) continue;
      for (final sem in sems) {
        if (sem is Map) {
          semesters.add(Map<String, dynamic>.from(sem));
        }
      }
    }

    final label = TextEditingController(
      text: stage?['label']?.toString() ?? '',
    );
    final description = TextEditingController(
      text: stage?['description']?.toString() ?? '',
    );
    final order = TextEditingController(
      text: stage?['display_order']?.toString() ??
          _nextDisplayOrder(ref.read(defenseStagesProvider)).toString(),
    );
    final panelCtrl = TextEditingController(text: '50');
    final adviserCtrl = TextEditingController(text: '30');
    final peerCtrl = TextEditingController(text: '20');
    var isActive = stage?['is_active'] != false;

    int? panelRubricId;
    int? adviserRubricId;
    int? peerRubricId;

    final activePeriod = ref.read(academicPeriodProvider).activeSemester;
    int? semesterId = activePeriod != null ? _asInt(activePeriod['id']) : null;
    if (semesterId == null && semesters.isNotEmpty) {
      semesterId = _asInt(semesters.first['id']);
    }

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

    if (!mounted) return;
    bool? saved;
    try {
      saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final total = (int.tryParse(panelCtrl.text.trim()) ?? 0) +
                  (int.tryParse(adviserCtrl.text.trim()) ?? 0) +
                  (int.tryParse(peerCtrl.text.trim()) ?? 0);

              List<Map<String, dynamic>> getRubricOptions(String evaluationType) {
                final rubrics = ref.watch(rubricEngineProvider).rubrics;
                return rubrics.where((r) {
                  final scopeMatch = r['scope'] == 'capstone';
                  final semMatch = _asInt(r['semester_id']) == semesterId;
                  final evalMatch = r['evaluation_type'] == evaluationType;
                  final publishedMatch = r['status'] == 'published';
                  return scopeMatch && semMatch && evalMatch && publishedMatch;
                }).toList();
              }

              List<DropdownMenuItem<int>> buildRubricDropdownItems(String evaluationType) {
                final options = getRubricOptions(evaluationType);
                final items = options.map((r) {
                  return DropdownMenuItem<int>(
                    value: _asInt(r['id']),
                    child: Text(r['name']?.toString() ?? ''),
                  );
                }).toList();

                items.insert(
                  0,
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text('None (No Rubric)'),
                  ),
                );

                return items;
              }

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
                        if (!editing) ...[
                          const SizedBox(height: 20),
                          Row(
                            children: const [
                              Icon(Icons.balance, size: 18, color: AppColors.maroon),
                              SizedBox(width: 8),
                              Text(
                                'Grade composition',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'How Panel, Adviser, and Peer scores combine for this stage. Defaults are 50 / 30 / 20.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (semesters.isNotEmpty) ...[
                            DropdownButtonFormField<int>(
                              initialValue: semesterId,
                              decoration: const InputDecoration(
                                labelText: 'Semester',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
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
                              onChanged: (value) {
                                setDialogState(() {
                                  semesterId = value;
                                });
                              },
                            ),
                            const SizedBox(height: 14),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: panelCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Panel %',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (_) {
                                    setDialogState(() {});
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: adviserCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Advisor %',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (_) {
                                    setDialogState(() {});
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: peerCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Peer %',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (_) {
                                    setDialogState(() {});
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Total: $total%${total == 100 ? '' : ' — must equal 100%'}',
                            style: TextStyle(
                              color: total == 100
                                  ? AppColors.success
                                  : AppColors.danger,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () {
                              setDialogState(() {
                                panelCtrl.text = '50';
                                adviserCtrl.text = '30';
                                peerCtrl.text = '20';
                              });
                            },
                            icon: const Icon(Icons.restore, size: 16),
                            label: const Text('Reset to 50 / 30 / 20'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              textStyle: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<int>(
                            initialValue: panelRubricId,
                            decoration: const InputDecoration(
                              labelText: 'Panel Rubric',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: buildRubricDropdownItems('panel'),
                            onChanged: (value) {
                              setDialogState(() {
                                panelRubricId = value;
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<int>(
                            initialValue: adviserRubricId,
                            decoration: const InputDecoration(
                              labelText: 'Adviser Rubric',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: buildRubricDropdownItems('adviser'),
                            onChanged: (value) {
                              setDialogState(() {
                                adviserRubricId = value;
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<int>(
                            initialValue: peerRubricId,
                            decoration: const InputDecoration(
                              labelText: 'Peer Rubric',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: buildRubricDropdownItems('peer'),
                            onChanged: (value) {
                              setDialogState(() {
                                peerRubricId = value;
                              });
                            },
                          ),
                        ],
                        const SizedBox(height: 20),
                        // Deliverables Section
                        Row(
                          children: [
                            const Icon(Icons.inventory_2,
                                size: 18, color: AppColors.maroon),
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
                                    'deliverable_id':
                                        'D${deliverables.length + 1}',
                                    'label': '',
                                    'deliverable_type': 'pre',
                                    'required': true,
                                    'display_order': deliverables.length + 1,
                                    'vault_note': '',
                                    'vault_file_template': '',
                                    'is_restricted': false,
                                  });
                                });
                              },
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Deliverable'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                textStyle: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w700),
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
                              Icon(Icons.info_outline,
                                  size: 16, color: Color(0xFF0369A1)),
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
                                    label,
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
                    onPressed: label.text.trim().isEmpty ||
                            (!editing && (total != 100 || semesterId == null))
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
    } finally {
      if (saved != true) {
        label.dispose();
        description.dispose();
        order.dispose();
        panelCtrl.dispose();
        adviserCtrl.dispose();
        peerCtrl.dispose();
        for (final item in deliverables) {
          (item['_labelController'] as TextEditingController?)?.dispose();
          (item['_templateController'] as TextEditingController?)?.dispose();
        }
      }
    }

    if (!mounted || saved != true) {
      return;
    }

    final payload = {
      'label': label.text.trim(),
      'display_order': int.tryParse(order.text.trim()) ??
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
      final newStageId =
          await ref.read(defenseStagesProvider.notifier).addStage(payload);
      if (newStageId != null && semesterId != null) {
        await ref.read(defenseStagesProvider.notifier).updateGradingConfig(
          newStageId,
          semesterId!,
          {
            'panel_weight': int.tryParse(panelCtrl.text.trim()) ?? 50,
            'adviser_weight': int.tryParse(adviserCtrl.text.trim()) ?? 30,
            'peer_weight': int.tryParse(peerCtrl.text.trim()) ?? 20,
            'panel_rubric_id': panelRubricId,
            'adviser_rubric_id': adviserRubricId,
            'peer_rubric_id': peerRubricId,
          },
        );
      }
    }

    label.dispose();
    description.dispose();
    order.dispose();
    panelCtrl.dispose();
    adviserCtrl.dispose();
    peerCtrl.dispose();
    for (final item in deliverables) {
      (item['_labelController'] as TextEditingController?)?.dispose();
      (item['_templateController'] as TextEditingController?)?.dispose();
    }
  }

  Widget _buildDeliverableRow(
    Map<String, dynamic> item,
    int index,
    List<Map<String, dynamic>> deliverables,
    void Function(void Function()) setDialogState,
    TextEditingController stageLabelCtrl,
  ) {
    final labelController = item['_labelController'] as TextEditingController? ??
        (item['_labelController'] = TextEditingController(text: item['label']?.toString() ?? ''));
    final templateController = item['_templateController'] as TextEditingController? ??
        (item['_templateController'] = TextEditingController(text: item['vault_file_template']?.toString() ?? ''));

    final isVault = item['deliverable_type'] == 'vault';

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  onChanged: (value) {
                    item['label'] = value;
                    if (isVault) {
                      setDialogState(() {});
                    }
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
                    final removed = deliverables.removeAt(index);
                    (removed['_labelController'] as TextEditingController?)?.dispose();
                    (removed['_templateController'] as TextEditingController?)?.dispose();
                  });
                },
              ),
            ],
          ),
          if (isVault) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: item['is_restricted'] == true,
                  onChanged: (value) {
                    setDialogState(() {
                      item['is_restricted'] = value ?? false;
                    });
                  },
                ),
                const Text(
                  'Restricted (Private in Vault)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.maroon,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: templateController,
              decoration: const InputDecoration(
                labelText: 'Vault File Template',
                isDense: true,
                border: OutlineInputBorder(),
                hintText: '{year}.{course}.{project}.{stage}.{deliverable}.{semester}',
              ),
              onChanged: (value) {
                setDialogState(() {
                  item['vault_file_template'] = value;
                });
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
                _variableChip(item, templateController, '{year}', setDialogState),
                _variableChip(item, templateController, '{course}', setDialogState),
                _variableChip(item, templateController, '{project}', setDialogState),
                _variableChip(item, templateController, '{stage}', setDialogState),
                _variableChip(item, templateController, '{deliverable}', setDialogState),
                _variableChip(item, templateController, '{semester}', setDialogState),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Preview: ${_resolvePreview(item['vault_file_template']?.toString() ?? '', item['label']?.toString() ?? '', stageLabelCtrl.text)}',
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

  String _resolvePreview(String template, String deliverableLabel, String stageLabel) {
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
    final stage = slugify(stageLabel.trim().isEmpty ? 'StageLabel' : stageLabel.trim());
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

  Widget _variableChip(
    Map<String, dynamic> item,
    TextEditingController controller,
    String variable,
    void Function(void Function()) setDialogState,
  ) {
    return InkWell(
      onTap: () => _insertVariable(item, controller, variable, setDialogState),
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

  void _insertVariable(
    Map<String, dynamic> item,
    TextEditingController controller,
    String variable,
    void Function(void Function()) setDialogState,
  ) {
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

    setDialogState(() {
      controller.text = newText;
      controller.selection = TextSelection.collapsed(offset: newCursorPosition);
      item['vault_file_template'] = newText;
    });
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
