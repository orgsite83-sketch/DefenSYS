import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/authenticated_client.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/utils/pdf_viewer.dart';
import 'package:defensys/widgets/confirm_dialog.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/screens/web/faculty/weekly_progress_reports_screen.dart';
import 'package:defensys/screens/web/shared/team_deliverables/dialogs/deliverable_submission_detail_modal.dart';
import 'package:defensys/screens/web/shared/team_deliverables/dialogs/grade_deliverable_modal.dart';
import 'package:defensys/screens/web/shared/team_deliverables/dialogs/wpr_management_dialogs.dart';

int parseAsInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

double? parseAsDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

BoxDecoration cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: const Color(0xFFE2E8F0)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.02),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

class DeliverablesTablePane extends ConsumerStatefulWidget {
  final CapstoneDeliverablesState state;
  final bool isAdviser;
  final int? initialTeamId;
  final int? initialTab;

  const DeliverablesTablePane({
    super.key,
    required this.state,
    required this.isAdviser,
    this.initialTeamId,
    this.initialTab,
  });

  @override
  ConsumerState<DeliverablesTablePane> createState() => _DeliverablesTablePaneState();
}

class _DeliverablesTablePaneState extends ConsumerState<DeliverablesTablePane> {
  int? _selectedTeamId;
  bool _showMobileDetail = false;
  final Map<int, String> _cardSelectedStages = {};
  final Map<int, int> _cardActiveTabs = {}; // teamId -> tabIndex

  // Scoring controllers & rubrics state
  final Map<String, Map<String, TextEditingController>> _teamCriteriaScoreCtrls = {};
  final Map<String, TextEditingController> _teamManualScoreCtrls = {};
  final Map<String, Map<String, dynamic>?> _teamSelectedRubrics = {};

  Timer? _pendingRemoveTimer;
  bool _pendingRemoveCancelled = false;

  @override
  void initState() {
    super.initState();
    _selectedTeamId = widget.initialTeamId;
    if (widget.initialTeamId != null && widget.initialTab != null) {
      _cardActiveTabs[widget.initialTeamId!] = widget.initialTab!;
    }
  }

