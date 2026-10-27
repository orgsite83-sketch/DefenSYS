import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../services/auth_provider.dart';
import '../../../../services/grading/grade_masterlist_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/export/report_export_menu.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../widgets/table/table.dart';
import 'grade_center_team_detail_screen.dart';
import 'grade_table_values.dart';
export 'grade_table_values.dart';

/// The masterlist has one continuous row per entity; all evidence is on details.
class GradeMasterlist extends ConsumerStatefulWidget {
  const GradeMasterlist({
    super.key,
    required this.groupKey,
    required this.scope,
    required this.stageLabel,
    this.initialYear = '',
    this.initialSemesterId,
    this.initialAssessmentId,
    this.readinessSummary = '',
    this.onRefresh,
    this.onBack,
    this.headerActions = const [],
  });

  final String groupKey, scope, stageLabel, initialYear;
  final int? initialSemesterId, initialAssessmentId;
  final String readinessSummary;
  final VoidCallback? onRefresh;
  final VoidCallback? onBack;
  final List<Widget> headerActions;

  @override
  ConsumerState<GradeMasterlist> createState() => _GradeMasterlistState();
}

class _GradeMasterlistState extends ConsumerState<GradeMasterlist> {
  late Map<String, String> _params;
  final _search = TextEditingController();
  final _horizontal = ScrollController();
  Timer? _debounce;
  bool _overflow = false;
  GradeRow? _lastData;
  String? _lastActor;

  String get _session =>
      '${ref.read(authProvider).user?['id']}|${widget.scope}|${widget.groupKey}|${widget.initialSemesterId}|${widget.initialAssessmentId}';
  bool get _students => (_params['entity'] ?? 'students') == 'students';
  bool get _full => _params['detail_level'] == 'full';

  @override
  void initState() {
    super.initState();
    final saved =
        ref.read(gradeMasterlistSessionsProvider)[_session] ??
        const <String, String>{};
    // Only table preferences survive navigation; the opened assessment owns scope.
    _params = {
      'entity': 'students',
      'detail_level': 'summary',
      'page': '1',
      'page_size': '25',
      'ordering': 'name',
      for (final key in const [
        'entity',
        'detail_level',
        'page',
        'page_size',
        'ordering',
        'search',
        'section',
        'status',
        '_scroll',
      ])
        if (saved[key] != null) key: saved[key]!,
      'scope': widget.scope,
      'workspace':
          ref.read(authProvider).user?['role'] == 'admin' ||
              ref.read(authProvider).user?['is_pit_lead'] == true
          ? 'operations'
          : '',
      'coverage': 'assessment',
      if (widget.initialYear.isNotEmpty) 'year_level': widget.initialYear,
      if (widget.initialSemesterId != null)
        'semester_id': '${widget.initialSemesterId}',
      if (widget.initialAssessmentId != null)
        widget.scope == 'pit' ? 'pit_event_config_id' : 'defense_stage_id':
            '${widget.initialAssessmentId}'
      else
        'stage_label': widget.stageLabel,
    };
    _search.text = _params['search'] ?? '';
    final offset = double.tryParse(_params.remove('_scroll') ?? '');
    if (offset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_horizontal.hasClients) {
          _horizontal.jumpTo(
            offset.clamp(0, _horizontal.position.maxScrollExtent),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _set(Map<String, String> changes, {bool resetPage = true}) {
    _debounce?.cancel();
    setState(() {
      _params = {..._params, 'search': _search.text, ...changes};
      if (resetPage) _params['page'] = '1';
    });
    ref.read(gradeMasterlistSessionsProvider.notifier).save(_session, _params);
  }

  void _sort(String key) =>
      _set({'ordering': _params['ordering'] == key ? '-$key' : key});

  Widget _select(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> onChanged, {
    double width = 180,
  }) {
    final selected = options.containsKey(value) ? value : null;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          ShadSelect<String>(
            key: ValueKey('$label-$selected-${options.keys.join()}'),
            initialValue: selected,
            placeholder: Text(label),
            options: options.entries.map(
              (entry) => ShadOption(value: entry.key, child: Text(entry.value)),
            ),
            selectedOptionBuilder: (_, selection) => Text(
              options[selection] ?? label,
              overflow: TextOverflow.ellipsis,
            ),
            onChanged: (selection) {
              if (selection != null) onChanged(selection);
            },
          ),
        ],
      ),
    );
  }

