import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/defense_stages_provider.dart';
import '../../../../services/academic_period_provider.dart';
import '../../../../services/rubric_engine_provider.dart';
import '../../../../services/unsaved_changes_provider.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/feedback/empty_state.dart';
import 'defense_stage_editor_screen.dart';
import 'widgets/pipeline_position_selector.dart';
import 'widgets/endorsed_stage_resolution_dialog.dart';
import '../widgets/defensys_admin_shell.dart';
import '../admin_shell.dart';

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
    ref.read(unsavedChangesProvider.notifier).setDirty(false);
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

    ref.listen<DefensysAdminSection>(
      activeAdminSectionProvider,
      (previous, next) {
        if (next == DefensysAdminSection.defenseStages) {
          ref.read(defenseStagesProvider.notifier).fetchStages();
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x03000000),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 740;

          final item1 = _executiveStatItem(
            icon: Icons.account_tree_outlined,
            iconColor: AppColors.maroon,
            value: '$total',
            label: 'Total Academic Stages',
          );

          final item2 = _executiveStatItem(
            icon: Icons.check_circle_outline_rounded,
            iconColor: const Color(0xFF10B981),
            value: '$published',
            label: 'Published & Active',
          );

          final item3 = _executiveStatItem(
            icon: Icons.task_alt_rounded,
            iconColor: const Color(0xFF2563EB),
            value: '$locked',
            label: 'Completed Stages',
          );

          if (isCompact) {
            return Column(
              children: [
                item1,
                const Divider(height: 16, color: Color(0xFFF1F5F9)),
                item2,
                const Divider(height: 16, color: Color(0xFFF1F5F9)),
                item3,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: item1),
              Container(width: 1, height: 34, color: const Color(0xFFE2E8F0)),
              Expanded(child: item2),
              Container(width: 1, height: 34, color: const Color(0xFFE2E8F0)),
              Expanded(child: item3),
            ],
          );
        },
      ),
    );
  }

  Widget _executiveStatItem({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 760;

          final badge1 = _lifecycleInlineBadge(
            step: '1',
            name: 'Draft',
            hint: 'Configure rubrics & files',
            color: const Color(0xFFF59E0B),
            bgColor: const Color(0xFFFFFBEB),
          );

          final badge2 = _lifecycleInlineBadge(
            step: '2',
            name: 'Published',
            hint: 'Active in defense scheduler',
            color: const Color(0xFF10B981),
            bgColor: const Color(0xFFECFDF5),
          );

          final badge3 = _lifecycleInlineBadge(
            step: '3',
            name: 'Completed',
            hint: 'Finalized with scheduled defenses',
            color: const Color(0xFF2563EB),
            bgColor: const Color(0xFFEFF6FF),
          );

          if (isMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.alt_route_rounded, size: 14, color: AppColors.maroon),
                    SizedBox(width: 6),
                    Text(
                      'Stage Cycle',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [badge1, badge2, badge3],
                ),
              ],
            );
          }

          return Row(
            children: [
              const Icon(Icons.alt_route_rounded, size: 14, color: AppColors.maroon),
              const SizedBox(width: 6),
              const Text(
                'Stage Cycle: ',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              badge1,
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward_rounded, size: 12, color: Color(0xFF94A3B8)),
              ),
              badge2,
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward_rounded, size: 12, color: Color(0xFF94A3B8)),
              ),
              badge3,
            ],
          );
        },
      ),
    );
  }

  Widget _lifecycleInlineBadge({
    required String step,
    required String name,
    required String hint,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 15,
            height: 15,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Text(
              step,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            name,
            style: TextStyle(
              color: color == const Color(0xFF64748B) ? AppColors.textPrimary : color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '($hint)',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
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
                        'Sequential progression of defense milestones & milestone requirements',
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
    final totalStages = state.stages.length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < totalStages; i++) ...[
            Stack(
              children: [
                // 1. Continuous Timeline Rail Spine (spans full dynamic height of this stage)
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  width: 36,
                  child: CustomPaint(
                    painter: _TimelineRailPainter(
                      isFirst: i == 0,
                      isLast: i == totalStages - 1,
                      nodeTop: 14.0,
                      nodeSize: 36.0,
                    ),
                  ),
                ),
                // 2. Stage Content Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Step Badge Node
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: _buildTimelineNode(state.stages[i], i, totalStages),
                    ),
                    const SizedBox(width: 14),
                    // Stage Card + Bridge
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _stagePipelineNodeCard(state, state.stages[i], i, totalStages),
                          if (i < totalStages - 1)
                            _milestoneBridge(state.stages[i + 1]['label']?.toString() ?? ''),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineNode(Map<String, dynamic> stage, int index, int totalStages) {
    final status = _stageStatus(stage);
    final isLocked = status == 'locked';
    final isPublished = status == 'published';
    final order = stage['display_order']?.toString() ?? '${index + 1}';

    Color borderColor;
    Color bgColor;
    Color textColor;

    if (isLocked) {
      borderColor = const Color(0xFF60A5FA);
      bgColor = const Color(0xFFEFF6FF);
      textColor = const Color(0xFF1D4ED8);
    } else if (isPublished) {
      borderColor = const Color(0xFF10B981);
      bgColor = const Color(0xFFECFDF5);
      textColor = const Color(0xFF047857);
    } else {
      borderColor = const Color(0xFFF59E0B);
      bgColor = const Color(0xFFFFFBEB);
      textColor = const Color(0xFFB45309);
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          order.padLeft(2, '0'),
          style: TextStyle(
            color: textColor,
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }

  Widget _milestoneBridge(String nextLabel) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_downward_rounded, size: 12, color: AppColors.maroon),
            const SizedBox(width: 5),
            const Text(
              'Unlocks Next Milestone: ',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              nextLabel.isNotEmpty ? nextLabel : 'Next Stage',
              style: const TextStyle(
                color: AppColors.maroon,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deliverableCategoryBadge({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    String? tooltip,
    bool compact = false,
    VoidCallback? onTap,
  }) {
    final badgeWidget = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 11 : 13, color: color),
            const SizedBox(width: 4),
            Text(
              '$label: $count',
              style: TextStyle(
                fontSize: compact ? 10.5 : 11.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: badgeWidget);
    }
    return badgeWidget;
  }

  Widget _buildDeliverablesColumn({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color headerBg,
    required Color headerBorder,
    required List<dynamic> deliverables,
    required bool isPost,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner styled header matching Project Archive
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: headerBorder),
            ),
            child: Row(
              children: [
                Icon(icon, size: 15, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: headerBorder),
                  ),
                  child: Text(
                    '${deliverables.length}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (deliverables.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                isPost
                    ? 'No post-defense deliverables configured.'
                    : 'No pre-defense deliverables configured.',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF94A3B8),
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            Column(
              children: deliverables.map<Widget>((item) {
                final d = Map<String, dynamic>.from(item as Map);
                final label = d['label']?.toString() ?? d['name']?.toString() ?? 'Deliverable';
                final isReq = d['required'] == true;
                final isRestricted = d['is_restricted'] == true;
                final template = d['archive_file_template']?.toString() ?? '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x02000000),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isPost ? Icons.inventory_2_rounded : Icons.folder_open_rounded,
                            size: 14,
                            color: accentColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (isReq) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: const Text(
                                'Required',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFB91C1C),
                                ),
                              ),
                            ),
                          ],
                          if (!isPost && d['is_defense_material'] == true) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.visibility_rounded, size: 9.5, color: Color(0xFF1D4ED8)),
                                  SizedBox(width: 2.5),
                                  Text(
                                    'Panel View',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1D4ED8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (isPost && d['verdict_condition'] == 'revisions_only') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF7ED),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFFED7AA)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_note_rounded, size: 10, color: Color(0xFFC2410C)),
                                  SizedBox(width: 2.5),
                                  Text(
                                    'Revisions Only',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFC2410C),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (isRestricted) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: const Text(
                                'Private Vault',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (isPost && template.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.code_rounded, size: 11, color: Color(0xFF94A3B8)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Archive Pattern: $template',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
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
    final isExpanded = _expandedStageIds.contains(stageId);

    final delivs = (stage['deliverables'] is List) ? (stage['deliverables'] as List) : [];
    final delivCount = delivs.length;
    final isPresentationOnly = stage['is_presentation_only'] == true;
    final preDeliverables = delivs
        .where((d) => (d is Map) && (d['deliverable_type'] == 'pre' || d['type'] == 'pre'))
        .toList();
    final postDeliverables = delivs
        .where((d) =>
            (d is Map) &&
            (d['deliverable_type'] == 'post' || d['deliverable_type'] == 'vault' || d['type'] == 'post'))
        .toList();
    final preCount = preDeliverables.length;
    final postCount = postDeliverables.length;

    final previousLabel = stage['previous_stage_label']?.toString();
    final description = stage['description']?.toString() ?? '';
    final rubricInfo = (stage['rubric_info'] is Map)
        ? (stage['rubric_info'] as Map)
        : <String, dynamic>{};
    final hasRubrics = rubricInfo['has_rubrics'] == true ||
        (stage['rubric_name'] != null && stage['rubric_name'].toString().trim().isNotEmpty) ||
        (stage['rubric'] is Map && stage['rubric']['name'] != null);
    final rubricName = rubricInfo['summary']?.toString() ??
        stage['rubric_name']?.toString() ??
        (stage['rubric'] is Map ? stage['rubric']['name']?.toString() : null) ??
        'None attached';

    return Container(
      width: double.infinity,
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
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Title, Code, Status, and Action Buttons
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
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
                const SizedBox(width: 8),
                _statusChip(stage),
                const Spacer(),
                _buildStageActions(state, stage, index, totalStages),
              ],
            ),
            // Subtitle & Prerequisite Row
            if (description.isNotEmpty || (previousLabel != null && previousLabel.isNotEmpty) || index == 0) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (description.isNotEmpty)
                    Expanded(
                      child: Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ),
                  if (previousLabel != null && previousLabel.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.turn_right_rounded, size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 3),
                          Text(
                            'Prerequisite: $previousLabel',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (index == 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.flag_outlined, size: 11, color: AppColors.textSecondary),
                          SizedBox(width: 3),
                          Text(
                            'Sequence Start',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 10),
            // Configuration Strip: Rubric + Explicit Deliverables Section + Expand Button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  // 1. Rubric Section
                  Icon(
                    hasRubrics ? Icons.assignment_turned_in_rounded : Icons.assignment_outlined,
                    size: 13.5,
                    color: hasRubrics ? AppColors.maroon : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'Rubric: ',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                  Flexible(
                    child: Text(
                      hasRubrics ? rubricName : 'None attached',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: hasRubrics ? FontWeight.w800 : FontWeight.w500,
                        color: hasRubrics ? AppColors.textPrimary : const Color(0xFF64748B),
                        fontStyle: hasRubrics ? FontStyle.normal : FontStyle.italic,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(width: 1, height: 16, color: const Color(0xFFCBD5E1)),
                  const SizedBox(width: 12),
                  // 2. Deliverables Section
                  if (isPresentationOnly) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.record_voice_over_rounded, size: 12, color: Color(0xFF2563EB)),
                          SizedBox(width: 4),
                          Text(
                            'Presentation / Demo Only (No Uploads)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1D4ED8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                  ] else ...[
                    const Icon(Icons.inventory_2_outlined, size: 13.5, color: Color(0xFF475569)),
                    const SizedBox(width: 5),
                    const Text(
                      'Deliverables: ',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 2),
                    // Pre-Defense Deliverables Pill (Blue)
                    _deliverableCategoryBadge(
                      label: 'Pre-defense',
                      count: preCount,
                      icon: Icons.folder_open_rounded,
                      color: const Color(0xFF2563EB),
                      bgColor: const Color(0xFFEFF6FF),
                      borderColor: const Color(0xFFBFDBFE),
                      tooltip: 'Gatekeeper submissions required before defense scheduling',
                      onTap: () {
                        setState(() {
                          if (_expandedStageIds.contains(stageId)) {
                            _expandedStageIds.remove(stageId);
                          } else {
                            _expandedStageIds.add(stageId);
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 6),
                    // Post-Defense Deliverables Pill (Maroon)
                    _deliverableCategoryBadge(
                      label: 'Post-defense',
                      count: postCount,
                      icon: Icons.inventory_2_rounded,
                      color: AppColors.maroon,
                      bgColor: const Color(0xFFFFF1F2),
                      borderColor: const Color(0xFFFECDD3),
                      tooltip: 'Final revisions & post-defense deliverables required after defense',
                      onTap: () {
                        setState(() {
                          if (_expandedStageIds.contains(stageId)) {
                            _expandedStageIds.remove(stageId);
                          } else {
                            _expandedStageIds.add(stageId);
                          }
                        });
                      },
                    ),
                    const Spacer(),
                    // Expand / Collapse Chevron Button
                    InkWell(
                      onTap: () {
                        setState(() {
                          if (_expandedStageIds.contains(stageId)) {
                            _expandedStageIds.remove(stageId);
                          } else {
                            _expandedStageIds.add(stageId);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isExpanded ? 'Hide Deliverables' : 'View Deliverables ($delivCount)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isExpanded ? AppColors.maroon : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: isExpanded ? AppColors.maroon : AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Expanded 2-Column Pre-Defense vs Post-Defense Section
            if (isExpanded && !isPresentationOnly) ...[
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final isMobile = MediaQuery.sizeOf(context).width < 800;
                  final leftCol = _buildDeliverablesColumn(
                    title: 'Pre-defense deliverables',
                    subtitle: 'Required submissions before defense schedule',
                    icon: Icons.folder_open_rounded,
                    accentColor: const Color(0xFF2563EB),
                    headerBg: const Color(0xFFEFF6FF),
                    headerBorder: const Color(0xFFBFDBFE),
                    deliverables: preDeliverables,
                    isPost: false,
                  );

                  final rightCol = _buildDeliverablesColumn(
                    title: 'Post-defense deliverables',
                    subtitle: 'Required outcomes after defense for completion & archive',
                    icon: Icons.inventory_2_rounded,
                    accentColor: AppColors.maroon,
                    headerBg: const Color(0xFFFFF1F2),
                    headerBorder: const Color(0xFFFECDD3),
                    deliverables: postDeliverables,
                    isPost: true,
                  );

                  if (isMobile) {
                    return Column(
                      children: [
                        leftCol,
                        const SizedBox(height: 10),
                        rightCol,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: leftCol),
                      const SizedBox(width: 12),
                      Expanded(child: rightCol),
                    ],
                  );
                },
              ),
            ],
          ],
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
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _tableLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _stageThFixed('ORDER', 65, maxLines: 1),
          Expanded(flex: 22, child: _stageTh('STAGE NAME & CODE')),
          Expanded(flex: 16, child: _stageTh('PREREQUISITE')),
          Expanded(flex: 18, child: _stageTh('EVALUATION RUBRIC')),
          _stageThFixed('DELIVERABLES', 170),
          _stageThFixed('STATUS', 130),
          _stageThFixed('ACTIONS', 115),
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
    final delivs = (stage['deliverables'] is List) ? (stage['deliverables'] as List) : [];
    final isPresentationOnly = stage['is_presentation_only'] == true;
    final preCount = delivs
        .where((d) => (d is Map) && (d['deliverable_type'] == 'pre' || d['type'] == 'pre'))
        .length;
    final postCount = delivs
        .where((d) =>
            (d is Map) &&
            (d['deliverable_type'] == 'post' || d['deliverable_type'] == 'vault' || d['type'] == 'post'))
        .length;
    final rubricInfo = (stage['rubric_info'] is Map)
        ? (stage['rubric_info'] as Map)
        : <String, dynamic>{};
    final hasRubrics = rubricInfo['has_rubrics'] == true ||
        (stage['rubric_name'] != null && stage['rubric_name'].toString().trim().isNotEmpty) ||
        (stage['rubric'] is Map && stage['rubric']['name'] != null);
    final rubricName = rubricInfo['summary']?.toString() ??
        stage['rubric_name']?.toString() ??
        (stage['rubric'] is Map ? stage['rubric']['name']?.toString() : null) ??
        'None attached';

    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: zebra ? const Color(0xFFFAFAFA) : Colors.white,
        border: index > 0
            ? const Border(top: BorderSide(color: _tableLine))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _stageTdFixed(65, _orderTableBadge(stage['display_order'])),
          Expanded(
            flex: 22,
            child: _stageTd(
              Row(
                children: [
                  Expanded(child: _stageNameCell(stage)),
                  const SizedBox(width: 8),
                  _codeTag(stage['code']?.toString() ?? ''),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 16,
            child: _stageTd(_previousStageCell(stage)),
          ),
          Expanded(
            flex: 18,
            child: _stageTd(
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
                    Icon(
                      hasRubrics ? Icons.assignment_turned_in_rounded : Icons.assignment_outlined,
                      size: 13,
                      color: hasRubrics ? AppColors.maroon : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        hasRubrics ? rubricName : 'None attached',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: hasRubrics ? FontWeight.w700 : FontWeight.w500,
                          color: hasRubrics ? AppColors.textPrimary : const Color(0xFF64748B),
                          fontStyle: hasRubrics ? FontStyle.normal : FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _stageTdFixed(
            170,
            isPresentationOnly
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.record_voice_over_rounded, size: 12, color: Color(0xFF2563EB)),
                        SizedBox(width: 4),
                        Text(
                          'Oral / Demo',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                      ],
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _deliverableCategoryBadge(
                        label: 'Pre',
                        count: preCount,
                        icon: Icons.folder_open_rounded,
                        color: const Color(0xFF2563EB),
                        bgColor: const Color(0xFFEFF6FF),
                        borderColor: const Color(0xFFBFDBFE),
                        compact: true,
                      ),
                      const SizedBox(width: 4),
                      _deliverableCategoryBadge(
                        label: 'Post',
                        count: postCount,
                        icon: Icons.inventory_2_rounded,
                        color: AppColors.maroon,
                        bgColor: const Color(0xFFFFF1F2),
                        borderColor: const Color(0xFFFECDD3),
                        compact: true,
                      ),
                    ],
                  ),
          ),
          _stageTdFixed(130, _statusChip(stage)),
          _stageTdFixedActions(115, _buildStageActions(state, stage, index, state.stages.length)),
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
    final text = value?.toString() ?? '';
    final formatted = text.length == 1 ? '0$text' : text;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        formatted,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
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
          for (int i = 0; i < state.stages.length; i++) ...[
            Builder(
              builder: (context) {
                final stage = state.stages[i];
                final delivs = (stage['deliverables'] is List) ? (stage['deliverables'] as List) : [];
                final preCount = delivs
                    .where((d) => (d is Map) && (d['deliverable_type'] == 'pre' || d['type'] == 'pre'))
                    .length;
                final postCount = delivs
                    .where((d) =>
                        (d is Map) &&
                        (d['deliverable_type'] == 'post' || d['deliverable_type'] == 'vault' || d['type'] == 'post'))
                    .length;

                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
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
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _codeTag(stage['code']?.toString() ?? ''),
                          if (stage['is_presentation_only'] == true)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.record_voice_over_rounded, size: 12, color: Color(0xFF2563EB)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Oral / Demo Only',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1D4ED8),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            _deliverableCategoryBadge(
                              label: 'Pre-defense',
                              count: preCount,
                              icon: Icons.folder_open_rounded,
                              color: const Color(0xFF2563EB),
                              bgColor: const Color(0xFFEFF6FF),
                              borderColor: const Color(0xFFBFDBFE),
                              compact: true,
                            ),
                            _deliverableCategoryBadge(
                              label: 'Post-defense',
                              count: postCount,
                              icon: Icons.inventory_2_rounded,
                              color: AppColors.maroon,
                              bgColor: const Color(0xFFFFF1F2),
                              borderColor: const Color(0xFFFECDD3),
                              compact: true,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      _previousStageCell(stage),
                      const SizedBox(height: 10),
                      _buildStageActions(state, stage, i, state.stages.length),
                    ],
                  ),
                );
              },
            ),
          ],
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
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (stage['description']?.toString().isNotEmpty == true) ...[
          const SizedBox(height: 2),
          Text(
            stage['description'].toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ],
      ],
    );
  }

  Widget _previousStageCell(Map<String, dynamic> stage) {
    final previous = stage['previous_stage_label']?.toString();

    if (previous == null || previous.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag_outlined, size: 11, color: Color(0xFF64748B)),
            SizedBox(width: 4),
            Text(
              'Initial Stage',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: Color(0xFF94A3B8)),
        const SizedBox(width: 4),
        Flexible(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                previous,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (stage['previous_stage_code']?.toString().isNotEmpty == true) ...[
                const SizedBox(height: 1),
                Text(
                  stage['previous_stage_code'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: Color(0xFF64748B),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMoreActionsMenu({
    required DefenseStagesState state,
    required Map<String, dynamic> stage,
    required int? stageId,
    required bool locked,
    required bool published,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.1),
        ),
      ),
      child: PopupMenuButton<String>(
        tooltip: 'More actions',
        icon: Container(
          width: 32,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Icon(
            Icons.more_horiz_rounded,
            size: 17,
            color: AppColors.textPrimary,
          ),
        ),
        padding: EdgeInsets.zero,
        offset: const Offset(0, 36),
        onSelected: (value) {
          if (stageId == null) return;
          switch (value) {
            case 'view':
            case 'edit':
              _openStageEditor(stage);
              break;
            case 'publish':
              ref.read(defenseStagesProvider.notifier).updateStage(stageId, {
                'label': stage['label'],
                'display_order': stage['display_order'],
                'description': stage['description'] ?? '',
                'is_active': true,
              });
              break;
            case 'delete':
              _confirmDelete(stageId, stage['label']?.toString() ?? 'stage');
              break;
          }
        },
        itemBuilder: (context) => [
          if (locked)
            const PopupMenuItem<String>(
              value: 'view',
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.visibility_outlined, size: 15, color: Color(0xFF2563EB)),
                  SizedBox(width: 9),
                  Text('View Details', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ],
              ),
            )
          else ...[
            const PopupMenuItem<String>(
              value: 'edit',
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 15, color: AppColors.textPrimary),
                  SizedBox(width: 9),
                  Text('Edit Configuration', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ],
              ),
            ),
            if (!published)
              const PopupMenuItem<String>(
                value: 'publish',
                height: 36,
                child: Row(
                  children: [
                    Icon(Icons.send_rounded, size: 15, color: Color(0xFF047857)),
                    SizedBox(width: 9),
                    Text('Publish', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF047857))),
                  ],
                ),
              ),
            const PopupMenuDivider(height: 1),
            const PopupMenuItem<String>(
              value: 'delete',
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded, size: 15, color: AppColors.danger),
                  SizedBox(width: 9),
                  Text('Delete Stage', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.danger)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStageActions(
    DefenseStagesState state,
    Map<String, dynamic> stage,
    int index,
    int totalStages,
  ) {
    final stageId = _asInt(stage['id']);
    if (stageId == null) return const SizedBox.shrink();

    final status = _stageStatus(stage);
    final locked = status == 'locked';
    final published = status == 'published';

    final prevStage = index > 0 ? state.stages[index - 1] : null;
    final prevIsLocked = prevStage != null && _stageStatus(prevStage) == 'locked';
    final nextStage = index < totalStages - 1 ? state.stages[index + 1] : null;
    final nextIsLocked = nextStage != null && _stageStatus(nextStage) == 'locked';

    final canMoveUp = index > 0 && !locked && !prevIsLocked && !state.isSaving;
    final canMoveDown = index < totalStages - 1 && !locked && !nextIsLocked && !state.isSaving;

    String upTooltip;
    if (locked) {
      upTooltip = 'Completed stages cannot be reordered';
    } else if (prevIsLocked) {
      upTooltip = 'Cannot move before completed milestone (${prevStage['label'] ?? "Completed Stage"})';
    } else if (index == 0) {
      upTooltip = 'Already at Start';
    } else {
      upTooltip = 'Move Up (▲)';
    }

    String downTooltip;
    if (locked) {
      downTooltip = 'Completed stages cannot be reordered';
    } else if (nextIsLocked) {
      downTooltip = 'Cannot move past completed milestone (${nextStage['label'] ?? "Completed Stage"})';
    } else if (index >= totalStages - 1) {
      downTooltip = 'Already at End';
    } else {
      downTooltip = 'Move Down (▼)';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Reorder quick controls
        if (totalStages > 1) ...[
          Container(
            height: 30,
            decoration: BoxDecoration(
              color: locked ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: upTooltip,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 13),
                  color: canMoveUp ? AppColors.textPrimary : const Color(0xFFCBD5E1),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: canMoveUp
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
                  tooltip: downTooltip,
                  icon: const Icon(Icons.arrow_downward_rounded, size: 13),
                  color: canMoveDown ? AppColors.textPrimary : const Color(0xFFCBD5E1),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: canMoveDown
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
          const SizedBox(width: 6),
        ],
        // More Options 3-Dots Button
        _buildMoreActionsMenu(
          state: state,
          stage: stage,
          stageId: stageId,
          locked: locked,
          published: published,
        ),
      ],
    );
  }


  InputDecoration _dialogInputDecoration({
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
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
      hintStyle: const TextStyle(
        fontSize: 13,
        color: Color(0xFF94A3B8),
      ),
      helperStyle: const TextStyle(
        fontSize: 11,
        color: AppColors.textSecondary,
      ),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
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

  Widget _buildDialogTabBar({
    required int activeTab,
    required int deliverableCount,
    required int totalWeight,
    required void Function(int) onTabSelected,
    bool isPresentationOnly = false,
  }) {
    final hasWeightError = totalWeight != 100;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          _buildDialogTabItem(
            index: 0,
            label: '1. Stage Details',
            icon: Icons.account_tree_rounded,
            isSelected: activeTab == 0,
            onTap: () => onTabSelected(0),
          ),
          const SizedBox(width: 4),
          _buildDialogTabItem(
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
          _buildDialogTabItem(
            index: 2,
            label: '3. Deliverables',
            icon: Icons.inventory_2_rounded,
            badge: isPresentationOnly
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: activeTab == 2
                          ? Colors.white.withValues(alpha: 0.25)
                          : const Color(0xFFE0E7FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Oral / Demo',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: activeTab == 2 ? Colors.white : const Color(0xFF4338CA),
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

  Widget _buildDialogTabItem({
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

  Widget _buildSubmissionModeSelector({
    required bool isPresentationOnly,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 16, color: AppColors.maroon),
              const SizedBox(width: 8),
              const Text(
                'Stage Submission Mode',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _submissionModeCard(
                  title: 'Document Submissions Required',
                  description:
                      'Standard defense milestone. Requires student files for endorsement and archiving.',
                  icon: Icons.description_rounded,
                  selected: !isPresentationOnly,
                  onTap: () => onChanged(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _submissionModeCard(
                  title: 'Presentation / Demo Only',
                  description:
                      'Oral defense, pitch, or expo only — no student file uploads required.',
                  icon: Icons.co_present_rounded,
                  selected: isPresentationOnly,
                  onTap: () => onChanged(true),
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
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? (title.contains('Presentation')
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFFAF5FF))
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
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
              size: 16,
              color: selected
                  ? (title.contains('Presentation')
                      ? const Color(0xFF16A34A)
                      : AppColors.maroon)
                  : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 14, color: AppColors.textPrimary),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.25,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Color(0xFF15803D),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Presentation / Demo Mode Active',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF14532D),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'This milestone does not require document submissions.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF166534),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '• Students will not be prompted to upload manuscripts or archive files for this stage.\n'
            '• Advisers can endorse teams directly based on verbal presentation or demo readiness.\n'
            '• Administrators can schedule defenses freely once endorsed.',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF166534),
              height: 1.35,
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
    required List<Map<String, dynamic>> allDeliverables,
    required void Function(void Function()) setDialogState,
    required TextEditingController stageLabelCtrl,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bgHeaderColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 15, color: accentColor),
                ),
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
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: accentColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onAdd,
                  icon: Icon(Icons.add_rounded, size: 14, color: accentColor),
                  label: Text(buttonText),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accentColor,
                    side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: items.isEmpty
                ? InkWell(
                    onTap: onAdd,
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
                    children: items.asMap().entries.map((entry) {
                      return _buildDeliverableItemCard(
                        index: entry.key + 1,
                        item: entry.value,
                        isPost: isPost,
                        allDeliverables: allDeliverables,
                        setDialogState: setDialogState,
                        stageLabelCtrl: stageLabelCtrl,
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliverableItemCard({
    required int index,
    required Map<String, dynamic> item,
    required bool isPost,
    required List<Map<String, dynamic>> allDeliverables,
    required void Function(void Function()) setDialogState,
    required TextEditingController stageLabelCtrl,
  }) {
    const legacyDefault = '{year}.{course}.{project}.{stage}.{deliverable}.{semester}';
    final existingTpl = item['archive_file_template']?.toString().trim() ?? '';
    if (isPost && (existingTpl.isEmpty || existingTpl == legacyDefault)) {
      item['archive_file_template'] = '{project}';
    }

    final labelController = item['_labelController'] as TextEditingController? ??
        (item['_labelController'] = TextEditingController(text: item['label']?.toString() ?? ''));
    final templateController = item['_templateController'] as TextEditingController? ??
        (item['_templateController'] = TextEditingController(
          text: item['archive_file_template']?.toString() ?? (isPost ? '{project}' : ''),
        ));

    if (isPost && templateController.text.trim() == legacyDefault) {
      templateController.text = '{project}';
      item['archive_file_template'] = '{project}';
    }

    final accentColor = isPost ? AppColors.maroon : const Color(0xFF2563EB);
    final isArchiveExpanded = item['_isArchiveExpanded'] == true;
    final currentFormat = (item['file_format']?.toString().isNotEmpty == true)
        ? item['file_format'].toString()
        : 'any';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                  onPressed: () {
                    setDialogState(() {
                      allDeliverables.remove(item);
                      (item['_labelController'] as TextEditingController?)?.dispose();
                      (item['_templateController'] as TextEditingController?)?.dispose();
                    });
                  },
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 18),
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
                        decoration: _dialogInputDecoration(
                          labelText: isPost ? 'Post-Defense Deliverable Name *' : 'Pre-Defense Deliverable Name *',
                          hintText: isPost
                              ? 'e.g. Final Manuscript PDF, Source Code Archive'
                              : 'e.g. Concept Paper Draft, Similarity Report',
                        ),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        onChanged: (value) {
                          item['label'] = value.trim();
                          setDialogState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      height: 42,
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
                          onChanged: (val) {
                            setDialogState(() {
                              item['file_format'] = val ?? 'any';
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      height: 42,
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
                            onChanged: (value) {
                              setDialogState(() {
                                item['required'] = value == true;
                              });
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
                        onChanged: (value) {
                          setDialogState(() {
                            item['is_defense_material'] = value == true;
                          });
                        },
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Defense Material (Evaluated by Defense Panelists)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
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
                        onChanged: (value) {
                          setDialogState(() {
                            item['is_restricted'] = value == true;
                          });
                        },
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Restricted / Private in Institutional Archive',
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
                            onChanged: (val) {
                              setDialogState(() {
                                item['verdict_condition'] = val ?? 'all_pass';
                              });
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

                  // Progressive Disclosure Drawer for Archive Naming
                  InkWell(
                    onTap: () {
                      setDialogState(() {
                        item['_isArchiveExpanded'] = !isArchiveExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: isArchiveExpanded ? const Color(0xFFFFF1F2) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isArchiveExpanded ? const Color(0xFFFECDD3) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 14,
                            color: isArchiveExpanded ? AppColors.maroon : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Archive Naming & File Pattern',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: isArchiveExpanded ? AppColors.maroon : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Text(
                              templateController.text.trim().isNotEmpty
                                  ? templateController.text.trim()
                                  : '{project}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontFamily: 'monospace',
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            isArchiveExpanded ? 'Hide' : 'Configure',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isArchiveExpanded ? AppColors.maroon : const Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            isArchiveExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: isArchiveExpanded ? AppColors.maroon : const Color(0xFF64748B),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (isArchiveExpanded) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Builder(builder: (context) {
                            final currentTemplate = templateController.text.trim();
                            final varMatches = RegExp(r'\{[a-zA-Z0-9_]+\}').allMatches(currentTemplate);
                            final varCount = varMatches.length;
                            final isOverLimit = varCount > 3;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextFormField(
                                  controller: templateController,
                                  decoration: _dialogInputDecoration(
                                    labelText: 'Archive Naming Template',
                                    hintText: 'e.g. {project}',
                                    helperText: isOverLimit
                                        ? null
                                        : 'Default is {project}. Max 3 variables allowed for phone file names.',
                                    errorText: isOverLimit
                                        ? 'Exceeds limit of 3 variables ($varCount/3). Shorten for phone file name limit.'
                                        : null,
                                    suffixIcon: Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Center(
                                        widthFactor: 1.0,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isOverLimit
                                                ? AppColors.danger.withValues(alpha: 0.1)
                                                : AppColors.maroon.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isOverLimit
                                                  ? AppColors.danger.withValues(alpha: 0.3)
                                                  : AppColors.maroon.withValues(alpha: 0.2),
                                            ),
                                          ),
                                          child: Text(
                                            '$varCount/3 tags',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: isOverLimit ? AppColors.danger : AppColors.maroon,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      item['archive_file_template'] = value.trim();
                                    });
                                  },
                                ),
                                const SizedBox(height: 5),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: ['{year}', '{course}', '{project}', '{stage}', '{deliverable}', '{semester}']
                                      .map((varName) {
                                        final isReached = varCount >= 3;
                                        return ActionChip(
                                          label: Text(
                                            varName,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          labelStyle: TextStyle(
                                            color: isReached ? Colors.grey.shade600 : AppColors.maroon,
                                          ),
                                          backgroundColor: isReached
                                              ? Colors.grey.shade100
                                              : AppColors.maroon.withValues(alpha: 0.05),
                                          side: BorderSide(
                                            color: isReached
                                                ? Colors.grey.shade300
                                                : AppColors.maroon.withValues(alpha: 0.15),
                                          ),
                                          padding: EdgeInsets.zero,
                                          visualDensity: VisualDensity.compact,
                                          tooltip: isReached
                                              ? 'Maximum 3 variables limit reached'
                                              : 'Insert $varName',
                                          onPressed: () => _insertVariable(item, templateController, varName, setDialogState),
                                        );
                                      })
                                      .toList(),
                                ),
                              ],
                            );
                          }),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.maroon.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.maroon.withValues(alpha: 0.12)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(Icons.remove_red_eye_outlined, size: 12, color: AppColors.maroon),
                                    SizedBox(width: 4),
                                    Text(
                                      'Filename Preview',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.maroon,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  _resolvePreview(
                                    item['archive_file_template']?.toString() ?? '',
                                    item['label']?.toString() ?? '',
                                    stageLabelCtrl.text,
                                    format: item['file_format']?.toString() ?? 'any',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 11,
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showStageDialog([Map<String, dynamic>? stage]) async {
    final editing = stage != null;

    // Fetch periods for grade composition weights
    await ref.read(academicPeriodProvider.notifier).fetchPeriods();
    // Fetch capstone rubrics (published ones are filtered client-side for dropdowns)
    await ref.read(rubricEngineProvider.notifier).fetchRubrics(
          scope: 'capstone',
          status: '',
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
    final stageIsLocked = editing && (_stageStatus(stage) == 'locked' || stage['is_locked'] == true);
    final lockReason = stage?['lock_reason']?.toString();

    // Calculate the highest order of completed stages
    int lastCompletedOrder = 0;
    for (int i = 0; i < existingStages.length; i++) {
      final s = existingStages[i];
      if (_stageStatus(s) == 'locked') {
        final order = _asInt(s['display_order']) ?? (i + 1);
        if (order > lastCompletedOrder) {
          lastCompletedOrder = order;
        }
      }
    }

    final minPosition = stageIsLocked
        ? (currentOrder ?? 1)
        : (lastCompletedOrder + 1);

    int selectedPosition = editing
        ? (currentOrder ?? 1).clamp(1, totalExisting > 0 ? totalExisting : 1)
        : (totalExisting + 1);

    if (selectedPosition < minPosition) {
      selectedPosition = minPosition;
    }
    final panelCtrl = TextEditingController(text: '50');
    final adviserCtrl = TextEditingController(text: '30');
    final peerCtrl = TextEditingController(text: '20');
    var isActive = stage?['is_active'] != false;
    var isPresentationOnly = stage?['is_presentation_only'] == true;

    int? panelRubricId;
    int? adviserRubricId;
    int? peerRubricId;

    if (stage != null) {
      final gc = (stage['grading_config'] is Map) ? stage['grading_config'] as Map : stage;
      if (gc['panel_weight'] != null) panelCtrl.text = gc['panel_weight'].toString();
      if (gc['adviser_weight'] != null) adviserCtrl.text = gc['adviser_weight'].toString();
      if (gc['peer_weight'] != null) peerCtrl.text = gc['peer_weight'].toString();
      panelRubricId = _asInt(gc['panel_rubric_id']);
      adviserRubricId = _asInt(gc['adviser_rubric_id']);
      peerRubricId = _asInt(gc['peer_rubric_id']);
    }

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

    int activeTab = 0;

    await ref.read(rubricEngineProvider.notifier).fetchRubrics(
          scope: 'capstone',
          status: '',
        );

    if (!mounted) return;
    bool? saved;
    try {
      saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final panelVal = int.tryParse(panelCtrl.text.trim()) ?? 0;
              final adviserVal = int.tryParse(adviserCtrl.text.trim()) ?? 0;
              final peerVal = int.tryParse(peerCtrl.text.trim()) ?? 0;
              final total = panelVal + adviserVal + peerVal;

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
                          fontSize: 13,
                        ),
                      ),
                    );
                  }

                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text(
                      r['name']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList();

                items.insert(
                  0,
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text(
                      'None (No Rubric Assigned)',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                  ),
                );

                return items;
              }

              final preDeliverables = deliverables.where((d) => d['deliverable_type'] == 'pre').toList();
              final postDeliverables = deliverables.where((d) => d['deliverable_type'] == 'post').toList();

              return Dialog(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 960,
                    maxHeight: MediaQuery.of(dialogContext).size.height * 0.90,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Dialog Header
                      Container(
                        padding: const EdgeInsets.fromLTRB(24, 18, 16, 12),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.maroon.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.account_tree_rounded, size: 20, color: AppColors.maroon),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    editing ? 'Edit Defense Stage' : 'Add Defense Stage',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.textPrimary,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Configure lifecycle sequence, role grading weights, and submission requirements.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                              tooltip: 'Close',
                              style: IconButton.styleFrom(
                                hoverColor: const Color(0xFFF1F5F9),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Segmented Step Tab Bar
                      _buildDialogTabBar(
                        activeTab: activeTab,
                        deliverableCount: deliverables.length,
                        totalWeight: total,
                        isPresentationOnly: isPresentationOnly,
                        onTabSelected: (index) {
                          setDialogState(() => activeTab = index);
                        },
                      ),

                      // Scrollable Tab Content
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                          child: IndexedStack(
                            index: activeTab,
                            children: [
                              // TAB 0: Stage Identity & Pipeline Flow
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: TextField(
                                          controller: label,
                                          decoration: _dialogInputDecoration(
                                            labelText: 'Stage Name',
                                            hintText: 'e.g. Concept Proposal, Colloquium, Final Defense',
                                          ),
                                          onChanged: (_) => setDialogState(() {}),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: TextField(
                                          controller: codeCtrl,
                                          decoration: _dialogInputDecoration(
                                            labelText: 'Stage Code',
                                            hintText: 'e.g. CAPS101',
                                            helperText: 'Unique system identifier',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: PipelinePositionSelector(
                                      selectedPosition: selectedPosition,
                                      totalSlots: editing ? totalExisting : totalExisting + 1,
                                      existingStages: existingStages,
                                      currentStageName: label.text,
                                      editing: editing,
                                      initialOrder: currentOrder,
                                      isLocked: stageIsLocked,
                                      minPosition: minPosition,
                                      lockReason: lockReason,
                                      onPositionChanged: (val) {
                                        setDialogState(() => selectedPosition = val);
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: description,
                                    minLines: 2,
                                    maxLines: 3,
                                    decoration: _dialogInputDecoration(
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
                                      value: isActive,
                                      onChanged: (value) {
                                        setDialogState(() {
                                          isActive = value;
                                        });
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
                                    padding: const EdgeInsets.all(16),
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
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const Spacer(),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF1F5F9),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.calendar_today_rounded, size: 11, color: Color(0xFF475569)),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    activeSemesterName,
                                                    style: const TextStyle(
                                                      fontSize: 11.5,
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
                                          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                                        ),
                                        const SizedBox(height: 14),
                                        _buildWeightDistributionBar(panelVal, adviserVal, peerVal),
                                        const SizedBox(height: 14),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: panelCtrl,
                                                keyboardType: TextInputType.number,
                                                decoration: _dialogInputDecoration(
                                                  labelText: 'Panel %',
                                                  prefixIcon: const Icon(Icons.gavel_rounded, size: 16, color: AppColors.maroon),
                                                ),
                                                onChanged: (_) => setDialogState(() {}),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: TextField(
                                                controller: adviserCtrl,
                                                keyboardType: TextInputType.number,
                                                decoration: _dialogInputDecoration(
                                                  labelText: 'Adviser %',
                                                  prefixIcon: const Icon(Icons.school_rounded, size: 16, color: Color(0xFFD97706)),
                                                ),
                                                onChanged: (_) => setDialogState(() {}),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: TextField(
                                                controller: peerCtrl,
                                                keyboardType: TextInputType.number,
                                                decoration: _dialogInputDecoration(
                                                  labelText: 'Peer %',
                                                  prefixIcon: const Icon(Icons.people_outline_rounded, size: 16, color: Color(0xFF0D9488)),
                                                ),
                                                onChanged: (_) => setDialogState(() {}),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                            onPressed: () {
                                              setDialogState(() {
                                                panelCtrl.text = '50';
                                                adviserCtrl.text = '30';
                                                peerCtrl.text = '20';
                                              });
                                            },
                                            icon: const Icon(Icons.restore_rounded, size: 15),
                                            label: const Text('Reset to standard 50 / 30 / 20'),
                                            style: TextButton.styleFrom(
                                              foregroundColor: const Color(0xFF475569),
                                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // 2. Evaluation Rubrics Assignment Card
                                  Builder(
                                    builder: (context) {
                                      final panelOpts = getRubricOptions('panel');
                                      final adviserOpts = getRubricOptions('adviser');
                                      final peerOpts = getRubricOptions('peer');
                                      final hasNoRubricsAtAll = panelOpts.isEmpty &&
                                          adviserOpts.isEmpty &&
                                          peerOpts.isEmpty;

                                      return Container(
                                        padding: const EdgeInsets.all(16),
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
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: AppColors.textPrimary,
                                                  ),
                                                ),
                                                const Spacer(),
                                                OutlinedButton.icon(
                                                  onPressed: () {
                                                    Navigator.pop(dialogContext, false);
                                                    context.push(AdminRoutes.rubrics);
                                                  },
                                                  icon: const Icon(Icons.open_in_new_rounded, size: 13),
                                                  label: const Text('Manage in Rubrics'),
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: AppColors.maroon,
                                                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            const Text(
                                              'Assign published Capstone rubrics to evaluate each role (optional; can attach later before defense scheduling).',
                                              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                                            ),
                                            if (hasNoRubricsAtAll) ...[
                                              const SizedBox(height: 12),
                                              Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFFFBEB),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFB45309)),
                                                    const SizedBox(width: 8),
                                                    const Expanded(
                                                      child: Text(
                                                        'No published Capstone rubrics found for this semester. Create rubrics in Evaluation Rubrics to attach.',
                                                        style: TextStyle(
                                                          fontSize: 11.5,
                                                          color: Color(0xFF92400E),
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    ElevatedButton.icon(
                                                      onPressed: () {
                                                        Navigator.pop(dialogContext, false);
                                                        context.push(AdminRoutes.rubrics);
                                                      },
                                                      icon: const Icon(Icons.add_rounded, size: 13),
                                                      label: const Text('Create Rubric'),
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: const Color(0xFFB45309),
                                                        foregroundColor: Colors.white,
                                                        elevation: 0,
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 14),
                                            DropdownButtonFormField<int>(
                                              initialValue: panelRubricId,
                                              decoration: _dialogInputDecoration(
                                                labelText: 'Panel Rubric',
                                                prefixIcon: const Icon(Icons.gavel_rounded, size: 16, color: AppColors.maroon),
                                              ),
                                              items: buildRubricDropdownItems('panel'),
                                              onChanged: (val) => setDialogState(() => panelRubricId = val),
                                            ),
                                            const SizedBox(height: 12),
                                            DropdownButtonFormField<int>(
                                              initialValue: adviserRubricId,
                                              decoration: _dialogInputDecoration(
                                                labelText: 'Adviser Rubric',
                                                prefixIcon: const Icon(Icons.school_rounded, size: 16, color: Color(0xFFD97706)),
                                              ),
                                              items: buildRubricDropdownItems('adviser'),
                                              onChanged: (val) => setDialogState(() => adviserRubricId = val),
                                            ),
                                            const SizedBox(height: 12),
                                            DropdownButtonFormField<int>(
                                              initialValue: peerRubricId,
                                              decoration: _dialogInputDecoration(
                                                labelText: 'Peer Rubric',
                                                prefixIcon: const Icon(Icons.people_outline_rounded, size: 16, color: Color(0xFF0D9488)),
                                              ),
                                              items: buildRubricDropdownItems('peer'),
                                              onChanged: (val) => setDialogState(() => peerRubricId = val),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),

                              // TAB 2: Deliverables Split (Pre-Defense vs. Post-Defense)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSubmissionModeSelector(
                                    isPresentationOnly: isPresentationOnly,
                                    onChanged: (val) {
                                      setDialogState(() => isPresentationOnly = val);
                                    },
                                  ),
                                  if (isPresentationOnly)
                                    _buildPresentationOnlyInfoBanner()
                                  else ...[
                                    // Pre-Defense Gatekeepers
                                    _buildDeliverableSection(
                                      title: 'Pre-Defense Gatekeepers',
                                      subtitle: 'Submissions required before adviser endorsement and defense scheduling.',
                                      icon: Icons.folder_open_rounded,
                                      accentColor: const Color(0xFF2563EB),
                                      bgHeaderColor: const Color(0xFFEFF6FF),
                                      borderColor: const Color(0xFFBFDBFE),
                                      count: preDeliverables.length,
                                      buttonText: 'Add Pre-Defense',
                                      onAdd: () {
                                        setDialogState(() {
                                          deliverables.add({
                                            'deliverable_id': 'D${deliverables.length + 1}',
                                            'label': '',
                                            'deliverable_type': 'pre',
                                            'required': true,
                                            'display_order': deliverables.length + 1,
                                            'archive_note': '',
                                            'archive_file_template': '',
                                            'is_restricted': false,
                                             'is_defense_material': false,
                                             'verdict_condition': 'all_pass',
                                          });
                                        });
                                      },
                                      emptyPlaceholderText: 'No pre-defense gatekeepers configured yet. (e.g. Proposal Manuscript Draft, Similarity Report)',
                                      items: preDeliverables,
                                      isPost: false,
                                      allDeliverables: deliverables,
                                      setDialogState: setDialogState,
                                      stageLabelCtrl: label,
                                    ),

                                    const SizedBox(height: 16),

                                    // Post-Defense Requirements & Archive
                                    _buildDeliverableSection(
                                      title: 'Post-Defense Requirements & Archive',
                                      subtitle: 'Deliverables required for milestone clearance and repository archiving.',
                                      icon: Icons.inventory_2_rounded,
                                      accentColor: AppColors.maroon,
                                      bgHeaderColor: const Color(0xFFFFF1F2),
                                      borderColor: const Color(0xFFFECDD3),
                                      count: postDeliverables.length,
                                      buttonText: 'Add Post-Defense',
                                      onAdd: () {
                                        setDialogState(() {
                                          deliverables.add({
                                            'deliverable_id': 'D${deliverables.length + 1}',
                                            'label': '',
                                            'deliverable_type': 'post',
                                            'required': true,
                                            'display_order': deliverables.length + 1,
                                            'archive_note': '',
                                            'archive_file_template': '{project}',
                                            'is_restricted': false,
                                             'is_defense_material': false,
                                             'verdict_condition': 'all_pass',
                                          });
                                        });
                                      },
                                      emptyPlaceholderText: 'No post-defense deliverables configured yet. (e.g. Final Manuscript PDF, Source Code Zip, Demo Video)',
                                      items: postDeliverables,
                                      isPost: true,
                                      allDeliverables: deliverables,
                                      setDialogState: setDialogState,
                                      stageLabelCtrl: label,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Footer Actions Bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8FAFC),
                          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: Row(
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF64748B),
                                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              child: const Text('Cancel'),
                            ),
                            const Spacer(),
                            if (activeTab > 0) ...[
                              OutlinedButton.icon(
                                onPressed: () {
                                  setDialogState(() => activeTab--);
                                },
                                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                                label: const Text('Back'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.textPrimary,
                                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            if (activeTab < 2)
                              ElevatedButton.icon(
                                onPressed: () {
                                  if (activeTab == 0 && label.text.trim().isEmpty) {
                                    showValidationToast(context, 'Please enter a stage name before proceeding.');
                                    return;
                                  }
                                  if (activeTab == 1 && !editing && total != 100) {
                                    showValidationToast(context, 'Panel, Adviser, and Peer weights must total 100%.');
                                    return;
                                  }
                                  setDialogState(() => activeTab++);
                                },
                                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                                label: Text(activeTab == 0 ? 'Next: Grading & Rubrics' : 'Next: Deliverables'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.maroon,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              )
                            else
                              ElevatedButton.icon(
                                onPressed: () {
                                  final stageName = label.text.trim();
                                  if (stageName.isEmpty) {
                                    setDialogState(() => activeTab = 0);
                                    showValidationToast(context, 'Enter a stage name.');
                                    return;
                                  }
                                  if (!editing) {
                                    if (semesterId == null) {
                                      setDialogState(() => activeTab = 1);
                                      showValidationToast(context, 'Select a semester.');
                                      return;
                                    }
                                    if (total != 100) {
                                      setDialogState(() => activeTab = 1);
                                      showValidationToast(context, 'Panel, Adviser, and Peer weights must total 100%.');
                                      return;
                                    }
                                  }
                                  if (!isPresentationOnly) {
                                    for (int i = 0; i < deliverables.length; i++) {
                                      final dLabel = deliverables[i]['label']?.toString().trim() ?? '';
                                      if (dLabel.isEmpty) {
                                        setDialogState(() => activeTab = 2);
                                        showValidationToast(context, 'Deliverable name cannot be empty (item ${i + 1}).');
                                        return;
                                      }
                                      if (deliverables[i]['deliverable_type'] == 'post') {
                                        final tpl = (deliverables[i]['archive_file_template'] ?? '').toString().trim();
                                        final vCount = RegExp(r'\{[a-zA-Z0-9_]+\}').allMatches(tpl).length;
                                        if (vCount > 3) {
                                          setDialogState(() => activeTab = 2);
                                          showValidationToast(context, 'Deliverable "$dLabel" template exceeds 3 variables ($vCount used). Limit is 3 for phone file names.');
                                          return;
                                        }
                                      }
                                    }
                                  }
                                  Navigator.pop(dialogContext, true);
                                },
                                icon: const Icon(Icons.save_rounded, size: 16),
                                label: Text(editing ? 'Save Changes' : 'Add Stage'),
                                style: DefensysTokens.saveButtonStyle(
                                  isPill: false,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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

    final endorsedCount = stage != null ? (_asInt(stage['endorsed_teams_count']) ?? 0) : 0;
    String? endorsedAction;

    if (editing && currentOrder != null && currentOrder != selectedPosition && endorsedCount > 0) {
      endorsedAction = await showEndorsedStageResolutionDialog(
        context: context,
        stageLabel: label.text.trim().isEmpty ? (stage['label']?.toString() ?? 'Stage') : label.text.trim(),
        endorsedCount: endorsedCount,
        targetPosition: selectedPosition,
      );
      if (!mounted || endorsedAction == null) {
        return;
      }
    }

    final payload = {
      'label': label.text.trim(),
      'code': codeCtrl.text.trim(),
      'display_order': selectedPosition,
      'description': description.text.trim(),
      'is_active': isActive,
      'is_presentation_only': isPresentationOnly,
      'deliverables': isPresentationOnly ? [] : deliverables,
      if (endorsedAction != null) 'endorsed_teams_action': endorsedAction,
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

  void _insertVariable(
    Map<String, dynamic> item,
    TextEditingController controller,
    String variable,
    void Function(void Function()) setDialogState,
  ) {
    final text = controller.text;
    final selection = controller.selection;

    int varCount = RegExp(r'\{[a-zA-Z0-9_]+\}').allMatches(text).length;
    if (selection.isValid && !selection.isCollapsed) {
      final selectedText = text.substring(selection.start, selection.end);
      final replacedVars = RegExp(r'\{[a-zA-Z0-9_]+\}').allMatches(selectedText).length;
      varCount -= replacedVars;
    }

    if (varCount >= 3) {
      showValidationToast(context, 'Maximum 3 variables allowed for mobile phone file name limits.');
      return;
    }

    String newText;
    int newCursorPosition;

    if (selection.isValid && !selection.isCollapsed) {
      final start = selection.start;
      final end = selection.end;
      newText = text.replaceRange(start, end, variable);
      newCursorPosition = start + variable.length;
    } else {
      final insertPos = (selection.isValid && selection.isCollapsed)
          ? selection.start
          : text.length;
      final before = text.substring(0, insertPos);
      final after = text.substring(insertPos);

      String inserted = variable;
      if (before.trim().isNotEmpty && !before.trim().endsWith('.')) {
        inserted = '.$variable';
      }
      if (after.trim().isNotEmpty && !after.trim().startsWith('.')) {
        inserted = '$inserted.';
      }

      newText = before + inserted + after;
      newCursorPosition = before.length + inserted.length;
    }

    setDialogState(() {
      controller.text = newText;
      controller.selection = TextSelection.collapsed(offset: newCursorPosition);
      item['archive_file_template'] = newText;
    });
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

  String _resolvePreview(String template, String deliverableLabel, String stageLabel, {String format = 'any'}) {
    final cleanTemplate = template.trim();
    final finalTemplate = cleanTemplate.isEmpty 
        ? '{project}'
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

    const year = '3rdYear';
    const course = 'CAP301';
    const project = 'ProjectTitle';
    final stage = slugify(stageLabel.trim().isEmpty ? 'StageLabel' : stageLabel.trim());
    final deliverable = deliverableSlug(deliverableLabel);
    const semester = '2ndSemester';

    var resolved = finalTemplate
        .replaceAll('{year}', year)
        .replaceAll('{course}', course)
        .replaceAll('{project}', project)
        .replaceAll('{stage}', stage)
        .replaceAll('{deliverable}', deliverable)
        .replaceAll('{semester}', semester);

    String defaultExt;
    switch (format) {
      case 'pdf':
        defaultExt = '.pdf';
        break;
      case 'video':
        defaultExt = '.mp4';
        break;
      case 'image':
        defaultExt = '.png';
        break;
      case 'presentation':
        defaultExt = '.pptx';
        break;
      case 'document':
        defaultExt = '.docx';
        break;
      case 'spreadsheet':
        defaultExt = '.xlsx';
        break;
      case 'archive':
        defaultExt = '.zip';
        break;
      case 'audio':
        defaultExt = '.mp3';
        break;
      default:
        defaultExt = '.pdf';
    }

    if (!resolved.contains('.')) {
      resolved += defaultExt;
    }

    return resolved;
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

    final movingStage = allStages[currentIndex];
    final targetStage = allStages[targetIndex];

    if (_stageStatus(movingStage) == 'locked' || _stageStatus(targetStage) == 'locked') {
      showErrorToast(context, 'Completed stages cannot be reordered.');
      return;
    }

    final targetStageName = allStages[targetIndex]['label']?.toString() ?? 'the adjacent stage';
    final movingUp = delta < 0;
    final endorsedCount = _asInt(movingStage['endorsed_teams_count']) ?? 0;
    String? endorsedAction;

    if (endorsedCount > 0) {
      endorsedAction = await showEndorsedStageResolutionDialog(
        context: context,
        stageLabel: stageLabel,
        endorsedCount: endorsedCount,
        targetPosition: targetIndex + 1,
      );
      if (!mounted || endorsedAction == null) return;
    } else {
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
    }

    await ref.read(defenseStagesProvider.notifier).moveStage(
      stageId,
      delta,
      endorsedTeamsAction: endorsedAction,
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
        'Completed',
        const Color(0xFFEFF6FF),
        const Color(0xFF1D4ED8),
        const Color(0xFFBFDBFE),
        icon: Icons.task_alt_rounded,
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
    double? chipMaxWidth,
  }) {
    return Container(
      constraints: chipMaxWidth != null
          ? BoxConstraints(maxWidth: chipMaxWidth)
          : const BoxConstraints(),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12.5, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: FontWeight.w800,
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

class _TimelineRailPainter extends CustomPainter {
  final bool isFirst;
  final bool isLast;
  final double nodeTop;
  final double nodeSize;

  static const Color _lineColor = Color(0xFFCBD5E1);

  _TimelineRailPainter({
    required this.isFirst,
    required this.isLast,
    this.nodeTop = 14.0,
    this.nodeSize = 36.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _lineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final centerX = size.width / 2;

    if (!isFirst) {
      canvas.drawLine(Offset(centerX, 0), Offset(centerX, nodeTop), paint);
    }

    if (!isLast) {
      canvas.drawLine(
        Offset(centerX, nodeTop + nodeSize),
        Offset(centerX, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineRailPainter oldDelegate) =>
      oldDelegate.isFirst != isFirst ||
      oldDelegate.isLast != isLast ||
      oldDelegate.nodeTop != nodeTop ||
      oldDelegate.nodeSize != nodeSize;
}
