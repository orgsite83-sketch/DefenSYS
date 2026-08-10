import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/config/api_config.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/weekly_progress_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/toasts/feedback_toast.dart';

Future<void> showApproveWPRDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> team,
  required String stageLabel,
  required bool alreadyApproved,
  required void Function(void Function()) setDialogState,
}) async {
  final teamId = team['id']?.toString() ?? '';

  if (teamId.isEmpty) {
    showValidationToast(context, 'Invalid team ID.');
    return;
  }

  // Show loading indicator
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(child: CircularProgressIndicator()),
  );

  try {
    // Fetch fresh weekly progress reports from database for this team
    await ref.read(weeklyProgressProvider.notifier).fetchReports();

    // Get the updated state
    final progressState = ref.read(weeklyProgressProvider);

    // Filter reports for this specific team
    final teamReports = progressState.reports
        .where((r) => r['team'].toString() == teamId)
        .toList();

    // Close loading indicator
    if (context.mounted) Navigator.pop(context);

    if (teamReports.isEmpty) {
      if (context.mounted) {
        showValidationToast(
          context,
          'No weekly progress reports found for ${team['name']}. Students must submit reports first.',
        );
      }
      return;
    }

    // Show approval dialog
    if (context.mounted) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              Icon(
                alreadyApproved
                    ? Icons.visibility
                    : Icons.check_circle_outline,
                color: alreadyApproved ? Colors.blue : AppColors.success,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  alreadyApproved
                      ? 'Weekly Reports - ${team['name']}'
                      : 'Approve Weekly Reports - ${team['name']}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 650,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Team: ${team['name']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Stage: $stageLabel',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: alreadyApproved
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: alreadyApproved
                          ? const Color(0xFF86EFAC)
                          : const Color(0xFFBAE6FD),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        alreadyApproved
                            ? Icons.check_circle
                            : Icons.info_outline,
                        color: alreadyApproved
                            ? const Color(0xFF166534)
                            : const Color(0xFF0369A1),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          alreadyApproved
                              ? 'PDF compilation of all weekly reports has been generated and submitted. You can view the reports below or download them again.'
                              : 'Review the ${teamReports.length} weekly progress reports submitted by this team. Click "Generate & Submit PDF" to compile all reports into a single PDF document and submit it as the WPR deliverable.',
                          style: TextStyle(
                            color: alreadyApproved
                                ? const Color(0xFF166534)
                                : const Color(0xFF0369A1),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Weekly reports submitted (${teamReports.length}):',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        showCompileWPRDialog(context: context, ref: ref, team: team);
                      },
                      icon: const Icon(Icons.folder_zip_outlined, size: 16),
                      label: const Text('Download All'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.maroon,
                        side: const BorderSide(color: AppColors.maroon),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: teamReports.length,
                    itemBuilder: (context, index) {
                      final report = teamReports[index];
                      return Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.success,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Week ${report['week_number'] ?? 0}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Date: ${report['report_date'] ?? 'N/A'} • Submitted by: ${report['student_name'] ?? 'Unknown'}',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Week ${report['week_number']}',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Close'),
            ),
            if (!alreadyApproved)
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.picture_as_pdf),
                label: Text(
                  'Generate & Submit PDF (${teamReports.length} reports)',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        ),
      );

      // If approved, generate PDF and save to database
      if (approved == true && context.mounted) {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );

        try {
          final teamIdInt = team['id'] is int
              ? team['id'] as int
              : int.tryParse(team['id'].toString()) ?? 0;
          final success = await generateAndSubmitPDF(
            ref: ref,
            teamId: teamIdInt,
            stageLabel: stageLabel,
          );

          // Close loading indicator
          if (context.mounted) Navigator.pop(context);

          if (success && context.mounted) {
            setDialogState(() {});

            showSuccessToast(
              context,
              'Weekly Progress Reports PDF generated and submitted for ${team['name']}!',
            );
          }
        } catch (e) {
          if (context.mounted) Navigator.pop(context);

          if (context.mounted) {
            showErrorToast(context, 'Error generating PDF: $e');
          }
        }
      }
    }
  } catch (e) {
    if (context.mounted) Navigator.pop(context);

    if (context.mounted) {
      showErrorToast(context, 'Error fetching weekly reports: $e');
    }
  }
}

Future<void> showCompileWPRDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> team,
}) async {
  final teamId = team['id']?.toString() ?? '';

  if (teamId.isEmpty) {
    showValidationToast(context, 'Invalid team ID.');
    return;
  }

  // Show loading indicator
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(child: CircularProgressIndicator()),
  );

  try {
    await ref.read(weeklyProgressProvider.notifier).fetchReports();

    final progressState = ref.read(weeklyProgressProvider);

    final teamReports = progressState.reports
        .where((r) => r['team'].toString() == teamId)
        .toList();

    if (context.mounted) Navigator.pop(context);

    if (teamReports.isEmpty) {
      if (context.mounted) {
        showValidationToast(
          context,
          'No weekly progress reports found for ${team['name']}.',
        );
      }
      return;
    }

    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.folder_zip, color: AppColors.maroon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Compile Weekly Reports - ${team['name']}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Team: ${team['name']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBAE6FD)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFF0369A1),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This will generate a compilation report of all ${teamReports.length} weekly progress reports for this team from the database.',
                          style: const TextStyle(
                            color: Color(0xFF0369A1),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Weekly reports to compile:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: teamReports.length,
                    itemBuilder: (context, index) {
                      final report = teamReports[index];
                      return Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.success,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Week ${report['week_number'] ?? 0}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Date: ${report['report_date'] ?? 'N/A'}',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Week ${report['week_number']}',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                downloadWPRCompilation(context, team, teamReports);
              },
              icon: const Icon(Icons.download),
              label: const Text('Download Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.maroon,
                foregroundColor: AppColors.gold,
              ),
            ),
          ],
        ),
      );
    }
  } catch (e) {
    if (context.mounted) Navigator.pop(context);

    if (context.mounted) {
      showErrorToast(context, 'Error fetching weekly reports: $e');
    }
  }
}

