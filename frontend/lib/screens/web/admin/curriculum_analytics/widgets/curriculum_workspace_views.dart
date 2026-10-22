import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../../../services/academic/curriculum_explorer_provider.dart';
import '../../../../../theme/defensys_tokens.dart';
import 'curriculum_chart_palette.dart';
import 'curriculum_explorer_charts.dart';

TextStyle _muted(BuildContext c) => TextStyle(
  fontSize: 12,
  height: 1.5,
  color: DefensysTokens.textSecondaryOf(c),
);
Widget _panel(BuildContext c, String title, String description, Widget body) =>
    ShadCard(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      title: Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      description: Text(description, style: _muted(c)),
      child: Padding(padding: const EdgeInsets.only(top: 18), child: body),
    );
Widget _pair(Widget left, Widget right) => LayoutBuilder(
  builder: (_, c) => c.maxWidth < 1000
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, const SizedBox(height: 20), right],
        )
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: left),
            const SizedBox(width: 20),
            Expanded(flex: 2, child: right),
          ],
        ),
);
String _score(dynamic value) => explorerNumber(value) == null
    ? 'Awaiting'
    : '${explorerNumber(value)!.toStringAsFixed(1)}%';

class CurriculumHistoryOverview extends StatelessWidget {
  const CurriculumHistoryOverview({
    super.key,
    required this.data,
    required this.onYear,
    required this.onComparison,
  });
  final Map<String, dynamic> data;
  final ValueChanged<String> onYear, onComparison;
  @override
  Widget build(BuildContext context) {
    final rows = explorerRows(data['annual_performance']);
    final options = explorerRows(data['comparison_options']);
    final latest = rows.where((r) => r['score'] != null).lastOrNull;
    final chart = _panel(
      context,
      'Performance over time',
      'One assessment across academic years · average published team grade',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Stage / event',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (_, c) => ShadSelect<String>(
              key: ValueKey('history-assessment-${data['comparison']}'),
              initialValue: '${data['comparison'] ?? ''}',
              minWidth: c.maxWidth,
              maxWidth: c.maxWidth,
              options: options.map(
                (o) => ShadOption(
                  value: '${o['id']}',
                  child: Text('${o['label']}'),
                ),
              ),
              selectedOptionBuilder: (_, v) => Text(
                '${options.where((o) => o['id'] == v).firstOrNull?['label'] ?? 'No recorded assessments'}',
                maxLines: 2,
              ),
              onChanged: (v) {
                if (v != null) onComparison(v);
              },
            ),
          ),
          const SizedBox(height: 16),
          if (options.isEmpty)
            Text(
              'No recorded assessment results yet. Select a year to inspect its configured stages or events.',
              style: _muted(context),
            ),
          _TimeChart(rows: rows, onYear: onYear),
        ],
      ),
    );
    final summary = _panel(
      context,
      'Read the results in context',
      'Published results describe this assessment; they do not establish learning growth.',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (latest != null) ...[
            Text(
              _score(latest['score']),
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w600,
                color: CurriculumChartPalette.primary(context),
              ),
            ),
            Text(
              'Latest published average · ${latest['academic_year']}',
              style: _muted(context),
            ),
            const SizedBox(height: 16),
            Text(
              '${latest['assessed']} / ${latest['eligible']} teams assessed',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              '${latest['pending'] ?? 0} pending · ${latest['assessed_students'] ?? 0} students in assessed teams',
              style: _muted(context),
            ),
            const SizedBox(height: 16),
            const Text(
              'Published grade distribution',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            for (final band in explorerRows(latest['distribution']))
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${band['label']}', style: _muted(context)),
                    ),
                    Text('${band['count']} teams', style: _muted(context)),
                  ],
                ),
              ),
          ] else
            Text(
              'Published scores are not available yet. Missing results remain pending.',
              style: _muted(context),
            ),
          const SizedBox(height: 20),
          ShadAlert(
            title: Text(
              data['rubric_changed'] == true
                  ? 'Rubric or grading weights changed'
                  : 'Assessment comparability',
            ),
            description: Text(
              data['rubric_changed'] == true
                  ? 'Interpret these years separately where the rubric or weights differ. A higher average alone does not measure student improvement.'
                  : 'Matching stage names do not guarantee equivalent difficulty. Current-year results are provisional.',
            ),
          ),
          ShadAccordion<String>(
            children: [
              ShadAccordionItem(
                value: 'rubrics',
                title: const Text('Rubrics by academic year'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final row in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${row['academic_year']}: ${(row['rubrics'] as List? ?? []).join(', ')}',
                          style: _muted(context),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return _pair(chart, summary);
  }
}

class CurriculumYearOverview extends StatelessWidget {
  const CurriculumYearOverview({
    super.key,
    required this.data,
    required this.onAssessment,
  });
  final Map<String, dynamic> data;
  final ValueChanged<String> onAssessment;
  @override
  Widget build(BuildContext context) {
    final rows = explorerRows(data['stage_results']);
    return _panel(
      context,
      'Stage and event results · ${data['academic_year']}',
      'Each assessment has its own criteria. These results describe stages, rather than a measured growth score.',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${data['matched_students'] ?? 0} students have published results across all assessed stages in this view.',
            style: _muted(context),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              'No stages or events are configured for this academic year.',
              style: _muted(context),
            ),
          for (final row in rows)
            CurriculumRankedBar(
              key: ValueKey('assessment-${row['id']}'),
              label: '${row['label']}',
              value: explorerNumber(row['score']),
              reference: 0,
              caption:
                  '${row['assessed']} / ${row['eligible']} teams assessed · ${row['pending']} pending${row['semester_label'] == null ? '' : ' · ${row['semester_label']}'}',
              onPressed: () => onAssessment('${row['id']}'),
            ),
          if (rows.isNotEmpty) const CurriculumPercentAxis(),
          const SizedBox(height: 14),
          Text(
            'Select an assessment to review its evaluator components, criteria and student evidence.',
            style: _muted(context),
          ),
        ],
      ),
    );
  }
}

