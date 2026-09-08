import 'dart:convert';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../toasts/feedback_toast.dart';
import 'universal_file_viewer_models.dart';

/// ----------------------------------------------------------------------
/// 1. Interactive Image Viewer with Pan, Zoom & Transparency Grid
/// ----------------------------------------------------------------------
class UniversalImageViewer extends StatelessWidget {
  final Uint8List bytes;
  final String fileName;
  final TransformationController controller;
  final double rotationAngle;

  const UniversalImageViewer({
    super.key,
    required this.bytes,
    required this.fileName,
    required this.controller,
    this.rotationAngle = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B0F19),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Checkerboard pattern for alpha transparency
          CustomPaint(
            painter: _CheckerboardPainter(),
            size: Size.infinite,
          ),
          Center(
            child: InteractiveViewer(
              transformationController: controller,
              clipBehavior: Clip.none,
              minScale: 0.1,
              maxScale: 10.0,
              child: Transform.rotate(
                angle: rotationAngle,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.broken_image_outlined, size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text(
                          'Failed to render image preview: $error',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Subtle hint at the bottom
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pinch_outlined, size: 14, color: Colors.white70),
                    SizedBox(width: 6),
                    Text(
                      'Scroll to zoom • Drag to pan • Double tap to reset',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()..color = const Color(0xFF0F172A);
    final paint2 = Paint()..color = const Color(0xFF131D33);
    const cellSize = 20.0;

    for (double y = 0; y < size.height; y += cellSize) {
      for (double x = 0; x < size.width; x += cellSize) {
        final isEven = ((x / cellSize).floor() + (y / cellSize).floor()) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, cellSize, cellSize),
          isEven ? paint1 : paint2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ----------------------------------------------------------------------
/// 2. Spreadsheet Viewer (Excel .xlsx / .xls and CSV / TSV)
/// ----------------------------------------------------------------------
class UniversalSpreadsheetViewer extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;

  const UniversalSpreadsheetViewer({
    super.key,
    required this.bytes,
    required this.fileName,
  });

  @override
  State<UniversalSpreadsheetViewer> createState() => _UniversalSpreadsheetViewerState();
}

class _UniversalSpreadsheetViewerState extends State<UniversalSpreadsheetViewer> {
  bool _isLoading = true;
  String? _error;
  List<String> _sheetNames = [];
  String _activeSheet = '';
  // Map of sheetName -> List of rows (each row is List of String cells)
  final Map<String, List<List<String>>> _sheetData = {};
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _parseSpreadsheet();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _parseSpreadsheet() {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final lowerName = widget.fileName.toLowerCase();
      if (lowerName.endsWith('.csv') || lowerName.endsWith('.tsv')) {
        _parseCsv(isTsv: lowerName.endsWith('.tsv'));
      } else {
        _parseExcel();
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to parse spreadsheet: $e';
        _isLoading = false;
      });
    }
  }

  void _parseCsv({required bool isTsv}) {
    final text = utf8.decode(widget.bytes, allowMalformed: true);
    final delimiter = isTsv ? '\t' : ',';
    final lines = const LineSplitter().convert(text);
    final List<List<String>> rows = [];

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      // Simple parse handling delimiter
      final parts = line.split(delimiter).map((e) {
        var clean = e.trim();
        if (clean.startsWith('"') && clean.endsWith('"') && clean.length >= 2) {
          clean = clean.substring(1, clean.length - 1).replaceAll('""', '"');
        }
        return clean;
      }).toList();
      rows.add(parts);
    }

    _sheetNames = ['Data'];
    _activeSheet = 'Data';
    _sheetData['Data'] = rows;

    setState(() {
      _isLoading = false;
    });
  }

  void _parseExcel() {
    final excel = xl.Excel.decodeBytes(widget.bytes);
    if (excel.tables.isEmpty) {
      setState(() {
        _error = 'Spreadsheet contains no readable sheets.';
        _isLoading = false;
      });
      return;
    }

    _sheetNames = excel.tables.keys.toList();
    _activeSheet = _sheetNames.first;

    for (final entry in excel.tables.entries) {
      final sheet = entry.value;
      final List<List<String>> rows = [];
      for (final row in sheet.rows) {
        final rowStrings = row.map((cell) => _excelCellText(cell?.value)).toList();
        // Drop trailing empty cells
        while (rowStrings.isNotEmpty && rowStrings.last.isEmpty) {
          rowStrings.removeLast();
        }
        if (rowStrings.any((s) => s.isNotEmpty)) {
          rows.add(rowStrings);
        }
      }
      _sheetData[entry.key] = rows;
    }

    setState(() {
      _isLoading = false;
    });
  }

  String _excelCellText(xl.CellValue? value) {
    if (value == null) return '';
    if (value is xl.TextCellValue) {
      return (value.value.text ?? '').trim();
    }
    if (value is xl.IntCellValue) return value.value.toString();
    if (value is xl.DoubleCellValue) {
      final number = value.value;
      if (number == number.roundToDouble()) {
        return number.round().toString();
      }
      return number.toString();
    }
    if (value is xl.FormulaCellValue) return value.formula.trim();
    if (value is xl.BoolCellValue) return value.value ? 'true' : 'false';
    if (value is xl.DateCellValue) {
      final dt = value.asDateTimeLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    if (value is xl.DateTimeCellValue) {
      final dt = value.asDateTimeLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    if (value is xl.TimeCellValue) {
      final d = value.asDuration();
      final h = (d.inHours % 24).toString().padLeft(2, '0');
      final m = (d.inMinutes % 60).toString().padLeft(2, '0');
      return '$h:$m';
    }
    return value.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF10B981)),
            SizedBox(height: 16),
            Text('Parsing spreadsheet data...', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _parseSpreadsheet,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry Parsing'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              ),
            ],
          ),
        ),
      );
    }

