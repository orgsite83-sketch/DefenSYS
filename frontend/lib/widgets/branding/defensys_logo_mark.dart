import 'package:flutter/material.dart';

enum DefensysLogoColorMode {
  white,
  brand,
  black,
}

/// A 100% resolution-independent, ultra-crisp vector logo mark for DefenSYS (Concept 02).
/// Renders using native Flutter GPU paths with anti-aliasing to eliminate any pixelation.
class DefensysLogoMark extends StatelessWidget {
  const DefensysLogoMark({
    super.key,
    this.size = 40,
    this.colorMode = DefensysLogoColorMode.white,
    this.customColor,
  });

  final double size;
  final DefensysLogoColorMode colorMode;
  final Color? customColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: Concept02LogoPainter(
          colorMode: colorMode,
          customColor: customColor,
        ),
      ),
    );
  }
}

class Concept02LogoPainter extends CustomPainter {
  Concept02LogoPainter({
    required this.colorMode,
    this.customColor,
  });

  final DefensysLogoColorMode colorMode;
  final Color? customColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.width / 200.0;

    Path buildPolygon(List<Offset> points) {
      final path = Path();
      if (points.isEmpty) return path;
      path.moveTo(points[0].dx * scale, points[0].dy * scale);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx * scale, points[i].dy * scale);
      }
      path.close();
      return path;
    }

    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high
      ..style = PaintingStyle.fill;

    // Polygons definitions (200x200 viewbox coordinates)
    final pTop = buildPolygon(const [Offset(100, 20), Offset(122, 42), Offset(100, 56), Offset(78, 42)]);
    final pUR = buildPolygon(const [Offset(105, 62), Offset(150, 42), Offset(138, 72), Offset(105, 86)]);
    final pUL = buildPolygon(const [Offset(95, 62), Offset(50, 42), Offset(62, 72), Offset(95, 86)]);
    final pMR = buildPolygon(const [Offset(105, 92), Offset(168, 66), Offset(152, 104), Offset(105, 120)]);
    final pML = buildPolygon(const [Offset(95, 92), Offset(32, 66), Offset(48, 104), Offset(95, 120)]);
    final pBR = buildPolygon(const [Offset(105, 126), Offset(180, 94), Offset(160, 144), Offset(105, 178)]);
    final pBL = buildPolygon(const [Offset(95, 126), Offset(20, 94), Offset(40, 144), Offset(95, 178)]);

    Color cTop, cU, cM, cB;

    if (customColor != null) {
      cTop = customColor!;
      cU = customColor!.withValues(alpha: 0.95);
      cM = customColor!.withValues(alpha: 0.85);
      cB = customColor!.withValues(alpha: 0.75);
    } else {
      switch (colorMode) {
        case DefensysLogoColorMode.white:
          cTop = const Color(0xFFFFFFFF);
          cU = const Color(0xF5FFFFFF);
          cM = const Color(0xDCFFFFFF);
          cB = const Color(0xC0FFFFFF);
          break;
        case DefensysLogoColorMode.brand:
          cTop = const Color(0xFFF59E0B);
          cU = const Color(0xFFB91C1C);
          cM = const Color(0xFF7A110A);
          cB = const Color(0xFF540A06);
          break;
        case DefensysLogoColorMode.black:
          cTop = const Color(0xFF111827);
          cU = const Color(0xF51F2937);
          cM = const Color(0xDC374151);
          cB = const Color(0xC04B5563);
          break;
      }
    }

    paint.color = cTop;
    canvas.drawPath(pTop, paint);

    paint.color = cU;
    canvas.drawPath(pUR, paint);
    canvas.drawPath(pUL, paint);

    paint.color = cM;
    canvas.drawPath(pMR, paint);
    canvas.drawPath(pML, paint);

    paint.color = cB;
    canvas.drawPath(pBR, paint);
    canvas.drawPath(pBL, paint);
  }

  @override
  bool shouldRepaint(covariant Concept02LogoPainter oldDelegate) {
    return oldDelegate.colorMode != colorMode || oldDelegate.customColor != customColor;
  }
}
