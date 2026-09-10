import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

/// Clean, institutional PDF Document Viewer rendered via Flutter Canvas.
/// Eliminates dark-mode browser header toolbars and provides seamless light-theme styling.
class DefensysPdfViewer extends StatefulWidget {
  final Uint8List pdfBytes;
  final String title;

  const DefensysPdfViewer({
    super.key,
    required this.pdfBytes,
    this.title = 'Document Preview',
  });

  @override
  State<DefensysPdfViewer> createState() => _DefensysPdfViewerState();
}

class _DefensysPdfViewerState extends State<DefensysPdfViewer> {
  late PdfViewerController _pdfController;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
  }

  @override
  void didUpdateWidget(covariant DefensysPdfViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If bytes changed, controller maintains position or can be refreshed
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE2E8F0), // Clean light neutral background matching DefenSYS
      child: SfPdfViewerTheme(
        data: const SfPdfViewerThemeData(
          backgroundColor: Color(0xFFE2E8F0),
        ),
        child: SfPdfViewer.memory(
          widget.pdfBytes,
          controller: _pdfController,
          canShowScrollHead: true,
          canShowScrollStatus: true,
          enableDoubleTapZooming: true,
          pageLayoutMode: PdfPageLayoutMode.continuous,
          pageSpacing: 16.0,
        ),
      ),
    );
  }
}
