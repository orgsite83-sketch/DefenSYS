import 'package:flutter/material.dart';
import '../../../../../theme/defensys_tokens.dart';

/// Executive KPI stat cards matching User Management's clean metric cards.
/// Provides purposeful, uncluttered metrics: Defense Pass Rate, Competency Index (CPI),
/// Cohort Hearings, and Institutional Benchmark.
class CurriculumCircularKpis extends StatelessWidget {
  final Map<String, dynamic> kpiSummary;
  final Map<String, dynamic> defenseFunnel;
  final bool hasEvaluations;

  const CurriculumCircularKpis({
    super.key,
    required this.kpiSummary,
    required this.defenseFunnel,
    required this.hasEvaluations,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Overall Pass Rate
    final passRateRaw =
        defenseFunnel['overall_pass_rate'] ?? defenseFunnel['pass_rate'];
    final double? passRate = passRateRaw != null
        ? (double.tryParse(passRateRaw.toString()) ?? 0.0)
        : null;

    // 2. Competency Proficiency Index (CPI)
    final cpiRaw = kpiSummary['competency_index'];
    final double? cpi =
        cpiRaw != null ? (double.tryParse(cpiRaw.toString()) ?? 0.0) : null;

    // 3. Evaluated Teams / Hearings
    final totalEvalsRaw =
        kpiSummary['active_cohort_projects'] ?? kpiSummary['total_projects'];
    final int totalEvals = totalEvalsRaw != null
        ? (int.tryParse(totalEvalsRaw.toString()) ?? 0)
        : 0;
    final int stagesCount =
        int.tryParse(kpiSummary['stages_count']?.toString() ?? '0') ?? 0;

    final bool isPassEvaluated = passRate != null && hasEvaluations;
    final bool hasCpi = cpi != null && hasEvaluations && cpi > 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 800;

        final card1 = _buildMetricCard(
          context: context,
          title: 'Defense Pass Rate',
          value: isPassEvaluated ? '${passRate.toStringAsFixed(1)}%' : 'Pending',
          subtitle: hasEvaluations
              ? (passRate != null && passRate >= 75.0 ? 'Exceeds 75% target' : 'Remediation needed')
              : 'Awaiting defense hearings',
          icon: Icons.verified_outlined,
          iconColor: DefensysTokens.maroonOf(context),
          iconBg: const Color(0xFFFDF2F2),
        );

        final card2 = _buildMetricCard(
          context: context,
          title: 'Competency Index (CPI)',
          value: hasCpi ? '${cpi.toStringAsFixed(1)}%' : 'No Grades',
          subtitle: hasCpi ? 'Cohort score average' : 'Awaiting rubric scoring',
          icon: Icons.insights_rounded,
          iconColor: const Color(0xFF059669),
          iconBg: const Color(0xFFECFDF5),
        );

        final card3 = _buildMetricCard(
          context: context,
          title: 'Cohort Hearings',
          value: hasEvaluations ? '$totalEvals Evals' : '0 Evals',
          subtitle: stagesCount > 0
              ? 'Across $stagesCount defense stages'
              : 'No evaluations recorded',
          icon: Icons.how_to_reg_outlined,
          iconColor: const Color(0xFF2563EB),
          iconBg: const Color(0xFFEFF6FF),
        );

        final card4 = _buildMetricCard(
          context: context,
          title: 'Target Benchmark',
          value: '75.0%',
          subtitle: 'Institutional threshold',
          icon: Icons.flag_outlined,
          iconColor: const Color(0xFFD97706),
          iconBg: const Color(0xFFFEF3C7),
        );

        if (isNarrow) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: card1),
                  const SizedBox(width: 14),
                  Expanded(child: card2),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: card3),
                  const SizedBox(width: 14),
                  Expanded(child: card4),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: card1),
            const SizedBox(width: 14),
            Expanded(child: card2),
            const SizedBox(width: 14),
            Expanded(child: card3),
            const SizedBox(width: 14),
            Expanded(child: card4),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required BuildContext context,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
  }) {
    final isDark = DefensysTokens.isDark(context);
    final cardBg = DefensysTokens.panelOf(context);
    final borderColor = DefensysTokens.borderOf(context);
    final textTitle = DefensysTokens.textSecondaryOf(context);
    final textValue = DefensysTokens.textPrimaryOf(context);
    final textSub = DefensysTokens.textSecondaryOf(context);
    final actualIconBg = isDark ? iconColor.withValues(alpha: 0.18) : iconBg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: actualIconBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: textTitle,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: textValue,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: textSub,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
