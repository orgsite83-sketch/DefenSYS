import 'package:flutter/material.dart';
import '../../../../../theme/defensys_tokens.dart';
import 'curriculum_radar_chart.dart';

/// Scannable card placed beside the Cohort Stages Benchmark Chart.
/// Summarizes academic strengths, remediation alerts, faculty consensus, and bottlenecks
/// using clean shadcn-style divided rows and semantic status badges.
class CurriculumAcademicHighlights extends StatelessWidget {
  final List<RadarCriterionPoint> criteria;
  final Map<String, dynamic> kpiSummary;
  final Map<String, dynamic> defenseFunnel;
  final List<Map<String, dynamic>> prescriptions;
  final VoidCallback onOpenMatrixDialog;

  const CurriculumAcademicHighlights({
    super.key,
    required this.criteria,
    required this.kpiSummary,
    required this.defenseFunnel,
    required this.prescriptions,
    required this.onOpenMatrixDialog,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = DefensysTokens.isDark(context);

    // 1. Identify Top Strength Criterion (highest score)
    final scoredCriteria = criteria
        .where((c) => c.combinedScore != null && c.combinedScore! > 0)
        .toList()
      ..sort((a, b) => (b.combinedScore ?? 0).compareTo(a.combinedScore ?? 0));

    final topCriterion = scoredCriteria.isNotEmpty ? scoredCriteria.first : null;
    final topScore = topCriterion?.combinedScore ?? 0.0;
    final topDelta = topScore - (topCriterion?.benchmark ?? 75.0);

    // 2. Identify Lowest / Remediation Focus Criterion
    final lowestCriterion = scoredCriteria.isNotEmpty ? scoredCriteria.last : null;
    final lowestScore = lowestCriterion?.combinedScore ?? 0.0;
    final bool hasRemediationNeed = lowestCriterion != null &&
        lowestScore < (lowestCriterion.benchmark);
    final lowestDelta = lowestScore - (lowestCriterion?.benchmark ?? 75.0);

    // Find mapped prerequisite course from prescriptions if available
    String mappedCourse = '';
    if (lowestCriterion != null && prescriptions.isNotEmpty) {
      final matchingPrescription = prescriptions.firstWhere(
        (p) =>
            p['title']?.toString().toLowerCase().contains(lowestCriterion.name.toLowerCase()) == true ||
            p['description']?.toString().toLowerCase().contains(lowestCriterion.name.toLowerCase()) == true,
        orElse: () => prescriptions.first,
      );
      mappedCourse = matchingPrescription['course']?.toString() ??
          (matchingPrescription['prerequisite_course']?.toString() ?? '');
    }
    if (mappedCourse.isEmpty && hasRemediationNeed) {
      mappedCourse = 'Foundational Curriculum Remediation';
    }

    // 3. Evaluator Discrepancy / Alignment
    final meanDivRaw = kpiSummary['mean_evaluator_divergence'];
    final double? meanDiv = meanDivRaw != null ? double.tryParse(meanDivRaw.toString()) : null;
    String alignmentStatus = 'Evaluating';
    String alignmentBadge = 'Evaluating';
    Color alignmentColor = const Color(0xFF059669);
    Color alignmentBg = isDark ? const Color(0x20059669) : const Color(0xFFECFDF5);

    if (meanDiv != null) {
      if (meanDiv >= 15.0) {
        alignmentStatus = 'High Divergence (±${meanDiv.toStringAsFixed(1)}%)';
        alignmentBadge = 'High Variance';
        alignmentColor = const Color(0xFFDC2626);
        alignmentBg = isDark ? const Color(0x20DC2626) : const Color(0xFFFEF2F2);
      } else if (meanDiv >= 8.0) {
        alignmentStatus = 'Moderate Variance (±${meanDiv.toStringAsFixed(1)}%)';
        alignmentBadge = 'Moderate';
        alignmentColor = const Color(0xFFD97706);
        alignmentBg = isDark ? const Color(0x20D97706) : const Color(0xFFFFFBEB);
      } else {
        alignmentStatus = 'Strong Consensus (±${meanDiv.toStringAsFixed(1)}%)';
        alignmentBadge = 'Aligned';
        alignmentColor = const Color(0xFF059669);
        alignmentBg = isDark ? const Color(0x20059669) : const Color(0xFFECFDF5);
      }
    }

    // 4. Bottleneck Stage
    final bottleneckStage = defenseFunnel['bottleneck_stage']?.toString() ??
        (kpiSummary['bottleneck_stage']?.toString() ?? 'None');

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
          // Header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: DefensysTokens.maroonOf(context).withValues(alpha: isDark ? 0.20 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.insights_rounded,
                  color: DefensysTokens.maroonOf(context),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Academic Highlights',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: DefensysTokens.textPrimaryOf(context),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Rubric performance and evaluator alignment',
                    style: TextStyle(
                      fontSize: 11,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: DefensysTokens.borderOf(context)),
          const SizedBox(height: 6),

          // 1. Top Strength
          _highlightRow(
            context: context,
            icon: Icons.workspace_premium_outlined,
            iconColor: const Color(0xFF059669),
            iconBg: isDark ? const Color(0x20059669) : const Color(0xFFECFDF5),
            title: 'Top Competency Area',
            badgeText: topCriterion != null
                ? '+${topDelta.toStringAsFixed(1)}%'
                : 'Pending',
            badgeColor: const Color(0xFF059669),
            badgeBg: isDark ? const Color(0x20059669) : const Color(0xFFECFDF5),
            value: topCriterion != null
                ? '${topCriterion.name.replaceAll('Visuals & Aida', 'Presentation & Visual Aids')} (${topScore.toStringAsFixed(1)}%)'
                : 'Awaiting Evaluations',
            tooltip: topCriterion != null
                ? 'Highest average student rubric score (+${topDelta.toStringAsFixed(1)}% vs target)'
                : 'Evaluations will compute top performing criteria',
          ),
          Divider(height: 12, color: DefensysTokens.borderOf(context).withValues(alpha: 0.5)),

          // 2. Focus Area / Remediation
          _highlightRow(
            context: context,
            icon: hasRemediationNeed
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            iconColor: hasRemediationNeed
                ? const Color(0xFFDC2626)
                : const Color(0xFF059669),
            iconBg: hasRemediationNeed
                ? (isDark ? const Color(0x20DC2626) : const Color(0xFFFEF2F2))
                : (isDark ? const Color(0x20059669) : const Color(0xFFECFDF5)),
            title: hasRemediationNeed ? 'Remediation Focus' : 'Institutional Benchmark',
            badgeText: lowestCriterion != null
                ? (hasRemediationNeed
                    ? '${lowestDelta.toStringAsFixed(1)}%'
                    : 'Target Met')
                : 'Pending',
            badgeColor: hasRemediationNeed
                ? const Color(0xFFDC2626)
                : const Color(0xFF059669),
            badgeBg: hasRemediationNeed
                ? (isDark ? const Color(0x20DC2626) : const Color(0xFFFEF2F2))
                : (isDark ? const Color(0x20059669) : const Color(0xFFECFDF5)),
            value: lowestCriterion != null
                ? '${lowestCriterion.name.replaceAll('Visuals & Aida', 'Presentation & Visual Aids')} (${lowestScore.toStringAsFixed(1)}%)'
                : 'All Criteria Above Target',
            tooltip: mappedCourse.isNotEmpty
                ? 'Linked prerequisite course: $mappedCourse'
                : 'Institutional benchmark standard is 75.0%',
          ),
          Divider(height: 12, color: DefensysTokens.borderOf(context).withValues(alpha: 0.5)),

          // 3. Faculty Evaluator Alignment
          _highlightRow(
            context: context,
            icon: Icons.balance_outlined,
            iconColor: alignmentColor,
            iconBg: alignmentBg,
            title: 'Evaluator Consensus',
            badgeText: alignmentBadge,
            badgeColor: alignmentColor,
            badgeBg: alignmentBg,
            value: alignmentStatus,
            tooltip: 'Average score difference between panelist and adviser',
          ),
          Divider(height: 12, color: DefensysTokens.borderOf(context).withValues(alpha: 0.5)),

          // 4. Pipeline Bottleneck
          _highlightRow(
            context: context,
            icon: Icons.alt_route_rounded,
            iconColor: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF475569),
            iconBg: DefensysTokens.surfaceHigherOf(context),
            title: 'Pipeline Bottleneck',
            badgeText: bottleneckStage != 'None' ? 'Review Needed' : 'Balanced',
            badgeColor: bottleneckStage != 'None'
                ? const Color(0xFFD97706)
                : DefensysTokens.textSecondaryOf(context),
            badgeBg: bottleneckStage != 'None'
                ? (isDark ? const Color(0x20D97706) : const Color(0xFFFFFBEB))
                : DefensysTokens.surfaceHigherOf(context),
            value: bottleneckStage != 'None'
                ? bottleneckStage
                : 'Balanced Flow Across Stages',
            tooltip: bottleneckStage != 'None'
                ? 'Defense stage with highest redefense or revision volume'
                : 'No excessive re-defense backlog detected across stages',
          ),
          const SizedBox(height: 14),

          // Docked Full-Width Action Button (Shadcn Outline Style)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onOpenMatrixDialog,
              style: OutlinedButton.styleFrom(
                foregroundColor: DefensysTokens.textPrimaryOf(context),
                backgroundColor: DefensysTokens.surfaceHigherOf(context),
                side: BorderSide(color: DefensysTokens.borderOf(context)),
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.table_chart_outlined,
                      size: 15, color: DefensysTokens.maroonOf(context)),
                  const SizedBox(width: 8),
                  Text(
                    'View Granular Rubric Matrix',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded,
                      size: 14, color: DefensysTokens.textSecondaryOf(context)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _highlightRow({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String badgeText,
    required Color badgeColor,
    required Color badgeBg,
    required String value,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: badgeColor.withValues(alpha: 0.25),
                  width: 0.8,
                ),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: badgeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
