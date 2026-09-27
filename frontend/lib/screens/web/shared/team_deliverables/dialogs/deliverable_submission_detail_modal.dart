import 'dart:convert';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:defensys/config/api_config.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/progress_upload.dart';
import 'package:defensys/utils/universal_file_viewer.dart';

/// Smooth dashed border painter for the upload dropzone container.
class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;

  const _DashedRectPainter({
    required this.color,
    this.strokeWidth = 1.2,
    this.radius = 8.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double dash = 5.0;
    const double gap = 3.5;
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );
    final Path path = Path()..addRRect(rrect);
    final Path dashPath = Path();

    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double len = (distance + dash < metric.length) ? dash : metric.length - distance;
        dashPath.addPath(metric.extractPath(distance, distance + len), Offset.zero);
        distance += dash + gap;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

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
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: DefensysTokens.maroon.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.cloud_upload_rounded, size: 20, color: DefensysTokens.maroon),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upload ${item['id']}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  Text(
                    item['label']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Color(0xFF64748B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: formatInfo.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: formatInfo.color.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(formatInfo.icon, size: 15, color: formatInfo.color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Accepted: ${formatInfo.description} • Max 50 MB',
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
              const SizedBox(height: 14),

              // Hero Dropzone (when no file selected)
              if (selectedFileName == null && !isUploading) ...[
                InkWell(
                  onTap: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: formatInfo.extensions,
                      withData: true,
                    );
                    if (result != null && result.files.single.name.isNotEmpty) {
                      setState(() {
                        selectedFileName = result.files.single.name;
                        selectedFileBytes = result.files.single.bytes;
                        final bytes = result.files.single.size;
                        selectedFileSize = '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
                        if (bytes < 1024 * 1024) {
                          selectedFileSize = '${(bytes / 1024).toStringAsFixed(1)} KB';
                        }
                        uploadError = null;
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: CustomPaint(
                    painter: const _DashedRectPainter(
                      color: Color(0xFFCBD5E1),
                      strokeWidth: 1.5,
                      radius: 10,
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: DefensysTokens.maroon.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.cloud_upload_rounded,
                              size: 28,
                              color: DefensysTokens.maroon,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Click to browse or drop your document here',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Select any file with ${formatInfo.label} extension',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF64748B),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              // Rich File Preview Card (when file selected)
              if (selectedFileName != null && !isUploading) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.description_rounded, color: Color(0xFF15803D), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedFileName!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${selectedFileSize ?? ""} • Ready to submit',
                              style: const TextStyle(
                                color: Color(0xFF15803D),
                                fontWeight: FontWeight.w600,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Change file',
                        icon: const Icon(Icons.sync_rounded, color: Color(0xFF15803D), size: 20),
                        onPressed: () async {
                          FilePickerResult? result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: formatInfo.extensions,
                            withData: true,
                          );
                          if (result != null && result.files.single.name.isNotEmpty) {
                            setState(() {
                              selectedFileName = result.files.single.name;
                              selectedFileBytes = result.files.single.bytes;
                              final bytes = result.files.single.size;
                              selectedFileSize = '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
                              if (bytes < 1024 * 1024) {
                                selectedFileSize = '${(bytes / 1024).toStringAsFixed(1)} KB';
                              }
                              uploadError = null;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],

              // Recommended File Name Notice (with Copy Button)
              if (!isUploading && suggestedName.isNotEmpty && (item['type'] == 'post' || item['type'] == 'vault')) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          const Text(
                            'Recommended File Name:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: suggestedName));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Recommended filename copied to clipboard'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.copy_rounded, size: 13, color: DefensysTokens.maroon),
                                  SizedBox(width: 4),
                                  Text(
                                    'Copy',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: DefensysTokens.maroon,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        suggestedName,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: DefensysTokens.maroon,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'DefenSYS will automatically standardize this file for the repository archive upon upload.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Upload Progress State
              if (isUploading) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: DefensysTokens.maroon),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Uploading ${selectedFileName ?? "document"}...',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(uploadProgress * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: DefensysTokens.maroon, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: uploadProgress,
                          color: DefensysTokens.maroon,
                          backgroundColor: DefensysTokens.maroon.withValues(alpha: 0.15),
                          minHeight: 8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (uploadError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          uploadError!,
                          style: const TextStyle(color: Colors.red, fontSize: 11.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: isUploading ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton.icon(
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

                    // Determine the effective filename for the repository
                    final isPostDefense = item['type'] == 'post' || item['type'] == 'vault';
                    String effectiveFileName = selectedFileName!;

                    if (isPostDefense && suggestedName.isNotEmpty) {
                      // Compare basenames (ignoring extension) to detect mismatch
                      String stripExt(String name) {
                        final dotIdx = name.lastIndexOf('.');
                        return dotIdx > 0 ? name.substring(0, dotIdx) : name;
                      }

                      // Ensure repository name preserves the uploaded file's actual extension
                      String targetRepoName = suggestedName;
                      final selDot = selectedFileName!.lastIndexOf('.');
                      final sugDot = suggestedName.lastIndexOf('.');
                      if (selDot > 0) {
                        final selExt = selectedFileName!.substring(selDot);
                        if (sugDot < 0) {
                          targetRepoName = '$suggestedName$selExt';
                        } else {
                          final sugExt = suggestedName.substring(sugDot);
                          if (sugExt.toLowerCase() != selExt.toLowerCase()) {
                            targetRepoName = '${suggestedName.substring(0, sugDot)}$selExt';
                          }
                        }
                      }

                      final selectedBase = stripExt(selectedFileName!).trim().toLowerCase();
                      final suggestedBase = stripExt(suggestedName).trim().toLowerCase();

                      if (selectedBase != suggestedBase) {
                        // Show blocking rename confirmation dialog
                        final confirmed = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (confirmCtx) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                            contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                            title: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.drive_file_rename_outline_rounded, size: 20, color: Color(0xFFD97706)),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Filename Will Be Adjusted',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                  ),
                                ),
                              ],
                            ),
                            content: SizedBox(
                              width: 420,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Your file:',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.description_outlined, size: 15, color: Color(0xFF64748B)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            selectedFileName!,
                                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'Repository name:',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: DefensysTokens.maroon.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: DefensysTokens.maroon.withValues(alpha: 0.2)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.inventory_2_outlined, size: 15, color: DefensysTokens.maroon),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            targetRepoName,
                                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w700, color: DefensysTokens.maroon),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEFCE8),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFFDE68A)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: const [
                                        Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFFD97706)),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'The repository requires a standardized filename. Your file will be saved under the repository name shown above.',
                                            style: TextStyle(fontSize: 11.5, color: Color(0xFF92400E), height: 1.35),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(confirmCtx, false),
                                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(confirmCtx, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: DefensysTokens.maroon,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('OK, Proceed', style: TextStyle(fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        );

                        if (confirmed != true) return;
                        effectiveFileName = targetRepoName;
                      } else {
                        effectiveFileName = targetRepoName;
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
                      request.fields['file_name'] = effectiveFileName;
                      request.fields['file_size'] = selectedFileSize ?? '';
                      if (fileId != null) {
                        request.fields['file_id'] = fileId.toString();
                      }

                      // Add file
                      request.files.add(
                        http.MultipartFile.fromBytes(
                          'file',
                          selectedFileBytes!,
                          filename: effectiveFileName,
                        ),
                      );

                      final response = await client.sendAuthenticated(
                        request,
                      );

                      if (response.statusCode == 200) {
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
                ? const SizedBox.shrink()
                : const Icon(Icons.cloud_upload_rounded, size: 16),
            label: Text(isUploading ? 'Uploading...' : 'Submit Deliverable'),
            style: ElevatedButton.styleFrom(
              backgroundColor: DefensysTokens.maroon,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    ),
  );
}
