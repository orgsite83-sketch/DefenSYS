// Web-specific implementation
import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import '../theme/defensys_tokens.dart';

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

Future<void> viewPdfInDialog({
  required BuildContext context,
  required List<int> pdfBytes,
  required String fileName,
}) async {
  // Create a blob URL from the PDF bytes
  final blob = html.Blob([pdfBytes], 'application/pdf');
  final blobUrl = html.Url.createObjectUrlFromBlob(blob);
  
  // Create a unique view type for this PDF
  final viewType = 'pdf-iframe-${DateTime.now().millisecondsSinceEpoch}';
  
  // Register iframe with the blob URL
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) {
      final iframe = html.IFrameElement()
        ..src = blobUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    },
  );
  
  // Show PDF viewer dialog
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
                  const Icon(Icons.picture_as_pdf, color: Colors.white),
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
                  // Download button
                  IconButton(
                    icon: const Icon(Icons.download, color: Colors.white),
                    tooltip: 'Download PDF',
                    onPressed: () {
                      html.AnchorElement(href: blobUrl)
                        ..setAttribute('download', fileName)
                        ..click();
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('PDF downloaded'),
                          backgroundColor: DefensysTokens.success,
                          duration: Duration(seconds: 2),
                        ),
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
            // PDF Viewer using iframe
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
