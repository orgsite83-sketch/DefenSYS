import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/repository_audit_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/utils/pdf_viewer.dart';
import 'package:defensys/widgets/feedback_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StatusOverrideDialog {
  static Widget _dialogDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      initialValue: value,
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
    );
  }

  static Future<void> showOverrideDialog({
    required BuildContext context,
    required WidgetRef ref,
    required Map<String, dynamic> entry,
  }) async {
    String status = entry['status']?.toString() ?? 'Approved';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Override PIT Status'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => _dialogDropdown(
            label: 'Status',
            value: status,
            items: const ['Approved', 'Needs Revision'],
            onChanged: (value) =>
                setDialogState(() => status = value ?? status),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!context.mounted || saved != true) {
      return;
    }
    await ref
        .read(repositoryAuditProvider.notifier)
        .overrideStatus(entry['id'].toString(), status);
  }

  static Future<void> viewPdf({
    required BuildContext context,
    required WidgetRef ref,
    required String fileUrl,
    required String fileName,
  }) async {
    if (fileUrl.isEmpty) {
      showErrorToast(context, 'File URL not available');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.maroon),
      ),
    );

    try {
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile(fileUrl);
      if (context.mounted) Navigator.pop(context);
      if (!context.mounted) return;
      await viewFileInDialog(
        context: context,
        fileBytes: bytes,
        fileName: fileName,
      );
    } catch (e) {
      if (context.mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (context.mounted) {
        showErrorToast(context, 'Error opening file: $e');
      }
    }
  }

  static Future<void> downloadFile({
    required BuildContext context,
    required WidgetRef ref,
    required String fileUrl,
    required String fileName,
  }) async {
    if (fileUrl.isEmpty) {
      showErrorToast(context, 'File URL not available');
      return;
    }

    try {
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile(fileUrl);
      await downloadBytesFile(bytes: bytes, fileName: fileName);
      if (!context.mounted) return;
      showSuccessToast(
        context,
        'Downloaded $fileName',
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      if (!context.mounted) return;
      showErrorToast(context, 'Download failed: $e');
    }
  }

  static Future<void> exportCsv({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final csv = await ref.read(repositoryAuditProvider.notifier).exportCsv();
    if (!context.mounted || csv == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Project Archive CSV'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(child: SelectableText(csv)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
