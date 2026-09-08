import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../../theme/app_theme.dart';

/// Data point representing a criterion on the Radar Chart.
class RadarCriterionPoint {
  final String name;
  final double? panelScore;
  final double? adviserScore;
  final double? peerScore;
  final double? combinedScore;
  final double benchmark;
  final String? divergenceStatus;
  final double? divergence;

  const RadarCriterionPoint({
    required this.name,
    this.panelScore,
    this.adviserScore,
    this.peerScore,
    this.combinedScore,
    this.benchmark = 75.0,
    this.divergenceStatus,
    this.divergence,
  });

  factory RadarCriterionPoint.fromMap(Map<String, dynamic> map) {
    final name = map['name']?.toString() ?? 'Criterion';
    final evalBreakdown = map['evaluator_breakdown'] as Map<String, dynamic>?;

    double? parseScore(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString());
    }

    final panelVal = evalBreakdown != null && evalBreakdown['panel'] != null
        ? parseScore(evalBreakdown['panel']['score'])
        : null;
    final adviserVal = evalBreakdown != null && evalBreakdown['adviser'] != null
        ? parseScore(evalBreakdown['adviser']['score'])
        : null;
    final peerVal = evalBreakdown != null && evalBreakdown['peer'] != null
        ? parseScore(evalBreakdown['peer']['score'])
        : null;
    final combinedVal = parseScore(map['average_score'] ?? map['score']);

    final divVal = parseScore(map['divergence']);
    final divStatus = map['divergence_status']?.toString();

    return RadarCriterionPoint(
      name: name,
      panelScore: panelVal,
      adviserScore: adviserVal,
      peerScore: peerVal,
      combinedScore: combinedVal,
      benchmark: parseScore(map['benchmark']) ?? 75.0,
      divergenceStatus: divStatus,
      divergence: divVal,
    );
  }
}

/// Interactive Multi-Layered Radar Chart displaying dynamic rubric criteria
/// with toggleable layers for Panelists, Advisers, Peers, and the 75% Target benchmark.
class CurriculumRadarChart extends StatefulWidget {
  final List<RadarCriterionPoint> criteria;
  final String stageTitle;
  final bool isLoading;

  const CurriculumRadarChart({
    super.key,
    required this.criteria,
    required this.stageTitle,
    this.isLoading = false,
  });

  @override
  State<CurriculumRadarChart> createState() => _CurriculumRadarChartState();
}

