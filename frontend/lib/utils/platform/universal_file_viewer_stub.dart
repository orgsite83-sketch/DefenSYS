// Mobile & Desktop implementation for non-web platforms
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/network/authenticated_client.dart';
import '../../theme/defensys_tokens.dart';
import '../../widgets/export/defensys_pdf_viewer.dart';
import '../../widgets/file_viewer_dialog_layout.dart';
import 'universal_file_viewer_models.dart';
import 'universal_file_viewer_widgets.dart';

export 'universal_file_viewer_models.dart';
export 'universal_file_viewer_widgets.dart';

/// Saves in-memory bytes to device storage on mobile or desktop platforms.
Future<void> downloadBytesFile({
  required List<int> bytes,
  required String fileName,
  String mimeType = 'application/octet-stream',
}) async {
  try {
    final Uint8List data = Uint8List.fromList(bytes);

    // Try native Save File picker first (works on desktop and newer mobile OS)
    String? outputPath;
    try {
      outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save File',
        fileName: fileName,
        bytes: data,
      );
    } catch (_) {}

    if (outputPath != null && outputPath.isNotEmpty) {
      final file = File(outputPath);
      if (!await file.exists() || (await file.length()) == 0) {
        await file.writeAsBytes(data, flush: true);
      }
      return;
    }

    // Fallback saving directly to Downloads or Documents directory
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {}
    dir ??= await getApplicationDocumentsDirectory();

    final fallbackFile = File('${dir.path}/$fileName');
    await fallbackFile.writeAsBytes(data, flush: true);
  } catch (e) {
    debugPrint('Error saving file in mobile/desktop stub: $e');
    rethrow;
  }
}

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
    builder: (dialogContext) => UniversalMobileFileViewerDialog(
      fileBytes: fileBytes,
      fileUrl: fileUrl,
      fileName: fileName,
      propertiesInfo: propertiesInfo,
    ),
  );
}

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

class UniversalMobileFileViewerDialog extends ConsumerStatefulWidget {
  final List<int>? fileBytes;
  final String? fileUrl;
  final String fileName;
  final DeliverablePropertiesInfo? propertiesInfo;

  const UniversalMobileFileViewerDialog({
    super.key,
    this.fileBytes,
    this.fileUrl,
    required this.fileName,
    this.propertiesInfo,
  });

  @override
  ConsumerState<UniversalMobileFileViewerDialog> createState() =>
      _UniversalMobileFileViewerDialogState();
}

