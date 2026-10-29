import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/capstone_deliverables_provider.dart';
import '../../../../services/defense/adviser_defense_provider.dart';
import '../../../../services/adviser_grading_provider.dart';
import '../../../../models/adviser_workflow.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../admin/widgets/defensys_admin_shell.dart';
import '../../shared/team_deliverables/deliverables_view_types.dart';
import '../dashboard_widgets.dart';

class AdviserDashboardContent extends ConsumerStatefulWidget {
  final Map<String, dynamic>? data;
  final String facultyName;
  final void Function(int? teamId) onOpenDeliverables;
  final void Function(int? teamId, String stageLabel) onOpenDefense;
  final void Function(int teamId, String stageLabel) onOpenGrades;

  const AdviserDashboardContent({
    super.key,
    required this.data,
    required this.facultyName,
    required this.onOpenDeliverables,
    required this.onOpenDefense,
    required this.onOpenGrades,
  });

  @override
  ConsumerState<AdviserDashboardContent> createState() =>
      _AdviserDashboardContentState();
}

class _AdviserTask {
  final String title;
  final String detail;
  final IconData icon;
  final int teamId;
  final VoidCallback onTap;

  const _AdviserTask(
    this.title,
    this.detail,
    this.icon,
    this.teamId,
    this.onTap,
  );
}

