import 'package:flutter/material.dart';
import '../../services/admin/reports_provider.dart';
import '../../theme/defensys_tokens.dart';
import 'defensys_export_models.dart';
import 'defensys_document_sheet.dart';
import 'defensys_pdf_viewer.dart';

/// Reusable right pane / main pane rendering structured live preview data.
/// Supports both True Institutional Document Sheet Preview and Raw Data Grid mode.
class DefensysLiveDataPreviewPane extends StatefulWidget {
  final bool isLoading;
  final ReportPreviewData? previewData;
  final VoidCallback onRefresh;
  final Widget? emptyStateOverride;
  final List<DefensysSignatory> signatories;
  final bool includeSignatures;
  final String selectedFormat;

  const DefensysLiveDataPreviewPane({
    super.key,
    required this.isLoading,
    required this.previewData,
    required this.onRefresh,
    this.emptyStateOverride,
    this.signatories = const [],
    this.includeSignatures = true,
    this.selectedFormat = 'pdf',
  });

  @override
  State<DefensysLiveDataPreviewPane> createState() => _DefensysLiveDataPreviewPaneState();
}

class _DefensysLiveDataPreviewPaneState extends State<DefensysLiveDataPreviewPane> {
  final _searchController = TextEditingController();
  bool _isDocumentView = true;
  double _zoomScale = 1.0;

