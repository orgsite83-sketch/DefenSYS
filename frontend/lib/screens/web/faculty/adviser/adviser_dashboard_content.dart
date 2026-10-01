import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/capstone_deliverables_provider.dart';
import '../../../../services/defense/adviser_defense_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../admin/widgets/defensys_admin_shell.dart';
import '../../shared/team_deliverables/deliverables_view_types.dart';

class AdviserDashboardContent extends ConsumerStatefulWidget {
  final Map<String, dynamic>? data;
  final String facultyName;
  final void Function(int? teamId) onOpenDeliverables;
  final void Function(int? teamId) onOpenDefense;

  const AdviserDashboardContent({
    super.key,
    required this.data,
    required this.facultyName,
    required this.onOpenDeliverables,
    required this.onOpenDefense,
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

  String _defenseSummary(Map<String, dynamic> schedule) {
    final date = DateTime.tryParse(
      schedule['scheduled_date']?.toString() ?? '',
    );
    final dateLabel = date == null
        ? 'Date pending'
        : MaterialLocalizations.of(context).formatMediumDate(date);
    final rawTime = schedule['start_time']?.toString() ?? '';
    final hour = rawTime.length >= 5
        ? int.tryParse(rawTime.substring(0, 2))
        : null;
    final timeLabel = hour == null
        ? 'Time pending'
        : '${hour % 12 == 0 ? 12 : hour % 12}:${rawTime.substring(3, 5)} ${hour < 12 ? 'AM' : 'PM'}';
    final room = schedule['room']?.toString() ?? '';
    return [
      schedule['stage_label']?.toString() ?? 'Defense',
      dateLabel,
      timeLabel,
      if (room.isNotEmpty) room,
    ].join(' · ');
  }

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
        .fetchDeliverables(scope: 'capstone');
    ref.read(adviserDefenseProvider.notifier).fetch();
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
            Column(
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
            'Reviews, endorsements, and minutes that need your attention.',
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

  Widget _upcomingDefenses(
    List<Map<String, dynamic>> schedules,
    Map<int, String> teamNames,
    bool loading,
    bool hasError,
  ) => _surface(
    Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Upcoming defenses',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Open a team’s Defense tab for its full record.',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 16),
          if (loading && schedules.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(),
              ),
            )
          else if (hasError && schedules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Unable to load defense schedules. Refresh to try again.',
              ),
            )
          else if (schedules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No defenses scheduled for your teams yet.'),
            )
          else
            for (final schedule in schedules.take(4))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.event_outlined,
                  color: DefensysTokens.maroonOf(context),
                ),
                title: Text(
                  teamNames[_id(schedule['team_id'])] ?? 'Team',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  _defenseSummary(schedule),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => widget.onOpenDefense(_id(schedule['team_id'])),
              ),
        ],
      ),
    ),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'My teams',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => widget.onOpenDeliverables(null),
                child: const Text('Open Capstone Teams'),
              ),
            ],
          ),
          if (teams.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No capstone teams are assigned to you for this term.',
              ),
            )
          else
            for (final team in teams) ...[
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => widget.onOpenDeliverables(_id(team['id'])),
              ),
              if (deliverablesById[_id(team['id'])] case final detail?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    DeliverablesTriageHelper.hasPendingReview(detail)
                        ? '${DeliverablesTriageHelper.pendingReviewCount(detail)} submission(s) awaiting review'
                        : DeliverablesTriageHelper.isOverdueOrMissing(detail)
                        ? 'Waiting on team requirements'
                        : 'No submission review pending',
                    style: TextStyle(
                      fontSize: 11,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ),
            ],
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
    var readyCount = 0;
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
        readyCount++;
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
    for (final schedule in visibleSchedules) {
      if (schedule['minutes_status'] != 'submitted') continue;
      final teamId = _id(schedule['team_id']);
      if (teamId == null) continue;
      tasks.add(
        _AdviserTask(
          teamNames[teamId] ?? 'Team',
          'Minutes are ready for your review and signature',
          Icons.description_outlined,
          teamId,
          () => widget.onOpenDefense(teamId),
        ),
      );
    }
    final now = DateTime.now();
    final upcoming =
        visibleSchedules.where((schedule) {
          if (schedule['status'] != 'scheduled') return false;
          final date = DateTime.tryParse(
            schedule['scheduled_date']?.toString() ?? '',
          );
          return date != null &&
              !date.isBefore(DateTime(now.year, now.month, now.day));
        }).toList()..sort(
          (a, b) => (a['scheduled_date']?.toString() ?? '').compareTo(
            b['scheduled_date']?.toString() ?? '',
          ),
        );

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
              _stat('$readyCount', 'Ready to endorse', Icons.verified_outlined),
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
                stats[0],
                const SizedBox(width: 12),
                stats[1],
                const SizedBox(width: 12),
                stats[2],
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 1000) {
              return Column(
                children: [
                  _taskList(
                    tasks,
                    deliverables.isLoading || defense.isLoading,
                    deliverables.error != null || defense.error != null,
                  ),
                  const SizedBox(height: 16),
                  _upcomingDefenses(
                    upcoming,
                    teamNames,
                    defense.isLoading,
                    defense.error != null,
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _taskList(
                    tasks,
                    deliverables.isLoading || defense.isLoading,
                    deliverables.error != null || defense.error != null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: _upcomingDefenses(
                    upcoming,
                    teamNames,
                    defense.isLoading,
                    defense.error != null,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _teamList(advisedTeams, deliverablesById),
      ],
    );
  }
}
