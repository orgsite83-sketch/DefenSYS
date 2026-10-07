import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/universal_file_viewer.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
              backgroundColor: isDark ? DefensysTokens.mistSurface : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB)),
              ),
              title: Text(
                '${team['name']} - Deliverables Review',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? DefensysTokens.textPrimaryDark : AppColors.textPrimary,
                ),
              ),
              content: SizedBox(
                width: 600,
                height: 400,
                child: delState.isLoading
                    ? Center(child: CircularProgressIndicator(color: isDark ? DefensysTokens.mistMaroon : AppColors.maroon))
                    : deliverables.isEmpty
                        ? Center(
                            child: Text(
                              'No deliverables configured for this stage.',
                              style: TextStyle(
                                color: isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: deliverables.length,
                            separatorBuilder: (_, __) => Divider(
                              color: isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB),
                            ),
                            itemBuilder: (context, index) {
                              final d = deliverables[index];
                              final label = d['label'] ?? '';
                              final required = d['required'] == true;
                              final type = d['type'] ?? '';
                              final uploaded = d['uploaded'] == true;
                              final submission = d['submission'] as Map?;

                              Color statusColor = isDark ? DefensysTokens.textSecondaryDark : Colors.grey;
                              String statusText = 'Not Submitted';
                              if (uploaded && submission != null) {
                                final status = submission['status']?.toString() ?? 'pending';
                                if (status == 'accepted') {
                                  statusColor = isDark ? const Color(0xFF34D399) : Colors.green;
                                  statusText = 'Accepted';
                                } else if (status == 'rejected') {
                                  statusColor = isDark ? const Color(0xFFF87171) : Colors.red;
                                  statusText = 'Rejected';
                                } else {
                                  statusColor = isDark ? const Color(0xFFFBBF24) : Colors.orange;
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
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isDark ? DefensysTokens.textPrimaryDark : AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    if (required) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? const Color(0xFF7F1D1D).withValues(alpha: 0.35)
                                              : const Color(0xFFFEECEC),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: isDark
                                                ? const Color(0xFFDC2626).withValues(alpha: 0.45)
                                                : const Color(0xFFFECACA),
                                          ),
                                        ),
                                        child: Text(
                                          'Required',
                                          style: TextStyle(
                                            color: isDark ? const Color(0xFFFCA5A5) : Colors.red,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      'Type: ${type == 'pre' ? 'Pre-Defense' : 'Post-Defense'}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
                                      ),
                                    ),
                                    if (uploaded &&
                                        submission != null &&
                                        submission['feedback'] != null &&
                                        submission['feedback'].toString().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Feedback: ${submission['feedback']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                          color: isDark ? const Color(0xFFFCA5A5) : Colors.red,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (uploaded) ...[
                                      Icon(
                                        Icons.remove_red_eye_rounded,
                                        size: 16,
                                        color: isDark ? DefensysTokens.mistMaroonText : AppColors.maroon,
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: isDark ? 0.22 : 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: statusColor.withValues(alpha: isDark ? 0.6 : 1.0)),
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
                  style: TextButton.styleFrom(
                    foregroundColor: isDark ? DefensysTokens.mistMaroonText : AppColors.maroon,
                  ),
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
