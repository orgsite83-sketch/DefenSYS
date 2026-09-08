import 'package:flutter/material.dart';
import '../../../../../theme/app_theme.dart';
import 'curriculum_radar_chart.dart';

/// Scannable card placed directly beside the Radar Polygon in Section 1.
/// Summarizes academic strengths, remediation alerts, faculty consensus, and bottleneck.
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

    // 2. Identify Lowest / Remediation Focus Criterion
    final lowestCriterion = scoredCriteria.isNotEmpty ? scoredCriteria.last : null;
    final bool hasRemediationNeed = lowestCriterion != null &&
        lowestCriterion.combinedScore != null &&
        lowestCriterion.combinedScore! < 75.0;

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
    Color alignmentColor = const Color(0xFF10B981);
    if (meanDiv != null) {
      if (meanDiv >= 15.0) {
        alignmentStatus = 'High Divergence (±${meanDiv.toStringAsFixed(1)}%)';
        alignmentColor = const Color(0xFFEF4444);
      } else if (meanDiv >= 8.0) {
        alignmentStatus = 'Moderate Variance (±${meanDiv.toStringAsFixed(1)}%)';
        alignmentColor = const Color(0xFFF59E0B);
      } else {
        alignmentStatus = 'Strong Consensus (±${meanDiv.toStringAsFixed(1)}%)';
        alignmentColor = const Color(0xFF10B981);
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
            color: Color(0x05000000),
            blurRadius: 6,
            offset: Offset(0, 2),
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
                  color: AppColors.maroon.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.insights_rounded, color: AppColors.maroon, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Academic Highlights',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Core competency highlights, faculty consensus, and remediation indicators.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 14),

          // 1. Top Strength
          _highlightItem(
            icon: Icons.star_rounded,
            iconColor: const Color(0xFFD97706),
            iconBg: const Color(0xFFFEF3C7),
            title: 'TOP COMPETENCY AREA',
            value: topCriterion != null
                ? '${topCriterion.name} (${(topCriterion.combinedScore ?? 0).toStringAsFixed(1)}%)'
                : 'Awaiting Evaluations',
            subtitle: topCriterion != null
                ? 'Highest average student rubric score in this cohort'
                : 'Evaluations will compute top performing criteria',
          ),
          const SizedBox(height: 12),

          // 2. Focus Area / Remediation
          _highlightItem(
            icon: hasRemediationNeed ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
            iconColor: hasRemediationNeed ? const Color(0xFFDC2626) : const Color(0xFF059669),
            iconBg: hasRemediationNeed ? const Color(0xFFFEE2E2) : const Color(0xFFECFDF5),
            title: hasRemediationNeed ? 'REMEDIATION FOCUS (<75%)' : 'INSTITUTIONAL BENCHMARK',
            value: lowestCriterion != null
                ? '${lowestCriterion.name} (${(lowestCriterion.combinedScore ?? 0).toStringAsFixed(1)}%)'
                : 'All Criteria Above Target',
            subtitle: mappedCourse.isNotEmpty
                ? 'Linked prerequisite course: $mappedCourse'
                : (lowestCriterion != null && !hasRemediationNeed
                    ? 'All evaluated criteria exceed 75% passing target'
                    : 'Target benchmark is 75.0%'),
          ),
          const SizedBox(height: 12),

          // 3. Faculty Evaluator Alignment
          _highlightItem(
            icon: Icons.balance_rounded,
            iconColor: alignmentColor,
            iconBg: alignmentColor.withValues(alpha: 0.12),
            title: 'FACULTY EVALUATOR CONSENSUS',
            value: alignmentStatus,
            subtitle: 'Average difference between panelist and project adviser scores',
          ),
          const SizedBox(height: 12),

          // 4. Pipeline Bottleneck
          _highlightItem(
            icon: Icons.alt_route_rounded,
            iconColor: const Color(0xFF6366F1),
            iconBg: const Color(0xFFEEF2FF),
            title: 'PIPELINE WORKLOAD BOTTLENECK',
            value: bottleneckStage != 'None' ? bottleneckStage : 'Balanced Flow Across Stages',
            subtitle: bottleneckStage != 'None'
                ? 'Defense stage with highest redefense or revision volume'
                : 'No excessive re-defense backlog detected',
          ),
          const SizedBox(height: 18),

          // Drill-down button
          OutlinedButton.icon(
            onPressed: onOpenMatrixDialog,
            icon: const Icon(Icons.table_chart_outlined, size: 16),
            label: const Text('View Granular Rubric Matrix'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.maroon,
              side: const BorderSide(color: AppColors.maroon, width: 1.2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    required String value,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconBg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
