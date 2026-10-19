import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'curriculum_chart_palette.dart';
import '../../../../../services/academic/curriculum_explorer_provider.dart';
import '../../../../../theme/defensys_tokens.dart';

class CurriculumAnnualChart extends StatelessWidget {
  const CurriculumAnnualChart({
    super.key,
    required this.rows,
    required this.onYear,
  });
  final List<Map<String, dynamic>> rows;
  final ValueChanged<String> onYear;

  @override
  Widget build(BuildContext context) {
    final muted = DefensysTokens.textSecondaryOf(context);
    final border = DefensysTokens.borderOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 320,
          child: SfCartesianChart(
            key: const ValueKey('academic-year-chart'),
            margin: const EdgeInsets.fromLTRB(0, 16, 12, 0),
            plotAreaBorderWidth: 0,
            tooltipBehavior: TooltipBehavior(
              enable: true,
              format: 'point.x: point.y%',
            ),
            primaryXAxis: CategoryAxis(
              labelStyle: TextStyle(color: muted, fontSize: 12),
              majorGridLines: const MajorGridLines(width: 0),
              majorTickLines: const MajorTickLines(size: 0),
              axisLine: AxisLine(color: border, width: 1),
            ),
            primaryYAxis: NumericAxis(
              minimum: 0,
              maximum: 100,
              interval: 25,
              labelFormat: '{value}%',
              labelStyle: TextStyle(color: muted, fontSize: 11),
              majorGridLines: MajorGridLines(color: border, width: 1),
              majorTickLines: const MajorTickLines(size: 0),
              axisLine: const AxisLine(width: 0),
            ),
            series: <CartesianSeries<Map<String, dynamic>, String>>[
              ColumnSeries<Map<String, dynamic>, String>(
                dataSource: rows,
                xValueMapper: (r, _) => '${r['academic_year']}',
                yValueMapper: (r, _) => explorerNumber(r['score']),
                color: DefensysTokens.maroonOf(context),
                width: .4,
                animationDuration: 0,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(3),
                ),
                dataLabelMapper: (r, _) => r['score'] == null
                    ? 'Awaiting'
                    : '${explorerNumber(r['score'])!.toStringAsFixed(1)}%',
                dataLabelSettings: DataLabelSettings(
                  isVisible: true,
                  textStyle: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
                onPointTap: (details) {
                  if (details.pointIndex != null) {
                    onYear('${rows[details.pointIndex!]['academic_year']}');
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 48, right: 12),
          child: Row(
            children: rows
                .map(
                  (r) => Expanded(
                    child: ShadButton.ghost(
                      key: ValueKey('year-${r['academic_year']}'),
                      height: 82,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      onPressed: () => onYear('${r['academic_year']}'),
                      child: Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${r['academic_year']}',
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              '${r['assessed']} / ${r['eligible']} assessed${r['in_progress'] == true ? '\nIn progress' : ''}',
                              maxLines: 3,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

/// A ranked chart mark inside a real shadcn button. Keyboard users can activate
/// the same criterion or team as pointer users; null scores have no zero bar.
class CurriculumRankedBar extends StatelessWidget {
  const CurriculumRankedBar({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    required this.reference,
    required this.onPressed,
    this.color,
  });
  final String label, caption;
  final double? value;
  final double reference;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '$label, ${value == null ? 'awaiting assessment' : '${value!.toStringAsFixed(1)} percent'}, $caption',
    child: ShadButton.ghost(
      width: double.infinity,
      height: 98,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      onPressed: onPressed,
      child: Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.left,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  value == null ? 'Awaiting' : '${value!.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            SizedBox(
              height: 13,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    if (value != null)
                      SizedBox(
                        width:
                            constraints.maxWidth * value!.clamp(0, 100) / 100,
                        height: 11,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color:
                                color ??
                                CurriculumChartPalette.primary(context),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ReferenceLine(
                          reference / 100,
                          DefensysTokens.textSecondaryOf(
                            context,
                          ).withValues(alpha: .5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              caption,
              textAlign: TextAlign.left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: DefensysTokens.textSecondaryOf(context),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReferenceLine extends CustomPainter {
  _ReferenceLine(this.fraction, this.color);
  final double fraction;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final x = (size.width * fraction).clamp(0.0, size.width - 1).toDouble();
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 5) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, (y + 3).clamp(0.0, size.height).toDouble()),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ReferenceLine old) =>
      old.fraction != fraction || old.color != color;
}

class CurriculumPercentAxis extends StatelessWidget {
  const CurriculumPercentAxis({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    child: Column(
      children: [
        Divider(height: 1, color: DefensysTokens.borderOf(context)),
        const SizedBox(height: 7),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: ['0%', '50%', '100%']
              .map(
                (s) => Text(
                  s,
                  style: TextStyle(
                    fontSize: 11,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    ),
  );
}

Color curriculumCategoryColor(BuildContext context, String category) {
  if (category == 'Unclassified' || category == 'Unresolved domain') {
    return CurriculumChartPalette.neutral(context);
  }
  final index = category.codeUnits.fold<int>(0, (sum, code) => sum + code) % 2;
  return CurriculumChartPalette.slice(context, index);
}

/// Ranked categories remain readable even when only one category is available.
class CurriculumCategoryBars extends StatelessWidget {
  const CurriculumCategoryBars({
    super.key,
    required this.rows,
    required this.onCategory,
  });
  final List<Map<String, dynamic>> rows;
  final ValueChanged<String> onCategory;

  @override
  Widget build(BuildContext context) {
    final ranked = [...rows]
      ..sort(
        (a, b) => (explorerNumber(b['count']) ?? 0).compareTo(
          explorerNumber(a['count']) ?? 0,
        ),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in ranked)
          ShadButton.ghost(
            key: ValueKey('category-${r['category']}'),
            width: double.infinity,
            height: 84,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            mainAxisAlignment: MainAxisAlignment.start,
            onPressed: () => onCategory('${r['category']}'),
            child: Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${r['category']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${r['count']} · ${(explorerNumber(r['percentage']) ?? 0).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 10,
                    child: LayoutBuilder(
                      builder: (_, c) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width:
                              c.maxWidth *
                              (explorerNumber(r['percentage']) ?? 0).clamp(
                                0,
                                100,
                              ) /
                              100,
                          height: 10,
                          decoration: BoxDecoration(
                            color: curriculumCategoryColor(
                              context,
                              '${r['category']}',
                            ),
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
      ],
    );
  }
}

class CurriculumProjectPie extends StatelessWidget {
  const CurriculumProjectPie({
    super.key,
    required this.rows,
    required this.onCategory,
  });
  final List<Map<String, dynamic>> rows;
  final ValueChanged<String> onCategory;
  @override
  Widget build(BuildContext context) {
    final chart = SizedBox(
      height: 290,
      child: SfCircularChart(
        key: const ValueKey('project-category-pie'),
        tooltipBehavior: TooltipBehavior(
          enable: true,
          format: 'point.x: point.y projects',
        ),
        margin: const EdgeInsets.all(8),
        series: <CircularSeries<Map<String, dynamic>, String>>[
          PieSeries<Map<String, dynamic>, String>(
            dataSource: rows,
            xValueMapper: (r, _) => '${r['category']}',
            yValueMapper: (r, _) => explorerNumber(r['count']),
            pointColorMapper: (r, _) =>
                curriculumCategoryColor(context, '${r['category']}'),
            dataLabelMapper: (r, _) =>
                '${explorerNumber(r['percentage'])!.toStringAsFixed(0)}%',
            animationDuration: 0,
            dataLabelSettings: const DataLabelSettings(
              isVisible: true,
              labelPosition: ChartDataLabelPosition.outside,
              connectorLineSettings: ConnectorLineSettings(length: '12%'),
              textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
            onPointTap: (details) {
              if (details.pointIndex != null) {
                onCategory('${rows[details.pointIndex!]['category']}');
              }
            },
          ),
        ],
      ),
    );
    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows
          .map(
            (r) => ShadButton.ghost(
              key: ValueKey('category-${r['category']}'),
              width: double.infinity,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onPressed: () => onCategory('${r['category']}'),
              child: Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: curriculumCategoryColor(
                          context,
                          '${r['category']}',
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${r['category']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${r['count']} (${explorerNumber(r['percentage'])!.toStringAsFixed(1)}%)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 650
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [chart, legend],
            )
          : Row(
              children: [
                Expanded(child: chart),
                const SizedBox(width: 28),
                Expanded(child: legend),
              ],
            ),
    );
  }
}
