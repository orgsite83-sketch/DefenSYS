// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

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
}) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';

  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

Future<void> downloadBinaryFile({
  required String filename,
  required List<int> bytes,
  String mimeType = 'application/pdf',
}) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';

  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

Future<String?> pickCsvTextFile() async {
  final files = await pickMultipleTabularDataFiles();
  if (files.isEmpty) return null;
  final texts = files
      .map((f) => f.text ?? utf8.decode(f.bytes, allowMalformed: true))
      .where((t) => t.trim().isNotEmpty)
      .toList();
  if (texts.isEmpty) return null;
  return texts.join('\n\n');
}

Future<PickedTabularFile?> pickTabularDataFile() async {
  return pickSingleTabularDataFile();
}

Future<PickedTabularFile?> pickSingleTabularDataFile() async {
  final files = await _pickTabularFilesInternal(multiple: false);
  return files.isNotEmpty ? files.first : null;
}

Future<List<PickedTabularFile>> pickMultipleTabularDataFiles() {
  return _pickTabularFilesInternal(multiple: true);
}

Future<List<PickedTabularFile>> _pickTabularFilesInternal({required bool multiple}) {
  final completer = Completer<List<PickedTabularFile>>();
  final input = html.FileUploadInputElement()
    ..accept =
        '.csv,.xlsx,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    ..multiple = multiple
    ..style.display = 'none';

  if (multiple) {
    input.setAttribute('multiple', 'multiple');
  }
  html.document.body?.append(input);

  StreamSubscription? changeSub;
  StreamSubscription? cancelSub;
  StreamSubscription? focusSub;
  Timer? focusTimer;

  void cleanup() {
    changeSub?.cancel();
    cancelSub?.cancel();
    focusSub?.cancel();
    focusTimer?.cancel();
    input.remove();
  }

  void completeWith(List<PickedTabularFile> result) {
    cleanup();
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }

  changeSub = input.onChange.listen((_) async {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completeWith([]);
      return;
    }
    final pickedFiles = await _parseHtmlFiles(files);
    completeWith(pickedFiles);
  });

  // Modern browsers dispatch 'cancel' on <input type="file"> when cancelled
  cancelSub = input.on['cancel'].listen((_) {
    completeWith([]);
  });

  // Fallback: When OS file picker dialog closes on cancel, window regains focus.
  // Wait 400ms to allow onChange to fire first if a file was selected.
  focusSub = html.window.onFocus.listen((_) {
    focusTimer?.cancel();
    focusTimer = Timer(const Duration(milliseconds: 400), () {
      completeWith([]);
    });
  });

  input.click();
  return completer.future;
}

Future<List<PickedTabularFile>> _parseHtmlFiles(List<html.File> files) async {
  final pickedFiles = <PickedTabularFile>[];
  for (final file in files) {
    final extension = file.name.toLowerCase().split('.').last;
    if (extension != 'csv' && extension != 'xlsx') {
      continue;
    }

    final fileCompleter = Completer<PickedTabularFile?>();
    final reader = html.FileReader();
    reader.onError.first.then((_) {
      if (!fileCompleter.isCompleted) fileCompleter.complete(null);
    });
    reader.onLoadEnd.first.then((_) {
      if (fileCompleter.isCompleted) return;
      final result = reader.result;
      if (result == null) {
        fileCompleter.complete(null);
        return;
      }
      try {
        List<int> bytes;
        if (result is ByteBuffer) {
          bytes = result.asUint8List().toList();
        } else if (result is TypedData) {
          bytes = result.buffer.asUint8List().toList();
        } else if (result is List<int>) {
          bytes = result;
        } else {
          bytes = (result as dynamic).asUint8List().toList();
        }
        fileCompleter.complete(
          PickedTabularFile(
            name: file.name,
            extension: extension,
            bytes: bytes,
            text: extension == 'csv'
                ? utf8.decode(bytes, allowMalformed: true)
                : null,
          ),
        );
      } catch (e) {
        fileCompleter.complete(null);
      }
    });
    reader.readAsArrayBuffer(file);

    final picked = await fileCompleter.future;
    if (picked != null) {
      pickedFiles.add(picked);
    }
  }
  return pickedFiles;
}

StreamSubscription? setupDropzoneListener(
  void Function(List<PickedTabularFile> files) onFilesDropped,
) {
  html.document.body?.onDragOver.listen((event) {
    event.preventDefault();
  });
  return html.document.body?.onDrop.listen((event) async {
    event.preventDefault();
    final dtFiles = event.dataTransfer.files;
    if (dtFiles == null || dtFiles.isEmpty) return;

    final pickedFiles = await _parseHtmlFiles(dtFiles);
    if (pickedFiles.isNotEmpty) {
      onFilesDropped(pickedFiles);
    }
  });
}