  @override
  void dispose() {
    _pendingRemoveTimer?.cancel();
    for (final c in _teamManualScoreCtrls.values) {
      c.dispose();
    }
    for (final subMap in _teamCriteriaScoreCtrls.values) {
      for (final c in subMap.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _stageList(Map<String, dynamic> team) {
    final stages = team['stages'];
    if (stages is! List) {
      return [];
    }
    return stages
        .whereType<Map>()
        .map((s) => Map<String, dynamic>.from(s))
        .toList();
  }

  Map<String, dynamic> _stagePayload(
    List<Map<String, dynamic>> stages,
    String label,
  ) {
    return stages.firstWhere(
      (item) => item['stage_label']?.toString() == label,
      orElse: () => <String, dynamic>{},
    );
  }

  String _effectiveSelectedStage(Map<String, dynamic> team) {
    final teamId = parseAsInt(team['id']);
    if (_cardSelectedStages.containsKey(teamId)) {
      return _cardSelectedStages[teamId]!;
    }

    final stages = _stageList(team);
    final currentStage = team['current_stage']?.toString();
    if (currentStage != null &&
        currentStage.isNotEmpty &&
        stages.any((s) => s['stage_label']?.toString() == currentStage)) {
      return currentStage;
    }

    final backendSelected = team['selected_stage'] is Map
        ? team['selected_stage']['stage_label']?.toString()
        : null;
    if (backendSelected != null &&
        backendSelected.isNotEmpty &&
        stages.any((s) => s['stage_label']?.toString() == backendSelected)) {
      return backendSelected;
    }

    if (widget.state.selectedStage.isNotEmpty &&
        stages.any((s) => s['stage_label']?.toString() == widget.state.selectedStage)) {
      return widget.state.selectedStage;
    }

    if (stages.isNotEmpty) {
      return stages.first['stage_label']?.toString() ?? '';
    }

    return widget.state.selectedStage;
  }

  List<Map<String, dynamic>> _deliverables(
    Map<String, dynamic> stage,
    String key,
  ) {
    final list = stage[key];
    if (list is! List) {
      return [];
    }
    return list
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  IconData _getFileIcon(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.pdf')) {
      return Icons.picture_as_pdf_outlined;
    } else if (lowerName.endsWith('.png') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.webp') ||
        lowerName.endsWith('.gif')) {
      return Icons.image_outlined;
    } else if (lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.mov') ||
        lowerName.endsWith('.avi') ||
        lowerName.endsWith('.mkv')) {
      return Icons.video_library_outlined;
    } else if (lowerName.endsWith('.zip') ||
        lowerName.endsWith('.rar') ||
        lowerName.endsWith('.7z')) {
      return Icons.folder_zip_outlined;
    } else if (lowerName.endsWith('.doc') ||
        lowerName.endsWith('.docx')) {
      return Icons.description_outlined;
    } else if (lowerName.endsWith('.ppt') ||
        lowerName.endsWith('.pptx')) {
      return Icons.slideshow_outlined;
    } else if (lowerName.endsWith('.xls') ||
        lowerName.endsWith('.xlsx') ||
        lowerName.endsWith('.csv')) {
      return Icons.table_chart_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Color _getFileIconColor(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.pdf')) {
      return Colors.red.shade700;
    } else if (lowerName.endsWith('.png') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.webp') ||
        lowerName.endsWith('.gif')) {
      return Colors.green.shade700;
    } else if (lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.mov') ||
        lowerName.endsWith('.avi') ||
        lowerName.endsWith('.mkv')) {
      return Colors.indigo.shade700;
    } else if (lowerName.endsWith('.zip') ||
        lowerName.endsWith('.rar') ||
        lowerName.endsWith('.7z')) {
      return Colors.amber.shade800;
    } else if (lowerName.endsWith('.doc') ||
        lowerName.endsWith('.docx') ||
        lowerName.endsWith('.ppt') ||
        lowerName.endsWith('.pptx') ||
        lowerName.endsWith('.xls') ||
        lowerName.endsWith('.xlsx') ||
        lowerName.endsWith('.csv')) {
      return Colors.blue.shade700;
    }
    return Colors.grey.shade600;
  }

  Future<void> _viewPdf(String fileUrl, String fileName) async {
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
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      await viewFileInDialog(
        context: context,
        fileBytes: bytes,
        fileName: fileName,
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (mounted) {
        showErrorToast(context, 'Error opening file: $e');
      }
    }
  }

  Future<void> _promptUploadOrReplace(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item, {
    int? fileId,
  }) async {
    if (fileId != null) {
      final ok = await confirmDestructive(
        context,
        title: 'Replace file?',
        message: 'The current file will be replaced. This cannot be undone.',
        confirmLabel: 'Replace',
      );
      if (!ok || !mounted) return;
    }
    await showUploadDialog(
      context: context,
      ref: ref,
      team: team,
      stageLabel: stageLabel,
      item: item,
      fileId: fileId,
    );
  }

  Future<void> _removeFile(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item, {
    int? fileId,
  }) async {
    final label =
        item['label']?.toString() ?? item['id']?.toString() ?? 'this file';
    final teamName = team['name']?.toString();
    final message = fileId != null
        ? 'Remove this file? This cannot be undone.'
        : (teamName != null && teamName.isNotEmpty
            ? 'Remove $label for $teamName? This cannot be undone.'
            : 'Remove $label? This cannot be undone.');

    final ok = await confirmDestructive(
      context,
      title: 'Remove file?',
      message: message,
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;

    _pendingRemoveTimer?.cancel();
    _pendingRemoveCancelled = false;
    final payload = {
      'team_id': parseAsInt(team['id']),
      'stage_label': stageLabel,
      'deliverable_id': item['id'],
      if (fileId != null) 'file_id': fileId,
    };

    showUndoToast(
      context,
      'File removed.',
      undoLabel: 'Undo',
      onUndo: () {
        _pendingRemoveCancelled = true;
        _pendingRemoveTimer?.cancel();
      },
    );

    _pendingRemoveTimer = Timer(const Duration(seconds: 5), () async {
      if (_pendingRemoveCancelled || !mounted) return;
      final removed = await ref
          .read(capstoneDeliverablesProvider.notifier)
          .removeDeliverable(payload);
      if (mounted && !removed) {
        showErrorToast(context, 'Failed to remove file.');
      }
    });
  }

  Future<void> _promptAcceptDialog(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
  ) async {
    final deliverableName = item['label']?.toString() ?? item['id']?.toString() ?? 'Deliverable';
    final teamName = team['name']?.toString() ?? 'the team';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppColors.success, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Accept Deliverable',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to accept "$deliverableName" for $teamName?',
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppColors.gold),
                  SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Accepting will finalize and lock this submission. Any future file replacements or revisions must be unlocked by a System Admin.',
                      style: TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Confirm & Accept'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(capstoneDeliverablesProvider.notifier).reviewDeliverable(
            teamId: parseAsInt(team['id']),
            stageLabel: stageLabel,
            deliverableId: item['id'].toString(),
            status: 'accepted',
          );
    }
  }

  Future<void> _promptRejectDialog(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
  ) async {
    final feedbackCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Reject Deliverable: ${item['label'] ?? item['id']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please provide feedback explaining why this submission is being rejected so students can revise it:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: feedbackCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter rejection remarks...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Rejection'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(capstoneDeliverablesProvider.notifier).reviewDeliverable(
            teamId: parseAsInt(team['id']),
            stageLabel: stageLabel,
            deliverableId: item['id'].toString(),
            status: 'rejected',
            feedback: feedbackCtrl.text.trim(),
          );
    }
  }

  Widget _buildFileRow(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
    Map<String, dynamic> submission,
    Map<String, dynamic> fileMap,
    bool locked,
    bool isFaculty,
    bool isAdmin,
    bool endorsed,
    void Function(void Function()) setDialogState,
  ) {
    final fileId = fileMap['id'];
    final fileName = fileMap['file_name']?.toString() ?? 'document.pdf';
    final fileSize = fileMap['file_size']?.toString() ?? '';
    final fileUrl = fileMap['file_url']?.toString() ?? '';
    
    final lowerName = fileName.toLowerCase();
    final isPreviewable = lowerName.endsWith('.pdf') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.webp') ||
        lowerName.endsWith('.gif') ||
        lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.mov') ||
        lowerName.endsWith('.avi') ||
        lowerName.endsWith('.mkv');

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(
            _getFileIcon(fileName),
            size: 16,
            color: _getFileIconColor(fileName),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (fileSize.isNotEmpty)
                  Text(
                    fileSize,
                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: isPreviewable ? 'View File' : 'Download File',
            icon: Icon(
              isPreviewable ? Icons.visibility_outlined : Icons.download_outlined,
              color: isPreviewable ? Colors.blue : Colors.green.shade700,
            ),
            onPressed: () => _viewPdf(fileUrl, fileName),
          ),
          if (!isFaculty || isAdmin) ...[
            if (!locked) ...[
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: 'Replace File',
                icon: const Icon(Icons.swap_horiz, color: AppColors.gold),
                onPressed: () => _promptUploadOrReplace(team, stageLabel, item, fileId: fileId),
              ),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove File',
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                onPressed: () => _removeFile(team, stageLabel, item, fileId: fileId),
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<Widget> _buildFileList(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
    Map<String, dynamic> submission,
    bool locked,
    bool isFaculty,
    bool isAdmin,
    bool endorsed,
    void Function(void Function()) setDialogState,
  ) {
    final filesList = submission['files'] as List? ?? [];
    
    if (filesList.isEmpty) {
      final legacyFile = {
        'id': null,
        'file_name': submission['file_name'] ?? 'document.pdf',
        'file_size': submission['file_size'] ?? '',
        'file_url': submission['file_url'] ?? '',
      };
      return [_buildFileRow(team, stageLabel, item, submission, legacyFile, locked, isFaculty, isAdmin, endorsed, setDialogState)];
    }
    
    return filesList.map((f) {
      final fileMap = Map<String, dynamic>.from(f as Map);
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _buildFileRow(team, stageLabel, item, submission, fileMap, locked, isFaculty, isAdmin, endorsed, setDialogState),
      );
    }).toList();
  }

  Widget _deliverableRow(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
    void Function(void Function()) setDialogState,
  ) {
    final submission = item['submission'] as Map?;
    final uploaded = item['uploaded'] == true || submission != null;
    final requiredItem = item['required'] == true;
    final isFaculty = widget.isAdviser || widget.state.scope == 'pit' || widget.state.scope == 'capstone';
    final isAdmin = widget.state.scope == 'admin';

    final stages = _stageList(team);
    final currentStageObj = _stagePayload(stages, stageLabel);
    final endorsed = currentStageObj['endorsed'] == true;
    final locked = item['locked'] == true;
    final isPost = item['type'] == 'post' || item['deliverable_type'] == 'post';
    final canFacultyReview = item['can_faculty_review'] == true ||
        (isPost
            ? (currentStageObj['can_faculty_review_post'] != false)
            : (currentStageObj['can_faculty_review'] != false));

    final isWPR = item['id']?.toString() == 'WPR' ||
        item['label']?.toString().contains('Weekly Progress Report') == true;

    final subStatus = submission?['status']?.toString();
    final feedback = submission?['feedback']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: subStatus == 'rejected'
            ? Colors.red.withValues(alpha: 0.04)
            : (subStatus == 'accepted'
                ? Colors.green.withValues(alpha: 0.05)
                : (uploaded
                    ? Colors.orange.withValues(alpha: 0.04)
                    : (requiredItem
                        ? Colors.red.withValues(alpha: 0.03)
                        : const Color(0xFFF8FAFC)))),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: subStatus == 'rejected'
              ? Colors.red.withValues(alpha: 0.3)
              : (subStatus == 'accepted'
                  ? Colors.green.withValues(alpha: 0.2)
                  : (uploaded
                      ? Colors.orange.withValues(alpha: 0.3)
                      : (requiredItem
                          ? Colors.red.withValues(alpha: 0.2)
                          : const Color(0xFFE2E8F0)))),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                subStatus == 'accepted'
                    ? Icons.check_circle_rounded
                    : (subStatus == 'rejected'
                        ? Icons.cancel_rounded
                        : (uploaded ? Icons.hourglass_empty_rounded : Icons.radio_button_unchecked)),
                color: subStatus == 'accepted'
                    ? AppColors.success
                    : (subStatus == 'rejected'
                        ? AppColors.danger
                        : (uploaded
                            ? AppColors.warning
                            : (requiredItem ? AppColors.danger : AppColors.textSecondary))),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item['label']?.toString() ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: uploaded ? AppColors.textPrimary : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        if (requiredItem) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'REQUIRED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppColors.danger,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (item['description']?.toString().isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        item['description']?.toString() ?? '',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              if (isWPR) ...[
                OutlinedButton.icon(
                  onPressed: () => showApproveWPRDialog(
                    context: context,
                    ref: ref,
                    team: team,
                    stageLabel: stageLabel,
                    alreadyApproved: uploaded,
                    setDialogState: setDialogState,
                  ),
                  icon: Icon(
                    uploaded ? Icons.visibility : Icons.check_circle_outline,
                    size: 16,
                  ),
                  label: Text(uploaded ? 'View WPR' : 'Approve WPR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: uploaded ? Colors.blue : AppColors.success,
                    side: BorderSide(
                      color: uploaded ? Colors.blue : AppColors.success,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ] else if (!uploaded) ...[
                if (!isFaculty || isAdmin)
                  if (!locked)
                    ElevatedButton.icon(
                      onPressed: () => _promptUploadOrReplace(team, stageLabel, item),
                      icon: const Icon(Icons.upload_file, size: 14),
                      label: const Text('Upload'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.maroon,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        visualDensity: VisualDensity.compact,
                        elevation: 0,
                      ),
                    ),
                if (isFaculty && !isAdmin)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.hourglass_empty_rounded, size: 12, color: AppColors.warning),
                        SizedBox(width: 4),
                        Text(
                          'Awaiting student upload',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
              ] else if (uploaded && !isWPR) ...[
                if (isFaculty && !isAdmin) ...[
                  if (subStatus == 'accepted') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded, size: 12, color: AppColors.success),
                          SizedBox(width: 4),
                          Text(
                            'Accepted',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (subStatus == 'rejected') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cancel_rounded, size: 12, color: AppColors.danger),
                          SizedBox(width: 4),
                          Text(
                            'Rejected',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (canFacultyReview) ...[
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        onPressed: widget.state.isSaving
                            ? null
                            : () => _promptAcceptDialog(team, stageLabel, item),
                        icon: const Icon(Icons.check_circle_outline, size: 14),
                        label: const Text('Accept'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                          elevation: 0,
                        ),
                      ),
                    ],
                  ] else ...[
                    if (canFacultyReview) ...[
                      ElevatedButton.icon(
                        onPressed: widget.state.isSaving
                            ? null
                            : () => _promptAcceptDialog(team, stageLabel, item),
                        icon: const Icon(Icons.check_circle_outline, size: 14),
                        label: const Text('Accept'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                          elevation: 0,
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        onPressed: widget.state.isSaving
                            ? null
                            : () => _promptRejectDialog(team, stageLabel, item),
                        icon: const Icon(Icons.cancel_outlined, size: 14),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_outline, size: 12, color: AppColors.textSecondary),
                            SizedBox(width: 4),
                            Text(
                              'Locked (Defense Done)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ],
            ],
          ),
          if (uploaded && submission != null) ...[
            const SizedBox(height: 8),
            ..._buildFileList(
              team,
              stageLabel,
              item,
              Map<String, dynamic>.from(submission),
              locked,
              isFaculty,
              isAdmin,
              endorsed,
              setDialogState,
            ),
          ],
          if (uploaded && subStatus == 'rejected' && feedback != null && feedback.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 14, color: AppColors.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Rejection Remarks: $feedback',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.danger,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _requiredProgressBlock({
    required bool configured,
    required int done,
    required int total,
  }) {
    final pct = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    final color = done == total && total > 0 ? AppColors.success : AppColors.warning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Required Pre-Defense Check',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              configured ? '$done / $total Complete' : 'Not Configured',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: const Color(0xFFE2E8F0),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _archiveProgressBlock(Map<String, dynamic> stage) {
    final done = parseAsInt(stage['archive_required_uploaded']);
    final total = parseAsInt(stage['archive_required_total']);
    final pct = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    final color = done == total && total > 0 ? AppColors.success : AppColors.gold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Post-Defense Deliverables',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              '$done / $total Complete',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: const Color(0xFFE2E8F0),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Map<String, dynamic> _resolveStageStatusBadge(Map<String, dynamic> stage) {
    final statusDetail = stage['stage_status_detail']?.toString();
    final endorsed = stage['endorsed'] == true;
    final complete = stage['required_complete'] == true;
    final configured = stage['deliverables_configured'] == true;

    if (!configured) {
      return {
        'label': 'Not Configured',
        'color': Colors.grey.shade600,
        'bg': Colors.grey.shade100,
        'border': Colors.grey.shade300,
        'icon': Icons.settings_outlined,
      };
    }

    if (statusDetail == 'passed') {
      return {
        'label': 'Passed',
        'color': AppColors.success,
        'bg': AppColors.success.withValues(alpha: 0.1),
        'border': AppColors.success.withValues(alpha: 0.3),
        'icon': Icons.check_circle_rounded,
      };
    }

    if (statusDetail == 'pending_post_defense') {
      return {
        'label': 'Pending Post-Defense',
        'color': const Color(0xFF7C3AED),
        'bg': const Color(0xFF7C3AED).withValues(alpha: 0.1),
        'border': const Color(0xFF7C3AED).withValues(alpha: 0.3),
        'icon': Icons.assignment_late_rounded,
      };
    }

    if (statusDetail == 'defense_ongoing') {
      return {
        'label': 'Defense Ongoing',
        'color': const Color(0xFF2563EB),
        'bg': const Color(0xFF2563EB).withValues(alpha: 0.1),
        'border': const Color(0xFF2563EB).withValues(alpha: 0.3),
        'icon': Icons.campaign_rounded,
      };
    }

    if (statusDetail == 'defense_scheduled') {
      return {
        'label': 'Defense Scheduled',
        'color': Colors.blue.shade700,
        'bg': Colors.blue.withValues(alpha: 0.1),
        'border': Colors.blue.withValues(alpha: 0.3),
        'icon': Icons.event_rounded,
      };
    }

    if (statusDetail == 'endorsed' || (endorsed && statusDetail == null)) {
      return {
        'label': 'Endorsed',
        'color': AppColors.success,
        'bg': AppColors.success.withValues(alpha: 0.1),
        'border': AppColors.success.withValues(alpha: 0.3),
        'icon': Icons.verified_rounded,
      };
    }

    if (complete) {
      return {
        'label': 'Ready for Endorsement',
        'color': Colors.blue,
        'bg': Colors.blue.withValues(alpha: 0.1),
        'border': Colors.blue.withValues(alpha: 0.3),
        'icon': Icons.check_circle_outline,
      };
    }

    return {
      'label': 'Awaiting Endorsement',
      'color': AppColors.warning,
      'bg': AppColors.warning.withValues(alpha: 0.1),
      'border': AppColors.warning.withValues(alpha: 0.3),
      'icon': Icons.hourglass_top_rounded,
    };
  }

  Widget _buildStageStatusBadge(Map<String, dynamic> stage) {
    final badge = _resolveStageStatusBadge(stage);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: badge['bg'] as Color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: badge['border'] as Color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge['icon'] as IconData, size: 12, color: badge['color'] as Color),
          const SizedBox(width: 4),
          Text(
            badge['label'] as String,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: badge['color'] as Color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _expandedTabButton(int teamId, int tabIndex, String label) {
    final activeTab = _cardActiveTabs[teamId] ?? 0;
    final isActive = activeTab == tabIndex;
    return InkWell(
      onTap: () {
        setState(() {
          _cardActiveTabs[teamId] = tabIndex;
        });
      },
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: isActive
              ? const Border(
                  bottom: BorderSide(
                    color: AppColors.maroon,
                    width: 2,
                  ),
                )
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? AppColors.maroon : AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedSection(Map<String, dynamic> team) {
    final teamId = parseAsInt(team['id']);
    final stages = _stageList(team);
    final selectedStage = _effectiveSelectedStage(team);

    final stage = _stagePayload(stages, selectedStage);
    var pre = _deliverables(stage, 'pre');
    var vault = _deliverables(stage, 'post');
    if (pre.isEmpty) {
      final allDeliverables = _deliverables(stage, 'deliverables');
      pre = allDeliverables.where((d) => d['type'] == 'pre').toList();
    }
    if (vault.isEmpty) {
      final allDeliverables = _deliverables(stage, 'deliverables');
      vault = allDeliverables.where((d) => d['type'] == 'post').toList();
    }

    final configured = stage['deliverables_configured'] == true;
    final complete = stage['required_complete'] == true;
    final endorsed = stage['endorsed'] == true;
    final canEndorse = configured && complete && !endorsed;

    final activeTab = _cardActiveTabs[teamId] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Inline Tab Swapping
        Container(
          height: 38,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              _expandedTabButton(teamId, 0, '📁 Deliverables'),
              const SizedBox(width: 20),
              _expandedTabButton(teamId, 1, '📊 Grades & Rubric'),
              if (widget.state.scope == 'capstone') ...[
                const SizedBox(width: 20),
                _expandedTabButton(teamId, 2, '📅 Weekly Reports'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (activeTab == 0) ...[
          if (stages.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: cardDecoration(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_busy_outlined,
                    size: 48,
                    color: AppColors.textSecondary.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.state.scope == 'pit'
                        ? 'No PIT events configured for ${team['year_level'] ?? 'this team'}.'
                        : 'No defense stages configured.',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.state.scope == 'pit'
                        ? 'Configure PIT events and deliverables in PIT Events Setup.'
                        : 'Configure stages and deliverables in Defense Stages Setup.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.touch_app_outlined,
                            size: 15,
                            color: AppColors.maroon,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.state.scope == 'pit' ? 'PIT Event Overview' : 'Defense Stage Overview',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Text(
                              widget.state.scope == 'pit'
                                  ? 'Click event to select view'
                                  : 'Click stage to select view',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.state.scope == 'admin' && stage['is_defense_done'] == true) ...[
                            OutlinedButton.icon(
                              onPressed: widget.state.isSaving
                                  ? null
                                  : () async {
                                      final success = await ref
                                          .read(capstoneDeliverablesProvider.notifier)
                                          .unlockDeliverables(
                                            teamId: teamId,
                                            stageLabel: selectedStage,
                                          );
                                      if (success && mounted) {
                                        showInfoToast(
                                          context,
                                          stage['admin_unlocked'] == true
                                              ? 'Deliverables relocked.'
                                              : 'Deliverables unlocked for resubmission.',
                                        );
                                      }
                                    },
                              icon: Icon(
                                stage['admin_unlocked'] == true
                                    ? Icons.lock_outline
                                    : Icons.lock_open_outlined,
                                size: 14,
                              ),
                              label: Text(
                                stage['admin_unlocked'] == true
                                    ? 'Relock Deliverables'
                                    : 'Unlock for Resubmission',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: stage['admin_unlocked'] == true
                                    ? AppColors.danger
                                    : AppColors.maroon,
                                side: BorderSide(
                                  color: stage['admin_unlocked'] == true
                                      ? AppColors.danger
                                      : AppColors.maroon,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          _buildStageStatusBadge(stage),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: stages.map((item) {
                      final label = item['stage_label']?.toString() ?? '';
                      final active = label == selectedStage;
                      final isCurrentConfig = label == team['current_stage']?.toString();

                      final isStageComplete = item['required_complete'] == true;
                      final isStageEndorsed = item['endorsed'] == true;
                      final isPit = widget.state.scope == 'pit';

                      return Tooltip(
                        message: active
                            ? '$label (Currently active ${isPit ? 'event' : 'stage'})'
                            : 'Click to select and view $label deliverables',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _cardSelectedStages[teamId] = label;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: active
                                    ? AppColors.maroon
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: active
                                      ? AppColors.maroon
                                      : const Color(0xFFCBD5E1),
                                  width: active ? 1.5 : 1.0,
                                ),
                                boxShadow: active
                                    ? [
                                        BoxShadow(
                                          color: AppColors.maroon.withValues(alpha: 0.25),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : [],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (active) ...[
                                    const Icon(
                                      Icons.check_circle,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                  ] else if (isStageEndorsed) ...[
                                    const Icon(
                                      Icons.verified,
                                      size: 14,
                                      color: AppColors.success,
                                    ),
                                    const SizedBox(width: 6),
                                  ] else if (isStageComplete) ...[
                                    const Icon(
                                      Icons.check_circle_outline,
                                      size: 14,
                                      color: Colors.blue,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                                      color: active ? Colors.white : AppColors.textPrimary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (isCurrentConfig) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: active
                                            ? Colors.white.withValues(alpha: 0.25)
                                            : AppColors.maroon.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Current',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: active ? Colors.white : AppColors.maroon,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Divider(color: Color(0xFFF1F5F9), height: 1),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final useVerticalLayout = constraints.maxWidth < 600;
                      final requiredUploaded = parseAsInt(stage['required_uploaded']);
                      final requiredTotal = parseAsInt(stage['required_total']);
                      final configuredReq = stage['deliverables_configured'] == true;
                      final archiveUnlocked = stage['archive_unlocked'] == true;

                      final reqBlock = Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: _requiredProgressBlock(
                          configured: configuredReq,
                          done: requiredUploaded,
                          total: requiredTotal,
                        ),
                      );

                      if (!archiveUnlocked) {
                        return reqBlock;
                      }

                      final archiveBlock = Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: _archiveProgressBlock(stage),
                      );

                      if (useVerticalLayout) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            reqBlock,
                            const SizedBox(height: 12),
                            archiveBlock,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: reqBlock),
                          const SizedBox(width: 16),
                          Expanded(child: archiveBlock),
                        ],
                      );
                    },
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(color: Color(0xFFE2E8F0), height: 1),
                  ),

                  _sectionTitle('Pre-Defense Requirements'),
                  const SizedBox(height: 8),
                  if (pre.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No pre-defense requirements configured.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else
                    ...pre.map(
                      (item) => _deliverableRow(
                        team,
                        selectedStage,
                        item,
                        (fn) => setState(fn),
                      ),
                    ),

                  if (stage['archive_unlocked'] == true) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(color: Color(0xFFE2E8F0), height: 1),
                    ),
                    _sectionTitle('Post-Defense Deliverables'),
                    const SizedBox(height: 8),
                    if (vault.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No post-defense deliverables configured.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                            fontSize: 12,
                          ),
                        ),
                      )
                    else
                      ...vault.map(
                        (item) => _deliverableRow(
                          team,
                          selectedStage,
                          item,
                          (fn) => setState(fn),
                        ),
                      ),
                  ],
                  if (canEndorse) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(color: Color(0xFFE2E8F0), height: 1),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: widget.state.isSaving
                            ? null
                            : () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('Endorse Team'),
                                    content: Text(
                                      'Endorse ${team['name']} for $selectedStage? '
                                      'This confirms all required deliverables are complete '
                                      'and the team is ready for defense scheduling.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, true),
                                        icon: const Icon(Icons.verified_outlined),
                                        label: const Text('Endorse'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.success,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && mounted) {
                                  await ref
                                      .read(capstoneDeliverablesProvider.notifier)
                                      .endorseTeam(
                                        parseAsInt(team['id']),
                                        selectedStage,
                                      );
                                }
                              },
                        icon: const Icon(Icons.verified_outlined, size: 16),
                        label: const Text(
                          'Endorse Team',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.maroon,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ] else if (activeTab == 1) ...[
          GradeDeliverableTab(
            team: team,
            selectedStage: selectedStage,
            isAdviser: widget.isAdviser,
            teamCriteriaScoreCtrls: _teamCriteriaScoreCtrls,
            teamManualScoreCtrls: _teamManualScoreCtrls,
            teamSelectedRubrics: _teamSelectedRubrics,
          ),
        ] else ...[
          SizedBox(
            height: 650,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: WeeklyProgressReportsScreen(
                  embeddedTeamId: teamId.toString(),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCompactTeamCard(
    Map<String, dynamic> team,
    bool isSelected,
  ) {
    final teamId = parseAsInt(team['id']);
    final stages = _stageList(team);
    final cardSelectedStageLabel = _effectiveSelectedStage(team);
    final selectedStage = _stagePayload(stages, cardSelectedStageLabel);

    final badge = _resolveStageStatusBadge(selectedStage);
    final badgeColor = badge['color'] as Color;
    final badgeText = badge['label'] as String;
    final badgeIcon = badge['icon'] as IconData;

    final gradingState = ref.watch(adviserGradingProvider);
    final gradeRecord = gradingState.grades.firstWhere(
      (g) => parseAsInt(g['team_id']) == teamId && g['stage_label']?.toString() == cardSelectedStageLabel,
      orElse: () => team['grade'] is Map ? Map<String, dynamic>.from(team['grade'] as Map) : <String, dynamic>{},
    );
    final adviserScore = gradeRecord['adviser_score'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.maroon.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppColors.maroon : const Color(0xFFE2E8F0),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _selectedTeamId = teamId;
              _showMobileDetail = true;
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            team['name']?.toString() ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isSelected ? AppColors.maroon : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            team['project_title']?.toString() ?? 'No Project Title',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, size: 12, color: badgeColor),
                          const SizedBox(width: 4),
                          Text(
                            badgeText,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (team['adviser_name']?.toString().isNotEmpty == true) ...[
                      const Icon(Icons.person_outline, size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          team['adviser_name'].toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                    if (adviserScore != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Adv: ${parseAsDouble(adviserScore)?.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTeamListCompact() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.state.teams.length,
      itemBuilder: (context, index) {
        final team = widget.state.teams[index];
        final teamId = parseAsInt(team['id']);
        final isSelected = teamId == _selectedTeamId;
        return _buildCompactTeamCard(team, isSelected);
      },
    );
  }

  Widget _buildNoSelectionDetailPane() {
    return Container(
      decoration: cardDecoration(),
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined, size: 48, color: AppColors.textSecondary),
          SizedBox(height: 16),
          Text(
            'Select a Team',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Choose a team from the list on the left to view deliverables, grades, and team details.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  void _showRosterDetailsModal(BuildContext context, Map<String, dynamic> team, Map<String, dynamic>? gradeRecord) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.groups_outlined, color: AppColors.maroon),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${team['name']} - Team Roster & Peer Evaluation',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: buildRosterAndIndividualGrades(team, gradeRecord),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactRosterBanner(BuildContext context, Map<String, dynamic> team, Map<String, dynamic>? gradeRecord) {
    final List<dynamic> members = team['members'] as List? ?? [];
    final List<dynamic> peerGrades = gradeRecord?['peer_per_student'] as List? ?? [];

    if (members.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.groups_outlined, size: 16, color: AppColors.maroon),
                  const SizedBox(width: 6),
                  Text(
                    'Team Roster (${members.length})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => _showRosterDetailsModal(context, team, gradeRecord),
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View Details & Peer Scores',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.maroon,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.chevron_right, size: 14, color: AppColors.maroon),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: members.map((rawMember) {
              if (rawMember is! Map) return const SizedBox.shrink();
              final member = Map<String, dynamic>.from(rawMember);
              final studentId = member['id'];
              final name = member['name']?.toString() ?? member['username']?.toString() ?? 'Student';
              final role = member['role']?.toString() ?? 'member';
              final isLeader = role == 'leader';

              final peerDetails = peerGrades.firstWhere(
                (g) => g is Map && g['student_id'] == studentId,
                orElse: () => null,
              );
              final double? avgScore = parseAsDouble(peerDetails?['average_score']);

              final sanitizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
              final parts = sanitizedName.split(' ');
              final initials = parts.isNotEmpty
                  ? (parts.first.isNotEmpty ? parts.first[0] : '') +
                      (parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '')
                  : '';

              return Tooltip(
                message: avgScore != null
                    ? '$name • Peer Score: ${avgScore.toStringAsFixed(1)} / 5.0'
                    : '$name (Click to view details)',
                child: InkWell(
                  onTap: () => _showRosterDetailsModal(context, team, gradeRecord),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isLeader ? AppColors.maroon.withValues(alpha: 0.4) : const Color(0xFFCBD5E1),
                        width: isLeader ? 1.5 : 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: isLeader ? AppColors.maroon : const Color(0xFF64748B),
                          child: Text(
                            initials.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isLeader ? FontWeight.bold : FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (isLeader) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.maroon.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Leader',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppColors.maroon,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamDetailPane(Map<String, dynamic> team) {
    final teamId = parseAsInt(team['id']);
    final gradingState = ref.watch(adviserGradingProvider);
    final cardSelectedStageLabel = _effectiveSelectedStage(team);
    final gradeRecord = gradingState.grades.firstWhere(
      (g) => parseAsInt(g['team_id']) == teamId && g['stage_label']?.toString() == cardSelectedStageLabel,
      orElse: () => team['grade'] is Map ? Map<String, dynamic>.from(team['grade'] as Map) : <String, dynamic>{},
    );

    return Container(
      decoration: cardDecoration(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team['name']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      team['project_title']?.toString() ?? 'No Project Title',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (team['adviser_name']?.toString().isNotEmpty == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'Adviser: ${team['adviser_name']}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCompactRosterBanner(context, team, gradeRecord),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFE2E8F0), height: 1),
          const SizedBox(height: 16),
          _buildExpandedSection(team),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    final teamIds = widget.state.teams.map((t) => parseAsInt(t['id'])).toList();
    if (_selectedTeamId == null || !teamIds.contains(_selectedTeamId)) {
      if (teamIds.isNotEmpty) {
        _selectedTeamId = teamIds.first;
      }
    }

    final selectedTeam = widget.state.teams.firstWhere(
      (t) => parseAsInt(t['id']) == _selectedTeamId,
      orElse: () => <String, dynamic>{},
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 320,
          child: Container(
            decoration: cardDecoration(),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'Teams (${widget.state.teams.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                _buildTeamListCompact(),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: selectedTeam.isNotEmpty
              ? _buildTeamDetailPane(selectedTeam)
              : _buildNoSelectionDetailPane(),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    final selectedTeam = widget.state.teams.firstWhere(
      (t) => parseAsInt(t['id']) == _selectedTeamId,
      orElse: () => <String, dynamic>{},
    );

    if (_showMobileDetail && selectedTeam.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _showMobileDetail = false;
              });
            },
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Back to Team List'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
          const SizedBox(height: 12),
          _buildTeamDetailPane(selectedTeam),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Teams (${widget.state.teams.length})',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        _buildTeamListCompact(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state.teams.isEmpty) {
      return Container(
        decoration: cardDecoration(),
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        child: const Column(
          children: [
            Icon(Icons.inbox, size: 48, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text(
              'No teams match the current filters.',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 900;
    return isWide ? _buildDesktopLayout() : _buildMobileLayout();
  }
}
