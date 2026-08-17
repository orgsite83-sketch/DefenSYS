import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';

import '../../../navigation/admin_route_paths.dart';
import '../../../services/auth_provider.dart';
import '../../../services/rubric_engine_provider.dart';
import '../../../services/unsaved_changes_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../toasts/feedback_toast.dart';
import 'rubric_full_page_editor.dart';
import 'widgets/defensys_admin_shell.dart';

class RubricEngineScreen extends ConsumerStatefulWidget {
  const RubricEngineScreen({super.key});

  @override
  ConsumerState<RubricEngineScreen> createState() => _RubricEngineScreenState();
}

class _RubricEngineScreenState extends ConsumerState<RubricEngineScreen> {
  static const _kColName = 320.0;
  static const _kColStage = 210.0;
  static const _kColScope = 110.0;
  static const _kColEval = 150.0;
  static const _kColStatus = 140.0;
  static const _kRubricDataTableWidth =
      _kColName + _kColStage + _kColScope + _kColEval + _kColStatus;
  static const _kRubricActionColumnWidth = 110.0;

  final _searchController = TextEditingController();
  final _tableHScrollController = ScrollController();
  bool _showTableScrollHint = false;

  bool _rubricEditorOpen = false;
  bool _rubricEditorReadOnly = false;
  Map<String, dynamic>? _rubricEditorTarget;
  String? _rubricEditorInitialEval;
  String? _rubricEditorInitialScope;

