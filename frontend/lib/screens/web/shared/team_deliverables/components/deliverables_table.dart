import 'package:defensys/theme/program_colors.dart';
import 'package:defensys/widgets/repository/concept_workspace.dart';
import 'package:defensys/widgets/repository/document_group.dart';
import 'package:defensys/widgets/repository/deliverable_file_widgets.dart';
import 'package:defensys/widgets/defense/system_defense_records.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/widgets/repository/workflow_status_style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/reports_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/utils/universal_file_viewer.dart';
import 'package:defensys/widgets/confirm_dialog.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/screens/web/faculty/weekly_progress_reports_screen.dart';
import 'package:defensys/screens/web/faculty/adviser/adviser_defense_tab.dart';
import 'package:defensys/screens/web/faculty/pit_instructor/pit_team_schedule_tab.dart';
import 'package:defensys/screens/web/shared/team_deliverables/components/faculty_teams_overview_export.dart';
import 'package:defensys/screens/web/shared/team_deliverables/dialogs/deliverable_submission_detail_modal.dart';
import 'package:defensys/screens/web/shared/team_deliverables/dialogs/grade_deliverable_modal.dart';
import 'package:defensys/screens/web/shared/team_deliverables/dialogs/wpr_management_dialogs.dart';
import 'package:defensys/services/auth_provider.dart';
import 'package:defensys/screens/web/admin/grade_center/defense_workflow_panel.dart';
import 'package:defensys/models/adviser_workflow.dart';
import 'package:defensys/services/defense/team_defense_provider.dart';
import 'package:defensys/widgets/adviser/workflow_reminder.dart';
import 'package:defensys/widgets/repository/defense_material_readiness.dart';
import 'package:defensys/screens/web/admin/defense_board/components/material_deadline_dialog.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import '../deliverables_view_types.dart';
import '../../project_archive/dialogs/stage_access_management_dialog.dart';

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

