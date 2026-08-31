import 'package:flutter/material.dart';

enum BookCoverSize {
  small(width: 58, height: 82, titleSize: 8, authorSize: 7, iconSize: 14),
  medium(width: 104, height: 148, titleSize: 10.5, authorSize: 8.5, iconSize: 20),
  large(width: 140, height: 200, titleSize: 13, authorSize: 10, iconSize: 28);

  final double width;
  final double height;
  final double titleSize;
  final double authorSize;
  final double iconSize;

  const BookCoverSize({
    required this.width,
    required this.height,
    required this.titleSize,
    required this.authorSize,
    required this.iconSize,
  });
}

class BookThemePalette {
  final Color primary;
  final Color darkGradient;
  final Color accent;
  final Color textColor;
  final Color ribbonColor;

  const BookThemePalette({
    required this.primary,
    required this.darkGradient,
    required this.accent,
    required this.textColor,
    required this.ribbonColor,
  });

  static BookThemePalette forTypeAndCategory({
    required String type,
    required String category,
    required String stage,
  }) {
    final lowerType = type.toLowerCase();
    final lowerCat = category.toLowerCase();
    final lowerStage = stage.toLowerCase();

    if (lowerType == 'capstone') {
      if (lowerCat.contains('ai') || lowerCat.contains('machine') || lowerCat.contains('intel')) {
        return const BookThemePalette(
          primary: Color(0xFF6B1D2F),
          darkGradient: Color(0xFF380813),
          accent: Color(0xFFF6AD55),
          textColor: Color(0xFFFFF5F5),
          ribbonColor: Color(0xFFDD6B20),
        );
      }
      return const BookThemePalette(
        primary: Color(0xFF7A110A),
        darkGradient: Color(0xFF450A0A),
        accent: Color(0xFFFBBF24),
        textColor: Color(0xFFFFFBEB),
        ribbonColor: Color(0xFFD97706),
      );
    } else if (lowerType == 'pit') {
      if (lowerCat.contains('iot') || lowerCat.contains('hardware') || lowerCat.contains('embed')) {
        return const BookThemePalette(
          primary: Color(0xFF14532D),
          darkGradient: Color(0xFF052E16),
          accent: Color(0xFF86EFAC),
          textColor: Color(0xFFF0FDF4),
          ribbonColor: Color(0xFF16A34A),
        );
      }
      return const BookThemePalette(
        primary: Color(0xFF1E3A8A),
        darkGradient: Color(0xFF0F172A),
        accent: Color(0xFF93C5FD),
        textColor: Color(0xFFEFF6FF),
        ribbonColor: Color(0xFF2563EB),
      );
    } else {
      // Document / other
      if (lowerStage.contains('final') || lowerStage.contains('manuscript')) {
        return const BookThemePalette(
          primary: Color(0xFF4C1D95),
          darkGradient: Color(0xFF2E1065),
          accent: Color(0xFFC084FC),
          textColor: Color(0xFFFAF5FF),
          ribbonColor: Color(0xFF9333EA),
        );
      }
      return const BookThemePalette(
        primary: Color(0xFF334155),
        darkGradient: Color(0xFF0F172A),
        accent: Color(0xFF94A3B8),
        textColor: Color(0xFFF8FAFC),
        ribbonColor: Color(0xFF64748B),
      );
    }
  }
}

class BookCoverWidget extends StatelessWidget {
  final String title;
  final String authorOrTeam;
  final String type; // 'capstone', 'pit', 'uploader'
  final String stage;
  final String category;
  final String academicYear;
  final double? rating;
  final BookCoverSize size;
  final bool showBookmarkRibbon;
  final bool isBookmarked;
  final VoidCallback? onBookmarkTap;

