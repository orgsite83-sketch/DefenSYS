import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../services/admin/reports_provider.dart';
import '../../theme/defensys_tokens.dart';
import 'defensys_export_models.dart';
import 'defensys_document_sheet.dart';
import 'defensys_pdf_viewer.dart';

/// Reusable right pane / main pane rendering structured live preview data.
/// The selected export format determines the document or table preview.
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
    this.includeSignatures = false,
    this.selectedFormat = 'pdf',
  });

  @override
  State<DefensysLiveDataPreviewPane> createState() =>
      _DefensysLiveDataPreviewPaneState();
}

class _DefensysLiveDataPreviewPaneState
    extends State<DefensysLiveDataPreviewPane> {
  final _searchController = TextEditingController();
  bool get _isDocumentView =>
      !const ['xlsx', 'excel', 'sheet', 'csv'].contains(widget.selectedFormat);
  double _zoomScale = 1.0;
  Uint8List? _pdfBytes;
  int _selectedSheet = 0;
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _pdfBytes = widget.previewData?.pdfBytes;
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant DefensysLiveDataPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previewData != widget.previewData) {
      _pdfBytes = widget.previewData?.pdfBytes;
      _selectedSheet = 0;
      _sortColumnIndex = null;
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
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DefensysTokens.textDark,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Fetching realtime evaluations, defense scores, and official institutional layout.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: DefensysTokens.steelGrey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.emptyStateOverride != null) {
      return widget.emptyStateOverride!;
    }

    final sourceData = widget.previewData;
    if (!_isDocumentView && sourceData != null) {
      if (sourceData.workbookSheets.isNotEmpty) {
        return _buildWorkbookView(sourceData);
      }
      if (sourceData.excelPreviewError != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.table_view_outlined,
                  color: DefensysTokens.steelGrey,
                  size: 32,
                ),
                const SizedBox(height: 12),
                Text(
                  sourceData.excelPreviewError!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: widget.onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh preview'),
                ),
              ],
            ),
          ),
        );
      }
    }
    final data = sourceData == null ? null : _sheetData(sourceData);
    if (data == null ||
        (_isDocumentView && data.rows.isEmpty && data.sections.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.dataset_linked_outlined,
                size: 40,
                color: DefensysTokens.steelGrey,
              ),
              const SizedBox(height: 12),
              const Text(
                'No data records found for current filter',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DefensysTokens.textDark,
                ),
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

    if (!_isDocumentView && _sortColumnIndex != null) {
      final col = data.columns[_sortColumnIndex!];
      displayRows.sort(
        (a, b) => _compareCells(a[col['key']], b[col['key']], col),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Format preview, zoom controls, and refresh
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
  Widget _buildWorkbookView(ReportPreviewData data) {
    final sheet = data.workbookSheets[_selectedSheet];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(bottom: BorderSide(color: DefensysTokens.border)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.table_view_outlined,
                size: 17,
                color: DefensysTokens.steelGrey,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Excel workbook preview',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.steelGrey,
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onRefresh,
                tooltip: 'Refresh workbook preview',
                icon: const Icon(Icons.refresh_rounded, size: 17),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
              ),
            ],
          ),
        ),
        if (data.workbookSheets.length > 1)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                const Text(
                  'Worksheet',
                  style: TextStyle(
                    fontSize: 11,
                    color: DefensysTokens.steelGrey,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedSheet,
                      isExpanded: true,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: DefensysTokens.textDark,
                      ),
                      items: [
                        for (final entry in data.workbookSheets.asMap().entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(
                              entry.value.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _selectedSheet = value ?? 0),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: DefensysPdfViewer(
            key: ValueKey(sheet.pdfBytes),
            pdfBytes: sheet.pdfBytes,
            title: sheet.name,
            documentType: 'Excel worksheet',
          ),
        ),
      ],
    );
  }

  Widget _buildTopToolbar(ReportPreviewData data, int displayRowCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: DefensysTokens.border)),
      ),
      child: Row(
        children: [
          Icon(
            _isDocumentView
                ? Icons.picture_as_pdf_outlined
                : Icons.table_view_rounded,
            size: 17,
            color: DefensysTokens.steelGrey,
          ),
          const SizedBox(width: 8),

          // Subtitle / Context Info
          Expanded(
            child: Text(
              _isDocumentView
                  ? 'PDF document preview'
                  : 'Excel data preview ($displayRowCount of ${data.totalRows} records)',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.steelGrey,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Zoom Controls (Fallback Sheet Mode Only)
          if (_isDocumentView && _pdfBytes == null) ...[
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
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
            icon: const Icon(
              Icons.refresh_rounded,
              size: 17,
              color: DefensysTokens.steelGrey,
            ),
            tooltip: 'Refresh dataset',
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
            onPressed: widget.onRefresh,
          ),
        ],
      ),
    );
  }

  /// 1. True Document Sheet View
  Widget _buildDocumentSheetView(ReportPreviewData data) {
    final pdfBytes = _pdfBytes;
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

  ReportPreviewData _sheetData(ReportPreviewData data) {
    if (_isDocumentView || _selectedSheet == 0) return data;
    final sheet = data.excelSheets[_selectedSheet - 1];
    final rows = (sheet['rows'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    return ReportPreviewData(
      title: sheet['title'].toString(),
      subtitle: '',
      generatedAt: data.generatedAt,
      summaryKpis: const [],
      columns: (sheet['columns'] as List)
          .map((col) => Map<String, dynamic>.from(col as Map))
          .toList(),
      rows: rows,
      totalRows: rows.length,
      excelHeader: (sheet['excel_header'] as List)
          .map((value) => value.toString())
          .toList(),
    );
  }

  int _compareCells(dynamic a, dynamic b, Map<String, dynamic> column) {
    final left = a?.toString() ?? '';
    final right = b?.toString() ?? '';
    final type = column['type'];
    num? leftNumber, rightNumber;
    if (const ['date', 'datetime'].contains(type)) {
      leftNumber = DateTime.tryParse(left)?.millisecondsSinceEpoch;
      rightNumber = DateTime.tryParse(right)?.millisecondsSinceEpoch;
    } else if (a is num ||
        b is num ||
        const ['percentage', 'number', 'integer'].contains(type)) {
      leftNumber = num.tryParse(left.replaceAll('%', '').replaceAll(',', ''));
      rightNumber = num.tryParse(right.replaceAll('%', '').replaceAll(',', ''));
    }
    // Pending/N/A stays after recorded numbers in either sort direction.
    if (leftNumber != null && rightNumber == null) return -1;
    if (leftNumber == null && rightNumber != null) return 1;
    final result = leftNumber != null && rightNumber != null
        ? leftNumber.compareTo(rightNumber)
        : left.toLowerCase().compareTo(right.toLowerCase());
    return _sortAscending ? result : -result;
  }

  /// Excel preview mirrors the merged headings and plain bordered workbook.
  Widget _buildRawDataTableView(
    ReportPreviewData data,
    List<Map<String, dynamic>> displayRows,
  ) {
    final sourceData = widget.previewData!;
    final widths = data.columns.map((col) {
      final units = (col['width'] as num?)?.toDouble() ?? 24;
      return (units * 7).clamp(112.0, 462.0);
    }).toList();
    final contextLine = data.excelHeader.length > 1
        ? data.excelHeader[1]
        : 'All matching records';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (sourceData.excelSheets.isNotEmpty) ...[
                DropdownButton<int>(
                  value: _selectedSheet,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: DefensysTokens.textDark,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('Report Data'),
                    ),
                    for (final entry in sourceData.excelSheets.asMap().entries)
                      DropdownMenuItem(
                        value: entry.key + 1,
                        child: Text(entry.value['name'].toString()),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _selectedSheet = value ?? 0;
                    _sortColumnIndex = null;
                    _searchController.clear();
                  }),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Filter table records...',
                      hintStyle: const TextStyle(
                        fontSize: 11.5,
                        color: DefensysTokens.steelGrey,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 15),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 13),
                              onPressed: _searchController.clear,
                            ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          DefensysTokens.radiusMd,
                        ),
                        borderSide: const BorderSide(
                          color: DefensysTokens.border,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${displayRows.length} of ${data.rows.length} rows',
                style: const TextStyle(
                  fontSize: 11,
                  color: DefensysTokens.steelGrey,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: const Color(0xFFF1F5F9),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (data.columns.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: IntrinsicWidth(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final heading in [data.title, contextLine])
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  border: Border(
                                    top: BorderSide(
                                      color: Colors.black,
                                      width: 0.6,
                                    ),
                                    left: BorderSide(
                                      color: Colors.black,
                                      width: 0.6,
                                    ),
                                    right: BorderSide(
                                      color: Colors.black,
                                      width: 0.6,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  heading,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: heading == data.title ? 13 : 11,
                                    fontWeight: heading == data.title
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            DataTable(
                              border: TableBorder.all(
                                color: Colors.black,
                                width: 0.6,
                              ),
                              headingRowHeight: 36,
                              dataRowMinHeight: 32,
                              dataRowMaxHeight: double.infinity,
                              headingRowColor: WidgetStateProperty.all(
                                Colors.white,
                              ),
                              horizontalMargin: 12,
                              columnSpacing: 24,
                              sortColumnIndex: _sortColumnIndex,
                              sortAscending: _sortAscending,
                              columns: data.columns
                                  .asMap()
                                  .entries
                                  .map(
                                    (entry) => DataColumn(
                                      onSort: (index, ascending) =>
                                          setState(() {
                                            _sortColumnIndex = index;
                                            _sortAscending = ascending;
                                          }),
                                      label: SizedBox(
                                        width: widths[entry.key],
                                        child: Text(
                                          entry.value['label']?.toString() ??
                                              '',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              rows: displayRows
                                  .map(
                                    (row) => DataRow(
                                      color: WidgetStateProperty.all(
                                        Colors.white,
                                      ),
                                      cells: data.columns.asMap().entries.map((
                                        entry,
                                      ) {
                                        final col = entry.value;
                                        return DataCell(
                                          SizedBox(
                                            width: widths[entry.key],
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 6,
                                                  ),
                                              child: Text(
                                                row[col['key']]?.toString() ??
                                                    '',
                                                softWrap: true,
                                                textAlign:
                                                    col['align'] == 'right'
                                                    ? TextAlign.right
                                                    : col['align'] == 'center'
                                                    ? TextAlign.center
                                                    : TextAlign.left,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.black,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (displayRows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No matching records found in table.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: DefensysTokens.steelGrey,
                        ),
                      ),
                    ),
                  if (_selectedSheet == 0 &&
                      widget.includeSignatures &&
                      widget.signatories.isNotEmpty)
                    _buildExcelSignatories(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExcelSignatories() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Signatories',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          for (final signer in widget.signatories)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(signer.label, style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 24),
                    const Divider(height: 1, color: DefensysTokens.textDark),
                    const SizedBox(height: 4),
                    Text(
                      signer.name,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(signer.role, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
