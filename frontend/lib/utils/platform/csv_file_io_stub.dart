import '../import/picked_tabular_file.dart';
export '../import/picked_tabular_file.dart';

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

Future<PickedTabularFile?> pickSingleTabularDataFile() async {
  return null;
}

Future<List<PickedTabularFile>> pickMultipleTabularDataFiles() async {
  return [];
}

dynamic setupDropzoneListener(
  void Function(List<PickedTabularFile> files) onFilesDropped, {
  void Function(bool isDragging)? onDragStateChanged,
  void Function(List<String> rejectedFileNames)? onRejectedFiles,
}) {
  return null;
}

Future<void> downloadBinaryFile({
  required String filename,
  required List<int> bytes,
  String? mimeType,
}) async {}
