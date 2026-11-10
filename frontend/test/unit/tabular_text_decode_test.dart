import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:defensys/utils/import/tabular_text_decode.dart';
import 'package:defensys/utils/csv_file_io.dart';

void main() {
  const text = 'id_number,first_name,last_name\n213,RAY AN,QUI\u00d1ON';
  test('UTF-8 BOM and both UTF-16 BOMs preserve names', () {
    final variants = <List<int>>[
      utf8.encode(text),
      [0xef, 0xbb, 0xbf, ...utf8.encode(text)],
      [
        0xff,
        0xfe,
        ...text.codeUnits.expand((v) => [v & 255, v >> 8]),
      ],
      [
        0xfe,
        0xff,
        ...text.codeUnits.expand((v) => [v >> 8, v & 255]),
      ],
    ];
    for (final bytes in variants) {
      final decoded = decodeTabularText(bytes);
      expect(decoded.text, text);
      expect(decoded.needsConfirmation, isFalse);
    }
    expect(
      decodeTabularText([0xff, 0xfe, 0x3d, 0xd8, 0x00, 0xde]).text,
      '\ud83d\ude00',
    );
  });
  test(
    'legacy Excel names require confirmation and bytes override damaged cached text',
    () {
      final file = PickedTabularFile(
        name: 'faculty.csv',
        extension: 'csv',
        bytes: text.codeUnits,
        text: 'QUI\ufffdON',
      );
      expect(file.decoded.encoding, 'Windows-1252');
      expect(file.decoded.text, text);
      expect(() => file.decodedText, throwsFormatException);
      expect(file.confirmEncoding().decodedText, text);
      expect(file.decoded.samples, ['QUI\u00d1ON']);
    },
  );
  test(
    'invalid declared encodings undefined legacy bytes and damaged text fail',
    () {
      for (final bytes in <List<int>>[
        [0xef, 0xbb, 0xbf, 0xd1],
        [0x81],
        [0xff, 0xfe, 1],
        [0xff, 0xfe, 0, 0xd8],
        [0, 1],
        utf8.encode('Name\ufffd'),
      ]) {
        expect(() => decodeTabularText(bytes), throwsFormatException);
      }
      expect(
        () => decodeTabularText([], suppliedText: 'Name\ufffd'),
        throwsFormatException,
      );
      expect(decodeTabularText([], suppliedText: text).text, text);
    },
  );
  test(
    'suspected mojibake requires review and Excel CSV export round trips',
    () {
      expect(
        decodeTabularText(utf8.encode('QUI\u00c3\u2018ON')).needsConfirmation,
        isTrue,
      );
      final exported = encodeExcelCsv(text);
      expect(exported.take(3), [0xef, 0xbb, 0xbf]);
      expect(decodeTabularText(exported).text, text);
      expect(encodeExcelCsv('\ufeff$text'), exported);
    },
  );
  test(
    'read failures keep the filename and are not converted into empty files',
    () {
      const file = PickedTabularFile(
        name: 'failed.csv',
        extension: 'csv',
        bytes: [],
        readError: 'Unreadable',
      );
      expect(
        () => file.decodedText,
        throwsA(predicate((e) => '$e'.contains('failed.csv'))),
      );
    },
  );
}
