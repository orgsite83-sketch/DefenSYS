// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/network/authenticated_client.dart';
import '../../theme/defensys_tokens.dart';
import '../../toasts/feedback_toast.dart';
import '../../widgets/export/defensys_pdf_viewer.dart';
import '../../widgets/file_viewer_dialog_layout.dart';
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
    ..setAttribute('download', fileName)
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // Delay revoking the object URL so the browser has sufficient time to stream/save the blob
  Future.delayed(const Duration(seconds: 30), () {
    try {
      html.Url.revokeObjectUrl(url);
    } catch (_) {}
  });
}

/// Universal file viewer dialog supporting PDFs, Videos, Audio, Images,
/// Spreadsheets (Excel/CSV), Code/Text files, and Office Document Inspection.
Future<void> viewFileInDialog({
  required BuildContext context,
  List<int>? fileBytes,
  String? fileUrl,
  required String fileName,
  DeliverablePropertiesInfo? propertiesInfo,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (dialogContext) => UniversalFileViewerDialog(
      fileBytes: fileBytes,
      fileUrl: fileUrl,
      fileName: fileName,
      propertiesInfo: propertiesInfo,
    ),
  );
}

/// Legacy alias for backward compatibility.
Future<void> viewPdfInDialog({
  required BuildContext context,
  List<int>? pdfBytes,
  String? fileUrl,
  required String fileName,
  DeliverablePropertiesInfo? propertiesInfo,
}) => viewFileInDialog(
  context: context,
  fileBytes: pdfBytes,
  fileUrl: fileUrl,
  fileName: fileName,
  propertiesInfo: propertiesInfo,
);

/// Stateful Universal File Viewer Dialog
class UniversalFileViewerDialog extends ConsumerStatefulWidget {
  final List<int>? fileBytes;
  final String? fileUrl;
  final String fileName;
  final DeliverablePropertiesInfo? propertiesInfo;

  const UniversalFileViewerDialog({
    super.key,
    this.fileBytes,
    this.fileUrl,
    required this.fileName,
    this.propertiesInfo,
  });

  @override
  ConsumerState<UniversalFileViewerDialog> createState() =>
      _UniversalFileViewerDialogState();
}