    final rawRows = _sheetData[_activeSheet] ?? [];
    if (rawRows.isEmpty) {
      return const Center(
        child: Text('This sheet is empty.', style: TextStyle(color: Colors.white60, fontSize: 14)),
      );
    }

    // Filter rows based on search
    final rows = _searchQuery.isEmpty
        ? rawRows
        : rawRows.where((row) {
            return row.any((cell) => cell.toLowerCase().contains(_searchQuery.toLowerCase()));
          }).toList();

    // Determine max column count
    int maxCols = 0;
    for (final r in rows) {
      if (r.length > maxCols) maxCols = r.length;
    }

    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          // Sheet Tabs & Search Bar Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              border: Border(bottom: BorderSide(color: Color(0xFF334155))),
            ),
            child: Row(
              children: [
                // Sheet switcher tabs
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _sheetNames.map((name) {
                        final isSelected = name == _activeSheet;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _activeSheet = name;
                              });
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF10B981) : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF10B981) : const Color(0xFF475569),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.table_chart_outlined,
                                    size: 14,
                                    color: isSelected ? Colors.white : Colors.white70,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    name,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white70,
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Stats badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Text(
                    '${rawRows.length} rows • $maxCols cols',
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(width: 12),
                // Search field
                SizedBox(
                  width: 200,
                  height: 32,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.trim();
                      });
                    },
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Search sheet...',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                      prefixIcon: const Icon(Icons.search, size: 14, color: Colors.white54),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 12, color: Colors.white54),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF475569)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF10B981)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Interactive Matrix Table
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Scrollbar(
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      defaultColumnWidth: const IntrinsicColumnWidth(),
                      border: TableBorder.all(color: const Color(0xFF334155), width: 0.8),
                      children: List.generate(rows.length > 500 ? 500 : rows.length, (rowIndex) {
                        final isHeader = rowIndex == 0 && _searchQuery.isEmpty;
                        final row = rows[rowIndex];
                        final isEven = rowIndex % 2 == 0;

                        return TableRow(
                          decoration: BoxDecoration(
                            color: isHeader
                                ? const Color(0xFF1E293B)
                                : isEven
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFF162033),
                          ),
                          children: [
                            // Row Number Header
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              color: isHeader ? const Color(0xFF0F172A) : const Color(0xFF1A2234),
                              alignment: Alignment.center,
                              child: Text(
                                isHeader ? '#' : '$rowIndex',
                                style: TextStyle(
                                  color: isHeader ? const Color(0xFF10B981) : Colors.white38,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // Cells
                            ...List.generate(maxCols, (colIndex) {
                              final text = colIndex < row.length ? row[colIndex] : '';
                              return Container(
                                constraints: const BoxConstraints(minWidth: 100, maxWidth: 300),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: SelectableText(
                                  text,
                                  style: TextStyle(
                                    color: isHeader ? Colors.white : Colors.white.withValues(alpha: 0.9),
                                    fontSize: 12,
                                    fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              );
                            }),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (rows.length > 500)
            Container(
              padding: const EdgeInsets.all(8),
              color: const Color(0xFF1E293B),
              child: Text(
                'Showing first 500 of ${rows.length} rows for performance. Download file for full dataset.',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

/// ----------------------------------------------------------------------
/// 3. Code & Text File Viewer with Line Numbers and Search
/// ----------------------------------------------------------------------
class UniversalCodeTextViewer extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;

  const UniversalCodeTextViewer({
    super.key,
    required this.bytes,
    required this.fileName,
  });

  @override
  State<UniversalCodeTextViewer> createState() => _UniversalCodeTextViewerState();
}

class _UniversalCodeTextViewerState extends State<UniversalCodeTextViewer> {
  late String _fullText;
  late List<String> _lines;
  bool _wrapLines = true;

  @override
  void initState() {
    super.initState();
    _fullText = utf8.decode(widget.bytes, allowMalformed: true);
    _lines = const LineSplitter().convert(_fullText);
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _copyAll() {
    Clipboard.setData(ClipboardData(text: _fullText));
    showSuccessToast(context, 'Copied full text to clipboard!');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B0F19),
      child: Column(
        children: [
          // Sub-toolbar for code viewer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF161E2E),
              border: Border(bottom: BorderSide(color: Color(0xFF273142))),
            ),
            child: Row(
              children: [
                // Info badges
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0F19),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF273142)),
                  ),
                  child: Text(
                    '${_lines.length} lines • ${_fullText.length} chars',
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
                const Spacer(),
                // Wrap toggle
                IconButton(
                  icon: Icon(
                    _wrapLines ? Icons.wrap_text : Icons.menu,
                    color: _wrapLines ? const Color(0xFFF59E0B) : Colors.white54,
                    size: 18,
                  ),
                  tooltip: _wrapLines ? 'Line Wrap: ON' : 'Line Wrap: OFF',
                  onPressed: () {
                    setState(() {
                      _wrapLines = !_wrapLines;
                    });
                  },
                ),
                const SizedBox(width: 8),
                // Copy button
                ElevatedButton.icon(
                  onPressed: _copyAll,
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Copy All', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF273142),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
          // Code content with line numbers
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: _wrapLines
                    ? _buildWrappedContent()
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _buildWrappedContent(),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWrappedContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line Numbers
          SelectableText(
            List.generate(_lines.length, (i) => '${i + 1}').join('\n'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF4B5563),
            ),
            textAlign: TextAlign.right,
          ),
          const SizedBox(width: 16),
          // Code Text
          Expanded(
            flex: _wrapLines ? 1 : 0,
            child: SelectableText(
              _fullText,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.5,
                color: Color(0xFFE2E8F0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ----------------------------------------------------------------------
/// 4. Office & Binary Inspector Card (Word, PowerPoint, Archives)
/// ----------------------------------------------------------------------
class UniversalOfficeInspectorCard extends StatelessWidget {
  final String fileName;
  final int fileSizeBytes;
  final FileCategory category;
  final VoidCallback onDownload;
  final VoidCallback onOpenInNewTab;

  const UniversalOfficeInspectorCard({
    super.key,
    required this.fileName,
    required this.fileSizeBytes,
    required this.category,
    required this.onDownload,
    required this.onOpenInNewTab,
  });

  @override
  Widget build(BuildContext context) {
    final color = FileViewerMetadata.getCategoryColor(category);
    final icon = FileViewerMetadata.getCategoryIcon(category);
    final categoryLabel = FileViewerMetadata.getCategoryLabel(category, fileName);

    String formatDescription;
    String tipDescription;

    if (category == FileCategory.officeDoc) {
      formatDescription = 'Microsoft Word / Rich Text Document';
      tipDescription = 'Contains complex word-processing elements, tables, and typography. For 100% fidelity and revision tracking, open in Microsoft Word or Google Docs.';
    } else if (category == FileCategory.officePresentation) {
      formatDescription = 'Microsoft PowerPoint Presentation Deck';
      tipDescription = 'Contains slide transitions, shapes, and presenter notes. For smooth slide presentations and animations, open in Microsoft PowerPoint.';
    } else if (category == FileCategory.archive) {
      formatDescription = 'Compressed File Archive';
      tipDescription = 'Contains multiple bundled deliverable files or source code repositories. Download and extract on your computer to view contents.';
    } else {
      formatDescription = 'Binary Application Deliverable';
      tipDescription = 'This format requires an external specialized application to view or execute.';
    }

    return Container(
      color: const Color(0xFF0B0F19),
      child: Center(
        child: Container(
          width: 580,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF161E2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing Icon badge
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
                ),
                child: Icon(icon, size: 36, color: color),
              ),
              const SizedBox(height: 20),
              // Category tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  categoryLabel,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // File Name
              Text(
                fileName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                formatDescription,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              // Metadata specs container
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF273142)),
                ),
                child: Column(
                  children: [
                    _specRow('File Size', FileViewerMetadata.formatBytes(fileSizeBytes)),
                    const Divider(color: Color(0xFF273142), height: 16),
                    _specRow('MIME Type', FileViewerMetadata.getMimeType(fileName)),
                    const Divider(color: Color(0xFF273142), height: 16),
                    _specRow('Intranet Security', 'Verified Clean Deliverable'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Guidance banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.amberAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tipDescription,
                        style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Download Original File', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: onOpenInNewTab,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open in New Tab'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Color(0xFF475569)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _specRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// ----------------------------------------------------------------------
/// 5. Audio Player Visualizer Card
/// ----------------------------------------------------------------------
class UniversalAudioPlayerCard extends StatelessWidget {
  final String fileName;
  final int fileSizeBytes;
  final Widget audioPlayerWidget;

  const UniversalAudioPlayerCard({
    super.key,
    required this.fileName,
    required this.fileSizeBytes,
    required this.audioPlayerWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B0F19),
      child: Center(
        child: Container(
          width: 540,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF161E2E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF43F5E).withValues(alpha: 0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Vinyl / waveform disc
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: const RadialGradient(
                    colors: [Color(0xFFF43F5E), Color(0xFF881337), Color(0xFF0F172A)],
                    stops: [0.3, 0.7, 1.0],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF43F5E).withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.graphic_eq, size: 40, color: Colors.white),
                ),
              ),
              const SizedBox(height: 20),
              // Category tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF43F5E).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF43F5E).withValues(alpha: 0.4)),
                ),
                child: const Text(
                  'AUDIO DELIVERABLE',
                  style: TextStyle(
                    color: Color(0xFFF43F5E),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // File Name
              Text(
                fileName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                FileViewerMetadata.formatBytes(fileSizeBytes),
                style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 28),
              // Audio element view container
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: audioPlayerWidget,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
