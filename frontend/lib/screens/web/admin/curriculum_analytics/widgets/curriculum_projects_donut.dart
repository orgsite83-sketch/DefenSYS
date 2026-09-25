import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../../../theme/defensys_tokens.dart';

class _DomainChartData {
  final String domain;
  final int count;
  final double percentage;
  final Color color;

  _DomainChartData(this.domain, this.count, this.percentage, this.color);
}

/// Renders Section 2: Project Domains Donut Chart paired with Technology Frameworks
/// and the Tech Monoculture Index with modern shadcn styling.
class CurriculumProjectsDonut extends StatelessWidget {
  final List<Map<String, dynamic>> domainDistribution;
  final List<Map<String, dynamic>> techDistribution;
  final int totalProjects;

  const CurriculumProjectsDonut({
    super.key,
    required this.domainDistribution,
    required this.techDistribution,
    required this.totalProjects,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 920;

        final donutCard = _buildDonutCard(context);
        final techCard = _buildTechStackCard(context);

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: donutCard),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: techCard),
            ],
          );
        } else {
          return Column(
            children: [
              donutCard,
              const SizedBox(height: 16),
              techCard,
            ],
          );
        }
      },
    );
  }

  Widget _buildDonutCard(BuildContext context) {
    final isDark = DefensysTokens.isDark(context);
    final chartData = <_DomainChartData>[];
    for (final item in domainDistribution) {
      final domain = item['domain']?.toString() ?? 'General Software';
      final count = int.tryParse(item['count']?.toString() ?? '0') ?? 0;
      final pct = double.tryParse(item['percentage']?.toString() ?? '0') ?? 0.0;
      final hexColor = item['color']?.toString() ?? '#6366F1';
      final color = _parseColor(hexColor);
      chartData.add(_DomainChartData(domain, count, pct, color));
    }

    final bool hasData = chartData.isNotEmpty && totalProjects > 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0x20000000) : const Color(0x04000000),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.20 : 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.pie_chart_rounded, color: Color(0xFF6366F1), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project Domain Specialization',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: DefensysTokens.textPrimaryOf(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Student deliverables classified into computing specialization domains',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: DefensysTokens.borderOf(context)),
          const SizedBox(height: 14),

          if (!hasData)
            Container(
              height: 260,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open_rounded, size: 38, color: DefensysTokens.textSecondaryOf(context).withValues(alpha: 0.5)),
                  const SizedBox(height: 10),
                  Text(
                    'No Deliverable Submissions Recorded',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: DefensysTokens.textPrimaryOf(context)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Deliverables submitted by student teams will automatically classify into domains.',
                    style: TextStyle(fontSize: 11.5, color: DefensysTokens.textSecondaryOf(context)),
                  ),
                ],
              ),
            )
          else ...[
            SizedBox(
              height: 240,
              child: SfCircularChart(
                margin: EdgeInsets.zero,
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  format: 'point.x : point.y projects (point.percentage)',
                ),
                annotations: <CircularChartAnnotation>[
                  CircularChartAnnotation(
                    widget: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$totalProjects',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: DefensysTokens.textPrimaryOf(context),
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'PROJECTS',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                series: <DoughnutSeries<_DomainChartData, String>>[
                  DoughnutSeries<_DomainChartData, String>(
                    dataSource: chartData,
                    xValueMapper: (_DomainChartData d, _) => d.domain,
                    yValueMapper: (_DomainChartData d, _) => d.count,
                    pointColorMapper: (_DomainChartData d, _) => d.color,
                    innerRadius: '68%',
                    radius: '95%',
                    enableTooltip: true,
                    strokeColor: DefensysTokens.surfaceOf(context),
                    strokeWidth: 2.0,
                    animationDuration: 700,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Clean Custom Legend Grid
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: chartData.map((d) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: d.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      d.domain,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${d.percentage.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: DefensysTokens.textSecondaryOf(context),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTechStackCard(BuildContext context) {
    final isDark = DefensysTokens.isDark(context);
    final items = techDistribution.take(6).toList();
    final bool hasData = items.isNotEmpty;

    // Calculate top tech monoculture percentage
    final topItem = items.isNotEmpty ? items.first : null;
    final topPct = topItem != null ? (double.tryParse(topItem['percentage']?.toString() ?? '0') ?? 0.0) : 0.0;
    final bool isMonocultureAlert = topPct >= 50.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0x20000000) : const Color(0x04000000),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF0EA5E9).withValues(alpha: isDark ? 0.20 : 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.code_rounded, color: Color(0xFF0EA5E9), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Top Technology Stacks',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: DefensysTokens.textPrimaryOf(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Frameworks and languages detected across deliverable repositories',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: DefensysTokens.borderOf(context)),
          const SizedBox(height: 14),

          if (!hasData)
            Container(
              height: 260,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.devices_rounded, size: 38, color: DefensysTokens.textSecondaryOf(context).withValues(alpha: 0.5)),
                  const SizedBox(height: 10),
                  Text(
                    'No Technology Data Recorded',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: DefensysTokens.textPrimaryOf(context)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Deliverables submitted by student teams will extract software frameworks.',
                    style: TextStyle(fontSize: 11.5, color: DefensysTokens.textSecondaryOf(context)),
                  ),
                ],
              ),
            )
          else ...[
            ...items.map((item) {
              final tech = item['tech']?.toString() ?? 'Framework';
              final count = int.tryParse(item['count']?.toString() ?? '0') ?? 0;
              final pct = double.tryParse(item['percentage']?.toString() ?? '0') ?? 0.0;
              final color = _parseColor(item['color']?.toString() ?? '#0EA5E9');

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              tech,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: DefensysTokens.textPrimaryOf(context),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '$count projects (${pct.toStringAsFixed(0)}%)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: DefensysTokens.textSecondaryOf(context),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (pct / 100.0).clamp(0.0, 1.0),
                        backgroundColor: DefensysTokens.surfaceHigherOf(context),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 6.5,
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 6),
            // Tech Monoculture Index Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMonocultureAlert
                    ? (isDark ? const Color(0x20DC2626) : const Color(0xFFFEF2F2))
                    : (isDark ? const Color(0x2016A34A) : const Color(0xFFF0FDF4)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isMonocultureAlert
                      ? (isDark ? const Color(0x40DC2626) : const Color(0xFFFECACA))
                      : (isDark ? const Color(0x4016A34A) : const Color(0xFFBBF7D0)),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isMonocultureAlert ? Icons.info_outline_rounded : Icons.check_circle_outline_rounded,
                    size: 18,
                    color: isMonocultureAlert ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMonocultureAlert ? 'Stack Monoculture Alert' : 'Healthy Stack Diversification',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isMonocultureAlert
                                ? (isDark ? const Color(0xFFF87171) : const Color(0xFFB91C1C))
                                : (isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D)),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          isMonocultureAlert
                              ? 'Top technology (${topItem?['tech'] ?? 'Stack'}) commands ${topPct.toStringAsFixed(0)}% of deliverables. Introduce emerging tech elective tracks.'
                              : 'No single software framework exceeds 50% share. Good cohort diversification across modern technologies.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isMonocultureAlert
                                ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B))
                                : (isDark ? const Color(0xFF86EFAC) : const Color(0xFF166534)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _parseColor(String hexString) {
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return const Color(0xFF6366F1);
    }
  }
}
