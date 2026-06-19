import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../config/api_config.dart';
import '../../../services/authenticated_client.dart';
import '../../../services/capstone_deliverables_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/feedback_toast.dart';
import '../../../utils/progress_upload.dart';

String _formatUploadFailureMessage(int statusCode, String responseBody) {
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
  } catch (_) {}
  if (responseBody.contains('<!DOCTYPE html>') || responseBody.contains('<html')) {
    return 'Upload failed (server error $statusCode). Try again later.';
  }
  final trimmed = responseBody.trim();
  return trimmed.isEmpty ? 'Upload failed (status $statusCode).' : 'Upload failed: $trimmed';
}

class StudentDeliverablesTab extends ConsumerStatefulWidget {
  final bool isCapstone;
  final Map<String, dynamic>? studentData;

  const StudentDeliverablesTab({
    super.key,
    required this.isCapstone,
    required this.studentData,
  });

  @override
  ConsumerState<StudentDeliverablesTab> createState() => _StudentDeliverablesTabState();
}

class _StudentDeliverablesTabState extends ConsumerState<StudentDeliverablesTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
            scope: widget.isCapstone ? 'capstone' : 'pit',
          );
    });
  }

  Future<void> _refresh() async {
    await Future.wait([
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
            scope: widget.isCapstone ? 'capstone' : 'pit',
          ),
      ref.read(dashboardProvider('student').notifier).fetchDashboardData(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(capstoneDeliverablesProvider);
    final team = state.teams.firstOrNull;

    if (state.isLoading && team == null) {
      return const Center(
        child: CircularProgressIndicator(color: DefensysTokens.maroon),
      );
    }

    if (state.error != null && team == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _refresh,
                style: ElevatedButton.styleFrom(backgroundColor: DefensysTokens.maroon),
                child: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    if (team == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_off, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'No team assigned yet.',
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final selectedStage = Map<String, dynamic>.from(
      team['selected_stage'] as Map? ?? const {},
    );
    final configured = selectedStage['deliverables_configured'] == true;
    final endorsed = selectedStage['endorsed'] == true;
    final pre = _deliverables(selectedStage, 'pre');
    final vault = _deliverables(selectedStage, 'vault');

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: RefreshIndicator(
        color: DefensysTokens.maroon,
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.upload_file, color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Deliverables',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: endorsed ? Colors.green.shade600 : Colors.orange.shade600,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            endorsed ? 'Endorsed' : 'Awaiting Endorsement',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Stage/Event: ${state.selectedStage}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (state.message != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          state.message!,
                          style: TextStyle(color: Colors.green.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (!configured)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No deliverables configured for this stage/event yet.',
                          style: TextStyle(fontSize: 14, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                _sectionTitle('Pre-Defense Requirements'),
                const SizedBox(height: 8),
                ...pre.map((item) => _deliverableRow(team, state.selectedStage, item, endorsed)),
                const SizedBox(height: 20),
                if (widget.isCapstone) ...[
                  _sectionTitle('Post-Defense Vault Submissions'),
                  const SizedBox(height: 8),
                  if (selectedStage['vault_unlocked'] != true)
                    _lockedVaultNotice(state.selectedStage)
                  else
                    ...vault.map((item) => _deliverableRow(team, state.selectedStage, item, endorsed)),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: DefensysTokens.maroon,
        ),
      ),
    );
  }

  Widget _lockedVaultNotice(String stage) {
    return Card(
      elevation: 0,
      color: Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, color: Colors.grey, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Vault submissions are locked. They will open once your defense for $stage is complete.',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _deliverables(Map<String, dynamic> stage, String type) {
    final list = stage['deliverables'] as List?;
    if (list == null) return [];
    return list
        .where((item) => item is Map && item['type']?.toString() == type)
        .cast<Map<String, dynamic>>()
        .toList();
  }

  Widget _deliverableRow(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
    bool endorsed,
  ) {
    final uploaded = item['uploaded'] == true;
    final submission = Map<String, dynamic>.from(
      item['submission'] as Map? ?? const {},
    );
    final status = submission['status']?.toString();
    final feedback = submission['feedback']?.toString();
    final isAccepted = status == 'accepted';
    final isRejected = status == 'rejected';

    // Lock file from edits/removals if endorsed OR backend lock is set OR review status is Accepted
    final fileLocked = endorsed || item['locked'] == true || isAccepted;
    final isWPR = item['id'] == 'WPR';
    final suggestedFile = item['suggested_file_name']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Section: Info & Badges
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  uploaded ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: uploaded ? Colors.green : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['label']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      if (uploaded)
                        Text(
                          isWPR
                              ? 'All weekly reports approved - Compiled by Adviser'
                              : '${submission['file_name'] ?? ''} - ${submission['uploaded_by_name'] ?? ''}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        )
                      else if ((item['vault_note']?.toString() ?? '').isNotEmpty)
                        Text(
                          item['vault_note'].toString(),
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        )
                      else if (isWPR)
                        const Text(
                          'Adviser will compile weekly reports once approved.',
                          style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Badges Column
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (uploaded) ...[
                      if (isAccepted)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, size: 12, color: Colors.green.shade700),
                              const SizedBox(width: 4),
                              Text(
                                'Accepted',
                                style: TextStyle(fontSize: 10, color: Colors.green.shade700, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        )
                      else if (isRejected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cancel, size: 12, color: Colors.red.shade700),
                              const SizedBox(width: 4),
                              Text(
                                'Needs Revision',
                                style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.hourglass_empty, size: 12, color: Colors.orange.shade700),
                              const SizedBox(width: 4),
                              Text(
                                'Awaiting Review',
                                style: TextStyle(fontSize: 10, color: Colors.orange.shade700, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 4),
                    ],
                    if (item['required'] == true)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: const Text(
                          'Required',
                          style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (uploaded && isRejected && feedback != null && feedback.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Adviser/Instructor Remarks:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feedback,
                      style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                    ),
                  ],
                ),
              ),
            ],
            if (uploaded && isAccepted && feedback != null && feedback.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Remarks:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feedback,
                      style: TextStyle(fontSize: 12, color: Colors.green.shade900),
                    ),
                  ],
                ),
              ),
            ],
            if (suggestedFile.isNotEmpty && !uploaded) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DefensysTokens.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DefensysTokens.gold.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: DefensysTokens.gold, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Naming template (PDF must match):',
                            style: TextStyle(color: DefensysTokens.gold, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            suggestedFile,
                            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Bottom Actions Section
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (uploaded && !isWPR && !fileLocked) ...[
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: () => _removeFile(team, stageLabel, item),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                  const SizedBox(width: 8),
                ],
                if (isWPR)
                  ElevatedButton.icon(
                    onPressed: () => _showWPRDialog(team, stageLabel),
                    icon: const Icon(Icons.assignment, size: 16),
                    label: const Text('Manage Weekly Reports', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DefensysTokens.maroon,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: fileLocked ? null : () => _promptUploadOrReplace(team, stageLabel, item),
                    icon: Icon(uploaded ? Icons.swap_horiz : Icons.upload_file, size: 16),
                    label: Text(uploaded ? 'Replace' : 'Upload', style: const TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: uploaded ? Colors.blue.shade600 : DefensysTokens.maroon,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeFile(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
  ) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Remove file?',
      message: 'Remove submission for "${item['label']}"? This cannot be undone.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;

    await ref.read(capstoneDeliverablesProvider.notifier).removeDeliverable({
      'team_id': team['id'],
      'stage_label': stageLabel,
      'deliverable_id': item['id'],
    });
  }

  Future<void> _promptUploadOrReplace(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
  ) async {
    if (item['uploaded'] == true) {
      final ok = await confirmDestructive(
        context,
        title: 'Replace file?',
        message: 'The current upload will be replaced. This cannot be undone.',
        confirmLabel: 'Replace',
      );
      if (!ok || !mounted) return;
    }
    await _showUploadDialog(team, stageLabel, item);
  }

  Future<void> _showUploadDialog(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
  ) async {
    String? selectedFileName;
    String? selectedFileSize;
    Uint8List? selectedFileBytes;
    bool isUploading = false;
    double uploadProgress = 0.0;
    String? uploadError;

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Upload ${item['id']}'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['label']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 14),
                if (!isUploading)
                  OutlinedButton.icon(
                    onPressed: () async {
                      FilePickerResult? result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['pdf'],
                        withData: true,
                      );
                      if (result != null && result.files.single.name.isNotEmpty) {
                        setState(() {
                          selectedFileName = result.files.single.name;
                          selectedFileBytes = result.files.single.bytes;
                          final bytes = result.files.single.size;
                          selectedFileSize = '${(bytes / 1024).toStringAsFixed(2)} KB';
                          uploadError = null;
                        });
                      }
                    },
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Choose PDF File'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: BorderSide(color: DefensysTokens.maroon),
                      foregroundColor: DefensysTokens.maroon,
                    ),
                  ),
                const SizedBox(height: 16),
                if (selectedFileName != null && !isUploading) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedFileName!,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(selectedFileSize ?? '', style: const TextStyle(color: Colors.grey, fontSize: 11)),
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
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No file selected.',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
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
                            color: Colors.green,
                            backgroundColor: Colors.green.withValues(alpha: 0.15),
                            minHeight: 8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${(uploadProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Uploading ${selectedFileName ?? "file"}...', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
                if (uploadError != null) ...[
                  const SizedBox(height: 12),
                  Text(uploadError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (selectedFileName != null && !isUploading)
                  ? () async {
                      final suggestedName = item['suggested_file_name']?.toString() ?? '';
                      if (item['type'] == 'vault' && suggestedName.isNotEmpty) {
                        if (selectedFileName!.trim().toLowerCase() != suggestedName.trim().toLowerCase()) {
                          setState(() {
                            uploadError = "File name must match exactly.\nExpected: '$suggestedName'";
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
                        final client = ref.read(authenticatedHttpClientProvider);
                        final uri = Uri.parse('${ApiConfig.capstoneDeliverablesUrl}/upload/');
                        final request = MultipartRequestWithProgress(
                          'POST',
                          uri,
                          onProgress: (sent, total) {
                            if (total > 0) {
                              setState(() {
                                uploadProgress = sent / total;
                              });
                            }
                          },
                        );
                        request.fields['team_id'] = team['id'].toString();
                        request.fields['stage_label'] = stageLabel;
                        request.fields['deliverable_id'] = item['id'].toString();
                        request.fields['file_name'] = selectedFileName!;
                        request.fields['file_size'] = selectedFileSize ?? '';
                        request.files.add(
                          http.MultipartFile.fromBytes(
                            'file',
                            selectedFileBytes!,
                            filename: selectedFileName!,
                          ),
                        );
                        final response = await client.sendAuthenticated(request);
                        if (response.statusCode == 200) {
                          await ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
                                successMessage: 'Uploaded successfully.',
                              );
                          if (context.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } else {
                          final body = await response.stream.bytesToString();
                          setState(() {
                            isUploading = false;
                            uploadError = _formatUploadFailureMessage(response.statusCode, body);
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
              style: ElevatedButton.styleFrom(backgroundColor: DefensysTokens.maroon, foregroundColor: Colors.white),
              child: const Text('Save Upload'),
            ),
          ],
        ),
      ),
    );
  }

  void _showWPRDialog(Map<String, dynamic> team, String stageLabel) {
    final weekNumberCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final now = DateTime.now();
    dateCtrl.text = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    String? selectedFileName;
    String? selectedFileSize;
    Uint8List? selectedFileBytes;
    bool isSubmitting = false;

    final studentData = widget.studentData;
    final leaderName = team['leader_name'] ?? team['leaderName'] as String?;
    final studentName = studentData?['student']?['name'] as String?;
    final isLeader = leaderName == studentName;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          Future<void> pickFile() async {
            try {
              FilePickerResult? result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['pdf'],
                withData: true,
              );
              if (result != null && result.files.single.name.isNotEmpty) {
                setState(() {
                  selectedFileName = result.files.single.name;
                  selectedFileBytes = result.files.single.bytes;
                  final bytes = result.files.single.size;
                  selectedFileSize = '${(bytes / 1024).toStringAsFixed(2)} KB';
                });
              }
            } catch (e) {
              if (context.mounted) showErrorToast(context, 'Error picking file: $e');
            }
          }

          Future<void> submitReport() async {
            if (weekNumberCtrl.text.trim().isEmpty) {
              showValidationToast(context, 'Please enter week number');
              return;
            }
            if (selectedFileName == null || selectedFileBytes == null) {
              showValidationToast(context, 'Please select a PDF file');
              return;
            }
            final week = weekNumberCtrl.text.trim();
            final fileName = selectedFileName!;

            final confirmed = await confirmDestructive(
              context,
              title: 'Submit Weekly Report?',
              message: 'Week $week — $fileName. This submission will be sent to your adviser.',
              confirmLabel: 'Submit',
            );
            if (!confirmed || !mounted) return;

            setState(() => isSubmitting = true);
            try {
              final client = ref.read(authenticatedHttpClientProvider);
              final request = http.MultipartRequest(
                'POST',
                Uri.parse('${ApiConfig.weeklyProgressUrl}/'),
              );
              request.fields['team'] = team['id'].toString();
              request.fields['week_number'] = week;
              request.fields['report_date'] = dateCtrl.text.trim();
              request.fields['file_size'] = selectedFileSize ?? '';
              request.fields['accomplishments'] = '[]';
              request.fields['contributions'] = '[]';
              request.fields['issues'] = '[]';
              request.fields['plans'] = '[]';

              request.files.add(http.MultipartFile.fromBytes(
                'report_file',
                selectedFileBytes!,
                filename: fileName,
              ));

              final responseStream = await client.sendAuthenticated(request);
              final response = await http.Response.fromStream(responseStream);

              if (response.statusCode == 201 || response.statusCode == 200) {
                await ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
                      scope: 'capstone',
                      successMessage: 'Weekly report submitted successfully!',
                    );
                if (context.mounted) {
                  Navigator.pop(dialogContext);
                }
              } else {
                throw Exception('Failed to submit: ${response.body}');
              }
            } catch (e) {
              if (context.mounted) showErrorToast(context, 'Error: $e');
            } finally {
              setState(() => isSubmitting = false);
            }
          }

          return AlertDialog(
            title: const Text('Weekly Progress Reports'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isLeader)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          'Only the team leader can submit weekly progress reports.',
                          style: TextStyle(color: Colors.orange.shade800, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    TextField(
                      controller: weekNumberCtrl,
                      keyboardType: TextInputType.number,
                      enabled: isLeader && !isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Week Number *',
                        hintText: 'e.g. 1, 2, 3...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: dateCtrl,
                      readOnly: true,
                      enabled: isLeader && !isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Report Date',
                        prefixIcon: Icon(Icons.event),
                      ),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) {
                          setState(() {
                            dateCtrl.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    const Text('Upload Report (PDF only) *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: (isLeader && !isSubmitting) ? pickFile : null,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Choose PDF File'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        side: BorderSide(color: DefensysTokens.maroon),
                        foregroundColor: DefensysTokens.maroon,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (selectedFileName != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(selectedFileName!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  Text(selectedFileSize ?? '', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
              if (isLeader)
                ElevatedButton.icon(
                  onPressed: (isSubmitting || selectedFileName == null) ? null : submitReport,
                  icon: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                      : const Icon(Icons.send, size: 16),
                  label: const Text('Submit Report'),
                  style: ElevatedButton.styleFrom(backgroundColor: DefensysTokens.maroon, foregroundColor: Colors.white),
                ),
            ],
          );
        },
      ),
    );
  }
}