class _TimeChart extends StatelessWidget {
  const _TimeChart({
    required this.rows,
    required this.onYear,
    this.output = false,
  });
  final List<Map<String, dynamic>> rows;
  final ValueChanged<String> onYear;
  final bool output;
  @override
  Widget build(BuildContext context) {
    final border = DefensysTokens.borderOf(context), muted = _muted(context);
    void select(ChartPointDetails d) {
      if (d.pointIndex != null) {
        onYear('${rows[d.pointIndex!]['academic_year']}');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 310,
          child: SfCartesianChart(
            key: ValueKey(
              output ? 'project-output-chart' : 'academic-year-chart',
            ),
            plotAreaBorderWidth: 0,
            tooltipBehavior: TooltipBehavior(enable: true),
            primaryXAxis: CategoryAxis(
              labelStyle: muted,
              majorGridLines: const MajorGridLines(width: 0),
              majorTickLines: const MajorTickLines(size: 0),
              axisLine: AxisLine(color: border),
            ),
            primaryYAxis: NumericAxis(
              minimum: 0,
              maximum: output ? null : 100,
              interval: output ? null : 25,
              decimalPlaces: output ? 0 : 1,
              labelFormat: output ? '{value}' : '{value}%',
              labelStyle: muted,
              majorGridLines: MajorGridLines(color: border),
              majorTickLines: const MajorTickLines(size: 0),
              axisLine: const AxisLine(width: 0),
            ),
            series: <CartesianSeries<Map<String, dynamic>, String>>[
              if (output)
                ColumnSeries<Map<String, dynamic>, String>(
                  dataSource: rows,
                  xValueMapper: (r, _) => '${r['academic_year']}',
                  yValueMapper: (r, _) => explorerNumber(r['count']),
                  color: CurriculumChartPalette.primary(context),
                  width: .45,
                  animationDuration: 0,
                  onPointTap: select,
                  dataLabelSettings: const DataLabelSettings(isVisible: true),
                )
              else
                LineSeries<Map<String, dynamic>, String>(
                  dataSource: rows,
                  xValueMapper: (r, _) => '${r['academic_year']}',
                  yValueMapper: (r, _) => explorerNumber(r['score']),
                  color: CurriculumChartPalette.primary(context),
                  emptyPointSettings: const EmptyPointSettings(
                    mode: EmptyPointMode.gap,
                  ),
                  markerSettings: const MarkerSettings(
                    isVisible: true,
                    width: 8,
                    height: 8,
                  ),
                  animationDuration: 0,
                  onPointTap: select,
                ),
            ],
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final row in rows)
              ShadButton.ghost(
                key: ValueKey('year-${row['academic_year']}'),
                size: ShadButtonSize.sm,
                onPressed: () => onYear('${row['academic_year']}'),
                child: Text(
                  output
                      ? '${row['academic_year']} · ${row['count']} projects'
                      : '${row['academic_year']} · ${_score(row['score'])}${row['in_progress'] == true ? ' · In progress' : ''}',
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class CurriculumOutputChart extends StatelessWidget {
  const CurriculumOutputChart({
    super.key,
    required this.data,
    required this.onYear,
  });
  final Map<String, dynamic> data;
  final ValueChanged<String> onYear;
  @override
  Widget build(BuildContext context) => _panel(
    context,
    'Projects by academic year',
    data['project_status'] == 'completed'
        ? 'Each project counts once, in its first documented completion year.'
        : 'Each project record counts once, in its latest recorded year.',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${data['projects_count'] ?? 0} projects in this selection',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        _TimeChart(
          rows: explorerRows(data['project_output']),
          onYear: onYear,
          output: true,
        ),
        const SizedBox(height: 14),
        Text(
          'Select a year to inspect its project focus, domains and technologies.',
          style: _muted(context),
        ),
      ],
    ),
  );
}

class CurriculumProjectMix extends StatefulWidget {
  const CurriculumProjectMix({
    super.key,
    required this.data,
    required this.status,
    required this.onStatus,
    required this.onGroup,
    required this.onOutput,
    required this.dimension,
    required this.onDimension,
  });
  final Map<String, dynamic> data;
  final String status;
  final ValueChanged<String> onStatus;
  final void Function(String, String) onGroup;
  final VoidCallback onOutput;
  final String dimension;
  final ValueChanged<String> onDimension;
  @override
  State<CurriculumProjectMix> createState() => _CurriculumProjectMixState();
}

class _CurriculumProjectMixState extends State<CurriculumProjectMix> {
  String get _dimension => widget.dimension;
  bool _allGroups = false, _allTechnologies = false;
  @override
  Widget build(BuildContext context) {
    final projects = explorerRows(widget.data['projects']);
    final total = projects.length;
    final groups = <String, int>{}, technologies = <String, int>{};
    for (final p in projects) {
      groups.update(
        '${p[_dimension] ?? (_dimension == 'application_area' ? 'Unresolved application area' : 'Unclassified')}',
        (n) => n + 1,
        ifAbsent: () => 1,
      );
      for (final t in (p['technologies'] as List? ?? []).toSet()) {
        technologies.update('$t', (n) => n + 1, ifAbsent: () => 1);
      }
    }
    List<MapEntry<String, int>> ordered(Map<String, int> input) =>
        input.entries.toList()..sort((a, b) {
          final n = b.value.compareTo(a.value);
          return n == 0 ? a.key.compareTo(b.key) : n;
        });
    final ranks = ordered(groups), stack = ordered(technologies);
    final coverage = widget.data['project_analytics'] is Map
        ? widget.data['project_analytics']['coverage'] as Map? ?? {}
        : {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '$total ${widget.status == 'completed' ? 'completed projects' : 'project records'}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              '${coverage['classified'] ?? 0} with a computing-focus estimate · ${coverage['with_technologies'] ?? 0} with documented technologies',
              style: _muted(context),
            ),
            ShadButton.link(
              key: const ValueKey('view-yearly-output'),
              size: ShadButtonSize.sm,
              onPressed: widget.onOutput,
              child: const Text('View yearly output'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (_, c) => Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: c.maxWidth.clamp(120.0, 260.0).toDouble(),
              child: ShadSelect<String>(
                key: ValueKey('project-status-${widget.status}'),
                initialValue: widget.status,
                minWidth: c.maxWidth.clamp(120.0, 260.0).toDouble(),
                options: const [
                  ShadOption(
                    value: 'completed',
                    child: Text('Completed projects'),
                  ),
                  ShadOption(value: 'all', child: Text('All project records')),
                ],
                selectedOptionBuilder: (_, v) => Text(
                  v == 'completed'
                      ? 'Completed projects'
                      : 'All project records',
                ),
                onChanged: (v) {
                  if (v != null) widget.onStatus(v);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (total == 0)
          _panel(
            context,
            'No projects match this selection',
            'Completion requires recorded approval and assessment closure.',
            Text(
              'Choose another period or select All project records to inspect work in progress.',
              style: _muted(context),
            ),
          )
        else
          _pair(
            _panel(
              context,
              'Project mix',
              _dimension == 'application_area'
                  ? 'Document-based project purposes. Each project counts once.'
                  : _dimension == 'category'
                  ? 'Broad computing focus. Different project purposes can share a focus.'
                  : 'Broad application domain. Campus projects can share the Education domain.',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (_, constraints) {
                      if (constraints.maxWidth < 400) {
                        return ShadSelect<String>(
                          key: ValueKey('project-mix-dimension-$_dimension'),
                          initialValue: _dimension,
                          minWidth: constraints.maxWidth,
                          maxWidth: constraints.maxWidth,
                          options: const [
                            ShadOption(
                              value: 'application_area',
                              child: Text('Application area'),
                            ),
                            ShadOption(
                              value: 'category',
                              child: Text('Project focus'),
                            ),
                            ShadOption(value: 'domain', child: Text('Domain')),
                          ],
                          selectedOptionBuilder: (_, value) => Text(
                            value == 'application_area'
                                ? 'Application area'
                                : value == 'category'
                                ? 'Project focus'
                                : 'Domain',
                          ),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _allGroups = false;
                              widget.onDimension(value);
                            });
                          },
                        );
                      }
                      return ShadTabs<String>(
                        key: const ValueKey('project-mix-tabs'),
                        value: _dimension,
                        gap: 0,
                        scrollable: false,
                        onChanged: (v) => setState(() {
                          widget.onDimension(v);
                          _allGroups = false;
                        }),
                        tabs: const [
                          ShadTab(
                            value: 'application_area',
                            child: Flexible(child: Text('Application area')),
                          ),
                          ShadTab(
                            value: 'category',
                            child: Flexible(child: Text('Project focus')),
                          ),
                          ShadTab(
                            value: 'domain',
                            child: Flexible(child: Text('Domain')),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  if (ranks.length == 1) ...[
                    Text(
                      ranks.single.key.startsWith('Unresolved') ||
                              ranks.single.key == 'Unclassified'
                          ? '${total == 1 ? 'The project needs' : 'All $total projects need'} more evidence for this grouping.'
                          : 'All $total projects share this ${_dimension == 'category'
                                ? 'computing focus'
                                : _dimension == 'domain'
                                ? 'domain'
                                : 'application area'}.',
                      key: const ValueKey('project-mix-single-group'),
                      style: _muted(context),
                    ),
                    if (_dimension != 'application_area')
                      Text(
                        'Choose Application area to compare their documented purposes.',
                        style: _muted(context),
                      ),
                    const SizedBox(height: 8),
                  ],
                  Column(
                    key: const ValueKey('project-mix-bars'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final e in ranks.take(_allGroups ? ranks.length : 6))
                        _groupRow(
                          context,
                          e.key,
                          e.value,
                          total,
                          e.key.startsWith('Unresolved') ||
                                  e.key == 'Unclassified'
                              ? CurriculumChartPalette.neutral(context)
                              : CurriculumChartPalette.primary(context),
                          () => widget.onGroup(_dimension, e.key),
                          bar: true,
                        ),
                    ],
                  ),
                  if (ranks.length > 6)
                    ShadButton.link(
                      key: const ValueKey('show-project-groups'),
                      size: ShadButtonSize.sm,
                      onPressed: () => setState(() => _allGroups = !_allGroups),
                      child: Text(
                        _allGroups
                            ? 'Show leading areas'
                            : 'Show all ${ranks.length} groups',
                      ),
                    ),
                ],
              ),
            ),
            _panel(
              context,
              'Documented technologies',
              'Projects can use several technologies; percentages overlap.',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (stack.isEmpty)
                    Text(
                      'No technologies specified in the eligible documents. Concept papers can leave the stack undecided; technologies are not inferred.',
                      style: _muted(context),
                    ),
                  for (final e in stack.take(
                    _allTechnologies ? stack.length : 8,
                  ))
                    _groupRow(
                      context,
                      e.key,
                      e.value,
                      total,
                      CurriculumChartPalette.primary(context),
                      () => widget.onGroup('technology', e.key),
                      bar: true,
                      field: 'technology',
                    ),
                  if (stack.length > 8)
                    ShadButton.link(
                      size: ShadButtonSize.sm,
                      onPressed: () =>
                          setState(() => _allTechnologies = !_allTechnologies),
                      child: Text(
                        _allTechnologies
                            ? 'Show leading technologies'
                            : 'Show all technologies',
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),
        ShadButton.link(
          key: const ValueKey('view-all-projects'),
          size: ShadButtonSize.sm,
          onPressed: () => widget.onGroup('category', '__all__'),
          child: const Text('Explore contributing projects'),
        ),
        ShadAccordion<String>(
          children: [
            ShadAccordionItem(
              value: 'counting',
              title: const Text('Counting and evidence'),
              child: Text(
                '${widget.data['completion_policy'] ?? ''} Application areas describe the service or purpose supported by source passages; they do not imply a platform or technology. Focus, domain and technology estimates use eligible documents from the assigned project year. Estimates are not faculty-reviewed. Missing evidence stays explicit.',
                style: _muted(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _groupRow(
    BuildContext c,
    String name,
    int count,
    int total,
    Color color,
    VoidCallback onTap, {
    bool bar = false,
    String? field,
  }) => ShadButton.ghost(
    key: ValueKey('project-group-${field ?? _dimension}-$name'),
    width: double.infinity,
    height: bar ? 72 : 60,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    onPressed: onTap,
    child: Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (!bar) ...[
                Container(width: 8, height: 8, color: color),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  name,
                  textAlign: TextAlign.left,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count / $total · ${total == 0 ? 0 : (count / total * 100).round()}%',
                style: _muted(c),
              ),
            ],
          ),
          if (bar) ...[
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (_, b) => Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 8,
                  width: total == 0 ? 0 : b.maxWidth * count / total,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