  const BookCoverWidget({
    super.key,
    required this.title,
    required this.authorOrTeam,
    this.type = 'capstone',
    this.stage = '',
    this.category = '',
    this.academicYear = '',
    this.rating,
    this.size = BookCoverSize.medium,
    this.showBookmarkRibbon = true,
    this.isBookmarked = false,
    this.onBookmarkTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = BookThemePalette.forTypeAndCategory(
      type: type,
      category: category,
      stage: stage,
    );

    final cleanTitle = _cleanTitle(title);
    final displayAuthor = authorOrTeam.isEmpty || authorOrTeam == '—' ? 'USTP Research' : authorOrTeam;

    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(3),
          bottomLeft: Radius.circular(3),
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 8,
            offset: const Offset(3, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 2,
            offset: const Offset(1, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(3),
          bottomLeft: Radius.circular(3),
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        child: Stack(
          children: [
            // ── Background Gradient ──
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    palette.primary,
                    palette.darkGradient,
                  ],
                ),
              ),
            ),

            // ── Subtle Cover Texture Lines ──
            Positioned.fill(
              child: CustomPaint(
                painter: _BookCoverPatternPainter(accentColor: palette.accent.withValues(alpha: 0.12)),
              ),
            ),

            // ── Realistic Spine Shadow & Crease (Left edge 3D fold) ──
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: size == BookCoverSize.large ? 12 : 7,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.5),
                      Colors.black.withValues(alpha: 0.15),
                      Colors.white.withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 0.65, 1.0],
                  ),
                ),
              ),
            ),

            // ── Inner Embossed Gold/Silver Border ──
            Positioned(
              top: 5,
              bottom: 5,
              left: (size == BookCoverSize.large ? 14 : 9),
              right: 6,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: palette.accent.withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
              ),
            ),

            // ── Content Area ──
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  (size == BookCoverSize.large ? 18 : 12),
                  size == BookCoverSize.small ? 6 : 10,
                  8,
                  size == BookCoverSize.small ? 6 : 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // University Seal / Monogram Eyebrow
                    Row(
                      children: [
                        Icon(
                          Icons.menu_book_rounded,
                          size: size == BookCoverSize.small ? 8 : (size == BookCoverSize.large ? 14 : 10),
                          color: palette.accent,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            type.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: size == BookCoverSize.small ? 6.5 : (size == BookCoverSize.large ? 9 : 7.5),
                              fontWeight: FontWeight.w900,
                              color: palette.accent,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(flex: 1),

                    // Book Title
                    Text(
                      cleanTitle,
                      maxLines: size == BookCoverSize.small ? 2 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: size.titleSize,
                        fontWeight: FontWeight.w800,
                        color: palette.textColor,
                        height: 1.18,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 3),

                    // Subtitle / Stage line
                    if (stage.isNotEmpty && stage != '—' && size != BookCoverSize.small)
                      Text(
                        stage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: size.authorSize - 1,
                          fontWeight: FontWeight.w600,
                          color: palette.accent.withValues(alpha: 0.9),
                        ),
                      ),

                    const Spacer(flex: 2),

                    // Gold decorative divider
                    Container(
                      height: 1,
                      width: size.width * 0.45,
                      color: palette.accent.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 4),

                    // Authors / Team Name
                    Text(
                      displayAuthor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: size.authorSize,
                        fontWeight: FontWeight.w600,
                        color: palette.textColor.withValues(alpha: 0.85),
                      ),
                    ),

                    if (academicYear.isNotEmpty && academicYear != '—' && size == BookCoverSize.large) ...[
                      const SizedBox(height: 2),
                      Text(
                        'SY $academicYear',
                        style: TextStyle(
                          fontSize: size.authorSize - 1.5,
                          color: palette.textColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Rating Badge Pill (Top-Left or Bottom-Right) ──
            if (rating != null && rating! > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: palette.accent.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, size: 9, color: Color(0xFFFBBF24)),
                      const SizedBox(width: 2),
                      Text(
                        rating!.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Top-Right Bookmark Ribbon (if bookmarked) ──
            if (showBookmarkRibbon && isBookmarked)
              Positioned(
                top: 0,
                right: 8,
                child: Container(
                  width: 10,
                  height: 16,
                  decoration: BoxDecoration(
                    color: palette.ribbonColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _cleanTitle(String raw) {
    var name = raw;
    final lastDot = name.lastIndexOf('.');
    if (lastDot != -1) {
      name = name.substring(0, lastDot);
    }
    name = name.replaceAll(RegExp(r'[._\-]'), ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return name;
  }
}

class _BookCoverPatternPainter extends CustomPainter {
  final Color accentColor;

  _BookCoverPatternPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accentColor
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Subtle corner ornaments
    final path = Path();
    const margin = 12.0;
    const len = 8.0;

    // Top-left
    path.moveTo(margin + len, margin);
    path.lineTo(margin, margin);
    path.lineTo(margin, margin + len);

    // Bottom-right
    path.moveTo(size.width - margin - len, size.height - margin);
    path.lineTo(size.width - margin, size.height - margin);
    path.lineTo(size.width - margin, size.height - margin - len);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BookCoverPatternPainter oldDelegate) => false;
}
