// Mobile & Desktop implementation for non-web platforms
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../theme/defensys_tokens.dart';
import '../../toasts/feedback_toast.dart';
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
  required List<int> fileBytes,
  required String fileName,
  DeliverablePropertiesInfo? propertiesInfo,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (dialogContext) => UniversalMobileFileViewerDialog(
      fileBytes: fileBytes,
      fileName: fileName,
      propertiesInfo: propertiesInfo,
    ),
  );
}

Future<void> viewPdfInDialog({
  required BuildContext context,
  required List<int> pdfBytes,
  required String fileName,
  DeliverablePropertiesInfo? propertiesInfo,
}) =>
    viewFileInDialog(
      context: context,
      fileBytes: pdfBytes,
      fileName: fileName,
      propertiesInfo: propertiesInfo,
    );

class UniversalMobileFileViewerDialog extends StatefulWidget {
  final List<int> fileBytes;
  final String fileName;
  final DeliverablePropertiesInfo? propertiesInfo;

  const UniversalMobileFileViewerDialog({
    super.key,
    required this.fileBytes,
    required this.fileName,
    this.propertiesInfo,
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
                borderRadius: widget.propertiesInfo != null
                    ? BorderRadius.zero
                    : const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                child: _buildViewerContent(),
              ),
            ),
            if (widget.propertiesInfo != null)
              _buildPropertiesSection(formattedSize, catLabel),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertiesSection(String fallbackSize, String fallbackType) {
    final info = widget.propertiesInfo!;
    final size = (info.fileSize != null && info.fileSize!.isNotEmpty)
        ? info.fileSize!
        : fallbackSize;
    final type = (info.fileType != null && info.fileType!.isNotEmpty)
        ? info.fileType!
        : fallbackType;
    final uploader = (info.uploader != null && info.uploader!.isNotEmpty)
        ? info.uploader!
        : 'Team Member';
    final timestamp = (info.timestamp != null && info.timestamp!.isNotEmpty)
        ? info.timestamp!
        : 'Recently';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'FILE PROPERTIES & INFO',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildPropertyTile('Size', size)),
              const SizedBox(width: 8),
              Expanded(child: _buildPropertyTile('Type', type)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _buildPropertyTile('Uploader', uploader)),
              const SizedBox(width: 8),
              Expanded(child: _buildPropertyTile('Timestamp', timestamp)),
            ],
          ),
          if (info.feedback != null && info.feedback!.isNotEmpty && info.isRejected) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF7F1D1D).withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFF87171)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Remarks: ${info.feedback}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFFFECACA)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPropertyTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
