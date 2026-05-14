// Stub implementation for non-web platforms
import 'package:flutter/material.dart';

Future<void> viewPdfInDialog({
  required BuildContext context,
  required List<int> pdfBytes,
  required String fileName,
}) async {
  throw UnsupportedError('PDF viewing is only supported on web platform');
}