  @override
  void initState() {
    super.initState();
    final isTabular = widget.selectedFormat == 'xlsx' ||
        widget.selectedFormat == 'csv' ||
        widget.selectedFormat == 'sheet';
    _isDocumentView = !isTabular;
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant DefensysLiveDataPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFormat != widget.selectedFormat) {
      final isTabular = widget.selectedFormat == 'xlsx' ||
          widget.selectedFormat == 'csv' ||
          widget.selectedFormat == 'sheet';
      setState(() {
        _isDocumentView = !isTabular;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    setState(() {
      if (_zoomScale < 1.35) _zoomScale = (_zoomScale + 0.1).clamp(0.7, 1.4);
    });
  }

  void _zoomOut() {
    setState(() {
      if (_zoomScale > 0.75) _zoomScale = (_zoomScale - 0.1).clamp(0.7, 1.4);
    });
  }

  void _resetZoom() {
    setState(() {
      _zoomScale = 1.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: DefensysTokens.maroon),
              SizedBox(height: 16),
              Text(
                'Compiling live report document...',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DefensysTokens.textDark),
              ),
              SizedBox(height: 4),
              Text(
                'Fetching realtime evaluations, defense scores, and official institutional layout.',
                style: TextStyle(fontSize: 11.5, color: DefensysTokens.steelGrey),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.emptyStateOverride != null) {
      return widget.emptyStateOverride!;
    }

    final data = widget.previewData;
    if (data == null || (data.rows.isEmpty && data.sections.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.dataset_linked_outlined, size: 40, color: DefensysTokens.steelGrey),
              const SizedBox(height: 12),
              const Text(
                'No data records found for current filter',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DefensysTokens.textDark),
              ),
              const SizedBox(height: 4),
              const Text(
                'Try adjusting the semester or filter criteria on the left.',
                style: TextStyle(fontSize: 12, color: DefensysTokens.steelGrey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh Data'),
                onPressed: widget.onRefresh,
              ),
            ],
          ),
        ),
      );
    }

    // Filter rows by in-viewer search for Data Table mode
    final query = _searchController.text.trim().toLowerCase();
    final displayRows = data.rows.where((row) {
      if (query.isEmpty) return true;
      for (final val in row.values) {
        if (val != null && val.toString().toLowerCase().contains(query)) {
          return true;
        }
      }
      return false;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Institutional Toolbar (View Switcher + Zoom Controls + Refresh)
        _buildTopToolbar(data, displayRows.length),

        // Main Preview Area (Document Sheet vs Raw Data Table)
        Expanded(
          child: _isDocumentView
              ? _buildDocumentSheetView(data)
              : _buildRawDataTableView(data, displayRows),
        ),
      ],
    );
  }

  /// Top Institutional Toolbar
  Widget _buildTopToolbar(ReportPreviewData data, int displayRowCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: DefensysTokens.border)),
      ),
      child: Row(
        children: [
          // View Mode Switcher Pills
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModePill(
                  label: 'Document Sheet',
                  icon: Icons.description_rounded,
                  isSelected: _isDocumentView,
                  onTap: () => setState(() => _isDocumentView = true),
                ),
                _buildModePill(
                  label: 'Data Table',
                  icon: Icons.table_chart_rounded,
                  isSelected: !_isDocumentView,
                  onTap: () => setState(() => _isDocumentView = false),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Subtitle / Context Info
          Expanded(
            child: Text(
              _isDocumentView
                  ? (data.pdfBytes != null
                      ? 'Official Document Preview — Dynamic output matching exact PDF export'
                      : 'Official Document Preview (Multi-Page) — Mirrored letterheads, sidebars, and signatures')
                  : 'Viewing $displayRowCount of ${data.totalRows} raw records',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.steelGrey,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Zoom Controls (Fallback Sheet Mode Only)
          if (_isDocumentView && data.pdfBytes == null) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_rounded, size: 14),
                    tooltip: 'Zoom Out',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: _zoomOut,
                  ),
                  InkWell(
                    onTap: _resetZoom,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        '${(_zoomScale * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: DefensysTokens.textDark,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, size: 14),
                    tooltip: 'Zoom In',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: _zoomIn,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Refresh Button
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 17, color: DefensysTokens.steelGrey),
            tooltip: 'Refresh dataset',
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
            onPressed: widget.onRefresh,
          ),
        ],
      ),
    );
  }

  Widget _buildModePill({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
            boxShadow: isSelected
                ? const [
                    BoxShadow(
                      color: Color(0x10000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? DefensysTokens.maroon : DefensysTokens.steelGrey,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? DefensysTokens.maroon : DefensysTokens.steelGrey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 1. True Document Sheet View
  Widget _buildDocumentSheetView(ReportPreviewData data) {
    final pdfBytes = data.pdfBytes;
    if (pdfBytes != null && pdfBytes.isNotEmpty) {
      return DefensysPdfViewer(
        key: ValueKey(pdfBytes),
        pdfBytes: pdfBytes,
        title: data.title,
      );
    }

    return Container(
      color: const Color(0xFFE5E9F0),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DefensysDocumentSheet(
          previewData: data,
          signatories: widget.signatories,
          includeSignatures: widget.includeSignatures,
          scale: _zoomScale,
        ),
      ),
    );
  }

  /// 2. Raw Data Table View
  Widget _buildRawDataTableView(ReportPreviewData data, List<Map<String, dynamic>> displayRows) {
    return Column(
      children: [
        // KPI Summary Cards
        if (data.summaryKpis.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: DefensysTokens.border)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: data.summaryKpis.map((kpi) {
                  final label = kpi['label']?.toString() ?? '';
                  final val = kpi['value']?.toString() ?? '';
                  final badge = kpi['badge']?.toString();

                  return Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                      border: Border.all(color: DefensysTokens.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: DefensysTokens.steelGrey,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              val,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: DefensysTokens.textDark,
                              ),
                            ),
                            if (badge != null && badge.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: badge.contains('MEET') || badge.contains('PASS')
                                      ? DefensysTokens.successBg
                                      : DefensysTokens.dangerBg,
                                  borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                ),
                                child: Text(
                                  badge,
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    color: badge.contains('MEET') || badge.contains('PASS')
                                        ? DefensysTokens.successText
                                        : DefensysTokens.dangerText,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

        // Search Input Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Filter table records...',
                      hintStyle: const TextStyle(fontSize: 11.5, color: DefensysTokens.steelGrey),
                      prefixIcon: const Icon(Icons.search_rounded, size: 15, color: DefensysTokens.steelGrey),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 13),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: const BorderSide(color: DefensysTokens.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: const BorderSide(color: DefensysTokens.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                ),
                child: Text(
                  '${displayRows.length} of ${data.rows.length} rows',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: DefensysTokens.steelGrey),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1, color: Color(0xFFF1F5F9)),

        // Data Table
        Expanded(
          child: displayRows.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No matching records found in table.',
                      style: TextStyle(fontSize: 12.5, color: DefensysTokens.steelGrey),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 620),
                      child: DataTable(
                        headingRowHeight: 36,
                        dataRowMinHeight: 32,
                        dataRowMaxHeight: 44,
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                        horizontalMargin: 14,
                        columnSpacing: 16,
                        columns: data.columns.map((col) {
                          final label = col['label']?.toString() ?? '';
                          final align = col['align']?.toString() ?? 'left';

                          return DataColumn(
                            numeric: align == 'center' || align == 'right',
                            label: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: DefensysTokens.textDark,
                                letterSpacing: 0.3,
                              ),
                            ),
                          );
                        }).toList(),
                        rows: displayRows.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final row = entry.value;
                          final isStripe = idx % 2 == 1;

                          return DataRow(
                            color: WidgetStateProperty.all(
                              isStripe ? const Color(0xFFFAFAFA) : Colors.white,
                            ),
                            cells: data.columns.map((col) {
                              final key = col['key']?.toString() ?? '';
                              final val = row[key]?.toString() ?? '';
                              final align = col['align']?.toString() ?? 'left';

                              final isPassed = val == 'PASSED' || val == 'ACTIVE' || val == 'Proficient';
                              final isFailed = val == 'FAILED' || val == 'REVISION' || val == 'Action Needed';
                              final isSpecial = isPassed || isFailed;

                              if (isSpecial) {
                                return DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isPassed ? DefensysTokens.successBg : DefensysTokens.dangerBg,
                                      borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                                    ),
                                    child: Text(
                                      val,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: isPassed ? DefensysTokens.successText : DefensysTokens.dangerText,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              return DataCell(
                                Align(
                                  alignment: align == 'center'
                                      ? Alignment.center
                                      : align == 'right'
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                  child: Text(
                                    val,
                                    style: const TextStyle(fontSize: 11, color: DefensysTokens.textDark),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
