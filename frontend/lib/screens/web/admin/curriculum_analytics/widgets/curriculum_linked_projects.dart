import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../../../services/academic/curriculum_explorer_provider.dart';
import '../../../../../theme/defensys_tokens.dart';
import 'curriculum_chart_palette.dart';
import 'curriculum_linked_panels.dart';

class CurriculumLinkedProjects extends StatelessWidget {
  const CurriculumLinkedProjects({
    super.key,
    required this.data,
    required this.query,
    required this.dimension,
    required this.onDimension,
    required this.onYear,
    required this.onStatus,
    required this.onGroup,
    required this.onClear,
    required this.projectList,
    this.group,
    this.groupField = 'domain',
  });
  final Map<String, dynamic> data;
  final CurriculumExplorerQuery query;
  final String dimension, groupField;
  final String? group;
  final ValueChanged<String> onDimension, onYear, onStatus;
  final void Function(String, String) onGroup;
  final VoidCallback onClear;
  final Widget projectList;

  @override
  Widget build(BuildContext context) {
    const dimensions = {
      'application_area': 'Application area',
      'domain': 'Domain',
      'category': 'Computing focus',
    };
    final all = explorerRows(data['project_collection'] ?? data['projects']);
    final years =
        (data['range_years'] as List? ??
                all
                    .map((p) => p['academic_year'])
                    .whereType<String>()
                    .toSet()
                    .toList())
            .map((y) => '$y')
            .toList()
          ..sort();
    final year = query.year.isNotEmpty ? query.year : years.lastOrNull ?? '';
    final projects = all.where((p) => p['academic_year'] == year).toList();
    final activeGroup = groupField == dimension && group != '__all__'
        ? group
        : null;
    final filtered = group == null || group == '__all__'
        ? projects
        : projects
              .where(
                (p) => groupField == 'technology'
                    ? (p['technologies'] as List? ?? []).contains(group)
                    : p[groupField] == group,
              )
              .toList();
    String name(Map<String, dynamic> p) =>
        '${p[dimension] ?? (dimension == 'application_area' ? 'Unresolved application area' : 'Unclassified')}';
    final labels = all.map(name).toSet().toList()..sort();
    final totals = {
      for (final y in years)
        y: all.where((p) => p['academic_year'] == y).length,
    };
    final maxCount = totals.values.fold<int>(0, math.max);
    final maximum = math.max(4, (maxCount / 4).ceil() * 4).toDouble();
    final ranked =
        {
          for (final label in labels)
            label: projects.where((p) => name(p) == label).length,
        }.entries.where((e) => e.value > 0).toList()..sort((a, b) {
          final counts = b.value.compareTo(a.value);
          return counts == 0 ? a.key.compareTo(b.key) : counts;
        });
    final text = TextStyle(
      fontFamily: DefensysTokens.fontFamilyInter,
      fontSize: 12,
      color: DefensysTokens.textSecondaryOf(context),
    );
    final title = TextStyle(
      fontFamily: DefensysTokens.fontFamilyInter,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: DefensysTokens.textPrimaryOf(context),
    );

    Widget rank(
      String label,
      int count,
      int total,
      Color color,
      VoidCallback pressed, {
      bool selected = false,
      double? scale,
    }) => Semantics(
      selected: selected,
      label: '$label, $count of $total projects',
      child: ShadButton.ghost(
        key: ValueKey('project-group-$dimension-$label'),
        width: double.infinity,
        height: 74,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        onPressed: pressed,
        child: Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(width: 8, height: 8, color: color),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.left,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count · ${total == 0 ? 0 : (count / total * 100).round()}%',
                    style: text,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (_, c) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 10,
                    width:
                        c.maxWidth *
                        (count / (scale ?? math.max(total, 1))).clamp(0, 1),
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final chart = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final label in labels)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    color: CurriculumChartPalette.category(context, label),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label,
                      style: text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 280,
          child: SfCartesianChart(
            key: const ValueKey('project-yearly-mix-chart'),
            plotAreaBorderWidth: 0,
            tooltipBehavior: TooltipBehavior(enable: true),
            primaryXAxis: CategoryAxis(
              labelStyle: text,
              labelIntersectAction: AxisLabelIntersectAction.wrap,
              majorGridLines: const MajorGridLines(width: 0),
              majorTickLines: const MajorTickLines(size: 0),
            ),
            primaryYAxis: NumericAxis(
              minimum: 0,
              maximum: maximum,
              interval: maximum / 4,
              decimalPlaces: 0,
              labelStyle: text,
              axisLine: const AxisLine(width: 0),
              majorTickLines: const MajorTickLines(size: 0),
              majorGridLines: MajorGridLines(
                color: DefensysTokens.borderOf(context),
              ),
            ),
            series: <CartesianSeries<String, String>>[
              for (final label in labels)
                StackedColumnSeries<String, String>(
                  name: label,
                  dataSource: years,
                  xValueMapper: (y, _) => y,
                  yValueMapper: (y, _) => all
                      .where((p) => p['academic_year'] == y && name(p) == label)
                      .length,
                  pointColorMapper: (y, _) =>
                      CurriculumChartPalette.category(
                        context,
                        label,
                      ).withValues(
                        alpha:
                            y == year &&
                                (activeGroup == null || activeGroup == label)
                            ? 1
                            : .3,
                      ),
                  width: .42,
                  animationDuration: 0,
                  onPointTap: (d) {
                    if (d.pointIndex != null) onYear(years[d.pointIndex!]);
                  },
                ),
            ],
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final y in years)
              ShadButton.ghost(
                key: ValueKey('project-year-$y'),
                size: ShadButtonSize.sm,
                leading: y == year
                    ? const Icon(LucideIcons.check, size: 12)
                    : null,
                onPressed: () => onYear(y),
                child: Text('$y · ${totals[y]}', style: text),
              ),
          ],
        ),
      ],
    );
    final ranking = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$year · ${dimensions[dimension]}', style: title),
        const SizedBox(height: 6),
        Text('${projects.length} projects', style: text),
        const SizedBox(height: 16),
        if (ranked.isEmpty) Text('No projects in this year', style: text),
        for (final e in ranked)
          rank(
            e.key,
            e.value,
            projects.length,
            CurriculumChartPalette.category(context, e.key).withValues(
              alpha: activeGroup == null || activeGroup == e.key ? 1 : .35,
            ),
            () => activeGroup == e.key ? onClear() : onGroup(dimension, e.key),
            selected: activeGroup == e.key,
            scale: maximum,
          ),
        if (ranked.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0', style: text),
                Text('${maximum ~/ 2}', style: text),
                Text('${maximum.toInt()} projects', style: text),
              ],
            ),
          ),
      ],
    );
    final technologies = <String, int>{};
    for (final p in filtered) {
      for (final t
          in (p['technologies'] as List? ?? []).map((v) => '$v').toSet()) {
        technologies.update(t, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final techs = technologies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final stages = <String, int>{};
    for (final p in projects) {
      final stage = '${p['current_stage'] ?? 'Not recorded'}';
      stages.update(stage, (n) => n + 1, ifAbsent: () => 1);
    }
    final techPanel = ShadCard(
      backgroundColor: DefensysTokens.surfaceOf(context),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      title: Text('Documented technologies', style: title),
      description: Text(
        '${filtered.length} projects · Tags can overlap',
        style: text,
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (techs.isEmpty)
              Text('Not specified in project sources', style: text),
            for (final e in techs.take(10))
              rank(
                e.key,
                e.value,
                filtered.length,
                CurriculumChartPalette.secondary(context),
                () => onGroup('technology', e.key),
              ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShadCard(
          backgroundColor: DefensysTokens.surfaceOf(context),
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          title: Text('Projects by academic year', style: title),
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    ShadSelect<String>(
                      key: ValueKey('linked-mix-$dimension'),
                      initialValue: dimension,
                      options: [
                        for (final e in dimensions.entries)
                          ShadOption(value: e.key, child: Text(e.value)),
                      ],
                      selectedOptionBuilder: (_, v) => Text(dimensions[v] ?? v),
                      onChanged: (v) {
                        if (v != null) onDimension(v);
                      },
                    ),
                    ShadSelect<String>(
                      key: ValueKey('linked-status-${query.projectStatus}'),
                      initialValue: query.projectStatus,
                      options: const [
                        ShadOption(
                          value: 'completed',
                          child: Text('Completed projects'),
                        ),
                        ShadOption(
                          value: 'all',
                          child: Text('All project records'),
                        ),
                      ],
                      selectedOptionBuilder: (_, v) => Text(
                        v == 'completed'
                            ? 'Completed projects'
                            : 'All project records',
                      ),
                      onChanged: (v) {
                        if (v != null) onStatus(v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(year, style: title),
                    const Icon(LucideIcons.chevronRight, size: 13),
                    Text(
                      group == null || group == '__all__'
                          ? switch (dimension) {
                              'domain' => 'All domains',
                              'category' => 'All computing focuses',
                              _ => 'All application areas',
                            }
                          : group!,
                      style: text,
                    ),
                    if (group != null)
                      ShadButton.ghost(
                        key: const ValueKey('clear-linked-project-group'),
                        size: ShadButtonSize.sm,
                        onPressed: onClear,
                        child: const Text('Clear'),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                CurriculumLinkedPanels(overview: chart, detail: ranking),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (_, c) {
            if (c.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [techPanel, const SizedBox(height: 20), projectList],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: techPanel),
                const SizedBox(width: 20),
                Expanded(flex: 3, child: projectList),
              ],
            );
          },
        ),
        if (query.projectStatus == 'all') ...[
          const SizedBox(height: 20),
          ShadCard(
            backgroundColor: DefensysTokens.surfaceOf(context),
            width: double.infinity,
            title: Text('Current stage', style: title),
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Wrap(
                spacing: 30,
                runSpacing: 14,
                children: [
                  for (final e in stages.entries)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(e.key, style: text),
                        Text('${e.value}', style: title),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        ShadAccordion<String>(
          children: [
            ShadAccordionItem(
              value: 'counting',
              title: Text('Counting and evidence', style: text),
              child: Text('${data['completion_policy'] ?? ''}', style: text),
            ),
          ],
        ),
      ],
    );
  }
}
