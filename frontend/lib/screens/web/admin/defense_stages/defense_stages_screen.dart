import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/defense_stages_provider.dart';
import '../../../../services/academic_period_provider.dart';
import '../../../../services/rubric_engine_provider.dart';
import '../../../../theme/app_theme.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/feedback/empty_state.dart';
import 'defense_stage_editor_screen.dart';
import '../widgets/defensys_admin_shell.dart';

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
  bool _isPipelineView = true;
  final Set<int> _expandedStageIds = {};

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
          showErrorToast(context, next.error!);
        }
        if (next.message != null && next.message != previous?.message) {
          showSuccessToast(context, next.message!);
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
            const SizedBox(height: 16),
            _buildExecutiveStatCards(state),
            const SizedBox(height: 12),
            _buildLifecycleLegend(state),
            const SizedBox(height: 16),
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFEE2E2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_tree_rounded,
                        color: AppColors.maroon, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Capstone Stage Chain & Governance',
                    style: TextStyle(
                      color: AppColors.maroon,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Define sequential defense milestones, evaluation rubrics, and deliverable archive templates for Capstone.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
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
                icon: const Icon(Icons.sync_rounded, size: 17),
                label: const Text('Refresh Stages'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            SizedBox(
              height: 42,
              child: ElevatedButton.icon(
                onPressed: state.isSaving ? null : () => _showStageDialog(),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Add Stage'),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: AppColors.maroon,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExecutiveStatCards(DefenseStagesState state) {
    final total = _count(state, 'total');
    final published = _count(state, 'active');
    final locked = state.stages.where((s) => _stageStatus(s) == 'locked').length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 800;

        final cards = [
          _statTile(
            title: 'Total Academic Stages',
            value: '$total',
            subtitle: 'Configured in master pipeline',
            icon: Icons.layers_outlined,
            accentColor: AppColors.maroon,
          ),
          _statTile(
            title: 'Published & Active',
            value: '$published / $total',
            subtitle: 'Available for scheduler configuration',
            icon: Icons.check_circle_outline_rounded,
            accentColor: const Color(0xFF10B981),
            badgeText: published > 0 ? 'Scheduler Active' : 'Draft Phase',
            badgeColor: const Color(0xFFECFDF5),
            badgeTextColor: const Color(0xFF047857),
          ),
          _statTile(
            title: 'Locked Defenses',
            value: '$locked',
            subtitle: 'Read-only stages with active defenses',
            icon: Icons.lock_clock_outlined,
            accentColor: const Color(0xFF64748B),
            badgeText: locked > 0 ? 'Protected' : 'Unlocked',
            badgeColor: const Color(0xFFF1F5F9),
            badgeTextColor: const Color(0xFF475569),
          ),
        ];

        if (isCompact) {
          return Column(
            children: cards
                .map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: c,
                    ))
                .toList(),
          );
        }

        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
            const SizedBox(width: 12),
            Expanded(child: cards[2]),
          ],
        );
      },
    );
  }

  Widget _statTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    String? badgeText,
    Color? badgeColor,
    Color? badgeTextColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accentColor, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        height: 1.1,
                      ),
                    ),
                    if (badgeText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor ?? const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            color: badgeTextColor ?? AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLifecycleLegend(DefenseStagesState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x03000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.alt_route_rounded, size: 15, color: AppColors.maroon),
              SizedBox(width: 6),
              Text(
                'Stage Lifecycle & Governance Rules',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 650;

              final steps = [
                _lifecycleStepPill(
                  step: '1',
                  label: 'Draft Stage',
                  description: 'Configure deliverables & rubrics',
                  color: const Color(0xFFF59E0B),
                  bgColor: const Color(0xFFFFFBEB),
                  borderColor: const Color(0xFFFDE68A),
                ),
                _lifecycleStepPill(
                  step: '2',
                  label: 'Published Stage',
                  description: 'Active for defense scheduler',
                  color: const Color(0xFF10B981),
                  bgColor: const Color(0xFFECFDF5),
                  borderColor: const Color(0xFFA7F3D0),
                ),
                _lifecycleStepPill(
                  step: '3',
                  label: 'Locked Stage',
                  description: 'Read-only once defenses scheduled',
                  color: const Color(0xFF64748B),
                  bgColor: const Color(0xFFF1F5F9),
                  borderColor: const Color(0xFFCBD5E1),
                ),
              ];

              if (isMobile) {
                return Column(
                  children: steps
                      .map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: s,
                          ))
                      .toList(),
                );
              }

              return Row(
                children: [
                  Expanded(child: steps[0]),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward_rounded,
                        size: 14, color: Color(0xFF94A3B8)),
                  ),
                  Expanded(child: steps[1]),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward_rounded,
                        size: 14, color: Color(0xFF94A3B8)),
                  ),
                  Expanded(child: steps[2]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _lifecycleStepPill({
    required String step,
    required String label,
    required String description,
    required Color color,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Text(
              step,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color == const Color(0xFF64748B)
                        ? AppColors.textPrimary
                        : color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10.5,
                    height: 1.15,
                  ),
                ),
              ],
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Academic Stage Chain',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Sequential progression of defense milestones',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _viewSwitchBtn(
                        label: 'Pipeline Flow',
                        icon: Icons.account_tree_outlined,
                        selected: _isPipelineView,
                        onTap: () => setState(() => _isPipelineView = true),
                      ),
                      _viewSwitchBtn(
                        label: 'Table View',
                        icon: Icons.table_rows_outlined,
                        selected: !_isPipelineView,
                        onTap: () => setState(() => _isPipelineView = false),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE2E8F0)),
          if (_isPipelineView)
            _buildStagePipelineView(state)
          else
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

  Widget _viewSwitchBtn({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x10000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? AppColors.maroon : AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.maroon : AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStagePipelineView(DefenseStagesState state) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          for (var i = 0; i < state.stages.length; i++) ...[
            _stagePipelineNodeCard(state, state.stages[i], i, state.stages.length),
            if (i < state.stages.length - 1)
              _pipelineConnectorLine(state.stages[i + 1]['label']?.toString() ?? ''),
          ],
        ],
      ),
    );
  }

  Widget _pipelineConnectorLine([String nextLabel = '']) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      height: 24,
      child: Row(
        children: [
          const SizedBox(width: 38),
          Container(
            width: 2,
            color: const Color(0xFFCBD5E1),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.arrow_downward_rounded, size: 13, color: AppColors.maroon),
          const SizedBox(width: 5),
          Text(
            nextLabel.isNotEmpty
                ? 'Unlocks Next Academic Milestone: $nextLabel'
                : 'Unlocks Next Academic Milestone',
            style: const TextStyle(
              color: AppColors.maroon,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stagePipelineNodeCard(
    DefenseStagesState state,
    Map<String, dynamic> stage,
    int index,
    int totalStages,
  ) {
    final stageId = _asInt(stage['id']) ?? index;
    final status = _stageStatus(stage);
    final isPublished = status == 'published';
    final isLocked = status == 'locked';
    final order = stage['display_order']?.toString() ?? '${index + 1}';
    final isExpanded = _expandedStageIds.contains(stageId);

    Color sideAccentColor;
    if (isLocked) {
      sideAccentColor = const Color(0xFF64748B);
    } else if (isPublished) {
      sideAccentColor = const Color(0xFF10B981);
    } else {
      sideAccentColor = const Color(0xFFF59E0B);
    }

    final delivs = (stage['deliverables'] is List) ? (stage['deliverables'] as List) : [];
    final delivCount = delivs.length;
    final preCount = delivs.where((d) => (d is Map) && (d['deliverable_type'] == 'pre' || d['type'] == 'pre')).length;
    final postCount = delivs.where((d) => (d is Map) && (d['deliverable_type'] == 'post' || d['deliverable_type'] == 'vault' || d['type'] == 'post')).length;

    final previousLabel = stage['previous_stage_label']?.toString();
    final rubricName = stage['rubric_name']?.toString() ??
        (stage['rubric'] is Map ? stage['rubric']['name']?.toString() : null) ??
        'Evaluation Rubric Attached';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                color: sideAccentColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: sideAccentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: sideAccentColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              order.padLeft(2, '0'),
                              style: TextStyle(
                                color: sideAccentColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      stage['label']?.toString() ?? 'Stage',
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _codeTag(stage['code']?.toString() ?? ''),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  stage['description']?.toString() ??
                                      'Academic defense milestone configuration.',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          _statusChip(stage),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Rubric Micro-card
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.assignment_outlined, size: 13, color: AppColors.maroon),
                            const SizedBox(width: 6),
                            const Text(
                              'Stage Rubric: ',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                            ),
                            Text(
                              rubricName,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Deliverables Accordion Expander
                      InkWell(
                        onTap: () {
                          setState(() {
                            if (isExpanded) {
                              _expandedStageIds.remove(stageId);
                            } else {
                              _expandedStageIds.add(stageId);
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: delivCount > 0 ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: delivCount > 0 ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.folder_outlined,
                                    size: 15,
                                    color: delivCount > 0 ? const Color(0xFF1D4ED8) : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$delivCount Deliverables Configured ($preCount Pre, $postCount Post)',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: delivCount > 0 ? const Color(0xFF1D4ED8) : AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              Icon(
                                isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: delivCount > 0 ? const Color(0xFF1D4ED8) : const Color(0xFF64748B),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isExpanded) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: delivs.isEmpty
                              ? const Text(
                                  'No deliverables configured for this stage.',
                                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: delivs.map<Widget>((item) {
                                    final d = Map<String, dynamic>.from(item as Map);
                                    final label = d['label']?.toString() ?? d['name']?.toString() ?? 'Deliverable';
                                    final isPost = d['deliverable_type'] == 'post' || d['deliverable_type'] == 'vault' || d['type'] == 'post';
                                    final isReq = d['required'] == true;
                                    final isRestricted = d['is_restricted'] == true;

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isPost ? Icons.archive_outlined : Icons.description_outlined,
                                            size: 12,
                                            color: isPost ? const Color(0xFF6366F1) : AppColors.maroon,
                                          ),
                                          const SizedBox(width: 5),
                                          Expanded(
                                            child: Text(
                                              label,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textPrimary,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isReq)
                                            Container(
                                              margin: const EdgeInsets.only(left: 4),
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFEE2E2),
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: const Text(
                                                'Req',
                                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.maroon),
                                              ),
                                            ),
                                          if (isRestricted)
                                            Container(
                                              margin: const EdgeInsets.only(left: 4),
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFEF3C7),
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: const Text(
                                                'Private Archive',
                                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.turn_right_rounded, size: 13, color: AppColors.textSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  previousLabel == null || previousLabel.isEmpty
                                      ? 'Sequence Start'
                                      : 'Prerequisite: $previousLabel',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          _buildStageActions(state, stage, index, totalStages),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
          _stageThFixed('ORDER', 80, maxLines: 1),
          Expanded(flex: 24, child: _stageTh('STAGE NAME & CODE')),
          Expanded(flex: 18, child: _stageTh('PREREQUISITE')),
          Expanded(flex: 20, child: _stageTh('RUBRIC')),
          _stageThFixed('DELIVERABLES', 120),
          _stageThFixed('STATUS', 120),
          _stageThFixed('ACTIONS', 220),
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
    final rubricName = stage['rubric_name']?.toString() ??
        (stage['rubric'] is Map ? stage['rubric']['name']?.toString() : null) ??
        'Attached';

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
          _stageTdFixed(80, _orderTableBadge(stage['display_order'])),
          Expanded(
            flex: 24,
            child: _stageTd(
              Row(
                children: [
                  Expanded(child: _stageNameCell(stage)),
                  const SizedBox(width: 6),
                  _codeTag(stage['code']?.toString() ?? ''),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 18,
            child: _stageTd(_previousStageCell(stage)),
          ),
          Expanded(
            flex: 20,
            child: _stageTd(
              Text(
                rubricName,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          _stageTdFixed(
            120,
            Text(
              '${_deliverablesCount(stage)} attached',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _stageTdFixed(120, _statusChip(stage)),
          _stageTdFixedActions(220, _buildStageActions(state, stage, index, state.stages.length)),
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
        children: [
          for (int i = 0; i < state.stages.length; i++)
            Container(
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
                      _orderTableBadge(state.stages[i]['display_order']),
                      const SizedBox(width: 12),
                      Expanded(child: _stageNameCell(state.stages[i])),
                      _statusChip(state.stages[i]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _codeTag(state.stages[i]['code']?.toString() ?? ''),
                      _softChip(
                        '${_deliverablesCount(state.stages[i])} deliverables',
                        const Color(0xFFF8FAFC),
                        AppColors.textPrimary,
                        const Color(0xFFD7DDE8),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _previousStageCell(state.stages[i]),
                  const SizedBox(height: 12),
                  _buildStageActions(state, state.stages[i], i, state.stages.length),
                ],
              ),
            ),
        ],
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
    int index,
    int totalStages,
  ) {
    final stageId = _asInt(stage['id']);
    final status = _stageStatus(stage);
    final locked = status == 'locked';
    final published = status == 'published';

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Reorder quick controls
        if (totalStages > 1)
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: index > 0 ? 'Move Up in Sequence (▲)' : 'Already at Start',
                  icon: const Icon(Icons.arrow_upward_rounded, size: 14),
                  color: index > 0 ? AppColors.textPrimary : const Color(0xFFCBD5E1),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: index > 0 && !state.isSaving && stageId != null
                      ? () => _confirmMoveStage(
                            stageId: stageId,
                            stageLabel: stage['label']?.toString() ?? 'Stage',
                            delta: -1,
                            currentIndex: index,
                            allStages: state.stages,
                          )
                      : null,
                ),
                Container(
                  width: 1,
                  height: 14,
                  color: const Color(0xFFE2E8F0),
                ),
                IconButton(
                  tooltip: index < totalStages - 1 ? 'Move Down in Sequence (▼)' : 'Already at End',
                  icon: const Icon(Icons.arrow_downward_rounded, size: 14),
                  color: index < totalStages - 1 ? AppColors.textPrimary : const Color(0xFFCBD5E1),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: index < totalStages - 1 && !state.isSaving && stageId != null
                      ? () => _confirmMoveStage(
                            stageId: stageId,
                            stageLabel: stage['label']?.toString() ?? 'Stage',
                            delta: 1,
                            currentIndex: index,
                            allStages: state.stages,
                          )
                      : null,
                ),
              ],
            ),
          ),
        if (locked)
          OutlinedButton.icon(
            onPressed: stageId == null ? null : () => _openStageEditor(stage),
            icon: const Icon(Icons.visibility_outlined, size: 15),
            label: const Text('View Details'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: Color(0xFFCBD5E1)),
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
        else ...[
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
          if (!published)
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
    final codeCtrl = TextEditingController(
      text: stage?['code']?.toString() ?? '',
    );
    final description = TextEditingController(
      text: stage?['description']?.toString() ?? '',
    );
    final existingStages = ref.read(defenseStagesProvider).stages;
    final totalExisting = existingStages.length;
    final currentOrder = stage != null ? _asInt(stage['display_order']) : null;
    int selectedPosition = editing
        ? (currentOrder ?? 1).clamp(1, totalExisting > 0 ? totalExisting : 1)
        : (totalExisting + 1);
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

              final activeSemObj = semesters.firstWhere(
                (s) => _asInt(s['id']) == semesterId,
                orElse: () => activePeriod ?? (semesters.isNotEmpty ? semesters.first : {}),
              );
              final activeSemesterName = activeSemObj['display_name']?.toString() ??
                  activeSemObj['label']?.toString() ??
                  (semesterId != null ? 'Semester $semesterId' : 'No Active Semester');

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
                final currentStageId = stage != null ? _asInt(stage['id']) : null;

                final items = options.map((r) {
                  final id = _asInt(r['id']);
                  final assignedStageId = _asInt(r['defense_stage_id']);
                  final assignedStageLabel = r['defense_stage_label']?.toString();
                  final isAssignedToOther = assignedStageId != null && assignedStageId != currentStageId;

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
                          controller: codeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Stage code',
                            helperText: 'Unique system identifier'
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          key: ValueKey(selectedPosition),
                          initialValue: selectedPosition,
                          decoration: const InputDecoration(
                            labelText: 'Sequence Position in Pipeline',
                            helperText: 'Position sets milestone order. Other stages automatically shift.',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (int i = 1; i <= (editing ? totalExisting : totalExisting + 1); i++)
                              DropdownMenuItem<int>(
                                value: i,
                                child: Text(
                                  i == 1
                                      ? 'Position 1 of ${editing ? totalExisting : totalExisting + 1} (Start of Pipeline)'
                                      : (i == (editing ? totalExisting : totalExisting + 1) && !editing)
                                          ? 'Position $i of ${totalExisting + 1} (End of Pipeline)'
                                          : 'Position $i of ${editing ? totalExisting : totalExisting + 1}${i - 2 >= 0 && i - 2 < existingStages.length ? " (After ${existingStages[i - 2]['label']})" : ""}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: (editing && currentOrder == i)
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedPosition = val);
                            }
                          },
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
                                    'archive_note': '',
                                    'archive_file_template': '',
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
                                  'Pre-Defense items gate endorsement. Post-Defense items unlock after defense is officially complete.',
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
                    onPressed: () {
                      final stageName = label.text.trim();
                      if (stageName.isEmpty) {
                        showValidationToast(context, 'Enter a stage name.');
                        return;
                      }
                      if (!editing) {
                        if (semesterId == null) {
                          showValidationToast(context, 'Select a semester.');
                          return;
                        }
                        if (total != 100) {
                          showValidationToast(context, 'Panel, Adviser, and Peer weights must total 100%.');
                          return;
                        }
                      }
                      // Validate deliverables labels
                      for (int i = 0; i < deliverables.length; i++) {
                        final dLabel = deliverables[i]['label']?.toString().trim() ?? '';
                        if (dLabel.isEmpty) {
                          showValidationToast(context, 'Deliverable label cannot be empty (item ${i + 1}).');
                          return;
                        }
                      }
                      Navigator.pop(dialogContext, true);
                    },
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
        codeCtrl.dispose();
        description.dispose();
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
      'code': codeCtrl.text.trim(),
      'display_order': selectedPosition,
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
          semesterId,
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
    codeCtrl.dispose();
    description.dispose();
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
        (item['_templateController'] = TextEditingController(text: item['archive_file_template']?.toString() ?? ''));

    final isPost = item['deliverable_type'] == 'post';

    InputDecoration dialogInputDecoration({
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
                  decoration: dialogInputDecoration(
                    labelText: 'Name / Label',
                    hintText: 'e.g. Concept Paper PDF',
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (value) {
                    item['label'] = value.trim();
                    if (isPost) {
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
                  initialValue: item['deliverable_type']?.toString() ?? 'pre',
                  decoration: dialogInputDecoration(labelText: 'Type'),
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  items: const [
                    DropdownMenuItem(value: 'pre', child: Text('Pre-Defense', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'post', child: Text('Post-Defense', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        item['deliverable_type'] = value;
                        if (value == 'post' || value == 'pre') {
                          item['required'] = true;
                        }
                      });
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
                      onChanged: (value) {
                        setDialogState(() {
                          item['required'] = value == true;
                        });
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
                onPressed: () {
                  setDialogState(() {
                    final removed = deliverables.removeAt(index);
                    (removed['_labelController'] as TextEditingController?)?.dispose();
                    (removed['_templateController'] as TextEditingController?)?.dispose();
                  });
                },
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                style: IconButton.styleFrom(
                  hoverColor: AppColors.danger.withValues(alpha: 0.08),
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
                  onChanged: (value) {
                    setDialogState(() {
                      item['is_restricted'] = value == true;
                    });
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
                        decoration: dialogInputDecoration(
                          labelText: 'Archive Naming Template',
                          hintText: 'e.g. {year}.{course}.{project}.{stage}.{deliverable}.{semester}',
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (value) {
                          setDialogState(() {
                            item['archive_file_template'] = value.trim();
                          });
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
                                  labelStyle: const TextStyle(color: AppColors.maroon),
                                  backgroundColor: AppColors.maroon.withValues(alpha: 0.05),
                                  side: BorderSide(color: AppColors.maroon.withValues(alpha: 0.15)),
                                  padding: EdgeInsets.zero,
                                  onPressed: () => _insertVariable(item, templateController, varName, setDialogState),
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
                          _resolvePreview(item['archive_file_template']?.toString() ?? '', item['label']?.toString() ?? '', stageLabelCtrl.text),
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

  String _resolvePreview(String template, String deliverableLabel, String stageLabel) {
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
      item['archive_file_template'] = newText;
    });
  }

  Future<void> _confirmMoveStage({
    required int stageId,
    required String stageLabel,
    required int delta,
    required int currentIndex,
    required List<Map<String, dynamic>> allStages,
  }) async {
    final targetIndex = currentIndex + delta;
    if (targetIndex < 0 || targetIndex >= allStages.length) return;

    final targetStageName = allStages[targetIndex]['label']?.toString() ?? 'the adjacent stage';
    final movingUp = delta < 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              movingUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              color: AppColors.maroon,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(movingUp ? 'Move Stage Earlier?' : 'Move Stage Later?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              movingUp
                  ? 'Move "$stageLabel" before "$targetStageName" (Position ${targetIndex + 1})?'
                  : 'Move "$stageLabel" after "$targetStageName" (Position ${targetIndex + 1})?',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'This will automatically adjust sequence progression and milestone prerequisites across the pipeline.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.maroon,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(movingUp ? 'Move Earlier' : 'Move Later'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    await ref.read(defenseStagesProvider.notifier).moveStage(stageId, delta);
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE6E8EF)),
      ),
      child: DefensysEmptyState(
        icon: Icons.layers_outlined,
        title: 'No Defense Stages Found',
        description:
            'Add a stage to construct your capstone defense pipeline and scheduler milestone chain.',
        size: DefensysEmptyStateSize.compact,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        primaryAction: DefensysEmptyAction(
          label: 'Add Stage',
          icon: Icons.add_rounded,
          onPressed: () => _showStageDialog(),
        ),
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
