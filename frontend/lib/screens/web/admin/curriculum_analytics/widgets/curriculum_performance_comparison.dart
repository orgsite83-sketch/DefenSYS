import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../../../services/academic/curriculum_explorer_provider.dart';
import '../../../../../theme/defensys_tokens.dart';
import 'curriculum_chart_palette.dart';

class CurriculumPerformanceComparison extends StatefulWidget {
  const CurriculumPerformanceComparison({
    super.key,
    required this.data,
    required this.query,
    required this.onSubject,
    required this.onAssessment,
  });
  final Map<String, dynamic> data;
  final CurriculumExplorerQuery query;
  final ValueChanged<String> onSubject;
  final void Function(String context, String role) onAssessment;

  @override
  State<CurriculumPerformanceComparison> createState() =>
      _CurriculumPerformanceComparisonState();
}

class _CurriculumPerformanceComparisonState
    extends State<CurriculumPerformanceComparison> {
  final _chartScroll = ScrollController();

  @override
  void dispose() {
    _chartScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data, query = widget.query;
    final onSubject = widget.onSubject, onAssessment = widget.onAssessment;
    final performance = data['performance'] as Map? ?? {};
    final rows = explorerRows(performance['contexts']);
    final selections = explorerRows(performance['selections']);
    final muted = TextStyle(
      fontSize: 12,
      height: 1.5,
      color: DefensysTokens.textSecondaryOf(context),
    );
    String label(Map<String, dynamic> row) =>
        '${row['label']}${row['semester_label'] == null ? '' : ' · ${row['semester_label']}'}';
    Map<String, dynamic>? component(Map<String, dynamic> row, String role) =>
        explorerRows(
          row['components'],
        ).where((r) => r['id'] == role).firstOrNull;
    final roles = ['panel', 'peer', if (query.scope == 'capstone') 'adviser']
        .where(
          (role) => rows.any((r) => component(r, role)?['available'] == true),
        )
        .toList();
    return ShadCard(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      title: Text(
        query.view == 'assessment'
            ? 'Evaluator components'
            : query.scope == 'pit'
            ? 'Performance across events'
            : 'Performance across stages',
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      description: Text(
        'Published component percentages · before final-grade weighting',
        style: muted,
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Show results for',
              style: muted.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (_, constraints) => ShadSelect<String>(
                key: ValueKey('performance-subject-${query.subject}'),
                initialValue: query.subject,
                minWidth: constraints.maxWidth,
                maxWidth: constraints.maxWidth,
                options: [
                  const ShadOption(value: '', child: Text('All students')),
                  for (final option in selections)
                    ShadOption(
                      value: '${option['id']}',
                      child: Text(
                        '${option['kind'] == 'team' ? 'Team · ' : 'Student · '}${option['label']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                selectedOptionBuilder: (_, value) => Text(
                  value.isEmpty
                      ? 'All students'
                      : '${selections.where((r) => r['id'] == value).firstOrNull?['label'] ?? 'Selection unavailable'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onChanged: (value) {
                  if (value != null) onSubject(value);
                },
              ),
            ),
            const SizedBox(height: 16),
            if (rows.isEmpty || roles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Text(
                  'No component comparisons are available for this period yet.',
                  style: muted,
                ),
              )
            else ...[
              Semantics(
                label:
                    'Clustered percentages across the academic year. Equivalent event and evaluator controls follow the chart.',
                child: LayoutBuilder(
                  builder: (_, constraints) => Scrollbar(
                    controller: _chartScroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _chartScroll,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: constraints.maxWidth < rows.length * 130
                            ? rows.length * 130.0
                            : constraints.maxWidth,
                        height: 330,
                        child: SfCartesianChart(
                          key: const ValueKey('performance-clustered-chart'),
                          margin: const EdgeInsets.fromLTRB(0, 12, 8, 0),
                          plotAreaBorderWidth: 0,
                          tooltipBehavior: TooltipBehavior(
                            enable: true,
                            builder: (point, _, series, pointIndex, seriesIndex) {
                              final row = rows[pointIndex];
                              final value = component(row, roles[seriesIndex]);
                              return Container(
                                padding: const EdgeInsets.all(12),
                                constraints: const BoxConstraints(
                                  maxWidth: 260,
                                ),
                                decoration: BoxDecoration(
                                  color: DefensysTokens.surfaceOf(context),
                                  border: Border.all(
                                    color: DefensysTokens.borderOf(context),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${label(row)}\n${value?['label']}: ${explorerNumber(value?['score'])?.toStringAsFixed(1) ?? 'Awaiting'}%\n'
                                  '${value?['assessed'] ?? 0} / ${value?['eligible'] ?? 0} students assessed\n'
                                  '${value?['shared'] ?? 0} shared team results',
                                  style: muted,
                                ),
                              );
                            },
                          ),
                          primaryXAxis: CategoryAxis(
                            labelStyle: muted.copyWith(fontSize: 11),
                            labelIntersectAction: AxisLabelIntersectAction.wrap,
                            maximumLabels: 3,
                            majorGridLines: const MajorGridLines(width: 0),
                            majorTickLines: const MajorTickLines(size: 0),
                            axisLine: AxisLine(
                              color: DefensysTokens.borderOf(context),
                            ),
                          ),
                          primaryYAxis: NumericAxis(
                            minimum: 0,
                            maximum: 100,
                            interval: 25,
                            labelFormat: '{value}%',
                            labelStyle: muted.copyWith(fontSize: 11),
                            axisLine: const AxisLine(width: 0),
                            majorTickLines: const MajorTickLines(size: 0),
                            majorGridLines: MajorGridLines(
                              color: DefensysTokens.borderOf(context),
                            ),
                          ),
                          series:
                              <CartesianSeries<Map<String, dynamic>, String>>[
                                for (final role in roles)
                                  ColumnSeries<Map<String, dynamic>, String>(
                                    name:
                                        role[0].toUpperCase() +
                                        role.substring(1),
                                    dataSource: rows,
                                    xValueMapper: (r, _) => label(r),
                                    yValueMapper: (r, _) => explorerNumber(
                                      component(r, role)?['score'],
                                    ),
                                    color: CurriculumChartPalette.evaluator(
                                      context,
                                      role,
                                    ),
                                    width: .72,
                                    spacing: .12,
                                    animationDuration: 0,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(2),
                                    ),
                                    onPointTap: (details) {
                                      if (details.pointIndex != null) {
                                        onAssessment(
                                          '${rows[details.pointIndex!]['id']}',
                                          role,
                                        );
                                      }
                                    },
                                  ),
                              ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  for (final role in roles)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          color: CurriculumChartPalette.evaluator(
                            context,
                            role,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          role[0].toUpperCase() + role.substring(1),
                          style: muted,
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ShadAccordion<String>(
                children: [
                  ShadAccordionItem(
                    value: 'comparison-records',
                    title: Text(
                      'Assessment coverage and accessible results',
                      style: muted,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final row in rows) ...[
                          Text(
                            label(row),
                            style: muted.copyWith(fontWeight: FontWeight.w600),
                          ),
                          for (final role in roles)
                            ShadButton.ghost(
                              key: ValueKey('assessment-${row['id']}-$role'),
                              mainAxisAlignment: MainAxisAlignment.start,
                              onPressed: () =>
                                  onAssessment('${row['id']}', role),
                              child: Flexible(
                                child: Text(
                                  '${component(row, role)?['label'] ?? role}: '
                                  '${explorerNumber(component(row, role)?['score'])?.toStringAsFixed(1) ?? 'Awaiting'}'
                                  ' · ${component(row, role)?['assessed'] ?? 0}/${component(row, role)?['eligible'] ?? 0} students'
                                  ' · ${component(row, role)?['shared'] ?? 0} shared team results',
                                  textAlign: TextAlign.left,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Select a column to inspect its criteria. Missing scores are excluded. Shared team results are identified in assessment coverage.',
              style: muted,
            ),
          ],
        ),
      ),
    );
  }
}
