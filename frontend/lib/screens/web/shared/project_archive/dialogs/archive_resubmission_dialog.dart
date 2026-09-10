import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/project_archive_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/universal_file_viewer.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/widgets/tactile_button.dart';
import 'package:defensys/utils/csv_file_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ArchiveResubmissionDialog {
  static Future<void> showResubmissionDialog({
    required BuildContext context,
    required WidgetRef ref,
    required Map<String, dynamic> entry,
  }) async {
    final entryId = entry['id']?.toString() ?? '';
    final currentFileName =
        entry['file_name']?.toString() ?? entry['deliverable_label']?.toString() ?? 'File';
    final teamName = entry['team_name']?.toString() ?? 'Team';
    final status = entry['status']?.toString() ?? 'Approved';
    final existingFeedback = (entry['feedback']?.toString() ?? entry['remarks']?.toString() ?? '').trim();
    final deliverableTypeLabel = (entry['deliverable_type_label']?.toString().isNotEmpty == true)
        ? entry['deliverable_type_label'].toString()
        : (entry['deliverable_type']?.toString().toLowerCase() == 'post' ? 'Post-Defense' : 'Pre-Defense');

    final isNeedsRevision = status == 'Needs Revision' || status == 'Rejected' || status == 'Needs Re-upload';
    final isReplacementUnlocked = !isNeedsRevision &&
        ((entry['archive_unlocked'] == true) ||
            (entry['unlocked'] == true) ||
            existingFeedback.toLowerCase().contains('unlocked for file replacement') ||
            existingFeedback.toLowerCase().contains('unlocked'));

    final displayStatus = isNeedsRevision
        ? 'Needs Revision (Pending Student Re-upload)'
        : (isReplacementUnlocked ? 'Approved (File Replacement Unlocked)' : status);

    PlatformFile? selectedFile;
    final feedbackController = TextEditingController();

    final actionChoice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            width: 560,
            decoration: DefensysTokens.dialogDecoration(),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Request File Resubmission or Replacement',
                      style: DefensysTokens.dialogTitle.copyWith(color: DefensysTokens.maroon),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: DefensysTokens.steelGrey),
                      onPressed: () => Navigator.pop(dialogContext, null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                currentFileName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (teamName.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                'Team: $teamName',
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: Text(
                                  'Type: $deliverableTypeLabel',
                                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isNeedsRevision
                                      ? const Color(0xFFFEF3C7)
                                      : (isReplacementUnlocked ? const Color(0xFFCCFBF1) : const Color(0xFFECFDF5)),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isNeedsRevision
                                        ? const Color(0xFFF59E0B)
                                        : (isReplacementUnlocked ? const Color(0xFF0D9488) : const Color(0xFF10B981)),
                                  ),
                                ),
                                child: Text(
                                  'Status: $displayStatus',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isNeedsRevision
                                        ? const Color(0xFFB45309)
                                        : (isReplacementUnlocked ? const Color(0xFF115E59) : const Color(0xFF047857)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (existingFeedback.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFFCD34D)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.comment_outlined, size: 15, color: Color(0xFFD97706)),
                                    SizedBox(width: 6),
                                    Text(
                                      'Current Remarks & Author:',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF92400E),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  existingFeedback,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF78350F),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Choose how to replace or update this file:',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  // Option 1: Unlock for Student Re-upload (Student Portal Action)
                  Card(
                    elevation: 0,
                    color: const Color(0xFFEFF6FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFFBFDBFE)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.published_with_changes_rounded, color: Color(0xFF2563EB), size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Option 1: Request Student Re-upload (Student Portal)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: Color(0xFF1E40AF),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Unlocks the submission slot in team $teamName\'s student portal so students upload their file themselves. Choose the status outcome:',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF1E3A8A)),
                          ),
                          const SizedBox(height: 12),
                          if (isNeedsRevision) ...[
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFF59E0B)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 18),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Student Re-upload is currently PENDING. The slot is open in the student portal.',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF92400E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          // Sub-Option 1A: Needs Revision
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.edit_note_rounded, color: Colors.orange, size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      'Choice A: Document Content Revision',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF1E293B)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Sets status to "Needs Revision" for required manuscript corrections.',
                                  style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: feedbackController,
                                  decoration: InputDecoration(
                                    hintText: 'Adviser/Admin Remarks (e.g. "Fix Chapter 3 bibliography")',
                                    hintStyle: const TextStyle(fontSize: 11.5, color: Colors.grey),
                                    helperText: 'Your name & role will automatically be attached to remarks.',
                                    helperStyle: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2563EB),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                    onPressed: () => Navigator.pop(dialogContext, 'unlock_needs_revision'),
                                    icon: const Icon(Icons.send_rounded, size: 15),
                                    label: Text(
                                      isNeedsRevision ? 'Update Remarks & Keep "Needs Revision"' : 'Unlock with "Needs Revision" Status',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Sub-Option 1B: Allow Replacement (Keep Approved)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.swap_horiz_rounded, color: Colors.teal, size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      'Choice B: Wrong File Replacement',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF1E293B)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Keeps status as "Approved" but enables "Replace File" in student portal for wrong file upload fixes.',
                                  style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                                ),
                                if (isReplacementUnlocked) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFCCFBF1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF0D9488)),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.lock_open_rounded, color: Color(0xFF0D9488), size: 16),
                                        SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'File Replacement is currently UNLOCKED for students.',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF115E59),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0D9488),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                    onPressed: () => Navigator.pop(dialogContext, 'unlock_keep_approved'),
                                    icon: const Icon(Icons.lock_open_rounded, size: 15),
                                    label: Text(
                                      isReplacementUnlocked
                                          ? 'Re-confirm Unlock Replacement (Keep Status Approved)'
                                          : 'Unlock Replacement (Keep Status Approved)',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Option 2: Direct Admin Upload (Secondary)
                  Card(
                    elevation: 0,
                    color: const Color(0xFFF8FAFC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.upload_file_rounded, color: AppColors.maroon, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Option 2: Upload Corrected File Directly as Admin',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Select a replacement PDF file to upload directly right now on behalf of the team.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            onTap: () async {
                              final picked = await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['pdf'],
                                withData: true,
                              );
                              if (picked != null && picked.files.isNotEmpty) {
                                setDialogState(() {
                                  selectedFile = picked.files.first;
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              decoration: BoxDecoration(
                                color: selectedFile != null
                                    ? AppColors.success.withValues(alpha: 0.08)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selectedFile != null
                                      ? AppColors.success
                                      : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selectedFile != null ? Icons.check_circle_rounded : Icons.folder_open_rounded,
                                    color: selectedFile != null ? AppColors.success : AppColors.maroon,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      selectedFile != null
                                          ? selectedFile!.name
                                          : 'Select replacement PDF file...',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: selectedFile != null ? AppColors.success : AppColors.maroon,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (selectedFile != null) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: TactileButton.primary(
                                label: 'Upload File Now',
                                onPressed: () => Navigator.pop(dialogContext, 'admin_upload'),
                                icon: const Icon(Icons.swap_vert_rounded, size: 16, color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  ),
),
);

    if (!context.mounted || actionChoice == null) {
      return;
    }

    if (actionChoice == 'unlock_needs_revision') {
      final success = await ref.read(repositoryAuditProvider.notifier).requestResubmission(
            entryId,
            status: 'Needs Revision',
            feedback: feedbackController.text.trim(),
          );
      if (context.mounted) {
        if (success) {
          showSuccessToast(context, 'Unlocked for student resubmission with Needs Revision ($teamName)');
        } else {
          showErrorToast(context, 'Failed to unlock for resubmission');
        }
      }
    } else if (actionChoice == 'unlock_keep_approved') {
      final success = await ref.read(repositoryAuditProvider.notifier).requestResubmission(
            entryId,
            status: 'Approved',
            feedback: 'Unlocked for file replacement by Admin',
          );
      if (context.mounted) {
        if (success) {
          showSuccessToast(context, 'Unlocked file replacement for student team ($teamName)');
        } else {
          showErrorToast(context, 'Failed to unlock file replacement');
        }
      }
    } else if (actionChoice == 'admin_upload' && selectedFile != null && selectedFile!.bytes != null) {
      final success = await ref
          .read(repositoryAuditProvider.notifier)
          .replaceFile(entryId, selectedFile!.bytes!, selectedFile!.name);
      if (context.mounted) {
        if (success) {
          showSuccessToast(context, 'PDF file replaced successfully');
        } else {
          showErrorToast(context, 'Failed to replace PDF file');
        }
      }
    }
  }

  static Future<void> showOverrideDialog({
    required BuildContext context,
    required WidgetRef ref,
    required Map<String, dynamic> entry,
  }) {
    return showResubmissionDialog(context: context, ref: ref, entry: entry);
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
    if (!context.mounted) return;
    if (csv == null || csv.trim().isEmpty) {
      final error = ref.read(repositoryAuditProvider).error ?? 'Failed to export archive records.';
      showErrorToast(context, error);
      return;
    }
    try {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final fileName = 'project_archive_records_$dateStr.csv';
      await downloadTextFile(
        filename: fileName,
        content: csv,
      );
      if (context.mounted) {
        showSuccessToast(context, 'Archive records exported to $fileName');
      }
    } catch (e) {
      if (context.mounted) {
        showErrorToast(context, 'Failed to save export file: $e');
      }
    }
  }
}

typedef StatusOverrideDialog = ArchiveResubmissionDialog;