class _AdviserDashboardContentState
    extends ConsumerState<AdviserDashboardContent> {
  static int? _id(dynamic value) => int.tryParse(value?.toString() ?? '');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh();
    });
  }

  void _refresh() {
    ref
        .read(capstoneDeliverablesProvider.notifier)
        .fetchDeliverables(
          workspace: 'adviser',
          scope: 'capstone',
          search: '',
          status: '',
          selectedStage: '',
          yearLevel: '',
          section: '',
        );
    ref.read(adviserDefenseProvider.notifier).fetch(workspace: 'adviser');
    ref.read(adviserGradingProvider.notifier).fetchAll();
  }

  Widget _surface(Widget child) => Container(
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceOf(context),
      borderRadius: BorderRadius.circular(DefensysTokens.radiusXl),
      border: Border.all(color: DefensysTokens.borderOf(context)),
    ),
    child: child,
  );

  Widget _stat(String value, String label, IconData icon) => Expanded(
    child: _surface(
      Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: DefensysTokens.maroonOf(context), size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  Text(
                    label,
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
    ),
  );

  Widget _taskList(
    List<_AdviserTask> tasks,
    bool loading,
    bool hasError,
  ) => _surface(
    Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'My actions',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Submission reviews, grades, endorsements, and minutes to sign.',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 16),
          if (loading && tasks.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(),
              ),
            )
          else if (hasError && tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Unable to check team actions. Refresh to try again.',
              ),
            )
          else if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'You are all caught up. Team blockers and schedules remain visible below.',
              ),
            )
          else
            for (final task in tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: DefensysTokens.surfaceHigherOf(context),
                  borderRadius: BorderRadius.circular(10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 3,
                    ),
                    leading: Icon(
                      task.icon,
                      color: DefensysTokens.maroonOf(context),
                    ),
                    title: Text(
                      task.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      task.detail,
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: task.onTap,
                  ),
                ),
              ),
        ],
      ),
    ),
  );

  Widget _defenseCalendar(
    List<Map<String, dynamic>> schedules,
    Map<int, String> teamNames,
    bool loading,
    bool hasError,
  ) => DefenseScheduleCalendar(
    title: 'Defense Schedule',
    subtitle:
        'Your advisees only · Select a date to see defenses and materials.',
    schedules: schedules,
    teamNames: teamNames,
    loading: loading,
    hasError: hasError,
    onOpenDefense: widget.onOpenDefense,
    onRefresh: _refresh,
  );

  Widget _teamList(
    List<Map<String, dynamic>> teams,
    Map<int, Map<String, dynamic>> deliverablesById,
  ) => _surface(
    Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'My teams',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
          if (teams.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No capstone teams are assigned to you for this term.',
              ),
            )
          else
            for (final team in teams.take(4)) ...[
              const Divider(height: 1),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                title: Text(
                  team['name']?.toString() ?? 'Team',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  team['project_title']?.toString() ??
                      team['projectTitle']?.toString() ??
                      'No project title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TeamRequirementBadge(
                      team: deliverablesById[_id(team['id'])],
                    ),
                    FacultyTeamMenu(
                      teamName: team['name']?.toString() ?? 'Team',
                      actions: [
                        FacultyTeamAction(
                          label: 'Open deliverables',
                          icon: Icons.folder_open_outlined,
                          onTap: () =>
                              widget.onOpenDeliverables(_id(team['id'])),
                        ),
                        FacultyTeamAction(
                          label: 'Grades & rubric',
                          icon: Icons.fact_check_outlined,
                          onTap: () {
                            final id = _id(team['id']);
                            if (id == null) return;
                            final stage =
                                DeliverablesTriageHelper.resolveActiveStage(
                                  deliverablesById[id] ?? const {},
                                )?['stage_label']?.toString() ??
                                '';
                            widget.onOpenGrades(id, stage);
                          },
                        ),
                        FacultyTeamAction(
                          label: 'Defense records',
                          icon: Icons.event_note_outlined,
                          onTap: () {
                            final id = _id(team['id']);
                            final stage =
                                DeliverablesTriageHelper.resolveActiveStage(
                                  deliverablesById[id] ?? const {},
                                )?['stage_label']?.toString() ??
                                '';
                            widget.onOpenDefense(id, stage);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                onTap: () => widget.onOpenDeliverables(_id(team['id'])),
              ),
            ],
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SizedBox(
                height: 32,
                child: OutlinedButton(
                  onPressed: () => widget.onOpenDeliverables(null),
                  style: facultyDashboardOutlineStyle(context),
                  child: const Text('Open Capstone Teams'),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final activeTerm = widget.data?['active_semester']?.toString();
    final advisedTeams = (widget.data?['advised_teams'] as List? ?? [])
        .whereType<Map>()
        .map((team) => Map<String, dynamic>.from(team))
        .where((team) {
          final semester = team['semester']?.toString();
          final schoolYear = team['schoolYear']?.toString();
          if (activeTerm == null ||
              activeTerm == 'Not configured' ||
              semester == null ||
              schoolYear == null) {
            return true;
          }
          return '$semester, A.Y. $schoolYear' == activeTerm;
        })
        .toList();
    final teamNames = <int, String>{
      for (final team in advisedTeams)
        if (_id(team['id']) != null)
          _id(team['id'])!: team['name']?.toString() ?? 'Team',
    };
    final teamIds = teamNames.keys.toSet();
    final deliverables = ref.watch(capstoneDeliverablesProvider);
    final defense = ref.watch(adviserDefenseProvider);
    final grading = ref.watch(adviserGradingProvider);
    final deliverablesById = <int, Map<String, dynamic>>{
      for (final team in deliverables.teams)
        if (teamIds.contains(_id(team['id']))) _id(team['id'])!: team,
    };
    final visibleSchedules = defense.schedules
        .where(
          (schedule) =>
              schedule['scope'] == 'capstone' &&
              teamIds.contains(_id(schedule['team_id'])),
        )
        .toList();

    final tasks = <_AdviserTask>[];
    var reviewCount = 0;
    var gradeCount = 0;
    var signatureCount = 0;
    for (final entry in deliverablesById.entries) {
      final team = entry.value;
      final name = teamNames[entry.key] ?? team['name']?.toString() ?? 'Team';
      final pending = DeliverablesTriageHelper.pendingReviewCount(team);
      if (pending > 0) {
        reviewCount += pending;
        tasks.add(
          _AdviserTask(
            name,
            '$pending submission(s) awaiting review',
            Icons.rate_review_outlined,
            entry.key,
            () => widget.onOpenDeliverables(entry.key),
          ),
        );
      }
      final stage = DeliverablesTriageHelper.resolveActiveStage(team);
      if (stage != null &&
          pending == 0 &&
          stage['required_complete'] == true &&
          (stage['deliverables_configured'] == true ||
              stage['is_presentation_only'] == true) &&
          stage['endorsed'] != true) {
        tasks.add(
          _AdviserTask(
            name,
            'Required items complete; ready for endorsement',
            Icons.verified_outlined,
            entry.key,
            () => widget.onOpenDeliverables(entry.key),
          ),
        );
      }
    }
    for (final grade in grading.grades) {
      final teamId = _id(grade['team_id']);
      if (teamId == null || !teamIds.contains(teamId)) continue;
      final guidance = AdviserGradingStatus.fromGrade(
        grade,
        enabled: grading.adviserGradingEnabled,
        error: grading.error,
      );
      if (!guidance.needsGrade) continue;
      gradeCount++;
      final stage = grade['stage_label']?.toString() ?? '';
      tasks.add(
        _AdviserTask(
          teamNames[teamId] ?? 'Team',
          '$stage · Ready to grade',
          Icons.rate_review_outlined,
          teamId,
          () => widget.onOpenGrades(teamId, stage),
        ),
      );
    }
    for (final schedule in visibleSchedules) {
      if (!AdviserMinutesStatus.fromSchedule(schedule).needsSignature) continue;
      final teamId = _id(schedule['team_id']);
      if (teamId == null) continue;
      signatureCount++;
      tasks.add(
        _AdviserTask(
          teamNames[teamId] ?? 'Team',
          '${schedule['stage_label']} · Minutes ready to sign',
          Icons.description_outlined,
          teamId,
          () => widget.onOpenDefense(
            teamId,
            schedule['stage_label']?.toString() ?? '',
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DefensysPageHeader(
          icon: Icons.school_outlined,
          title: 'Welcome, ${widget.facultyName}',
          subtitle:
              'Project Adviser workspace · ${widget.data?['active_semester'] ?? 'Active Semester'}',
          actions: IconButton(
            tooltip: 'Refresh adviser workspace',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final stats = [
              _stat(
                '${advisedTeams.length}',
                'Advised teams',
                Icons.groups_outlined,
              ),
              _stat(
                '$reviewCount',
                'Submissions to review',
                Icons.rate_review_outlined,
              ),
              _stat(
                '$gradeCount',
                'Ready to grade',
                Icons.rate_review_outlined,
              ),
              _stat('$signatureCount', 'Minutes to sign', Icons.draw_outlined),
            ];
            if (constraints.maxWidth < 760) {
              return Column(
                children: [
                  for (final stat in stats) ...[
                    Row(children: [stat]),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            }
            return Row(
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  stats[i],
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        FacultyDashboardColumns(
          left: _teamList(advisedTeams, deliverablesById),
          topRight: _defenseCalendar(
            visibleSchedules,
            teamNames,
            defense.isLoading,
            defense.error != null,
          ),
          bottomRight: _taskList(
            tasks,
            deliverables.isLoading || defense.isLoading || grading.isLoading,
            deliverables.error != null ||
                defense.error != null ||
                grading.error != null,
          ),
        ),
      ],
    );
  }
}