class _CurriculumRadarChartState extends State<CurriculumRadarChart> {
  bool _showPanel = true;
  bool _showAdviser = true;
  bool _showPeer = true;
  bool _showCombined = true;
  bool _showBenchmark = true;

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return Container(
        height: 380,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: AppColors.maroon),
      );
    }

    // Filter criteria that have at least a valid name
    final validCriteria = widget.criteria.where((c) => c.name.trim().isNotEmpty).toList();

    if (validCriteria.isEmpty) {
      return Container(
        height: 380,
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(Icons.radar_rounded, size: 28, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 14),
            Text(
              'No Rubric Criteria Available for ${widget.stageTitle}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Evaluations or rubric criteria for this stage will render as a dynamic radar polygon.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Layer Toggle Chips (Approach A)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildToggleChip(
                label: 'Combined',
                color: AppColors.maroon,
                isSelected: _showCombined,
                onTap: () => setState(() => _showCombined = !_showCombined),
              ),
              _buildToggleChip(
                label: 'Panelist',
                color: const Color(0xFF0EA5E9), // Sky blue
                isSelected: _showPanel,
                onTap: () => setState(() => _showPanel = !_showPanel),
              ),
              _buildToggleChip(
                label: 'Adviser',
                color: const Color(0xFF10B981), // Emerald green
                isSelected: _showAdviser,
                onTap: () => setState(() => _showAdviser = !_showAdviser),
              ),
              _buildToggleChip(
                label: 'Peer',
                color: const Color(0xFF8B5CF6), // Violet purple
                isSelected: _showPeer,
                onTap: () => setState(() => _showPeer = !_showPeer),
              ),
              _buildBenchmarkChip(),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Radar Canvas
        LayoutBuilder(
          builder: (context, constraints) {
            final double chartHeight = constraints.maxWidth < 450 ? 320 : 380;
            return SizedBox(
              height: chartHeight,
              child: CustomPaint(
                painter: _RadarPolygonPainter(
                  criteria: validCriteria,
                  showPanel: _showPanel,
                  showAdviser: _showAdviser,
                  showPeer: _showPeer,
                  showCombined: _showCombined,
                  showBenchmark: _showBenchmark,
                ),
                child: const SizedBox.expand(),
              ),
            );
          },
        ),

        const SizedBox(height: 8),
        // Helper Caption
        const Center(
          child: Text(
            'Polygons illustrate multi-axial cohort competency vs the 75% target passing line.',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleChip({
    required String label,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFCBD5E1),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: isSelected ? color : const Color(0xFF94A3B8),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenchmarkChip() {
    return InkWell(
      onTap: () => setState(() => _showBenchmark = !_showBenchmark),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _showBenchmark
              ? const Color(0xFFEF4444).withValues(alpha: 0.08)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _showBenchmark ? const Color(0xFFEF4444) : const Color(0xFFCBD5E1),
            width: _showBenchmark ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 2,
              color: _showBenchmark ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Text(
              '75% Benchmark',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: _showBenchmark ? FontWeight.w700 : FontWeight.w500,
                color: _showBenchmark ? const Color(0xFFDC2626) : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CustomPainter rendering the dynamic concentric polygons and the multi-layer overlay
class _RadarPolygonPainter extends CustomPainter {
  final List<RadarCriterionPoint> criteria;
  final bool showPanel;
  final bool showAdviser;
  final bool showPeer;
  final bool showCombined;
  final bool showBenchmark;

  _RadarPolygonPainter({
    required this.criteria,
    required this.showPanel,
    required this.showAdviser,
    required this.showPeer,
    required this.showCombined,
    required this.showBenchmark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (criteria.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    // Allow padding for text labels around the radar
    final maxRadius = math.min(size.width / 2 - 58, size.height / 2 - 28);
    if (maxRadius <= 10) return;

    final int n = criteria.length;
    final double angleStep = (2 * math.pi) / n;
    const double startAngle = -math.pi / 2; // Start from top 12 o'clock

    // 1. Draw Concentric Grid Polygons (25%, 50%, 75%, 100%)
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final axisLinePaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final gridSteps = [0.25, 0.50, 0.75, 1.0];
    for (final step in gridSteps) {
      final ringPath = Path();
      final currentRadius = maxRadius * step;
      for (int i = 0; i < n; i++) {
        final angle = startAngle + i * angleStep;
        final point = Offset(
          center.dx + currentRadius * math.cos(angle),
          center.dy + currentRadius * math.sin(angle),
        );
        if (i == 0) {
          ringPath.moveTo(point.dx, point.dy);
        } else {
          ringPath.lineTo(point.dx, point.dy);
        }
      }
      ringPath.close();
      canvas.drawPath(ringPath, gridPaint);
    }

    // 2. Draw Spokes / Axis Lines
    for (int i = 0; i < n; i++) {
      final angle = startAngle + i * angleStep;
      final outerPoint = Offset(
        center.dx + maxRadius * math.cos(angle),
        center.dy + maxRadius * math.sin(angle),
      );
      canvas.drawLine(center, outerPoint, axisLinePaint);
    }

    // 3. Draw 75% Benchmark Target Polygon (Red / Crimson dashed ring)
    if (showBenchmark) {
      final benchmarkRadius = maxRadius * 0.75;
      final benchmarkPath = Path();
      for (int i = 0; i < n; i++) {
        final angle = startAngle + i * angleStep;
        final point = Offset(
          center.dx + benchmarkRadius * math.cos(angle),
          center.dy + benchmarkRadius * math.sin(angle),
        );
        if (i == 0) {
          benchmarkPath.moveTo(point.dx, point.dy);
        } else {
          benchmarkPath.lineTo(point.dx, point.dy);
        }
      }
      benchmarkPath.close();

      final benchmarkPaint = Paint()
        ..color = const Color(0xFFEF4444).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;

      canvas.drawPath(benchmarkPath, benchmarkPaint);
    }

    // Helper to draw a filled/stroked layer polygon
    void drawLayer({
      required List<double?> scores,
      required Color color,
      required double fillAlpha,
      required double strokeWidth,
    }) {
      final layerPath = Path();
      final points = <Offset>[];
      bool hasAnyScore = false;

      for (int i = 0; i < n; i++) {
        final score = scores[i] ?? 0.0;
        if (scores[i] != null && scores[i]! > 0) hasAnyScore = true;
        // Clamp score between 0 and 100
        final normalized = (score / 100.0).clamp(0.0, 1.0);
        final r = maxRadius * normalized;
        final angle = startAngle + i * angleStep;
        final pt = Offset(
          center.dx + r * math.cos(angle),
          center.dy + r * math.sin(angle),
        );
        points.add(pt);
        if (i == 0) {
          layerPath.moveTo(pt.dx, pt.dy);
        } else {
          layerPath.lineTo(pt.dx, pt.dy);
        }
      }
      layerPath.close();

      if (!hasAnyScore) return;

      // Fill
      final fillPaint = Paint()
        ..color = color.withValues(alpha: fillAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawPath(layerPath, fillPaint);

      // Stroke
      final strokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawPath(layerPath, strokePaint);

      // Vertices dots
      final dotFillPaint = Paint()..color = Colors.white;
      final dotStrokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      for (int i = 0; i < n; i++) {
        if (scores[i] != null && scores[i]! > 0) {
          canvas.drawCircle(points[i], 3.5, dotFillPaint);
          canvas.drawCircle(points[i], 3.5, dotStrokePaint);
        }
      }
    }

    // 4. Overlaid Polygons (Panelist, Adviser, Peer, Combined)
    if (showPeer) {
      drawLayer(
        scores: criteria.map((c) => c.peerScore).toList(),
        color: const Color(0xFF8B5CF6), // Purple
        fillAlpha: 0.18,
        strokeWidth: 2.0,
      );
    }

    if (showAdviser) {
      drawLayer(
        scores: criteria.map((c) => c.adviserScore).toList(),
        color: const Color(0xFF10B981), // Emerald
        fillAlpha: 0.22,
        strokeWidth: 2.0,
      );
    }

    if (showPanel) {
      drawLayer(
        scores: criteria.map((c) => c.panelScore).toList(),
        color: const Color(0xFF0EA5E9), // Sky Blue
        fillAlpha: 0.25,
        strokeWidth: 2.2,
      );
    }

    if (showCombined) {
      drawLayer(
        scores: criteria.map((c) => c.combinedScore).toList(),
        color: AppColors.maroon, // DefenSYS Maroon
        fillAlpha: 0.20,
        strokeWidth: 2.4,
      );
    }

    // 5. Draw Axis Labels around perimeter
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < n; i++) {
      final angle = startAngle + i * angleStep;
      final labelDist = maxRadius + 18;
      final labelX = center.dx + labelDist * math.cos(angle);
      final labelY = center.dy + labelDist * math.sin(angle);

      final crit = criteria[i];
      final rawScore = crit.combinedScore;
      final scoreStr = rawScore != null ? '${rawScore.toStringAsFixed(0)}%' : 'N/A';

      // Truncate long criteria names
      String shortName = crit.name;
      if (shortName.length > 20) {
        shortName = '${shortName.substring(0, 18)}...';
      }

      final labelSpan = TextSpan(
        children: [
          TextSpan(
            text: '$shortName\n',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
              height: 1.15,
            ),
          ),
          TextSpan(
            text: scoreStr,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: rawScore != null
                  ? (rawScore >= 75 ? const Color(0xFF059669) : const Color(0xFFDC2626))
                  : const Color(0xFF94A3B8),
            ),
          ),
        ],
      );

      textPainter.text = labelSpan;
      textPainter.layout(maxWidth: 100);

      // Center the label box around the target offset
      double offsetX = labelX - textPainter.width / 2;
      double offsetY = labelY - textPainter.height / 2;

      // Nudge slightly based on angle quadrant for visual balance
      if (math.cos(angle).abs() > 0.3) {
        if (math.cos(angle) > 0) {
          offsetX += 4;
        } else {
          offsetX -= 4;
        }
      }

      textPainter.paint(canvas, Offset(offsetX, offsetY));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPolygonPainter oldDelegate) {
    return oldDelegate.criteria != criteria ||
        oldDelegate.showPanel != showPanel ||
        oldDelegate.showAdviser != showAdviser ||
        oldDelegate.showPeer != showPeer ||
        oldDelegate.showCombined != showCombined ||
        oldDelegate.showBenchmark != showBenchmark;
  }
}