  @override
  void initState() {
    super.initState();
    _tableHScrollController.addListener(_updateTableScrollHint);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider).user;
      ref.read(rubricEngineProvider.notifier).fetchRubrics(
            scope: _isPitLeadOnly(user) ? 'pit' : null,
            termContext: 'active',
          );
      _updateTableScrollHint();
    });
  }

  void _updateTableScrollHint() {
    if (!_tableHScrollController.hasClients) {
      if (_showTableScrollHint && mounted) {
        setState(() => _showTableScrollHint = false);
      }
      return;
    }
    final show = _tableHScrollController.position.maxScrollExtent > 4;
    if (show != _showTableScrollHint && mounted) {
      setState(() => _showTableScrollHint = show);
    }
  }

  bool _isPitLeadOnly(Map<String, dynamic>? user) {
    if (user == null) return false;
    if (user['role']?.toString() == 'admin') return false;
    if (user['is_superuser'] == true) return false;
    return user['is_pit_lead'] == true;
  }

  @override
  void dispose() {
    _tableHScrollController.removeListener(_updateTableScrollHint);
    _tableHScrollController.dispose();
    _searchController.dispose();
    super.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
      ref.read(unsavedChangesProvider.notifier).setDirty(false);
    });
  }

  void _openRubricEditor({
    Map<String, dynamic>? rubric,
    String? initialEvaluationType,
    String? initialScope,
    bool readOnly = false,
  }) {
    if (GoRouterState.of(context).uri.path == AdminRoutes.rubrics) {
      final id = rubric != null ? _asInt(rubric['id']) : null;
      context.push(
        id != null ? AdminRoutes.rubricEdit(id) : AdminRoutes.rubricCreate,
      );
      return;
    }
    setState(() {
      _rubricEditorOpen = true;
      _rubricEditorReadOnly = readOnly;
      _rubricEditorTarget = rubric;
      _rubricEditorInitialEval = initialEvaluationType;
      _rubricEditorInitialScope = initialScope;
    });
  }

  void _closeRubricEditor() {
    ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
    ref.read(unsavedChangesProvider.notifier).setDirty(false);
    setState(() {
      _rubricEditorOpen = false;
      _rubricEditorReadOnly = false;
      _rubricEditorTarget = null;
      _rubricEditorInitialEval = null;
      _rubricEditorInitialScope = null;
    });
  }

  void _showRubricToast(String message, ToastificationType type) {
    toastification.show(
      context: context,
      type: type,
      style: ToastificationStyle.flatColored,
      alignment: Alignment.topRight,
      title: Text(message),
      autoCloseDuration: const Duration(seconds: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rubricEngineProvider);
    final user = ref.watch(authProvider).user;
    final isPitLeadOnly = _isPitLeadOnly(user);

    ref.listen(rubricEngineProvider, (previous, next) {
      final error = next.error;
      if (error != null && error.isNotEmpty && error != previous?.error) {
        _showRubricToast(error, ToastificationType.error);
      }

      final message = next.message;
      if (message != null &&
          message.isNotEmpty &&
          message != previous?.message) {
        _showRubricToast(message, ToastificationType.success);
      }

      if (previous?.isLoading != next.isLoading ||
          previous?.rubrics.length != next.rubrics.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _updateTableScrollHint();
          }
        });
      }
    });

    final onAdminList =
        GoRouterState.of(context).uri.path == AdminRoutes.rubrics;

    if (!onAdminList && _rubricEditorOpen) {
      final target = _rubricEditorTarget;
      final rubricId = target != null ? _asInt(target['id']) : null;
      return RubricFullPageEditor(
        key: ValueKey(
          '${target?['id'] ?? 'new'}-$_rubricEditorInitialScope-$_rubricEditorInitialEval-$_rubricEditorReadOnly',
        ),
        rubric: target,
        initialScope: _rubricEditorInitialScope,
        initialEvaluationType: _rubricEditorInitialEval,
        readOnly: _rubricEditorReadOnly,
        onBack: _closeRubricEditor,
        onDelete: rubricId != null
            ? () => _confirmDelete(
                  rubricId,
                  target!['name']?.toString() ?? 'rubric',
                  rubric: target,
                  closeEditorOnSuccess: true,
                )
            : null,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(unsavedChangesSaveDraftProvider.notifier).setCallback(null);
      ref.read(unsavedChangesProvider.notifier).setDirty(false);
    });

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(state, isPitLeadOnly: isPitLeadOnly),
          const SizedBox(height: 20),
          _buildGuidanceNoticeCard(isPitLeadOnly: isPitLeadOnly, scope: state.scope),
          const SizedBox(height: 20),
          _buildStats(state, isPitLeadOnly: isPitLeadOnly),
          const SizedBox(height: 24),
          _rubricTableCard(state, isPitLeadOnly: isPitLeadOnly),
        ],
      ),
    );
  }

  Widget _buildPageHeader(RubricEngineState state, {required bool isPitLeadOnly}) {
    return DefensysPageHeader(
      icon: Icons.auto_awesome_mosaic_rounded,
      title: 'Rubric Engine',
      subtitle: isPitLeadOnly
          ? 'Create and manage PIT evaluation rubrics for your department events.'
          : 'Central repository for Capstone and PIT evaluation rubrics across academic stages.',
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _primaryActionButton(
            icon: Icons.add_rounded,
            label: 'Create Standard Rubric',
            onTap: state.isSaving
                ? null
                : () => _openRubricEditor(
                      initialScope: isPitLeadOnly ? 'pit' : 'capstone',
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidanceNoticeCard({required bool isPitLeadOnly, required String scope}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: DefensysUi.primaryMaroon.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: DefensysUi.primaryMaroon,
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Weight Distribution & Scope Configuration',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isPitLeadOnly || scope == 'pit'
                      ? 'PIT rubrics define criteria and scoring scales. Evaluation grade splits are configured per event in Defense Scheduler.'
                      : 'Capstone weights (Panel / Adviser / Peer) are defined per Defense Stage in Defense Stages Setup. PIT grade splits are defined per event in PIT Events Setup.',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(RubricEngineState state, {required bool isPitLeadOnly}) {
    final hideAdviser = isPitLeadOnly || state.scope == 'pit';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _evaluationStatCard(
            state: state,
            evalType: 'panel',
            title: 'Panel Rubrics',
            badgeText: 'PANEL',
            icon: Icons.groups_rounded,
            accent: DefensysUi.primaryMaroon,
            iconBg: const Color(0xFFFFF1F2),
          ),
        ),
        if (!hideAdviser) ...[
          const SizedBox(width: 14),
          Expanded(
            child: _evaluationStatCard(
              state: state,
              evalType: 'adviser',
              title: 'Adviser Rubrics',
              badgeText: 'ADVISER',
              icon: Icons.school_rounded,
              accent: const Color(0xFF059669),
              iconBg: const Color(0xFFECFDF5),
            ),
          ),
        ],
        const SizedBox(width: 14),
        Expanded(
          child: _evaluationStatCard(
            state: state,
            evalType: 'peer',
            title: 'Peer Rubrics',
            badgeText: 'PEER',
            icon: Icons.people_alt_rounded,
            accent: const Color(0xFF2563EB),
            iconBg: const Color(0xFFEFF6FF),
          ),
        ),
      ],
    );
  }

  void _toggleEvalFilter(String evalType) {
    final notifier = ref.read(rubricEngineProvider.notifier);
    final current = ref.read(rubricEngineProvider).evaluationType;
    if (current == evalType) {
      notifier.fetchRubrics(evaluationType: '');
    } else {
      notifier.fetchRubrics(evaluationType: evalType);
    }
  }

  String _evalCountKey(String evalType) {
    return switch (evalType) {
      'adviser' => 'eval_adviser',
      'peer' => 'eval_peer',
      _ => 'eval_panel',
    };
  }

  Widget _evaluationStatCard({
    required RubricEngineState state,
    required String evalType,
    required String title,
    required String badgeText,
    required IconData icon,
    required Color accent,
    required Color iconBg,
  }) {
    final selected = state.evaluationType == evalType;
    final count = _count(state, _evalCountKey(evalType));

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: Tooltip(
        message: selected
            ? 'Clear filter and show all evaluation types'
            : 'Filter table by $title',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: state.isSaving ? null : () => _toggleEvalFilter(evalType),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.05) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? accent : const Color(0xFFE2E8F0),
                width: selected ? 1.8 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: selected
                      ? accent.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.03),
                  blurRadius: selected ? 16 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$count',
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                color: accent,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? accent : const Color(0xFF334155),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.check_circle_rounded
                                : Icons.filter_alt_outlined,
                            size: 11,
                            color: selected ? accent : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            selected ? 'Filter active · Tap to clear' : 'Tap to filter table',
                            style: TextStyle(
                              color: selected ? accent : const Color(0xFF94A3B8),
                              fontSize: 11,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rubricTableCard(
    RubricEngineState state, {
    required bool isPitLeadOnly,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Command Bar
          Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 720;
                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _searchField(state),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _termSegmentedControl(state)),
                          if (!isPitLeadOnly) ...[
                            const SizedBox(width: 10),
                            Expanded(child: _scopeSegmentedControl(state)),
                          ],
                        ],
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 3, child: _searchField(state)),
                    const SizedBox(width: 14),
                    _termSegmentedControl(state),
                    if (!isPitLeadOnly) ...[
                      const SizedBox(width: 14),
                      _scopeSegmentedControl(state),
                    ],
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),

          // Table / Skeletons / Empty State
          if (state.isLoading)
            _tableSkeletonLoader()
          else if (state.rubrics.isEmpty)
            _emptyRubricTable(isPitLeadOnly: isPitLeadOnly)
          else
            _rubricTableWithStickyActions(state),

          if (_showTableScrollHint && state.rubrics.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: const [
                  Icon(Icons.swap_horiz_rounded, size: 14, color: Color(0xFF94A3B8)),
                  SizedBox(width: 6),
                  Text(
                    'Scroll horizontally to view all table columns',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _searchField(RubricEngineState state) {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: _searchController,
        enabled: !state.isSaving,
        style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF64748B),
            size: 18,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF94A3B8)),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(rubricEngineProvider.notifier).fetchRubrics(search: '');
                  },
                )
              : null,
          hintText: 'Search rubrics by name or academic year...',
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: DefensysUi.primaryMaroon, width: 1.5),
          ),
        ),
        onSubmitted: (value) {
          ref.read(rubricEngineProvider.notifier).fetchRubrics(search: value);
        },
      ),
    );
  }

  Widget _scopeSegmentedControl(RubricEngineState state) {
    final current = state.scope;
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segmentItem(
            label: 'All Scopes',
            selected: current.isEmpty,
            onTap: () => ref.read(rubricEngineProvider.notifier).fetchRubrics(scope: ''),
          ),
          _segmentItem(
            label: 'Capstone',
            selected: current == 'capstone',
            onTap: () => ref.read(rubricEngineProvider.notifier).fetchRubrics(scope: 'capstone'),
          ),
          _segmentItem(
            label: 'PIT',
            selected: current == 'pit',
            onTap: () => ref.read(rubricEngineProvider.notifier).fetchRubrics(scope: 'pit'),
          ),
        ],
      ),
    );
  }

  Widget _termSegmentedControl(RubricEngineState state) {
    final isHistory = state.termContext == 'history';
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segmentItem(
            label: 'Current Term',
            selected: !isHistory,
            onTap: () => ref.read(rubricEngineProvider.notifier).fetchRubrics(termContext: 'active'),
          ),
          _segmentItem(
            label: 'History',
            selected: isHistory,
            onTap: () => ref.read(rubricEngineProvider.notifier).fetchRubrics(termContext: 'history'),
          ),
        ],
      ),
    );
  }

  Widget _segmentItem({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? DefensysUi.primaryMaroon : const Color(0xFF64748B),
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _rubricTableWithStickyActions(RubricEngineState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dataAreaWidth =
            (constraints.maxWidth - _kRubricActionColumnWidth).clamp(0.0, double.infinity);
        final needsHorizontalScroll = dataAreaWidth < _kRubricDataTableWidth;

        Widget dataPane = _rubricDataTable(
          state,
          useFlexibleColumns: !needsHorizontalScroll,
        );

        if (needsHorizontalScroll) {
          dataPane = Scrollbar(
            controller: _tableHScrollController,
            thumbVisibility: true,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _tableHScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _kRubricDataTableWidth,
                child: dataPane,
              ),
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: dataPane),
            _rubricActionColumn(state),
          ],
        );
      },
    );
  }

  Widget _rubricDataTable(
    RubricEngineState state, {
    required bool useFlexibleColumns,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rubricDataHeader(useFlexibleColumns: useFlexibleColumns),
        ...state.rubrics.map(
          (rubric) => _rubricDataRow(
            rubric,
            useFlexibleColumns: useFlexibleColumns,
          ),
        ),
      ],
    );
  }

  Widget _rubricDataHeader({required bool useFlexibleColumns}) {
    return Container(
      height: 44,
      width: useFlexibleColumns ? null : _kRubricDataTableWidth,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: useFlexibleColumns
          ? const Row(
              children: [
                _RubricFlexHeaderCell('RUBRIC NAME', flex: 1.55),
                _RubricFlexHeaderCell('DEFENSE STAGE', flex: 1.2),
                _RubricFlexHeaderCell('SCOPE', flex: 0.8),
                _RubricFlexHeaderCell('EVALUATION', flex: 0.95),
                _RubricFlexHeaderCell('STATUS', flex: 0.9),
              ],
            )
          : const Row(
              children: [
                _RubricFixedHeaderCell('RUBRIC NAME', _kColName),
                _RubricFixedHeaderCell('DEFENSE STAGE', _kColStage),
                _RubricFixedHeaderCell('SCOPE', _kColScope),
                _RubricFixedHeaderCell('EVALUATION', _kColEval),
                _RubricFixedHeaderCell('STATUS', _kColStatus),
              ],
            ),
    );
  }

  Widget _rubricDataRow(
    Map<String, dynamic> rubric, {
    required bool useFlexibleColumns,
  }) {
    return Container(
      width: useFlexibleColumns ? null : _kRubricDataTableWidth,
      constraints: const BoxConstraints(minHeight: 64),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: useFlexibleColumns
          ? Row(
              children: [
                _RubricFlexTableCell(_rubricNameCell(rubric), flex: 1.55),
                _RubricFlexTableCell(_defenseStageCell(rubric), flex: 1.2),
                _RubricFlexTableCell(_scopeCell(rubric), flex: 0.8),
                _RubricFlexTableCell(_evaluationTypeCell(rubric), flex: 0.95),
                _RubricFlexTableCell(_statusChip(rubric), flex: 0.9),
              ],
            )
          : Row(
              children: [
                _RubricFixedTableCell(_rubricNameCell(rubric), _kColName),
                _RubricFixedTableCell(_defenseStageCell(rubric), _kColStage),
                _RubricFixedTableCell(_scopeCell(rubric), _kColScope),
                _RubricFixedTableCell(_evaluationTypeCell(rubric), _kColEval),
                _RubricFixedTableCell(_statusChip(rubric), _kColStatus),
              ],
            ),
    );
  }

  Widget _rubricActionColumn(RubricEngineState state) {
    return Container(
      width: _kRubricActionColumnWidth,
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rubricActionHeader(),
          ...state.rubrics.map((rubric) => _rubricActionRow(state, rubric)),
        ],
      ),
    );
  }

  Widget _rubricActionHeader() {
    return Container(
      height: 44,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: const Text(
        'ACTION',
        style: TextStyle(
          color: Color(0xFF64748B),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _rubricActionRow(RubricEngineState state, Map<String, dynamic> rubric) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: _buildActions(state, rubric),
    );
  }

  Widget _tableSkeletonLoader() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: List.generate(
          5,
          (index) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyRubricTable({required bool isPitLeadOnly}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.quiz_outlined,
              size: 36,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Rubrics Found',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No rubrics match your active filter parameters or search query.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  ref.read(rubricEngineProvider.notifier).fetchRubrics(
                        scope: '',
                        evaluationType: '',
                        termContext: 'active',
                        search: '',
                      );
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Reset Filters'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF475569),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _openRubricEditor(
                  initialScope: isPitLeadOnly ? 'pit' : 'capstone',
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Create Rubric'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DefensysUi.primaryMaroon,
                  foregroundColor: DefensysUi.accentGold,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rubricNameCell(Map<String, dynamic> rubric) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rubric['name']?.toString() ?? '-',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule_rounded, size: 12, color: Color(0xFF94A3B8)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                _rubricNameSubtitle(rubric),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _rubricNameSubtitle(Map<String, dynamic> rubric) {
    final semester = rubric['display_semester']?.toString().trim() ?? '';
    final creator = _createdByLabel(rubric);
    if (semester.isEmpty) {
      return creator == '-' ? '' : creator;
    }
    if (creator == '-') {
      return semester;
    }
    return '$semester · $creator';
  }

  String _createdByLabel(Map<String, dynamic> rubric) {
    final name = rubric['created_by_name']?.toString().trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return '-';
  }

  Widget _defenseStageCell(Map<String, dynamic> rubric) {
    final scope = rubric['scope']?.toString() ?? '';
    if (scope == 'pit') {
      final event = rubric['event_name']?.toString().trim();
      return _stagePill(event != null && event.isNotEmpty ? event : 'Unassigned PIT Event', isPit: true);
    }
    final stage = rubric['defense_stage_label']?.toString().trim();
    return _stagePill(stage != null && stage.isNotEmpty ? stage : 'Unassigned Stage', isPit: false);
  }

  Widget _stagePill(String label, {required bool isPit}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isPit ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isPit ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF334155),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _scopeCell(Map<String, dynamic> rubric) {
    final scope = rubric['scope']?.toString() ?? '';
    final isPit = scope == 'pit';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: isPit ? const Color(0xFFF0FDF4) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isPit ? const Color(0xFFBBF2D0) : const Color(0xFFBFDBFE)),
      ),
      child: Text(
        isPit ? 'PIT' : 'Capstone',
        style: TextStyle(
          color: isPit ? const Color(0xFF166534) : const Color(0xFF1E40AF),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _evaluationTypeCell(Map<String, dynamic> rubric) {
    return _evaluationTypeChip(rubric['evaluation_type']?.toString());
  }

  Widget _evaluationTypeChip(String? evalType) {
    final type = evalType ?? 'panel';
    final (label, bg, border, fg, icon) = switch (type) {
      'adviser' => ('Adviser', const Color(0xFFECFDF5), const Color(0xFFA7F3D0), const Color(0xFF047857), Icons.school_outlined),
      'peer' => ('Peer', const Color(0xFFEFF6FF), const Color(0xFFBFDBFE), const Color(0xFF1D4ED8), Icons.people_outline),
      _ => ('Panel', const Color(0xFFFFF1F2), const Color(0xFFFECDD3), const Color(0xFF9F1239), Icons.groups_outlined),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(RubricEngineState state, Map<String, dynamic> rubric) {
    final published = rubric['status'] == 'published';
    final rubricId = _asInt(rubric['id']);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: published ? 'View locked rubric' : 'Edit rubric criteria',
          child: IconButton(
            onPressed: state.isSaving
                ? null
                : () => _openRubricEditor(rubric: rubric, readOnly: published),
            icon: Icon(
              published ? Icons.lock_outline_rounded : Icons.edit_outlined,
              size: 17,
              color: published ? const Color(0xFF64748B) : DefensysUi.primaryMaroon,
            ),
            style: IconButton.styleFrom(
              minimumSize: const Size(34, 34),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              hoverColor: const Color(0xFFF1F5F9),
            ),
          ),
        ),
        if (!published && rubricId != null) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: 'Delete draft rubric',
            child: IconButton(
              onPressed: state.isSaving
                  ? null
                  : () => _confirmDelete(
                        rubricId,
                        rubric['name']?.toString() ?? 'rubric',
                        rubric: rubric,
                      ),
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 17,
                color: AppColors.danger,
              ),
              style: IconButton.styleFrom(
                minimumSize: const Size(34, 34),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                hoverColor: const Color(0xFFFFF1F2),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _primaryActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: DefensysUi.primaryMaroon,
          foregroundColor: DefensysUi.accentGold,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    int rubricId,
    String rubricName, {
    Map<String, dynamic>? rubric,
    bool closeEditorOnSuccess = false,
  }) async {
    final canDelete = rubric?['can_delete'] != false;
    final lockReason = rubric?['lock_reason']?.toString();
    final isAssigned = rubric?['is_assigned'] == true;
    final assignedContext = rubric?['assigned_context_name']?.toString();

    if (!canDelete) {
      showErrorToast(
        context,
        lockReason ?? 'This rubric is assigned to active defenses or evaluations and cannot be deleted.',
      );
      return;
    }

    String dialogMessage = 'Delete $rubricName? This will permanently remove its criteria and score levels.';
    if (isAssigned && assignedContext != null && assignedContext.isNotEmpty) {
      dialogMessage =
          'This rubric is currently assigned to Defense Stage "$assignedContext". '
          'Deleting it will remove the assignment from the stage configuration. Are you sure you want to proceed?';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Rubric', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(dialogMessage, style: const TextStyle(fontSize: 13.5, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }
    final success = await ref.read(rubricEngineProvider.notifier).deleteRubric(rubricId);
    if (!mounted) {
      return;
    }
    if (success && closeEditorOnSuccess) {
      _closeRubricEditor();
    }
  }

  Widget _statusChip(Map<String, dynamic> rubric) {
    final published = rubric['status'] == 'published';
    final (label, bg, border, fg, icon) = published
        ? ('Published', const Color(0xFFF0FDF4), const Color(0xFFBBF2D0), const Color(0xFF15803D), Icons.lock_outline_rounded)
        : ('Draft', const Color(0xFFFFFBEB), const Color(0xFFFDE68A), const Color(0xFFB45309), Icons.edit_note_rounded);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  int _count(RubricEngineState state, String key) {
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

class _RubricFlexHeaderCell extends StatelessWidget {
  const _RubricFlexHeaderCell(this.text, {required this.flex});

  final String text;
  final double flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _RubricFlexTableCell extends StatelessWidget {
  const _RubricFlexTableCell(this.child, {required this.flex});

  final Widget child;
  final double flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}

class _RubricFixedHeaderCell extends StatelessWidget {
  const _RubricFixedHeaderCell(this.text, this.width);

  final String text;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _RubricFixedTableCell extends StatelessWidget {
  const _RubricFixedTableCell(this.child, this.width);

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}
