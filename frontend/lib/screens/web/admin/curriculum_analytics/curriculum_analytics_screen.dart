import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../services/academic/curriculum_explorer_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../widgets/shadcn/defensys_workflow_widgets.dart';
import '../../../../widgets/feedback/defensys_loading.dart';
import 'widgets/curriculum_explorer_charts.dart';
import 'widgets/curriculum_evidence_dialog.dart';
import 'widgets/curriculum_meeting_export.dart';
import 'widgets/curriculum_review_panels.dart';
import 'widgets/curriculum_project_analytics.dart';

class CurriculumAnalyticsScreen extends ConsumerStatefulWidget {
  const CurriculumAnalyticsScreen({super.key});
  @override
  ConsumerState<CurriculumAnalyticsScreen> createState() =>
      _CurriculumAnalyticsScreenState();
}

class _CurriculumAnalyticsScreenState
    extends ConsumerState<CurriculumAnalyticsScreen> {
  String _tab = 'performance', _filter = 'all';
  String? _criterionId, _category, _teamCategory;
  String _projectDimension = 'category';
  int _page = 0;
  int _queryVersion = 0;
  final _reference = TextEditingController(text: '75');
  String? _referenceError;
  BuildContext? _shadContext;

  @override
  void initState() {
    super.initState();
    _reference.text = ref
        .read(curriculumExplorerProvider)
        .query
        .reference
        .toStringAsFixed(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadInitial();
    });
  }

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  void _reset() {
    _criterionId = null;
    _category = null;
    _teamCategory = null;
    _projectDimension = 'category';
    _page = 0;
    _filter = 'all';
  }

  void _fetch(CurriculumExplorerQuery query) {
    _queryVersion++;
    setState(_reset);
    ref.read(curriculumExplorerProvider.notifier).fetch(query);
  }

  Future<void> _loadInitial() async {
    final version = _queryVersion;
    final notifier = ref.read(curriculumExplorerProvider.notifier);
    final query = ref.read(curriculumExplorerProvider).query;
    await notifier.fetch(query);
    if (!mounted || version != _queryVersion || query.year.isNotEmpty) return;
    final state = ref.read(curriculumExplorerProvider);
    if (state.error != null || state.isLoading) return;
    final years = explorerRows(state.data['annual_performance']);
    if (years.isEmpty) return;
    final active = years.where((y) => y['in_progress'] == true).lastOrNull;
    _year('${(active ?? years.last)['academic_year']}');
  }

  void _selectCriterion(String id) => setState(() {
    _criterionId = id;
    _page = 0;
    _filter = 'all';
  });

  void _year(String value) => _fetch(
    ref
        .read(curriculumExplorerProvider)
        .query
        .copyWith(year: value, semester: '', context: ''),
  );
  TextStyle get _muted => TextStyle(
    fontSize: 12,
    height: 1.5,
    color: DefensysTokens.textSecondaryOf(context),
  );
  Widget _field(
    String label,
    Map<String, String> options,
    String value,
    ValueChanged<String> changed, {
    double width = 220,
    bool enabled = true,
  }) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: _muted.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ShadSelect<String>(
          key: ValueKey('analytics-$label-$value'),
          initialValue: value,
          enabled: enabled,
          minWidth: width,
          maxWidth: width,
          options: options.entries.map(
            (e) => ShadOption(
              value: e.key,
              child: Text(
                e.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          selectedOptionBuilder: (_, v) => Text(
            options[v] ?? v,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onChanged: (v) {
            if (v != null) changed(v);
          },
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(curriculumExplorerProvider),
        q = state.query,
        data = state.data;
    final criteria = explorerRows(data['criteria']);
    final selected = criteria.where((c) => c['id'] == _criterionId).firstOrNull;
    final contexts = explorerRows(data['contexts']);
    final selectedContext = contexts
        .where((c) => c['id'] == q.context)
        .firstOrNull;
    return DefensysShadcnScope(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _shadContext = context;
          final narrow = constraints.maxWidth < 650;
          final fieldWidth = narrow ? constraints.maxWidth - 32 : 225.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              narrow ? 16 : 24,
              22,
              narrow ? 16 : 24,
              32,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 24,
                      runSpacing: 14,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Curriculum Analytics',
                              style: DefensysTokens.pageTitle.copyWith(
                                fontSize: 26,
                                color: DefensysTokens.textPrimaryOf(context),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Review cohort performance, identify learning gaps and explore project evidence.',
                              style: _muted,
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ShadButton.outline(
                              size: ShadButtonSize.sm,
                              enabled: !state.isLoading,
                              leading: const Icon(
                                LucideIcons.refreshCw,
                                size: 15,
                              ),
                              onPressed: () => _fetch(q),
                              child: const Text('Refresh'),
                            ),
                            ShadButton(
                              size: ShadButtonSize.sm,
                              enabled: !state.isLoading && data.isNotEmpty,
                              backgroundColor: DefensysTokens.maroonOf(context),
                              foregroundColor: Colors.white,
                              leading: const Icon(
                                LucideIcons.download,
                                size: 15,
                              ),
                              onPressed: () => openCurriculumMeetingExport(
                                context,
                                ref,
                                q,
                                _tab,
                              ),
                              child: const Text('Export analytics report'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: DefensysTokens.surfaceOf(context),
                        border: Border.all(
                          color: DefensysTokens.borderOf(context),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 14,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: narrow ? fieldWidth - 32 : 190,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Program',
                                  style: _muted.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ShadTabs<String>(
                                  value: q.scope,
                                  gap: 0,
                                  scrollable: false,
                                  onChanged: (v) => _fetch(
                                    q.copyWith(
                                      scope: v,
                                      semester: '',
                                      context: '',
                                      role: 'panel',
                                    ),
                                  ),
                                  tabs: const [
                                    ShadTab(
                                      value: 'capstone',
                                      child: Flexible(
                                        child: Text(
                                          'Capstone',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    ShadTab(
                                      value: 'pit',
                                      child: Flexible(child: Text('PIT')),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (q.scope == 'pit')
                            _field(
                              'PIT year level',
                              const {
                                '1': '1st Year',
                                '2': '2nd Year',
                                '3': '3rd Year',
                              },
                              q.yearLevel,
                              (v) => _fetch(
                                q.copyWith(
                                  yearLevel: v,
                                  semester: '',
                                  context: '',
                                  role: 'panel',
                                ),
                              ),
                              width: narrow ? fieldWidth - 32 : 150,
                              enabled: !state.isLoading,
                            ),
                          _field(
                            'Academic year',
                            {
                              '': 'All academic years',
                              for (final y
                                  in (data['academic_years'] as List? ?? []))
                                '$y': '$y',
                            },
                            q.year,
                            _year,
                            width: narrow ? fieldWidth - 32 : 200,
                            enabled: !state.isLoading,
                          ),
                          if (q.year.isNotEmpty)
                            _field(
                              'Semester',
                              {
                                '': 'All semesters',
                                for (final s in explorerRows(data['semesters']))
                                  '${s['id']}': '${s['label']}',
                              },
                              q.semester,
                              (v) =>
                                  _fetch(q.copyWith(semester: v, context: '')),
                              width: narrow ? fieldWidth - 32 : 175,
                              enabled: !state.isLoading,
                            ),
                          if (contexts.isNotEmpty)
                            _field(
                              q.scope == 'capstone' ? 'Stage' : 'Event',
                              {
                                for (final c in contexts)
                                  '${c['id']}':
                                      '${c['label']}${c['semester_label'] != null && q.semester.isEmpty ? ' (${c['semester_label']})' : ''}',
                              },
                              q.context,
                              (v) => _fetch(q.copyWith(context: v)),
                              width: narrow ? fieldWidth - 32 : 240,
                              enabled: !state.isLoading,
                            ),
                          if (q.year.isNotEmpty &&
                              explorerRows(data['roles']).isNotEmpty)
                            _field(
                              'Rubric source',
                              {
                                for (final r in explorerRows(data['roles']))
                                  '${r['id']}': '${r['label']}',
                              },
                              q.role,
                              (v) => _fetch(q.copyWith(role: v)),
                              width: narrow ? fieldWidth - 32 : 145,
                              enabled: !state.isLoading,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 20,
                      runSpacing: 10,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ShadTabs<String>(
                          value: _tab,
                          gap: 0,
                          scrollable: false,
                          tabBarConstraints: BoxConstraints(
                            maxWidth: narrow ? fieldWidth : 370,
                          ),
                          onChanged: (v) => setState(() {
                            _tab = v;
                            _reset();
                          }),
                          tabs: const [
                            ShadTab(
                              value: 'performance',
                              child: Flexible(
                                child: Text(
                                  'Performance',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            ShadTab(
                              value: 'projects',
                              child: Flexible(
                                child: Text(
                                  'Project insights',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_tab == 'performance' && q.year.isNotEmpty)
                          ShadButton.link(
                            key: const ValueKey('compare-academic-years'),
                            size: ShadButtonSize.sm,
                            enabled: !state.isLoading,
                            leading: const Icon(
                              LucideIcons.chartColumn,
                              size: 15,
                            ),
                            onPressed: () => _year(''),
                            child: const Text('Compare academic years'),
                          ),
                      ],
                    ),
                    if (selected != null || _category != null)
                      ShadBreadcrumb(
                        children: [
                          ShadButton.link(
                            size: ShadButtonSize.sm,
                            padding: EdgeInsets.zero,
                            onPressed: () => setState(_reset),
                            child: Text(
                              _tab == 'performance'
                                  ? 'Performance by criterion'
                                  : 'All projects',
                            ),
                          ),
                          if (selected != null) Text('${selected['name']}'),
                          if (_category != null)
                            Text(
                              _category == '__all__'
                                  ? 'Project list'
                                  : _projectDimension == 'reason'
                                  ? classificationReasonLabels[_category!] ??
                                        _category!
                                  : _category!,
                            ),
                        ],
                      ),
                    const SizedBox(height: 14),
                    if (state.error != null) ...[
                      WorkflowNotice(
                        title: 'Analytics could not load',
                        message: state.error!,
                        error: true,
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ShadButton.outline(
                          onPressed: () => _fetch(q),
                          child: const Text('Try again'),
                        ),
                      ),
                    ] else if (state.isLoading)
                      ShadCard(
                        width: double.infinity,
                        child: DefensysLoading.section(
                          height: 350,
                          label: 'Loading recorded analytics…',
                        ),
                      )
                    else ...[
                      if (_tab == 'projects' || q.year.isNotEmpty) ...[
                        CurriculumCohortSummary(
                          query: q,
                          data: data,
                          contextLabel: selectedContext?['label']?.toString(),
                          projects: _tab == 'projects',
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (_tab == 'projects')
                        _projectView(data, q)
                      else if (q.year.isEmpty)
                        _annualView(data)
                      else if (selected != null)
                        _teamView(selected, q)
                      else
                        LayoutBuilder(
                          builder: (_, c) {
                            final main = _criteriaView(
                              criteria,
                              contexts,
                              data,
                              q,
                            );
                            final side = Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                CurriculumReviewPriorities(
                                  criteria: criteria,
                                  reference: q.reference,
                                  onCriterion: _selectCriterion,
                                ),
                                const SizedBox(height: 18),
                                CurriculumGradeDistribution(
                                  summary: data['assessment_summary'] is Map
                                      ? Map<String, dynamic>.from(
                                          data['assessment_summary'] as Map,
                                        )
                                      : {},
                                ),
                              ],
                            );
                            return c.maxWidth < 1000
                                ? Column(
                                    children: [
                                      main,
                                      const SizedBox(height: 18),
                                      side,
                                    ],
                                  )
                                : Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: main),
                                      const SizedBox(width: 20),
                                      SizedBox(width: 320, child: side),
                                    ],
                                  );
                          },
                        ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      q.scope == 'capstone'
                          ? 'Source: recorded Capstone stage assessments. Missing scores are excluded. Project categories are document-based estimates.'
                          : 'Source: recorded PIT event assessments for the selected year level. Missing scores are excluded. Project categories are document-based estimates.',
                      style: _muted,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _card(String title, String description, Widget child) => ShadCard(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    title: Text(
      title,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    ),
    description: Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(description, style: _muted),
    ),
    child: Padding(padding: const EdgeInsets.only(top: 18), child: child),
  );
  Widget _empty(String title, String body) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 42),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text(body, style: _muted),
      ],
    ),
  );

  Widget _annualView(Map<String, dynamic> data) {
    final rows = explorerRows(data['annual_performance']);
    return _card(
      'Performance across academic years',
      'Average published grade / latest published assessment per team',
      rows.isEmpty
          ? _empty(
              'No recorded academic years yet',
              'This chart will appear as teams and published assessments become available.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (rows.length == 1)
                  ShadButton.ghost(
                    key: ValueKey('year-${rows.first['academic_year']}'),
                    width: double.infinity,
                    height: 118,
                    mainAxisAlignment: MainAxisAlignment.start,
                    padding: const EdgeInsets.all(16),
                    onPressed: () => _year('${rows.first['academic_year']}'),
                    child: Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${rows.first['academic_year']}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${rows.first['score'] == null ? 'Awaiting published grades' : '${explorerNumber(rows.first['score'])!.toStringAsFixed(1)}% published average'} · ${rows.first['assessed']} / ${rows.first['eligible']} teams',
                            style: _muted,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Explore this cohort →',
                            style: _muted.copyWith(
                              color: DefensysTokens.maroonTextOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  CurriculumAnnualChart(rows: rows, onYear: _year),
                const SizedBox(height: 16),
                Text(
                  rows.length == 1
                      ? 'One academic year is available. More recorded cohorts are needed for a year comparison.'
                      : 'Select a year to explore its rubrics. In-progress years and different assessment stages are not directly comparable.',
                  style: _muted,
                ),
              ],
            ),
    );
  }

  Widget _criteriaView(
    List<Map<String, dynamic>> criteria,
    List<Map<String, dynamic>> contexts,
    Map<String, dynamic> data,
    CurriculumExplorerQuery q,
  ) => _card(
    'Performance by criterion',
    'Recorded ${q.role} rubric scores · lowest averages first',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (criteria.isEmpty)
          _empty(
            'No rubric results for this selection',
            'Choose another period or assessment. Missing scores are kept out of averages.',
          )
        else ...[
          ...criteria.map(
            (c) => CurriculumRankedBar(
              key: ValueKey('criterion-${c['id']}'),
              label: '${c['name']}',
              value: explorerNumber(c['score']),
              reference: q.reference,
              caption:
                  '${c['assessed']} / ${c['eligible']} ${c['target_type'] == 'individual' ? 'students' : 'teams'} assessed  |  ${c['semester_label'] ?? ''} / ${c['rubric_name']}',
              onPressed: () => _selectCriterion('${c['id']}'),
            ),
          ),
          const CurriculumPercentAxis(),
          const SizedBox(height: 14),
          Text(
            'Select a criterion to see the teams behind its score.',
            style: _muted,
          ),
        ],
        ShadAccordion<String>(
          children: [
            ShadAccordionItem(
              value: 'reference',
              title: Text(
                'Analysis reference: ${q.reference.toStringAsFixed(0)}%',
                style: _muted,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'An optional analysis target. Changing it does not change recorded grades or passing rules.',
                    style: _muted,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: 100,
                        child: ShadInput(
                          controller: _reference,
                          keyboardType: TextInputType.number,
                          placeholder: const Text('0–100'),
                        ),
                      ),
                      ShadButton.outline(
                        onPressed: () {
                          final v = double.tryParse(_reference.text.trim());
                          if (v == null || !v.isFinite || v < 0 || v > 100) {
                            setState(
                              () => _referenceError =
                                  'Enter a number from 0 to 100.',
                            );
                            return;
                          }
                          setState(() => _referenceError = null);
                          _fetch(q.copyWith(reference: v));
                        },
                        child: const Text('Apply reference'),
                      ),
                    ],
                  ),
                  if (_referenceError != null)
                    Text(
                      _referenceError!,
                      style: TextStyle(color: DefensysTokens.dangerText),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _teamView(Map<String, dynamic> c, CurriculumExplorerQuery q) {
    final rows = explorerRows(c['teams']).where((t) {
      if (_teamCategory != null && t['category'] != _teamCategory) return false;
      final score = explorerNumber(t['score']);
      return switch (_filter) {
        'below' => score != null && score < q.reference,
        'meeting' => score != null && score >= q.reference,
        'pending' => score == null,
        _ => true,
      };
    }).toList();
    final score = explorerNumber(c['score']),
        individual = c['target_type'] == 'individual';
    final page = _page.clamp(0, rows.isEmpty ? 0 : (rows.length - 1) ~/ 6);
    return _card(
      '${c['name']} / teams',
      '${score == null ? 'Awaiting assessment' : '${score.toStringAsFixed(1)}% average'} / ${c['below']} of ${c['assessed']} assessed ${individual ? 'students' : 'teams'} below reference',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_teamCategory != null) ...[
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Project focus: $_teamCategory', style: _muted),
                ShadButton.link(
                  size: ShadButtonSize.sm,
                  onPressed: () => setState(() {
                    _teamCategory = null;
                    _page = 0;
                  }),
                  child: const Text('Show all teams'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                {
                      'all': 'All',
                      'below': 'Below reference',
                      'meeting': 'Meeting reference',
                      'pending': 'Awaiting',
                    }.entries
                    .map(
                      (e) => ShadButton.raw(
                        key: ValueKey('filter-${e.key}'),
                        variant: _filter == e.key
                            ? ShadButtonVariant.secondary
                            : ShadButtonVariant.outline,
                        size: ShadButtonSize.sm,
                        onPressed: () => setState(() {
                          _filter = e.key;
                          _page = 0;
                        }),
                        child: Text(e.value),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 12),
          if (individual)
            Text(
              'Team bars show the average of assessed members. Open a team for individual student results.',
              style: _muted,
            ),
          if (rows.isEmpty)
            _empty(
              'No teams match this selection',
              'Select another result filter.',
            )
          else
            ...rows
                .skip(page * 6)
                .take(6)
                .map(
                  (t) => CurriculumRankedBar(
                    key: ValueKey('team-${t['id']}'),
                    label: '${t['team_name']}',
                    value: explorerNumber(t['score']),
                    reference: q.reference,
                    caption: individual
                        ? '${t['assessed']} / ${t['eligible']} members assessed'
                        : '${t['project_title']}',
                    onPressed: () => _evidence(t, c),
                  ),
                ),
          const CurriculumPercentAxis(),
          const SizedBox(height: 18),
          _pager(rows.length, page),
          const SizedBox(height: 14),
          Text(
            'Select a team to inspect recorded scores, feedback and project evidence.',
            style: _muted,
          ),
        ],
      ),
    );
  }

  Widget _pager(int count, int page) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 10,
    children: [
      Text(
        '${count == 0 ? 0 : page * 6 + 1}–${((page + 1) * 6).clamp(0, count)} of $count',
        style: _muted,
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShadButton.outline(
            size: ShadButtonSize.sm,
            enabled: page > 0,
            onPressed: () => setState(() => _page = page - 1),
            child: const Text('Previous'),
          ),
          const SizedBox(width: 8),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            enabled: (page + 1) * 6 < count,
            onPressed: () => setState(() => _page = page + 1),
            child: const Text('Next'),
          ),
        ],
      ),
    ],
  );

  Widget _projectView(Map<String, dynamic> data, CurriculumExplorerQuery q) {
    if (_category == null) {
      return CurriculumProjectAnalytics(
        data: data,
        query: q,
        onYear: _year,
        onGroup: (field, value) => setState(() {
          _projectDimension = field;
          _category = value;
          _page = 0;
        }),
        onCriterion: (criterion, category) => setState(() {
          _tab = 'performance';
          _criterionId = criterion;
          _teamCategory = category;
          _category = null;
          _filter = 'all';
          _page = 0;
        }),
      );
    }
    final rows = explorerRows(data['projects'])
        .where(
          (p) =>
              _category == '__all__' ||
              switch (_projectDimension) {
                'domain' => p['domain'] == _category,
                'technology' => (p['technologies'] as List? ?? []).contains(
                  _category,
                ),
                'reason' => p['classification_reason_code'] == _category,
                _ => p['category'] == _category,
              },
        )
        .toList();
    final page = _page.clamp(0, rows.isEmpty ? 0 : (rows.length - 1) ~/ 6);
    return _card(
      _category == '__all__'
          ? 'All projects'
          : _projectDimension == 'reason'
          ? classificationReasonLabels[_category!] ?? 'Unresolved projects'
          : '$_category projects',
      '${rows.length} unique projects / ${q.year.isEmpty ? 'all academic years' : q.year}',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in rows.skip(page * 6).take(6)) _projectRow(p),
          const SizedBox(height: 18),
          _pager(rows.length, page),
          const SizedBox(height: 14),
          Text(
            'Open a project to inspect its classification source and rubric evidence.',
            style: _muted,
          ),
          if (_category != '__all__' &&
              (_projectDimension == 'category' ||
                  _projectDimension == 'domain'))
            ShadAccordion<String>(
              children: [
                ShadAccordionItem<String>(
                  value: 'category-trend',
                  title: Text(
                    'Selected group across academic years',
                    style: _muted,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final t in explorerRows(data['project_trends']))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${t['academic_year']}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  Text(
                                    t['projects_count'] == 0
                                        ? 'Not recorded'
                                        : '${_categoryCount(t)} / ${t['projects_count']} projects',
                                    style: _muted,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              LayoutBuilder(
                                builder: (_, c) => Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    height: 10,
                                    width: t['projects_count'] == 0
                                        ? 0
                                        : c.maxWidth *
                                              _categoryCount(t) /
                                              (t['projects_count'] as num),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: DefensysTokens.maroonOf(context),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const CurriculumPercentAxis(),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _projectRow(Map<String, dynamic> p) => Column(
    children: [
      ShadButton.ghost(
        key: ValueKey('project-${p['id']}'),
        width: double.infinity,
        height: 100,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        mainAxisAlignment: MainAxisAlignment.start,
        onPressed: () => _evidence(p, null),
        child: Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${p['project_title']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${p['team_name']} · ${p['category'] ?? 'Unclassified'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                LucideIcons.chevronRight,
                size: 17,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ],
          ),
        ),
      ),
      Divider(height: 1, color: DefensysTokens.borderOf(context)),
    ],
  );

  void _evidence(
    Map<String, dynamic> project,
    Map<String, dynamic>? criterion,
  ) => showShadDialog(
    context: _shadContext ?? context,
    barrierLabel: 'Close project evidence',
    builder: (_) => CurriculumEvidenceDialog(
      project: project,
      criterion: criterion,
      allAssessments: _tab == 'projects',
      initialRole: ref.read(curriculumExplorerProvider).query.role,
    ),
  );
  int _categoryCount(Map<String, dynamic> trend) =>
      explorerRows(
            trend[_projectDimension == 'domain' ? 'domains' : 'distribution'],
          )
          .where((d) => d['category'] == _category)
          .fold(0, (sum, d) => sum + ((d['count'] as num?)?.toInt() ?? 0));
}