void downloadWPRCompilation(
  BuildContext context,
  Map<String, dynamic> team,
  List<Map<String, dynamic>> reports,
) {
  final buffer = StringBuffer();
  buffer.writeln('=' * 60);
  buffer.writeln('WEEKLY PROGRESS REPORTS COMPILATION');
  buffer.writeln('=' * 60);
  buffer.writeln();
  buffer.writeln('Team: ${team['name']}');
  buffer.writeln('Project: ${team['project_title'] ?? 'N/A'}');
  buffer.writeln('Section: ${team['year_level'] ?? 'N/A'}');
  buffer.writeln('Generated: ${DateTime.now().toString().substring(0, 19)}');
  buffer.writeln();
  buffer.writeln('=' * 60);
  buffer.writeln('WEEKLY REPORTS (${reports.length})');
  buffer.writeln('=' * 60);
  buffer.writeln();

  for (var i = 0; i < reports.length; i++) {
    final report = reports[i];
    final weekNumber = report['week_number'] ?? 0;
    final reportDate = report['report_date'] ?? 'N/A';
    final studentName = report['student_name'] ?? 'Unknown';
    final submittedAt = report['submitted_at'] ?? 'N/A';

    buffer.writeln('${i + 1}. WEEK $weekNumber');
    buffer.writeln('   Date: $reportDate');
    buffer.writeln('   Submitted by: $studentName');
    buffer.writeln('   Submitted at: $submittedAt');
    buffer.writeln();

    final accomplishments =
        (report['accomplishments'] as List?)?.cast<Map<String, dynamic>>() ??
        [];
    if (accomplishments.isNotEmpty) {
      buffer.writeln('   Accomplishments:');
      for (var acc in accomplishments) {
        buffer.writeln('   - Task: ${acc['task'] ?? 'N/A'}');
        buffer.writeln('     Description: ${acc['description'] ?? 'N/A'}');
      }
      buffer.writeln();
    }

    final contributions =
        (report['contributions'] as List?)?.cast<Map<String, dynamic>>() ??
        [];
    if (contributions.isNotEmpty) {
      buffer.writeln('   Individual Contributions:');
      for (var contrib in contributions) {
        buffer.writeln(
          '   - ${contrib['member'] ?? 'N/A'}: ${contrib['contribution'] ?? 'N/A'}',
        );
      }
      buffer.writeln();
    }

    final issues =
        (report['issues'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (issues.isNotEmpty) {
      buffer.writeln('   Issues & Actions:');
      for (var issue in issues) {
        buffer.writeln('   - Issue: ${issue['issue'] ?? 'N/A'}');
        buffer.writeln('     Action: ${issue['action'] ?? 'N/A'}');
      }
      buffer.writeln();
    }

    final plans =
        (report['plans'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (plans.isNotEmpty) {
      buffer.writeln('   Plans for Next Week:');
      for (var plan in plans) {
        buffer.writeln('   - Task: ${plan['task'] ?? 'N/A'}');
        buffer.writeln('     Expected Output: ${plan['output'] ?? 'N/A'}');
      }
      buffer.writeln();
    }

    buffer.writeln('-' * 60);
    buffer.writeln();
  }

  buffer.writeln('=' * 60);
  buffer.writeln('END OF COMPILATION');
  buffer.writeln('=' * 60);

  showSuccessToast(
    context,
    'Compilation report generated for ${team['name']}\n'
    '${reports.length} weekly reports compiled.',
    duration: const Duration(seconds: 4),
    action: FeedbackToastAction(
      label: 'View',
      textColor: Colors.white,
      onPressed: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Compilation Report'),
            content: SizedBox(
              width: 600,
              height: 400,
              child: SingleChildScrollView(
                child: SelectableText(
                  buffer.toString(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

Future<bool> generateAndSubmitPDF({
  required WidgetRef ref,
  required int teamId,
  required String stageLabel,
}) async {
  final client = ref.read(authenticatedHttpClientProvider);
  final response = await client.post(
    Uri.parse(
      '${ApiConfig.capstoneDeliverablesUrl}/compile-weekly-reports/',
    ),
    body: jsonEncode({'team_id': teamId, 'stage_label': stageLabel}),
  );

  if (response.statusCode == 200) {
    jsonDecode(response.body);

    await ref
        .read(capstoneDeliverablesProvider.notifier)
        .fetchDeliverables();

    return true;
  } else {
    final error = jsonDecode(response.body);
    throw Exception(error['error'] ?? 'Failed to generate PDF');
  }
}
