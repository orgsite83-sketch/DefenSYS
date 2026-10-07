import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../../../services/academic/curriculum_explorer_provider.dart';
import '../../../../../theme/defensys_tokens.dart';
import 'curriculum_explorer_charts.dart';

const classificationReasonLabels = {
  'no_documents': 'No eligible project documents',
  'unreadable': 'Text extraction unavailable',
  'unrelated_documents': 'Document topic needs checking',
  'insufficient_evidence': 'Insufficient computing evidence',
  'low_score': 'Model score below threshold',
  'ambiguous': 'Competing computing categories',
};

class CurriculumProjectAnalytics extends StatefulWidget {
  const CurriculumProjectAnalytics({
    super.key,
    required this.data,
    required this.query,
    required this.onGroup,
    required this.onYear,
    required this.onCriterion,
  });
  final Map<String, dynamic> data;
  final CurriculumExplorerQuery query;
  final void Function(String field, String value) onGroup;
  final ValueChanged<String> onYear;
  final void Function(String criterion, String category) onCriterion;

  @override
  State<CurriculumProjectAnalytics> createState() =>
      _CurriculumProjectAnalyticsState();
}

class _CurriculumProjectAnalyticsState
    extends State<CurriculumProjectAnalytics> {
  String _trendDimension = 'distribution', _trendMetric = 'share';
  TextStyle get _muted => TextStyle(
    fontSize: 12,
    height: 1.5,
    color: DefensysTokens.textSecondaryOf(context),
  );

  Map<String, dynamic> get _analytics => widget.data['project_analytics'] is Map
      ? Map<String, dynamic>.from(widget.data['project_analytics'] as Map)
      : {};

  Widget _panel(String title, String description, Widget child) => ShadCard(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    title: Text(
      title,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    ),
    description: Text(description, style: _muted),
    child: Padding(padding: const EdgeInsets.only(top: 18), child: child),
  );

  Widget _pair(Widget left, Widget right) => LayoutBuilder(
    builder: (_, c) => c.maxWidth < 850
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 18), right],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 20),
              Expanded(child: right),
            ],
          ),
  );

  @override
  Widget build(BuildContext context) {
    final analytics = _analytics;
    final focus = explorerRows(analytics['categories']);
    final domains = explorerRows(analytics['domains']);
    final technologies = explorerRows(analytics['technologies']);
    final reasons = explorerRows(analytics['unresolved_reasons']);
    final observations = analytics['observations'] as List? ?? [];
    final projects = explorerNumber(widget.data['projects_count']) ?? 0;
    if (projects == 0) {
      return _panel(
        'No projects in this selection',
        'Choose another academic year or semester.',
        Text(
          'Charts use one unique project per team in the selected period.',
          style: _muted,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (observations.isNotEmpty) ...[
          Container(
            key: const ValueKey('project-observations'),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: DefensysTokens.surfaceHigherOf(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Observed patterns',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                for (final sentence in observations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('$sentence', style: _muted),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        _pair(
          _panel(
            'Primary computing focus',
            'One primary estimate per project · share of the full cohort',
            focus.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No supported computing estimates yet. Classification coverage below explains the unresolved results.',
                      style: _muted,
                    ),
                  )
                : _distribution(focus, 'category'),
          ),
          _panel(
            'Application domains',
            'The problems projects address · separate from technology',
            domains.isEmpty
                ? Text(
                    'No application-domain evidence is available yet.',
                    style: _muted,
                  )
                : _distribution(domains, 'domain'),
          ),
        ),
        const SizedBox(height: 20),
        _pair(
          _panel(
            'Documented technologies',
            'A project can mention several technologies; shares can overlap.',
            technologies.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No specific technologies are established in the eligible document sections. Tentative technology choices are excluded.',
                      style: _muted,
                    ),
                  )
                : _distribution(technologies, 'technology'),
          ),
          _coverage(reasons),
        ),
        const SizedBox(height: 20),
        _trends(),
        const SizedBox(height: 20),
        _performance(),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: ShadButton.link(
            key: const ValueKey('view-all-projects'),
            size: ShadButtonSize.sm,
            onPressed: () => widget.onGroup('category', '__all__'),
            trailing: const Icon(LucideIcons.arrowRight, size: 14),
            child: const Text('Explore contributing projects'),
          ),
        ),
      ],
    );
  }

  Widget _distribution(List<Map<String, dynamic>> rows, String field) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final row in rows)
        ShadButton.ghost(
          key: ValueKey('$field-${row['category']}'),
          width: double.infinity,
          height: 82,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          mainAxisAlignment: MainAxisAlignment.start,
          onPressed: () => widget.onGroup(field, '${row['category']}'),
          child: Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${row['category']}',
                        textAlign: TextAlign.left,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${row['count']} · ${(explorerNumber(row['percentage']) ?? 0).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 9,
                  child: LayoutBuilder(
                    builder: (_, c) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width:
                            c.maxWidth *
                            (explorerNumber(row['percentage']) ?? 0).clamp(
                              0,
                              100,
                            ) /
                            100,
                        height: 9,
                        decoration: BoxDecoration(
                          color: field == 'category'
                              ? curriculumCategoryColor(
                                  context,
                                  '${row['category']}',
                                )
                              : DefensysTokens.maroonOf(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      const CurriculumPercentAxis(),
      const SizedBox(height: 12),
      Text(
        'Select a bar to inspect the projects and supporting passages.',
        style: _muted,
      ),
    ],
  );

  Widget _coverage(List<Map<String, dynamic>> reasons) {
    final coverage = _analytics['coverage'] as Map? ?? {};
    return _panel(
      'Classification coverage',
      'Uploaded documents and unresolved estimates are different states.',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 28,
            runSpacing: 16,
            children: [
              _stat('${coverage['classified'] ?? 0}', 'Estimated focus'),
              _stat('${coverage['unresolved'] ?? 0}', 'Unresolved focus'),
              _stat(
                '${coverage['domains_resolved'] ?? 0}',
                'Domain identified',
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (reasons.isEmpty)
            Text(
              'Every project has a supported computing estimate. Estimates still require academic review.',
              style: _muted,
            )
          else ...[
            Text(
              'Why projects remain unresolved',
              style: _muted.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final reason in reasons)
              ShadButton.ghost(
                key: ValueKey('reason-${reason['category']}'),
                width: double.infinity,
                height: 62,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                onPressed: () =>
                    widget.onGroup('reason', '${reason['category']}'),
                child: Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          classificationReasonLabels['${reason['category']}'] ??
                              '${reason['category']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _muted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${reason['count']}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(LucideIcons.chevronRight, size: 14),
                    ],
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton.link(
                key: const ValueKey('category-Unclassified'),
                size: ShadButtonSize.sm,
                onPressed: () => widget.onGroup('category', 'Unclassified'),
                child: const Text('Inspect unresolved projects'),
              ),
            ),
          ],
          ShadAccordion<String>(
            children: [
              ShadAccordionItem(
                value: 'method',
                title: Text('How are the estimates assigned?', style: _muted),
                child: Text(
                  'Computing focus is estimated from substantive project sections using a section-aware text model and supporting terms. Application domains and technology mentions use document evidence separately. References and tentative choices are excluded. The current model uses authored development examples and has not been validated against a faculty-reviewed dataset. Model scores are not measured accuracy.',
                  style: _muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 3),
      Text(label, style: _muted),
    ],
  );

  Widget _trends() {
    final rows = explorerRows(widget.data['project_trends']);
    final categories = <String>{
      for (final year in rows)
        for (final group in explorerRows(year[_trendDimension]))
          '${group['category']}',
    };
    return _panel(
      'Project interests across academic years',
      'Compare cohort counts, category shares and classification coverage.',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 210,
                child: ShadSelect<String>(
                  initialValue: _trendDimension,
                  onChanged: (v) {
                    if (v != null) setState(() => _trendDimension = v);
                  },
                  options: const [
                    ShadOption(
                      value: 'distribution',
                      child: Text('Computing focus'),
                    ),
                    ShadOption(
                      value: 'domains',
                      child: Text('Application domains'),
                    ),
                  ],
                  selectedOptionBuilder: (_, v) => Text(
                    v == 'domains' ? 'Application domains' : 'Computing focus',
                  ),
                ),
              ),
              SizedBox(
                width: 190,
                child: ShadTabs<String>(
                  value: _trendMetric,
                  gap: 0,
                  scrollable: false,
                  onChanged: (v) => setState(() => _trendMetric = v),
                  tabs: const [
                    ShadTab(
                      value: 'share',
                      child: Flexible(child: Text('Share')),
                    ),
                    ShadTab(
                      value: 'count',
                      child: Flexible(child: Text('Count')),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (rows.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'One academic year is available. A trend needs at least two recorded cohorts.',
                style: _muted,
              ),
            )
          else
            SizedBox(
              height: 310,
              child: SfCartesianChart(
                key: ValueKey('project-trend-$_trendDimension-$_trendMetric'),
                plotAreaBorderWidth: 0,
                legend: Legend(
                  isVisible: true,
                  position: LegendPosition.bottom,
                  overflowMode: LegendItemOverflowMode.wrap,
                  textStyle: _muted.copyWith(fontSize: 10),
                ),
                tooltipBehavior: TooltipBehavior(enable: true),
                primaryXAxis: CategoryAxis(
                  majorGridLines: const MajorGridLines(width: 0),
                  labelStyle: _muted,
                ),
                primaryYAxis: NumericAxis(
                  minimum: 0,
                  maximum: _trendMetric == 'share' ? 100 : null,
                  labelFormat: _trendMetric == 'share' ? '{value}%' : '{value}',
                  labelStyle: _muted,
                  majorGridLines: MajorGridLines(
                    color: DefensysTokens.borderOf(context),
                  ),
                ),
                series: [
                  for (final category in categories)
                    StackedColumnSeries<Map<String, dynamic>, String>(
                      name: category,
                      dataSource: rows,
                      animationDuration: 0,
                      color: curriculumCategoryColor(context, category),
                      xValueMapper: (year, _) => '${year['academic_year']}',
                      yValueMapper: (year, _) {
                        final count = explorerRows(year[_trendDimension])
                            .where((r) => r['category'] == category)
                            .fold(
                              0.0,
                              (sum, r) =>
                                  sum + (explorerNumber(r['count']) ?? 0),
                            );
                        final total =
                            explorerNumber(year['projects_count']) ?? 0;
                        return _trendMetric == 'share'
                            ? total == 0
                                  ? 0
                                  : count / total * 100
                            : count;
                      },
                      onPointTap: (details) {
                        if (details.pointIndex != null) {
                          widget.onYear(
                            '${rows[details.pointIndex!]['academic_year']}',
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
          LayoutBuilder(
            builder: (_, c) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final year in rows)
                  ShadButton.outline(
                    key: ValueKey(
                      'project-trend-year-${year['academic_year']}',
                    ),
                    size: ShadButtonSize.sm,
                    width: math.min(c.maxWidth, 300),
                    height: 56,
                    onPressed: () => widget.onYear('${year['academic_year']}'),
                    child: Flexible(
                      child: Text(
                        '${year['academic_year']} · ${year['projects_count']} projects · ${year['classified'] ?? 0} classified',
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Unresolved projects remain visible. Changes in classification coverage can affect apparent trends.',
            style: _muted,
          ),
        ],
      ),
    );
  }

  Widget _performance() {
    final rows = explorerRows(_analytics['performance']);
    final categories = <String>{
      for (final row in rows)
        for (final group in explorerRows(row['categories']))
          '${group['category']}',
    };
    final selected = explorerRows(
      widget.data['contexts'],
    ).where((c) => c['id'] == widget.query.context).firstOrNull;
    return _panel(
      'Rubric performance by project focus',
      '${selected?['label'] ?? 'Select an assessment'} · ${widget.query.role} results · ${widget.query.reference.toStringAsFixed(0)}% analysis reference',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (categories.isEmpty || rows.isEmpty)
            Text(
              'This comparison needs classified projects and recorded criterion scores in the selected assessment.',
              style: _muted,
            )
          else
            LayoutBuilder(
              builder: (_, c) {
                final width = math.max(
                  c.maxWidth,
                  240.0 + categories.length * 125,
                );
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 240,
                              child: Text(
                                'Criterion / rubric',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            for (final category in categories)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    category,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final row in rows)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 240,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${row['name']}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          '${row['semester']} · ${row['rubric']}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: _muted.copyWith(fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                for (final category in categories)
                                  Expanded(
                                    child: Builder(
                                      builder: (_) {
                                        final group =
                                            explorerRows(row['categories'])
                                                .where(
                                                  (g) =>
                                                      g['category'] == category,
                                                )
                                                .firstOrNull;
                                        final score = explorerNumber(
                                          group?['score'],
                                        );
                                        final count =
                                            (explorerNumber(
                                                      group?['assessed_teams'],
                                                    ) ??
                                                    0)
                                                .toInt();
                                        final color =
                                            score != null &&
                                                score < widget.query.reference
                                            ? DefensysTokens.goldOf(context)
                                            : DefensysTokens.maroonTextOf(
                                                context,
                                              );
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          child: ShadButton.ghost(
                                            key: ValueKey(
                                              'focus-performance-${row['id']}-$category',
                                            ),
                                            height: 66,
                                            width: double.infinity,
                                            enabled: score != null,
                                            backgroundColor: score == null
                                                ? DefensysTokens.surfaceHigherOf(
                                                    context,
                                                  )
                                                : color.withValues(alpha: .12),
                                            onPressed: () => widget.onCriterion(
                                              '${row['id']}',
                                              category,
                                            ),
                                            child: Expanded(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    score == null
                                                        ? '—'
                                                        : '${score.toStringAsFixed(1)}%',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: color,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    '$count ${count == 1 ? 'team' : 'teams'}${count > 0 && count < 3 ? ' · small sample' : ''}',
                                                    maxLines: 2,
                                                    textAlign: TextAlign.center,
                                                    style: _muted.copyWith(
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
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
            ),
          const SizedBox(height: 14),
          Text(
            'Select a cell to inspect its team results. Missing scores are excluded. Peer cells average assessed members within each team. Small samples and estimated categories limit comparisons; these associations do not establish cause.',
            style: _muted,
          ),
        ],
      ),
    );
  }
}
