import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';

import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/auth_provider.dart';
import '../../../../services/rubric_engine_provider.dart';
import '../../../../services/unsaved_changes_provider.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/feedback/empty_state.dart';
import '../../../../widgets/table/table.dart';
import 'rubric_full_page_editor.dart';
import '../widgets/defensys_admin_shell.dart';
import '../admin_shell.dart';

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
  static const _kRubricActionColumnWidth = 80.0;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _surfaceColor => _isDark ? DefensysTokens.mistSurface : Colors.white;
  Color get _borderColor => _isDark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0);
  Color get _textPrimaryColor => _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF0F172A);
  Color get _textSecondaryColor => _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF64748B);
  Color get _subtleFillColor => _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF1F5F9);

  final _searchController = TextEditingController();
  final _tableHScrollController = ScrollController();
  bool _showTableScrollHint = false;

  bool _rubricEditorOpen = false;
  bool _rubricEditorReadOnly = false;
  Map<String, dynamic>? _rubricEditorTarget;
  String? _rubricEditorInitialEval;
  String? _rubricEditorInitialScope;
  UnsavedChangesNotifier? _unsavedNotifier;
  UnsavedChangesSaveDraftNotifier? _unsavedDraftNotifier;

  @override
  void initState() {
    super.initState();
    _tableHScrollController.addListener(_updateTableScrollHint);
    _unsavedNotifier = ref.read(unsavedChangesProvider.notifier);
    _unsavedDraftNotifier = ref.read(unsavedChangesSaveDraftProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider).user;
      ref.read(rubricEngineProvider.notifier).fetchRubrics(
            scope: _isPitLeadOnly(user) ? 'pit' : null,
            status: '',
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
    _unsavedDraftNotifier?.setCallback(null);
    _unsavedNotifier?.setDirty(false);
    super.dispose();
  }

  void _openRubricEditor({
    Map<String, dynamic>? rubric,
    String? initialEvaluationType,
    String? initialScope,
    bool readOnly = false,
  }) {
    if (GoRouterState.of(context).uri.path == AdminRoutes.rubrics) {
      final id = rubric != null ? _asInt(rubric['id']) : null;
      context.go(
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

    ref.listen<DefensysAdminSection>(
      activeAdminSectionProvider,
      (previous, next) {
        if (next == DefensysAdminSection.rubrics) {
          final user = ref.read(authProvider).user;
          ref.read(rubricEngineProvider.notifier).fetchRubrics(
                scope: _isPitLeadOnly(user) ? 'pit' : null,
                status: '',
                termContext: 'active',
              );
        }
      },
    );

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
      title: 'Evaluation Rubrics',
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
        color: _isDark ? _surfaceColor : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.2 : 0.02),
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
              color: DefensysUi.primaryMaroon.withValues(alpha: _isDark ? 0.2 : 0.08),
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
                Text(
                  'Weight Distribution & Scope Configuration',
                  style: TextStyle(
                    color: _textPrimaryColor,
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
                  style: TextStyle(
                    color: _textSecondaryColor,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 780;
        final cards = [
          _evaluationStatCard(
            state: state,
            evalType: 'panel',
            title: 'Panel Rubrics',
            badgeText: 'PANEL',
            icon: Icons.groups_rounded,
            accent: DefensysUi.primaryMaroon,
            iconBg: const Color(0xFFFFF1F2),
          ),
          if (!hideAdviser)
            _evaluationStatCard(
              state: state,
              evalType: 'adviser',
              title: 'Adviser Rubrics',
              badgeText: 'ADVISER',
              icon: Icons.school_rounded,
              accent: const Color(0xFF059669),
              iconBg: const Color(0xFFECFDF5),
            ),
          _evaluationStatCard(
            state: state,
            evalType: 'peer',
            title: 'Peer Rubrics',
            badgeText: 'PEER',
            icon: Icons.people_alt_rounded,
            accent: const Color(0xFF2563EB),
            iconBg: const Color(0xFFEFF6FF),
          ),
        ];

        if (isNarrow) {
          return Column(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                cards[i],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 14),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
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
              color: selected
                  ? accent.withValues(alpha: _isDark ? 0.15 : 0.05)
                  : _surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? accent : _borderColor,
                width: selected ? 1.8 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: selected
                      ? accent.withValues(alpha: _isDark ? 0.25 : 0.12)
                      : Colors.black.withValues(alpha: _isDark ? 0.2 : 0.03),
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
                    color: _isDark ? accent.withValues(alpha: 0.18) : iconBg,
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
                            style: TextStyle(
                              color: _textPrimaryColor,
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
                              color: accent.withValues(alpha: _isDark ? 0.2 : 0.1),
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
                          color: selected ? accent : (_isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF334155)),
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
                            color: selected ? accent : _textSecondaryColor,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              selected ? 'Filter active · Tap to clear' : 'Tap to filter table',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected ? accent : _textSecondaryColor,
                                fontSize: 11,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                              ),
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
    return DefensysTableCard(
      searchController: _searchController,
      searchHint: 'Search rubrics by name or academic year...',
      isSearchEnabled: !state.isSaving,
      onSearchSubmitted: (value) {
        ref.read(rubricEngineProvider.notifier).fetchRubrics(search: value);
      },
      onSearchCleared: () {
        ref.read(rubricEngineProvider.notifier).fetchRubrics(search: '');
      },
      showScrollHint: _showTableScrollHint && state.rubrics.isNotEmpty,
      filterControls: [
        DefensysSegmentedControl<String>(
          value: state.termContext == 'history' ? 'history' : 'active',
          items: const [
            DefensysSegmentItem(value: 'active', label: 'Current Term'),
            DefensysSegmentItem(value: 'history', label: 'History'),
          ],
          onChanged: (val) {
            ref.read(rubricEngineProvider.notifier).fetchRubrics(termContext: val);
          },
        ),
        if (!isPitLeadOnly)
          DefensysSegmentedControl<String>(
            value: state.scope,
            items: const [
              DefensysSegmentItem(value: '', label: 'All Scopes'),
              DefensysSegmentItem(value: 'capstone', label: 'Capstone'),
              DefensysSegmentItem(value: 'pit', label: 'PIT'),
            ],
            onChanged: (val) {
              ref.read(rubricEngineProvider.notifier).fetchRubrics(scope: val);
            },
          ),
      ],
      child: DefensysDataTable<Map<String, dynamic>>(
        items: state.rubrics,
        isLoading: state.isLoading,
        emptyState: _emptyRubricTable(isPitLeadOnly: isPitLeadOnly),
        horizontalScrollController: _tableHScrollController,
        onScrollHintChanged: (show) {
          if (_showTableScrollHint != show && mounted) {
            setState(() => _showTableScrollHint = show);
          }
        },
        stickyActionColumn: DefensysActionColumn(
          width: _kRubricActionColumnWidth,
          title: 'ACTION',
          alignment: Alignment.center,
          builder: (context, rubric, _) => _buildActions(state, rubric),
        ),
        columns: [
          DefensysTableColumn(
            title: 'RUBRIC NAME',
            flex: 1.55,
            minWidth: _kColName,
            cellBuilder: (context, rubric, _) => _rubricNameCell(rubric),
          ),
          DefensysTableColumn(
            title: 'DEFENSE STAGE',
            flex: 1.2,
            minWidth: _kColStage,
            cellBuilder: (context, rubric, _) => _defenseStageCell(rubric),
          ),
          DefensysTableColumn(
            title: 'SCOPE',
            flex: 0.8,
            minWidth: _kColScope,
            cellBuilder: (context, rubric, _) => _scopeCell(rubric),
          ),
          DefensysTableColumn(
            title: 'EVALUATION',
            flex: 0.95,
            minWidth: _kColEval,
            cellBuilder: (context, rubric, _) => _evaluationTypeCell(rubric),
          ),
          DefensysTableColumn(
            title: 'STATUS',
            flex: 0.9,
            minWidth: _kColStatus,
            cellBuilder: (context, rubric, _) => _statusChip(rubric),
          ),
        ],
      ),
    );
  }


  Widget _emptyRubricTable({required bool isPitLeadOnly}) {
    return DefensysEmptyState.table(
      icon: Icons.quiz_outlined,
      title: 'No Rubrics Found',
      description:
          'No rubrics match your active filter parameters or search query.',
      size: DefensysEmptyStateSize.standard,
      secondaryAction: DefensysEmptyAction(
        label: 'Reset Filters',
        icon: Icons.refresh_rounded,
        isOutlined: true,
        onPressed: () {
          _searchController.clear();
          ref.read(rubricEngineProvider.notifier).fetchRubrics(
                scope: '',
                evaluationType: '',
                termContext: 'active',
                search: '',
              );
        },
      ),
      primaryAction: DefensysEmptyAction(
        label: 'Create Standard Rubric',
        icon: Icons.add_rounded,
        onPressed: () => _openRubricEditor(
          initialScope: isPitLeadOnly ? 'pit' : 'capstone',
        ),
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
          style: TextStyle(
            color: _textPrimaryColor,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 12, color: _textSecondaryColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                _rubricNameSubtitle(rubric),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textSecondaryColor,
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
        color: _subtleFillColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _isDark ? DefensysTokens.textPrimaryDark : const Color(0xFF334155),
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
        color: isPit
            ? (_isDark ? const Color(0xFF064E3B).withValues(alpha: 0.35) : const Color(0xFFF0FDF4))
            : (_isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.35) : const Color(0xFFEFF6FF)),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isPit
              ? (_isDark ? const Color(0xFF064E3B).withValues(alpha: 0.7) : const Color(0xFFBBF2D0))
              : (_isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.7) : const Color(0xFFBFDBFE)),
        ),
      ),
      child: Text(
        isPit ? 'PIT' : 'Capstone',
        style: TextStyle(
          color: isPit
              ? (_isDark ? const Color(0xFF34D399) : const Color(0xFF166534))
              : (_isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF)),
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
      'adviser' => (
        'Adviser',
        _isDark ? const Color(0xFF064E3B).withValues(alpha: 0.35) : const Color(0xFFECFDF5),
        _isDark ? const Color(0xFF064E3B).withValues(alpha: 0.7) : const Color(0xFFA7F3D0),
        _isDark ? const Color(0xFF34D399) : const Color(0xFF047857),
        Icons.school_outlined,
      ),
      'peer' => (
        'Peer',
        _isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.35) : const Color(0xFFEFF6FF),
        _isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.7) : const Color(0xFFBFDBFE),
        _isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
        Icons.people_outline,
      ),
      _ => (
        'Panel',
        _isDark ? const Color(0xFF881337).withValues(alpha: 0.35) : const Color(0xFFFFF1F2),
        _isDark ? const Color(0xFF881337).withValues(alpha: 0.7) : const Color(0xFFFECDD3),
        _isDark ? const Color(0xFFFDA4AF) : const Color(0xFF9F1239),
        Icons.groups_outlined,
      ),
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
    final isHardLocked = rubric['is_locked'] == true;
    final isSoftLocked = !isHardLocked &&
        (rubric['is_soft_locked'] == true || rubric['is_assigned'] == true);
    final assignedContext = rubric['assigned_context_name']?.toString();
    final canDelete = rubric['can_delete'] != false;
    final rubricId = _asInt(rubric['id']);

    String tooltipMessage = 'More actions';
    if (isHardLocked) {
      tooltipMessage = rubric['lock_reason']?.toString() ?? 'View locked rubric';
    } else if (isSoftLocked && assignedContext != null && assignedContext.isNotEmpty) {
      tooltipMessage = 'Rubric options (Assigned to $assignedContext)';
    }

    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: _surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: _borderColor),
          ),
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: _isDark ? 0.3 : 0.1),
        ),
      ),
      child: PopupMenuButton<String>(
        tooltip: tooltipMessage,
        enabled: !state.isSaving,
        icon: Container(
          width: 32,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _isDark ? _subtleFillColor : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _borderColor),
          ),
          child: Icon(
            Icons.more_horiz_rounded,
            size: 17,
            color: _textPrimaryColor,
          ),
        ),
        padding: EdgeInsets.zero,
        offset: const Offset(0, 36),
        onSelected: (value) {
          switch (value) {
            case 'view':
              _openRubricEditor(rubric: rubric, readOnly: true);
              break;
            case 'edit':
              _openRubricEditor(rubric: rubric, readOnly: false);
              break;
            case 'delete':
              if (rubricId != null) {
                _confirmDelete(
                  rubricId,
                  rubric['name']?.toString() ?? 'rubric',
                  rubric: rubric,
                );
              }
              break;
          }
        },
        itemBuilder: (context) => [
          if (isHardLocked)
            PopupMenuItem<String>(
              value: 'view',
              height: 36,
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined, size: 15, color: Color(0xFF2563EB)),
                  const SizedBox(width: 9),
                  Text(
                    'View Details',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _textPrimaryColor,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            PopupMenuItem<String>(
              value: 'edit',
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 15, color: _textPrimaryColor),
                  const SizedBox(width: 9),
                  Text(
                    'Edit Rubric',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _textPrimaryColor,
                    ),
                  ),
                ],
              ),
            ),
            if (rubricId != null) ...[
              const PopupMenuDivider(height: 1),
              PopupMenuItem<String>(
                value: 'delete',
                height: 36,
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 15,
                      color: canDelete ? AppColors.danger : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      'Delete Rubric',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: canDelete ? AppColors.danger : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
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
        ? (
            'Published',
            _isDark ? const Color(0xFF064E3B).withValues(alpha: 0.35) : const Color(0xFFF0FDF4),
            _isDark ? const Color(0xFF064E3B).withValues(alpha: 0.7) : const Color(0xFFBBF2D0),
            _isDark ? const Color(0xFF34D399) : const Color(0xFF15803D),
            Icons.check_circle_outline_rounded,
          )
        : (
            'Draft',
            _isDark ? const Color(0xFF78350F).withValues(alpha: 0.35) : const Color(0xFFFFFBEB),
            _isDark ? const Color(0xFF78350F).withValues(alpha: 0.7) : const Color(0xFFFDE68A),
            _isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
            Icons.edit_note_rounded,
          );

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

