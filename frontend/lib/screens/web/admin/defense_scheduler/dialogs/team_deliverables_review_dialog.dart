import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/utils/pdf_viewer.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import '../models/schedule_import_models.dart';

class TeamDeliverablesReviewDialog {
  static void show(
    BuildContext context,
    WidgetRef ref, {
    required Map<String, dynamic> team,
    required String stageLabel,
    required String scope,
  }) {
    ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
          scope: scope,
          selectedStage: stageLabel,
        );

    showDialog(
      context: context,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final delState = ref.watch(capstoneDeliverablesProvider);
            final teamData = delState.teams.firstWhere(
              (t) => asInt(t['id']) == asInt(team['id']),
              orElse: () => <String, dynamic>{},
            );

            final stageData = teamData['selected_stage'] as Map? ?? {};
            final deliverables = (stageData['deliverables'] as List? ?? [])
                .where((d) => d['type'] == 'pre')
                .toList();

            return AlertDialog(
              title: Text('${team['name']} - Deliverables Review'),
              content: SizedBox(
                width: 600,
                height: 400,
                child: delState.isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.maroon))
                    : deliverables.isEmpty
                        ? const Center(child: Text('No deliverables configured for this stage.'))
                        : ListView.separated(
                            itemCount: deliverables.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              final d = deliverables[index];
                              final label = d['label'] ?? '';
                              final required = d['required'] == true;
                              final type = d['type'] ?? '';
                              final uploaded = d['uploaded'] == true;
                              final submission = d['submission'] as Map?;

                              Color statusColor = Colors.grey;
                              String statusText = 'Not Submitted';
                              if (uploaded && submission != null) {
                                final status = submission['status']?.toString() ?? 'pending';
                                if (status == 'accepted') {
                                  statusColor = Colors.green;
                                  statusText = 'Accepted';
                                } else if (status == 'rejected') {
                                  statusColor = Colors.red;
                                  statusText = 'Rejected';
                                } else {
                                  statusColor = Colors.orange;
                                  statusText = 'Pending Review';
                                }
                              }

                              final fileUrl = submission?['file_url'] as String? ?? '';
                              final fileName = submission?['file_name'] as String? ?? 'document.pdf';

                              final listTile = ListTile(
                                mouseCursor: uploaded ? SystemMouseCursors.click : null,
                                onTap: uploaded
                                    ? () => _viewDeliverableFile(context, ref, fileUrl, fileName)
                                    : null,
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ),
                                    if (required) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEECEC),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Required',
                                          style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text('Type: ${type == 'pre' ? 'Pre-Defense' : 'Post-Defense'}', style: const TextStyle(fontSize: 12)),
                                    if (uploaded &&
                                        submission != null &&
                                        submission['feedback'] != null &&
                                        submission['feedback'].toString().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Feedback: ${submission['feedback']}',
                                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.red),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (uploaded) ...[
                                      const Icon(Icons.remove_red_eye_rounded, size: 16, color: AppColors.maroon),
                                      const SizedBox(width: 8),
                                    ],
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: statusColor),
                                      ),
                                      child: Text(
                                        statusText,
                                        style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              );

                              if (uploaded) {
                                return Tooltip(
                                  message: 'Click to preview deliverable',
                                  child: listTile,
                                );
                              }
                              return listTile;
                            },
                          ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<void> _viewDeliverableFile(
    BuildContext context,
    WidgetRef ref,
    String fileUrl,
    String fileName,
  ) async {
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
      if (!context.mounted) return;
      Navigator.pop(context);

      final lowerName = fileName.toLowerCase();
      if (lowerName.endsWith('.pdf')) {
        if (!context.mounted) return;
        await viewPdfInDialog(
          context: context,
          pdfBytes: bytes,
          fileName: fileName,
        );
      } else {
        await downloadBytesFile(
          bytes: bytes,
          fileName: fileName,
        );
        if (!context.mounted) return;
        showSuccessToast(context, 'Document downloaded: $fileName');
      }
    } catch (e) {
      if (!context.mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      showErrorToast(context, 'Error opening file: $e');
    }
  }
}
