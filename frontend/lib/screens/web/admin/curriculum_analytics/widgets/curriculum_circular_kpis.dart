import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../../theme/app_theme.dart';

/// Renders the 3 prominent circular KPI metric rings inspired by post-match stats.
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
    final passRateRaw = defenseFunnel['overall_pass_rate'] ?? defenseFunnel['pass_rate'];
    final double? passRate = passRateRaw != null ? (double.tryParse(passRateRaw.toString()) ?? 0.0) : null;

    // 2. Competency Proficiency Index (CPI)
    final cpiRaw = kpiSummary['competency_index'];
    final double? cpi = cpiRaw != null ? (double.tryParse(cpiRaw.toString()) ?? 0.0) : null;

    // 3. Evaluated Teams / Hearings
    final totalEvalsRaw = kpiSummary['active_cohort_projects'] ?? kpiSummary['total_projects'];
    final int totalEvals = totalEvalsRaw != null ? (int.tryParse(totalEvalsRaw.toString()) ?? 0) : 0;
    final int stagesCount = int.tryParse(kpiSummary['stages_count']?.toString() ?? '0') ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;

        final badge1 = _CircularKpiBadge(
          title: 'DEFENSE PASS RATE',
          mainValue: passRate != null && hasEvaluations ? '${passRate.toStringAsFixed(1)}%' : 'Pending',
          subtext: hasEvaluations ? 'Target: ≥ 75.0%' : 'Awaiting defense hearings',
          progress: passRate != null && hasEvaluations ? (passRate / 100.0).clamp(0.0, 1.0) : 0.0,
          ringColor: (passRate != null && passRate >= 75.0)
              ? const Color(0xFF10B981) // Emerald
              : const Color(0xFFF59E0B), // Amber
          statusLabel: passRate != null && hasEvaluations
              ? (passRate >= 75.0 ? 'Benchmark Met' : 'Remediation Alert')
              : 'Unscheduled',
          statusColor: passRate != null && hasEvaluations
              ? (passRate >= 75.0 ? const Color(0xFF047857) : const Color(0xFFB45309))
              : const Color(0xFF64748B),
          statusBg: passRate != null && hasEvaluations
              ? (passRate >= 75.0 ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB))
              : const Color(0xFFF1F5F9),
        );

        final badge2 = _CircularKpiBadge(
          title: 'COMPETENCY INDEX (CPI)',
          mainValue: cpi != null && hasEvaluations && cpi > 0 ? cpi.toStringAsFixed(1) : 'No Grades',
          subtext: hasEvaluations && cpi != null && cpi > 0
              ? 'Average student rubric score'
              : 'Awaiting rubric scoring',
          progress: cpi != null && hasEvaluations && cpi > 0 ? (cpi / 100.0).clamp(0.0, 1.0) : 0.0,
          ringColor: (cpi != null && cpi >= 75.0)
              ? const Color(0xFF0EA5E9) // Sky blue
              : const Color(0xFFEF4444), // Crimson
          statusLabel: cpi != null && hasEvaluations && cpi > 0
              ? (cpi >= 80.0 ? 'High Proficiency' : (cpi >= 75.0 ? 'Passing' : 'Needs Focus (<75)'))
              : 'Pending',
          statusColor: cpi != null && hasEvaluations && cpi > 0
              ? (cpi >= 75.0 ? const Color(0xFF0369A1) : const Color(0xFFB91C1C))
              : const Color(0xFF64748B),
          statusBg: cpi != null && hasEvaluations && cpi > 0
              ? (cpi >= 75.0 ? const Color(0xFFE0F2FE) : const Color(0xFFFEF2F2))
              : const Color(0xFFF1F5F9),
        );

        final badge3 = _CircularKpiBadge(
          title: 'COHORT HEARINGS',
          mainValue: totalEvals > 0 ? '$totalEvals Evals' : '0 Evals',
          subtext: stagesCount > 0 ? 'Across $stagesCount defense stages' : 'Deliverables uploaded',
          progress: totalEvals > 0 ? 1.0 : 0.0,
          ringColor: AppColors.maroon,
          statusLabel: totalEvals > 0 ? 'Active Cohort' : 'No Submissions',
          statusColor: totalEvals > 0 ? AppColors.maroon : const Color(0xFF64748B),
          statusBg: totalEvals > 0 ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9),
        );

        if (isMobile) {
          return Column(
            children: [
              badge1,
              const SizedBox(height: 12),
              badge2,
              const SizedBox(height: 12),
              badge3,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: badge1),
            const SizedBox(width: 14),
            Expanded(child: badge2),
            const SizedBox(width: 14),
            Expanded(child: badge3),
          ],
        );
      },
    );
  }
}

class _CircularKpiBadge extends StatelessWidget {
  final String title;
  final String mainValue;
  final String subtext;
  final double progress;
  final Color ringColor;
  final String statusLabel;
  final Color statusColor;
  final Color statusBg;

  const _CircularKpiBadge({
    required this.title,
    required this.mainValue,
    required this.subtext,
    required this.progress,
    required this.ringColor,
    required this.statusLabel,
    required this.statusColor,
    required this.statusBg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Circular Progress Ring
          SizedBox(
            width: 72,
            height: 72,
            child: CustomPaint(
              painter: _CircularRingPainter(
                progress: progress,
                ringColor: ringColor,
                trackColor: const Color(0xFFF1F5F9),
              ),
              child: Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ringColor.withValues(alpha: 0.08),
                  ),
                  child: Icon(
                    _iconForTitle(title),
                    color: ringColor,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Metric details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  mainValue,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        subtext,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForTitle(String title) {
    if (title.contains('PASS')) return Icons.verified_rounded;
    if (title.contains('INDEX') || title.contains('CPI')) return Icons.school_rounded;
    return Icons.groups_rounded;
  }
}

class _CircularRingPainter extends CustomPainter {
  final double progress;
  final Color ringColor;
  final Color trackColor;

  const _CircularRingPainter({
    required this.progress,
    required this.ringColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 6.0;
    final radius = (size.width - strokeWidth) / 2;

    // Background track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      const startAngle = -math.pi / 2;
      final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CircularRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.trackColor != trackColor;
  }
}
