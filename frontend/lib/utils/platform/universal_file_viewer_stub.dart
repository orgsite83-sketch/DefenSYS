// Mobile & Desktop implementation for non-web platforms
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../theme/defensys_tokens.dart';
import '../../toasts/feedback_toast.dart';
import 'universal_file_viewer_models.dart';
import 'universal_file_viewer_widgets.dart';

export 'universal_file_viewer_models.dart';
export 'universal_file_viewer_widgets.dart';

Future<void> downloadBytesFile({
  required List<int> bytes,
  required String fileName,
  String mimeType = 'application/octet-stream',
}) async {
  // Mobile platform placeholder - bytes are handled in-app
}

Future<void> viewFileInDialog({
  required BuildContext context,
  required List<int> fileBytes,
  required String fileName,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (dialogContext) => UniversalMobileFileViewerDialog(
      fileBytes: fileBytes,
      fileName: fileName,
    ),
  );
}

Future<void> viewPdfInDialog({
  required BuildContext context,
  required List<int> pdfBytes,
  required String fileName,
}) =>
    viewFileInDialog(context: context, fileBytes: pdfBytes, fileName: fileName);

class UniversalMobileFileViewerDialog extends StatefulWidget {
  final List<int> fileBytes;
  final String fileName;

  const UniversalMobileFileViewerDialog({
    super.key,
    required this.fileBytes,
    required this.fileName,
  });

  @override
  State<UniversalMobileFileViewerDialog> createState() =>
      _UniversalMobileFileViewerDialogState();
}

class _UniversalMobileFileViewerDialogState
    extends State<UniversalMobileFileViewerDialog> {
  late final FileCategory _category;
  final TransformationController _imageTransformCtrl =
      TransformationController();
  double _imageRotation = 0.0;

  @override
  void initState() {
    super.initState();
    _category = FileViewerMetadata.detectCategory(widget.fileName);
  }

  @override
  void dispose() {
    _imageTransformCtrl.dispose();
    super.dispose();
  }

  void _rotateImage() {
    setState(() {
      _imageRotation += 1.57079632679; // 90 degrees in radians
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.96).clamp(320.0, 900.0);
    final dialogHeight = (screenSize.height * 0.88).clamp(400.0, 900.0);

    final catColor = FileViewerMetadata.getCategoryColor(_category);
    final catIcon = FileViewerMetadata.getCategoryIcon(_category);
    final catLabel =
        FileViewerMetadata.getCategoryLabel(_category, widget.fileName);
    final formattedSize =
        FileViewerMetadata.formatBytes(widget.fileBytes.length);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF0B0F19),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF273142), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header Toolbar
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                color: DefensysTokens.maroon,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: catColor.withValues(alpha: 0.7)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(catIcon, size: 13, color: catColor),
                        const SizedBox(width: 4),
                        Text(
                          catLabel,
                          style: const TextStyle(
                            color: Colors.white,
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      formattedSize,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  if (_category == FileCategory.image) ...[
                    IconButton(
                      icon: const Icon(Icons.rotate_right,
                          color: Colors.white, size: 18),
                      tooltip: 'Rotate',
                      onPressed: _rotateImage,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.white, size: 20),
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
    switch (_category) {
      case FileCategory.pdf:
        return SfPdfViewer.memory(
          Uint8List.fromList(widget.fileBytes),
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
      case FileCategory.video:
      case FileCategory.audio:
      case FileCategory.other:
        return UniversalOfficeInspectorCard(
          fileName: widget.fileName,
          fileSizeBytes: widget.fileBytes.length,
          category: _category,
          onDownload: () {
            showInfoToast(context, 'File is stored in device app cache.');
          },
          onOpenInNewTab: () {},
        );
    }
  }
}
