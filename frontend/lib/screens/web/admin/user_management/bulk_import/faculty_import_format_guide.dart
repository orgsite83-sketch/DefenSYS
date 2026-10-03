import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/import/student_bulk_import_csv.dart';

/// A spreadsheet preview of the exact CSV supplied by the download action.
class FacultyImportFormatGuide extends StatefulWidget {
  const FacultyImportFormatGuide({
    super.key,
    required this.templateRows,
    required this.onDownload,
  });

  final List<List<String>> templateRows;
  final VoidCallback onDownload;

  @override
  State<FacultyImportFormatGuide> createState() =>
      _FacultyImportFormatGuideState();
}

class _FacultyImportFormatGuideState extends State<FacultyImportFormatGuide> {
  final _scrollController = ScrollController();
  static const _columnWidths = [32.0, 108.0, 94.0, 94.0, 172.0, 220.0];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = DefensysTokens.textPrimaryOf(context);
    final muted = DefensysTokens.textSecondaryOf(context);
    final isDark = DefensysTokens.isDark(context);
    final accent = isDark ? DefensysTokens.dangerBorder : DefensysTokens.maroon;
    final border = DefensysTokens.borderOf(context);
    final surface = DefensysTokens.surfaceOf(context);
    final raisedSurface = DefensysTokens.surfaceHigherOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final minimumTableWidth =
        _columnWidths.reduce((a, b) => a + b) * math.max(1, textScale);

    return DefensysCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                ),
                child: Icon(Icons.badge_outlined, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CSV Format',
                      style: DefensysTokens.sectionTitle.copyWith(color: ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Official Faculty & Staff Template • Institutional Accounts',
                      style: DefensysTokens.caption.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: raisedSurface,
                    border: Border(bottom: BorderSide(color: border)),
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(
                            DefensysTokens.radiusSm,
                          ),
                          border: Border.all(color: border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.insert_drive_file_outlined,
                              size: 14,
                              color: isDark
                                  ? DefensysTokens.successBorder
                                  : DefensysTokens.successText,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                sampleFacultyCsvFilename,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Faculty & Staff Template',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final canScroll = constraints.maxWidth < minimumTableWidth;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: canScroll,
                          trackVisibility: canScroll,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.only(
                              bottom: canScroll ? 12 : 0,
                            ),
                            child: SizedBox(
                              width: math.max(
                                constraints.maxWidth,
                                minimumTableWidth,
                              ),
                              child: Table(
                                defaultVerticalAlignment:
                                    TableCellVerticalAlignment.middle,
                                columnWidths: {
                                  0: FixedColumnWidth(
                                    32 * math.max(1, textScale),
                                  ),
                                  for (var i = 1; i < _columnWidths.length; i++)
                                    i: FlexColumnWidth(_columnWidths[i]),
                                },
                                border: TableBorder.symmetric(
                                  inside: BorderSide(
                                    color: border.withValues(alpha: 0.7),
                                  ),
                                ),
                                children: [
                                  for (
                                    var r = 0;
                                    r < widget.templateRows.length;
                                    r++
                                  )
                                    TableRow(
                                      decoration: BoxDecoration(
                                        color: r == 0
                                            ? isDark
                                                  ? raisedSurface
                                                  : DefensysTokens.border
                                            : r.isEven
                                            ? raisedSurface
                                            : surface,
                                      ),
                                      children: [
                                        ExcludeSemantics(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            child: Text(
                                              '${r + 1}',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: muted,
                                              ),
                                            ),
                                          ),
                                        ),
                                        for (
                                          var c = 0;
                                          c < widget.templateRows[r].length;
                                          c++
                                        )
                                          Semantics(
                                            header: r == 0,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                              child: Text(
                                                widget.templateRows[r][c],
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: r == 0 || c == 0
                                                      ? FontWeight.w600
                                                      : FontWeight.w400,
                                                  color: r > 0 && c == 4
                                                      ? accent
                                                      : c == 3 && r > 0
                                                      ? muted
                                                      : ink,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (canScroll)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                            child: Text(
                              'Scroll horizontally to view all columns',
                              style: DefensysTokens.caption.copyWith(
                                color: muted,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Use one row per account and keep the headers shown above. '
                  'Separate multiple roles with commas or slashes, such as '
                  '"Panelist, Adviser" or "PIT Lead 1st Year / Panelist". '
                  'When editing a CSV directly, put roles containing commas in double quotes.',
                  style: DefensysTokens.caption.copyWith(color: muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: widget.onDownload,
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Download Sample Template'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ink,
              side: BorderSide(color: border),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
              ),
              textStyle: DefensysTokens.caption.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
