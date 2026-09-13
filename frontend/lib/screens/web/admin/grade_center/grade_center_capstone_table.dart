import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/grade_center_provider.dart';
import '../../../../widgets/dialogs/confirm_dialog.dart';
import '../../../../widgets/feedback/empty_state.dart';
import 'grade_center_shared.dart';
import '../widgets/defensys_admin_shell.dart';

/// Option B: one card with term settings, filters, and capstone stages table.
class CapstoneStagesUnifiedCard extends ConsumerWidget {
  const CapstoneStagesUnifiedCard({
    super.key,
    required this.state,
    this.stages = const [],
    this.stagesLoading = false,
    required this.isAdmin,
    required this.searchController,
    required this.scopeFilter,
    required this.yearLevelFilter,
    required this.statusFilter,
    required this.onOpenStage,
    required this.onOfficiallyCompleteChanged,
    this.onPeerGradingChanged,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onSearchFocusChanged,
    this.showScopeFilter = false,
    this.scope = 'capstone',
    this.title,
    this.subtitle,
    this.icon,
  });

  final GradeCenterState state;
  final List<Map<String, dynamic>> stages;
  final bool stagesLoading;
  final bool isAdmin;
  final TextEditingController searchController;
  final Widget scopeFilter;
  final Widget yearLevelFilter;
  final Widget statusFilter;
  final void Function(CapstoneStageRow row) onOpenStage;
  final void Function(CapstoneStageRow row, bool value)
  onOfficiallyCompleteChanged;
  final void Function(CapstoneStageRow row, bool value)? onPeerGradingChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final ValueChanged<bool> onSearchFocusChanged;
  final bool showScopeFilter;
  final String scope;
  final String? title;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPit = scope == 'pit';
    final isAll = scope == 'all';
    final rows = isPit
        ? buildPitStageRows(state: state, pitEvents: stages)
        : (isAll
            ? buildAllStageRows(
                state: state,
                defenseStages: stages,
                pitEvents: state.pitEvents,
              )
            : buildCapstoneStageRows(state: state, defenseStages: stages));
    final sem = state.activeSemester;
    final termLabel = sem?['display_name']?.toString().trim() ?? '';

    final effectiveIcon = icon ??
        (isPit
            ? Icons.lightbulb_rounded
            : (isAll ? Icons.auto_graph_rounded : Icons.rocket_launch_rounded));
    final effectiveTitle = title ??
        (isPit
            ? 'PIT Expos & Event Stages'
            : (isAll ? 'All Grade Groups' : 'Capstone stages'));
    final effectiveSubtitle = subtitle ??
        (isPit
            ? 'Manage panel and peer grading across PIT year-level expos and event tracks.'
            : (isAll
                ? 'Overview of all Capstone and PIT grade groups for the active term.'
                : 'Manage grading by defense stage for the active term.'));

