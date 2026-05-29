Future<void> downloadTextFile({
  required String filename,
  required String content,
  String mimeType = 'text/csv;charset=utf-8',
}) async {}

Future<String?> pickCsvTextFile() async {
  return null;
}

Future<void> downloadBinaryFile({
  required String filename,
  required List<int> bytes,
  String mimeType = 'application/pdf',
}) async {}
