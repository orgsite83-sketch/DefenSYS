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
import '../../../../widgets/repository/repository_archive_naming_panel.dart';
import 'defense_stage_editor_screen.dart';
import 'widgets/pipeline_position_selector.dart';
import 'widgets/defense_stage_directory.dart';
import 'widgets/stage_setup_confirmation.dart';
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

    return DefenseStageDirectory(
      state: state,
      onRefresh: () => ref.read(defenseStagesProvider.notifier).fetchStages(),
      onAdd: () => _showStageDialog(),
      onConfigure: _openStageEditor,
      onPublish: (stage) => ref
          .read(defenseStagesProvider.notifier)
          .updateStage(_asInt(stage['id'])!, {'is_active': true}),
      onDelete: (stage) => _confirmDelete(
        _asInt(stage['id'])!,
        stage['label']?.toString() ?? 'stage',
      ),
      onMove: (stage, index, delta) => _confirmMoveStage(
        stageId: _asInt(stage['id'])!,
        stageLabel: stage['label']?.toString() ?? 'Stage',
        delta: delta,
        currentIndex: index,
        allStages: state.stages,
      ),
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
                  // Smart Enterprise Repository Archiving Panel
                  RepositoryArchiveNamingPanel(
                    templateController: templateController,
                    deliverableLabel: labelController.text,
                    fileFormat: currentFormat,
                    isLocked: false,
                    isPit: false,
                    stageOrEventLabel: stageLabelCtrl.text,
                    siblingDeliverables: allDeliverables.where((d) => d['deliverable_type'] == (isPost ? 'post' : 'pre')).toList(),
                    currentIndex: allDeliverables.where((d) => d['deliverable_type'] == (isPost ? 'post' : 'pre')).toList().indexOf(item),
                    onChanged: () {
                      setDialogState(() {
                        item['archive_file_template'] = templateController.text.trim();
                      });
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
    final stageIsLocked = editing && stageSetupLocked(stage);
    final lockReason = stage?['lock_reason']?.toString();

    // Calculate the highest order of locked stages
    int lastLockedOrder = 0;
    for (int i = 0; i < existingStages.length; i++) {
      final s = existingStages[i];
      if (stageSetupLocked(s)) {
        final order = _asInt(s['display_order']) ?? (i + 1);
        if (order > lastLockedOrder) {
          lastLockedOrder = order;
        }
      }
    }

    final minPosition = stageIsLocked
        ? (currentOrder ?? 1)
        : (lastLockedOrder + 1);

    int selectedPosition = editing
        ? (currentOrder ?? 1).clamp(1, totalExisting > 0 ? totalExisting : 1)
        : (totalExisting + 1);

    if (selectedPosition < minPosition) {
      selectedPosition = minPosition;
    }
    final panelCtrl = TextEditingController(text: '50');
    final adviserCtrl = TextEditingController(text: '30');
    final peerCtrl = TextEditingController(text: '20');
    var isActive = stage?['is_active'] == true;
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
                                        'Published stages are available in defense scheduling. Leave unpublished while preparing setup.',
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
                                            'archive_file_template': postDeliverables.isEmpty ? '{project}' : '{project}_{deliverable}',
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

    if (stageSetupLocked(movingStage) || stageSetupLocked(targetStage)) {
      showErrorToast(context, 'Stages with scheduled defenses or recorded grades cannot be reordered.');
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
      final confirmed = await showStageSetupConfirmation(
        context,
        title: movingUp ? 'Move stage earlier?' : 'Move stage later?',
        description: movingUp
            ? 'Move "$stageLabel" before "$targetStageName"? This changes the stage sequence and prerequisite relationships.'
            : 'Move "$stageLabel" after "$targetStageName"? This changes the stage sequence and prerequisite relationships.',
        confirmLabel: movingUp ? 'Move earlier' : 'Move later',
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
    final confirmed = await showStageSetupConfirmation(
      context,
      title: 'Delete defense stage?',
      description: 'Delete "$label"? It will no longer be available in the defense sequence or scheduler.',
      confirmLabel: 'Delete stage',
      destructive: true,
    );

    if (!mounted || confirmed != true) {
      return;
    }

    await ref.read(defenseStagesProvider.notifier).deleteStage(stageId);
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();

    return int.tryParse(value?.toString() ?? '');
  }
}
