import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../../../services/academic/curriculum_explorer_provider.dart';
import '../../../../../theme/defensys_tokens.dart';
import 'curriculum_chart_palette.dart';

class CurriculumPerformanceComparison extends StatelessWidget {
  const CurriculumPerformanceComparison({
    super.key,
    required this.data,
    required this.query,
    required this.onSubject,
    required this.onAssessment,
    this.embedded = false,
  });
  final Map<String, dynamic> data;
  final CurriculumExplorerQuery query;
  final ValueChanged<String> onSubject;
  final void Function(String context, String role) onAssessment;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final performance = data['performance'] as Map? ?? {};
    final rows = explorerRows(performance['contexts']);
    final selections = explorerRows(performance['selections']);
    final muted = TextStyle(
      fontFamily: DefensysTokens.fontFamilyInter,
      fontSize: 12,
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
    Widget accessibleResults() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              label(row),
              style: muted.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          for (final role in roles)
            if (component(row, role)?['available'] == true)
              ShadButton.ghost(
                key: ValueKey('assessment-${row['id']}-$role'),
                mainAxisAlignment: MainAxisAlignment.start,
                onPressed: () => onAssessment('${row['id']}', role),
                leading: Icon(
                  query.context == row['id'] && query.role == role
                      ? LucideIcons.circleCheck
                      : LucideIcons.circle,
                  size: 14,
                  color: CurriculumChartPalette.evaluator(context, role),
                ),
                child: Flexible(
                  child: Text(
                    '${component(row, role)?['label'] ?? role} · '
                    '${explorerNumber(component(row, role)?['score'])?.toStringAsFixed(1) ?? 'Pending'}'
                    '${component(row, role)?['score'] == null ? '' : '%'}'
                    ' · ${component(row, role)?['assessed'] ?? 0}/${component(row, role)?['eligible'] ?? 0}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
        ],
      ],
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShadSelect<String>(
          key: ValueKey('performance-subject-${query.subject}'),
          initialValue: query.subject,
          options: [
            const ShadOption(value: '', child: Text('All students')),
            for (final option in selections)
              ShadOption(
                value: '${option['id']}',
                child: Text(
                  '${option['kind'] == 'team' ? 'Team' : 'Student'} · ${option['label']}',
                ),
              ),
          ],
          selectedOptionBuilder: (_, v) => Text(
            v.isEmpty
                ? 'All students'
                : '${selections.where((r) => r['id'] == v).firstOrNull?['label'] ?? 'Selection unavailable'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onChanged: (v) {
            if (v != null) onSubject(v);
          },
        ),
        const SizedBox(height: 16),
        if (rows.isEmpty || roles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Text('No published results', style: muted),
          )
        else
          LayoutBuilder(
            builder: (_, c) {
              if (c.maxWidth < 360) return accessibleResults();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      for (final role in roles)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 9,
                              height: 9,
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
                  SizedBox(
                    height: 290,
                    child: SfCartesianChart(
                      key: const ValueKey('performance-clustered-chart'),
                      plotAreaBorderWidth: 0,
                      tooltipBehavior: TooltipBehavior(
                        enable: true,
                        builder: (point, _, series, pi, si) {
                          final row = rows[pi],
                              value = component(row, roles[si]);
                          final score = explorerNumber(value?['score']);
                          return Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: DefensysTokens.surfaceOf(context),
                              border: Border.all(
                                color: DefensysTokens.borderOf(context),
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${label(row)} · ${value?['label']}\n'
                              '${score == null ? 'Pending' : '${score.toStringAsFixed(1)}%'} · '
                              '${value?['assessed']}/${value?['eligible']} students\n'
                              '${value?['shared'] ?? 0} shared team results',
                              style: muted,
                            ),
                          );
                        },
                      ),
                      primaryXAxis: CategoryAxis(
                        labelStyle: muted,
                        labelIntersectAction: AxisLabelIntersectAction.wrap,
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
                        labelStyle: muted,
                        axisLine: const AxisLine(width: 0),
                        majorTickLines: const MajorTickLines(size: 0),
                        majorGridLines: MajorGridLines(
                          color: DefensysTokens.borderOf(context),
                        ),
                      ),
                      series: <CartesianSeries<Map<String, dynamic>, String>>[
                        for (final role in roles)
                          ColumnSeries<Map<String, dynamic>, String>(
                            name: role[0].toUpperCase() + role.substring(1),
                            dataSource: rows,
                            xValueMapper: (r, _) => label(r),
                            yValueMapper: (r, _) =>
                                component(r, role)?['available'] == true
                                ? explorerNumber(component(r, role)?['score'])
                                : null,
                            pointColorMapper: (r, _) =>
                                CurriculumChartPalette.evaluator(
                                  context,
                                  role,
                                ).withValues(
                                  alpha:
                                      query.context == r['id'] &&
                                          query.role == role
                                      ? 1
                                      : .36,
                                ),
                            width: .72,
                            spacing: .12,
                            animationDuration: 0,
                            onPointTap: (d) {
                              if (d.pointIndex != null) {
                                onAssessment(
                                  '${rows[d.pointIndex!]['id']}',
                                  role,
                                );
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                  ShadAccordion<String>(
                    children: [
                      ShadAccordionItem(
                        value: 'comparison-records',
                        title: Text('Assessment coverage', style: muted),
                        child: accessibleResults(),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
      ],
    );
    if (embedded) return body;
    return ShadCard(
      backgroundColor: DefensysTokens.surfaceOf(context),
      width: double.infinity,
      title: Text(
        query.scope == 'pit'
            ? 'Performance across events'
            : 'Performance across stages',
      ),
      child: Padding(padding: const EdgeInsets.only(top: 16), child: body),
    );
  }
}
