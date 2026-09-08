// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/defensys_tokens.dart';
import '../../toasts/feedback_toast.dart';
import 'universal_file_viewer_models.dart';
import 'universal_file_viewer_widgets.dart';

/// Triggers a browser file download from in-memory bytes.
Future<void> downloadBytesFile({
  required List<int> bytes,
  required String fileName,
  String mimeType = 'application/octet-stream',
}) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

/// Universal file viewer dialog supporting PDFs, Videos, Audio, Images,
/// Spreadsheets (Excel/CSV), Code/Text files, and Office Document Inspection.
Future<void> viewFileInDialog({
  required BuildContext context,
  required List<int> fileBytes,
  required String fileName,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (dialogContext) => UniversalFileViewerDialog(
      fileBytes: fileBytes,
      fileName: fileName,
    ),
  );
}

/// Legacy alias for backward compatibility.
Future<void> viewPdfInDialog({
  required BuildContext context,
  required List<int> pdfBytes,
  required String fileName,
}) =>
    viewFileInDialog(context: context, fileBytes: pdfBytes, fileName: fileName);

/// Stateful Universal File Viewer Dialog
class UniversalFileViewerDialog extends StatefulWidget {
  final List<int> fileBytes;
  final String fileName;

  const UniversalFileViewerDialog({
    super.key,
    required this.fileBytes,
    required this.fileName,
  });

  @override
  State<UniversalFileViewerDialog> createState() => _UniversalFileViewerDialogState();
}

class _UniversalFileViewerDialogState extends State<UniversalFileViewerDialog> {
  late final FileCategory _category;
  late final String _mimeType;
  late final String _blobUrl;
  late final String _viewType;

  // Image manipulation controller
  final TransformationController _imageTransformCtrl = TransformationController();
  double _imageRotation = 0.0;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _category = FileViewerMetadata.detectCategory(widget.fileName);
    _mimeType = FileViewerMetadata.getMimeType(widget.fileName);

    // Create browser blob URL for iframe/video/audio or new-tab opening
    final blob = html.Blob([widget.fileBytes], _mimeType);
    _blobUrl = html.Url.createObjectUrlFromBlob(blob);

    // Create unique viewType for web platform views
    _viewType = 'univ-viewer-${DateTime.now().millisecondsSinceEpoch}-${widget.fileName.hashCode}';