BoxDecoration cardDecoration(BuildContext context) {
  return BoxDecoration(
    color: DefensysTokens.surfaceOf(context),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: DefensysTokens.borderOf(context)),
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
  final bool isPitInstructor;
  final int? initialTeamId;
  final int? initialTab;
  final TeamTriageFilter activeTriageFilter;
  final ValueChanged<int>? onOpenSharedReview;

  const DeliverablesTablePane({
    super.key,
    required this.state,
    required this.isAdviser,
    this.isPitInstructor = false,
    this.initialTeamId,
    this.initialTab,
    this.activeTriageFilter = TeamTriageFilter.all,
    this.onOpenSharedReview,
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
  final Map<String, Map<dynamic, Map<String, TextEditingController>>> _teamStudentCriteriaScoreCtrls = {};
  final Map<String, TextEditingController> _teamManualScoreCtrls = {};
  final Map<String, Map<String, dynamic>?> _teamSelectedRubrics = {};

  Timer? _pendingRemoveTimer;
  bool _pendingRemoveCancelled = false;

  @override
  void initState() {
    super.initState();
    _selectedTeamId = widget.initialTeamId;
    _showMobileDetail = widget.initialTeamId != null;
    if (widget.initialTeamId != null && widget.initialTab != null) {
      _cardActiveTabs[widget.initialTeamId!] = widget.initialTab!;
    }
  }

  @override
  void didUpdateWidget(covariant DeliverablesTablePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTeamId != oldWidget.initialTeamId &&
        widget.initialTeamId != null) {
      _selectedTeamId = widget.initialTeamId;
      _showMobileDetail = true;
      if (widget.initialTab != null) {
        _cardActiveTabs[widget.initialTeamId!] = widget.initialTab!;
      }
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
    for (final perStudentMap in _teamStudentCriteriaScoreCtrls.values) {
      for (final subMap in perStudentMap.values) {
        for (final c in subMap.values) {
          c.dispose();
        }
      }
    }
    super.dispose();
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: DefensysTokens.textSecondaryOf(context),
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
    if ((widget.isAdviser || widget.isPitInstructor) &&
        widget.state.selectedStage.isNotEmpty) {
      return widget.state.selectedStage;
    }

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
        lowerName.endsWith('.gif') ||
        lowerName.endsWith('.svg')) {
      return Icons.image_outlined;
    } else if (lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.mov') ||
        lowerName.endsWith('.avi') ||
        lowerName.endsWith('.mkv') ||
        lowerName.endsWith('.webm')) {
      return Icons.video_library_outlined;
    } else if (lowerName.endsWith('.mp3') ||
        lowerName.endsWith('.wav') ||
        lowerName.endsWith('.aac') ||
        lowerName.endsWith('.ogg') ||
        lowerName.endsWith('.m4a')) {
      return Icons.audiotrack_outlined;
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
    } else if (lowerName.endsWith('.txt') ||
        lowerName.endsWith('.json') ||
        lowerName.endsWith('.sql') ||
        lowerName.endsWith('.md')) {
      return Icons.code_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Color _getFileIconColor(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.pdf')) {
      return const Color(0xFFEF4444);
    } else if (lowerName.endsWith('.png') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.webp') ||
        lowerName.endsWith('.gif') ||
        lowerName.endsWith('.svg')) {
      return const Color(0xFF06B6D4);
    } else if (lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.mov') ||
        lowerName.endsWith('.avi') ||
        lowerName.endsWith('.mkv') ||
        lowerName.endsWith('.webm')) {
      return const Color(0xFF8B5CF6);
    } else if (lowerName.endsWith('.mp3') ||
        lowerName.endsWith('.wav') ||
        lowerName.endsWith('.aac') ||
        lowerName.endsWith('.ogg') ||
        lowerName.endsWith('.m4a')) {
      return const Color(0xFFF43F5E);
    } else if (lowerName.endsWith('.zip') ||
        lowerName.endsWith('.rar') ||
        lowerName.endsWith('.7z')) {
      return const Color(0xFF64748B);
    } else if (lowerName.endsWith('.doc') ||
        lowerName.endsWith('.docx')) {
      return const Color(0xFF2563EB);
    } else if (lowerName.endsWith('.ppt') ||
        lowerName.endsWith('.pptx')) {
      return const Color(0xFFEA580C);
    } else if (lowerName.endsWith('.xls') ||
        lowerName.endsWith('.xlsx') ||
        lowerName.endsWith('.csv')) {
      return const Color(0xFF10B981);
    } else if (lowerName.endsWith('.txt') ||
        lowerName.endsWith('.json') ||
        lowerName.endsWith('.sql') ||
        lowerName.endsWith('.md')) {
      return const Color(0xFFF59E0B);
    }
    return Colors.grey.shade600;
  }

  Future<void> _viewPdf(String fileUrl, String fileName) async {
    if (fileUrl.isEmpty) {
      showErrorToast(context, 'File URL not available');
      return;
    }

    await viewFileInDialog(
      context: context,
      fileUrl: fileUrl,
      fileName: fileName,
    );
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
      programScope: widget.state.scope,
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
    final isPost = item['type'] == 'post' || item['deliverable_type'] == 'post';

    final stages = _stageList(team);
    final stagePayload = _stagePayload(stages, stageLabel);
    final grade = stagePayload['grade'] is Map
        ? Map<String, dynamic>.from(stagePayload['grade'] as Map)
        : (team['grade'] is Map ? Map<String, dynamic>.from(team['grade'] as Map) : <String, dynamic>{});
    final workflow = grade['workflow'] is Map ? Map<String, dynamic>.from(grade['workflow'] as Map) : <String, dynamic>{};

    final authUser = ref.read(authProvider).user ?? <String, dynamic>{};
    final isAdmin = authUser['role'] == 'admin' || authUser['is_superuser'] == true;
    final currentUserId = int.tryParse('${authUser['id']}');
    final isChair = currentUserId != null && currentUserId == workflow['chair_id'];
    final isAdviser = currentUserId != null && (
        currentUserId == workflow['adviser_id'] ||
        currentUserId == team['adviser_id'] ||
        (team['adviser'] is Map && currentUserId == team['adviser']?['id'])
    );
    final canManageClearance = isAdmin || isChair || isAdviser;

    final hasPendingRevisions = grade['verdict'] == 'approved_with_revisions' && grade['revisions_cleared_at'] == null;
    final canClearRevisions = isPost && canManageClearance && hasPendingRevisions;
    bool clearRevisions = canClearRevisions;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: AppColors.success, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isPost ? 'Approve for Archive' : 'Accept Pre-Defense Requirement',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isPost
                    ? 'Approve "$deliverableName" for $teamName and add it to the archive?'
                    : 'Accept "$deliverableName" for $teamName? This clears a pre-defense requirement for endorsement.',
                style: TextStyle(fontSize: 13, color: DefensysTokens.textPrimaryOf(context)),
              ),
              if (canClearRevisions) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: clearRevisions,
                    onChanged: (val) => setDialogState(() => clearRevisions = val ?? true),
                    title: Text(
                      isAdviser && !isAdmin && !isChair
                          ? 'Approve & Clear Defense Revisions (as Adviser)'
                          : 'Approve & Clear Defense Revisions',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                    ),
                    subtitle: Text(
                      isAdviser && !isAdmin && !isChair
                          ? 'Certifies that panel-required revisions were satisfied. Advances defense status to Passed.'
                          : 'Clears pending revisions for this stage and advances defense status to Passed.',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF15803D)),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              ],
              if (isPost && !canClearRevisions) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: AppColors.gold),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Approval makes this file available in the archive according to its access settings. Only a System Admin can reopen it for revision.',
                          style: TextStyle(fontSize: 12, color: DefensysTokens.textPrimaryOf(context), height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
              child: Text(
                canClearRevisions && clearRevisions
                    ? 'Approve & Clear Revisions'
                    : (isPost ? 'Approve & Archive' : 'Accept Requirement'),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(capstoneDeliverablesProvider.notifier).reviewDeliverable(
            teamId: parseAsInt(team['id']),
            stageLabel: stageLabel,
            deliverableId: item['id'].toString(),
            status: 'accepted',
            clearDefenseRevisions: canClearRevisions && clearRevisions,
          );
    }
  }

  Future<void> _promptRejectDialog(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
  ) async {
    final isPost = item['type'] == 'post' || item['deliverable_type'] == 'post';
    final isDefense = !isPost && item['requirement_timing'] == 'defense';
    final actionLabel = isPost
        ? 'Request Revision'
        : isDefense ? 'Request corrections' : 'Reject';
    var feedback = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
        title: Text('$actionLabel: ${item['label'] ?? item['id']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPost
                  ? 'Explain what the team must correct before this file can be archived:'
                  : 'Explain what the team needs to correct and upload again:',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (value) => setDialogState(() => feedback = value),
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Describe the required corrections...',
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
            onPressed: feedback.trim().isEmpty
                ? null
                : () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: Text(isPost ? 'Send Revision Request' : actionLabel),
          ),
        ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(capstoneDeliverablesProvider.notifier).reviewDeliverable(
            teamId: parseAsInt(team['id']),
            stageLabel: stageLabel,
            deliverableId: item['id'].toString(),
            status: 'rejected',
            feedback: feedback.trim(),
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
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: DefensysTokens.panelOf(context),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: DefensysTokens.borderOf(context)),
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
                    style: TextStyle(fontSize: 10, color: DefensysTokens.textSecondaryOf(context)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => showDeliverableFileDetails(
              context: context,
              label: '${item['label'] ?? 'Document'}',
              stageLabel: stageLabel,
              programScope: programTrack(scope: widget.state.scope, data: team).name,
              file: {...submission, ...fileMap},
              uploader: submission['uploaded_by_name']?.toString(),
              status: (fileMap['status'] ?? submission['status']) == 'accepted'
                  ? item['type'] == 'post' ? 'Archived' : 'Accepted'
                  : (fileMap['status'] ?? submission['status']) == 'rejected'
                  ? 'Corrections requested'
                  : item['requirement_timing'] == 'defense' ? 'Uploaded' : 'Awaiting review',
            ),
            style: TextButton.styleFrom(
              foregroundColor: DefensysTokens.textPrimaryOf(context),
              textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Details'),
          ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: 'View File',
            icon: const Icon(
              Icons.visibility_outlined,
              color: Colors.blue,
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
    if (usesGroupedDocumentCard(item)) {
      return DocumentGroup(
        teamId: team['id'] as int,
        stageLabel: stageLabel,
        item: item,
        programScope: programTrack(scope: widget.state.scope, data: team).name,
      );
    }
    final submission = item['submission'] as Map?;
    final uploaded = hasSubmittedDeliverable(item);
    final isFaculty = widget.isAdviser || widget.state.scope == 'pit' || widget.state.scope == 'capstone';
    final isAdmin = widget.state.scope == 'admin';

    final stages = _stageList(team);
    final currentStageObj = _stagePayload(stages, stageLabel);
    final endorsed = currentStageObj['endorsed'] == true;
    final subStatus = submission?['status']?.toString();
    final locked = item['can_upload'] is bool ? item['can_upload'] != true :
        item['locked'] == true || subStatus == 'accepted';
    final isPost = item['type'] == 'post' || item['deliverable_type'] == 'post';
    final postLocked = isPost && locked;
    final isDefense = !isPost && item['requirement_timing'] == 'defense';
    final displayCleared = subStatus == 'accepted' || (isDefense && uploaded && subStatus != 'rejected');
    final canFacultyReview = item['can_faculty_review'] is bool
        ? item['can_faculty_review'] == true
        : (isPost
            ? currentStageObj['can_faculty_review_post'] == true
            : currentStageObj['can_faculty_review'] == true);

    final isWPR = item['id']?.toString() == 'WPR' ||
        item['label']?.toString().contains('Weekly Progress Report') == true;

    final feedback = submission?['feedback']?.toString();

    final fileStyle = WorkflowStatusStyle.of(context,
      subStatus == 'rejected' ? WorkflowStatusTone.attention
        : displayCleared ? WorkflowStatusTone.success
        : uploaded ? WorkflowStatusTone.active : WorkflowStatusTone.neutral);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fileStyle.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                displayCleared
                    ? Icons.check_circle_rounded
                    : (subStatus == 'rejected'
                        ? Icons.cancel_rounded
                        : (uploaded
                            ? Icons.hourglass_empty_rounded
                            : (postLocked ? Icons.lock_outline : Icons.radio_button_unchecked))),
                color: fileStyle.foreground,
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
                              color: uploaded ? DefensysTokens.textPrimaryOf(context) : DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ),
                        if (item['required'] == false) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: DefensysTokens.textSecondaryOf(context).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'OPTIONAL',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                            ),
                          ),
                        ],
                        if (submission?['is_late'] == true || item['is_late'] == true) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFEA580C).withValues(alpha: 0.3)),
                            ),
                            child: const Text(
                              'LATE SUBMISSION',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFEA580C),
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
                        style: TextStyle(fontSize: 11, color: DefensysTokens.textSecondaryOf(context)),
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
                if (isDefense) ...[
                  Text(item['materials_status'] == 'overdue' ? 'Overdue' : 'Missing',
                      style: TextStyle(fontSize: 11, color: item['materials_status'] == 'overdue' ? AppColors.danger : DefensysTokens.textSecondaryOf(context))),
                  const SizedBox(width: 8),
                ],
                if (!isFaculty || isAdmin)
                  if (!locked)
                    OutlinedButton.icon(
                      onPressed: () => _promptUploadOrReplace(team, stageLabel, item),
                      icon: const Icon(Icons.upload_file, size: 14),
                      label: const Text('Upload'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DefensysTokens.textPrimaryOf(context),
                        side: BorderSide(color: DefensysTokens.borderOf(context)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        visualDensity: VisualDensity.compact,
                        elevation: 0,
                      ),
                    ),
              ] else if (uploaded && !isWPR) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: isAdmin && isPost && subStatus == 'accepted'
                      ? 'Use Reopen for Revision in Repository Audit to correct this file.'
                      : '',
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: DeliverableStatusBadge(
                    label: subStatus == 'rejected'
                        ? 'Corrections requested'
                        : subStatus == 'accepted'
                        ? (isPost ? 'Archived' : 'Accepted')
                        : isDefense ? 'Uploaded'
                        : isFaculty && !isAdmin && !canFacultyReview
                        ? 'Locked (Defense Done)' : 'Awaiting review',
                    tone: subStatus == 'rejected'
                        ? WorkflowStatusTone.attention
                        : displayCleared
                        ? WorkflowStatusTone.success
                        : isFaculty && !isAdmin && !canFacultyReview
                        ? WorkflowStatusTone.neutral
                        : WorkflowStatusTone.attention,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (isDefense) ...[
              const SizedBox(height: 6),
              Text(item['due_at'] == null
                  ? 'Deadline set when defense is scheduled'
                  : 'Due before defense: ${materialDeadlineLabel(item['due_at'])}',
                  style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context))),
          ],
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
                      'Corrections requested: $feedback',
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
          if (uploaded && !isWPR &&
              ((isFaculty && !isAdmin) || (isAdmin && isDefense)) && canFacultyReview &&
              !(isPost && subStatus == 'accepted')) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: DefensysShadcnScope(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!isDefense && subStatus != 'accepted')
                      ShadButton.outline(
                        size: ShadButtonSize.sm,
                        enabled: !widget.state.isSaving,
                        onPressed: () => _promptAcceptDialog(team, stageLabel, item),
                        child: Text(isPost ? 'Approve & Archive' : 'Accept'),
                      ),
                    if (!isDefense || subStatus != 'rejected')
                      ShadButton.ghost(
                        size: ShadButtonSize.sm,
                        enabled: !widget.state.isSaving,
                        onPressed: () => _promptRejectDialog(team, stageLabel, item),
                        child: const Text('Request corrections'),
                      ),
                  ],
                ),
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
    required int accepted,
    bool isPresentationOnly = false,
  }) {
    if (isPresentationOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Oral / Presentation Milestone',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              Text(
                'No Uploads Required',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2563EB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              value: 1.0,
              minHeight: 6,
              backgroundColor: Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
            ),
          ),
        ],
      );
    }

    if (configured && total == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Scheduling Clearance', style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.bold,
            color: DefensysTokens.textPrimaryOf(context),
          )),
          SizedBox(height: 6),
          Text('No scheduling uploads required', style: TextStyle(
            fontSize: 12, color: DefensysTokens.textSecondaryOf(context),
          )),
        ],
      );
    }

    final pct = total > 0 ? (accepted / total).clamp(0.0, 1.0) : 0.0;
    final color = accepted == total && total > 0 ? AppColors.success : const Color(0xFF2563EB);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(
              'Scheduling Clearance',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            Text(
              configured ? '$done/$total submitted, $accepted/$total accepted' : 'Not Configured',
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
    final accepted = parseAsInt(stage['archive_required_accepted']);
    final total = parseAsInt(stage['archive_required_total']);
    final pct = total > 0 ? (accepted / total).clamp(0.0, 1.0) : 0.0;
    final color = accepted == total && total > 0 ? AppColors.success : AppColors.gold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(
              'Post-Defense Deliverables',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            Text(
              '$done/$total uploaded, $accepted/$total archived',
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

  Widget _buildStageStatusBadge(Map<String, dynamic> stage) => TeamWorkflowBadge(
    status: TeamWorkflowStatus.fromStage(stage, scope: widget.state.scope),
  );

  bool _canEndorseTeam(Map<String, dynamic> stage) {
    final review = stage['endorsement_review'];
    return stage['required_complete'] == true &&
        review is Map &&
        review['can_review_and_endorse'] == true;
  }

  Future<void> _confirmEndorseTeam(
    Map<String, dynamic> team,
    String selectedStage,
    bool isPresentationOnly,
  ) async {
    final stage = _stagePayload(_stageList(team), selectedStage);
    if (!_canEndorseTeam(stage)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Endorse team'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isPresentationOnly
              ? 'Endorse ${team['name']} for $selectedStage? '
                'This confirms the team is verbally prepared and ready for presentation / demo scheduling.'
              : 'All required before-endorsement files have been accepted. '
                'Endorse ${team['name']} for $selectedStage? This records approval of the team’s work. Any required shared-paper acceptance and adviser acknowledgment remain separate scheduling checks.'),
              const SizedBox(height: 16),
              const Text('Before-defense materials remain due by their scheduled deadline.', style: TextStyle(fontSize: 12)),
            ],
          )),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
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
      await ref.read(capstoneDeliverablesProvider.notifier).endorseTeam(
            parseAsInt(team['id']),
            selectedStage,
          );
    }
  }

  Widget _buildEndorseButton(
    Map<String, dynamic> team,
    String selectedStage, {
    required bool enabled,
    required bool isPresentationOnly,
  }) {
    return ElevatedButton.icon(
      onPressed: enabled && !widget.state.isSaving
          ? () => _confirmEndorseTeam(team, selectedStage, isPresentationOnly)
          : null,
      icon: const Icon(Icons.verified_outlined, size: 16),
      label: const Text(
        'Endorse team',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: DefensysTokens.maroonOf(context),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _expandedTabButton(
    int teamId,
    int tabIndex,
    String label, {
    String? badgeText,
    Color? badgeColor,
  }) {
    final activeTab = _cardActiveTabs[teamId] ?? 0;
    final isActive = activeTab == tabIndex;
    return InkWell(
      onTap: () {
        setState(() {
          _cardActiveTabs[teamId] = tabIndex;
        });
      },
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: isActive
              ? Border(
                  bottom: BorderSide(
                    color: DefensysTokens.maroonOf(context),
                    width: 2.5,
                  ),
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                color: isActive ? DefensysTokens.maroonTextOf(context) : DefensysTokens.textSecondaryOf(context),
                fontSize: 13,
              ),
            ),
            if (badgeText != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: (badgeColor ?? DefensysTokens.textSecondaryOf(context)).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeColor ?? DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedSection(Map<String, dynamic> team) {
    final teamId = parseAsInt(team['id']);
    final stages = _stageList(team);
    final selectedStage = _effectiveSelectedStage(team);

    final stage = _stagePayload(stages, selectedStage);
    final gradingState = ref.watch(adviserGradingProvider);
    final gradingStatus = AdviserGradingStatus.fromGrade(
      adviserGradeForTeam(team, selectedStage, gradingState.grades),
      enabled: gradingState.adviserGradingEnabled, loading: gradingState.isLoading,
      error: gradingState.error, officiallyComplete: stage['is_officially_complete'] == true);
    final minutesToSign = adviserMinutesToSign(team, selectedStage,
      ref.watch(teamDefenseProvider).schedules);
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
    final beforeEndorsement = pre
        .where((item) => item['requirement_timing'] != 'defense')
        .toList();
    final beforeDefense = pre
        .where((item) => item['requirement_timing'] == 'defense')
        .toList();

    final isPresentationOnly = stage['is_presentation_only'] == true;
    final configured = stage['deliverables_configured'] == true || isPresentationOnly;
    final endorsed = stage['endorsed'] == true;
    final archiveUnlocked = stage['archive_unlocked'] == true;
    final showPostChecklist = vault.isNotEmpty &&
        (endorsed || stage['has_active_schedule'] == true ||
            stage['has_done_schedule'] == true);
    final canEndorse = configured && _canEndorseTeam(stage) && !endorsed &&
        (widget.state.scope != 'pit' || stage['endorsement_required'] != false);
    final canCancelEndorsement = (stage['can_cancel_endorsement'] == true) ||
        (endorsed &&
            stage['has_active_schedule'] != true &&
            stage['has_done_schedule'] != true &&
            stage['is_defense_done'] != true &&
            stage['stage_status_detail'] == 'endorsed');
    final isFacultyOrAdmin = widget.isAdviser ||
        widget.state.scope == 'pit' ||
        widget.state.scope == 'capstone' ||
        widget.state.scope == 'admin';

    final activeTab = _cardActiveTabs[teamId] ?? 0;
    final reqUploaded = parseAsInt(stage['required_uploaded']);
    final reqTotal = parseAsInt(stage['required_total']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Workspace Tab Switcher
        Container(
          height: 40,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: DefensysTokens.borderOf(context))),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
            children: [
              _expandedTabButton(
                teamId,
                0,
                'Deliverables',
                badgeText: isPresentationOnly ? 'Oral / Demo' : (configured ? '$reqUploaded/$reqTotal' : null),
                badgeColor: isPresentationOnly
                    ? const Color(0xFF4F46E5)
                    : ((configured && reqUploaded >= reqTotal && reqTotal > 0)
                        ? AppColors.success
                        : DefensysTokens.textSecondaryOf(context)),
              ),
              if (widget.isAdviser && widget.state.scope == 'capstone') ...[
                const SizedBox(width: 24),
                _expandedTabButton(teamId, 2, 'Weekly Reports'),
                const SizedBox(width: 24),
                _expandedTabButton(teamId, 3, 'Defense',
                  badgeText: minutesToSign.isEmpty ? null : 'Sign minutes${minutesToSign.length > 1 ? ' (${minutesToSign.length})' : ''}',
                  badgeColor: AdviserWorkflowReminder.colorOf(context, AdviserWorkflowTone.success, onLightSurface: true)),
              ],
              const SizedBox(width: 24),
              _expandedTabButton(teamId, 1, 'Grades & Rubric',
                badgeText: widget.isAdviser && gradingStatus.badge != 'Not open'
                    ? gradingStatus.badge : null,
                badgeColor: AdviserWorkflowReminder.colorOf(context, gradingStatus.tone, onLightSurface: true)),
              if (!widget.isAdviser && widget.state.scope == 'capstone') ...[
                const SizedBox(width: 24),
                _expandedTabButton(teamId, 2, 'Weekly Reports'),
              ],
              if (widget.isPitInstructor) ...[
                const SizedBox(width: 24),
                _expandedTabButton(teamId, 3, 'Schedule'),
              ],
            ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (activeTab == 0) ...[
          if (stages.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: cardDecoration(context),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_busy_outlined,
                    size: 48,
                    color: DefensysTokens.textSecondaryOf(context).withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.state.scope == 'pit'
                        ? 'No PIT events configured for ${team['year_level'] ?? 'this team'}.'
                        : 'No defense stages configured.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (!widget.isAdviser) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.state.scope == 'pit'
                          ? 'Configure PIT events and deliverables in PIT Events Setup.'
                          : 'Configure stages and deliverables in Defense Stages Setup.',
                      style: TextStyle(
                        fontSize: 12,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            )
          else ...[
            ConceptWorkspace(teamId: team['id'] as int, stageLabel: selectedStage, stage: stage,
              onOpenSharedReview: widget.onOpenSharedReview),
            // Deliverables Progress Summary (Required & Post-Defense Archive)
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
                    color: DefensysTokens.surfaceHigherOf(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: DefensysTokens.borderOf(context)),
                  ),
                  child: _requiredProgressBlock(
                    configured: configuredReq,
                    done: requiredUploaded,
                    total: requiredTotal,
                    accepted: (stage['pre'] as List? ?? []).whereType<Map>().where(
                      (item) => item['required'] == true &&
                          item['requirement_timing'] != 'defense' &&
                          item['submission'] is Map && item['submission']['status'] == 'accepted',
                    ).length,
                    isPresentationOnly: isPresentationOnly,
                  ),
                );

                if (!archiveUnlocked) {
                  return reqBlock;
                }

                final archiveBlock = Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: DefensysTokens.surfaceHigherOf(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: DefensysTokens.borderOf(context)),
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
            if (isPresentationOnly)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Color(0xFF2563EB)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Presentation / Demo Stage — No document uploads required. Advisers can endorse the team directly.',
                        style: TextStyle(
                          color: Color(0xFF1D4ED8),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (pre.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No pre-defense requirements configured.',
                  style: TextStyle(
                    color: DefensysTokens.textSecondaryOf(context),
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                  ),
                ),
              )
            else ...[
              if (beforeEndorsement.isNotEmpty) ...[
                _sectionTitle(stage['endorsement_required'] == false
                    ? 'Before scheduling'
                    : 'Before endorsement'),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 10),
                  child: Text(
                    stage['endorsement_required'] == false
                        ? 'Required files here must be cleared before the team can be scheduled.'
                        : 'Required files here must be cleared before the team can be endorsed.',
                    style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context)),
                  ),
                ),
                ...beforeEndorsement.map(
                  (item) => _deliverableRow(
                    team,
                    selectedStage,
                    item,
                    (fn) => setState(fn),
                  ),
                ),
              ],
              if (beforeDefense.isNotEmpty) ...[
                if (beforeEndorsement.isNotEmpty) const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _sectionTitle('Before defense'),
                    const Spacer(),
                    if (((widget.state.scope == 'admin' ||
                                ref.watch(authProvider).user?['is_pit_lead'] == true ||
                                ref.watch(authProvider).user?['role'] == 'admin') &&
                            stage['schedule'] is Map))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () async {
                            final sched =
                                Map<String, dynamic>.from(stage['schedule'] as Map);
                            sched.putIfAbsent(
                              'materials_readiness',
                              () => stage['materials_readiness'],
                            );
                            sched.putIfAbsent('team_name', () => team['name']);
                            sched.putIfAbsent('stage_label', () => selectedStage);
                            await showMaterialDeadlineDialog(context, sched);
                            ref
                                .read(capstoneDeliverablesProvider.notifier)
                                .fetchInitialData();
                          },
                          icon: const Icon(Icons.edit_calendar_outlined, size: 14),
                          label: const Text('Edit deadline'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                DefenseMaterialReadiness(
                  readiness: Map<String, dynamic>.from(
                    stage['materials_readiness'] as Map? ?? const {},
                  ),
                ),
                ...beforeDefense.map(
                  (item) => _deliverableRow(
                    team,
                    selectedStage,
                    item,
                    (fn) => setState(fn),
                  ),
                ),
              ],
            ],

            if (showPostChecklist) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(color: Color(0xFFE2E8F0), height: 1),
              ),
              _sectionTitle('Post-Defense Deliverables'),
              const SizedBox(height: 8),
              if (!archiveUnlocked)
                Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, size: 15, color: DefensysTokens.textSecondaryOf(context)),
                      SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'For after this defense. Student uploads and faculty review open once the defense is completed.',
                          style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context)),
                        ),
                      ),
                    ],
                  ),
                ),
              ...vault.map(
                (item) => _deliverableRow(
                  team,
                  selectedStage,
                  item,
                  (fn) => setState(fn),
                ),
              ),
            ],

            if (_deliverables(stage, 'system').isNotEmpty) ...[
              const SizedBox(height: 20),
              SystemDefenseRecords(items: _deliverables(stage, 'system')),
            ],
            if (canEndorse && !widget.isAdviser && !widget.isPitInstructor) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(color: Color(0xFFE2E8F0), height: 1),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _buildEndorseButton(
                  team,
                  selectedStage,
                  enabled: true,
                  isPresentationOnly: isPresentationOnly,
                ),
              ),
            ] else if (canCancelEndorsement && isFacultyOrAdmin) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(color: Color(0xFFE2E8F0), height: 1),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: widget.state.isSaving
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                                  SizedBox(width: 8),
                                  Text('Cancel Endorsement'),
                                ],
                              ),
                              content: Text(
                                'Cancel endorsement for ${team['name']} on stage "$selectedStage"?\n\n'
                                'This will remove the team from the defense scheduling queue and unlock pre-defense deliverables for review and revision.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, false),
                                  child: const Text('Keep Endorsed'),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, true),
                                  icon: const Icon(Icons.undo, size: 16),
                                  label: const Text('Cancel Endorsement'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.danger,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true && mounted) {
                            await ref
                                .read(capstoneDeliverablesProvider.notifier)
                                .unendorseTeam(
                                  parseAsInt(team['id']),
                                  selectedStage,
                                );
                          }
                        },
                  icon: const Icon(Icons.undo, size: 16),
                  label: const Text(
                    'Cancel Endorsement',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ] else if (activeTab == 1) ...[
          GradeDeliverableTab(
            team: team,
            selectedStage: selectedStage,
            isAdviser: widget.isAdviser,
            teamCriteriaScoreCtrls: _teamCriteriaScoreCtrls,
            teamStudentCriteriaScoreCtrls: _teamStudentCriteriaScoreCtrls,
            teamManualScoreCtrls: _teamManualScoreCtrls,
            teamSelectedRubrics: _teamSelectedRubrics,
          ),
        ] else if (activeTab == 3 && widget.isAdviser) ...[
          AdviserDefenseTab(
            teamId: teamId,
            selectedStage: selectedStage,
            projectVersion: int.tryParse('${team['project_version'] ?? ''}'),
            semesterId: int.tryParse('${team['semester_id'] ?? ''}'),
            adviserName: team['adviser_name']?.toString(),
          ),
        ] else if (activeTab == 3 && widget.isPitInstructor) ...[
          PitTeamScheduleTab(
            teamId: teamId,
            selectedStage: selectedStage,
            projectVersion: int.tryParse('${team['project_version'] ?? ''}'),
          ),
        ] else ...[
          SizedBox(
            height: 650,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: DefensysTokens.borderOf(context)),
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

  Widget _adviserTeamAction(int teamId, int tab, String label, IconData icon) => TextButton.icon(
    key: ValueKey('adviser-team-action-$teamId-$tab'),
    onPressed: () => setState(() {
      _selectedTeamId = teamId;
      _cardActiveTabs[teamId] = tab;
      _showMobileDetail = true;
    }),
    style: TextButton.styleFrom(
      foregroundColor: AdviserWorkflowReminder.colorOf(context, AdviserWorkflowTone.success, onLightSurface: true),
      padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 40),
      textStyle: const TextStyle(fontFamily: DefensysTokens.fontFamily, fontSize: 11, fontWeight: FontWeight.w600)),
    icon: Icon(icon, size: 14), label: Text(label),
  );

  Widget _buildCompactTeamCard(
    Map<String, dynamic> team,
    bool isSelected,
  ) {
    final teamId = parseAsInt(team['id']);
    final stages = _stageList(team);
    final cardSelectedStageLabel = _effectiveSelectedStage(team);
    final selectedStage = _stagePayload(stages, cardSelectedStageLabel);

    final gradingState = ref.watch(adviserGradingProvider);
    final gradeRecord = adviserGradeForTeam(team, cardSelectedStageLabel,
      gradingState.grades) ?? <String, dynamic>{};
    final gradingStatus = AdviserGradingStatus.fromGrade(gradeRecord,
      enabled: gradingState.adviserGradingEnabled, loading: gradingState.isLoading,
      error: gradingState.error, officiallyComplete: selectedStage['is_officially_complete'] == true);
    final minutesToSign = adviserMinutesToSign(team, cardSelectedStageLabel,
      ref.watch(teamDefenseProvider).schedules);
    final adviserScore = gradeRecord['adviser_score'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? DefensysTokens.maroonOf(context).withValues(alpha: 0.04) : DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? DefensysTokens.maroonOf(context) : DefensysTokens.borderOf(context),
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
              if (widget.initialTab != null) {
                _cardActiveTabs.putIfAbsent(teamId, () => widget.initialTab!);
              }
              _showMobileDetail = true;
            });
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: team['name']?.toString() ?? '',
                  child: Text(
                    team['name']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                TeamWorkflowBadge(
                  status: TeamWorkflowStatus.fromStage(selectedStage, scope: widget.state.scope),
                  compact: true,
                ),
                if (widget.isAdviser && (gradingStatus.needsGrade || minutesToSign.isNotEmpty)) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if (gradingStatus.needsGrade)
                      _adviserTeamAction(teamId, 1, 'Grade now', Icons.rate_review_outlined),
                    if (minutesToSign.isNotEmpty)
                      _adviserTeamAction(teamId, 3, 'Sign minutes', Icons.draw_outlined),
                  ]),
                ],
                if (adviserScore != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: DefensysTokens.surfaceHigherOf(context),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Adv: ${parseAsDouble(adviserScore)?.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: DefensysTokens.textPrimaryOf(context),
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
  }

  Widget _buildTeamListCompact(List<Map<String, dynamic>> teams) {
    if (teams.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 24, horizontal: 8),
        child: Center(
          child: Text(
            'No teams match this triage filter.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context)),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: teams.length,
      itemBuilder: (context, index) {
        final team = teams[index];
        final teamId = parseAsInt(team['id']);
        final isSelected = teamId == _selectedTeamId;
        return _buildCompactTeamCard(team, isSelected);
      },
    );
  }

  Widget _buildNoSelectionDetailPane() {
    return Container(
      decoration: cardDecoration(context),
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined, size: 48, color: DefensysTokens.textSecondaryOf(context)),
          SizedBox(height: 16),
          Text(
            'Select a Team',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Choose a team from the list on the left to view deliverables, grades, and team details.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: DefensysTokens.textSecondaryOf(context)),
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
            Icon(Icons.groups_outlined, color: DefensysTokens.maroonTextOf(context)),
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

  Widget _buildAvatarCluster(Map<String, dynamic> team, Map<String, dynamic>? gradeRecord) {
    final List<dynamic> members = (team['members'] as List?) ?? [];
    if (members.isEmpty) return const SizedBox.shrink();

    final visibleMembers = members.take(4).toList();
    final remainingCount = members.length - visibleMembers.length;

    return InkWell(
      onTap: () => _showRosterDetailsModal(context, team, gradeRecord),
      borderRadius: BorderRadius.circular(20),
      child: Tooltip(
        message: 'View Team Roster & Peer Scores (${members.length} members)',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: DefensysTokens.borderOf(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 24,
                width: (visibleMembers.length * 16.0) + 8.0,
                child: Stack(
                  children: visibleMembers.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final raw = entry.value;
                    final m = raw is Map ? raw : {};
                    final name = m['name']?.toString() ?? 'S';
                    final role = m['role']?.toString() ?? 'member';
                    final isLeader = role == 'leader';
                    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'S';

                    return Positioned(
                      left: idx * 16.0,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isLeader ? DefensysTokens.maroonOf(context) : const Color(0xFF64748B),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                remainingCount > 0 ? '+${remainingCount + visibleMembers.length}' : '${members.length} ${members.length == 1 ? "Member" : "Members"}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 14, color: DefensysTokens.textSecondaryOf(context)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadTeamGradeReport(int teamId, String teamName, int gradeId) async {
    final success = await ref.read(reportsProvider.notifier).downloadReport(
      endpoint: 'team-grade/$teamId/',
      queryParams: {'grade_id': gradeId.toString()},
      defaultFilename: 'DefenSYS_${teamName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}_Grade_Report.pdf',
    );
    if (!mounted) return;
    if (success) {
      showSuccessToast(context, 'Team grade report downloaded.');
    } else {
      showErrorToast(context, ref.read(reportsProvider).error ?? 'Unable to download the report.');
    }
  }

  String get _facultyWorkspace => widget.isAdviser ? 'adviser' : 'pit_instructor';

  Future<void> _downloadTeamSummary(int teamId, String stage) async {
    final success = await ref.read(reportsProvider.notifier).downloadReport(
      endpoint: 'faculty-team/$teamId/',
      queryParams: {'workspace': _facultyWorkspace, if (stage.isNotEmpty) 'stage': stage},
      defaultFilename: 'DefenSYS_Team_${teamId}_Summary.pdf',
    );
    if (!mounted) return;
    if (success) {
      showSuccessToast(context, 'Team summary downloaded.');
    } else {
      showErrorToast(context, ref.read(reportsProvider).error ?? 'Unable to download the team summary.');
    }
  }

  Widget _teamSummaryExportButton(int teamId, String stage) =>
      DefensysShadcnScope(
        child: ShadButton.outline(
          enabled: !ref.watch(reportsProvider).isLoading,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          onPressed: () => _downloadTeamSummary(teamId, stage),
          leading: const Icon(Icons.download_outlined, size: 15),
          child: Text(
            MediaQuery.sizeOf(context).width < 420
                ? 'Export summary'
                : 'Export team summary',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      );

  Widget _buildAdviserRoster(Map<String, dynamic> team, Map<String, dynamic> gradeRecord) {
    final members = (team['members'] as List? ?? []).whereType<Map>().toList();
    final gradeId = parseAsInt(gradeRecord['id']);
    final canDownloadReport = gradeId > 0 && gradeRecord['status'] == 'published';
    final reportLoading = ref.watch(reportsProvider).isLoading;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Team roster (${members.length})',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: DefensysTokens.textPrimaryOf(context))),
              if (canDownloadReport)
                OutlinedButton.icon(
                  onPressed: reportLoading ? null : () => _downloadTeamGradeReport(
                    parseAsInt(team['id']), team['name']?.toString() ?? 'Team', gradeId,
                  ),
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Download grade report'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (members.isEmpty)
            Text('No members assigned to this team.',
                style: TextStyle(color: DefensysTokens.textSecondaryOf(context)))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: members.map((member) {
                final name = member['name']?.toString() ?? member['username']?.toString() ?? 'Student';
                final isLeader = member['role'] == 'leader' || member['is_leader'] == true;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: isLeader ? AppColors.gold.withValues(alpha: 0.12) : DefensysTokens.surfaceOf(context),
                    border: Border.all(color: isLeader
                        ? AppColors.gold.withValues(alpha: 0.35) : DefensysTokens.borderOf(context)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLeader) ...[
                        const Icon(Icons.star_rounded, size: 14, color: AppColors.gold),
                        const SizedBox(width: 5),
                      ],
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (isLeader) ...[
                        const SizedBox(width: 5),
                        Text('· Leader', style: TextStyle(fontSize: 11, color: DefensysTokens.textSecondaryOf(context))),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
    );
  }

  Widget _buildConsolidatedTeamHeader({
    required BuildContext context,
    required Map<String, dynamic> team,
    required int teamId,
    required List<Map<String, dynamic>> stages,
    required String selectedStage,
    required Map<String, dynamic> stagePayload,
    required Map<String, dynamic>? gradeRecord,
    required String? currentStage,
  }) {
    final isPit = widget.state.scope == 'pit';
    final isFacultyHeader = widget.isAdviser || widget.isPitInstructor;
    final yearLevel = team['year_level']?.toString().trim() ?? '';
    final section = team['section']?.toString().trim() ?? '';
    final isPresentationOnly = stagePayload['is_presentation_only'] == true;
    final conceptConfig = (stagePayload['concept_workflow'] as Map?)?['config'] as Map?;
    final projectTitle = '${team['project_title'] ?? ''}'.trim().isNotEmpty
        ? '${team['project_title']}' : '${conceptConfig?['assigned_title'] ?? ''}';
    final materialReadiness = stagePayload['materials_readiness'];
    final materialsPending = materialReadiness is Map &&
        parseAsInt(materialReadiness['required_total']) >
            parseAsInt(materialReadiness['submitted_total']);
    final canEndorse = _canEndorseTeam(stagePayload) &&
        stagePayload['endorsed'] != true &&
        (!isPit || stagePayload['endorsement_required'] != false);
    final review = stagePayload['endorsement_review'];
    final reviewReason = review is Map ? review['reason']?.toString() ?? '' : '';
    final workflow = TeamWorkflowStatus.fromStage(stagePayload, scope: widget.state.scope);
    final workflowHint = workflow.code == 'on_hold' && reviewReason.isNotEmpty
        ? reviewReason : workflow.nextStep;
    final compactHeader = MediaQuery.sizeOf(context).width < 1200;

    return Container(
      key: widget.isAdviser
          ? const Key('adviser-team-summary')
          : widget.isPitInstructor
              ? const Key('instructor-team-summary')
              : null,
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceHigherOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            team['name']?.toString() ?? '',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                        ),
                        if (!isFacultyHeader &&
                            currentStage != null && currentStage.isNotEmpty &&
                            MediaQuery.sizeOf(context).width >= 420) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: ProgramColors.of(context, scope: widget.state.scope, data: team).accent.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: ProgramColors.of(context, scope: widget.state.scope, data: team).accent.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              isPit ? 'PIT: $currentStage' : currentStage,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: ProgramColors.of(context, scope: widget.state.scope, data: team).text,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (!isFacultyHeader) ...[
                      const SizedBox(height: 2),
                      Text(
                        team['project_title']?.toString() ?? 'No Project Title',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (!isFacultyHeader && team['adviser_name']?.toString().isNotEmpty == true) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: DefensysTokens.surfaceOf(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DefensysTokens.borderOf(context)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_outline, size: 14, color: DefensysTokens.textSecondaryOf(context)),
                      const SizedBox(width: 5),
                      Text(
                        'Adv: ${team['adviser_name']}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (!isFacultyHeader) _buildAvatarCluster(team, gradeRecord),
              if (isFacultyHeader && !compactHeader) ...[
                if (stages.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _buildStageStatusBadge(stagePayload),
                ],
                const SizedBox(width: 8),
                _teamSummaryExportButton(teamId, selectedStage),
              ],
            ],
          ),
          if (isFacultyHeader && compactHeader) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (stages.isNotEmpty) _buildStageStatusBadge(stagePayload),
                  _teamSummaryExportButton(teamId, selectedStage),
                ],
              ),
            ),
          ],
          if (isFacultyHeader) ...[
            const SizedBox(height: 12),
            Text(
              'Project title',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              projectTitle.trim().isEmpty ? 'Awaiting concept selection' : projectTitle,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            if (yearLevel.isNotEmpty || section.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  if (yearLevel.isNotEmpty)
                    Text('Year level: $yearLevel',
                        style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context))),
                  if (section.isNotEmpty)
                    Text('Section: $section',
                        style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context))),
                ],
              ),
            ],
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 12),
            _buildAdviserRoster(team, gradeRecord ?? const <String, dynamic>{}),
          ],
          if (!isFacultyHeader && stages.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: stages.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final item = entry.value;
                        final label = item['stage_label']?.toString() ?? 'Stage ${idx + 1}';
                        final isSelected = label == selectedStage;
                        final isCurrent = label == currentStage;
                        final isPassed = item['status'] == 'passed';
                        final isLast = idx == stages.length - 1;

                        Color pillBg = Colors.white;
                        Color pillBorder = const Color(0xFFE2E8F0);
                        Color pillText = DefensysTokens.textSecondaryOf(context);

                        if (isSelected) {
                          pillBg = DefensysTokens.maroonOf(context);
                          pillBorder = DefensysTokens.maroonOf(context);
                          pillText = Colors.white;
                        } else if (isPassed) {
                          pillBg = const Color(0xFFF0FDF4);
                          pillBorder = const Color(0xFFBBF7D0);
                          pillText = const Color(0xFF15803D);
                        } else if (isCurrent) {
                          pillBg = DefensysTokens.maroonOf(context).withValues(alpha: 0.05);
                          pillBorder = DefensysTokens.maroonOf(context).withValues(alpha: 0.3);
                          pillText = DefensysTokens.maroonOf(context);
                        }

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _cardSelectedStages[teamId] = label;
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: pillBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: pillBorder),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isPassed && !isSelected)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 5),
                                        child: Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF15803D)),
                                      )
                                    else
                                      Container(
                                        width: 16,
                                        height: 16,
                                        alignment: Alignment.center,
                                        margin: const EdgeInsets.only(right: 5),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSelected ? DefensysTokens.surfaceOf(context).withValues(alpha: 0.25) : const Color(0xFFE2E8F0),
                                        ),
                                        child: Text(
                                          '${idx + 1}',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected ? Colors.white : DefensysTokens.textSecondaryOf(context),
                                          ),
                                        ),
                                      ),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                        color: pillText,
                                      ),
                                    ),
                                    if (isCurrent && !isSelected) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: DefensysTokens.maroonOf(context),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: const Text(
                                          'CURRENT',
                                          style: TextStyle(
                                            fontSize: 7.5,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (!isLast)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.chevron_right, size: 14, color: Color(0xFFCBD5E1)),
                              ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (widget.state.scope == 'admin' && stagePayload['is_defense_done'] == true) ...[
                  OutlinedButton.icon(
                    onPressed: widget.state.isSaving
                        ? null
                        : () async {
                            await StageAccessManagementDialog.show(
                              context: context, ref: ref, scope: 'team', teamId: teamId,
                              teamName: team['name']?.toString(), availableStages: [selectedStage],
                            );
                          },
                    icon: Icon(
                      stagePayload['admin_unlocked'] == true
                          ? Icons.lock_outline
                          : Icons.lock_open_outlined,
                      size: 13,
                    ),
                    label: Text(
                      stagePayload['admin_unlocked'] == true ? 'Relock' : 'Unlock',
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: stagePayload['admin_unlocked'] == true
                          ? AppColors.danger
                          : DefensysTokens.maroonOf(context),
                      side: BorderSide(
                        color: stagePayload['admin_unlocked'] == true
                            ? AppColors.danger
                            : DefensysTokens.maroonOf(context),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final status = Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Stage status',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                    _buildStageStatusBadge(stagePayload),
                  ],
                );
                if (!widget.isPitInstructor) return status;
                final export = _teamSummaryExportButton(teamId, selectedStage);
                if (constraints.maxWidth < 520) {
                  return Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [status, export],
                  );
                }
                return Row(children: [status, const Spacer(), export]);
              },
            ),
            if (isPit &&
                stagePayload['deliverables_configured'] == true &&
                stagePayload['endorsed'] != true &&
                (stagePayload['endorsement_required'] == false ||
                    (stagePayload['required_complete'] == true && materialsPending))) ...[
              const SizedBox(height: 6),
              Text(
                stagePayload['endorsement_required'] == false
                    ? (materialsPending
                        ? 'No endorsement needed. This team can be scheduled now. Defense files may be uploaded later, before their scheduled deadline.'
                        : 'No endorsement needed. This team can be scheduled now.')
                    : 'Scheduling checks are clear. You may endorse this team now; defense files may be uploaded later, before their scheduled deadline.',
                style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context)),
              ),
            ],
          ],
          if (isFacultyHeader && stages.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final hint = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Next step',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        workflowHint,
                        style: TextStyle(
                          fontSize: 12,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  );
                  final showEndorseButton = (widget.isAdviser || widget.isPitInstructor) &&
                          stagePayload['endorsement_required'] != false &&
                          stagePayload['endorsed'] != true &&
                          stagePayload['has_active_schedule'] != true &&
                          stagePayload['has_done_schedule'] != true;
                  if (!showEndorseButton) return hint;
                  final button = _buildEndorseButton(
                    team,
                    selectedStage,
                    enabled: canEndorse,
                    isPresentationOnly: isPresentationOnly,
                  );
                  if (constraints.maxWidth < 560) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        hint,
                        const SizedBox(height: 8),
                        Align(alignment: Alignment.centerRight, child: button),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: hint),
                      const SizedBox(width: 12),
                      button,
                    ],
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkflowActionBanner(
    Map<String, dynamic> team,
    String selectedStage,
    Map<String, dynamic> stagePayload,
    Map<String, dynamic> gradeRecord,
  ) {
    if (widget.state.scope != 'capstone') return const SizedBox.shrink();

    final gradeData = gradeRecord.isNotEmpty
        ? gradeRecord
        : (stagePayload['grade'] is Map ? Map<String, dynamic>.from(stagePayload['grade'] as Map) : <String, dynamic>{});

    final verdict = gradeData['verdict']?.toString() ?? '';
    final workflow = gradeData['workflow'] is Map
        ? Map<String, dynamic>.from(gradeData['workflow'] as Map)
        : <String, dynamic>{};
    final previousProjects = (workflow['previous_projects'] as List? ?? []);

    final hasActiveWorkflow = verdict == 'for_redefense' ||
        verdict == 'approved_with_revisions' ||
        verdict == 'failed' ||
        verdict == 'project_rejected' ||
        previousProjects.isNotEmpty;

    if (!hasActiveWorkflow) return const SizedBox.shrink();

    final normalizedGrade = <String, dynamic>{
      ...gradeData,
      'scope': 'capstone',
      'id': gradeData['id'] ?? team['grade']?['id'] ?? stagePayload['grade_id'],
      'team_name': team['name']?.toString() ?? 'Team',
      'stage_label': selectedStage,
      'workflow': {
        ...workflow,
        if (workflow['adviser_id'] == null && team['adviser_id'] != null)
          'adviser_id': team['adviser_id'],
      },
    };

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: DefenseWorkflowPanel(
        grade: normalizedGrade,
        onUpdated: () {
          ref.read(capstoneDeliverablesProvider.notifier).fetchInitialData();
        },
        onProjectReplaced: () {
          ref.read(capstoneDeliverablesProvider.notifier).fetchInitialData();
        },
      ),
    );
  }

  Widget _buildTeamDetailPane(Map<String, dynamic> team) {
    final teamId = parseAsInt(team['id']);
    final gradingState = ref.watch(adviserGradingProvider);
    final cardSelectedStageLabel = _effectiveSelectedStage(team);
    final stages = _stageList(team);
    final selectedStage = _effectiveSelectedStage(team);
    final stagePayload = _stagePayload(stages, selectedStage);
    final currentStage = team['current_stage']?.toString();

    final gradeRecord = gradingState.grades.firstWhere(
      (g) => parseAsInt(g['team_id']) == teamId && g['stage_label']?.toString() == cardSelectedStageLabel,
      orElse: () {
        if (team['grade'] is Map && team['grade']['stage_label']?.toString() == cardSelectedStageLabel) {
          return Map<String, dynamic>.from(team['grade'] as Map);
        }
        if (stagePayload['grade'] is Map && stagePayload['grade']['stage_label']?.toString() == cardSelectedStageLabel) {
          return Map<String, dynamic>.from(stagePayload['grade'] as Map);
        }
        return <String, dynamic>{};
      },
    );

    return Container(
      decoration: cardDecoration(context),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildConsolidatedTeamHeader(
            context: context,
            team: team,
            teamId: teamId,
            stages: stages,
            selectedStage: selectedStage,
            stagePayload: stagePayload,
            gradeRecord: gradeRecord,
            currentStage: currentStage,
          ),
          _buildWorkflowActionBanner(team, selectedStage, stagePayload, gradeRecord),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFE2E8F0), height: 1),
          const SizedBox(height: 16),
          _buildExpandedSection(team),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    final filteredTeams = DeliverablesTriageHelper.reviewFirst(widget.state.teams
        .map((t) => Map<String, dynamic>.from(t))
        .where((t) => DeliverablesTriageHelper.matchesFilter(t, widget.activeTriageFilter)));
    final teamIds = filteredTeams.map((t) => parseAsInt(t['id'])).toList();
    if (_selectedTeamId == null || !teamIds.contains(_selectedTeamId)) {
      if (teamIds.isNotEmpty) {
        _selectedTeamId = teamIds.first;
      }
    }
    if (_selectedTeamId != null && widget.initialTab != null) {
      _cardActiveTabs.putIfAbsent(_selectedTeamId!, () => widget.initialTab!);
    }

    final selectedTeam = filteredTeams.firstWhere(
      (t) => parseAsInt(t['id']) == _selectedTeamId,
      orElse: () => <String, dynamic>{},
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 320,
          child: Container(
            decoration: cardDecoration(context),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.activeTriageFilter == TeamTriageFilter.needsReview
                              ? 'Teams (${filteredTeams.length}) - Review first'
                              : 'Teams (${filteredTeams.length})',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      ),
                      if (widget.isAdviser || widget.isPitInstructor)
                        FacultyTeamsOverviewExport(
                          teams: filteredTeams,
                          workspace: _facultyWorkspace,
                          selectedStage: widget.state.selectedStage,
                        ),
                    ],
                  ),
                ),
                _buildTeamListCompact(filteredTeams),
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
    final filteredTeams = DeliverablesTriageHelper.reviewFirst(widget.state.teams
        .map((t) => Map<String, dynamic>.from(t))
        .where((t) => DeliverablesTriageHelper.matchesFilter(t, widget.activeTriageFilter)));
    final selectedTeam = filteredTeams.firstWhere(
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
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.activeTriageFilter == TeamTriageFilter.needsReview
                      ? 'Teams (${filteredTeams.length}) - Review first'
                      : 'Teams (${filteredTeams.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ),
              if (widget.isAdviser || widget.isPitInstructor)
                FacultyTeamsOverviewExport(
                  teams: filteredTeams,
                  workspace: _facultyWorkspace,
                  selectedStage: widget.state.selectedStage,
                ),
            ],
          ),
        ),
        _buildTeamListCompact(filteredTeams),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state.teams.isEmpty) {
      return Container(
        decoration: cardDecoration(context),
        padding: const EdgeInsets.all(40),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.inbox, size: 48, color: DefensysTokens.textSecondaryOf(context)),
            SizedBox(height: 12),
            Text(
              'No teams match the current filters.',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: DefensysTokens.textSecondaryOf(context),
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
