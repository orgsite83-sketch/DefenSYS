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

Future<String?> pickCsvTextFile() {
  final completer = Completer<String?>();
  final input = html.FileUploadInputElement()
    ..accept = '.csv,text/csv'
    ..multiple = false;

  input.onChange.first.then((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      return;
    }

    final reader = html.FileReader();
    reader.onError.first.then((_) {
      if (!completer.isCompleted) {
        completer.completeError('Unable to read the selected CSV file.');
      }
    });
    reader.onLoadEnd.first.then((_) {
      if (!completer.isCompleted) {
        completer.complete(reader.result?.toString());
      }
    });
    reader.readAsText(files.first);
  });

  input.click();
  return completer.future;
}

Future<PickedTabularFile?> pickTabularDataFile() {
  final completer = Completer<PickedTabularFile?>();
  final input = html.FileUploadInputElement()
    ..accept =
        '.csv,.xlsx,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    ..multiple = false;

  input.onChange.first.then((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      return;
    }

    final file = files.first;
    final extension = file.name.toLowerCase().split('.').last;
    if (extension != 'csv' && extension != 'xlsx') {
      completer.completeError('Select a CSV or XLSX file.');
      return;
    }

    final reader = html.FileReader();
    reader.onError.first.then((_) {
      if (!completer.isCompleted) {
        completer.completeError('Unable to read the selected class list file.');
      }
    });
    reader.onLoadEnd.first.then((_) {
      if (completer.isCompleted) return;
      final result = reader.result;
      if (result == null) {
        completer.completeError('Unable to read the selected class list file.');
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
        completer.complete(
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
        completer.completeError('Unable to read file bytes: $e');
      }
    });
    reader.readAsArrayBuffer(file);
  });

  input.click();
  return completer.future;
}
