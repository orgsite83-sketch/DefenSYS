import 'package:flutter/material.dart';

import '../../../models/team_workflow_status.dart';
import '../../../widgets/repository/workflow_status_style.dart';
import '../../../theme/defensys_tokens.dart';
import '../shared/dashboard_schedule_planner.dart';
import '../shared/team_deliverables/deliverables_view_types.dart';

class FacultyDashboardColumns extends StatelessWidget {
  final Widget left;
  final Widget topRight;
  final Widget bottomRight;

  const FacultyDashboardColumns({
    super.key,
    required this.left,
    required this.topRight,
    required this.bottomRight,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 1000) {
        return Column(
          children: [
            left,
            const SizedBox(height: 16),
            topRight,
            const SizedBox(height: 16),
            bottomRight,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [topRight, const SizedBox(height: 16), bottomRight],
            ),
          ),
        ],
      );
    },
  );
}

class FacultyTeamAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const FacultyTeamAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class FacultyTeamMenu extends StatelessWidget {
  final String teamName;
  final List<FacultyTeamAction> actions;

  const FacultyTeamMenu({
    super.key,
    required this.teamName,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final surface = DefensysTokens.surfaceOf(context);
    final ink = DefensysTokens.textPrimaryOf(context);
    final border = DefensysTokens.borderOf(context);
    final hover = DefensysTokens.surfaceHigherOf(context);
    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: hover,
        highlightColor: hover,
        splashColor: Colors.transparent,
      ),
      child: PopupMenuButton<int>(
        tooltip: 'Actions for $teamName',
        icon: Icon(Icons.more_horiz_rounded, size: 20, color: ink),
        padding: const EdgeInsets.all(6),
        borderRadius: BorderRadius.circular(6),
        menuPadding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 196, maxWidth: 240),
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border),
        ),
        onSelected: (index) => actions[index].onTap(),
        itemBuilder: (context) => [
          for (var i = 0; i < actions.length; i++)
            PopupMenuItem<int>(
              value: i,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(actions[i].icon, size: 16, color: ink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      actions[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: ink,
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
}

class FacultyTeamPager extends StatelessWidget {
  final int total;
  final int page;
  final int pageSize;
  final String viewAllLabel;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onViewAll;

  const FacultyTeamPager({
    super.key,
    required this.total,
    required this.page,
    this.pageSize = 4,
    required this.viewAllLabel,
    required this.onPrevious,
    required this.onNext,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final lastPage = total == 0 ? 0 : (total - 1) ~/ pageSize;
    final current = page > lastPage ? lastPage : page;
    final first = total == 0 ? 0 : current * pageSize + 1;
    final last = (current + 1) * pageSize > total
        ? total
        : (current + 1) * pageSize;
    final border = DefensysTokens.borderOf(context);
    final style = facultyDashboardOutlineStyle(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: total > pageSize
              ? WrapAlignment.spaceBetween
              : WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            if (total > pageSize)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: OutlinedButton(
                      key: const Key('team-page-previous'),
                      onPressed: current == 0 ? null : onPrevious,
                      style: style.copyWith(
                        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                        side: WidgetStatePropertyAll(BorderSide(color: border)),
                      ),
                      child: const Icon(Icons.chevron_left_rounded, size: 17),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    child: Text(
                      '$first–$last of $total',
                      style: TextStyle(
                        fontSize: 11,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: OutlinedButton(
                      key: const Key('team-page-next'),
                      onPressed: current == lastPage ? null : onNext,
                      style: style.copyWith(
                        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                        side: WidgetStatePropertyAll(BorderSide(color: border)),
                      ),
                      child: const Icon(Icons.chevron_right_rounded, size: 17),
                    ),
                  ),
                ],
              ),
            SizedBox(
              height: 32,
              child: OutlinedButton(
                onPressed: onViewAll,
                style: style,
                child: Text(viewAllLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

ButtonStyle facultyDashboardOutlineStyle(BuildContext context) =>
    OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      side: BorderSide(color: DefensysTokens.borderOf(context)),
      foregroundColor: DefensysTokens.textPrimaryOf(context),
      backgroundColor: DefensysTokens.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    );

/// A team-level summary. Defense files already present in the stage's pre
/// requirements are counted once, even when materials_readiness also lists them.
class TeamRequirementSummary {
  final int missingForEndorsement;
  final int pendingDefenseFiles;
  final int awaitingReview;
  final bool overdue;
  final bool awaitingSchedule;
  final bool configured;
  final bool needsAttention;
  final TeamWorkflowStatus? workflow;

  const TeamRequirementSummary({
    required this.missingForEndorsement,
    required this.pendingDefenseFiles,
    required this.awaitingReview,
    required this.overdue,
    required this.awaitingSchedule,
    required this.configured,
    required this.needsAttention,
    this.workflow,
  });

  int get missing => missingForEndorsement + pendingDefenseFiles;

  factory TeamRequirementSummary.fromTeam(
    Map<String, dynamic>? team, {
    String scope = 'capstone',
  }) {
    final stage = team == null
        ? null
        : DeliverablesTriageHelper.resolveCurrentStage(team);
    if (stage == null) {
      return const TeamRequirementSummary(
        missingForEndorsement: 0,
        pendingDefenseFiles: 0,
        awaitingReview: 0,
        overdue: false,
        awaitingSchedule: false,
        configured: false,
        needsAttention: false,
      );
    }

    final endorsementIds = <String>{};
    final defenseIds = <String>{};
    var overdue = false;
    for (final item in DeliverablesTriageHelper.items(stage)) {
      if (item['required'] != true ||
          item['is_waived'] == true ||
          item['type'] == 'post') {
        continue;
      }
      final submission = item['submission'];
      final status =
          (submission is Map ? submission['status'] : item['submission_status'])
              ?.toString()
              .toLowerCase();
      final isMaterial = item['requirement_timing'] == 'defense';
      final submitted = isMaterial && item['materials_submitted'] is bool
          ? item['materials_submitted'] == true
          : item['uploaded'] == true &&
                status != 'rejected' &&
                status != 'needs revision' &&
                status != 'needs_revision';
      if (!submitted) {
        final ids = isMaterial ? defenseIds : endorsementIds;
        ids.add(
          item['id']?.toString() ??
              item['label']?.toString() ??
              'requirement-${ids.length}',
        );
        if (item['materials_status'] == 'overdue') overdue = true;
      }
    }

    final materials = stage['materials_readiness'];
    if (materials is Map) {
      for (final item
          in (materials['missing'] as List? ?? []).whereType<Map>()) {
        defenseIds.add(
          item['id']?.toString() ??
              item['label']?.toString() ??
              'material-${defenseIds.length}',
        );
        if (item['materials_status'] == 'overdue') overdue = true;
      }
      overdue = overdue || materials['status'] == 'overdue';
    }

    return TeamRequirementSummary(
      missingForEndorsement: endorsementIds.length,
      pendingDefenseFiles: defenseIds.length,
      awaitingReview: TeamWorkflowStatus.pendingReviewCount(stage),
      overdue: overdue,
      awaitingSchedule:
          materials is Map && materials['status'] == 'awaiting_schedule',
      configured:
          stage['deliverables_configured'] == true ||
          stage['is_presentation_only'] == true ||
          DeliverablesTriageHelper.items(stage).isNotEmpty,
      needsAttention: stage['required_complete'] == false,
      workflow: TeamWorkflowStatus.fromStage(stage, scope: scope),
    );
  }

  String get label => workflow?.label ?? 'Not configured';
}

class TeamRequirementBadge extends StatelessWidget {
  final Map<String, dynamic>? team;

  final String scope;

  const TeamRequirementBadge({
    super.key,
    required this.team,
    this.scope = 'capstone',
  });

  @override
  Widget build(BuildContext context) {
    if (team == null) return const SizedBox.shrink();
    final summary = TeamRequirementSummary.fromTeam(team, scope: scope);
    return Tooltip(
      message:
          '${summary.workflow?.nextStep ?? ''} '
          '${summary.missingForEndorsement} files needed before endorsement; '
          '${summary.pendingDefenseFiles} defense files due later. '
          'Defense files do not block endorsement or scheduling. '
          '${summary.awaitingReview} submissions awaiting review.',
      child: TeamWorkflowBadge(
        key: const Key('team-requirement-badge'),
        status:
            summary.workflow ?? TeamWorkflowStatus.describe('not_configured'),
        compact: true,
      ),
    );
  }
}

class DefenseScheduleCalendar extends StatelessWidget {
  const DefenseScheduleCalendar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.schedules,
    required this.teamNames,
    required this.loading,
    required this.hasError,
    required this.onOpenDefense,
    this.programScope = 'capstone',
    this.onRefresh,
  });

  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> schedules;
  final Map<int, String> teamNames;
  final bool loading;
  final bool hasError;
  final void Function(int? teamId, String stageLabel) onOpenDefense;
  final String programScope;
  final VoidCallback? onRefresh;

  List<Map<String, dynamic>> _sessions() {
    final result = <Map<String, dynamic>>[];
    for (final schedule in schedules) {
      final teamId = int.tryParse('${schedule['team_id']}');
      final date = DateTime.tryParse('${schedule['scheduled_date']}');
      if (!teamNames.containsKey(teamId) ||
          date == null ||
          (schedule['scope'] != null && schedule['scope'] != programScope) ||
          schedule['status'] == 'cancelled') {
        continue;
      }
      final rawTime = schedule['start_time']?.toString() ?? '';
      final start = DateTime.tryParse('${schedule['scheduled_date']}T$rawTime');
      final duration = (schedule['slot_duration'] as num?)?.toInt() ?? 60;
      final end = start?.add(Duration(minutes: duration));
      final display =
          schedule['display_status']?.toString() ??
          (schedule['status'] == 'done'
              ? 'assessed'
              : schedule['status']?.toString() ?? 'scheduled');
      final level =
          schedule['team_level']?.toString() ??
          schedule['year_level']?.toString() ??
          '';
      final year = RegExp(
        r'^[1-4](?:st|nd|rd|th) Year',
      ).firstMatch(level)?.group(0);
      final state = schedule['status'] == 'archived'
          ? 'archived'
          : display == 'completed'
          ? 'completed'
          : schedule['status'] == 'done'
          ? 'assessed'
          : 'scheduled';
      result.add({
        'session_id':
            schedule['id']?.toString() ??
            '$teamId-${schedule['stage_label']}-$date-$rawTime',
        'date':
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'scope': programScope,
        'team_id': teamId,
        'team_name': teamNames[teamId],
        'team_count': 1,
        'event_name': schedule['stage_label']?.toString() ?? 'Defense',
        'year_levels': [if (year != null) year],
        'room': schedule['room']?.toString() ?? 'Venue to be confirmed',
        'time_blocks': [
          if (start != null && end != null)
            {'start': start.toIso8601String(), 'end': end.toIso8601String()},
        ],
        'status_counts': {state: 1},
        'display_status': display,
        'materials_readiness': schedule['materials_readiness'],
        'can_open': true,
        'sort_time': rawTime,
      });
    }
    result.sort(
      (a, b) => '${a['date']} ${a['sort_time']}'.compareTo(
        '${b['date']} ${b['sort_time']}',
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceOf(context),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: DefensysTokens.borderOf(context)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: DefensysTokens.borderOf(context)),
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: DefensysTokens.textPrimaryOf(context),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        DashboardSchedulePlanner(
          workspace: 'faculty',
          providedSessions: _sessions(),
          loading: loading,
          errorMessage: hasError ? 'The calendar could not be loaded.' : null,
          description: subtitle,
          onRetry: onRefresh,
          onOpenTeam: (teamId, stage) => onOpenDefense(teamId, stage),
        ),
      ],
    ),
  );
}
