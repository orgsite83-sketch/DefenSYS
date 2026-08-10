// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

// Web-specific implementation
import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import '../theme/defensys_tokens.dart';
import '../toasts/feedback_toast.dart';

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

Future<void> viewFileInDialog({
  required BuildContext context,
  required List<int> fileBytes,
  required String fileName,
}) async {
  final lowerName = fileName.toLowerCase();
  
  String mimeType = 'application/octet-stream';
  bool isPdf = false;
  bool isVideo = false;
  bool isImage = false;
  
  if (lowerName.endsWith('.pdf')) {
    mimeType = 'application/pdf';
    isPdf = true;
  } else if (lowerName.endsWith('.mp4')) {
    mimeType = 'video/mp4';
    isVideo = true;
  } else if (lowerName.endsWith('.mov')) {
    mimeType = 'video/quicktime';
    isVideo = true;
  } else if (lowerName.endsWith('.avi')) {
    mimeType = 'video/x-msvideo';
    isVideo = true;
  } else if (lowerName.endsWith('.mkv')) {
    mimeType = 'video/x-matroska';
    isVideo = true;
  } else if (lowerName.endsWith('.png')) {
    mimeType = 'image/png';
    isImage = true;
  } else if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
    mimeType = 'image/jpeg';
    isImage = true;
  } else if (lowerName.endsWith('.webp')) {
    mimeType = 'image/webp';
    isImage = true;
  } else if (lowerName.endsWith('.gif')) {
    mimeType = 'image/gif';
    isImage = true;
  }
  
  // If it is not a previewable file, download it and return
  if (!isPdf && !isVideo && !isImage) {
    await downloadBytesFile(bytes: fileBytes, fileName: fileName, mimeType: mimeType);
    if (context.mounted) {
      showSuccessToast(
        context,
        'File downloaded',
        duration: const Duration(seconds: 2),
      );
    }
    return;
  }
  
  // Create a blob URL from the file bytes
  final blob = html.Blob([fileBytes], mimeType);
  final blobUrl = html.Url.createObjectUrlFromBlob(blob);
  
  // Create a unique view type for this file
  final viewType = 'file-viewer-${DateTime.now().millisecondsSinceEpoch}-${fileName.hashCode}';
  
  // Register platform view factory based on file type
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) {
      if (isPdf) {
        return html.IFrameElement()
          ..src = blobUrl
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';
      } else if (isVideo) {
        final video = html.VideoElement()
          ..src = blobUrl
          ..controls = true
          ..autoplay = true
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';
        return video;
      } else {
        // Image
        return html.ImageElement()
          ..src = blobUrl
          ..style.border = 'none'
          ..style.objectFit = 'contain'
          ..style.width = '100%'
          ..style.height = '100%';
      }
    },
  );
  
  IconData headerIcon = Icons.insert_drive_file;
  if (isPdf) headerIcon = Icons.picture_as_pdf;
  if (isVideo) headerIcon = Icons.video_library;
  if (isImage) headerIcon = Icons.image;
  
  // Show file viewer dialog
  await showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: DefensysTokens.maroon,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(headerIcon, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      fileName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Open in New Tab button
                  IconButton(
                    icon: const Icon(Icons.open_in_new, color: Colors.white),
                    tooltip: 'Open in New Tab',
                    onPressed: () {
                      html.window.open(blobUrl, '_blank');
                    },
                  ),
                  // Download button
                  IconButton(
                    icon: const Icon(Icons.download, color: Colors.white),
                    tooltip: 'Download File',
                    onPressed: () {
                      html.AnchorElement(href: blobUrl)
                        ..setAttribute('download', fileName)
                        ..click();
                      
                      showSuccessToast(
                        context,
                        'File downloaded',
                        duration: const Duration(seconds: 2),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      html.Url.revokeObjectUrl(blobUrl);
                    },
                  ),
                ],
              ),
            ),
            // File Viewer
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                child: HtmlElementView(viewType: viewType),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  
  // Clean up blob URL when dialog closes
  html.Url.revokeObjectUrl(blobUrl);
}

Future<void> viewPdfInDialog({
  required BuildContext context,
  required List<int> pdfBytes,
  required String fileName,
}) => viewFileInDialog(context: context, fileBytes: pdfBytes, fileName: fileName);
