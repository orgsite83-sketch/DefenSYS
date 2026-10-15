import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;
import 'package:xml/xml.dart';

/// Sanitizes raw XLSX bytes before passing to `package:excel`.
///
/// Fixes an upstream bug in `excel: ^4.0.6` where worksheet relationship targets
/// with absolute or rooted paths (e.g., `Target="/xl/worksheets/sheet1.xml"` or
/// `Target="xl/worksheets/sheet1.xml"`) cause `file!.decompress()` to crash with
/// "Null check operator used on a null value".
xl.Excel safeDecodeExcel(List<int> rawBytes) {
  final archive = ZipDecoder().decodeBytes(rawBytes);
  final relations = archive.findFile('xl/_rels/workbook.xml.rels');
  if (relations == null) {
    throw const FormatException('The XLSX workbook relationships are missing.');
  }
  final document = XmlDocument.parse(
    utf8.decode(relations.content as List<int>),
  );
  var modified = false;
  for (final node in document.findAllElements('Relationship')) {
    if (node.getAttribute('TargetMode') == 'External') continue;
    final target = node.getAttribute('Target');
    if (target == null) continue;
    // excel 4.x resolves these paths by prepending "xl/". Keep relative
    // paths intact, and strip the workbook root from rooted paths only.
    final normalized = target.startsWith('/xl/')
        ? target.substring(4)
        : target.startsWith('xl/')
        ? target.substring(3)
        : target;
    if (target != normalized) {
      node.setAttribute('Target', normalized);
      modified = true;
    }
  }
  if (!modified) return xl.Excel.decodeBytes(rawBytes);
  final content = utf8.encode(document.toXmlString());
  archive.addFile(ArchiveFile(relations.name, content.length, content));
  final normalizedBytes = ZipEncoder().encode(archive);
  if (normalizedBytes == null) {
    throw const FormatException('The XLSX workbook could not be decoded.');
  }
  return xl.Excel.decodeBytes(normalizedBytes);
}
