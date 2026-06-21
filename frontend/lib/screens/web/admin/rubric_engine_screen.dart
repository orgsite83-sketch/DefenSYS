import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';

import '../../../navigation/admin_route_paths.dart';
import '../../../services/auth_provider.dart';
import '../../../services/rubric_engine_provider.dart';
import '../../../theme/app_theme.dart';
import 'rubric_full_page_editor.dart';
import 'widgets/defensys_admin_shell.dart';

class RubricEngineScreen extends ConsumerStatefulWidget {
  const RubricEngineScreen({super.key});

  @override
  ConsumerState<RubricEngineScreen> createState() => _RubricEngineScreenState();
}

class _RubricEngineScreenState extends ConsumerState<RubricEngineScreen> {
  static const _kColName = 300.0;
  static const _kColStage = 200.0;
  static const _kColScope = 100.0;
  static const _kColEval = 140.0;
  static const _kColStatus = 132.0;
  static const _kRubricDataTableWidth =
      _kColName + _kColStage + _kColScope + _kColEval + _kColStatus;
  static const _kRubricActionColumnWidth = 108.0;

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
        onDelete: !_rubricEditorReadOnly && rubricId != null
            ? () => _confirmDelete(
                  rubricId,
                  target!['name']?.toString() ?? 'rubric',
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
          DefensysPageHeader(
            icon: Icons.checklist_rounded,
            title: 'Rubric Engine',
            subtitle: isPitLeadOnly
                ? 'Create and manage PIT rubrics for your events. You only see rubrics you created.'
                : 'Browse Capstone and PIT rubrics. Create new rubrics as Capstone only; PIT rubrics are managed by PIT leads.',
            actions: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _primaryButton(
                  icon: Icons.add_rounded,
                  label: 'Create Standard Rubric',
                  onTap: state.isSaving
                      ? null
                      : () => _openRubricEditor(
                            initialScope: isPitLeadOnly
                                ? 'pit'
                                : 'capstone',
                          ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          _buildStats(state, isPitLeadOnly: isPitLeadOnly),
          const SizedBox(height: 22),
          _rubricTableCard(state, isPitLeadOnly: isPitLeadOnly),
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
            title: 'Panel',
            icon: Icons.groups_rounded,
            accent: DefensysUi.primaryMaroon,
            iconBg: const Color(0xFFFFF4F4),
          ),
        ),
        if (!hideAdviser) ...[
          const SizedBox(width: 14),
          Expanded(
            child: _evaluationStatCard(
              state: state,
              evalType: 'adviser',
              title: 'Adviser',
              icon: Icons.school_rounded,
              accent: AppColors.success,
              iconBg: const Color(0xFFE7F6EC),
            ),
          ),
        ],
        const SizedBox(width: 14),
        Expanded(
          child: _evaluationStatCard(
            state: state,
            evalType: 'peer',
            title: 'Peer',
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
    required IconData icon,
    required Color accent,
    required Color iconBg,
  }) {
    final selected = state.evaluationType == evalType;
    final count = _count(state, _evalCountKey(evalType));
    final subtitle = selected
        ? 'Showing in table · tap to clear'
        : 'Tap to filter table';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: Tooltip(
        message: selected
            ? 'Show all evaluation types'
            : 'Show only $title rubrics',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: state.isSaving ? null : () => _toggleEvalFilter(evalType),
          child: Container(
            height: 112,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.08) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? accent : const Color(0xFFE5E7EB),
                width: selected ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$count',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F2743),
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF98A2B3),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
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
    return DefensysCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isPitLeadOnly || state.scope == 'pit'
                ? 'PIT rubrics define criteria only. Panel / peer grade split is set per event on Defense Scheduler (Step 1).'
                : 'Capstone: Panel / Adviser / Peer weights are set once per defense stage (Defense Stages → Edit). '
                    'PIT: grade split is per event on Defense Scheduler.',
            style: TextStyle(
              fontFamily: DefensysUi.fontFamily,
              fontSize: 12,
              height: 1.45,
              color: const Color(0xFF98A2B3),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _searchField(state)),
              const SizedBox(width: 16),
              _termFilter(state),
              if (!isPitLeadOnly) ...[
                const SizedBox(width: 16),
                _scopeFilter(state),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (state.isLoading)
            const SizedBox(
              height: 150,
              child: Center(
                child: CircularProgressIndicator(
                  color: DefensysUi.primaryMaroon,
                ),
              ),
            )
          else if (state.rubrics.isEmpty)
            _emptyRubricTable()
          else
            _rubricTableWithStickyActions(state),
          if (_showTableScrollHint && state.rubrics.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Scroll horizontally to see all columns',
              style: TextStyle(
                color: Color(0xFF98A2B3),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
        ],
      ),
    );
  }

  Widget _searchField(RubricEngineState state) {
    return SizedBox(
      height: 43,
      child: TextField(
        controller: _searchController,
        enabled: !state.isSaving,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: DefensysUi.steelGrey,
            size: 19,
          ),
          hintText: 'Search by rubric name or academic year...',
          hintStyle: const TextStyle(color: DefensysUi.steelGrey, fontSize: 13),
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: DefensysUi.primaryMaroon),
          ),
        ),
        onSubmitted: (value) {
          ref.read(rubricEngineProvider.notifier).fetchRubrics(search: value);
        },
      ),
    );
  }

  Widget _scopeFilter(RubricEngineState state) {
    return Container(
      width: 190,
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: state.scope,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: DefensysUi.textDark,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: const [
            DropdownMenuItem(value: '', child: Text('All rubrics')),
            DropdownMenuItem(
              value: 'capstone',
              child: Text('Capstone rubrics'),
            ),
            DropdownMenuItem(value: 'pit', child: Text('PIT rubrics')),
          ],
          onChanged: state.isSaving
              ? null
              : (value) {
                  ref
                      .read(rubricEngineProvider.notifier)
                      .fetchRubrics(scope: value ?? '');
                },
        ),
      ),
    );
  }

  Widget _termFilter(RubricEngineState state) {
    return Container(
      width: 168,
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: state.termContext == 'history' ? 'history' : 'active',
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: DefensysUi.textDark,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: const [
            DropdownMenuItem(value: 'active', child: Text('Current Term')),
            DropdownMenuItem(value: 'history', child: Text('History')),
          ],
          onChanged: state.isSaving
              ? null
              : (value) {
                  if (value == null) return;
                  ref
                      .read(rubricEngineProvider.notifier)
                      .fetchRubrics(termContext: value);
                },
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
      height: 51,
      width: useFlexibleColumns ? null : _kRubricDataTableWidth,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.horizontal(
          left: const Radius.circular(5),
          right: useFlexibleColumns ? Radius.zero : const Radius.circular(5),
        ),
      ),
      child: useFlexibleColumns
          ? const Row(
              children: [
                _RubricFlexHeaderCell('Rubric Name', flex: 1.55),
                _RubricFlexHeaderCell('Defense Stage', flex: 1.2),
                _RubricFlexHeaderCell('Scope', flex: 0.8),
                _RubricFlexHeaderCell('Evaluation Type', flex: 0.95),
                _RubricFlexHeaderCell('Status', flex: 0.9),
              ],
            )
          : const Row(
              children: [
                _RubricFixedHeaderCell('Rubric Name', _kColName),
                _RubricFixedHeaderCell('Defense Stage', _kColStage),
                _RubricFixedHeaderCell('Scope', _kColScope),
                _RubricFixedHeaderCell('Evaluation Type', _kColEval),
                _RubricFixedHeaderCell('Status', _kColStatus),
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
      constraints: const BoxConstraints(minHeight: 62),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
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
        border: Border(left: BorderSide(color: Color(0xFFE5E7EB))),
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
      height: 51,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F1F4),
        borderRadius: BorderRadius.horizontal(right: Radius.circular(5)),
      ),
      child: const Text(
        'Action',
        style: TextStyle(
          color: Color(0xFF5D6678),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _rubricActionRow(RubricEngineState state, Map<String, dynamic> rubric) {
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: _buildActions(state, rubric),
    );
  }

  Widget _emptyRubricTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dataAreaWidth =
            (constraints.maxWidth - _kRubricActionColumnWidth).clamp(0.0, double.infinity);
        final useFlexibleColumns = dataAreaWidth >= _kRubricDataTableWidth;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _rubricDataHeader(useFlexibleColumns: useFlexibleColumns),
                  Container(
                height: 84,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                ),
                    child: const Text(
                      'No rubrics found. Click "Create Standard Rubric" to get started.',
                      style: TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: _kRubricActionColumnWidth,
              child: Column(
                children: [
                  _rubricActionHeader(),
                  Container(
                    height: 84,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        left: BorderSide(color: Color(0xFFE5E7EB)),
                        bottom: BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
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
            color: DefensysUi.textDark,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          _rubricNameSubtitle(rubric),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF98A2B3),
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
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
      return _bodyText('PIT (template)');
    }
    final stage = rubric['defense_stage_label']?.toString().trim();
    return _bodyText(stage != null && stage.isNotEmpty ? stage : '—');
  }

  Widget _scopeCell(Map<String, dynamic> rubric) {
    final scope = rubric['scope']?.toString() ?? '';
    return _bodyText(scope == 'pit' ? 'PIT' : 'Capstone');
  }

  Widget _evaluationTypeCell(Map<String, dynamic> rubric) {
    return _evaluationTypeChip(rubric['evaluation_type']?.toString());
  }

  Widget _evaluationTypeChip(String? evalType) {
    final type = evalType ?? 'panel';
    final color = switch (type) {
      'adviser' => AppColors.success,
      'peer' => Colors.blue,
      _ => AppColors.maroon,
    };
    return _buildChip(_evaluationLabel(type), color);
  }

  Widget _bodyText(String value) {
    return Text(
      value.isEmpty ? '-' : value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: DefensysUi.textDark,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildActions(RubricEngineState state, Map<String, dynamic> rubric) {
    final published = rubric['status'] == 'published';

    if (published) {
      return Tooltip(
        message: 'View locked rubric',
        child: IconButton(
          onPressed: state.isSaving
              ? null
              : () => _openRubricEditor(rubric: rubric, readOnly: true),
          icon: Icon(
            Icons.lock_outline,
            size: 18,
            color: state.isSaving
                ? const Color(0xFFC9CED8)
                : DefensysUi.steelGrey,
          ),
          style: IconButton.styleFrom(
            minimumSize: const Size(32, 32),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            hoverColor: DefensysUi.neutralBg,
          ),
        ),
      );
    }

    return Tooltip(
      message: 'Edit rubric',
      child: IconButton(
        onPressed: state.isSaving
            ? null
            : () => _openRubricEditor(rubric: rubric),
        icon: Icon(
          Icons.edit_outlined,
          size: 18,
          color: state.isSaving
              ? const Color(0xFFC9CED8)
              : DefensysUi.primaryMaroon,
        ),
        style: IconButton.styleFrom(
          minimumSize: const Size(36, 36),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          hoverColor: DefensysUi.neutralBg,
        ),
      ),
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool outlined = false,
  }) {
    if (outlined) {
      return SizedBox(
        height: 42,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 17),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: DefensysUi.primaryMaroon,
            side: const BorderSide(color: DefensysUi.primaryMaroon, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
        ),
      );
    }
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: DefensysUi.primaryMaroon,
          foregroundColor: DefensysUi.accentGold,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    int rubricId,
    String rubricName, {
    bool closeEditorOnSuccess = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Rubric'),
        content: Text('Delete $rubricName? This removes its criteria too.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }
    await ref.read(rubricEngineProvider.notifier).deleteRubric(rubricId);
    if (!mounted) {
      return;
    }
    if (closeEditorOnSuccess) {
      _closeRubricEditor();
    }
  }

  Widget _statusChip(Map<String, dynamic> rubric) {
    final published = rubric['status'] == 'published';
    return _buildChip(
      published ? 'Published' : 'Draft',
      published ? AppColors.success : AppColors.warning,
      icon: published ? Icons.lock_outline : Icons.edit_note,
    );
  }

  Widget _buildChip(String label, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  String _evaluationLabel(String? value) {
    return switch (value) {
      'adviser' => 'Adviser',
      'peer' => 'Peer',
      _ => 'Panel',
    };
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
              color: Color(0xFF5D6678),
              fontSize: 12,
              fontWeight: FontWeight.w800,
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
              color: Color(0xFF5D6678),
              fontSize: 12,
              fontWeight: FontWeight.w800,
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
