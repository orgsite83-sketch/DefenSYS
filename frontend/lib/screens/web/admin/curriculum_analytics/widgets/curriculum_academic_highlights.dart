import 'package:flutter/material.dart';
import '../../../../../theme/app_theme.dart';
import 'curriculum_radar_chart.dart';

/// Scannable card placed directly beside the Radar Polygon / Competency Map.
/// Summarizes academic strengths, remediation alerts, faculty consensus, and bottlenecks.
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
    Color alignmentBg = const Color(0xFFECFDF5);

    if (meanDiv != null) {
      if (meanDiv >= 15.0) {
        alignmentStatus = 'High Divergence (±${meanDiv.toStringAsFixed(1)}%)';
        alignmentBadge = 'High Variance';
        alignmentColor = const Color(0xFFDC2626);
        alignmentBg = const Color(0xFFFEF2F2);
      } else if (meanDiv >= 8.0) {
        alignmentStatus = 'Moderate Variance (±${meanDiv.toStringAsFixed(1)}%)';
        alignmentBadge = 'Moderate';
        alignmentColor = const Color(0xFFD97706);
        alignmentBg = const Color(0xFFFFFBEB);
      } else {
        alignmentStatus = 'Strong Consensus (±${meanDiv.toStringAsFixed(1)}%)';
        alignmentBadge = 'Aligned';
        alignmentColor = const Color(0xFF059669);
        alignmentBg = const Color(0xFFECFDF5);
      }
    }

    // 4. Bottleneck Stage
    final bottleneckStage = defenseFunnel['bottleneck_stage']?.toString() ??
        (kpiSummary['bottleneck_stage']?.toString() ?? 'None');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 6,
            offset: Offset(0, 2),
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
                  color: AppColors.maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: AppColors.maroon,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Academic Highlights',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Core competency achievements and faculty consensus',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 16),

          // 1. Top Strength
          _highlightItem(
            icon: Icons.workspace_premium_outlined,
            iconColor: const Color(0xFF059669),
            iconBg: const Color(0xFFECFDF5),
            title: 'TOP COMPETENCY AREA',
            badgeText: topCriterion != null
                ? '+${topDelta.toStringAsFixed(1)}% vs target'
                : 'Pending',
            badgeColor: const Color(0xFF059669),
            badgeBg: const Color(0xFFECFDF5),
            value: topCriterion != null
                ? '${topCriterion.name.replaceAll('Visuals & Aida', 'Presentation & Visual Aids')} (${topScore.toStringAsFixed(1)}%)'
                : 'Awaiting Evaluations',
            subtitle: topCriterion != null
                ? 'Highest average student rubric score in this cohort'
                : 'Evaluations will compute top performing criteria',
          ),
          const SizedBox(height: 14),

          // 2. Focus Area / Remediation
          _highlightItem(
            icon: hasRemediationNeed
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            iconColor: hasRemediationNeed
                ? const Color(0xFFDC2626)
                : const Color(0xFF059669),
            iconBg: hasRemediationNeed
                ? const Color(0xFFFEF2F2)
                : const Color(0xFFECFDF5),
            title: hasRemediationNeed
                ? 'REMEDIATION FOCUS (<75%)'
                : 'INSTITUTIONAL BENCHMARK',
            badgeText: lowestCriterion != null
                ? (hasRemediationNeed
                    ? '${lowestDelta.toStringAsFixed(1)}% deficit'
                    : 'Target Met')
                : 'Pending',
            badgeColor: hasRemediationNeed
                ? const Color(0xFFDC2626)
                : const Color(0xFF059669),
            badgeBg: hasRemediationNeed
                ? const Color(0xFFFEF2F2)
                : const Color(0xFFECFDF5),
            value: lowestCriterion != null
                ? '${lowestCriterion.name.replaceAll('Visuals & Aida', 'Presentation & Visual Aids')} (${lowestScore.toStringAsFixed(1)}%)'
                : 'All Criteria Above Target',
            subtitle: mappedCourse.isNotEmpty
                ? 'Linked prerequisite course: $mappedCourse'
                : (lowestCriterion != null && !hasRemediationNeed
                    ? 'All evaluated criteria exceed 75% passing target'
                    : 'Target benchmark is 75.0%'),
          ),
          const SizedBox(height: 14),

          // 3. Faculty Evaluator Alignment
          _highlightItem(
            icon: Icons.balance_outlined,
            iconColor: alignmentColor,
            iconBg: alignmentBg,
            title: 'FACULTY EVALUATOR CONSENSUS',
            badgeText: alignmentBadge,
            badgeColor: alignmentColor,
            badgeBg: alignmentBg,
            value: alignmentStatus,
            subtitle:
                'Average difference between panelist and project adviser scores',
          ),
          const SizedBox(height: 14),

          // 4. Pipeline Bottleneck
          _highlightItem(
            icon: Icons.alt_route_rounded,
            iconColor: const Color(0xFF475569),
            iconBg: const Color(0xFFF1F5F9),
            title: 'PIPELINE WORKLOAD BOTTLENECK',
            badgeText: bottleneckStage != 'None' ? 'Review Needed' : 'Balanced',
            badgeColor: bottleneckStage != 'None'
                ? const Color(0xFFD97706)
                : const Color(0xFF475569),
            badgeBg: bottleneckStage != 'None'
                ? const Color(0xFFFFFBEB)
                : const Color(0xFFF1F5F9),
            value: bottleneckStage != 'None'
                ? bottleneckStage
                : 'Balanced Flow Across Stages',
            subtitle: bottleneckStage != 'None'
                ? 'Defense stage with highest redefense or revision volume'
                : 'No excessive re-defense backlog detected across stages',
          ),
          const SizedBox(height: 20),

          // Docked Full-Width Action Button with Arrow Affordance
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onOpenMatrixDialog,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.maroon,
                side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
                backgroundColor: const Color(0xFFF8FAFC),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.table_chart_outlined, size: 15),
                  SizedBox(width: 8),
                  Text(
                    'View Granular Rubric Matrix',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _highlightItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String badgeText,
    required Color badgeColor,
    required Color badgeBg,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: badgeColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
