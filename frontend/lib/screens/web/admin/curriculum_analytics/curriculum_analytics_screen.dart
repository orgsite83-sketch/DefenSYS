import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../services/academic/curriculum_explorer_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../widgets/feedback/defensys_loading.dart';
import 'widgets/curriculum_explorer_charts.dart';
import 'widgets/curriculum_evidence_dialog.dart';
import 'widgets/curriculum_performance_comparison.dart';
import 'widgets/curriculum_chart_palette.dart';
import 'widgets/curriculum_meeting_export.dart';
import 'widgets/curriculum_workspace_views.dart';
import 'widgets/curriculum_linked_panels.dart';
import 'widgets/curriculum_linked_projects.dart';
part 'curriculum_assessment_detail.dart';

class CurriculumAnalyticsScreen extends ConsumerStatefulWidget {
  const CurriculumAnalyticsScreen({super.key, this.pitYearLevel});
  final String? pitYearLevel;
  @override
  ConsumerState<CurriculumAnalyticsScreen> createState() =>
      _CurriculumAnalyticsScreenState();
}

class _CurriculumAnalyticsScreenState
    extends ConsumerState<CurriculumAnalyticsScreen> {
  String? _criterionId, _teamCategory, _projectGroup;
  String _filter = 'all', _projectField = 'category';
  String _projectMixDimension = 'application_area';
  bool _strongestFirst = false;
  int _performancePage = 0, _projectPage = 0;
  int get _page => _tab == 'projects' ? _projectPage : _performancePage;
  set _page(int value) {
    if (_tab == 'projects') {
      _projectPage = value;
    } else {
      _performancePage = value;
    }
  }

  final _reference = TextEditingController(text: '75');
  String? _referenceError;
  BuildContext? _shadContext;
  CurriculumExplorerQuery? _performanceQuery, _projectsQuery;
  String get _tab =>
      ref.read(curriculumExplorerProvider).query.view.startsWith('project')
      ? 'projects'
      : 'performance';
  String? get _assignedYear => const {
    '1st Year': '1',
    '2nd Year': '2',
    '3rd Year': '3',
  }[widget.pitYearLevel];
  TextStyle get _muted => TextStyle(
    fontFamily: DefensysTokens.fontFamilyInter,
    fontSize: 12,
    height: 1.5,
    color: DefensysTokens.textSecondaryOf(context),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || (widget.pitYearLevel != null && _assignedYear == null)) {
        return;
      }
      var q = ref.read(curriculumExplorerProvider).query;
      if (widget.pitYearLevel != null &&
          (q.scope != 'pit' || q.yearLevel != _assignedYear)) {
        q = CurriculumExplorerQuery(scope: 'pit', yearLevel: _assignedYear!);
      }
      if (q.view == 'overview') {
        q = q.copyWith(
          year: '',
          context: '',
          subject: '',
          semester: '',
          initial: false,
        );
      }
      _reference.text = q.reference.toStringAsFixed(0);
      ref.read(curriculumExplorerProvider.notifier).fetch(q);
    });
  }

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _fetch(
    CurriculumExplorerQuery q, {
    bool selection = false,
    bool preserveSelection = false,
  }) async {
    if (widget.pitYearLevel != null) {
      q = q.copyWith(scope: 'pit', yearLevel: _assignedYear);
    }
    setState(() {
      if (!preserveSelection) {
        if (q.view.startsWith('project')) {
          _projectGroup = null;
          _projectPage = 0;
        } else {
          _criterionId = null;
          _teamCategory = null;
          _performancePage = 0;
          _filter = 'all';
        }
      }
    });
    await ref
        .read(curriculumExplorerProvider.notifier)
        .fetch(q.copyWith(initial: false), selection: selection);
    if (!mounted) return;
    final current = ref.read(curriculumExplorerProvider);
    if (preserveSelection &&
        _tab == 'performance' &&
        _criterionId != null &&
        current.error == null &&
        current.data['criteria_complete'] == false) {
      await ref
          .read(curriculumExplorerProvider.notifier)
          .fetch(
            current.query.copyWith(view: 'assessment'),
            loadEvidence: true,
          );
    }
  }

  void _switchTab(String tab) {
    final q = ref.read(curriculumExplorerProvider).query;
    if (tab == _tab) return;
    if (_tab == 'performance') {
      _performanceQuery = q;
    } else {
      _projectsQuery = q;
    }
    _fetch(
      (tab == 'performance' ? _performanceQuery : _projectsQuery) ??
          q.copyWith(
            view: tab == 'performance' ? 'overview' : 'projects',
            year: '',
            semester: '',
            context: '',
            subject: '',
            role: 'panel',
          ),
      preserveSelection: true,
    );
  }

  void _range(CurriculumExplorerQuery q) {
    final old = ref.read(curriculumExplorerProvider).query;
    _performanceQuery = null;
    _projectsQuery = null;
    _criterionId = _teamCategory = _projectGroup = null;
    _performancePage = _projectPage = 0;
    _filter = 'all';
    _fetch(
      q.copyWith(
        view: _tab == 'performance' ? 'overview' : 'projects',
        year: '',
        semester: '',
        context: '',
        subject: '',
        role: 'panel',
        comparison: old.scope == q.scope && old.yearLevel == q.yearLevel
            ? q.comparison
            : '',
      ),
    );
  }

  void _year(String year) {
    final q = ref.read(curriculumExplorerProvider).query;
    if (q.year == year && q.view != 'project_output') {
      if (_tab == 'performance') _change(() => _criterionId = null);
      return;
    }
    _fetch(
      q.copyWith(
        view: _tab == 'projects'
            ? 'projects'
            : year.isEmpty
            ? 'overview'
            : 'year',
        year: year,
        semester: '',
        context: '',
        subject: '',
      ),
      selection: _tab == 'projects',
    );
  }

  void _selectCriterion(String id) {
    setState(() {
      _criterionId = id;
      _page = 0;
      _filter = 'all';
    });
    final state = ref.read(curriculumExplorerProvider);
    if (state.data['criteria_complete'] == false) {
      ref
          .read(curriculumExplorerProvider.notifier)
          .fetch(state.query.copyWith(view: 'assessment'), loadEvidence: true);
    }
  }

  void _change(VoidCallback callback) => setState(callback);
  void _refresh() {
    final q = ref.read(curriculumExplorerProvider).query;
    ref
        .read(curriculumExplorerProvider.notifier)
        .fetch(
          q,
          force: true,
          loadEvidence: _tab == 'performance' && _criterionId != null,
        );
  }

  void _group(String field, String value) => setState(() {
    _projectField = field;
    _projectGroup = value;
    _page = 0;
  });
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
  Widget _card(String title, String description, Widget child) => ShadCard(
    backgroundColor: DefensysTokens.surfaceOf(context),
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    title: Text(
      title,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    ),
    description: description.isEmpty ? null : Text(description, style: _muted),
    child: Padding(padding: const EdgeInsets.only(top: 18), child: child),
  );
  Widget _empty(String title, String body) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(body, style: _muted),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(curriculumExplorerProvider),
        q = state.query,
        data = state.data;
    if (widget.pitYearLevel != null && _assignedYear == null) {
      return const Center(
        child: Text(
          'A PIT year assignment is required to view curriculum analytics.',
        ),
      );
    }
    if (widget.pitYearLevel != null &&
        (q.scope != 'pit' || q.yearLevel != _assignedYear)) {
      return const Center(child: CircularProgressIndicator());
    }
    final years = (data['academic_years'] as List? ?? [])
        .map((v) => '$v')
        .toList();
    final contexts = explorerRows(data['contexts']);
    final stage = contexts.where((c) => c['id'] == q.context).firstOrNull;
    final criteria = explorerRows(data['criteria']);
    final selected = criteria.where((c) => c['id'] == _criterionId).firstOrNull;
    return DefensysShadcnScope(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _shadContext = context;
          final narrow = constraints.maxWidth < 650;
          final fieldWidth = narrow
              ? (constraints.maxWidth - 72).clamp(120.0, 260.0).toDouble()
              : 190.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              narrow ? 16 : 24,
              22,
              narrow ? 16 : 24,
              32,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 20,
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
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ShadButton.outline(
                              size: ShadButtonSize.sm,
                              enabled: !state.isLoading && !state.isRefreshing,
                              leading: const Icon(
                                LucideIcons.refreshCw,
                                size: 15,
                              ),
                              onPressed: _refresh,
                              child: const Text('Refresh'),
                            ),
                            ShadButton.outline(
                              size: ShadButtonSize.sm,
                              enabled:
                                  !state.isLoading &&
                                  state.error == null &&
                                  data.isNotEmpty,
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
                              child: const Text('Export report'),
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
                        spacing: 14,
                        runSpacing: 14,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (widget.pitYearLevel != null)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Assigned program', style: _muted),
                                const SizedBox(height: 8),
                                ShadBadge.secondary(
                                  child: Text('PIT · ${widget.pitYearLevel}'),
                                ),
                              ],
                            )
                          else
                            _field(
                              'Program',
                              const {'capstone': 'Capstone', 'pit': 'PIT'},
                              q.scope,
                              (v) => _range(
                                q.copyWith(scope: v, yearFrom: '', yearTo: ''),
                              ),
                              width: fieldWidth,
                              enabled: !state.isLoading,
                            ),
                          if (q.scope == 'pit' && widget.pitYearLevel == null)
                            _field(
                              'PIT year level',
                              const {
                                '1': '1st Year',
                                '2': '2nd Year',
                                '3': '3rd Year',
                              },
                              q.yearLevel,
                              (v) => _range(
                                q.copyWith(
                                  yearLevel: v,
                                  yearFrom: '',
                                  yearTo: '',
                                ),
                              ),
                              width: fieldWidth,
                              enabled: !state.isLoading,
                            ),
                          _field(
                            'From academic year',
                            {for (final y in years) y: y},
                            q.yearFrom,
                            (v) => _range(
                              q.copyWith(
                                yearFrom: v,
                                yearTo: q.yearTo.compareTo(v) < 0
                                    ? v
                                    : q.yearTo,
                              ),
                            ),
                            width: fieldWidth,
                            enabled: !state.isLoading && years.isNotEmpty,
                          ),
                          _field(
                            'To academic year',
                            {for (final y in years) y: y},
                            q.yearTo,
                            (v) => _range(
                              q.copyWith(
                                yearTo: v,
                                yearFrom: q.yearFrom.compareTo(v) > 0
                                    ? v
                                    : q.yearFrom,
                              ),
                            ),
                            width: fieldWidth,
                            enabled: !state.isLoading && years.isNotEmpty,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: narrow ? double.infinity : 370,
                        child: ShadTabs<String>(
                          value: _tab,
                          gap: 0,
                          scrollable: false,
                          onChanged: _switchTab,
                          tabs: const [
                            ShadTab(
                              value: 'performance',
                              child: Flexible(child: Text('Performance')),
                            ),
                            ShadTab(
                              value: 'projects',
                              child: Flexible(child: Text('Project insights')),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ShadButton.link(
                          key: const ValueKey('analytics-root'),
                          size: ShadButtonSize.sm,
                          padding: EdgeInsets.zero,
                          onPressed: () => _fetch(
                            q.copyWith(
                              view: _tab == 'performance'
                                  ? 'overview'
                                  : 'projects',
                              year: '',
                              context: '',
                              subject: '',
                              semester: '',
                            ),
                          ),
                          child: Text(
                            _tab == 'performance'
                                ? 'Performance overview'
                                : 'Project collection',
                          ),
                        ),
                        if (q.year.isNotEmpty) ...[
                          const Icon(LucideIcons.chevronRight, size: 13),
                          ShadButton.link(
                            size: ShadButtonSize.sm,
                            padding: EdgeInsets.zero,
                            onPressed: () => _year(q.year),
                            child: Text(q.year),
                          ),
                        ],
                        if (q.view == 'assessment') ...[
                          const Icon(LucideIcons.chevronRight, size: 13),
                          ShadButton.link(
                            size: ShadButtonSize.sm,
                            padding: EdgeInsets.zero,
                            onPressed: () =>
                                setState(() => _criterionId = null),
                            child: Text('${stage?['label'] ?? 'Assessment'}'),
                          ),
                        ],
                        if (selected != null)
                          Text('/ ${selected['name']}', style: _muted),
                        if (q.view == 'project_output')
                          Text('/ Yearly output', style: _muted),
                        if (_projectGroup != null)
                          Text(
                            '/ ${_projectGroup == '__all__' ? 'Contributing projects' : _projectGroup}',
                            style: _muted,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (state.error != null) ...[
                      ShadAlert.destructive(
                        title: const Text('Analytics could not be loaded'),
                        description: Text(state.error!),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ShadButton.outline(
                          onPressed: _refresh,
                          child: const Text('Try again'),
                        ),
                      ),
                    ],
                    if (state.isRefreshing)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(
                          minHeight: 2,
                          color: DefensysTokens.maroonOf(context),
                          backgroundColor: DefensysTokens.borderOf(context),
                        ),
                      ),
                    if (state.isLoading || data.isEmpty) ...[
                      if (state.error == null)
                        ShadCard(
                          backgroundColor: DefensysTokens.surfaceOf(context),
                          width: double.infinity,
                          child: DefensysLoading.section(
                            height: 350,
                            label: 'Loading recorded analytics…',
                          ),
                        ),
                    ] else if (q.view == 'overview')
                      CurriculumHistoryOverview(
                        data: data,
                        onYear: _year,
                        onComparison: (v) => _fetch(
                          q.copyWith(comparison: v, year: '', context: ''),
                        ),
                      )
                    else if (q.view == 'year' &&
                        data['assessment_bundles'] == null)
                      CurriculumYearOverview(
                        data: data,
                        onAssessment: (id) => _fetch(
                          q.copyWith(
                            view: 'assessment',
                            context: id,
                            subject: '',
                            role: 'panel',
                          ),
                        ),
                      )
                    else if (q.view == 'assessment' || q.view == 'year') ...[
                      _assessmentView(data, criteria, q),
                      if (selected != null) ...[
                        const SizedBox(height: 20),
                        if (data['criteria_complete'] == false &&
                            state.isRefreshing)
                          DefensysLoading.section(
                            height: 130,
                            label: 'Loading team results…',
                          )
                        else
                          _teamView(selected, q),
                      ],
                    ] else if (q.view == 'project_output')
                      CurriculumOutputChart(data: data, onYear: _year)
                    else if (data['project_collection'] is List)
                      CurriculumLinkedProjects(
                        data: data,
                        query: q,
                        dimension: _projectMixDimension,
                        onDimension: (v) => _change(() {
                          _projectMixDimension = v;
                          _projectGroup = null;
                          _page = 0;
                        }),
                        onYear: _year,
                        onStatus: (v) => _fetch(q.copyWith(projectStatus: v)),
                        onGroup: _group,
                        group: _projectGroup,
                        groupField: _projectField,
                        onClear: () => _change(() {
                          _projectGroup = null;
                          _page = 0;
                        }),
                        projectList: _projectList(data),
                      )
                    else if (_projectGroup != null)
                      _projectList(data)
                    else
                      CurriculumProjectMix(
                        data: data,
                        dimension: _projectMixDimension,
                        onDimension: (v) =>
                            setState(() => _projectMixDimension = v),
                        status: q.projectStatus,
                        onStatus: (v) => _fetch(q.copyWith(projectStatus: v)),
                        onGroup: _group,
                        onOutput: () => _fetch(
                          q.copyWith(view: 'project_output', year: ''),
                        ),
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

  Widget _assessmentView(
    Map<String, dynamic> data,
    List<Map<String, dynamic>> criteria,
    CurriculumExplorerQuery q,
  ) {
    final selected = explorerRows(
      data['contexts'],
    ).where((c) => c['id'] == q.context).firstOrNull;
    return _card(
      q.scope == 'pit'
          ? 'Performance across events'
          : 'Performance across stages',
      '${q.year} · Evaluator scores before weighting',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${selected?['label'] ?? 'Assessment'}',
                style: const TextStyle(
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Icon(LucideIcons.chevronRight, size: 13),
              Container(
                width: 9,
                height: 9,
                color: CurriculumChartPalette.evaluator(context, q.role),
              ),
              Text(q.role[0].toUpperCase() + q.role.substring(1)),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (_, c) {
              final left = CurriculumPerformanceComparison(
                embedded: true,
                data: data,
                query: q,
                onSubject: (v) => _fetch(q.copyWith(subject: v)),
                onAssessment: (id, role) => _fetch(
                  q.copyWith(view: 'assessment', context: id, role: role),
                  selection: true,
                ),
              );
              final right = _criteriaView(
                criteria,
                explorerRows(data['contexts']),
                data,
                q,
              );
              return CurriculumLinkedPanels(overview: left, detail: right);
            },
          ),
        ],
      ),
    );
  }

  Widget _projectList(Map<String, dynamic> data) {
    final rows = explorerRows(data['projects'])
        .where(
          (p) =>
              _projectGroup == null ||
              _projectGroup == '__all__' ||
              (_projectField == 'technology'
                  ? (p['technologies'] as List? ?? []).contains(_projectGroup)
                  : p[_projectField] == _projectGroup),
        )
        .toList();
    final page = _page.clamp(0, rows.isEmpty ? 0 : (rows.length - 1) ~/ 8);
    return _card(
      'Contributing projects',
      '${rows.length} projects',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isEmpty)
            _empty(
              'No projects match this selection',
              'Choose another project group.',
            ),
          ...rows.skip(page * 8).take(8).map(_projectRow),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              Text('Page ${page + 1}', style: _muted),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                enabled: page > 0,
                onPressed: () => setState(() => _page--),
                child: const Text('Previous'),
              ),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                enabled: (page + 1) * 8 < rows.length,
                onPressed: () => setState(() => _page++),
                child: const Text('Next'),
              ),
              if (_projectGroup != null)
                ShadButton.link(
                  size: ShadButtonSize.sm,
                  onPressed: () => setState(() => _projectGroup = null),
                  child: const Text('Clear filter'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