class _UniversalFileViewerDialogState
    extends ConsumerState<UniversalFileViewerDialog> {
  late final FileCategory _category;
  late final String _mimeType;
  String? _blobUrl;
  late final String _viewType;
  Uint8List? _fileBytes;
  bool _isLoading = false;
  String? _loadError;

  // Image manipulation controller
  final TransformationController _imageTransformCtrl =
      TransformationController();
  double _imageRotation = 0.0;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _category = FileViewerMetadata.detectCategory(widget.fileName);
    _mimeType = FileViewerMetadata.getMimeType(widget.fileName);

    // Create unique viewType for web platform views
    _viewType =
        'univ-viewer-${DateTime.now().millisecondsSinceEpoch}-${widget.fileName.hashCode}';

    if (widget.fileBytes != null && widget.fileBytes!.isNotEmpty) {
      _initBytes(Uint8List.fromList(widget.fileBytes!));
    } else if (widget.fileUrl != null && widget.fileUrl!.isNotEmpty) {
      _loadFile();
    } else {
      _loadError = 'No file content or URL provided.';
    }
  }

  void _initBytes(Uint8List bytes) {
    _fileBytes = bytes;
    final blob = html.Blob([_fileBytes!], _mimeType);
    _blobUrl = html.Url.createObjectUrlFromBlob(blob);

    // Register platform view factories if needed
    if (_category == FileCategory.video) {
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int viewId) => html.VideoElement()
          ..src = _blobUrl!
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
          ..src = _blobUrl!
          ..controls = true
          ..autoplay = true
          ..style.width = '100%'
          ..style.height = '50px',
      );
    }
  }

  Future<void> _loadFile() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final client = ref.read(authenticatedHttpClientProvider);
      final bytes = await client.fetchAuthenticatedFile(widget.fileUrl!);
      if (!mounted) return;
      _initBytes(Uint8List.fromList(bytes));
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _imageTransformCtrl.dispose();
    if (_blobUrl != null) {
      html.Url.revokeObjectUrl(_blobUrl!);
    }
    super.dispose();
  }

  void _downloadFile() {
    if (_fileBytes == null) return;
    if (_blobUrl == null) {
      final blob = html.Blob([_fileBytes!], _mimeType);
      _blobUrl = html.Url.createObjectUrlFromBlob(blob);
    }
    final anchor = html.AnchorElement(href: _blobUrl!)
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
    if (_blobUrl != null) {
      html.window.open(_blobUrl!, '_blank');
    }
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
        } else if (event.logicalKey == LogicalKeyboardKey.keyR) {
          _rotateImage();
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final layout = FileViewerDialogLayout.of(context);
    final compact = screenSize.width < 600;
    final toolbarColor = DefensysTokens.surfaceOf(context);
    final toolbarForeground = DefensysTokens.textPrimaryOf(context);
    final toolbarSecondary = DefensysTokens.textSecondaryOf(context);

    final catColor = FileViewerMetadata.getCategoryColor(_category);
    final catIcon = FileViewerMetadata.getCategoryIcon(_category);
    final catLabel = FileViewerMetadata.getCategoryLabel(
      _category,
      widget.fileName,
    );
    final formattedSize = _fileBytes != null
        ? FileViewerMetadata.formatBytes(_fileBytes!.length)
        : (_isLoading ? 'Loading...' : '');

    final String downloadLabel;
    switch (_category) {
      case FileCategory.pdf:
        downloadLabel = 'Download PDF';
        break;
      case FileCategory.officePresentation:
        downloadLabel = 'Download Presentation';
        break;
      case FileCategory.officeDoc:
        downloadLabel = 'Download Document';
        break;
      case FileCategory.spreadsheet:
        downloadLabel = 'Download Spreadsheet';
        break;
      default:
        downloadLabel = 'Download File';
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: layout.insetPadding,
        child: Container(
          width: layout.size.width,
          height: layout.size.height,
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: DefensysTokens.borderOf(context),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: DefensysTokens.isDark(context) ? .65 : .15,
                ),
                blurRadius: 36,
                spreadRadius: 4,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              // ----------------------------------------------------
              // Header Toolbar (Unified Image 2 Aesthetic)
              // ----------------------------------------------------
              Container(
                height: 56,
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
                decoration: BoxDecoration(
                  color: toolbarColor,
                  border: Border(
                    bottom: BorderSide(color: DefensysTokens.borderOf(context)),
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    topRight: Radius.circular(10),
                  ),
                ),
                child: Row(
                  children: [
                    // Category Badge Pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: catColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(catIcon, size: 14, color: catColor),
                          if (!compact) const SizedBox(width: 6),
                          if (!compact)
                            Text(
                              catLabel,
                              style: TextStyle(
                                color: catColor,
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
                                style: TextStyle(
                                  color: toolbarForeground,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (!compact) const SizedBox(width: 8),
                          // Size pill
                          if (!compact)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: DefensysTokens.surfaceHigherOf(context),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: DefensysTokens.borderOf(context),
                                ),
                              ),
                              child: Text(
                                formattedSize,
                                style: TextStyle(
                                  color: toolbarSecondary,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    if (!_isLoading && _fileBytes != null) ...[
                      // Open in New Tab
                      IconButton(
                        icon: Icon(
                          Icons.open_in_new,
                          color: toolbarSecondary,
                          size: 18,
                        ),
                        tooltip: 'Open in New Tab',
                        onPressed: _openInNewTab,
                        visualDensity: VisualDensity.compact,
                      ),

                      // Download button
                      if (!compact) ...[
                        Tooltip(
                          message: 'Download File',
                          child: OutlinedButton.icon(
                            onPressed: _downloadFile,
                            icon: Icon(
                              Icons.download,
                              color: toolbarForeground,
                              size: 15,
                            ),
                            label: Text(
                              downloadLabel,
                              style: TextStyle(
                                color: toolbarForeground,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: DefensysTokens.borderOf(context),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ] else ...[
                        IconButton(
                          icon: Icon(
                            Icons.download,
                            color: toolbarForeground,
                            size: 18,
                          ),
                          tooltip: 'Download File',
                          onPressed: _downloadFile,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],

                      Container(
                        height: 20,
                        width: 1,
                        color: DefensysTokens.borderOf(context),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                    ],

                    // Close button
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: toolbarForeground,
                        size: 20,
                      ),
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
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: DefensysTokens.maroon),
            const SizedBox(height: 16),
            Text(
              'Loading ${widget.fileName}...',
              style: TextStyle(
                color: DefensysTokens.textSecondaryOf(context),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (_loadError != null || _fileBytes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 44,
                color: Color(0xFFEF4444),
              ),
              const SizedBox(height: 14),
              Text(
                'Unable to open ${widget.fileName}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _loadError ?? 'File data is not available.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: DefensysTokens.maroon,
                  foregroundColor: Colors.white,
                ),
                onPressed: _loadFile,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    switch (_category) {
      case FileCategory.pdf:
        return DefensysPdfViewer(pdfBytes: _fileBytes!, title: widget.fileName);

      case FileCategory.video:
        return HtmlElementView(viewType: _viewType);

      case FileCategory.audio:
        return UniversalAudioPlayerCard(
          fileName: widget.fileName,
          fileSizeBytes: _fileBytes!.length,
          audioPlayerWidget: HtmlElementView(viewType: _viewType),
        );

      case FileCategory.image:
        return UniversalImageViewer(
          bytes: _fileBytes!,
          fileName: widget.fileName,
          controller: _imageTransformCtrl,
          rotationAngle: _imageRotation,
        );

      case FileCategory.spreadsheet:
        return UniversalSpreadsheetViewer(
          bytes: _fileBytes!,
          fileName: widget.fileName,
        );

      case FileCategory.codeOrText:
        return UniversalCodeTextViewer(
          bytes: _fileBytes!,
          fileName: widget.fileName,
        );

      case FileCategory.officePresentation:
        return UniversalPresentationViewer(
          bytes: _fileBytes!,
          fileName: widget.fileName,
          onDownload: _downloadFile,
          onOpenInNewTab: _openInNewTab,
        );

      case FileCategory.officeDoc:
        return UniversalDocxViewer(
          bytes: _fileBytes!,
          fileName: widget.fileName,
          onDownload: _downloadFile,
          onOpenInNewTab: _openInNewTab,
        );

      case FileCategory.archive:
        return UniversalArchiveViewer(
          bytes: _fileBytes!,
          fileName: widget.fileName,
          onDownload: _downloadFile,
          onOpenInNewTab: _openInNewTab,
        );

      case FileCategory.other:
        return UniversalDeliverableCard(
          fileName: widget.fileName,
          fileSizeBytes: _fileBytes!.length,
          category: _category,
          onDownload: _downloadFile,
          onOpenInNewTab: _openInNewTab,
        );
    }
  }
}
