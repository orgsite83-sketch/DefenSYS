import 'package:flutter/foundation.dart';
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
  double _zoomLevel = 1;
  int _pageCount = 0;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
  }

  @override
  void didUpdateWidget(covariant DefensysPdfViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.pdfBytes, widget.pdfBytes)) {
      _pageCount = 0;
      _loadFailed = false;
      _zoomLevel = 1;
      _pdfController.zoomLevel = 1;
    }
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    // PDF pages are rasterized at this density by Syncfusion. Supersample on
    // standard-density web screens so small table text survives downscaling.
    final renderPixelRatio = kIsWeb && mediaQuery.devicePixelRatio < 2
        ? 2.0
        : mediaQuery.devicePixelRatio;
    return Container(
      color: const Color(
        0xFFE2E8F0,
      ), // Clean light neutral background matching DefenSYS
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 400;
              void fitWidth() => _pdfController.zoomLevel = 1;
              return Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                color: Colors.white,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _pageCount == 0
                            ? (compact ? 'PDF' : 'PDF preview')
                            : '$_pageCount ${_pageCount == 1 ? 'page' : 'pages'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Zoom out',
                      icon: const Icon(Icons.remove_rounded, size: 17),
                      onPressed: _pageCount > 0 && _zoomLevel > 1
                          ? () => _pdfController.zoomLevel = (_zoomLevel - 0.25)
                                .clamp(1.0, 3.0)
                          : null,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    TextButton(
                      onPressed: _pageCount > 0
                          ? () => _pdfController.zoomLevel = 1
                          : null,
                      child: Text('${(_zoomLevel * 100).round()}%'),
                    ),
                    IconButton(
                      tooltip: 'Zoom in',
                      icon: const Icon(Icons.add_rounded, size: 17),
                      onPressed: _pageCount > 0 && _zoomLevel < 3
                          ? () => _pdfController.zoomLevel = (_zoomLevel + 0.25)
                                .clamp(1.0, 3.0)
                          : null,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    if (compact)
                      IconButton(
                        tooltip: 'Fit width',
                        onPressed: _pageCount > 0 ? fitWidth : null,
                        icon: const Icon(Icons.fit_screen_rounded, size: 17),
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        padding: EdgeInsets.zero,
                      )
                    else
                      TextButton.icon(
                        onPressed: _pageCount > 0 ? fitWidth : null,
                        icon: const Icon(Icons.fit_screen_rounded, size: 16),
                        label: const Text(
                          'Fit width',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: _loadFailed
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Unable to preview this PDF. Try opening or downloading the file.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF475569)),
                      ),
                    ),
                  )
                : MediaQuery(
                    data: mediaQuery.copyWith(
                      devicePixelRatio: renderPixelRatio,
                    ),
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
                        onDocumentLoaded: (_) {
                          if (!mounted) return;
                          setState(() {
                            _pageCount = _pdfController.pageCount;
                            _loadFailed = false;
                            _zoomLevel = _pdfController.zoomLevel;
                          });
                        },
                        onDocumentLoadFailed: (_) {
                          if (!mounted) return;
                          setState(() => _loadFailed = true);
                        },
                        onZoomLevelChanged: (details) {
                          if (!mounted) return;
                          setState(() => _zoomLevel = details.newZoomLevel);
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
