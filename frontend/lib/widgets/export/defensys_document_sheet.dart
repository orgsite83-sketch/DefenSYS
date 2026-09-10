import 'package:flutter/material.dart';
import '../../services/admin/reports_provider.dart';
import '../../theme/defensys_tokens.dart';
import 'defensys_export_models.dart';

/// Authentic WYSIWYG A4 Institutional Document Sheet mirroring the exact multi-page PDF export.
class DefensysDocumentSheet extends StatelessWidget {
  final ReportPreviewData previewData;
  final List<DefensysSignatory> signatories;
  final bool includeSignatures;
  final double scale;

  static const double sheetWidth = 780.0;
  static const double sheetHeight = 1103.0; // Standard A4 Aspect Ratio (1 : 1.4142)

  const DefensysDocumentSheet({
    super.key,
    required this.previewData,
    this.signatories = const [],
    this.includeSignatures = true,
    this.scale = 1.0,
  });

  int _calculateTotalPages() {
    if (previewData.sections.isNotEmpty) {
      int maxPage = 1;
      for (final s in previewData.sections) {
        final p = (s['page'] as num?)?.toInt() ?? 1;
        if (p > maxPage) maxPage = p;
      }
      return maxPage;
    }

    // For generic single-table reports
    if (previewData.rows.length > 16) {
      return (previewData.rows.length / 16).ceil().clamp(1, 10);
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = _calculateTotalPages();

    return Column(
      children: List.generate(totalPages, (index) {
        final pageNum = index + 1;
        return Column(
          children: [
            if (index > 0) _buildPageDivider(pageNum, totalPages),
            _buildPageSheet(pageNum, totalPages),
          ],
        );
      }),
    );
  }

  /// Page Divider between physical A4 sheets
  Widget _buildPageDivider(int pageNum, int totalPages) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 18 * scale),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120 * scale,
            height: 1,
            color: const Color(0xFFCBD5E1),
          ),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 14 * scale),
            padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 4 * scale),
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.layers_outlined, size: 12 * scale, color: const Color(0xFF334155)),
                SizedBox(width: 5 * scale),
                Text(
                  'PAGE $pageNum OF $totalPages',
                  style: TextStyle(
                    fontSize: 9.5 * scale,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E293B),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 120 * scale,
            height: 1,
            color: const Color(0xFFCBD5E1),
          ),
        ],
      ),
    );
  }

  /// Physical A4 Paper Sheet representation for a specific page number
  Widget _buildPageSheet(int pageNum, int totalPages) {
    return Center(
      child: Container(
        width: sheetWidth * scale,
        height: sheetHeight * scale, // Exact physical A4 page height matching the exported PDF
        margin: EdgeInsets.only(bottom: 24 * scale),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Official USTP Header Banner (Rendered on EVERY Page)
            _buildHeaderBanner(),

            // 2. Main Two-Column Layout (Sidebar Ribbon + Document Content)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Sidebar Ribbon (USTP Vision, Mission, Quality Policy)
                  SizedBox(
                    width: 124 * scale,
                    child: _buildSidebarRibbon(),
                  ),

                  // Page Specific Document Content
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16 * scale,
                        8 * scale,
                        18 * scale,
                        8 * scale,
                      ),
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _buildPageContent(pageNum, totalPages),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 3. Official Institutional Running Footer (Pinned at the bottom of EVERY Page across full width)
            _buildOfficialFooter(pageNum, totalPages),
          ],
        ),
      ),
    );
  }

  /// Resolves which elements appear on Page 1, Page 2, etc.
  List<Widget> _buildPageContent(int pageNum, int totalPages) {
    final widgets = <Widget>[];

    if (previewData.sections.isNotEmpty) {
      if (pageNum == 1) {
        // Page 1: Title, Subtitle, Metadata Grid, and Page 1 Sections (Sections 1, 2, 3, and recommendations 1 & 2)
        widgets.add(_buildTitleBlock());
        widgets.add(SizedBox(height: 6 * scale));

        if (previewData.metadata.isNotEmpty) {
          widgets.add(_buildMetadataGrid());
          widgets.add(SizedBox(height: 6 * scale));
        }

        final page1Sections = previewData.sections
            .where((s) => (s['page'] as num?)?.toInt() == 1 || s['page'] == null)
            .toList();
        for (final s in page1Sections) {
          widgets.add(_buildReportSection(s));
        }

        if (totalPages == 1) {
          widgets.add(SizedBox(height: 14 * scale));
          widgets.add(_buildOfficialSignaturesBlock());
        }
      } else if (pageNum == 2) {
        // Page 2: Recommendations Continued (Items 3, 4, 5...) + Vertical Official Signatures Block
        final page2Sections = previewData.sections
            .where((s) => (s['page'] as num?)?.toInt() == 2)
            .toList();
        for (final s in page2Sections) {
          widgets.add(_buildReportSection(s));
        }

        widgets.add(SizedBox(height: 18 * scale));
        widgets.add(_buildOfficialSignaturesBlock());
      } else {
        // Page 3+ if applicable
        final pageNSections = previewData.sections
            .where((s) => (s['page'] as num?)?.toInt() == pageNum)
            .toList();
        for (final s in pageNSections) {
          widgets.add(_buildReportSection(s));
        }
        if (pageNum == totalPages) {
          widgets.add(SizedBox(height: 18 * scale));
          widgets.add(_buildOfficialSignaturesBlock());
        }
      }
    } else {
      // General Report Table Pagination (e.g. Audit Trail, Team Roster)
      if (pageNum == 1) {
        widgets.add(_buildTitleBlock());
        widgets.add(SizedBox(height: 6 * scale));
        if (previewData.metadata.isNotEmpty) {
          widgets.add(_buildMetadataGrid());
          widgets.add(SizedBox(height: 6 * scale));
        }
        widgets.add(_buildFallbackTableSection(startIndex: 0, count: 16));
        if (totalPages == 1) {
          widgets.add(SizedBox(height: 14 * scale));
          widgets.add(_buildOfficialSignaturesBlock());
        }
      } else {
        final startIndex = (pageNum - 1) * 16;
        widgets.add(_buildFallbackTableSection(startIndex: startIndex, count: 20));
        if (pageNum == totalPages) {
          widgets.add(SizedBox(height: 18 * scale));
          widgets.add(_buildOfficialSignaturesBlock());
        }
      }
    }

    return widgets;
  }

  /// 1. Top Header Banner (USTP Header Image with Fallback)
  Widget _buildHeaderBanner() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFCBD5E1), width: 0.8),
        ),
      ),
      child: Image.asset(
        'assets/ustp_header_banner.png',
        fit: BoxFit.fitWidth,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            color: const Color(0xFFFAFBFD),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: DefensysTokens.maroon.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.school_rounded, color: DefensysTokens.maroon, size: 30),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'REPUBLIC OF THE PHILIPPINES',
                        style: TextStyle(
                          fontFamily: 'serif',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: Color(0xFF334155),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'UNIVERSITY OF SCIENCE AND TECHNOLOGY OF SOUTHERN PHILIPPINES',
                        style: TextStyle(
                          fontFamily: 'serif',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Department of Information Technology',
                        style: TextStyle(
                          fontFamily: 'serif',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: DefensysTokens.maroon,
                        ),
                      ),
                      Text(
                        'P-6, Mobod, Oroquieta City, Misamis Occidental 7207 • Email: ustporoquieta.bsit@ustp.edu.ph',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: DefensysTokens.gold.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified_rounded, color: DefensysTokens.darkGold, size: 28),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 2. Left Sidebar Ribbon (USTP Vision, Mission, Quality Policy)
  Widget _buildSidebarRibbon() {
    return Container(
      color: const Color(0xFFFCFDFE),
      child: Image.asset(
        'assets/ustp_sidebar.png',
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        errorBuilder: (context, error, stackTrace) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 10 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sidebarSection(
                  title: 'UNIVERSITY VISION',
                  body: 'A nationally-recognized S&T University providing the vital link between education and the economy.',
                ),
                SizedBox(height: 12 * scale),
                _sidebarSection(
                  title: 'UNIVERSITY MISSION',
                  body: 'Bring the world of work into the actual higher education of students. Offer entrepreneurs opportunities to maximize potentials.',
                ),
                SizedBox(height: 12 * scale),
                _sidebarSection(
                  title: 'QUALITY POLICY',
                  body: 'We are committed to provide primary customers with excellent and continually improved quality services.',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sidebarSection({required String title, required String body}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 8 * scale,
            fontWeight: FontWeight.w800,
            color: DefensysTokens.maroon,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 2 * scale),
        Text(
          body,
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 7 * scale,
            fontStyle: FontStyle.italic,
            height: 1.30,
            color: const Color(0xFF475569),
          ),
        ),
      ],
    );
  }

  /// 3. Document Title & Subtitle Block
  Widget _buildTitleBlock() {
    return Column(
      children: [
        Text(
          previewData.title.toUpperCase(),
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 12 * scale,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            color: Colors.black,
          ),
          textAlign: TextAlign.center,
        ),
        if (previewData.subtitle.isNotEmpty) ...[
          SizedBox(height: 2 * scale),
          Text(
            previewData.subtitle,
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 9 * scale,
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
              color: const Color(0xFF1F2937),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// 4. Executive Metadata Grid
  Widget _buildMetadataGrid() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.6),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.1),
          1: FlexColumnWidth(2.0),
        },
        border: TableBorder.symmetric(
          inside: const BorderSide(color: Color(0xFFE5E7EB), width: 0.5),
        ),
        children: previewData.metadata.map((item) {
          final label = item['label']?.toString() ?? '';
          final val = item['value']?.toString() ?? '';

          return TableRow(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2.5 * scale),
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 8.5 * scale,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2.5 * scale),
                child: Text(
                  ': $val',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 8.5 * scale,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// 5. Structured Section Builder (Narrative, Tables, Recommendations)
  Widget _buildReportSection(Map<String, dynamic> section) {
    final title = section['title']?.toString() ?? '';
    final type = section['type']?.toString() ?? 'table';

    return Padding(
      padding: EdgeInsets.only(bottom: 6 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty) ...[
            Text(
              title,
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 9.8 * scale,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 3 * scale),
          ],

          if (type == 'summary') ...[
            Text(
              section['text']?.toString() ?? '',
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 8.5 * scale,
                height: 1.32,
                color: Colors.black,
              ),
            ),
          ] else if (type == 'table') ...[
            _buildSectionTable(
              headers: (section['headers'] as List?)?.map((e) => e.toString()).toList() ?? [],
              rows: (section['rows'] as List?) ?? [],
            ),
          ] else if (type == 'recommendations') ...[
            _buildRecommendationsList((section['items'] as List?) ?? []),
          ],
        ],
      ),
    );
  }

  /// Table Section Renderer
  Widget _buildSectionTable({
    required List<String> headers,
    required List<dynamic> rows,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.6),
        borderRadius: BorderRadius.circular(1),
      ),
      child: Table(
        border: TableBorder.all(color: const Color(0xFFCBD5E1), width: 0.5),
        children: [
          // Header Row
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFF3F4F6)),
            children: headers.map((h) {
              final isCenter = h.contains('%') ||
                  h.contains('Score') ||
                  h.contains('Share') ||
                  h.contains('Count') ||
                  h.contains('Status') ||
                  h.contains('Trend');
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 2.5 * scale),
                child: Text(
                  h,
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 8 * scale,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                  textAlign: isCenter ? TextAlign.center : TextAlign.left,
                ),
              );
            }).toList(),
          ),

          // Data Rows
          ...rows.asMap().entries.map((entry) {
            final idx = entry.key;
            final rowList = entry.value as List;
            final isStripe = idx % 2 == 1;

            return TableRow(
              decoration: BoxDecoration(
                color: isStripe ? const Color(0xFFF9FAFB) : Colors.white,
              ),
              children: rowList.asMap().entries.map((cEntry) {
                final cIdx = cEntry.key;
                final cellVal = cEntry.value?.toString() ?? '';
                final isCenter = cIdx > 0 && cIdx < rowList.length - 1;
                final isStatus = cIdx == rowList.length - 1;
                final isFirst = cIdx == 0;

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 2.2 * scale),
                  child: Text(
                    cellVal,
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 8 * scale,
                      fontWeight: (isFirst || isStatus || cIdx == 1) ? FontWeight.w800 : FontWeight.w500,
                      color: Colors.black,
                    ),
                    textAlign: (isCenter || isStatus) ? TextAlign.center : TextAlign.left,
                  ),
                );
              }).toList(),
            );
          }),
        ],
      ),
    );
  }

  /// Recommendations List Renderer
  Widget _buildRecommendationsList(List<dynamic> items) {
    if (items.isEmpty) {
      return Text(
        'Continue monitoring defense performance and repository compliance records.',
        style: TextStyle(fontFamily: 'serif', fontSize: 8.5 * scale, color: const Color(0xFF475569)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items.map((rec) {
        final num = rec['number']?.toString() ?? '•';
        final cat = rec['category']?.toString() ?? 'RECOMMENDATION';
        final title = rec['title']?.toString() ?? '';
        final body = rec['body']?.toString() ?? '';

        return Padding(
          padding: EdgeInsets.only(bottom: 4 * scale),
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 8.5 * scale,
                color: Colors.black,
                height: 1.28,
              ),
              children: [
                TextSpan(
                  text: '$num. [${cat.toUpperCase()}] $title\n',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: body,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Fallback Table Section for non-proposal reports
  Widget _buildFallbackTableSection({required int startIndex, required int count}) {
    final rowsSlice = previewData.rows.skip(startIndex).take(count).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Official Defense & Audit Records',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 10 * scale,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
        SizedBox(height: 4 * scale),
        _buildSectionTable(
          headers: previewData.columns.map((c) => c['label']?.toString() ?? '').toList(),
          rows: rowsSlice.map((r) {
            return previewData.columns.map((c) => r[c['key']]?.toString() ?? '').toList();
          }).toList(),
        ),
      ],
    );
  }

  /// 6. Official Vertical Signatures Block (Matching Image 2 and ReportLab add_signatures)
  Widget _buildOfficialSignaturesBlock() {
    if (!includeSignatures) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          '[Signatures Certification Block Omitted for this export copy]',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 8.5 * scale,
            fontStyle: FontStyle.italic,
            color: const Color(0xFF64748B),
          ),
        ),
      );
    }

    final activeSigners = signatories.isNotEmpty
        ? signatories
        : const [
            DefensysSignatory(
              label: 'Prepared by:',
              name: 'admin',
              role: 'Curriculum Analytics Lead / Evaluator',
            ),
            DefensysSignatory(
              label: 'Noted by:',
              name: 'Academic Department Secretary',
              role: 'Department Curriculum Committee Secretary',
            ),
            DefensysSignatory(
              label: 'Approved by:',
              name: 'IT Program Chairperson / College Dean',
              role: 'Chairperson, Department of Information Technology',
            ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: activeSigners.asMap().entries.map((entry) {
        final idx = entry.key;
        final s = entry.value;
        final isLast = idx == activeSigners.length - 1;

        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 12 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.label,
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 9 * scale,
                  fontStyle: FontStyle.italic,
                  color: Colors.black,
                ),
              ),
              SizedBox(height: 18 * scale),
              Container(
                width: 220 * scale,
                height: 0.8,
                color: Colors.black,
              ),
              SizedBox(height: 3 * scale),
              Text(
                s.name.isNotEmpty ? s.name : '—',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 9.5 * scale,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              if (s.role.isNotEmpty && s.role != s.name)
                Text(
                  s.role,
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 8.5 * scale,
                    color: const Color(0xFF374151),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 7. Official Institutional Running Footer (Pinned at the bottom of EVERY Page across full width)
  Widget _buildOfficialFooter(int pageNum, int totalPages) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Gold rule line across entire page width
        Container(
          height: 1.2 * scale,
          color: const Color(0xFFD4A843), // Official Gold
        ),
        Container(
          height: 32 * scale,
          padding: EdgeInsets.symmetric(horizontal: 16 * scale),
          color: Colors.white,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Campus badge on bottom left (under the sidebar ribbon)
              SizedBox(
                width: 124 * scale,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Image.asset(
                    'assets/ustp_footer_badge.png',
                    height: 20 * scale,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Text(
                        'USTP OROQUIETA',
                        style: TextStyle(
                          fontFamily: 'serif',
                          fontSize: 7.5 * scale,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Accountability text in center
              Expanded(
                child: Text(
                  'Official Record · Generated by: ${previewData.generatedBy.isNotEmpty ? previewData.generatedBy : 'admin'} · ${previewData.generatedAt}',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 7.5 * scale,
                    color: const Color(0xFF4B5563),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              // Page count on bottom right
              SizedBox(
                width: 70 * scale,
                child: Text(
                  'Page $pageNum of $totalPages',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 8 * scale,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
