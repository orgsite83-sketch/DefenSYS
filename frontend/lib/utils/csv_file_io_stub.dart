class PickedTabularFile {
  final String name;
  final String extension;
  final String? text;
  final List<int> bytes;

  const PickedTabularFile({
    required this.name,
    required this.extension,
    required this.bytes,
    this.text,
  });

  bool get isCsv => extension == 'csv';
  bool get isXlsx => extension == 'xlsx';
}

Future<void> downloadTextFile({
  required String filename,
  required String content,
  String mimeType = 'text/csv;charset=utf-8',
}) async {}

Future<String?> pickCsvTextFile() async {
  return null;
}

Future<PickedTabularFile?> pickTabularDataFile() async {
  return null;
}

Future<void> downloadBinaryFile({
  required String filename,
  required List<int> bytes,
  String mimeType = 'application/pdf',
}) async {}
