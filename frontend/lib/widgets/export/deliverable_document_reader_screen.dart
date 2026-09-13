import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../theme/defensys_tokens.dart';
import '../../toasts/feedback_toast.dart';
import '../../utils/universal_file_viewer.dart';

/// Available reading display themes for the document reader.
enum DeliverableReaderTheme {
  day(name: 'Day', bg: Color(0xFFF8FAFC), fg: Color(0xFF0F172A), appBarBg: DefensysTokens.maroon),
  sepia(name: 'Sepia', bg: Color(0xFFFBF0D9), fg: Color(0xFF3E2723), appBarBg: Color(0xFF5D4037)),
  night(name: 'Night', bg: Color(0xFF18181B), fg: Color(0xFFF4F4F5), appBarBg: Color(0xFF18181B));

  final String name;
  final Color bg;
  final Color fg;
  final Color appBarBg;

  const DeliverableReaderTheme({
    required this.name,
    required this.bg,
    required this.fg,
    required this.appBarBg,
  });
}

/// A dedicated, full-screen document reader container for student deliverables.
/// Features page indicator, theme selector, zoom controls, and direct download,
/// strictly without security watermarks since this is the student's own submission.
class DeliverableDocumentReaderScreen extends StatefulWidget {
  final Uint8List fileBytes;
  final String fileName;
  final String? deliverableLabel;
  final String? stageLabel;
  final String? teamName;
  final DeliverablePropertiesInfo? propertiesInfo;

  const DeliverableDocumentReaderScreen({
    super.key,
    required this.fileBytes,
    required this.fileName,
    this.deliverableLabel,
    this.stageLabel,
    this.teamName,
    this.propertiesInfo,
  });

  @override
  State<DeliverableDocumentReaderScreen> createState() =>
      _DeliverableDocumentReaderScreenState();
}

class _DeliverableDocumentReaderScreenState
    extends State<DeliverableDocumentReaderScreen> {
  late PdfViewerController _pdfViewerController;
  int _currentPage = 1;
  int _pageCount = 1;
  DeliverableReaderTheme _currentTheme = DeliverableReaderTheme.day;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
  }

  @override
  void dispose() {
    _pdfViewerController.dispose();
    super.dispose();
  }

  Future<void> _handleDownload() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    showSuccessToast(
      context,
      'Downloading ${widget.fileName}...',
      duration: const Duration(seconds: 2),
    );

    try {
      await downloadBytesFile(
        bytes: widget.fileBytes,
        fileName: widget.fileName,
        mimeType: 'application/pdf',
      );
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Failed to save file: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  void _onPageChanged(PdfPageChangedDetails details) {
    if (!mounted) return;
    setState(() {
      _currentPage = details.newPageNumber;
      _pageCount = _pdfViewerController.pageCount > 0
          ? _pdfViewerController.pageCount
          : _pageCount;
    });
  }

  void _onDocumentLoaded(PdfDocumentLoadedDetails details) {
    if (!mounted) return;
    setState(() {
      _pageCount = details.document.pages.count;
    });
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.palette_outlined, size: 20, color: DefensysTokens.maroon),
            SizedBox(width: 8),
            Text('Reader Display Theme', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: DeliverableReaderTheme.values.map((t) {
            final isSelected = _currentTheme == t;
            return ListTile(
              leading: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: t.bg,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade400, width: 1.5),
                ),
              ),
              title: Text(
                t.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check_circle_rounded, color: DefensysTokens.maroon, size: 20)
                  : null,
              onTap: () {
                setState(() => _currentTheme = t);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showFilePropertiesModal() {
    final info = widget.propertiesInfo;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: DefensysTokens.maroon, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'File Properties & Info',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: DefensysTokens.textPrimary),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(height: 20),
            _propRow('File Name', widget.fileName),
            _propRow('Type', info?.fileType ?? 'PDF Document'),
            if (widget.stageLabel != null) _propRow('Stage', widget.stageLabel!),
            if (info?.fileSize != null) _propRow('Size', info!.fileSize!),
            if (info?.uploader != null) _propRow('Uploaded By', info!.uploader!),
            if (info?.timestamp != null) _propRow('Submission Date', info!.timestamp!),
            if (info?.status != null) _propRow('Status', info!.status!.toUpperCase()),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _propRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtitleText = [
      if (widget.stageLabel != null && widget.stageLabel!.isNotEmpty) widget.stageLabel,
      'Page $_currentPage of $_pageCount',
    ].join(' · ');

    return Scaffold(
      backgroundColor: _currentTheme.bg,
      appBar: AppBar(
        backgroundColor: _currentTheme.appBarBg,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to Deliverables',
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.deliverableLabel ?? widget.fileName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitleText,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          // Zoom In / Zoom Out Controls
          IconButton(
            tooltip: 'Zoom In',
            icon: const Icon(Icons.zoom_in_rounded, size: 20),
            onPressed: () => _pdfViewerController.zoomLevel = (_pdfViewerController.zoomLevel + 0.25).clamp(1.0, 3.0),
          ),
          IconButton(
            tooltip: 'Zoom Out',
            icon: const Icon(Icons.zoom_out_rounded, size: 20),
            onPressed: () => _pdfViewerController.zoomLevel = (_pdfViewerController.zoomLevel - 0.25).clamp(1.0, 3.0),
          ),
          // Theme Picker
          IconButton(
            tooltip: 'Reading theme',
            icon: const Icon(Icons.palette_outlined, size: 20),
            onPressed: _showThemeDialog,
          ),
          // Properties Info
          IconButton(
            tooltip: 'File Properties',
            icon: const Icon(Icons.info_outline_rounded, size: 20),
            onPressed: _showFilePropertiesModal,
          ),
          // Download Student's Own File
          IconButton(
            tooltip: 'Download File',
            icon: _isDownloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.download_rounded, size: 20),
            onPressed: _isDownloading ? null : _handleDownload,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SfPdfViewerTheme(
        data: SfPdfViewerThemeData(
          backgroundColor: _currentTheme.bg,
        ),
        child: SfPdfViewer.memory(
          widget.fileBytes,
          controller: _pdfViewerController,
          canShowScrollHead: true,
          canShowScrollStatus: true,
          enableDoubleTapZooming: true,
          enableTextSelection: true,
          pageLayoutMode: PdfPageLayoutMode.continuous,
          pageSpacing: 16.0,
          onPageChanged: _onPageChanged,
          onDocumentLoaded: _onDocumentLoaded,
        ),
      ),
    );
  }
}
