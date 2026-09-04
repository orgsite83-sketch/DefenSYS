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
  final futures = files.map((file) async {
    final extension = file.name.contains('.')
        ? file.name.toLowerCase().split('.').last
        : '';

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
            text: extension == 'csv' || extension == 'txt' || extension == 'tsv'
                ? utf8.decode(bytes, allowMalformed: true)
                : null,
          ),
        );
      } catch (e) {
        fileCompleter.complete(null);
      }
    });
    try {
      reader.readAsArrayBuffer(file);
    } catch (_) {
      if (!fileCompleter.isCompleted) fileCompleter.complete(null);
    }
    return await fileCompleter.future;
  });

  final results = await Future.wait(futures);
  return results.whereType<PickedTabularFile>().toList();
}

class _DropzoneEntry {
  final void Function(List<PickedTabularFile> files) onFilesDropped;
  final void Function(bool isDragging)? onDragStateChanged;
  final void Function(List<String> rejectedFileNames)? onRejectedFiles;

  _DropzoneEntry({
    required this.onFilesDropped,
    this.onDragStateChanged,
    this.onRejectedFiles,
  });
}

class _DropzoneManager {
  static final _DropzoneManager instance = _DropzoneManager._();
  _DropzoneManager._();

  final List<_DropzoneEntry> _listeners = [];
  bool _isDragging = false;
  Timer? _dragDebounceTimer;

  StreamSubscription? _winDragEnterSub;
  StreamSubscription? _winDragOverSub;
  StreamSubscription? _winDragLeaveSub;
  StreamSubscription? _winDropSub;

  StreamSubscription? _bodyDragOverSub;
  StreamSubscription? _bodyDropSub;

  void _attachDomListeners() {
    if (_winDragOverSub != null) return;

    void handleDragOver(html.MouseEvent event) {
      event.preventDefault();
      try {
        event.dataTransfer.dropEffect = 'copy';
      } catch (_) {}

      if (!_isDragging) {
        _isDragging = true;
        _notifyDragState(true);
      }

      _dragDebounceTimer?.cancel();
      _dragDebounceTimer = Timer(const Duration(milliseconds: 350), () {
        if (_isDragging) {
          _isDragging = false;
          _notifyDragState(false);
        }
      });
    }

    void handleDragEnter(html.MouseEvent event) {
      event.preventDefault();
      try {
        event.dataTransfer.dropEffect = 'copy';
      } catch (_) {}

      if (!_isDragging) {
        _isDragging = true;
        _notifyDragState(true);
      }
    }

    void handleDragLeave(html.MouseEvent event) {
      event.preventDefault();
      final x = event.client.x;
      final y = event.client.y;
      final w = html.window.innerWidth ?? 0;
      final h = html.window.innerHeight ?? 0;
      if (x <= 0 || y <= 0 || (w > 0 && x >= w) || (h > 0 && y >= h)) {
        _dragDebounceTimer?.cancel();
        if (_isDragging) {
          _isDragging = false;
          _notifyDragState(false);
        }
      }
    }

    Future<void> handleDrop(html.MouseEvent event) async {
      event.preventDefault();
      _dragDebounceTimer?.cancel();
      if (_isDragging) {
        _isDragging = false;
        _notifyDragState(false);
      }

      final dtFiles = event.dataTransfer.files;
      if (dtFiles == null || dtFiles.isEmpty) return;

      final fileList = List<html.File>.from(dtFiles);
      if (_listeners.isEmpty) return;
      final activeListener = _listeners.last;

      final pickedFiles = await _parseHtmlFiles(fileList);
      if (pickedFiles.isNotEmpty) {
        activeListener.onFilesDropped(pickedFiles);
      }
    }

    _winDragEnterSub = html.window.onDragEnter.listen(handleDragEnter);
    _winDragOverSub = html.window.onDragOver.listen(handleDragOver);
    _winDragLeaveSub = html.window.onDragLeave.listen(handleDragLeave);
    _winDropSub = html.window.onDrop.listen(handleDrop);

    // Also attach to document.body to ensure events bubbling within body are handled
    _bodyDragOverSub = html.document.body?.onDragOver.listen((e) => e.preventDefault());
    _bodyDropSub = html.document.body?.onDrop.listen((e) => e.preventDefault());
  }

  void _detachDomListeners() {
    _dragDebounceTimer?.cancel();
    _dragDebounceTimer = null;

    _winDragEnterSub?.cancel();
    _winDragOverSub?.cancel();
    _winDragLeaveSub?.cancel();
    _winDropSub?.cancel();

    _bodyDragOverSub?.cancel();
    _bodyDropSub?.cancel();

    _winDragEnterSub = null;
    _winDragOverSub = null;
    _winDragLeaveSub = null;
    _winDropSub = null;
    _bodyDragOverSub = null;
    _bodyDropSub = null;

    _isDragging = false;
  }

  void _notifyDragState(bool isDragging) {
    if (_listeners.isNotEmpty) {
      _listeners.last.onDragStateChanged?.call(isDragging);
    }
  }

  StreamSubscription<List<PickedTabularFile>> register(
    void Function(List<PickedTabularFile> files) onFilesDropped, {
    void Function(bool isDragging)? onDragStateChanged,
    void Function(List<String> rejectedFileNames)? onRejectedFiles,
  }) {
    final entry = _DropzoneEntry(
      onFilesDropped: onFilesDropped,
      onDragStateChanged: onDragStateChanged,
      onRejectedFiles: onRejectedFiles,
    );
    _listeners.add(entry);
    _attachDomListeners();

    late final StreamController<List<PickedTabularFile>> controller;
    controller = StreamController<List<PickedTabularFile>>(
      onCancel: () {
        _listeners.remove(entry);
        if (_listeners.isEmpty) {
          _detachDomListeners();
        } else if (_isDragging) {
          _notifyDragState(true);
        }
      },
    );

    return controller.stream.listen(null);
  }
}

StreamSubscription? setupDropzoneListener(
  void Function(List<PickedTabularFile> files) onFilesDropped, {
  void Function(bool isDragging)? onDragStateChanged,
  void Function(List<String> rejectedFileNames)? onRejectedFiles,
}) {
  return _DropzoneManager.instance.register(
    onFilesDropped,
    onDragStateChanged: onDragStateChanged,
    onRejectedFiles: onRejectedFiles,
  );
}

