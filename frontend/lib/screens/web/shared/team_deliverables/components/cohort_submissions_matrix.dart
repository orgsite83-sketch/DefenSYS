import 'package:defensys/widgets/repository/document_group.dart';
import 'package:defensys/widgets/repository/section_concept_workspace.dart';
import 'package:defensys/widgets/repository/proposal_title_summary.dart';
import 'package:defensys/widgets/repository/shared_concept_review.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/network/authenticated_client.dart';
import 'package:defensys/config/api_config.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/screens/web/shared/team_deliverables/deliverables_view_types.dart';
import 'package:defensys/utils/universal_file_viewer.dart';
import 'package:defensys/widgets/repository/defense_material_readiness.dart';
import 'package:defensys/models/team_workflow_status.dart';
import 'package:defensys/widgets/repository/workflow_status_style.dart';

int _asInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

class CohortSubmissionsMatrix extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> teams;
  final CapstoneDeliverablesState state;
  final bool isAdviser;
  final ValueChanged<int>? onSelectTeam;
  final int? initialExpandedTeamId;
  final GlobalKey<SectionConceptOverviewState> Function(int)? sharedReviewKey;
  final ValueChanged<int>? onOpenSharedReview;

  const CohortSubmissionsMatrix({
    super.key,
    required this.teams,
    required this.state,
    required this.isAdviser,
    this.onSelectTeam,
    this.initialExpandedTeamId,
    this.sharedReviewKey,
    this.onOpenSharedReview,
  });

  @override
  ConsumerState<CohortSubmissionsMatrix> createState() => _CohortSubmissionsMatrixState();
}

class _CohortSubmissionsMatrixState extends ConsumerState<CohortSubmissionsMatrix> {

  late final Set<int> _expandedTeamIds;
  bool _isSendingBulkReminder = false;
  final Set<int> _remindingTeamIds = {};

  @override
  void initState() {
    super.initState();
    _expandedTeamIds = {};
    if (widget.initialExpandedTeamId != null) {
      _expandedTeamIds.add(widget.initialExpandedTeamId!);
    }
  }