class _UniversalMobileFileViewerDialogState
    extends ConsumerState<UniversalMobileFileViewerDialog> {
  late final FileCategory _category;
  Uint8List? _pdfBytes;
  bool _isLoading = false;
  String? _loadError;
  final TransformationController _imageTransformCtrl =
      TransformationController();
  final double _imageRotation = 0.0;

  @override
  void initState() {
    super.initState();
    _category = FileViewerMetadata.detectCategory(widget.fileName);
    if (widget.fileBytes != null && widget.fileBytes!.isNotEmpty) {
      _pdfBytes = Uint8List.fromList(widget.fileBytes!);
    } else if (widget.fileUrl != null && widget.fileUrl!.isNotEmpty) {
      _loadFile();
    } else {
      _loadError = 'No file content or URL provided.';
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
      setState(() {
        _pdfBytes = Uint8List.fromList(bytes);
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
    _imageTransformCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = FileViewerDialogLayout.of(context);
    final compact = layout.size.width < 600;
    final catColor = FileViewerMetadata.getCategoryColor(_category);
    final catIcon = FileViewerMetadata.getCategoryIcon(_category);
    final catLabel = FileViewerMetadata.getCategoryLabel(
      _category,
      widget.fileName,
    );
    final formattedSize = _pdfBytes != null
        ? FileViewerMetadata.formatBytes(_pdfBytes!.length)
        : (_isLoading ? 'Loading...' : '');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: layout.insetPadding,
      child: Container(
        width: layout.size.width,
        height: layout.size.height,
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: DefensysTokens.borderOf(context),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: DefensysTokens.isDark(context) ? .65 : .15,
              ),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header Toolbar (Unified Image 2 Aesthetic)
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: DefensysTokens.surfaceOf(context),
                border: Border(
                  bottom: BorderSide(color: DefensysTokens.borderOf(context)),
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
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
                        Icon(catIcon, size: 13, color: catColor),
                        if (!compact) const SizedBox(width: 4),
                        if (!compact)
                          Text(
                            catLabel,
                            style: TextStyle(
                              color: catColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.fileName,
                      style: TextStyle(
                        color: DefensysTokens.textPrimaryOf(context),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
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
                          color: DefensysTokens.textSecondaryOf(context),
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  if (!_isLoading && _pdfBytes != null) ...[
                    if (compact)
                      IconButton(
                        tooltip: 'Download File',
                        icon: const Icon(Icons.download, size: 18),
                        onPressed: () => downloadBytesFile(
                          bytes: _pdfBytes!,
                          fileName: widget.fileName,
                        ),
                        visualDensity: VisualDensity.compact,
                      )
                    else
                      Tooltip(
                        message: 'Download File',
                        child: OutlinedButton.icon(
                          onPressed: () {
                            downloadBytesFile(
                              bytes: _pdfBytes!,
                              fileName: widget.fileName,
                            );
                          },
                          icon: Icon(
                            Icons.download,
                            color: DefensysTokens.textPrimaryOf(context),
                            size: 15,
                          ),
                          label: Text(
                            _category == FileCategory.pdf
                                ? 'Download PDF'
                                : (_category == FileCategory.officePresentation
                                      ? 'Download Presentation'
                                      : (_category == FileCategory.officeDoc
                                            ? 'Download Document'
                                            : (_category ==
                                                      FileCategory.spreadsheet
                                                  ? 'Download Spreadsheet'
                                                  : 'Download'))),
                            style: TextStyle(
                              color: DefensysTokens.textPrimaryOf(context),
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
                  ],
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: DefensysTokens.textPrimaryOf(context),
                      size: 20,
                    ),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            // Viewer Content
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                child: _buildViewerContent(),
              ),
            ),
          ],
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

    if (_loadError != null || _pdfBytes == null) {
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
        return DefensysPdfViewer(pdfBytes: _pdfBytes!, title: widget.fileName);
      case FileCategory.image:
        return UniversalImageViewer(
          bytes: _pdfBytes!,
          fileName: widget.fileName,
          controller: _imageTransformCtrl,
          rotationAngle: _imageRotation,
        );
      case FileCategory.spreadsheet:
        return UniversalSpreadsheetViewer(
          bytes: _pdfBytes!,
          fileName: widget.fileName,
        );
      case FileCategory.codeOrText:
        return UniversalCodeTextViewer(
          bytes: _pdfBytes!,
          fileName: widget.fileName,
        );
      case FileCategory.officePresentation:
        return UniversalPresentationViewer(
          bytes: _pdfBytes!,
          fileName: widget.fileName,
          onDownload: () {
            downloadBytesFile(bytes: _pdfBytes!, fileName: widget.fileName);
          },
          onOpenInNewTab: () {},
        );
      case FileCategory.officeDoc:
        return UniversalDocxViewer(
          bytes: _pdfBytes!,
          fileName: widget.fileName,
          onDownload: () {
            downloadBytesFile(bytes: _pdfBytes!, fileName: widget.fileName);
          },
          onOpenInNewTab: () {},
        );
      case FileCategory.archive:
        return UniversalArchiveViewer(
          bytes: _pdfBytes!,
          fileName: widget.fileName,
          onDownload: () {
            downloadBytesFile(bytes: _pdfBytes!, fileName: widget.fileName);
          },
          onOpenInNewTab: () {},
        );
      case FileCategory.video:
      case FileCategory.audio:
      case FileCategory.other:
        return UniversalDeliverableCard(
          fileName: widget.fileName,
          fileSizeBytes: _pdfBytes!.length,
          category: _category,
          onDownload: () {
            downloadBytesFile(bytes: _pdfBytes!, fileName: widget.fileName);
          },
          onOpenInNewTab: () {},
        );
    }
  }
}
