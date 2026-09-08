import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:defensys/config/api_config.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/progress_upload.dart';
import 'package:defensys/utils/universal_file_viewer.dart';

String formatUploadFailureMessage(int statusCode, String responseBody) {
  try {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map) {
      final detail = decoded['detail'];
      if (detail is String && detail.isNotEmpty) {
        return 'Upload failed: $detail';
      }
      final lines = <String>[];
      decoded.forEach((key, value) {
        if (value is List) {
          for (final item in value) {
            lines.add('$key: $item');
          }
        } else {
          lines.add('$key: $value');
        }
      });
      if (lines.isNotEmpty) {
        return 'Upload failed: ${lines.join(' ')}';
      }
    }
  } catch (_) {
    // Not JSON (e.g. legacy HTML error page).
  }
  if (responseBody.contains('<!DOCTYPE html>') ||
      responseBody.contains('<html')) {
    return 'Upload failed (server error $statusCode). Check backend logs or try again.';
  }
  final trimmed = responseBody.trim();
  if (trimmed.isEmpty) {
    return 'Upload failed (status $statusCode).';
  }
  return 'Upload failed: $trimmed';
}

Future<void> showUploadDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> team,
  required String stageLabel,
  required Map<String, dynamic> item,
  int? fileId,
}) async {
  String? selectedFileName;
  String? selectedFileSize;
  List<int>? selectedFileBytes;
  bool isUploading = false;
  double uploadProgress = 0.0;
  String? uploadError;

  final rawFormat = item['file_format'] ?? item['fileFormat'];
  final formatInfo = DeliverableFormatInfo.fromFormat(rawFormat?.toString());
  final suggestedName = item['suggested_file_name']?.toString() ?? '';

  await showDialog<bool>(
    context: context,
    barrierDismissible: false, // Prevent dismissal during upload
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Upload ${item['id']}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['label']?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: formatInfo.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: formatInfo.color.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(formatInfo.icon, size: 15, color: formatInfo.color),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Accepted: ${formatInfo.description}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: formatInfo.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (suggestedName.isNotEmpty && item['type'] == 'post') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.label_important_outline, size: 15, color: Colors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Expected name: $suggestedName',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (!isUploading)
                OutlinedButton.icon(
                  onPressed: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: formatInfo.extensions,
                      withData: true, // Load file bytes
                    );

                    if (result != null &&
                        result.files.single.name.isNotEmpty) {
                      setState(() {
                        selectedFileName = result.files.single.name;
                        selectedFileBytes = result.files.single.bytes;
                        final bytes = result.files.single.size;
                        selectedFileSize =
                            '${(bytes / 1024).toStringAsFixed(2)} KB';
                        uploadError = null;
                      });
                    }
                  },
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Choose File'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              const SizedBox(height: 16),
              if (selectedFileName != null && !isUploading) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedFileName!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              selectedFileSize ?? '',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (!isUploading) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No file selected. Click "Choose File" to select a file.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (isUploading) ...[
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: uploadProgress,
                          color: AppColors.success,
                          backgroundColor: AppColors.success.withValues(
                            alpha: 0.12,
                          ),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${(uploadProgress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Uploading ${selectedFileName ?? "file"}...',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              if (uploadError != null) ...[
                const SizedBox(height: 12),
                Text(
                  uploadError!,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: isUploading
                ? null
                : () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: (selectedFileName != null && !isUploading)
                ? () async {
                    final ext = selectedFileName!.contains('.')
                        ? selectedFileName!.split('.').last.toLowerCase()
                        : '';
                    if (formatInfo.extensions.isNotEmpty &&
                        !formatInfo.extensions.contains(ext)) {
                      setState(() {
                        uploadError =
                            "Invalid file format (.$ext). Please upload a file matching: ${formatInfo.description}";
                      });
                      return;
                    }

                    final suggestedName =
                        item['suggested_file_name']?.toString() ?? '';
                    if (item['type'] == 'post' && suggestedName.isNotEmpty) {
                      if (selectedFileName!.trim().toLowerCase() !=
                          suggestedName.trim().toLowerCase()) {
                        setState(() {
                          uploadError =
                              "File name must match the naming convention exactly.\nExpected: '$suggestedName'";
                        });
                        return;
                      }
                    }

                    setState(() {
                      isUploading = true;
                      uploadProgress = 0.0;
                      uploadError = null;
                    });

                    try {
                      final client = ref.read(
                        authenticatedHttpClientProvider,
                      );
                      final uri = Uri.parse(
                        '${ApiConfig.capstoneDeliverablesUrl}/upload/',
                      );

                      final request = MultipartRequestWithProgress(
                        'POST',
                        uri,
                        onProgress: (bytesSent, totalBytes) {
                          if (totalBytes > 0) {
                            setState(() {
                              uploadProgress = bytesSent / totalBytes;
                            });
                          }
                        },
                      );

                      // Add form fields
                      request.fields['team_id'] = team['id'].toString();
                      request.fields['stage_label'] = stageLabel;
                      request.fields['deliverable_id'] = item['id'].toString();
                      request.fields['file_name'] = selectedFileName!;
                      request.fields['file_size'] = selectedFileSize ?? '';
                      if (fileId != null) {
                        request.fields['file_id'] = fileId.toString();
                      }

                      // Add file
                      request.files.add(
                        http.MultipartFile.fromBytes(
                          'file',
                          selectedFileBytes!,
                          filename: selectedFileName!,
                        ),
                      );

                      final response = await client.sendAuthenticated(
                        request,
                      );

                      if (response.statusCode == 200) {
                        // Refresh deliverables list
                        await ref
                            .read(capstoneDeliverablesProvider.notifier)
                            .fetchDeliverables(
                              successMessage:
                                  'Deliverable file uploaded successfully.',
                            );
                        if (context.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } else {
                        final responseBody = await response.stream
                            .bytesToString();
                        setState(() {
                          isUploading = false;
                          uploadError = formatUploadFailureMessage(
                            response.statusCode,
                            responseBody,
                          );
                        });
                      }
                    } catch (e) {
                      setState(() {
                        isUploading = false;
                        uploadError = 'Upload error: $e';
                      });
                    }
                  }
                : null,
            icon: isUploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 16),
            label: Text(isUploading ? 'Saving...' : 'Save Upload'),
            style: DefensysTokens.saveButtonStyle(isPill: false),
          ),
        ],
      ),
    ),
  );
}
