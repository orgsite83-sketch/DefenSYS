import 'package:flutter/material.dart';
import 'package:defensys/utils/student_bulk_import_csv.dart';

/// Modal dialog for choosing a year level to download sample CSV template.
class DownloadSampleCsvDialog extends StatelessWidget {
  const DownloadSampleCsvDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => const DownloadSampleCsvDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text('Download official class list sample'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Each file follows the official class list shape and includes '
              'one section plus four students for the chosen year level.',
              style: TextStyle(fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 16),
            for (final year in studentSampleYearLevels)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(year),
                  child: Text(year),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
