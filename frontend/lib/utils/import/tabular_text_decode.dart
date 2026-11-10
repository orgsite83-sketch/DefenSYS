import 'dart:convert';

class DecodedTabularText {
  const DecodedTabularText(
    this.text,
    this.encoding, {
    this.needsConfirmation = false,
  });
  final String text, encoding;
  final bool needsConfirmation;

  List<String> get samples => text
      .split(RegExp(r'[,;\t\r\n]'))
      .map((v) => v.trim().replaceAll('"', ''))
      .where((v) => v.runes.any((r) => r > 127))
      .toSet()
      .take(4)
      .toList();
}

const _windowsControls = <int?>[
  0x20ac,
  null,
  0x201a,
  0x0192,
  0x201e,
  0x2026,
  0x2020,
  0x2021,
  0x02c6,
  0x2030,
  0x0160,
  0x2039,
  0x0152,
  null,
  0x017d,
  null,
  null,
  0x2018,
  0x2019,
  0x201c,
  0x201d,
  0x2022,
  0x2013,
  0x2014,
  0x02dc,
  0x2122,
  0x0161,
  0x203a,
  0x0153,
  null,
  0x017e,
  0x0178,
];

void validateTabularText(String text) {
  if (text.contains('\ufffd')) {
    throw const FormatException(
      'Name encoding problem: replacement characters are present. Use an intact source or resave as UTF-8 CSV/XLSX.',
    );
  }
  if (RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]').hasMatch(text)) {
    throw const FormatException(
      'Unsupported text encoding or invalid control characters. Resave as UTF-8 CSV or XLSX.',
    );
  }
}

DecodedTabularText decodeTabularText(List<int> bytes, {String? suppliedText}) {
  String text, encoding;
  var legacy = false;
  bool starts(List<int> prefix) =>
      bytes.length >= prefix.length &&
      List.generate(
        prefix.length,
        (i) => bytes[i] == prefix[i],
      ).every((v) => v);
  if (bytes.isEmpty) {
    text = suppliedText ?? '';
    encoding = 'Provided text';
  } else if (starts([0xff, 0xfe, 0, 0]) || starts([0, 0, 0xfe, 0xff])) {
    throw const FormatException(
      'UTF-32 is not supported. Resave as UTF-8 CSV or XLSX.',
    );
  } else if (starts([0xef, 0xbb, 0xbf])) {
    text = utf8.decode(bytes.sublist(3));
    encoding = 'UTF-8';
  } else if (starts([0xff, 0xfe]) || starts([0xfe, 0xff])) {
    if (bytes.length.isOdd) {
      throw const FormatException('Invalid UTF-16 byte length.');
    }
    final little = bytes[0] == 0xff;
    final units = <int>[];
    for (var i = 2; i < bytes.length; i += 2) {
      units.add(
        little ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
      );
    }
    for (var i = 0; i < units.length; i++) {
      if (units[i] >= 0xd800 && units[i] <= 0xdbff) {
        if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
          throw const FormatException('Invalid UTF-16 surrogate pair.');
        }
      } else if (units[i] >= 0xdc00 && units[i] <= 0xdfff) {
        throw const FormatException('Invalid UTF-16 surrogate pair.');
      }
    }
    text = String.fromCharCodes(units);
    encoding = little ? 'UTF-16 LE' : 'UTF-16 BE';
  } else {
    try {
      text = utf8.decode(bytes);
      encoding = 'UTF-8';
    } on FormatException {
      final codes = <int>[];
      for (final byte in bytes) {
        final code = byte >= 0x80 && byte <= 0x9f
            ? _windowsControls[byte - 0x80]
            : byte;
        if (code == null || byte < 0 || byte > 255) {
          throw const FormatException(
            'Unsupported legacy CSV encoding. Resave as UTF-8 CSV or XLSX.',
          );
        }
        codes.add(code);
      }
      text = String.fromCharCodes(codes);
      encoding = 'Windows-1252';
      legacy = true;
    }
  }
  if (text.startsWith('\ufeff')) text = text.substring(1);
  validateTabularText(text);
  final suspicious = RegExp(
    '\u00c3[\u0080-\u00bf\u2018\u2019\u201c\u201d]|\u00c2[\u0080-\u00bf]',
  ).hasMatch(text);
  return DecodedTabularText(
    text,
    encoding,
    needsConfirmation: legacy || suspicious,
  );
}

List<int> encodeExcelCsv(String content) =>
    utf8.encode(content.startsWith('\ufeff') ? content : '\ufeff$content');
