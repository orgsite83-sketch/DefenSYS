import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/utils/csv_file_io.dart';

void main() {
  group('Dropzone Listener Platform Tests', () {
    test('setupDropzoneListener accepts callbacks and returns subscription on stub', () {
      bool isDraggingCalled = false;
      bool onFilesDroppedCalled = false;

      final sub = setupDropzoneListener(
        (files) {
          onFilesDroppedCalled = true;
        },
        onDragStateChanged: (isDragging) {
          isDraggingCalled = isDragging;
        },
      );

      // On non-web (VM/test), setupDropzoneListener safely returns null
      expect(sub, isNull);
      expect(isDraggingCalled, isFalse);
      expect(onFilesDroppedCalled, isFalse);
    });

    test('PickedTabularFile holds multiple files and recognizes extensions', () {
      final csvFile = PickedTabularFile(
        name: 'section_a.csv',
        extension: 'csv',
        bytes: Uint8List.fromList('id,name\n1,Alice'.codeUnits),
        text: 'id,name\n1,Alice',
      );

      final xlsxFile = PickedTabularFile(
        name: 'section_b.xlsx',
        extension: 'xlsx',
        bytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]),
      );

      expect(csvFile.isCsv, isTrue);
      expect(csvFile.isXlsx, isFalse);
      expect(csvFile.text, contains('Alice'));

      expect(xlsxFile.isCsv, isFalse);
      expect(xlsxFile.isXlsx, isTrue);
      expect(xlsxFile.bytes.length, 4);
    });
  });
}
