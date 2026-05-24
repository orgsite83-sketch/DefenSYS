// Stub implementation for non-web platforms
import 'package:flutter/material.dart';

Future<void> downloadBytesFile({
  required List<int> bytes,
  required String fileName,
  String mimeType = 'application/octet-stream',
}) async {
  throw UnsupportedError('File download is only supported on web platform');
}

Future<void> viewPdfInDialog({
  required BuildContext context,
  required List<int> pdfBytes,
  required String fileName,
}) async {
  throw UnsupportedError('PDF viewing is only supported on web platform');
}
