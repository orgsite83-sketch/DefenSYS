import 'package:defensys/widgets/repository/document_policy_editor.dart';
import '../../../../widgets/repository/shared_deliverables_editor.dart';
import '../../../../widgets/repository/deliverable_submission_settings.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/widgets/export/report_export_menu.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/defense_stages_provider.dart';
import '../../../../services/academic_period_provider.dart';
import '../../../../services/rubric_engine_provider.dart';
import '../../../../services/unsaved_changes_provider.dart';
import '../../../../services/auth_provider.dart';
import '../../../../utils/stage_setup_draft.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/repository/repository_archive_naming_panel.dart';
import '../../../../widgets/repository/deliverable_timing_fields.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../widgets/grading/grading_setup_section.dart';
import 'defense_stage_editor_screen.dart';
import 'widgets/pipeline_position_selector.dart';
import 'widgets/defense_stage_directory.dart';
import 'widgets/stage_setup_confirmation.dart';
import 'widgets/stage_minutes_settings.dart';
import 'widgets/stage_outcome_settings.dart';
import 'widgets/stage_setup_draft_notice.dart';
import 'widgets/stage_setup_actions.dart';
import 'widgets/stage_deliverable_overview.dart';
import 'widgets/stage_deliverable_choices.dart';
import 'widgets/stage_deliverable_presets_bar.dart';
import 'widgets/endorsed_stage_resolution_dialog.dart';

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
  StageSetupDraft? _creationDraft;
  bool _openingStageSetup = false;
  bool _wasVisible = false;

  Future<void> _startStageSetup() async {
    if (_openingStageSetup) return;
    _openingStageSetup = true;
    try {
      await _loadCreationDraft();
      if (mounted) await _showStageDialog(draft: _creationDraft);
    } finally {
      _openingStageSetup = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.of(context);
    if (visible && !_wasVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && TickerMode.of(context)) _loadCreationDraft();
      });
    }
    _wasVisible = visible;
  }

  StageSetupDraftStore? _draftStore({int? stageId, int? semesterId}) {
    final user = ref.read(authProvider).user;
    final userId = user?['id']?.toString() ?? user?['username']?.toString();
    if (userId == null || userId.isEmpty) return null;
    int? termId = semesterId ?? _asInt(ref.read(academicPeriodProvider).activeSemester?['id']);
    if (termId == null) {
      for (final year in ref.read(academicPeriodProvider).schoolYears) {
        final semesters = year['semesters'];
        if (semesters is List && semesters.isNotEmpty && semesters.first is Map) {
          termId = _asInt((semesters.first as Map)['id']);
          break;
        }
      }
    }
    return StageSetupDraftStore(
      userId: userId,
      semesterId: termId,
      stageId: stageId,
    );
  }

  Future<void> _loadCreationDraft() async {
    final store = _draftStore();
    try {
      final draft = await store?.load();
      if (mounted && store?.key == _draftStore()?.key) {
        setState(() => _creationDraft = draft);
      }
    } catch (_) {
      // A storage failure must not stop normal stage setup.
      if (mounted && store?.key == _draftStore()?.key) {
        setState(() => _creationDraft = null);
      }
    }
  }

  Future<void> _discardCreationDraft() async {
    final store = _draftStore();
    if (store == null) return;
    final discard = await showStageSetupConfirmation(
      context,
      title: 'Discard stage setup draft?',
      description: 'Your saved setup for this new stage will be removed.',
      confirmLabel: 'Discard draft',
      destructive: true,
    );
    if (!discard || !mounted) return;
    try {
      final pendingId = _asInt(_creationDraft?.fields['created_stage_id']);
      if (pendingId != null) await store.forStage(pendingId).clear();
      await store.clear();
      if (mounted && store.key == _draftStore()?.key) {
        setState(() => _creationDraft = null);
      }
    } catch (_) {
      if (mounted) showErrorToast(context, 'Could not discard the draft. Please try again.');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(defenseStagesProvider.notifier).fetchStages();
      await ref.read(academicPeriodProvider.notifier).fetchPeriods();
      if (mounted) await _loadCreationDraft();
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
    ref.listen(academicPeriodProvider.select((state) => state.activeSemester?['id']),
        (_, _) => _loadCreationDraft());
    ref.listen(authProvider.select((state) => state.user?['id']),
        (_, _) => _loadCreationDraft());
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

    return DefenseStageDirectory(
      exportAction: const ReportExportMenu(reportId: 'defense-stage-setup'),
      draftNotice: _creationDraft == null ? null : StageSetupDraftNotice(
        title: 'Stage setup draft: ${_creationDraft!.label.isEmpty ? 'Untitled stage' : _creationDraft!.label}',
        onResume: _startStageSetup,
        onDiscard: _discardCreationDraft,
      ),
      state: state,
      onRefresh: () => ref.read(defenseStagesProvider.notifier).fetchStages(),
      onAdd: _startStageSetup,
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
    String? labelText,
    String? hintText,
    String? helperText,
    String? errorText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    Color? fillColor,
  }) {
    final effectiveFill = fillColor ?? Colors.white;
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
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
      helperStyle: const TextStyle(
        fontSize: 11,
        color: AppColors.textSecondary,
      ),
      filled: true,
      fillColor: effectiveFill,
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

  Widget _buildDialogFormField({
    required String label,
    required Widget child,
    String? badge,
    Color? badgeColor,
    String? helperText,
    String? tooltip,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.1,
                  ),
                ),
                if (tooltip != null) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: tooltip,
                    child: const Icon(
                      Icons.help_outline_rounded,
                      size: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
            if (badge != null)
              Text(
                badge,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: badgeColor ?? AppColors.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 7),
        child,
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 12.5,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  helperText,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDialogPublishedStageBanner({
    required bool isActive,
    required bool isLocked,
    required ValueChanged<bool> onChanged,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFDCFCE7) : const Color(0xFFE2E8F0),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isActive ? Icons.check_circle_rounded : Icons.visibility_off_rounded,
              size: 19,
              color: isActive ? const Color(0xFF16A34A) : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    const Text(
                      'Published Stage',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: isActive ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                        border: Border.all(
                          color: isActive ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Text(
                        isActive ? 'Active' : 'Draft',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isActive ? const Color(0xFF15803D) : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                const Text(
                  'When active, this stage is part of the live capstone defense sequence.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: isActive,
            activeTrackColor: AppColors.maroon,
            onChanged: isLocked ? null : onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildDialogTabBar({
    required int activeTab,
    required int deliverableCount,
    required int totalWeight,
    required void Function(int) onTabSelected,
  }) {
    final hasWeightError = totalWeight != 100;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceHigherOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DefensysTokens.borderOf(context)),
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
            badge: (deliverableCount > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: activeTab == 2
                              ? Colors.white.withValues(alpha: 0.25)
                              : DefensysTokens.borderOf(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$deliverableCount',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: activeTab == 2 ? Colors.white : DefensysTokens.textPrimaryOf(context),
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
                color: isSelected ? Colors.white : DefensysTokens.textSecondaryOf(context),
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
                    color: isSelected ? Colors.white : DefensysTokens.textPrimaryOf(context),
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
    required List<Map<String, dynamic>> allDeliverables,
    required List<Map<String, dynamic>> sharedDeliverables,
    required bool conceptsEnabled,
    required void Function(void Function()) setDialogState,
    required TextEditingController stageLabelCtrl,
    required Map<String, dynamic>? selectedItem,
    required ValueChanged<Map<String, dynamic>?> onSelect,
    String? itemError,
  }) {
    final dark = DefensysTokens.isDark(context);
    final sectionAccent = dark
        ? DefensysTokens.textPrimaryOf(context)
        : accentColor;
    final sectionBorder = dark ? DefensysTokens.borderOf(context) : borderColor;
    final sectionHeader = dark
        ? DefensysTokens.backgroundOf(context)
        : bgHeaderColor;
    return Container(
      key: ValueKey(
        isPost
            ? 'post-defense-deliverables-section'
            : 'pre-defense-deliverables-section',
      ),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sectionBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: sectionHeader,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
              border: Border(bottom: BorderSide(color: sectionBorder)),
            ),
            child: StageDeliverableSectionHeader(
              heading: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: sectionAccent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 15, color: sectionAccent),
                  ),
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
                                color: sectionAccent,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: sectionAccent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: dark
                                      ? DefensysTokens.backgroundOf(context)
                                      : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: DefensysTokens.textSecondaryOf(context),
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
                  onPressed: onAdd,
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
                        onTap: onAdd,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isPost
                                    ? Icons.inventory_2_outlined
                                    : Icons.folder_open_rounded,
                                size: 16,
                                color: const Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  emptyPlaceholderText,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
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
                    : StageDeliverableOverview(
                        items: items,
                        isPost: isPost,
                        selectedItem: selectedItem,
                        onSelect: onSelect,
                        showGroupHeading: true,
                        showReviewHint: false,
                        showDoneEditingButton: false,
                        buildEditor: (item, index) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (itemError != null &&
                                identical(item, selectedItem) &&
                                (itemError.startsWith('Enter')
                                    ? (item['label']
                                              ?.toString()
                                              .trim()
                                              .isEmpty ??
                                          true)
                                    : RegExp(r'\{[a-zA-Z0-9_]+\}')
                                              .allMatches(
                                                item['archive_file_template']
                                                        ?.toString() ??
                                                    '',
                                              )
                                              .length >
                                          3))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  itemError,
                                  style: TextStyle(color: AppColors.danger),
                                ),
                              ),
                            _buildDeliverableItemCard(
                              index: index,
                              item: item,
                              isPost: isPost,
                              allDeliverables: allDeliverables,
                              sharedDeliverables: sharedDeliverables,
                              conceptsEnabled: conceptsEnabled,
                              setDialogState: setDialogState,
                              stageLabelCtrl: stageLabelCtrl,
                              onDone: () => onSelect(null),
                            ),
                          ],
                        ),
                      ),
              ],
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
    required List<Map<String, dynamic>> sharedDeliverables,
    required bool conceptsEnabled,
    required void Function(void Function()) setDialogState,
    required TextEditingController stageLabelCtrl,
    VoidCallback? onDone,
  }) {
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
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DefensysTokens.borderOf(context)),
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
            decoration: BoxDecoration(
              color: DefensysTokens.backgroundOf(context),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(9),
                topRight: Radius.circular(9),
              ),
              border: Border(
                bottom: BorderSide(color: DefensysTokens.borderOf(context)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: DefensysTokens.backgroundOf(context),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Text(
                    '#$index',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: DefensysTokens.textPrimaryOf(context),
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
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setDialogState(() {
                      removeConfiguredDeliverable(
                        item,
                        allDeliverables,
                        sharedDeliverables,
                      );
                      // A selected item disappears from the overview on the
                      // next build; the other items remain collapsed.
                      (item['_labelController'] as TextEditingController?)
                          ?.dispose();
                      (item['_templateController'] as TextEditingController?)
                          ?.dispose();
                    });
                  },
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.danger,
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
                      decoration: _dialogInputDecoration(
                        labelText: isPost
                            ? 'Post-Defense Deliverable Name *'
                            : 'Pre-Defense Deliverable Name *',
                        hintText: isPost
                            ? 'e.g. Final Manuscript PDF, Source Code Archive'
                            : 'e.g. Concept Paper Draft, Similarity Report',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      onChanged: (value) {
                        item['label'] = value.trim();
                        syncPolicySlot();
                        setDialogState(() {});
                      },
                    );
                    final formatField = SizedBox(
                      width: 210,
                      child: StageFileFormatPicker(
                        value: currentFormat,
                        onChanged: (val) => setDialogState(() {
                          item['file_format'] = val;
                          syncPolicySlot();
                        }),
                      ),
                    );
                    final requiredField = DefensysShadcnScope(
                      child: ShadCheckbox(
                        value: item['required'] == true,
                        label: Text('Required'),
                        onChanged: (value) => setDialogState(() {
                          item['required'] = value;
                          syncPolicySlot();
                        }),
                      ),
                    );

                    final isAdvancedExpanded =
                        item['_expandedAdvanced'] as bool? ?? false;

                    final moreOptionsBtn = DefensysShadcnScope(
                      child: ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: () {
                          setDialogState(() {
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
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: DefensysTokens.backgroundOf(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: DefensysTokens.borderOf(context),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 14,
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  isPost
                                      ? 'Post-Defense Rules & Archiving'
                                      : 'Pre-defense options',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: DefensysTokens.textPrimaryOf(
                                      context,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          DeliverableSubmissionPicker(
                            value: deliverableSubmissionAudience(item),
                            enabled: true,
                            onChanged: (value) {
                              setDialogState(
                                () => setDeliverableSubmissionAudience(
                                  item,
                                  value,
                                  allDeliverables,
                                  sharedDeliverables,
                                ),
                              );
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
                            enabled: true,
                            allowConcepts:
                                (conceptsEnabled) &&
                                (!isPost ||
                                    deliverableSubmissionAudience(item) ==
                                        'pm'),
                            deliverableLabel: labelController.text,
                            fileFormat: currentFormat,
                            required: item['required'] == true,
                            onChanged: (value) {
                              setDialogState(() => item['file_policy'] = value);
                            },
                          ),
                          const SizedBox(height: 12),
                          Divider(
                            height: 1,
                            color: DefensysTokens.borderOf(context),
                          ),
                          const SizedBox(height: 10),
                          if (!isPost) ...[
                            const DeliverableTimingFields(),
                            const SizedBox(height: 10),
                            Divider(
                              height: 1,
                              color: DefensysTokens.borderOf(context),
                            ),
                            const SizedBox(height: 10),
                            DefenseMaterialToggle(
                              value: item['is_defense_material'] == true,
                              onChanged: (value) => setDialogState(() {
                                item['is_defense_material'] = value;
                              }),
                            ),
                            const SizedBox(height: 10),
                            Divider(
                              height: 1,
                              color: DefensysTokens.borderOf(context),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (isPost) ...[
                            const StagePostDefenseReviewNotice(),
                            const SizedBox(height: 10),
                            Divider(
                              height: 1,
                              color: DefensysTokens.borderOf(context),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: DefensysShadcnScope(
                                    child: ShadCheckbox(
                                      value: item['is_restricted'] == true,
                                      onChanged: (value) {
                                        setDialogState(() {
                                          item['is_restricted'] = value;
                                        });
                                      },
                                      label: Text(
                                        'Restricted / Private in Institutional Archive',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: DefensysTokens.textPrimaryOf(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Tooltip(
                                  message:
                                      'Private for faculty and admin records only; hidden from students.',
                                  constraints: BoxConstraints(maxWidth: 240),
                                  child: Icon(
                                    Icons.help_outline_rounded,
                                    size: 14,
                                    color: DefensysTokens.textSecondaryOf(
                                      context,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Divider(
                              height: 1,
                              color: DefensysTokens.borderOf(context),
                            ),
                            const SizedBox(height: 8),
                            RepositoryArchiveNamingPanel(
                              templateController: templateController,
                              deliverableLabel: labelController.text,
                              fileFormat: currentFormat,
                              isLocked: false,
                              isPit: false,
                              stageOrEventLabel: stageLabelCtrl.text,
                              siblingDeliverables:
                                  deliverableSetupItems(
                                        allDeliverables,
                                        sharedDeliverables,
                                      )
                                      .where(
                                        (d) =>
                                            d['deliverable_type'] ==
                                            (isPost ? 'post' : 'pre'),
                                      )
                                      .toList(),
                              currentIndex:
                                  deliverableSetupItems(
                                        allDeliverables,
                                        sharedDeliverables,
                                      )
                                      .where(
                                        (d) =>
                                            d['deliverable_type'] ==
                                            (isPost ? 'post' : 'pre'),
                                      )
                                      .toList()
                                      .indexOf(item),
                              onChanged: () {
                                setDialogState(() {
                                  item['archive_file_template'] =
                                      templateController.text.trim();
                                });
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
                        leading: Icon(Icons.check_rounded, size: 14),
                        child: Text('Done editing'),
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

  Future<void> _showStageDialog({Map<String, dynamic>? stage, StageSetupDraft? draft}) async {
    final createdStageId = _asInt(draft?.fields['created_stage_id']);
    if (createdStageId != null) {
      context.push(AdminRoutes.defenseStageEdit(createdStageId, initialTab: draft!.tab));
      return;
    }
    final editing = stage != null;
    final setup = draft?.fields ?? stage;

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
      text: setup?['label']?.toString() ?? '',
    );
    final codeCtrl = TextEditingController(
      text: setup?['code']?.toString() ?? '',
    );
    final description = TextEditingController(
      text: setup?['description']?.toString() ?? '',
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
    final lastPosition = totalExisting + (editing ? 0 : 1);
    selectedPosition = (_asInt(setup?['display_order']) ?? selectedPosition)
        .clamp(minPosition, lastPosition < minPosition ? minPosition : lastPosition);

    if (selectedPosition < minPosition) {
      selectedPosition = minPosition;
    }
    final panelCtrl = TextEditingController(text: '50');
    final adviserCtrl = TextEditingController(text: '30');
    final peerCtrl = TextEditingController(text: '20');
    final qualifyingScoreCtrl = TextEditingController(text: setup?['qualifying_score']?.toString() ?? '');
    var scoreCarryover = setup?['score_carryover']?.toString() ?? (setup?['concept_config'] as Map?)?['score_carryover']?.toString() ?? 'reassess';
    var isActive = setup?['is_active'] == true;
    var conceptConfig = Map<String, dynamic>.from(setup?['concept_config'] as Map? ?? {});
    var sharedDeliverables = sharedDeliverableValues(setup?['shared_deliverables'] ??
        (conceptConfig['enabled'] == true ? defaultSharedDeliverables() : []));
    bool minutesRequired = setup?['minutes_required'] is bool
        ? setup!['minutes_required'] as bool : true;
    final minutesNumber = TextEditingController(
      text: setup?['minutes_deliverable_id']?.toString() ?? 'MINUTES',
    );
    final minutesName = TextEditingController(
      text: setup?['minutes_deliverable_label']?.toString() ?? '',
    );

    int? panelRubricId;
    int? adviserRubricId;
    int? peerRubricId;

    if (setup != null) {
      final gc = (setup['grading_config'] is Map) ? setup['grading_config'] as Map : setup;
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
    if (setup != null && setup['deliverables'] != null) {
      final delivsList = setup['deliverables'];
      if (delivsList is List) {
        deliverables = delivsList
            .whereType<Map>()
            .map((d) => Map<String, dynamic>.from(d))
            .toList();
      }
    }

    Map<String, dynamic>? selectedDeliverable;
    bool minutesExpanded = false;
    String? deliverableError;

    int activeTab = draft?.tab ?? 0;
    final draftStore = _draftStore(stageId: _asInt(stage?['id']), semesterId: semesterId);
    bool savingDraft = false;

    StageSetupDraft snapshotDraft() => StageSetupDraft(
      tab: activeTab,
      fields: {
        'label': label.text,
        'code': codeCtrl.text,
        'description': description.text,
        'display_order': selectedPosition,
        'is_active': isActive,
        'is_presentation_only': false,
        'minutes_required': minutesRequired,
        'concept_config': {...conceptConfig, if (conceptConfig['enabled'] == true) 'review_policy': 'always'},
        'qualifying_score': double.tryParse(qualifyingScoreCtrl.text.trim()),
        'score_carryover': scoreCarryover,
        'minutes_deliverable_id': minutesNumber.text,
        'minutes_deliverable_label': minutesName.text,
        'deliverables': deliverables,
        'shared_deliverables': configuredSharedDeliverables(deliverables, sharedDeliverables),
        'grading_config': {
          'panel_weight': panelCtrl.text,
          'adviser_weight': adviserCtrl.text,
          'peer_weight': peerCtrl.text,
          'panel_rubric_id': panelRubricId,
          'adviser_rubric_id': adviserRubricId,
          'peer_rubric_id': peerRubricId,
        },
      },
    );

    Future<bool> persistDraft() async {
      try {
        if (draftStore == null) throw StateError('Account is unavailable.');
        final snapshot = snapshotDraft();
        await draftStore.save(snapshot);
        if (mounted && !editing && draftStore.key == _draftStore()?.key) {
          setState(() => _creationDraft = snapshot);
        }
        return true;
      } catch (_) {
        if (mounted) showErrorToast(context, 'Could not save your draft. Your setup is still open; please try again.');
        return false;
      }
    }

    await ref.read(rubricEngineProvider.notifier).fetchRubrics(
          scope: 'capstone',
          status: '',
        );

    if (!mounted) return;
    bool? saved;
    ModalRoute<bool>? stageDialogRoute;
    try {
      saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          stageDialogRoute = ModalRoute.of<bool>(dialogContext);
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> saveAndLeave({bool openRubrics = false}) async {
                if (savingDraft) return;
                setDialogState(() => savingDraft = true);
                final savedDraft = await persistDraft();
                if (!dialogContext.mounted || stageDialogRoute?.isActive != true) return;
                if (!savedDraft) {
                  setDialogState(() => savingDraft = false);
                  return;
                }
                Navigator.pop(dialogContext, false);
                if (openRubrics && mounted) {
                  this.context.go(AdminRoutes.rubrics);
                } else if (mounted) {
                  showSuccessToast(this.context, 'Stage setup draft saved.');
                }
              }
              final panelVal = int.tryParse(panelCtrl.text.trim()) ?? 0;
              final adviserVal = int.tryParse(adviserCtrl.text.trim()) ?? 0;
              final peerVal = int.tryParse(peerCtrl.text.trim()) ?? 0;
              final total = panelVal + adviserVal + peerVal;

              List<Map<String, dynamic>> getRubricOptions(String evaluationType) {
                final rubrics = ref.watch(rubricEngineProvider).rubrics;
                return rubrics.where((r) {
                  final scopeMatch = r['scope'] == 'capstone';
                  final semMatch = _asInt(r['semester_id']) == semesterId;
                  final evalMatch = r['evaluation_type'] == evaluationType;
                  final publishedMatch = r['status'] == 'published';
                  final currentStageId = _asInt(stage?['id']);
                  final assignedStageId = _asInt(r['defense_stage_id']);
                  final stageMatch = assignedStageId == null || assignedStageId == currentStageId;
                  final available = r['is_locked'] != true ||
                      (currentStageId != null && assignedStageId == currentStageId);
                  return scopeMatch && semMatch && evalMatch && publishedMatch && stageMatch && available;
                }).toList();
              }



              final preDeliverables = deliverableSetupItems(deliverables, sharedDeliverables).where((d) => d['deliverable_type'] == 'pre').toList();
              final postDeliverables = deliverableSetupItems(deliverables, sharedDeliverables).where((d) => d['deliverable_type'] == 'post').toList();

              return Dialog(
                backgroundColor: DefensysTokens.surfaceOf(context),
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
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: DefensysTokens.borderOf(context))),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: DefensysTokens.surfaceHigherOf(context),
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
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: DefensysTokens.textPrimaryOf(context),
                                      letterSpacing: -0.3,
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
                        deliverableCount: deliverableSetupItems(deliverables, sharedDeliverables).length +
                            (minutesRequired == true ? 1 : 0),
                        totalWeight: total,
                        onTabSelected: (index) {
                          setDialogState(() => activeTab = index);
                        },
                      ),

                      // Scrollable Tab Content
                      Flexible(
                        child: SingleChildScrollView(
                          key: ValueKey('stage-dialog-step-$activeTab'),
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                          child: <Widget>[
                              // TAB 0: Stage Identity & Pipeline Flow
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 1. Stage Identity (Name & Code)
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final isWide = constraints.maxWidth >= 600;
                                      final nameField = _buildDialogFormField(
                                        label: 'Stage Name',
                                        badge: 'Required',
                                        badgeColor: AppColors.maroon,
                                        child: TextField(
                                          controller: label,
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          decoration: _dialogInputDecoration(
                                            hintText: 'e.g. Concept Proposal, Colloquium, Final Defense',
                                          ),
                                          onChanged: (_) => setDialogState(() {}),
                                        ),
                                      );

                                      final codeField = _buildDialogFormField(
                                        label: 'Stage Code',
                                        badge: 'System Identifier',
                                        child: TextField(
                                          controller: codeCtrl,
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          decoration: _dialogInputDecoration(
                                            hintText: 'e.g. concept-proposal',
                                            prefixIcon: const Icon(
                                              Icons.tag_rounded,
                                              size: 16,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                          onChanged: (_) => setDialogState(() {}),
                                        ),
                                      );

                                      if (!isWide) {
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            nameField,
                                            const SizedBox(height: 14),
                                            codeField,
                                          ],
                                        );
                                      }

                                      return Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(flex: 3, child: nameField),
                                          const SizedBox(width: 14),
                                          Expanded(flex: 2, child: codeField),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 14),

                                  // 2. Stage Description & Publication Status
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final isWide = constraints.maxWidth >= 600;
                                      final descField = _buildDialogFormField(
                                        label: 'Stage Description',
                                        badge: 'Optional',
                                        child: TextField(
                                          controller: description,
                                          minLines: 2,
                                          maxLines: 2,
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 13.5,
                                            height: 1.35,
                                          ),
                                          decoration: _dialogInputDecoration(
                                            hintText: 'Provide brief guidance or objectives for this defense milestone...',
                                          ),
                                        ),
                                      );

                                      final publishedField = _buildDialogFormField(
                                        label: 'Publication Status',
                                        badge: isActive ? 'Active' : 'Draft',
                                        badgeColor: isActive ? const Color(0xFF16A34A) : AppColors.textSecondary,
                                        child: _buildDialogPublishedStageBanner(
                                          isActive: isActive,
                                          isLocked: stageIsLocked,
                                          onChanged: (val) {
                                            setDialogState(() => isActive = val);
                                          },
                                        ),
                                      );

                                      if (!isWide) {
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            descField,
                                            const SizedBox(height: 14),
                                            publishedField,
                                          ],
                                        );
                                      }

                                      return Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(flex: 3, child: descField),
                                          const SizedBox(width: 14),
                                          Expanded(flex: 2, child: publishedField),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 16),

                                  // 3. Sequence Position in Pipeline
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: DefensysTokens.surfaceHigherOf(context),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: DefensysTokens.borderOf(context)),
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

                                  // 4. Session Documentation Policy
                                  const Text(
                                    'Stage policies',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  StageMinutesSettings(
                                    requiredMinutes: minutesRequired,
                                    enabled: !stageIsLocked,
                                    onChanged: (value) => setDialogState(() => minutesRequired = value),
                                  ),
                                  const SizedBox(height: 14),

                                  // 5. Concept Settings
                                  ConceptSettings(
                                    value: conceptConfig,
                                    enabled: !stageIsLocked,
                                    onChanged: (value) => setDialogState(() {
                                      if (conceptConfig['enabled'] != true && value['enabled'] == true && sharedDeliverables.isEmpty) {
                                        sharedDeliverables = defaultSharedDeliverables();
                                        ensureConceptPapers(deliverables, value, sharedItems: sharedDeliverables);
                                        linkNewSharedConceptDefaults(deliverables, sharedDeliverables);
                                      }
                                      conceptConfig = value;
                                      ensureConceptPapers(deliverables, value, sharedItems: sharedDeliverables);
                                      if (!deliverables.contains(selectedDeliverable)) selectedDeliverable = null;
                                    }),
                                  ),
                                ],
                              ),

                              // TAB 1: Grading and rubrics
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  GradingSetupSection(
                                    enabled: !stageIsLocked && !savingDraft,
                                    canManageRubrics: !savingDraft,
                                    onManageRubrics: () => saveAndLeave(openRubrics: true),
                                    resetLabel: 'Reset to 50 / 30 / 20',
                                    onReset: () => setDialogState(() {
                                      panelCtrl.text = '50'; adviserCtrl.text = '30'; peerCtrl.text = '20';
                                    }),
                                    roles: [
                                      GradingRoleSetup(role: 'panel', label: 'Panel', weightController: panelCtrl,
                                        rubrics: getRubricOptions('panel'), rubricId: panelRubricId,
                                        onWeightChanged: (_) => setDialogState(() {}),
                                        onRubricChanged: (value) => setDialogState(() => panelRubricId = value)),
                                      GradingRoleSetup(role: 'adviser', label: 'Adviser', weightController: adviserCtrl,
                                        rubrics: getRubricOptions('adviser'), rubricId: adviserRubricId,
                                        onWeightChanged: (_) => setDialogState(() {}),
                                        onRubricChanged: (value) => setDialogState(() => adviserRubricId = value)),
                                      GradingRoleSetup(role: 'peer', label: 'Peer', weightController: peerCtrl,
                                        rubrics: getRubricOptions('peer'), rubricId: peerRubricId,
                                        onWeightChanged: (_) => setDialogState(() {}),
                                        onRubricChanged: (value) => setDialogState(() => peerRubricId = value)),
                                    ],
                                  ),
                                  Padding(padding: const EdgeInsets.symmetric(vertical: 24),
                                    child: Divider(height: 1, color: DefensysTokens.borderOf(context))),
                                  StageOutcomeSettings(scoreController: qualifyingScoreCtrl,
                                    scoreCarryover: scoreCarryover, conceptSelection: conceptConfig['enabled'] == true,
                                    enabled: !stageIsLocked && !savingDraft,
                                    onChanged: () => setDialogState(() {}),
                                    onCarryoverChanged: (v) => setDialogState(() => scoreCarryover = v)),
                                ],
                              ),

                              // TAB 2: Deliverables Split (Pre-Defense vs. Post-Defense)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  StageDeliverablePresetsBar(
                                    existingStages: existingStages,
                                    currentDeliverables: deliverablePresetItems(deliverables, sharedDeliverables),
                                    enabled: !stageIsLocked,
                                    onApplyDeliverables: (newDeliverables) {
                                      setDialogState(() {
                                        applyDeliverablePresetItems(newDeliverables, deliverables, sharedDeliverables);
                                        selectedDeliverable = deliverables.isNotEmpty ? deliverables.first : null;
                                        deliverableError = null;
                                      });
                                    },
                                  ),
                                  StageDeliverableCounts(
                                    deliverables: deliverableSetupItems(deliverables, sharedDeliverables),
                                    minutesRequired: minutesRequired == true,
                                  ),
                                  // Pre-Defense Gatekeepers
                                  _buildDeliverableSection(
                                    title: 'Pre-Defense Requirements',
                                    subtitle: 'Required files need faculty acceptance before endorsement and scheduling.',
                                    icon: Icons.folder_open_rounded,
                                    accentColor: const Color(0xFF0F172A),
                                    bgHeaderColor: const Color(0xFFF8FAFC),
                                    borderColor: const Color(0xFFE2E8F0),
                                    count: preDeliverables.length,
                                        onAdd: () {
                                      setDialogState(() {
                                         final item = <String, dynamic>{
                                          'deliverable_id': 'D${deliverables.length + 1}',
                                          'label': '',
                                          'deliverable_type': 'pre',
                                          'requirement_timing': 'scheduling',
                                          'deadline_hours_before': 24,
                                          'required': true,
                                          'display_order': deliverables.length + 1,
                                          'archive_note': '',
                                          'archive_file_template': '',
                                          'is_restricted': false,
                                           'is_defense_material': false,
                                           'verdict_condition': 'all_pass',
                                           'file_format': 'any',
                                         };
                                         deliverables.add(item);
                                         selectedDeliverable = item;
                                         minutesExpanded = false;
                                         deliverableError = null;
                                      });
                                    },
                                    emptyPlaceholderText: 'No pre-defense gatekeepers configured yet. (e.g. Proposal Manuscript Draft, Similarity Report)',
                                    items: preDeliverables,
                                    isPost: false,
                                    allDeliverables: deliverables,
                                    sharedDeliverables: sharedDeliverables,
                                    conceptsEnabled: conceptConfig['enabled'] == true,
                                    setDialogState: setDialogState,
                                    stageLabelCtrl: label,
                                     selectedItem: selectedDeliverable,
                                     onSelect: (item) => setDialogState(() {
                                       selectedDeliverable = item;
                                       if (item != null) minutesExpanded = false;
                                       deliverableError = null;
                                     }),
                                     itemError: deliverableError,
                                  ),

                                  const SizedBox(height: 16),

                                  // Post-Defense Requirements & Archive
                                  _buildDeliverableSection(
                                    title: 'Post-Defense Requirements & Archive',
                                    subtitle: 'Deliverables required for milestone clearance and repository archiving.',
                                    icon: Icons.inventory_2_rounded,
                                    accentColor: const Color(0xFF0F172A),
                                    bgHeaderColor: const Color(0xFFF8FAFC),
                                    borderColor: const Color(0xFFE2E8F0),
                                    count: postDeliverables.length,
                                        onAdd: () {
                                      setDialogState(() {
                                         final item = <String, dynamic>{
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
                                           'file_format': 'any',
                                         };
                                         deliverables.add(item);
                                         selectedDeliverable = item;
                                         minutesExpanded = false;
                                         deliverableError = null;
                                      });
                                    },
                                    emptyPlaceholderText: 'No post-defense deliverables configured yet. (e.g. Final Manuscript PDF, Source Code Zip, Demo Video)',
                                    items: postDeliverables,
                                    isPost: true,
                                    allDeliverables: deliverables,
                                    sharedDeliverables: sharedDeliverables,
                                    conceptsEnabled: conceptConfig['enabled'] == true,
                                    setDialogState: setDialogState,
                                    stageLabelCtrl: label,
                                     selectedItem: selectedDeliverable,
                                     onSelect: (item) => setDialogState(() {
                                       selectedDeliverable = item;
                                       if (item != null) minutesExpanded = false;
                                       deliverableError = null;
                                     }),
                                     itemError: deliverableError,
                                  ),
                                  if (minutesRequired == true) ...[
                                    const SizedBox(height: 18),
                                    StageMinutesDeliverableCard(
                                      number: minutesNumber,
                                      name: minutesName,
                                      stageName: label.text,
                                      enabled: !stageIsLocked,
                                      expanded: minutesExpanded,
                                      onToggle: () => setDialogState(() {
                                        minutesExpanded = !minutesExpanded;
                                        if (minutesExpanded) selectedDeliverable = null;
                                      }),
                                      onConfigure: () =>
                                          setDialogState(() => activeTab = 0),
                                    ),
                                  ],
                                ],
                              ),
                            ][activeTab],
                        ),
                      ),

                      // Footer Actions Bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        decoration: BoxDecoration(
                          color: DefensysTokens.surfaceHigherOf(context),
                          border: Border(top: BorderSide(color: DefensysTokens.borderOf(context))),
                        ),
                        child: StageSetupActions(
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext, false),
                              style: TextButton.styleFrom(
                                foregroundColor: DefensysTokens.textSecondaryOf(context),
                                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              child: const Text('Cancel'),
                            ),
                            if (!stageIsLocked) ...[
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: savingDraft ? null : () => saveAndLeave(),
                                icon: const Icon(Icons.save_outlined, size: 16),
                                label: Text(savingDraft ? 'Saving draft…' : 'Save draft'),
                              ),
                            ],
                            const Spacer(),
                            if (activeTab > 0) ...[
                              OutlinedButton.icon(
                                onPressed: () {
                                  setDialogState(() => activeTab--);
                                },
                                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                                label: const Text('Back'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: DefensysTokens.textPrimaryOf(context),
                                  side: BorderSide(color: DefensysTokens.borderOf(context)),
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
                              ),
                            if (activeTab < 2 && editing) const SizedBox(width: 10),
                            if (editing || activeTab == 2)
                              ElevatedButton.icon(
                                onPressed: savingDraft ? null : () async {
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
                                  if (StageOutcomeSettings.validateScore(qualifyingScoreCtrl.text) != null) {
                                    setDialogState(() => activeTab = 1);
                                    showValidationToast(context, 'Set a qualifying panel score from 0 to 100%.');
                                    return;
                                  }
                                  for (int i = 0; i < deliverables.length; i++) {
                                    final dLabel = deliverables[i]['label']?.toString().trim() ?? '';
                                    if (dLabel.isEmpty) {
                                      setDialogState(() {
                                        activeTab = 2;
                                        selectedDeliverable = deliverables[i];
                                        deliverableError = 'Enter a name for this deliverable.';
                                      });
                                      showValidationToast(context, 'Deliverable name cannot be empty (item ${i + 1}).');
                                      return;
                                    }
                                    if (deliverables[i]['deliverable_type'] == 'post') {
                                      final tpl = (deliverables[i]['archive_file_template'] ?? '').toString().trim();
                                      final vCount = RegExp(r'\{[a-zA-Z0-9_]+\}').allMatches(tpl).length;
                                      if (vCount > 3) {
                                        setDialogState(() {
                                          activeTab = 2;
                                          selectedDeliverable = deliverables[i];
                                          deliverableError = 'Use at most 3 variables in the archive file name.';
                                        });
                                        showValidationToast(context, 'Deliverable "$dLabel" template exceeds 3 variables ($vCount used). Limit is 3 for phone file names.');
                                        return;
                                      }
                                    }
                                  }
                                  setDialogState(() => savingDraft = true);
                                  final savedDraft = await persistDraft();
                                  if (!dialogContext.mounted || stageDialogRoute?.isActive != true) return;
                                  if (!savedDraft) {
                                    setDialogState(() => savingDraft = false);
                                    return;
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
      // The popped result arrives before the closing animation finishes.
      // Keep controllers alive until the dialog's widgets have been removed.
      await stageDialogRoute?.completed;
      if (saved != true) {
        label.dispose();
        codeCtrl.dispose();
        description.dispose();
        panelCtrl.dispose();
        adviserCtrl.dispose();
        peerCtrl.dispose();
        minutesNumber.dispose();
        minutesName.dispose();
        qualifyingScoreCtrl.dispose();
        for (final item in deliverableSetupItems(deliverables, sharedDeliverables)) {
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
      'is_presentation_only': false,
      'minutes_required': minutesRequired,
      'concept_config': {...conceptConfig, if (conceptConfig['enabled'] == true) 'review_policy': 'always'},
        'qualifying_score': double.tryParse(qualifyingScoreCtrl.text.trim()),
        'score_carryover': scoreCarryover,
      'minutes_deliverable_id': minutesNumber.text.trim(),
      'minutes_deliverable_label': minutesName.text.trim(),
      'deliverables': deliverables,
      'shared_deliverables': configuredSharedDeliverables(deliverables, sharedDeliverables),
      if (endorsedAction != null) 'endorsed_teams_action': endorsedAction,
    };

    bool configured = false;
    if (editing) {
      configured = await ref
          .read(defenseStagesProvider.notifier)
          .updateStage(_asInt(stage['id'])!, payload);
    } else {
      final newStageId =
          await ref.read(defenseStagesProvider.notifier).addStage(payload);
      if (newStageId != null) {
        // If grading fails after creation, resume that stage instead of adding
        // it again. Keep the complete configuration in its editor draft.
        final pendingDraft = StageSetupDraft(
          fields: {
            ...snapshotDraft().fields,
            'created_stage_id': newStageId,
            // A new stage has no assigned rubrics until grading setup succeeds.
            'rubric_assignment_changes': [
              if (panelRubricId != null) 'panel',
              if (adviserRubricId != null) 'adviser',
              if (peerRubricId != null) 'peer',
            ],
            'rubric_assignment_base': {'panel': null, 'adviser': null, 'peer': null},
          },
          tab: 1,
        );
        if (mounted && draftStore?.key == _draftStore()?.key) {
          setState(() => _creationDraft = pendingDraft);
        }
        try {
          await draftStore?.save(pendingDraft);
          await draftStore?.forStage(newStageId).save(pendingDraft);
        } catch (_) {
          if (mounted) showErrorToast(context, 'Stage created, but its draft could not be updated. Open Configure to finish its grading setup.');
        }
      }
      if (newStageId != null && semesterId != null) {
        configured = await ref.read(defenseStagesProvider.notifier).updateGradingConfig(
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
      } else {
        configured = newStageId != null;
      }
    }

    if (configured) {
      try {
        await draftStore?.clear();
        if (!editing) {
          final pendingId = _asInt(_creationDraft?.fields['created_stage_id']);
          if (pendingId != null) {
            await draftStore?.forStage(pendingId).clear();
          }
        }
        if (mounted && !editing && draftStore?.key == _draftStore()?.key) {
          setState(() => _creationDraft = null);
        }
      } catch (_) {
        if (mounted) showErrorToast(context, 'Stage saved, but its browser draft could not be removed.');
      }
    }

    label.dispose();
    codeCtrl.dispose();
    description.dispose();
    panelCtrl.dispose();
    adviserCtrl.dispose();
    peerCtrl.dispose();
    minutesNumber.dispose();
    minutesName.dispose();
    qualifyingScoreCtrl.dispose();
    for (final item in deliverableSetupItems(deliverables, sharedDeliverables)) {
      (item['_labelController'] as TextEditingController?)?.dispose();
      (item['_templateController'] as TextEditingController?)?.dispose();
    }
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