  @override
  void didUpdateWidget(covariant CohortSubmissionsMatrix oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialExpandedTeamId != null &&
        widget.initialExpandedTeamId != oldWidget.initialExpandedTeamId) {
      _expandedTeamIds.add(widget.initialExpandedTeamId!);
    }
  }

  void _toggleExpanded(int teamId) {
    setState(() {
      if (_expandedTeamIds.contains(teamId)) {
        _expandedTeamIds.remove(teamId);
      } else {
        _expandedTeamIds.add(teamId);
      }
    });
  }

  IconData _getFileIcon(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return LucideIcons.fileText;
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp')) {
      return LucideIcons.image;
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mkv')) {
      return LucideIcons.video;
    }
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) return LucideIcons.presentation;
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return LucideIcons.fileText;
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx') || lower.endsWith('.csv')) {
      return LucideIcons.fileSpreadsheet;
    }
    if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z')) {
      return LucideIcons.fileArchive;
    }
    return LucideIcons.file;
  }

  Color _getFileIconColor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return const Color(0xFFDC2626);
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) return const Color(0xFFEA580C);
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return const Color(0xFF2563EB);
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx') || lower.endsWith('.csv')) {
      return const Color(0xFF16A34A);
    }
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return const Color(0xFF7C3AED);
    }
    return const Color(0xFF64748B);
  }

  // Calculate deliverable completion stats truthfully
  Map<String, dynamic> _computeDeliverablesStats(Map<String, dynamic>? activeStage) {
    if (activeStage == null) {
      return {'cleared': 0, 'pending': 0, 'missing': 0, 'total': 0, 'isAllCleared': false};
    }

    final allItems = DeliverablesTriageHelper.items(activeStage);
    final requiredPreItems = allItems.where((d) =>
        d['type'] != 'post' &&
        d['deliverable_type'] != 'post' &&
        d['requirement_timing'] != 'defense' &&
        d['required'] == true &&
        d['is_waived'] != true).toList();

    int cleared = 0;
    int pending = 0;
    int missing = 0;

    for (final item in requiredPreItems) {
      final sub = item['submission'] as Map?;
      final status = (sub?['status'] ?? item['submission_status'] ?? item['status'])?.toString().toLowerCase();
      final isUploaded = item['uploaded'] == true || sub != null;

      if (status == 'accepted' || status == 'approved' || status == 'cleared' || status == 'passed') {
        cleared++;
      } else if (isUploaded && (status == 'rejected' || status == 'needs revision')) {
        missing++;
      } else if (isUploaded) {
        pending++;
      } else {
        missing++;
      }
    }

    final backendTotal = _asInt(activeStage['required_total']);
    final total = requiredPreItems.isNotEmpty ? requiredPreItems.length : backendTotal;
    final isAllCleared = total > 0 && cleared >= total;

    return {
      'cleared': cleared,
      'pending': pending,
      'missing': missing,
      'total': total,
      'isAllCleared': isAllCleared,
    };
  }

  bool _teamLacksDeliverables(Map<String, dynamic> team) {
    final activeStage = DeliverablesTriageHelper.resolveActiveStage(team);
    if (activeStage?['is_presentation_only'] == true) return false;
    final stats = _computeDeliverablesStats(activeStage);
    if (stats['isAllCleared'] == true) return false;
    return (stats['missing'] as int) > 0 || (stats['pending'] as int) > 0 || DeliverablesTriageHelper.isOverdueOrMissing(team);
  }

  Future<void> _sendTeamReminder(BuildContext context, Map<String, dynamic> team, String stageLabel) async {
    final teamId = _asInt(team['id']);
    final teamName = team['name']?.toString() ?? 'Team';
    final isPit = widget.state.scope == 'pit' || team['is_pit'] == true;

    setState(() => _remindingTeamIds.add(teamId));
    try {
      final client = ref.read(authenticatedHttpClientProvider);
      final url = '${ApiConfig.teamsUrl}/$teamId/remind/';
      final response = await client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'stage_label': stageLabel}),
      );

      if (response.statusCode == 200) {
        if (context.mounted) {
          showSuccessToast(
            context,
            isPit
                ? 'Reminder successfully sent to $teamName and instructor.'
                : 'Reminder successfully sent to $teamName and adviser.',
          );
        }
      } else {
        if (context.mounted) {
          showErrorToast(context, 'Failed to send reminder to $teamName.');
        }
      }
    } catch (e) {
      if (context.mounted) {
        showErrorToast(context, 'Connection error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _remindingTeamIds.remove(teamId));
      }
    }
  }

  Future<void> _sendBulkReminders(BuildContext context, List<Map<String, dynamic>> lackingTeams) async {
    final isPit = widget.state.scope == 'pit' || lackingTeams.any((t) => t['is_pit'] == true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.notifications_active_outlined, color: Color(0xFFD97706), size: 20),
            const SizedBox(width: 8),
            Text('Remind All ${lackingTeams.length} Teams?'),
          ],
        ),
        content: Text(
          isPit
              ? 'This will notify student leaders, members, and instructors across all ${lackingTeams.length} teams with incomplete or pending stage deliverables.'
              : 'This will notify student leaders, members, and advisers across all ${lackingTeams.length} teams with incomplete or pending stage deliverables.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded, size: 14),
            label: const Text('Send Notifications'),
            style: ElevatedButton.styleFrom(
              backgroundColor: DefensysTokens.maroonOf(context),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSendingBulkReminder = true);
    int successCount = 0;
    try {
      final client = ref.read(authenticatedHttpClientProvider);
      for (final team in lackingTeams) {
        final teamId = _asInt(team['id']);
        final activeStage = DeliverablesTriageHelper.resolveActiveStage(team);
        final stageLabel = activeStage?['stage_label']?.toString() ??
            team['current_stage']?.toString() ??
            '';
        if (stageLabel.isEmpty) continue;

        try {
          final res = await client.post(
            Uri.parse('${ApiConfig.teamsUrl}/$teamId/remind/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'stage_label': stageLabel}),
          );
          if (res.statusCode == 200) successCount++;
        } catch (_) {}
      }

      if (context.mounted) {
        showSuccessToast(context, 'Reminders successfully delivered to $successCount teams.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingBulkReminder = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPit = widget.state.scope == 'pit' || widget.teams.any((t) => t['is_pit'] == true);

    if (widget.teams.isEmpty) {
      return DefensysShadcnScope(
        child: Container(
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
            border: Border.all(color: DefensysTokens.borderOf(context)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.searchX, size: 40, color: DefensysTokens.textSecondaryOf(context)),
              SizedBox(height: 14),
              Text(
                'No teams match the selected filter.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Try changing your search term or switching the triage filter above.',
                style: TextStyle(fontSize: 12.5, color: DefensysTokens.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final lackingTeams = widget.teams.where(_teamLacksDeliverables).toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final team in widget.teams) {
      final shared = sharedReviewForTeam(team, stageLabel: widget.state.selectedStage);
      final group = shared == null
          ? '${team['semester_id']}:${team['year_level']}:${team['section']}'
          : 'shared:${shared['project_id']}';
      groups.putIfAbsent(group, () => []).add(team);
    }
    final rows = <Map<String, dynamic>>[];
    for (final teams in groups.values) {
      final shared = sharedReviewForTeam(teams.first, stageLabel: widget.state.selectedStage);
      if (shared != null) rows.add({'review': shared});
      rows.addAll(teams.map((team) => {'team': team}));
    }

    return DefensysShadcnScope(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final isNarrow = screenWidth < 900;
          final tableWidth = isNarrow ? 900.0 : screenWidth;

          final tableContent = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Shadcn Toolbar Bar with Bulk Reminder Button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: DefensysTokens.surfaceOf(context),
                  border: Border(bottom: BorderSide(color: DefensysTokens.borderOf(context))),
                ),
                child: Row(
                  children: [
                    Text(
                      '${widget.teams.length} ${widget.teams.length == 1 ? 'Team' : 'Teams'} in Cohort',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: DefensysTokens.textPrimaryOf(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    if (lackingTeams.isNotEmpty)
                      ShadButton(
                        size: ShadButtonSize.sm,
                        height: 32,
                        backgroundColor: const Color(0xFFD97706),
                        hoverBackgroundColor: const Color(0xFFB45309),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        leading: _isSendingBulkReminder
                            ? const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.notifications_active_outlined, size: 14),
                        onPressed: _isSendingBulkReminder
                            ? null
                            : () => _sendBulkReminders(context, lackingTeams),
                        child: Text(
                          'Remind All Lacking Teams (${lackingTeams.length})',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
              // Shadcn Table Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: DefensysTokens.surfaceHigherOf(context),
                  border: Border(bottom: BorderSide(color: DefensysTokens.borderOf(context))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        'TEAM & PROJECT',
                        style: DefensysTokens.tableHeader,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'CURRENT STAGE',
                        style: DefensysTokens.tableHeader,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'STAGE DELIVERABLES',
                        style: DefensysTokens.tableHeader,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        isPit ? 'INSTRUCTOR' : 'ADVISER',
                        style: DefensysTokens.tableHeader,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'STATUS',
                        style: DefensysTokens.tableHeader,
                      ),
                    ),
                    SizedBox(
                      width: 170,
                      child: Text(
                        'ACTIONS',
                        textAlign: TextAlign.end,
                        style: DefensysTokens.tableHeader,
                      ),
                    ),
                  ],
                ),
              ),
              // Rows with Inline Accordion
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rows.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: DefensysTokens.borderOf(context)),
                itemBuilder: (context, index) {
                  if (rows[index]['review'] is Map) {
                    final review = Map<String, dynamic>.from(rows[index]['review']);
                    final projectId = review['project_id'] as int;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: screenWidth,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SectionConceptOverview(
                            key: widget.sharedReviewKey?.call(projectId) ?? ValueKey('matrix-shared-$projectId'),
                            projectId: projectId,
                            section: '${review['section']}',
                            stageLabel: '${review['stage_label']}',
                            systems: (review['systems'] as List? ?? []).whereType<Map>().map((s) => Map<String, dynamic>.from(s)).toList(),
                            summary: review,
                            collapsible: true,
                            onChanged: () => ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(),
                          ),
                        ),
                      ),
                    );
                  }
                  final team = Map<String, dynamic>.from(rows[index]['team']);
                  final teamId = _asInt(team['id']);
                  final name = team['name']?.toString() ?? 'Team';
                  final projectTitle = team['project_title']?.toString() ?? 'No Project Title';
                  final currentStage = team['current_stage']?.toString() ?? 'Concept Proposal';
                  final rawInstructor = (team['instructor_name'] ?? team['adviser_name'])?.toString().trim() ?? '';
                  final instructorDisplay = isPit
                      ? (rawInstructor.isEmpty || rawInstructor == 'Unassigned'
                          ? 'Unassigned Instructor'
                          : rawInstructor)
                      : (rawInstructor.isEmpty ? 'Unassigned' : rawInstructor);

                  final activeStage = DeliverablesTriageHelper.resolveActiveStage(team);
                  final stats = _computeDeliverablesStats(activeStage);
                  final clearedCount = stats['cleared'] as int;
                  final pendingCount = stats['pending'] as int;
                  final missingCount = stats['missing'] as int;
                  final totalRequired = stats['total'] as int;
                  final isAllCleared = stats['isAllCleared'] as bool;

                  final isPresentationOnly = activeStage?['is_presentation_only'] == true;
                  final hasPending = pendingCount > 0 || DeliverablesTriageHelper.hasPendingReview(team);

                  // Accurate Progress Value & Color calculation (truthful amber for pending review)
                  double progressValue;
                  Color progressBarColor;
                  String deliverableProgressLabel;

                  if (isPresentationOnly) {
                    progressValue = 1.0;
                    progressBarColor = WorkflowStatusStyle.of(context, WorkflowStatusTone.active).foreground;
                    deliverableProgressLabel = 'Oral Pitching & Demo';
                  } else if (isAllCleared) {
                    progressValue = 1.0;
                    progressBarColor = const Color(0xFF10B981);
                    deliverableProgressLabel = '$clearedCount / $totalRequired Cleared';
                  } else if (hasPending) {
                    progressBarColor = const Color(0xFFF59E0B);
                    progressValue = totalRequired > 0
                        ? ((clearedCount + (pendingCount * 0.5)) / totalRequired).clamp(0.1, 0.95)
                        : 0.5;
                    deliverableProgressLabel = clearedCount > 0
                        ? '$clearedCount cleared · $pendingCount pending review'
                        : '$pendingCount submitted · Pending review';
                  } else {
                    progressBarColor = clearedCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8);
                    progressValue = totalRequired > 0
                        ? (clearedCount / totalRequired).clamp(0.0, 1.0)
                        : 0.0;
                    deliverableProgressLabel = '$clearedCount / $totalRequired Cleared${missingCount > 0 ? ' · $missingCount missing' : ''}';
                  }

                  final isExpanded = _expandedTeamIds.contains(teamId);
                  final lacksDeliverables = _teamLacksDeliverables(team);
                  final isRemindingThis = _remindingTeamIds.contains(teamId);

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Material(
                        color: isExpanded ? DefensysTokens.surfaceHigherOf(context) : DefensysTokens.surfaceOf(context),
                        child: InkWell(
                          onTap: () {
                            _toggleExpanded(teamId);
                            widget.onSelectTeam?.call(teamId);
                          },
                          hoverColor: DefensysTokens.surfaceHigherOf(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                            child: Row(
                              children: [
                                // Team & Project
                                Expanded(
                                  flex: 4,
                                  child: Row(
                                    children: [
                                      Icon(
                                        isExpanded
                                            ? LucideIcons.chevronDown
                                            : LucideIcons.chevronRight,
                                        size: 16,
                                        color: isExpanded ? DefensysTokens.maroonTextOf(context) : DefensysTokens.textSecondaryOf(context),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                                color: DefensysTokens.textPrimaryOf(context),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            if (hasOpenConceptProposals(activeStage?['concept_workflow'] as Map?))
                                              ProposalTitleSummary(
                                                rows: conceptRows((activeStage!['concept_workflow'] as Map)['concepts']),
                                                collapsible: true,
                                              )
                                            else Text(
                                              projectTitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: DefensysTokens.textSecondaryOf(context),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Current Stage (ShadBadge)
                                Expanded(
                                  flex: 2,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: ShadBadge.secondary(
                                      backgroundColor: DefensysTokens.surfaceHigherOf(context),
                                      foregroundColor: DefensysTokens.textSecondaryOf(context),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        side: BorderSide(color: DefensysTokens.borderOf(context)),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                      child: Text(
                                        currentStage,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Stage Deliverables Progress (truthful colors & counts)
                                Expanded(
                                  flex: 3,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                deliverableProgressLabel,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: isAllCleared
                                                      ? const Color(0xFF047857)
                                                      : (hasPending
                                                          ? const Color(0xFFB45309)
                                                          : DefensysTokens.textPrimaryOf(context)),
                                                ),
                                              ),
                                            ),
                                            if (hasPending) ...[
                                              const SizedBox(width: 4),
                                              ShadBadge.secondary(
                                                backgroundColor: const Color(0xFFFEF3C7),
                                                foregroundColor: const Color(0xFFB45309),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(4),
                                                  side: const BorderSide(color: Color(0xFFFDE68A)),
                                                ),
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                child: const Text(
                                                  'Pending',
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(999),
                                          child: LinearProgressIndicator(
                                            value: progressValue,
                                            minHeight: 4.5,
                                            backgroundColor: DefensysTokens.surfaceHigherOf(context),
                                            valueColor: AlwaysStoppedAnimation<Color>(progressBarColor),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Adviser / Instructor
                                Expanded(
                                  flex: 2,
                                  child: Row(
                                    children: [
                                      Icon(
                                        isPit ? Icons.school_outlined : Icons.person_outline,
                                        size: 14,
                                        color: DefensysTokens.textSecondaryOf(context),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          instructorDisplay,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: DefensysTokens.textPrimaryOf(context),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Status Pill (ShadBadge.outline)
                                Expanded(
                                  flex: 2,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _buildStatusPill(activeStage ?? {}),
                                  ),
                                ),
                                // Actions: Remind + Review/Hide Button
                                SizedBox(
                                  width: 170,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (lacksDeliverables) ...[
                                        Tooltip(
                                          message: isPit
                                              ? 'Send reminder to student team & instructor'
                                              : 'Send reminder to student team & adviser',
                                          child: ShadButton.ghost(
                                            size: ShadButtonSize.sm,
                                            width: 32,
                                            height: 32,
                                            padding: EdgeInsets.zero,
                                            leading: isRemindingThis
                                                ? const SizedBox(
                                                    width: 13,
                                                    height: 13,
                                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD97706)),
                                                  )
                                                : const Icon(
                                                    Icons.notifications_active_outlined,
                                                    size: 15,
                                                    color: Color(0xFFD97706),
                                                  ),
                                            onPressed: isRemindingThis
                                                ? null
                                                : () => _sendTeamReminder(context, team, currentStage),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      isExpanded
                                          ? ShadButton.outline(
                                              size: ShadButtonSize.sm,
                                              height: 32,
                                              padding: const EdgeInsets.symmetric(horizontal: 10),
                                              leading: const Icon(LucideIcons.chevronUp, size: 14),
                                              onPressed: () => _toggleExpanded(teamId),
                                              child: const Text('Hide'),
                                            )
                                          : ShadButton(
                                              size: ShadButtonSize.sm,
                                              height: 32,
                                              backgroundColor: DefensysTokens.maroonOf(context),
                                              hoverBackgroundColor: DefensysTokens.maroonDark,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 12),
                                              leading: const Icon(LucideIcons.eye, size: 14),
                                              onPressed: () {
                                                _toggleExpanded(teamId);
                                                widget.onSelectTeam?.call(teamId);
                                              },
                                              child: const Text('Review'),
                                            ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Expanded Deliverables Accordion Panel
                      if (isExpanded)
                        _buildExpandedDeliverablesPanel(context, team, activeStage ?? {}, isPit),
                    ],
                  );
                },
              ),
            ],
          );

          return Container(
            decoration: BoxDecoration(
              color: DefensysTokens.surfaceOf(context),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
              border: Border.all(color: DefensysTokens.borderOf(context)),
            ),
            clipBehavior: Clip.antiAlias,
            child: isNarrow
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: tableContent,
                    ),
                  )
                : tableContent,
          );
        },
      ),
    );
  }

  Widget _buildExpandedDeliverablesPanel(
    BuildContext context,
    Map<String, dynamic> team,
    Map<String, dynamic> activeStage,
    bool isPit,
  ) {
    final teamId = _asInt(team['id']);
    final name = team['name']?.toString() ?? 'Team';
    final projectTitle = team['project_title']?.toString() ?? '';
    final currentStage = activeStage['stage_label']?.toString() ??
        team['current_stage']?.toString() ??
        'Stage';
    final isPresentationOnly = activeStage['is_presentation_only'] == true;

    final stats = _computeDeliverablesStats(activeStage);
    final clearedCount = stats['cleared'] as int;
    final pendingCount = stats['pending'] as int;
    final missingCount = stats['missing'] as int;
    final totalRequired = stats['total'] as int;
    final isAllCleared = stats['isAllCleared'] as bool;
    final hasPending = pendingCount > 0 || DeliverablesTriageHelper.hasPendingReview(team);
    final isMissing = missingCount > 0 || DeliverablesTriageHelper.isOverdueOrMissing(team);

    final materialsReadiness = activeStage['materials_readiness'];

    // Resolve pre, post, and deliverables collections
    final preList = (activeStage['pre'] as List?)
            ?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        [];
    final postList = (activeStage['post'] as List?)
            ?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        [];
    final rawDeliverables = (activeStage['deliverables'] as List?)
            ?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        [];

    List<Map<String, dynamic>> allPre = [];
    List<Map<String, dynamic>> allPost = [];

    if (preList.isNotEmpty || postList.isNotEmpty) {
      allPre = preList;
      allPost = postList;
    } else {
      for (final d in rawDeliverables) {
        if (d['type'] == 'post' || d['deliverable_type'] == 'post') {
          allPost.add(d);
        } else {
          allPre.add(d);
        }
      }
    }

    final beforeEndorsement =
        allPre.where((d) => d['requirement_timing'] != 'defense').toList();
    final beforeDefense =
        allPre.where((d) => d['requirement_timing'] == 'defense').toList();

    final lacksDeliverables = _teamLacksDeliverables(team);
    final isRemindingThis = _remindingTeamIds.contains(teamId);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceHigherOf(context),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: DefensysTokens.surfaceOf(context),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: DefensysTokens.borderOf(context))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: DefensysTokens.maroonOf(context).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(LucideIcons.folder, size: 16, color: DefensysTokens.maroonTextOf(context)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            '$name · $currentStage Deliverables',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                          ShadBadge.outline(
                            backgroundColor: isPresentationOnly
                                ? const Color(0xFFEEF2FF)
                                : (isAllCleared
                                    ? const Color(0xFFECFDF5)
                                    : (hasPending
                                        ? const Color(0xFFFFFBEB)
                                        : (isMissing
                                            ? const Color(0xFFFEF2F2)
                                            : const Color(0xFFF8FAFC)))),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                              side: BorderSide(
                                color: isPresentationOnly
                                    ? const Color(0xFFC7D2FE)
                                    : (isAllCleared
                                        ? const Color(0xFFA7F3D0)
                                        : (hasPending
                                            ? const Color(0xFFFDE68A)
                                            : (isMissing
                                                ? const Color(0xFFFECACA)
                                                : const Color(0xFFE2E8F0)))),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            child: Text(
                              isPresentationOnly
                                  ? 'Oral Presentation Stage'
                                  : (isAllCleared
                                      ? '$clearedCount / $totalRequired Cleared'
                                      : (hasPending
                                          ? '$pendingCount Pending Review'
                                          : '$clearedCount / $totalRequired Cleared · $missingCount Missing')),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: isPresentationOnly
                                    ? const Color(0xFF4338CA)
                                    : (isAllCleared
                                        ? const Color(0xFF047857)
                                        : (hasPending
                                            ? const Color(0xFFB45309)
                                            : (isMissing
                                                ? const Color(0xFFB91C1C)
                                                : const Color(0xFF475569)))),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (hasOpenConceptProposals(activeStage['concept_workflow'] as Map?)) ...[
                        const SizedBox(height: 2),
                        Text('Concept selection · ${conceptRows((activeStage['concept_workflow'] as Map)['concepts']).length} required proposals',
                          style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context))),
                      ] else if (projectTitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          projectTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: DefensysTokens.textSecondaryOf(context)),
                        ),
                      ],
                    ],
                  ),
                ),
                // Remind Team Button
                if (lacksDeliverables) ...[
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    height: 30,
                    foregroundColor: const Color(0xFFD97706),
                    backgroundColor: const Color(0xFFFFFBEB),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    leading: isRemindingThis
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD97706)),
                          )
                        : const Icon(Icons.notifications_active_outlined, size: 13, color: Color(0xFFD97706)),
                    onPressed: isRemindingThis
                        ? null
                        : () => _sendTeamReminder(context, team, currentStage),
                    child: const Text('Remind Team', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                ],
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  width: 28,
                  height: 28,
                  padding: EdgeInsets.zero,
                  leading: Icon(LucideIcons.x, size: 16, color: DefensysTokens.textSecondaryOf(context)),
                  onPressed: () => _toggleExpanded(teamId),
                ),
              ],
            ),
          ),
          // Content Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Defense Materials Readiness Notice (if present)
                if ((activeStage['concept_workflow'] as Map?)?['section_project_id'] != null)
                  SharedSectionStatus(
                    summary: Map<String, dynamic>.from((activeStage['concept_workflow'] as Map)['shared_review'] as Map? ?? {}),
                    onOpen: () {
                      final id = _asInt((activeStage['concept_workflow'] as Map)['section_project_id']);
                      if (widget.onOpenSharedReview != null) {
                        widget.onOpenSharedReview!(id);
                      } else {
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SectionConceptWorkspace(projectId: id)));
                      }
                    },
                  ),
                if (materialsReadiness is Map && materialsReadiness.isNotEmpty) ...[
                  DefenseMaterialReadiness(
                    readiness: Map<String, dynamic>.from(materialsReadiness),
                    compact: false,
                  ),
                  const SizedBox(height: 14),
                ],

                // Presentation Only Stage Notice
                if (isPresentationOnly)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFC7D2FE)),
                    ),
                    child: const Row(
                      children: [
                        Icon(LucideIcons.presentation, color: Color(0xFF4338CA), size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This stage is designated for oral pitching and live demonstration. No document uploads or file submissions are required for teams.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF3730A3),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  // Section 1: Before Endorsement / Clearance Requirements
                  if (beforeEndorsement.isNotEmpty) ...[
                    _buildSectionHeader(
                      icon: LucideIcons.fileCheck,
                      title: isPit ? 'Before Clearance Requirements' : 'Before Endorsement Requirements',
                      subtitle: isPit
                          ? 'Files required to be cleared before instructor endorses/clears this team.'
                          : 'Files required to be cleared before the adviser can endorse this team.',
                    ),
                    const SizedBox(height: 8),
                    ...beforeEndorsement.map((d) => _buildDeliverableItemCard(context, d, currentStage, isPit, teamId)),
                    const SizedBox(height: 14),
                  ],

                  // Section 2: Before Defense Materials
                  if (beforeDefense.isNotEmpty) ...[
                    _buildSectionHeader(
                      icon: LucideIcons.presentation,
                      title: 'Before Defense Materials',
                      subtitle: 'Presentation slides and demonstration materials required for panel review.',
                    ),
                    const SizedBox(height: 8),
                    ...beforeDefense.map((d) => _buildDeliverableItemCard(context, d, currentStage, isPit, teamId)),
                    const SizedBox(height: 14),
                  ],

                  // Section 3: Post-Defense Archive & Vault
                  if (allPost.isNotEmpty) ...[
                    _buildSectionHeader(
                      icon: LucideIcons.archive,
                      title: 'Post-Defense Archive Requirements',
                      subtitle: 'Final manuscripts, compliance forms, and project archives.',
                    ),
                    const SizedBox(height: 8),
                    ...allPost.map((d) => _buildDeliverableItemCard(context, d, currentStage, isPit, teamId)),
                  ],

                  // Empty State if no deliverables configured
                  if (beforeEndorsement.isEmpty && beforeDefense.isEmpty && allPost.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: DefensysTokens.surfaceOf(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: DefensysTokens.borderOf(context)),
                      ),
                      child: Text(
                        'No deliverables configured for $currentStage.',
                        style: TextStyle(fontSize: 12.5, color: DefensysTokens.textSecondaryOf(context)),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 15, color: DefensysTokens.textSecondaryOf(context)),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: DefensysTokens.textSecondaryOf(context)),
          ),
        ),
      ],
    );
  }

  Widget _buildDeliverableItemCard(
    BuildContext context,
    Map<String, dynamic> item,
    String stageLabel,
    bool isPit,
    int teamId,
  ) {
    if ((item['file_policy'] as Map? ?? {}).isNotEmpty) return DocumentGroup(teamId: teamId, stageLabel: stageLabel, item: item);
    final label = item['label']?.toString() ??
        item['title']?.toString() ??
        item['name']?.toString() ??
        'Deliverable';
    final isRequired = item['required'] == true;
    final isWaived = item['is_waived'] == true;
    final desc = item['description']?.toString() ?? '';
    final submission = item['submission'] is Map
        ? Map<String, dynamic>.from(item['submission'] as Map)
        : null;
    final subStatus = (submission?['status'] ?? item['submission_status'] ?? item['status'])
        ?.toString()
        .toLowerCase();
    final uploaded = item['uploaded'] == true || submission != null;
    final isLate = submission?['is_late'] == true || item['is_late'] == true;
    final feedback = submission?['feedback']?.toString() ?? '';
    final timing = item['requirement_timing']?.toString();
    final isDefense = timing == 'defense';

    final isAccepted = subStatus == 'accepted' ||
        subStatus == 'approved' ||
        subStatus == 'passed' ||
        subStatus == 'cleared';
    final isRejected = subStatus == 'rejected' || subStatus == 'needs revision';
    final isPending = uploaded && !isAccepted && !isRejected && !isDefense;
    final isMissing = !uploaded && isRequired && !isWaived;

    // Build files list
    final filesList = (submission?['files'] as List?)
            ?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        [];
    if (filesList.isEmpty && submission != null) {
      final url = submission['file_url']?.toString();
      if (url != null && url.isNotEmpty) {
        filesList.add({
          'file_name': submission['file_name']?.toString() ?? 'document.pdf',
          'file_url': url,
          'file_size': submission['file_size']?.toString() ?? '',
        });
      }
    }

    final uploaderName = submission?['submitted_by_name']?.toString() ??
        submission?['uploader_name']?.toString();
    final submittedAt = submission?['submitted_at']?.toString();

    // Determine leading icon and status border
    final fileStyle = WorkflowStatusStyle.of(context,
      isWaived ? WorkflowStatusTone.neutral
        : isRejected ? WorkflowStatusTone.attention
        : isAccepted || isDefense && uploaded ? WorkflowStatusTone.success
        : isPending ? WorkflowStatusTone.active : WorkflowStatusTone.neutral);
    final cardBorder = fileStyle.border;
    IconData leadingIcon = LucideIcons.circle;
    final leadingColor = fileStyle.foreground;

    if (isWaived) {
      leadingIcon = LucideIcons.minusCircle;
    } else if (isAccepted) {
      leadingIcon = LucideIcons.checkCircle2;
    } else if (isRejected) {
      leadingIcon = LucideIcons.circleAlert;
    } else if (isPending) {
      leadingIcon = LucideIcons.clock;
    } else if (isMissing) {
      leadingIcon = LucideIcons.circleAlert;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(leadingIcon, size: 18, color: leadingColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row: Title, chips, and right-aligned status badge
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: uploaded ? DefensysTokens.textPrimary : DefensysTokens.textPrimaryOf(context),
                                ),
                              ),
                              if (isRequired)
                                ShadBadge.secondary(
                                  backgroundColor: const Color(0xFFFEE2E2),
                                  foregroundColor: const Color(0xFFB91C1C),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  child: const Text(
                                    'REQUIRED',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                )
                              else
                                ShadBadge.secondary(
                                  backgroundColor: DefensysTokens.surfaceHigherOf(context),
                                  foregroundColor: DefensysTokens.textSecondaryOf(context),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  child: const Text(
                                    'OPTIONAL',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              if (timing == 'defense')
                                ShadBadge.secondary(
                                  backgroundColor: const Color(0xFFDBEAFE),
                                  foregroundColor: const Color(0xFF1D4ED8),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  child: const Text(
                                    'BEFORE DEFENSE',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              if (isLate)
                                ShadBadge.secondary(
                                  backgroundColor: const Color(0xFFFEF3C7),
                                  foregroundColor: const Color(0xFFB45309),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  child: const Text(
                                    'LATE SUBMISSION',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              if (isWaived)
                                ShadBadge.secondary(
                                  backgroundColor: DefensysTokens.surfaceHigherOf(context),
                                  foregroundColor: DefensysTokens.textSecondaryOf(context),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  child: const Text(
                                    'WAIVED',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildDeliverableStatusBadge(
                          isDefenseUploaded: isDefense && uploaded && !isRejected,
                          isAccepted: isAccepted,
                          isPending: isPending,
                          isRejected: isRejected,
                          isMissing: isMissing,
                          isWaived: isWaived,
                        ),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        desc,
                        style: TextStyle(fontSize: 11, color: DefensysTokens.textSecondaryOf(context)),
                      ),
                    ],
                    // Upload / File info with flexible fit
                    const SizedBox(height: 6),
                    if (filesList.isNotEmpty) ...[
                      ...filesList.map((fileMap) {
                        final fileName = fileMap['file_name']?.toString() ?? 'document.pdf';
                        final fileUrl = fileMap['file_url']?.toString() ?? '';
                        final fileSize = fileMap['file_size']?.toString() ?? '';

                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: DefensysTokens.surfaceHigherOf(context),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: DefensysTokens.borderOf(context)),
                            ),
                            child: Row(
                              children: [
                                Icon(_getFileIcon(fileName), size: 15, color: _getFileIconColor(fileName)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: DefensysTokens.textPrimaryOf(context),
                                    ),
                                  ),
                                ),
                                if (fileSize.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    fileSize,
                                    style: TextStyle(fontSize: 10, color: DefensysTokens.textSecondaryOf(context)),
                                  ),
                                ],
                                const SizedBox(width: 10),
                                ShadButton.outline(
                                  size: ShadButtonSize.sm,
                                  height: 28,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  foregroundColor: DefensysTokens.maroonOf(context),
                                  leading: const Icon(LucideIcons.eye, size: 13),
                                  onPressed: fileUrl.isNotEmpty
                                      ? () => viewFileInDialog(
                                            context: context,
                                            fileUrl: fileUrl,
                                            fileName: fileName,
                                          )
                                      : null,
                                  child: const Text(
                                    'Preview',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      if (uploaderName != null && uploaderName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Submitted by $uploaderName${submittedAt != null && submittedAt.isNotEmpty ? ' · $submittedAt' : ''}',
                          style: TextStyle(fontSize: 10.5, color: DefensysTokens.textSecondaryOf(context)),
                        ),
                      ],
                    ] else ...[
                      Text(
                        isMissing
                            ? 'Awaiting submission from student team.'
                            : (isWaived
                                ? 'Requirement waived for this stage.'
                                : 'No submission uploaded yet.'),
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: isMissing ? const Color(0xFFDC2626) : DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // Adviser/Instructor feedback remark if rejected or notes present
          if (feedback.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: isRejected ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isRejected ? const Color(0xFFFECDD3) : const Color(0xFFBBF7D0),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.comment_outlined,
                    size: 14,
                    color: isRejected ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isPit ? 'Instructor remarks: "$feedback"' : 'Adviser remarks: "$feedback"',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: isRejected ? const Color(0xFF881337) : const Color(0xFF14532D),
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

  Widget _buildDeliverableStatusBadge({
    bool isDefenseUploaded = false,
    required bool isAccepted,
    required bool isPending,
    required bool isRejected,
    required bool isMissing,
    required bool isWaived,
  }) {
    final style = WorkflowStatusStyle.of(context,
      isWaived ? WorkflowStatusTone.neutral
        : isRejected ? WorkflowStatusTone.attention
        : isDefenseUploaded || isAccepted ? WorkflowStatusTone.success
        : isPending ? WorkflowStatusTone.active : WorkflowStatusTone.neutral);
    final bg = style.background;
    final border = style.border;
    final fg = style.foreground;
    String text;
    IconData icon;

    if (isDefenseUploaded || isAccepted) {
      text = isDefenseUploaded ? 'Uploaded' : 'Accepted';
      icon = LucideIcons.checkCircle2;
    } else if (isPending) {
      text = 'Pending Review';
      icon = LucideIcons.clock;
    } else if (isRejected) {
      text = 'Needs Revision';
      icon = LucideIcons.circleAlert;
    } else if (isMissing) {
      text = 'Missing';
      icon = LucideIcons.circleAlert;
    } else if (isWaived) {
      text = 'Waived';
      icon = LucideIcons.minusCircle;
    } else {
      text = 'Not Uploaded';
      icon = LucideIcons.circle;
    }

    return ShadBadge.outline(
      backgroundColor: bg,
      foregroundColor: fg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(Map<String, dynamic> stage) => TeamWorkflowBadge(
    status: TeamWorkflowStatus.fromStage(stage, scope: widget.state.scope),
    compact: true,
  );
}
