import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../services/auth_provider.dart';
import '../../../../services/grading/grade_masterlist_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/export/report_catalog.dart';
import '../../../../widgets/export/report_export_configuration.dart';
import '../../../../widgets/export/report_export_menu.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../widgets/table/table.dart';
import '../widgets/defensys_admin_shell.dart';
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
    this.assessmentControls,
    this.onBack,
  });

  final String groupKey, scope, stageLabel, initialYear;
  final int? initialSemesterId;
  final Widget? assessmentControls;
  final VoidCallback? onBack;

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
      '${ref.read(authProvider).user?['id']}|${widget.scope}|${widget.groupKey}';
  bool get _students => (_params['entity'] ?? 'students') == 'students';
  bool get _semester => _params['coverage'] == 'semester';
  bool get _full => _params['detail_level'] == 'full';

  @override
  void initState() {
    super.initState();
    _params = Map<String, String>.from(
      ref.read(gradeMasterlistSessionsProvider)[_session] ??
          {
            'scope': widget.scope,
            'workspace':
                ref.read(authProvider).user?['role'] == 'admin' ||
                    ref.read(authProvider).user?['is_pit_lead'] == true
                ? 'operations'
                : '',
            'entity': 'students',
            'coverage': 'assessment',
            'detail_level': 'summary',
            'stage_label': widget.stageLabel,
            if (widget.initialYear.isNotEmpty) 'year_level': widget.initialYear,
            if (widget.initialSemesterId != null)
              'semester_id': '${widget.initialSemesterId}',
            'page': '1',
            'page_size': '25',
            'ordering': 'name',
          },
    );
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
      _params = {..._params, ...changes};
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
        secondary: '${values['weight'] ?? '—'}% weight',
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
    List<GradeRow> assessments,
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
          return _semester
              ? _text(row['name'], secondary: identity)
              : Semantics(
                  button: true,
                  child: ShadButton.link(
                    padding: EdgeInsets.zero,
                    height: null,
                    onPressed: () => _open(row, cell, contextData),
                    child: _text(row['name'], secondary: identity),
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
    if (_semester) {
      for (final assessment in assessments) {
        columns.add(
          column(
            assessment['label'].toString(),
            '',
            (row) {
              final cell = gradeMaps(row['assessments'])
                  .where((c) => c['assessment_key'] == assessment['key'])
                  .firstOrNull;
              if (cell == null) return _text('N/A');
              return ShadButton.link(
                padding: EdgeInsets.zero,
                height: null,
                onPressed: () => _open(row, cell, contextData),
                child: _text(
                  gradePercent(cell['final_grade']),
                  secondary: cell['status_label']?.toString(),
                  number: true,
                ),
              );
            },
            width: 195,
            number: true,
            sortable: false,
          ),
        );
      }
      return columns;
    }
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

  Widget _viewTabs() {
    void change(String value) {
      _search.clear();
      _set({'entity': value, 'status': '', 'search': ''});
    }

    return LayoutBuilder(
      builder: (_, constraints) {
        if (constraints.maxWidth < 330) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in const ['students', 'teams'])
                if ((_students ? 'students' : 'teams') == value)
                  ShadButton(
                    onPressed: () {},
                    child: Text(
                      value == 'students' ? 'Student Grades' : 'Team Grades',
                    ),
                  )
                else
                  ShadButton.outline(
                    onPressed: () => change(value),
                    child: Text(
                      value == 'students' ? 'Student Grades' : 'Team Grades',
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
          onChanged: change,
        );
      },
    );
  }

  Widget _header(GradeRow contextData) {
    final title = _semester
        ? '${widget.scope.toUpperCase()} · Semester grades'
        : '${widget.scope.toUpperCase()} · ${contextData['assessment_label'] ?? widget.stageLabel}';
    const subtitle =
        'Student and team evaluation records. Select a name for the complete assessment.';
    final back = ShadButton.outline(
      onPressed: widget.onBack,
      child: const Text('Back to Evaluation & Grades'),
    );
    return LayoutBuilder(
      builder: (_, constraints) {
        if (constraints.maxWidth < 650) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefensysPageHeader(
                icon: Icons.star_rounded,
                title: title,
                subtitle: subtitle,
              ),
              const SizedBox(height: 12),
              back,
            ],
          );
        }
        return DefensysPageHeader(
          icon: Icons.star_rounded,
          title: title,
          subtitle: subtitle,
          actions: back,
        );
      },
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
          if (widget.onBack != null) ...[
            _header(gradeMap(_lastData?['context'])),
            const SizedBox(height: 20),
          ],
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
            data: (data) {
              final rows = gradeMaps(data['rows']);
              final options = gradeMap(data['options']);
              final contextData = gradeMap(data['context']);
              final assessments = gradeMaps(data['assessments']);
              final user = ref.watch(authProvider).user;
              final lead =
                  user?['is_pit_lead'] == true &&
                  user?['role'] != 'admin' &&
                  user?['is_superuser'] != true;
              final selectedAssessment =
                  contextData['assessment_id']?.toString() ??
                  contextData['assessment_key']?.toString() ??
                  '';
              final exportParams =
                  <String, String>{
                    ..._params,
                    'semester_id': '${contextData['semester_id']}',
                    'year_level': contextData['year_level']?.toString() ?? '',
                    if (gradeNumber(selectedAssessment) != null)
                      widget.scope == 'pit'
                              ? 'pit_event_config_id'
                              : 'defense_stage_id':
                          selectedAssessment,
                    if (gradeNumber(selectedAssessment) == null)
                      'stage_label':
                          contextData['assessment_label']?.toString() ??
                          _params['stage_label'] ??
                          '',
                  }..removeWhere(
                    (key, _) =>
                        ['page', 'page_size', '_scroll'].contains(key) ||
                        key == 'stage_label' &&
                            gradeNumber(selectedAssessment) != null,
                  );
              final reportId = _students
                  ? 'student-grade-masterlist'
                  : 'team-grade-masterlist';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result.isLoading) ...[
                    LinearProgressIndicator(
                      minHeight: 2,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (widget.assessmentControls != null &&
                      !_semester &&
                      '${contextData['semester_id']}' ==
                          '${widget.initialSemesterId}' &&
                      assessments.length == 1 &&
                      assessments.first['label'] == widget.stageLabel &&
                      (widget.initialYear.isEmpty ||
                          assessments.first['year_level'] ==
                              widget.initialYear ||
                          widget.scope == 'capstone')) ...[
                    widget.assessmentControls!,
                    const SizedBox(height: 20),
                  ],
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      _select(
                        'Academic period',
                        '${contextData['semester_id']}',
                        {
                          for (final term in gradeMaps(options['semesters']))
                            '${term['id']}': '${term['label']}',
                        },
                        (value) => _set({
                          'semester_id': value,
                          'pit_event_config_id': '',
                          'defense_stage_id': '',
                          'stage_label': '',
                          'section': '',
                        }),
                        width: 260,
                      ),
                      _select(
                        'Coverage',
                        _params['coverage'] ?? 'assessment',
                        const {
                          'assessment': 'Selected assessment',
                          'semester': 'Whole semester',
                        },
                        (value) => _set({'coverage': value, 'status': ''}),
                        width: 215,
                      ),
                      if (!lead)
                        _select(
                          'Year level',
                          _params['year_level'] ?? '',
                          const {
                            '': 'All eligible years',
                            '1st Year': '1st Year',
                            '2nd Year': '2nd Year',
                            '3rd Year': '3rd Year',
                            '4th Year': '4th Year',
                          },
                          (value) => _set({
                            'year_level': value,
                            'pit_event_config_id': '',
                            'defense_stage_id': '',
                            'stage_label': '',
                            'section': '',
                          }),
                          width: 160,
                        ),
                      if (!_semester &&
                          gradeMaps(options['assessments']).isNotEmpty)
                        _select(
                          widget.scope == 'pit' ? 'PIT event' : 'Defense stage',
                          selectedAssessment,
                          {
                            for (final a in gradeMaps(options['assessments']))
                              a['id']?.toString() ?? '${a['key']}':
                                  '${a['label']}${!lead && widget.scope == 'pit' ? ' · ${a['year_level']}' : ''}',
                          },
                          (value) {
                            final choice = gradeMaps(options['assessments'])
                                .firstWhere(
                                  (a) =>
                                      (a['id']?.toString() ?? '${a['key']}') ==
                                      value,
                                );
                            _set({
                              widget.scope == 'pit'
                                      ? 'pit_event_config_id'
                                      : 'defense_stage_id':
                                  choice['id']?.toString() ?? '',
                              'stage_label': choice['id'] == null
                                  ? '${choice['label']}'
                                  : '',
                              'status': '',
                            });
                          },
                          width: 285,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _viewTabs(),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (!_semester) ...[
                        if (!_full)
                          ShadButton(
                            onPressed: () {},
                            child: const Text('Summary'),
                          )
                        else
                          ShadButton.outline(
                            onPressed: () => _set({'detail_level': 'summary'}),
                            child: const Text('Summary'),
                          ),
                        if (_full)
                          ShadButton(
                            onPressed: () {},
                            child: const Text('Full breakdown'),
                          )
                        else
                          ShadButton.outline(
                            onPressed: () => _set({'detail_level': 'full'}),
                            child: const Text('Full breakdown'),
                          ),
                      ],
                      ReportExportMenu(
                        reportId: reportId,
                        params: exportParams,
                      ),
                      ShadButton.outline(
                        onPressed: () => showReportExportConfiguration(
                          context: context,
                          ref: ref,
                          report: ReportCatalog.find(reportId)!,
                          params: exportParams,
                          initialFormat: 'xlsx',
                        ),
                        child: const Text('Configure export'),
                      ),
                      ShadButton.ghost(
                        onPressed: () =>
                            ref.invalidate(gradeMasterlistDataProvider(query)),
                        child: const Text('Refresh'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (_, constraints) => Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        SizedBox(
                          width: math.min(320, constraints.maxWidth),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _students
                                    ? 'Search students, IDs or teams'
                                    : 'Search teams or projects',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: DefensysTokens.textSecondaryOf(
                                    context,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              ShadInput(
                                controller: _search,
                                placeholder: const Text('Search grades…'),
                                onChanged: (value) {
                                  _debounce?.cancel();
                                  _debounce = Timer(
                                    const Duration(milliseconds: 350),
                                    () {
                                      if (mounted) _set({'search': value});
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        _select(
                          'Section',
                          _params['section'] ?? '',
                          {
                            '': 'All sections',
                            for (final section
                                in options['sections'] as List? ?? [])
                              '$section': '$section',
                          },
                          (value) => _set({'section': value}),
                          width: 155,
                        ),
                        _select(
                          _semester
                              ? 'Any assessment status'
                              : 'Grading status',
                          _params['status'] ?? '',
                          {
                            '': 'All statuses',
                            for (final status in gradeMaps(options['statuses']))
                              '${status['value']}': '${status['label']}',
                          },
                          (value) => _set({'status': value}),
                          width: 195,
                        ),
                        ShadButton.ghost(
                          onPressed: () {
                            _search.clear();
                            _set({'search': '', 'section': '', 'status': ''});
                          },
                          child: const Text('Clear filters'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${data['total']} ${_students ? 'students · Includes pending and unassigned students' : 'teams'} · ${contextData['academic_period']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DefensysTableCard(
                    showScrollHint: _overflow,
                    pagination: DefensysTablePagination(
                      currentPage:
                          (gradeNumber(data['page'])?.toInt() ?? 1) - 1,
                      totalItems: gradeNumber(data['total'])?.toInt() ?? 0,
                      rowsPerPage:
                          gradeNumber(data['page_size'])?.toInt() ?? 25,
                      itemLabel: _students ? 'students' : 'teams',
                      onPageChanged: (page) =>
                          _set({'page': '${page + 1}'}, resetPage: false),
                      onRowsPerPageChanged: (size) =>
                          _set({'page_size': '$size'}),
                    ),
                    child: DefensysDataTable<GradeRow>(
                      items: rows,
                      columns: _columns(rows, assessments, contextData),
                      rowMinHeight: 64,
                      headerHeight: 58,
                      horizontalScrollController: _horizontal,
                      onScrollHintChanged: (value) {
                        if (mounted && _overflow != value) {
                          setState(() => _overflow = value);
                        }
                      },
                      onRowTap: _semester
                          ? null
                          : (row) => _open(
                              row,
                              gradeMaps(row['assessments']).firstOrNull ?? {},
                              contextData,
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _semester
                        ? 'Select an assessment grade for its complete evaluation. No semester total is configured.'
                        : 'Select a ${_students ? 'student' : 'team'} for rubric marks, feedback and evaluation history. Exports include every matching page.',
                    style: TextStyle(
                      fontSize: 12,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ],
              );
            },
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
