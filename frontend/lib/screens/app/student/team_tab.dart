import 'package:defensys/theme/program_colors.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/capstone_deliverables_provider.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/program_badge.dart';
import '../../../widgets/student_team_setup_tasks.dart';
import '../../../services/academic/team_formation_service.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/app/data_refresh_provider.dart';
import '../../../widgets/repository/team_concept_title_editor.dart';
import '../../../widgets/repository/shared_concept_review.dart' show systemLetter;
import 'student_stage_data.dart';

/// Screen 1: Academic Defense Overview & Student Team Workspace.
/// Features clean, professional white surfaces, crisp hairline borders,
/// direct deep-linking quick actions (Repository & Peer Eval sub-tab),
/// the "Upcoming PIT Event" (or "Current Defense Stage") spotlight,
/// and an interactive team roster list.
class TeamTab extends ConsumerStatefulWidget {
  final Map<String, dynamic>? studentData;
  final Future<void> Function()? onRefresh;
  final void Function(int index, {int? subTabIndex})? onSelectTab;

  const TeamTab({
    super.key,
    required this.studentData,
    this.onRefresh,
    this.onSelectTab,
  });

  @override
  ConsumerState<TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends ConsumerState<TeamTab> {
  final _conceptOverrides = <String, Map<String, dynamic>>{};

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.onRefresh == null) return;
      final team = widget.studentData?['team'] as Map<String, dynamic>?;
      if (team == null) return;
      final deliv = ref.read(capstoneDeliverablesProvider);
      if (deliv.stageOptions.isNotEmpty) return;