  void _open(GradeRow row, GradeRow cell, GradeRow contextData) {
    final gradeId = gradeNumber(cell['grade_id'])?.toInt();
    final studentId = gradeNumber(row['student_id'])?.toInt();
    final params = <String, String>{
      'locked': cell['is_locked'] == true ? '1' : '0',
      if (studentId != null) 'student_id': '$studentId',
      'detail': _full ? 'full' : 'summary',
    };
    ref.read(gradeMasterlistSessionsProvider.notifier).save(_session, {
      ..._params,
      if (_horizontal.hasClients) '_scroll': '${_horizontal.offset}',
    });
    if (gradeId == null) {
      final pendingParams =
          {
            ..._params,
            'coverage': 'assessment',
            'semester_id': '${contextData['semester_id']}',
            if (studentId != null) 'student_id': '$studentId',
            if (studentId == null) 'team_id': '${row['id']}',
            if (cell['assessment_id'] != null)
              widget.scope == 'pit'
                      ? 'pit_event_config_id'
                      : 'defense_stage_id':
                  '${cell['assessment_id']}',
          }..removeWhere(
            (key, _) =>
                ['search', 'status', 'page', '_scroll'].contains(key) ||
                key == 'stage_label' && cell['assessment_id'] != null,
          );
      if (cell['assessment_id'] == null &&
          contextData['assessment_label'] != null) {
        pendingParams['stage_label'] =
            '${cell['assessment_label'] ?? contextData['assessment_label']}';
      }
      try {
        final router = GoRouter.of(context);
        final root =
            router.routeInformationProvider.value.uri.path.startsWith(
              '/faculty/',
            )
            ? '/faculty'
            : '/admin';
        router.push(
          Uri(
            path: '$root/grade-center/pending',
            queryParameters: pendingParams,
          ).toString(),
        );
      } catch (_) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              backgroundColor: DefensysTokens.backgroundOf(context),
              body: GradePendingDetails(
                row: row,
                cell: cell,
                contextData: contextData,
              ),
            ),
          ),
        );
      }
      return;
    }
    try {
      final router = GoRouter.of(context);
      final root =
          router.routeInformationProvider.value.uri.path.startsWith('/faculty/')
          ? '/faculty'
          : '/admin';
      router.push(
        Uri(
          path: '$root/grade-center/grades/$gradeId',
          queryParameters: params,
        ).toString(),
      );
    } catch (_) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            backgroundColor: DefensysTokens.backgroundOf(context),
            body: GradeCenterTeamDetailScreen(
              gradeId: gradeId,
              isLocked: cell['is_locked'] == true,
              initialStudentId: studentId,
              initialFullBreakdown: studentId != null,
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      );
    }
  }

  Widget _text(dynamic value, {String? secondary, bool number = false}) =>
      Column(
        crossAxisAlignment: number
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value?.toString() ?? '—',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          if (secondary != null && secondary.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              secondary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ],
        ],
      );

  Widget _score(GradeRow cell, String component, {bool weighted = false}) {
    final values = gradeMap(gradeMap(cell['components'])[component]);
    if (values['enabled'] == false) return _text('N/A', number: true);
    if (weighted) {
      final contribution = gradeNumber(values['weighted']);
      return _text(
        contribution?.toStringAsFixed(2) ?? '—',
        secondary: values['weight'] == null
            ? null
            : '${values['weight']}% weight',
        number: true,
      );
    }
    return _text(
      gradePercent(values['score']),
      secondary: [
        if ((cell['missing_components'] as List? ?? []).contains(component))
          'Pending',
        if (component == 'panel' &&
            cell['panel_required'] != null &&
            cell['panel_required'] != 0)
          '${cell['panel_submitted'] ?? 0}/${cell['panel_required']} evaluators',
      ].join(' · '),
      number: true,
    );
  }

  List<DefensysTableColumn<GradeRow>> _columns(
    List<GradeRow> rows,
    GradeRow contextData,
  ) {
    GradeRow first(GradeRow row) =>
        gradeMaps(row['assessments']).firstOrNull ?? {};
    DefensysTableColumn<GradeRow> column(
      String title,
      String key,
      Widget Function(GradeRow) builder, {
      double width = 130,
      bool number = false,
      bool sortable = true,
    }) => DefensysTableColumn(
      title: title,
      minWidth: width,
      flex: width / 120,
      alignment: number ? Alignment.centerRight : Alignment.centerLeft,
      isSortable: sortable,
      onSort: sortable ? () => _sort(key) : null,
      sortAscending: _params['ordering']?.replaceFirst('-', '') == key
          ? !_params['ordering']!.startsWith('-')
          : null,
      cellBuilder: (_, row, _) => builder(row),
    );
    final columns = <DefensysTableColumn<GradeRow>>[
      column(
        _students ? 'Student / ID' : 'Team / Project',
        'name',
        (row) {
          final cell = first(row);
          final identity = _students
              ? row['student_number']?.toString()
              : gradeMap(cell['team'])['project_title']?.toString();
          return Semantics(
            button: true,
            child: LayoutBuilder(
              builder: (_, constraints) => ShadButton.link(
                padding: EdgeInsets.zero,
                height: null,
                onPressed: () => _open(row, cell, contextData),
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: _text(row['name'], secondary: identity),
                ),
              ),
            ),
          );
        },
        width: _students ? 205 : 265,
      ),
      column('Section', 'section', (row) => _text(row['section']), width: 110),
      if (_students)
        column(
          'Team',
          'team_name',
          (row) => _text(row['team_name']),
          width: 165,
        ),
    ];
    if (_full) {
      final count = rows.fold<int>(
        gradeNumber(contextData['evaluator_slots'])?.toInt() ?? 0,
        (maximum, row) =>
            math.max(maximum, gradeMaps(first(row)['evaluators']).length),
      );
      for (var index = 0; index < count; index++) {
        columns.add(
          column(
            'Panel ${index + 1}',
            '',
            (row) {
              final evaluators = gradeMaps(first(row)['evaluators']);
              return index >= evaluators.length
                  ? _text('N/A', number: true)
                  : _text(
                      gradePercent(evaluators[index]['score']),
                      secondary: evaluators[index]['name']?.toString(),
                      number: true,
                    );
            },
            width: 155,
            number: true,
            sortable: false,
          ),
        );
      }
    }
    for (final name in [
      'panel',
      if (widget.scope == 'capstone') 'adviser',
      'peer',
    ]) {
      final label = '${name[0].toUpperCase()}${name.substring(1)}';
      columns.add(
        column(label, name, (row) => _score(first(row), name), number: true),
      );
      if (_full) {
        columns.add(
          column(
            '$label weighted',
            '',
            (row) => _score(first(row), name, weighted: true),
            number: true,
            sortable: false,
          ),
        );
      }
    }
    columns.add(
      column(
        _students ? 'Individual final' : 'Team final',
        'final_grade',
        (row) => _text(
          gradePercent(first(row)['final_grade']),
          secondary: first(row)['final_grade'] == null ? 'Pending' : null,
          number: true,
        ),
        number: true,
      ),
    );
    columns.add(
      column(
        'Grading status',
        'status',
        (row) => _text(
          first(row)['status_label'],
          secondary: first(row)['outcome']?.toString(),
        ),
        width: 170,
      ),
    );
    return columns;
  }

  void _changeEntity(String value) {
    _search.clear();
    _set({'entity': value, 'status': '', 'search': ''});
  }

  Widget _viewTabs() => LayoutBuilder(
    builder: (_, constraints) {
      if (constraints.maxWidth < 340) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in const ['students', 'teams'])
              Semantics(
                selected: (_students ? 'students' : 'teams') == value,
                child: (_students ? 'students' : 'teams') == value
                    ? ShadButton(
                        onPressed: () {},
                        child: Text(
                          value == 'students'
                              ? 'Student Grades'
                              : 'Team Grades',
                        ),
                      )
                    : ShadButton.outline(
                        onPressed: () => _changeEntity(value),
                        child: Text(
                          value == 'students'
                              ? 'Student Grades'
                              : 'Team Grades',
                        ),
                      ),
              ),
          ],
        );
      }
      return DefensysSegmentedControl<String>(
        value: _students ? 'students' : 'teams',
        items: const [
          DefensysSegmentItem(
            value: 'students',
            label: 'Student Grades',
            icon: Icons.people_outline,
          ),
          DefensysSegmentItem(
            value: 'teams',
            label: 'Team Grades',
            icon: Icons.groups_outlined,
          ),
        ],
        onChanged: _changeEntity,
      );
    },
  );

  Widget _modeToggle() => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final mode in const ['summary', 'full'])
        Semantics(
          selected: (_full ? 'full' : 'summary') == mode,
          child: (_full ? 'full' : 'summary') == mode
              ? ShadButton(
                  onPressed: () {},
                  child: Text(mode == 'summary' ? 'Summary' : 'Full breakdown'),
                )
              : ShadButton.outline(
                  onPressed: () => _set({'detail_level': mode}),
                  child: Text(mode == 'summary' ? 'Summary' : 'Full breakdown'),
                ),
        ),
    ],
  );

  Map<String, String> _exportParams(GradeRow contextData) {
    final assessmentId = contextData['assessment_id'];
    return {
      ..._params,
      'search': _search.text,
      if (contextData['semester_id'] != null)
        'semester_id': '${contextData['semester_id']}',
      'year_level': contextData['year_level']?.toString() ?? widget.initialYear,
      if (assessmentId != null)
        widget.scope == 'pit' ? 'pit_event_config_id' : 'defense_stage_id':
            '$assessmentId',
      if (assessmentId == null)
        'stage_label':
            contextData['assessment_label']?.toString() ?? widget.stageLabel,
    }..removeWhere(
      (key, _) =>
          ['page', 'page_size', '_scroll'].contains(key) ||
          key == 'stage_label' && assessmentId != null,
    );
  }

  Widget _header(GradeRow contextData, String query, {required bool ready}) {
    final metadata = [
      widget.scope == 'pit' ? 'PIT' : 'Capstone',
      if (contextData['academic_period'] != null)
        '${contextData['academic_period']}',
      if ((contextData['year_level']?.toString() ?? widget.initialYear)
          .isNotEmpty)
        contextData['year_level']?.toString() ?? widget.initialYear,
    ].join(' · ');
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.stageLabel,
          style: TextStyle(
            fontSize: 22,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          metadata,
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        if (widget.readinessSummary.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            widget.readinessSummary,
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ],
    );
    final back = widget.onBack == null
        ? null
        : ShadButton.outline(
            onPressed: widget.onBack,
            leading: const Icon(Icons.arrow_back_rounded, size: 16),
            child: const Text('Back'),
          );
    final actions = [
      ...widget.headerActions,
      ReportExportMenu(
        reportId: _students
            ? 'student-grade-masterlist'
            : 'team-grade-masterlist',
        params: _exportParams(contextData),
        enabled: ready,
        configureExport: true,
      ),
      Tooltip(
        message: 'Refresh grades',
        child: ShadButton.outline(
          width: 40,
          padding: EdgeInsets.zero,
          onPressed: () {
            ref.invalidate(gradeMasterlistDataProvider(query));
            widget.onRefresh?.call();
          },
          child: const Icon(Icons.refresh_rounded, size: 18),
        ),
      ),
    ];
    return LayoutBuilder(
      builder: (_, constraints) {
        if (constraints.maxWidth <
            (widget.headerActions.isEmpty ? 900 : 1100)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (back != null) ...[back, const SizedBox(height: 12)],
              title,
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (back != null) ...[back, const SizedBox(width: 14)],
            Expanded(child: title),
            const SizedBox(width: 20),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        );
      },
    );
  }

  Widget _searchField() => Semantics(
    label: _students
        ? 'Search students, IDs or teams'
        : 'Search teams or projects',
    child: ShadInput(
      controller: _search,
      leading: const Icon(Icons.search_rounded, size: 16),
      placeholder: Text(
        _students
            ? 'Search students, IDs or teams…'
            : 'Search teams or projects…',
      ),
      onChanged: (value) {
        // The clear action should appear immediately while the query is debounced.
        setState(() {});
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 350), () {
          if (mounted) _set({'search': value});
        });
      },
    ),
  );

  bool get _hasFilters =>
      _search.text.isNotEmpty ||
      (_params['search'] ?? '').isNotEmpty ||
      (_params['section'] ?? '').isNotEmpty ||
      (_params['status'] ?? '').isNotEmpty;

  Widget _filters(GradeRow options) => LayoutBuilder(
    builder: (_, constraints) {
      final section = _select(
        'Section',
        _params['section'] ?? '',
        {
          '': 'All sections',
          for (final item in options['sections'] as List? ?? [])
            '$item': '$item',
        },
        (value) => _set({'section': value}),
        width: 160,
      );
      final status = _select(
        'Grading status',
        _params['status'] ?? '',
        {
          '': 'All statuses',
          for (final item in gradeMaps(options['statuses']))
            '${item['value']}': '${item['label']}',
        },
        (value) => _set({'status': value}),
        width: 195,
      );
      final clear = _hasFilters
          ? ShadButton.ghost(
              onPressed: () {
                _search.clear();
                _set({'search': '', 'section': '', 'status': ''});
              },
              child: const Text('Clear filters'),
            )
          : null;
      if (constraints.maxWidth >= 860) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: _searchField()),
            const SizedBox(width: 12),
            section,
            const SizedBox(width: 12),
            status,
            if (clear != null) ...[const SizedBox(width: 8), clear],
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _searchField(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [section, status, if (clear != null) clear],
          ),
        ],
      );
    },
  );

  Widget _tableWorkspace(GradeRow data, {required bool loading}) {
    final rows = gradeMaps(data['rows']);
    final contextData = gradeMap(data['context']);
    return DefensysTableCard(
      key: const ValueKey('grade-table-workspace'),
      showScrollHint: _overflow,
      pagination: DefensysTablePagination(
        currentPage: (gradeNumber(data['page'])?.toInt() ?? 1) - 1,
        totalItems: gradeNumber(data['total'])?.toInt() ?? 0,
        rowsPerPage: gradeNumber(data['page_size'])?.toInt() ?? 25,
        itemLabel: _students ? 'students' : 'teams',
        onPageChanged: (page) =>
            _set({'page': '${page + 1}'}, resetPage: false),
        onRowsPerPageChanged: (size) => _set({'page_size': '$size'}),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            key: const ValueKey('grade-table-controls'),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (_, constraints) {
                    if (constraints.maxWidth < 760) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _viewTabs(),
                          const SizedBox(height: 12),
                          _modeToggle(),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: _viewTabs()),
                        const SizedBox(width: 16),
                        _modeToggle(),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                _filters(gradeMap(data['options'])),
                const SizedBox(height: 14),
                Text(
                  '${data['total']} ${_students ? 'students' : 'teams'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: DefensysTokens.borderOf(context)),
          if (loading)
            LinearProgressIndicator(
              minHeight: 2,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          AbsorbPointer(
            absorbing: loading,
            child: DefensysDataTable<GradeRow>(
              items: rows,
              columns: _columns(rows, contextData),
              rowMinHeight: 64,
              headerHeight: 58,
              horizontalScrollController: _horizontal,
              onScrollHintChanged: (value) {
                if (mounted && _overflow != value) {
                  setState(() => _overflow = value);
                }
              },
              onRowTap: (row) => _open(
                row,
                gradeMaps(row['assessments']).firstOrNull ?? {},
                contextData,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = masterlistQueryKey(_params);
    final result = ref.watch(gradeMasterlistDataProvider(query));
    final actor = ref.watch(authProvider).user;
    final actorKey =
        '${actor?['id']}|${actor?['role']}|${actor?['is_pit_lead']}|${actor?['pit_lead_year']}';
    if (_lastActor != actorKey) {
      _lastData = null;
      _lastActor = actorKey;
    }
    if (result.asData != null) _lastData = result.asData!.value;
    final displayed = result.isLoading && _lastData != null
        ? AsyncData<GradeRow>(_lastData!)
        : result;
    return DefensysShadcnScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(
            gradeMap(_lastData?['context']),
            query,
            ready: !result.isLoading && !result.hasError,
          ),
          const SizedBox(height: 20),
          displayed.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(error.toString().replaceFirst('Exception: ', '')),
                const SizedBox(height: 12),
                ShadButton.outline(
                  onPressed: () =>
                      ref.invalidate(gradeMasterlistDataProvider(query)),
                  child: const Text('Retry grade list'),
                ),
              ],
            ),
            data: (data) => _tableWorkspace(data, loading: result.isLoading),
          ),
        ],
      ),
    );
  }
}

class GradePendingDetails extends StatelessWidget {
  const GradePendingDetails({
    super.key,
    required this.row,
    required this.cell,
    this.contextData = const {},
  });
  final GradeRow row, cell;
  final GradeRow contextData;

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to grades'),
          ),
          const SizedBox(height: 24),
          Text(
            '${row['name']}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text('${row['student_number'] ?? ''} · ${row['section'] ?? ''}'),
          if (contextData['academic_period'] != null ||
              cell['assessment_label'] != null) ...[
            const SizedBox(height: 6),
            Text(
              '${contextData['academic_period'] ?? ''} · ${cell['assessment_label'] ?? contextData['assessment_label'] ?? ''}',
            ),
          ],
          const SizedBox(height: 24),
          Text(
            '${cell['status_label'] ?? 'Not assessed'}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            cell['team'] == null
                ? 'This student has no team assigned for the selected assessment.'
                : 'No evaluation record has been recorded for this assessment.',
          ),
        ],
      ),
    ),
  );
}
