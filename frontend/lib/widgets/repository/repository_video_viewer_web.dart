import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../utils/universal_file_viewer.dart';

Future<void> openRepositoryVideo({
  required BuildContext context,
  required Uint8List bytes,
  required String fileName,
  required VoidCallback onReady,
}) async {
  onReady();
  await viewFileInDialog(
    context: context,
    fileBytes: bytes,
    fileName: fileName,
  );
}
