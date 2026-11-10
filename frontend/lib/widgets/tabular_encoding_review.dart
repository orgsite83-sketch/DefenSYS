import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../utils/csv_file_io.dart';
import 'shadcn/defensys_shadcn_scope.dart';

/// Validate the complete selection before changing staged data. Confirmation is
/// per file, and only the validated file object carries that confirmation.
Future<List<PickedTabularFile>?> prepareTabularFiles(
  BuildContext context,
  List<PickedTabularFile> files,
) async {
  for (final file in files) {
    if (file.readError != null) {
      throw FormatException('${file.name}: ${file.readError}');
    }
    if (file.isText) file.decoded;
  }
  final result = <PickedTabularFile>[];
  for (final file in files) {
    if (file.isText &&
        file.decoded.needsConfirmation &&
        !file.encodingConfirmed) {
      if (!context.mounted) return null;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => DefensysShadcnScope(
          maroonActions: true,
          child: ShadDialog(
            actionsAxis: Axis.vertical,
            constraints: const BoxConstraints(maxWidth: 520),
            title: Text(
              file.decoded.encoding == 'Windows-1252'
                  ? 'Legacy CSV: confirm these names'
                  : 'Check name encoding',
            ),
            description: Text(file.name),
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ShadButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Names display correctly'),
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Check these values against the original file. If they look wrong, resave as UTF-8 CSV or upload XLSX.',
                ),
                const SizedBox(height: 12),
                for (final sample in file.decoded.samples)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SelectableText(sample),
                  ),
                Text(
                  'Read as ${file.decoded.encoding}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
      if (accepted != true) return null;
      result.add(file.confirmEncoding());
    } else {
      result.add(file);
    }
  }
  return result;
}
