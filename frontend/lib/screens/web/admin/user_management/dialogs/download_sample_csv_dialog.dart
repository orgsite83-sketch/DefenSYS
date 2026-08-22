import 'package:flutter/material.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:defensys/utils/import/student_bulk_import_csv.dart';

/// Modal dialog for choosing a year level to download sample official class list CSV template.
class DownloadSampleCsvDialog extends StatelessWidget {
  const DownloadSampleCsvDialog({super.key});

  static Future<String?> show(BuildContext context) async {
    final year = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const DownloadSampleCsvDialog(),
    );

    if (year != null && year.isNotEmpty) {
      final sample = sampleStudentCsvForYear(year);
      final filename = sampleStudentCsvFilenameForYear(year);
      await downloadTextFile(
        filename: filename,
        content: sample,
      );
      if (context.mounted) {
        ToastService.success(context, 'Official class list sample for $year downloaded.');
      }
    }
    return year;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text('Download Official Class List Sample'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select a year level to download the matching official university class list template (.csv):',
              style: TextStyle(fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 16),
            for (final year in studentSampleYearLevels)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.download_rounded, size: 16),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1E293B),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    alignment: Alignment.centerLeft,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(year),
                  label: Text('Download $year Class List Template'),
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