    // Register platform view factories if needed
    if (_category == FileCategory.pdf) {
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int viewId) => html.IFrameElement()
          ..src = _blobUrl
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%',
      );
    } else if (_category == FileCategory.video) {
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int viewId) => html.VideoElement()
          ..src = _blobUrl
          ..controls = true
          ..autoplay = true
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.backgroundColor = '#000000',
      );
    } else if (_category == FileCategory.audio) {
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int viewId) => html.AudioElement()
          ..src = _blobUrl
          ..controls = true
          ..autoplay = true
          ..style.width = '100%'
          ..style.height = '50px',
      );
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _imageTransformCtrl.dispose();
    html.Url.revokeObjectUrl(_blobUrl);
    super.dispose();
  }

  void _downloadFile() {
    final anchor = html.AnchorElement(href: _blobUrl)
      ..setAttribute('download', widget.fileName)
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();

    showSuccessToast(
      context,
      'Downloading ${widget.fileName}',
      duration: const Duration(seconds: 2),
    );
  }

  void _openInNewTab() {
    html.window.open(_blobUrl, '_blank');
  }

  void _zoomImage(double factor) {
    setState(() {
      final matrix = _imageTransformCtrl.value.clone();
      matrix.scale(factor);
      _imageTransformCtrl.value = matrix;
    });
  }

  void _resetImageZoom() {
    setState(() {
      _imageTransformCtrl.value = Matrix4.identity();
      _imageRotation = 0.0;
    });
  }

  void _rotateImage() {
    setState(() {
      _imageRotation += 1.57079632679; // 90 degrees in radians
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
      if (_category == FileCategory.image) {
        if (event.logicalKey == LogicalKeyboardKey.equal ||
            event.logicalKey == LogicalKeyboardKey.numpadAdd) {
          _zoomImage(1.2);
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.minus ||
            event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
          _zoomImage(0.8);
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.digit0 ||
            event.logicalKey == LogicalKeyboardKey.numpad0) {
          _resetImageZoom();
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.94).clamp(420.0, 1500.0);
    final dialogHeight = (screenSize.height * 0.92).clamp(520.0, 1000.0);

    final catColor = FileViewerMetadata.getCategoryColor(_category);
    final catIcon = FileViewerMetadata.getCategoryIcon(_category);
    final catLabel = FileViewerMetadata.getCategoryLabel(_category, widget.fileName);
    final formattedSize = FileViewerMetadata.formatBytes(widget.fileBytes.length);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF0B0F19),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF273142), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 36,
                spreadRadius: 4,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              // ----------------------------------------------------
              // Header Toolbar
              // ----------------------------------------------------
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: DefensysTokens.maroon,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(10),
                    topRight: Radius.circular(10),
                  ),
                ),
                child: Row(
                  children: [
                    // Category Badge Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: catColor.withValues(alpha: 0.7)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(catIcon, size: 14, color: catColor),
                          const SizedBox(width: 6),
                          Text(
                            catLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // File Name
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Tooltip(
                              message: widget.fileName,
                              child: Text(
                                widget.fileName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Size pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              formattedSize,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Contextual Controls for Image
                    if (_category == FileCategory.image) ...[
                      IconButton(
                        icon: const Icon(Icons.zoom_in, color: Colors.white, size: 18),
                        tooltip: 'Zoom In (+)',
                        onPressed: () => _zoomImage(1.25),
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: const Icon(Icons.zoom_out, color: Colors.white, size: 18),
                        tooltip: 'Zoom Out (-)',
                        onPressed: () => _zoomImage(0.8),
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: const Icon(Icons.restart_alt, color: Colors.white, size: 18),
                        tooltip: 'Reset Zoom (0)',
                        onPressed: _resetImageZoom,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: const Icon(Icons.rotate_right, color: Colors.white, size: 18),
                        tooltip: 'Rotate 90°',
                        onPressed: _rotateImage,
                        visualDensity: VisualDensity.compact,
                      ),
                      Container(
                        height: 20,
                        width: 1,
                        color: Colors.white24,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                    ],

                    // Open in New Tab
                    IconButton(
                      icon: const Icon(Icons.open_in_new, color: Colors.white, size: 18),
                      tooltip: 'Open in New Tab',
                      onPressed: _openInNewTab,
                      visualDensity: VisualDensity.compact,
                    ),

                    // Download button
                    IconButton(
                      icon: const Icon(Icons.download, color: Colors.white, size: 18),
                      tooltip: 'Download File',
                      onPressed: _downloadFile,
                      visualDensity: VisualDensity.compact,
                    ),

                    Container(
                      height: 20,
                      width: 1,
                      color: Colors.white24,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                    ),

                    // Close button
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                      tooltip: 'Close (Esc)',
                      onPressed: () => Navigator.of(context).pop(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),

              // ----------------------------------------------------
              // Main Viewer Canvas
              // ----------------------------------------------------
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                  child: _buildViewerContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewerContent() {
    switch (_category) {
      case FileCategory.pdf:
      case FileCategory.video:
        return HtmlElementView(viewType: _viewType);

      case FileCategory.audio:
        return UniversalAudioPlayerCard(
          fileName: widget.fileName,
          fileSizeBytes: widget.fileBytes.length,
          audioPlayerWidget: HtmlElementView(viewType: _viewType),
        );

      case FileCategory.image:
        return UniversalImageViewer(
          bytes: Uint8List.fromList(widget.fileBytes),
          fileName: widget.fileName,
          controller: _imageTransformCtrl,
          rotationAngle: _imageRotation,
        );

      case FileCategory.spreadsheet:
        return UniversalSpreadsheetViewer(
          bytes: Uint8List.fromList(widget.fileBytes),
          fileName: widget.fileName,
        );

      case FileCategory.codeOrText:
        return UniversalCodeTextViewer(
          bytes: Uint8List.fromList(widget.fileBytes),
          fileName: widget.fileName,
        );

      case FileCategory.officeDoc:
      case FileCategory.officePresentation:
      case FileCategory.archive:
      case FileCategory.other:
        return UniversalOfficeInspectorCard(
          fileName: widget.fileName,
          fileSizeBytes: widget.fileBytes.length,
          category: _category,
          onDownload: _downloadFile,
          onOpenInNewTab: _openInNewTab,
        );
    }
  }
}
