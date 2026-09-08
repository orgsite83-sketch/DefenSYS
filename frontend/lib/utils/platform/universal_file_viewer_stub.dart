// Stub implementation for non-web platforms
import 'package:flutter/material.dart';

export 'universal_file_viewer_models.dart';
export 'universal_file_viewer_widgets.dart';

Future<void> downloadBytesFile({
  required List<int> bytes,
  required String fileName,
  String mimeType = 'application/octet-stream',
}) async {
  throw UnsupportedError('File download is only supported on web platform');
}

Future<void> viewFileInDialog({
  required BuildContext context,
  required List<int> fileBytes,
  required String fileName,
}) async {
  throw UnsupportedError('File viewing is only supported on web platform');
}

Future<void> viewPdfInDialog({
  required BuildContext context,
  required List<int> pdfBytes,
  required String fileName,
}) => viewFileInDialog(context: context, fileBytes: pdfBytes, fileName: fileName);