      final isCapstone = team['isCapstone'] == true;
      final yearLevel = widget.studentData?['year_level']?.toString().trim();

      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
            scope: isCapstone ? 'capstone' : 'pit',
            yearLevel: isCapstone ? null : (yearLevel?.isNotEmpty == true ? yearLevel : null),
          );
    });
  }

  @override
  void didUpdateWidget(TeamTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.studentData, widget.studentData)) _conceptOverrides.clear();
    if (widget.onRefresh == null) return;
    final oldTeam = oldWidget.studentData?['team'];
    final newTeam = widget.studentData?['team'] as Map<String, dynamic>?;
    if (newTeam != null &&
        (oldTeam?['id'] != newTeam['id'] ||
            oldTeam?['isCapstone'] != newTeam['isCapstone'])) {
      final isCapstone = newTeam['isCapstone'] == true;
      final yearLevel = widget.studentData?['year_level']?.toString().trim();
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
            scope: isCapstone ? 'capstone' : 'pit',
            yearLevel: isCapstone ? null : (yearLevel?.isNotEmpty == true ? yearLevel : null),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final studentData = widget.studentData;
    final onRefresh = widget.onRefresh;
    final onSelectTab = widget.onSelectTab;

    final team = studentData?['team'] as Map<String, dynamic>?;
    final members =
        (studentData?['members'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final studentInfo = studentData?['student'] as Map<String, dynamic>?;
    final isCapstone = team?['isCapstone'] == true;

    if (team == null) {
      final emptyContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onRefresh != null) StudentTeamSetupTasks(onRefresh: onRefresh),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroonOf(context).withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.group_off_rounded,
                  size: 48,
                  color: DefensysTokens.maroonTextOf(context),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No Team Assigned Yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'You will see your project details, defense timeline, and teammate roster once an instructor or administrator assigns you to a team.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: DefensysTokens.textSecondaryOf(context),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              if (onRefresh != null)
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh Status'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DefensysTokens.maroonOf(context),
                    side: BorderSide(color: DefensysTokens.maroonOf(context)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

      if (onRefresh == null) return emptyContent;

      return RefreshIndicator(
        color: DefensysTokens.maroonOf(context),
        onRefresh: onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: emptyContent,
          ),
        ),
      );
    }

    final delivState = ref.watch(capstoneDeliverablesProvider);
    final teamData = delivState.teams.where((t) => t['id'] == team['id']).firstOrNull;

    final teamName = team['name']?.toString() ?? 'Team Project';
    final rawProjectTitle = team['projectTitle']?.toString() ??
        team['project_title']?.toString() ??
        '';
    final projectTitle = team['project_pending'] == true || rawProjectTitle.trim().isEmpty
        ? 'Project not selected' : rawProjectTitle;
    final semester = team['semester']?.toString() ?? '';
    final schoolYear = team['schoolYear']?.toString() ?? '';
    final section = team['section']?.toString() ??
        widget.studentData?['section']?.toString() ??
        '';
    final yearLevel = team['yearLevel']?.toString() ??
        widget.studentData?['year_level']?.toString() ??
        '';
    final adviserName =
        team['adviserName']?.toString() ?? (isCapstone ? 'Unassigned' : 'N/A');

    // Dynamic stage resolution
    final backendStageOptions = (widget.studentData?['stage_options'] as List?)
            ?.map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const <String>[];

    final stagesList = (widget.studentData?['stages'] as List? ??
            teamData?['stages'] as List? ??
            [])
        .cast<Map<String, dynamic>>();

    final stagesListOptions = stagesList
        .map((s) => s['stage_label']?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    final stageOptions = widget.studentData?.containsKey('stage_options') == true
        ? backendStageOptions
        : (delivState.stageOptions.isNotEmpty
            ? delivState.stageOptions
            : stagesListOptions);

    final rawActiveStageName = teamData?['current_stage']?.toString() ??
        teamData?['current_defense_stage']?.toString() ??
        teamData?['ready_for_stage']?.toString() ??
        team['currentStage']?.toString() ??
        team['readyForStage']?.toString() ??
        team['ready_for_stage']?.toString() ??
        widget.studentData?['current_stage']?.toString() ??
        (stageOptions.isNotEmpty ? stageOptions.first : '');

    final activeStageName = stageOptions.isEmpty
        ? ''
        : (stageOptions.any((s) => s.trim().toLowerCase() == rawActiveStageName.trim().toLowerCase())
            ? rawActiveStageName
            : stageOptions.first);

    final schedule = studentStageRecord(
      stage: activeStageName,
      stages: stagesList,
      field: 'schedule',
      fallback: studentData?['schedule'] as Map<String, dynamic>?,
    );
    final grades = studentStageRecord(
      stage: activeStageName,
      stages: stagesList,
      field: 'grade',
      fallback: studentData?['grades'] as Map<String, dynamic>?,
    );

    // Calculate deliverables file count
    final deliverables = (studentData?['deliverables'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    int fileCount = 0;
    for (final d in deliverables) {
      final files = d['files'] as List?;
      if (files != null && files.isNotEmpty) {
        fileCount += files.length;
      } else if (d['file_url'] != null || d['file_name'] != null) {
        fileCount += 1;
      }
    }
    if (fileCount == 0 && deliverables.isNotEmpty) {
      fileCount = deliverables.length;
    }

    final hasPendingPeer = StudentTaskBadgeHelper.hasPendingPeerEval(studentData);
    final peerEvalComplete = !hasPendingPeer &&
        (studentData?['myPeerEvalComplete'] == true ||
            studentData?['peerEvalComplete'] == true);

    // Extract set of evaluated teammate IDs/names
    final mySubmissions = (studentData?['myPeerSubmissions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final evaluatedTeammateKeys = <String>{};
    for (final sub in mySubmissions) {
      final id = sub['evaluateeId']?.toString() ?? sub['evaluatee_id']?.toString();
      if (id != null && id.isNotEmpty) evaluatedTeammateKeys.add(id);
      final name = sub['evaluateeName']?.toString() ?? sub['evaluatee_name']?.toString();
      if (name != null && name.trim().isNotEmpty) {
        evaluatedTeammateKeys.add(name.trim().toLowerCase());
      }
    }
    if (evaluatedTeammateKeys.isEmpty) {
      final stages = (studentData?['stages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final s in stages) {
        if (s['stage_label']?.toString().trim().toLowerCase() !=
            activeStageName.trim().toLowerCase()) {
          continue;
        }
        final stageSubs = (s['my_peer_submissions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        for (final sub in stageSubs) {
          final id = sub['evaluateeId']?.toString() ?? sub['evaluatee_id']?.toString();
          if (id != null && id.isNotEmpty) evaluatedTeammateKeys.add(id);
          final name = sub['evaluateeName']?.toString() ?? sub['evaluatee_name']?.toString();
          if (name != null && name.trim().isNotEmpty) {
            evaluatedTeammateKeys.add(name.trim().toLowerCase());
          }
        }
      }
    }

    final needsName = team['needs_name'] == true || team['setup_pending'] == true;
    final isLeader = StudentTaskBadgeHelper.isTeamLeader(widget.studentData);

    final leaderMember = members.where((m) => m['isLeader'] == true || m['is_leader'] == true).firstOrNull;
    final leaderName = team['leader_name']?.toString() ??
        leaderMember?['name']?.toString() ??
        leaderMember?['first_name']?.toString() ??
        '';

    Map<String, dynamic>? conceptWorkflow;
    for (final s in stagesList) {
      if ('${s['stage_label']}'.trim().toLowerCase() != activeStageName.trim().toLowerCase()) continue;
      if (s['team_id'] != null && s['team_id'] != team['id']) continue;
      final cw = s['concept_workflow'];
      if (cw is Map && (cw['enabled'] == true || (cw['concepts'] as List? ?? []).isNotEmpty)) {
        conceptWorkflow = Map<String, dynamic>.from(cw);
        break;
      }
    }
    conceptWorkflow = _conceptOverrides['${team['id']}:$activeStageName'] ?? conceptWorkflow;
    final concepts = (conceptWorkflow?['concepts'] as List? ?? [])
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList();
    final isSharedSystem = conceptWorkflow?['section_project_id'] != null ||
        conceptWorkflow?['shared_import_pending'] == true ||
        conceptWorkflow?['selection_mode'] == 'shared_module' ||
        team['section_project_id'] != null;
    final hasConceptWorkflow = conceptWorkflow != null && concepts.isNotEmpty;
    final isPendingSelection = team['project_pending'] == true ||
        rawProjectTitle.trim().isEmpty ||
        conceptWorkflow?['status'] != 'approved';

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onRefresh != null || team['setup_pending'] == true || team['project_pending'] == true)
          StudentTeamSetupTasks(onOpenRepository: () => onSelectTab?.call(1, subTabIndex: 1),
            onRefresh: onRefresh, refreshKey: delivState.teams, showConceptTasks: false),
        // 1. TEAM & PROJECT OVERVIEW (CLEAN WHITE CARD)
        _buildTeamHeaderCard(
          teamName: teamName,
          projectTitle: projectTitle,
          isCapstone: isCapstone,
          yearLevel: yearLevel,
          section: section,
          semester: semester,
          schoolYear: schoolYear,
          adviserName: adviserName,
          needsName: needsName,
          isLeader: isLeader,
          leaderName: leaderName,
          teamId: team['id'] as int?,
          hasConceptWorkflow: hasConceptWorkflow,
          conceptProgress: '${concepts.where((c) => '${c['title'] ?? ''}'.trim().isNotEmpty).length} of ${concepts.length} ${isSharedSystem ? 'module' : 'concept'} titles provided',
          isPendingSelection: isPendingSelection,
          isSharedSystem: isSharedSystem,
        ),
        if (hasConceptWorkflow && isPendingSelection) ...[
          const SizedBox(height: 12),
          _buildProposedConceptsCard(
            workflow: conceptWorkflow,
            concepts: concepts,
            isSharedSystem: isSharedSystem,
            isLeader: isLeader,
            onEdit: () => _editConceptTitles(team['id'] as int, activeStageName),
            onSelectTab: onSelectTab,
          ),
        ],
        const SizedBox(height: 12),

        // 2. DIRECT ACTION SHORTCUTS (REPOSITORY & PEER EVAL SUB-TAB)
        _buildQuickActionCards(
          fileCount: fileCount,
          peerEvalComplete: peerEvalComplete,
          hasPendingPeer: hasPendingPeer,
          onSelectTab: onSelectTab,
        ),
        const SizedBox(height: 12),

        // 3. UPCOMING PIT EVENT (OR CURRENT DEFENSE STAGE)
        _buildUpcomingEventCard(
          activeStageName: activeStageName,
          schedule: schedule,
          grades: grades,
          isCapstone: isCapstone,
          onSelectTab: onSelectTab,
        ),
        const SizedBox(height: 12),

        // 4. TEAM MEMBERS ROSTER
        _buildTeamRosterCard(
          members: members,
          studentInfo: studentInfo,
          peerEvalComplete: peerEvalComplete,
          evaluatedTeammateKeys: evaluatedTeammateKeys,
          onSelectTab: onSelectTab,
        ),
        const SizedBox(height: 24),
      ],
    );

    if (onRefresh == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: content,
      );
    }

    return RefreshIndicator(
      color: DefensysTokens.maroonOf(context),
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: content,
      ),
    );
  }

  Future<void> _handleNameTeam(int teamId, String currentName) async {
    final name = await showTeamNameDialog(context, initialName: currentName);
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await ref.read(teamFormationServiceProvider).completeName(teamId, name.trim());
      await widget.onRefresh?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _editConceptTitles(int teamId, String stageLabel) async {
    final workflow = await editTeamConceptTitles(context, teamId: teamId, stageLabel: stageLabel);
    if (workflow == null || !mounted) return;
    setState(() => _conceptOverrides['$teamId:$stageLabel'] = workflow);
    ref.read(dashboardProvider('student').notifier).applyStudentConceptWorkflow(teamId, stageLabel, workflow);
    ref.read(dataRefreshProvider.notifier).markChanged(const [DataArea.dashboard, DataArea.teams, DataArea.deliverables]);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
      (workflow['concepts'] as List? ?? []).whereType<Map>().any((c) => '${c['title'] ?? ''}'.trim().isEmpty)
        ? 'Draft saved. Complete the remaining titles before review.' :
          workflow['section_project_id'] != null || workflow['shared_import_pending'] == true
            ? 'Module titles saved.' : 'Concept titles saved.')));
    await widget.onRefresh?.call();
  }

  // ─── 1. TEAM & PROJECT OVERVIEW CARD ───────────────────────────────────────

  Widget _buildTeamHeaderCard({
    required String teamName,
    required String projectTitle,
    required bool isCapstone,
    required String yearLevel,
    required String section,
    required String semester,
    required String schoolYear,
    required String adviserName,
    String leaderName = '',
    bool needsName = false,
    bool isLeader = false,
    int? teamId,
    bool hasConceptWorkflow = false,
    bool isPendingSelection = false,
    bool isSharedSystem = false,
    String conceptProgress = '',
  }) {
    final monogram = _extractTeamMonogram(teamName);
    final compactSemester = semester
        .replaceAll('1st Semester', '1st Sem')
        .replaceAll('2nd Semester', '2nd Sem')
        .replaceAll('Summer Semester', 'Summer');
    final compactSchoolYear = schoolYear.contains('-') && schoolYear.length >= 9
        ? schoolYear.split('-').map((y) => y.length == 4 ? y.substring(2) : y).join('-')
        : schoolYear;
    final termText = compactSemester.isNotEmpty && compactSchoolYear.isNotEmpty
        ? '$compactSemester, AY $compactSchoolYear'
        : (compactSchoolYear.isNotEmpty ? 'AY $compactSchoolYear' : '');

    final scopeLabel = isCapstone
        ? 'Capstone Project'
        : (yearLevel.isNotEmpty ? '$yearLevel PIT' : 'PIT Project');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ProgramColors.of(context, data: widget.studentData?['team'] as Map?).accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: ProgramColors.of(context, data: widget.studentData?['team'] as Map?).accent.withValues(alpha: 0.2),
                  ),
                ),
                child: Center(
                  child: Text(
                    monogram,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: ProgramColors.of(context, data: widget.studentData?['team'] as Map?).text,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            teamName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (needsName && isLeader && teamId != null) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _handleNameTeam(teamId, teamName),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: DefensysTokens.maroonOf(context).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: DefensysTokens.maroonOf(context).withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_outlined, size: 12, color: DefensysTokens.maroonOf(context)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Name team',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: DefensysTokens.maroonOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else if (!needsName) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Official team name finalized',
                            child: Icon(Icons.lock_outline_rounded, size: 13, color: DefensysTokens.steelGrey.withValues(alpha: 0.6)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPendingSelection && hasConceptWorkflow
                          ? conceptProgress
                          : projectTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isPendingSelection && hasConceptWorkflow
                            ? DefensysTokens.darkGold
                            : DefensysTokens.textSecondaryOf(context),
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ProgramBadge(
                scope: isCapstone ? 'capstone' : 'pit',
                label: scopeLabel,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.school_outlined,
                      size: 13,
                      color: DefensysTokens.steelGrey,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '${section.isNotEmpty ? '$section · ' : ''}$termText',
                        style: TextStyle(
                          fontSize: 11,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCapstone) ...[
                const SizedBox(width: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 14,
                      color: DefensysTokens.steelGrey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      adviserName != 'N/A' && adviserName != 'Unassigned'
                          ? 'Adviser: $adviserName'
                          : 'Adviser: Unassigned',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ] else if (leaderName.isNotEmpty) ...[
                const SizedBox(width: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 14,
                      color: DefensysTokens.steelGrey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Lead: $leaderName',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ─── 1B. PROPOSED CONCEPTS OVERVIEW CARD ──────────────────────────────────

  Widget _buildProposedConceptsCard({
    required Map<String, dynamic> workflow,
    required List<Map<String, dynamic>> concepts,
    required bool isSharedSystem,
    required bool isLeader,
    required VoidCallback onEdit,
    required void Function(int index, {int? subTabIndex})? onSelectTab,
  }) {
    final canEditTitles = isLeader && StudentTaskBadgeHelper.canEditConceptTitles(workflow);
    final status = switch (workflow['status']) {
      'concepts_needed' => isSharedSystem ? 'Modules needed' : 'Concepts needed',
      'replacement_concepts_needed' => 'Replacement needed',
      'concept_review_pending' => 'Review pending',
      'concept_endorsement_pending' => 'Awaiting endorsement',
      'module_confirmation_pending' => 'Awaiting module confirmation',
      'shared_clearance_pending' => 'Team endorsed · Shared papers pending',
      'shared_acknowledgment_pending' => 'Team endorsed · Adviser shared review pending',
      'ready_to_schedule' => 'Ready to schedule',
      'scheduled' => 'Hearing scheduled',
      'approved' => 'Approved',
      _ => isSharedSystem ? 'Module stage' : 'Concept Stage',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: DefensysTokens.darkGold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: DefensysTokens.darkGold,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isSharedSystem ? 'Proposed Modules' : 'Proposed Concepts',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: DefensysTokens.panelOf(context),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: DefensysTokens.borderOf(context)),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isSharedSystem ? 24 : 12),
          if (concepts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                isSharedSystem ? 'No modules configured for this stage yet.' : 'No concepts configured for this stage yet.',
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          for (var i = 0; i < concepts.length; i++) ...[
            Builder(
              builder: (context) {
                final c = concepts[i];
                final modTitle = c['title']?.toString().trim() ?? '';
                final systemTitle = '${c['system_title'] ?? ''}'.trim();
                final docStatus = c['documents_status']?.toString() ?? '';
                final confirmed = c['faculty_confirmed'] == true;

                return Container(
                  margin: EdgeInsets.only(bottom: isSharedSystem ? 0 : 6),
                  padding: isSharedSystem ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: isSharedSystem ? null : BoxDecoration(
                    color: DefensysTokens.panelOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: confirmed ? const Color(0xFF86EFAC) : DefensysTokens.borderOf(context),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isSharedSystem && i > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Divider(height: 1, color: DefensysTokens.borderOf(context)),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (isSharedSystem)
                            Expanded(child: Text(
                              'System ${systemLetter(c['key'])}',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                color: DefensysTokens.textPrimaryOf(context)),
                            ))
                          else Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: DefensysTokens.maroonOf(context).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Concept ${i + 1}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: DefensysTokens.maroonOf(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (confirmed)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: const Color(0xFF86EFAC)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_rounded, size: 10, color: Color(0xFF15803D)),
                                  SizedBox(width: 3),
                                  Text(
                                    'Confirmed',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF15803D),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (docStatus == 'uploaded' || docStatus == 'ready')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: DefensysTokens.surfaceOf(context),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: DefensysTokens.borderOf(context)),
                              ),
                              child: Text(
                                'Paper ready',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: DefensysTokens.textSecondaryOf(context),
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: DefensysTokens.surfaceOf(context),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                docStatus.isNotEmpty ? docStatus.replaceAll('_', ' ') : 'Pending',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: DefensysTokens.textSecondaryOf(context),
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (isSharedSystem) ...[
                        const SizedBox(height: 8),
                        Text(
                          systemTitle.isEmpty ? 'System name not yet provided' : systemTitle,
                          style: TextStyle(fontSize: 13, height: 1.5,
                            color: DefensysTokens.textSecondaryOf(context)),
                        ),
                        const SizedBox(height: 16),
                        Text('Module title', style: TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: DefensysTokens.textPrimaryOf(context))),
                      ],
                      SizedBox(height: isSharedSystem ? 8 : 5),
                      Text(
                        modTitle.isNotEmpty
                            ? modTitle
                            : (isSharedSystem ? 'Module title not yet proposed' : 'Concept title not yet proposed'),
                        style: TextStyle(
                          fontSize: isSharedSystem ? 14 : 13,
                          fontWeight: FontWeight.w600,
                          color: modTitle.isNotEmpty
                              ? DefensysTokens.textPrimaryOf(context)
                              : DefensysTokens.steelGrey,
                          fontStyle: modTitle.isEmpty ? FontStyle.italic : FontStyle.normal,
                          height: isSharedSystem ? 1.5 : 1.25,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          if (isSharedSystem)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Divider(height: 1, color: DefensysTokens.borderOf(context)),
            )
          else const SizedBox(height: 8),
          SizedBox(
              height: 44,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (canEditTitles) ...[
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('edit-team-concepts'),
                        onPressed: onEdit,
                        style: FilledButton.styleFrom(
                          backgroundColor: DefensysTokens.maroonOf(context),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 14),
                        label: Text(
                          isSharedSystem ? 'Edit module titles' : 'Edit concept titles',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => isSharedSystem
                          ? onSelectTab?.call(3)
                          : onSelectTab?.call(1, subTabIndex: 1),
                      icon: Icon(isSharedSystem ? Icons.hub_outlined : Icons.description_outlined,
                        size: 14, color: DefensysTokens.maroonOf(context)),
                      label: Text(
                        isSharedSystem ? 'Integration →' : 'View deliverables',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: DefensysTokens.maroonOf(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DefensysTokens.maroonOf(context),
                        side: BorderSide(color: DefensysTokens.maroonOf(context).withValues(alpha: 0.3)),
                        backgroundColor: isSharedSystem
                            ? DefensysTokens.maroonOf(context).withValues(alpha: 0.04)
                            : null,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                    ),
                  ),
                ],
              ),
          ),
        ],
      ),
    );
  }

  // ─── 2. QUICK ACTION SHORTCUTS (DIRECT DEEP NAVIGATION) ───────────────────

  Widget _buildQuickActionCards({
    required int fileCount,
    required bool peerEvalComplete,
    bool hasPendingPeer = false,
    required void Function(int index, {int? subTabIndex})? onSelectTab,
  }) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => onSelectTab?.call(2), // Directly opens Tab 2 (Repository)
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: DefensysTokens.surfaceOf(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: DefensysTokens.borderOf(context)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.folder_outlined,
                      size: 18,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Repository',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          fileCount > 0 ? '$fileCount Files' : 'Deliverables',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 11,
                    color: DefensysTokens.steelGrey,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: () => onSelectTab?.call(1, subTabIndex: 2), // Directly opens Tab 1, Sub-tab 2 (Peer Eval)
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: DefensysTokens.surfaceOf(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: DefensysTokens.borderOf(context)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: DefensysTokens.maroonOf(context).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.rate_review_outlined,
                          size: 18,
                          color: DefensysTokens.maroonTextOf(context),
                        ),
                      ),
                      if (hasPendingPeer)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(
                              'Peer Eval',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: DefensysTokens.textPrimaryOf(context),
                              ),
                            )),
                            if (hasPendingPeer) ...[
                              const SizedBox(width: 5),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          peerEvalComplete ? 'Completed ✓' : 'Review Peers',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: peerEvalComplete ? const Color(0xFF15803D) : DefensysTokens.maroonTextOf(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 11,
                    color: DefensysTokens.steelGrey,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── 3. UPCOMING PIT EVENT / CURRENT DEFENSE STAGE ─────────────────────────

  Widget _buildUpcomingEventCard({
    required String activeStageName,
    required Map<String, dynamic>? schedule,
    required Map<String, dynamic>? grades,
    required bool isCapstone,
    required void Function(int index, {int? subTabIndex})? onSelectTab,
  }) {
    if (activeStageName.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DefensysTokens.borderOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCapstone ? 'Current Defense Stage' : 'Upcoming PIT Event',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isCapstone ? 'No defense stages configured yet' : 'No PIT events configured yet',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isCapstone
                  ? 'Your schedule and defense status will appear after an administrator adds a stage.'
                  : 'Your event and schedule will appear after an administrator adds a PIT event.',
              style: TextStyle(fontSize: 11.5, color: DefensysTokens.textSecondaryOf(context)),
            ),
          ],
        ),
      );
    }

    final scheduledDate = schedule?['date']?.toString() ?? schedule?['scheduled_date']?.toString();
    final startTime = schedule?['start_time']?.toString() ?? schedule?['time']?.toString();
    final room = schedule?['room']?.toString();
    final hasSchedule = scheduledDate != null && scheduledDate.trim().isNotEmpty;
    final panelChair = schedule?['chair']?.toString() ?? schedule?['panel_chair']?.toString();
    final isPassed = grades != null &&
        (grades['is_published'] == true || grades['status'] == 'published') &&
        grades['result']?.toString().toUpperCase() == 'PASSED';

    String monthLabel = 'DATE';
    String dayLabel = '—';
    if (hasSchedule) {
      try {
        if (scheduledDate.contains('-')) {
          final parts = scheduledDate.split('-');
          if (parts.length == 3) {
            final m = int.tryParse(parts[1]) ?? 1;
            const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
            monthLabel = (m >= 1 && m <= 12) ? months[m - 1] : 'DATE';
            dayLabel = parts[2].split(' ')[0];
          }
        } else if (scheduledDate.contains('/')) {
          final parts = scheduledDate.split('/');
          if (parts.length == 3) {
            final m = int.tryParse(parts[0]) ?? 1;
            const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
            monthLabel = (m >= 1 && m <= 12) ? months[m - 1] : 'DATE';
            dayLabel = parts[1];
          }
        }
      } catch (_) {}
    }

    final cardTitle = isCapstone ? 'Current Defense Stage' : 'Upcoming PIT Event';

    return InkWell(
      onTap: () => onSelectTab?.call(1, subTabIndex: 0), // Directly opens Tab 1, Sub-tab 0 (Schedule)
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DefensysTokens.borderOf(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    cardTitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View Details',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.maroonTextOf(context),
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 12,
                      color: DefensysTokens.maroonTextOf(context),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (hasSchedule)
                  Container(
                    width: 48,
                    height: 52,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: DefensysTokens.surfaceOf(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: DefensysTokens.borderOf(context)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 2.5),
                          decoration: BoxDecoration(
                            color: DefensysTokens.maroonOf(context),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
                          ),
                          child: Text(
                            monthLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              dayLabel,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: DefensysTokens.textPrimaryOf(context),
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: 46,
                    height: 46,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: DefensysTokens.surfaceHigherOf(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.event_note_outlined,
                      color: DefensysTokens.steelGrey,
                      size: 22,
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeStageName,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      if (isPassed)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Cleared ✓  Score: ${grades['final_grade'] ?? grades['grade'] ?? 'Passed'}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF15803D),
                            ),
                          ),
                        )
                      else if (hasSchedule)
                        Text(
                          '${startTime?.isNotEmpty == true ? '$startTime · ' : ''}${room?.isNotEmpty == true ? room : 'Room TBA'}${panelChair != null ? ' · Chair: $panelChair' : ''}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: DefensysTokens.textSecondaryOf(context),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      else
                        Text(
                          'Preparation Phase · Awaiting schedule assignment',
                          style: TextStyle(
                            fontSize: 11,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: DefensysTokens.steelGrey,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isCapstone
                        ? 'Evaluation: Panel Deliberation, Adviser Endorsement & Peer Reviews'
                        : 'Evaluation Formula: 80% Panel Deliberation · 20% Peer Review',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── 4. TEAM MEMBERS ROSTER LIST ───────────────────────────────────────────

  Widget _buildTeamRosterCard({
    required List<Map<String, dynamic>> members,
    required Map<String, dynamic>? studentInfo,
    required bool peerEvalComplete,
    required Set<String> evaluatedTeammateKeys,
    required void Function(int index, {int? subTabIndex})? onSelectTab,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.group_outlined,
                      size: 16,
                      color: DefensysTokens.maroonTextOf(context),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Team Members (${members.length})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: peerEvalComplete
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  peerEvalComplete ? 'All Evaluated ✓' : 'Reviews Pending',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: peerEvalComplete ? const Color(0xFF15803D) : DefensysTokens.dangerText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (members.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No teammates listed yet.',
                style: TextStyle(fontSize: 11, color: DefensysTokens.textSecondaryOf(context)),
              ),
            )
          else
            ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: members.length,
              separatorBuilder: (context, index) => const Divider(
                height: 14,
                thickness: 0.8,
                color: Color(0xFFF1F5F9),
              ),
              itemBuilder: (context, index) {
                final m = members[index];
                final name = m['name']?.toString().trim() ?? 'Student';
                final isLeader = m['isLeader'] == true || m['is_leader'] == true;
                final username = m['username']?.toString() ?? m['id']?.toString() ?? '—';
                final isCurrent = m['id']?.toString() == studentInfo?['id']?.toString() ||
                    m['username']?.toString() == studentInfo?['username']?.toString();

                final mId = m['id']?.toString() ?? '';
                final mName = name.toLowerCase();
                final mUsername = m['username']?.toString() ?? '';
                final isEvaluated = evaluatedTeammateKeys.contains(mId) ||
                    evaluatedTeammateKeys.contains(mName) ||
                    (mUsername.isNotEmpty && evaluatedTeammateKeys.contains(mUsername));

                final initials = name.isNotEmpty
                    ? name.split(' ').where((w) => w.isNotEmpty).map((e) => e[0]).take(2).join().toUpperCase()
                    : 'S';

                return Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: isLeader
                          ? const Color(0xFF7F1D1D)
                          : DefensysTokens.maroonOf(context).withValues(alpha: 0.1),
                      child: Text(
                        initials,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isLeader ? Colors.white : DefensysTokens.maroonTextOf(context),
                        ),
                      ),
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
                                  name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: DefensysTokens.textPrimaryOf(context),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isCurrent)
                                const Text(
                                  ' (You)',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: DefensysTokens.steelGrey,
                                  ),
                                ),
                              if (isLeader) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFFDE68A)),
                                  ),
                                  child: const Text(
                                    'Leader',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'ID: $username',
                            style: TextStyle(
                              fontSize: 10,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: DefensysTokens.surfaceHigherOf(context),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Self',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      )
                    else if (isEvaluated)
                      InkWell(
                        onTap: () => onSelectTab?.call(1, subTabIndex: 2), // Directly opens Tab 1, Sub-tab 2 (Peer Eval)
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF86EFAC),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.check_rounded,
                                size: 12,
                                color: Color(0xFF15803D),
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Evaluated',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      InkWell(
                        onTap: () => onSelectTab?.call(1, subTabIndex: 2), // Directly opens Tab 1, Sub-tab 2 (Peer Eval)
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: DefensysTokens.maroonOf(context).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: DefensysTokens.maroonOf(context).withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.edit_note_rounded,
                                size: 12,
                                color: DefensysTokens.maroonTextOf(context),
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Evaluate',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: DefensysTokens.maroonTextOf(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  // ─── HELPER: EXTRACT TEAM MONOGRAM ─────────────────────────────────────────

  static String _extractTeamMonogram(String name) {
    final clean = name.replaceFirst(RegExp(r'^Team\s+', caseSensitive: false), '').trim();
    if (clean.isEmpty) return 'TM';
    final parts = clean.split(RegExp(r'[\s\-_]+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final matches = RegExp(r'[A-Z]').allMatches(clean).map((m) => m.group(0)!).toList();
    if (matches.length >= 2) {
      return '${matches[0]}${matches[1]}'.toUpperCase();
    }
    return clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
  }
}
