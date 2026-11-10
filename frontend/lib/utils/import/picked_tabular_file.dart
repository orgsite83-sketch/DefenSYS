import 'tabular_text_decode.dart';

final _decodedFiles = Expando<DecodedTabularText>();

class PickedTabularFile {
  const PickedTabularFile({
    required this.name,
    required this.extension,
    required this.bytes,
    String? text,
    this.readError,
    this.encodingConfirmed = false,
    DecodedTabularText? decoded,
  }) : _suppliedText = text,
       _decoded = decoded;
  final String name, extension;
  final List<int> bytes;
  final String? _suppliedText, readError;
  final bool encodingConfirmed;
  final DecodedTabularText? _decoded;
  bool get isCsv => extension == 'csv';
  bool get isXlsx => extension == 'xlsx';
  bool get isText => const ['csv', 'tsv', 'txt'].contains(extension);

  DecodedTabularText get decoded {
    try {
      if (readError != null) throw FormatException(readError!);
      return _decoded ??
          (_decodedFiles[this] ??= decodeTabularText(
            bytes,
            suppliedText: _suppliedText,
          ));
    } on FormatException catch (error) {
      throw FormatException('$name: ${error.message}');
    }
  }

  String get decodedText {
    final result = decoded;
    if (result.needsConfirmation && !encodingConfirmed) {
      throw FormatException(
        '$name: confirm the decoded names before importing this file.',
      );
    }
    return result.text;
  }

  String? get text => isText ? decodedText : _suppliedText;
  PickedTabularFile confirmEncoding() => PickedTabularFile(
    name: name,
    extension: extension,
    bytes: bytes,
    text: _suppliedText,
    readError: readError,
    encodingConfirmed: true,
    decoded: decoded,
  );
}