    return DefensysCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  effectiveIcon,
                  color: DefensysUi.primaryMaroon,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        effectiveTitle,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: DefensysUi.textDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        effectiveSubtitle,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: DefensysUi.steelGrey,
                          height: 1.35,
                        ),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(height: 8),
                        if (isPit) ...[
                          Builder(
                            builder: (ctx) => pitTermStatusBadgeRow(
                              state,
                              context: ctx,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'PIT events use panel and peer evaluation rubrics. Adviser grading is not applicable.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF98A2B3),
                              height: 1.3,
                            ),
                          ),
                        ] else if (isAll) ...[
                          Builder(
                            builder: (ctx) => Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text(
                                  'Term:',
                                  style: TextStyle(
                                    color: Color(0xFF98A2B3),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                capstoneTermStatusChip(
                                  label: 'Adviser grading (Capstone)',
                                  enabled:
                                      capstoneTermAdviserGradingEnabled(state),
                                ),
                                capstoneTermStatusChip(
                                  label: 'Peer evaluation',
                                  enabled: capstoneTermPeerEvalEnabled(state),
                                  helpTooltip:
                                      'Click for Peer Evaluation Workflow Guide',
                                  onHelpTap: () =>
                                      showPeerGradingHelpDialog(ctx, isPit: false),
                                ),
                                capstoneTermStatusChip(
                                  label: 'PIT Panel & Peer',
                                  enabled: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Overview of Capstone defense stages and PIT year-level expos for the active term.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF98A2B3),
                              height: 1.3,
                            ),
                          ),
                        ] else ...[
                          Builder(
                            builder: (ctx) => capstoneTermStatusBadgeRow(
                              state,
                              showPeerEvaluation: true,
                              context: ctx,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Change term-wide peer and adviser settings in Academic Periods.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF98A2B3),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                if (termLabel.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  _headerPill(termLabel),
                ],
                const SizedBox(width: 8),
                _headerPill(
                  rows.isEmpty
                      ? '0 stages'
                      : '1–${rows.length} of ${rows.length} ${isAll ? 'groups' : 'stages'}',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: _filterToolbar(),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 10, 24, 16),
            child: Text(
              'Open a stage to view teams, edit scores, and mark officially complete.',
              style: TextStyle(
                color: Color(0xFF98A2B3),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          if ((scope == 'capstone' || scope == 'all') &&
              unscheduledCapstoneTeamCount(state) > 0) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: gradeCenterUnscheduledBanner(
                teamCount: unscheduledCapstoneTeamCount(state),
              ),
            ),
          ],
          _tableBody(rows),
        ],
      ),
    );
  }

  Widget _headerPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF5D6678),
        ),
      ),
    );
  }

  Widget _filterToolbar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (showScopeFilter && isAdmin) ...[
          Expanded(
            flex: 2,
            child: gradeCenterFilterField(
              label: 'Scope',
              icon: Icons.layers_outlined,
              dropdown: gradeCenterFilterDropdownShell(child: scopeFilter),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: 2,
          child: gradeCenterFilterField(
            label: 'Year level',
            icon: Icons.school_outlined,
            dropdown: gradeCenterFilterDropdownShell(child: yearLevelFilter),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: gradeCenterFilterField(
            label: 'Status',
            icon: Icons.flag_outlined,
            dropdown: gradeCenterFilterDropdownShell(child: statusFilter),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: gradeCenterFilterField(
            label: 'Search',
            icon: Icons.search_rounded,
            dropdown: SizedBox(
              height: 40,
              child: TextField(
                controller: searchController,
                enabled: !state.isSaving,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search teams...',
                  hintStyle: const TextStyle(
                    color: DefensysUi.steelGrey,
                    fontSize: 12.5,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: const BorderSide(
                      color: DefensysUi.primaryMaroon,
                    ),
                  ),
                ),
                onChanged: onSearchChanged,
                onSubmitted: onSearchSubmitted,
                onTap: () => onSearchFocusChanged(true),
                onEditingComplete: () => onSearchFocusChanged(false),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tableBody(List<CapstoneStageRow> rows) {
    final isPit = scope == 'pit';
    final isAll = scope == 'all';
    if (state.isLoading || (stagesLoading && stages.isEmpty)) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(color: DefensysUi.primaryMaroon),
        ),
      );
    }

    if (!isAll && stages.isEmpty && (!isPit || state.pitEvents.isEmpty)) {
      return DefensysEmptyState.table(
        icon: isPit ? Icons.lightbulb_outline_rounded : Icons.layers_outlined,
        title: isPit ? 'No PIT Events Setup' : 'No Defense Stages Setup',
        description: isPit
            ? 'Configure PIT events under Defense Operations or Academic Periods to enable evaluation tracking.'
            : 'Configure defense stages under Defense Stages Setup to enable evaluation tracking.',
        size: DefensysEmptyStateSize.compact,
      );
    }

    if (rows.isEmpty) {
      return DefensysEmptyState.table(
        icon: Icons.filter_alt_off_outlined,
        title: isAll
            ? 'No Active Grade Groups to Display'
            : 'No Active Stages to Display',
        description: isAll
            ? 'No Capstone defense stages or PIT events match the selected filters.'
            : (isPit
                ? 'No PIT stages match the selected filters.'
                : 'Activate stages under Defense Stages Setup to track student team grades.'),
        size: DefensysEmptyStateSize.compact,
      );
    }

    return _stageCardsList(rows);
  }

  Widget _stageCardsList(List<CapstoneStageRow> rows) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _stageMilestoneCard(rows[i]),
          ],
        ],
      ),
    );
  }

  Widget _stageMilestoneCard(CapstoneStageRow row) {
    final order = row.displayOrder > 0 ? row.displayOrder : 1;
    final isComplete = row.isOfficiallyComplete;
    final rowScope = row.groupKey.split('|').first;
    final isPitRow = rowScope == 'pit';
    final groupGrades = gradesForGroup(state, rowScope, row.label);
    final redefenseTeams = groupGrades
        .where((g) => g['verdict']?.toString() == 'for_redefense')
        .map((g) => g['team_name']?.toString() ?? g['team']?['name']?.toString() ?? 'Unknown Team')
        .toList();
    final redefenseNotice = redefenseTeams.isNotEmpty
        ? '\n\n⚠️ WARNING: ${redefenseTeams.length} team${redefenseTeams.length == 1 ? '' : 's'} (${redefenseTeams.take(3).join(', ')}${redefenseTeams.length > 3 ? '...' : ''}) currently ${redefenseTeams.length == 1 ? 'has' : 'have'} a "For Re-defense" verdict and ${redefenseTeams.length == 1 ? 'has' : 'have'} not passed.\n\nMarking this stage complete will finalize this milestone. These teams will officially FAIL this stage and will NOT advance to the next stage.'
        : '';

    final hasTeams = row.teamCount > 0;
    final teamNotice = hasTeams
        ? '\n\n${row.teamCount} team${row.teamCount == 1 ? '' : 's'} will be affected.'
        : '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isComplete
              ? const Color(0xFFA7F3D0)
              : const Color(0xFFE5E7EB),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isComplete
                ? const Color(0xFF047857).withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.025),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Row: Order Badge, Stage Name, Description, and Workflow Status
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                capstoneStageOrderBadge(order),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scope == 'all' ? row.title : row.label,
                        style: const TextStyle(
                          color: DefensysUi.textDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (row.description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          row.description,
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                capstoneStageWorkflowPill(row.workflowStatus),
              ],
            ),
          ),

          // Middle Section: Rich 3-Tile Evaluation & Readiness Snapshot
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: _stageEvaluationSnapshot(row),
          ),

          const Divider(height: 1, color: Color(0xFFF2F4F7)),

          // Bottom Action Bar: Guidance Note + Actions (More & Main Milestone Button)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            child: Builder(
              builder: (context) => Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Stage Guidance Note (Left)
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          isComplete
                              ? Icons.lock_outline_rounded
                              : Icons.info_outline_rounded,
                          size: 14,
                          color: isComplete
                              ? const Color(0xFF047857)
                              : const Color(0xFF667085),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isComplete
                                ? 'All faculty and panel evaluations are locked for this stage.'
                                : (hasTeams
                                    ? 'Complete all required evaluations before marking stage complete.'
                                    : 'Schedule defenses in Defense Scheduler to begin collecting evaluations.'),
                            style: TextStyle(
                              color: isComplete
                                  ? const Color(0xFF047857)
                                  : const Color(0xFF667085),
                              fontSize: 11.5,
                              fontWeight: isComplete
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Peer Grading Toggle (PIT Scope)
                  if (isPitRow && onPeerGradingChanged != null) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Peer grading open',
                          style: TextStyle(
                            color: isComplete
                                ? const Color(0xFF98A2B3)
                                : const Color(0xFF344054),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Transform.scale(
                          scale: 0.75,
                          child: Switch(
                            value: row.peerGradingEnabled,
                            activeColor: const Color(0xFF047857),
                            onChanged: (!state.isSaving && !isComplete)
                                ? (val) => onPeerGradingChanged!(row, val)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ],

                  // Quick Inspection Action: View Details
                  Tooltip(
                    message: 'View Stage Details',
                    waitDuration: const Duration(milliseconds: 300),
                    child: InkWell(
                      onTap: () => onOpenStage(row),
                      borderRadius: BorderRadius.circular(7),
                      child: Container(
                        height: 36,
                        width: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: const Color(0xFFD0D5DD),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.visibility_outlined,
                          size: 17,
                          color: Color(0xFF344054),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Main Action Button (Reopen Stage or Mark Complete)
                  if (isComplete)
                    OutlinedButton.icon(
                      onPressed: !state.isSaving
                          ? () async {
                              final confirmed = await showConfirmDialog(
                                context,
                                title: 'Reopen ${row.label}?',
                                message:
                                    'Reopening this defense stage will allow faculty to edit grades again and unlock defense stage settings.$teamNotice\n\nAre you sure you want to reopen ${row.label}?',
                                confirmLabel: 'Reopen Stage',
                                cancelLabel: 'Cancel',
                                destructive: false,
                                icon: Icons.lock_open_rounded,
                              );
                              if (confirmed) {
                                onOfficiallyCompleteChanged(row, false);
                              }
                            }
                          : null,
                      icon: const Icon(Icons.replay_rounded, size: 14),
                      label: const Text('Reopen Stage'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF344054),
                        backgroundColor: Colors.white,
                        side: const BorderSide(
                          color: Color(0xFFD0D5DD),
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: !state.isSaving
                          ? () async {
                              final confirmed = await showConfirmDialog(
                                context,
                                title: 'Mark ${row.label} Complete?',
                                message:
                                    'Marking this stage officially complete will lock faculty and panel grades, finalize student scores, and make passed teams eligible for project archiving.$teamNotice$redefenseNotice\n\nAre you sure you want to mark ${row.label} officially complete?',
                                confirmLabel: 'Mark Complete',
                                cancelLabel: 'Cancel',
                                destructive: false,
                                icon: Icons.verified_rounded,
                              );
                              if (confirmed) {
                                onOfficiallyCompleteChanged(row, true);
                              }
                            }
                          : null,
                      icon: const Icon(Icons.verified_outlined, size: 15),
                      label: const Text('Mark Complete'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFF047857),
                        disabledBackgroundColor: const Color(0xFFE2E8F0),
                        disabledForegroundColor: const Color(0xFF94A3B8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stageEvaluationSnapshot(CapstoneStageRow row) {
    final rowScope = row.groupKey.split('|').first;
    final isPitRow = rowScope == 'pit';
    final isComplete = row.isOfficiallyComplete;
    final hasTeams = row.teamCount > 0;
    final groupGrades = gradesForGroup(state, rowScope, row.label);
    final readyCount =
        groupGrades.where((g) => g['grading_ready'] == true).length;
    final panelCompleteCount =
        groupGrades.where((g) => g['panel_complete'] == true).length;
    final adviserCompleteCount =
        groupGrades.where((g) => g['adviser_complete'] == true).length;
    final peerCompleteCount =
        groupGrades.where((g) => g['peer_eval_complete'] == true).length;
    final peerEnabled = row.peerGradingEnabled ||
        (!isPitRow && capstoneTermPeerEvalEnabled(state));
    final adviserEnabled =
        isPitRow ? false : capstoneTermAdviserGradingEnabled(state);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650;

        final teamCard = _snapshotTile(
          icon: Icons.groups_outlined,
          iconColor: const Color(0xFF475467),
          label: 'ENROLLED TEAMS',
          value: '${row.teamCount} ${row.teamCount == 1 ? 'Team' : 'Teams'}',
          subtitle: hasTeams
              ? '$readyCount of ${row.teamCount} grading-ready'
              : 'No teams scheduled',
        );

        final readinessCard = _snapshotTile(
          icon: isComplete ? Icons.verified_rounded : Icons.fact_check_outlined,
          iconColor: isComplete
              ? const Color(0xFF047857)
              : const Color(0xFFD97706),
          label: 'EVALUATION READINESS',
          value: isComplete
              ? '100% Finalized'
              : (hasTeams
                  ? '$readyCount of ${row.teamCount} Ready'
                  : 'Pending Schedules'),
          subtitle: isComplete
              ? 'Grades locked · Archive eligible'
              : (hasTeams
                  ? 'Grading in progress'
                  : 'No active defense slots'),
        );

        final componentsCard = _snapshotComponentsTile(
          panelText:
              hasTeams ? '$panelCompleteCount/${row.teamCount} done' : 'Required',
          adviserText: adviserEnabled
              ? (hasTeams
                  ? '$adviserCompleteCount/${row.teamCount} done'
                  : 'Required')
              : 'Disabled',
          peerText: peerEnabled
              ? (hasTeams
                  ? '$peerCompleteCount/${row.teamCount} done'
                  : 'Active')
              : 'Disabled',
          isComplete: isComplete,
          showAdviser: !isPitRow,
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              teamCard,
              const SizedBox(height: 8),
              readinessCard,
              const SizedBox(height: 8),
              componentsCard,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: teamCard),
            const SizedBox(width: 10),
            Expanded(child: readinessCard),
            const SizedBox(width: 10),
            Expanded(child: componentsCard),
          ],
        );
      },
    );
  }

  Widget _snapshotTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEAECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13.5, color: iconColor),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: DefensysUi.textDark,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 1.5),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 11,
              height: 1.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _snapshotComponentsTile({
    required String panelText,
    String? adviserText,
    required String peerText,
    required bool isComplete,
    bool showAdviser = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEAECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.checklist_rounded, size: 13.5, color: Color(0xFF475467)),
              SizedBox(width: 5),
              Text(
                'EVALUATION COMPONENTS',
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              _componentMiniPill('Panel', panelText),
              if (showAdviser && adviserText != null) ...[
                const SizedBox(width: 4),
                _componentMiniPill('Adviser', adviserText),
              ],
              const SizedBox(width: 4),
              _componentMiniPill('Peer', peerText),
            ],
          ),
        ],
      ),
    );
  }

  Widget _componentMiniPill(String name, String status) {
    final isDone = status.contains('done') || status == 'Complete';
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: isDone ? const Color(0xFFECFDF5) : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isDone ? const Color(0xFFA7F3D0) : const Color(0xFFD0D5DD),
            width: 0.8,
          ),
        ),
        child: Column(
          children: [
            Text(
              name,
              style: TextStyle(
                color: isDone ? const Color(0xFF047857) : const Color(0xFF344054),
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              status,
              style: TextStyle(
                color: isDone ? const Color(0xFF059669) : const Color(0xFF667085),
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// PIT / All scopes: unified card shell with filters and grouped event cards.
class GradeCenterGroupedUnifiedCard extends StatelessWidget {
  const GradeCenterGroupedUnifiedCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.state,
    required this.isAdmin,
    required this.searchController,
    required this.scopeFilter,
    required this.yearLevelFilter,
    required this.statusFilter,
    required this.listContent,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onSearchFocusChanged,
    this.icon,
    this.showScopeFilter = false,
  });

  final String title;
  final String subtitle;
  final GradeCenterState state;
  final bool isAdmin;
  final TextEditingController searchController;
  final Widget scopeFilter;
  final Widget yearLevelFilter;
  final Widget statusFilter;
  final Widget listContent;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final ValueChanged<bool> onSearchFocusChanged;
  final IconData? icon;
  final bool showScopeFilter;

  @override
  Widget build(BuildContext context) {
    return DefensysCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: DefensysUi.primaryMaroon,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: DefensysUi.textDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: DefensysUi.steelGrey,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (showScopeFilter && isAdmin) ...[
                  Expanded(
                    flex: 2,
                    child: gradeCenterFilterField(
                      label: 'Scope',
                      icon: Icons.layers_outlined,
                      dropdown: gradeCenterFilterDropdownShell(
                        child: scopeFilter,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: gradeCenterFilterField(
                    label: 'Year level',
                    icon: Icons.school_outlined,
                    dropdown: gradeCenterFilterDropdownShell(
                      child: yearLevelFilter,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: gradeCenterFilterField(
                    label: 'Status',
                    icon: Icons.flag_outlined,
                    dropdown: gradeCenterFilterDropdownShell(
                      child: statusFilter,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: gradeCenterFilterField(
                    label: 'Search',
                    icon: Icons.search_rounded,
                    dropdown: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: searchController,
                        enabled: !state.isSaving,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search teams...',
                          hintStyle: const TextStyle(
                            color: DefensysUi.steelGrey,
                            fontSize: 12.5,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(
                              color: Color(0xFFD1D5DB),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(
                              color: Color(0xFFD1D5DB),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(
                              color: DefensysUi.primaryMaroon,
                            ),
                          ),
                        ),
                        onChanged: onSearchChanged,
                        onSubmitted: onSearchSubmitted,
                        onTap: () => onSearchFocusChanged(true),
                        onEditingComplete: () => onSearchFocusChanged(false),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 10, 24, 16),
            child: Text(
              'Open a stage to view teams, edit scores, and mark officially complete.',
              style: TextStyle(
                color: Color(0xFF98A2B3),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: listContent,
          ),
        ],
      ),
    );
  }
}
