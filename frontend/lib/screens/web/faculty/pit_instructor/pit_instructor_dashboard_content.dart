import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/capstone_deliverables_provider.dart';
import '../../../../services/defense/team_defense_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../admin/widgets/defensys_admin_shell.dart';
import '../../shared/team_deliverables/deliverables_view_types.dart';
import '../dashboard_widgets.dart';

class PitInstructorDashboardContent extends ConsumerStatefulWidget {
  final Map<String, dynamic>? data;
  final String facultyName;
  final String? yearLevel;
  final String? section;
  final void Function(int? teamId) onOpenDeliverables;
  final void Function(int? teamId) onOpenGrading;

  const PitInstructorDashboardContent({
    super.key,
    required this.data,
    required this.facultyName,
    this.yearLevel,
    this.section,
    required this.onOpenDeliverables,
    required this.onOpenGrading,
  });

  @override
  ConsumerState<PitInstructorDashboardContent> createState() =>
      _PitInstructorDashboardContentState();
}

class _PitInstructorDashboardContentState
    extends ConsumerState<PitInstructorDashboardContent> {
  static int? _id(dynamic value) => int.tryParse(value?.toString() ?? '');
  int _teamPage = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void didUpdateWidget(covariant PitInstructorDashboardContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.yearLevel != widget.yearLevel ||
        oldWidget.section != widget.section) {
      _teamPage = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  void _refresh() {
    ref
        .read(capstoneDeliverablesProvider.notifier)
        .fetchDeliverables(
          scope: 'pit',
          search: '',
          status: '',
          selectedStage: '',
          yearLevel: widget.yearLevel ?? '',
          section: widget.section ?? '',
        );
    ref.read(pitInstructorDefenseProvider.notifier).fetch();
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

  Widget _panel(String title, String subtitle, Widget body) => _surface(
    Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 16),
          body,
        ],
      ),
    ),
  );

  Widget _action(String title, String detail, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: DefensysTokens.surfaceHigherOf(context),
      borderRadius: BorderRadius.circular(10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        leading: Icon(
          Icons.rate_review_outlined,
          color: DefensysTokens.maroonOf(context),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        subtitle: Text(detail, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final activeTerm = widget.data?['active_semester']?.toString();
    final teams = (widget.data?['pit_teams'] as List? ?? [])
        .whereType<Map>()
        .map((team) => Map<String, dynamic>.from(team))
        .where((team) {
          final matchesYear =
              widget.yearLevel == null ||
              widget.yearLevel!.isEmpty ||
              team['yearLevel']?.toString().toLowerCase() ==
                  widget.yearLevel!.toLowerCase();
          final matchesSection =
              widget.section == null ||
              widget.section!.isEmpty ||
              team['section']?.toString().toLowerCase() ==
                  widget.section!.toLowerCase();
          final term = '${team['semester']}, A.Y. ${team['schoolYear']}';
          return matchesYear &&
              matchesSection &&
              (activeTerm == null ||
                  activeTerm == 'Not configured' ||
                  team['semester'] == null ||
                  team['schoolYear'] == null ||
                  term == activeTerm);
        })
        .toList();
    final teamIds = teams
        .map((team) => _id(team['id']))
        .whereType<int>()
        .toSet();
    final lastTeamPage = teams.isEmpty ? 0 : (teams.length - 1) ~/ 4;
    final visibleTeamPage = _teamPage > lastTeamPage ? lastTeamPage : _teamPage;
    final teamNames = <int, String>{
      for (final team in teams)
        if (_id(team['id']) != null)
          _id(team['id'])!: team['name']?.toString() ?? 'Team',
    };
    final state = ref.watch(capstoneDeliverablesProvider);
    final defense = ref.watch(pitInstructorDefenseProvider);
    final today = DateTime.now();
    final upcoming = defense.schedules.where((schedule) {
      if (schedule['scope'] != 'pit' ||
          schedule['status'] != 'scheduled' ||
          !teamIds.contains(_id(schedule['team_id']))) {
        return false;
      }
      final date = DateTime.tryParse(
        schedule['scheduled_date']?.toString() ?? '',
      );
      return date != null &&
          !date.isBefore(DateTime(today.year, today.month, today.day));
    }).toList();
    final details = state.scope == 'pit'
        ? {
            for (final team in state.teams)
              if (teamIds.contains(_id(team['id']))) _id(team['id'])!: team,
          }
        : <int, Map<String, dynamic>>{};

    var reviews = 0;
    var awaitingMaterials = 0;
    var readyToSchedule = 0;
    final actions = <Widget>[];
    for (final team in teams) {
      final id = _id(team['id']);
      if (id == null) continue;
      final detail = details[id];
      final stage = detail == null
          ? null
          : DeliverablesTriageHelper.resolveActiveStage(detail);
      if (stage == null) continue;
      final pending = DeliverablesTriageHelper.pendingReviewCount(detail!);
      reviews += pending;
      final materialMap = stage['materials_readiness'] is Map
          ? stage['materials_readiness'] as Map
          : const <String, dynamic>{};
      final total = (materialMap['required_total'] as num?)?.toInt() ?? 0;
      final submitted = (materialMap['submitted_total'] as num?)?.toInt() ?? 0;
      awaitingMaterials += total - submitted;
      final endorsementRequired = stage['endorsement_required'] != false;
      if (stage['deliverables_configured'] == true &&
          stage['required_complete'] == true &&
          stage['has_active_schedule'] != true &&
          stage['has_done_schedule'] != true &&
          stage['is_officially_complete'] != true &&
          ![
            'failed',
            'project_rejected',
            'for_redefense',
            'revisions_pending',
          ].contains(stage['stage_status_detail']) &&
          (!endorsementRequired || stage['endorsed'] == true)) {
        readyToSchedule++;
      }
      if (pending > 0) {
        actions.add(
          _action(
            team['name']?.toString() ?? 'Team',
            '$pending submission(s) awaiting review',
            () => widget.onOpenDeliverables(id),
          ),
        );
      } else if (stage['required_complete'] == true &&
          stage['deliverables_configured'] == true &&
          stage['endorsed'] != true &&
          endorsementRequired) {
        actions.add(
          _action(
            team['name']?.toString() ?? 'Team',
            total > submitted
                ? 'Ready for endorsement; $submitted/$total defense files uploaded (due later)'
                : 'Scheduling checks clear; ready for endorsement',
            () => widget.onOpenDeliverables(id),
          ),
        );
      }
    }

    final scope = [
      widget.yearLevel,
      widget.section,
    ].whereType<String>().where((part) => part.isNotEmpty).join(' — ');
    final stats = [
      _stat('${teams.length}', 'Assigned PIT teams', Icons.groups_outlined),
      _stat('$reviews', 'Submissions to review', Icons.rate_review_outlined),
      _stat('$readyToSchedule', 'Ready to schedule', Icons.verified_outlined),
      _stat(
        '$awaitingMaterials',
        'Defense files to upload',
        Icons.upload_file_outlined,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DefensysPageHeader(
          icon: Icons.school_outlined,
          title: 'Welcome, ${widget.facultyName}',
          subtitle:
              'PIT Instructor workspace${scope.isEmpty ? '' : ' · $scope'} · '
              '${activeTerm ?? 'Active Semester'}',
          actions: IconButton(
            tooltip: 'Refresh instructor workspace',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 760
              ? Column(
                  children: [
                    for (final stat in stats) ...[
                      Row(children: [stat]),
                      const SizedBox(height: 10),
                    ],
                  ],
                )
              : Row(
                  children: [
                    for (var i = 0; i < stats.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      stats[i],
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 18),
        FacultyDashboardColumns(
          topRight: DefenseScheduleCalendar(
            title: 'Defense schedule & materials',
            subtitle: 'Select a date to see team defenses and file progress.',
            schedules: upcoming,
            teamNames: teamNames,
            loading: defense.isLoading,
            hasError: defense.error != null,
            onOpenDefense: (teamId, _) => widget.onOpenDeliverables(teamId),
          ),
          left: _panel(
            'My teams',
            'Assigned teams in this PIT section.',
            Column(
              children: [
                if (teams.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'No PIT teams are assigned to you for this term.',
                    ),
                  ),
                for (final team in teams.skip(visibleTeamPage * 4).take(4)) ...[
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
                      team['projectTitle']?.toString() ?? 'No project title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TeamRequirementBadge(team: details[_id(team['id'])]),
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
                              label: 'View grades',
                              icon: Icons.fact_check_outlined,
                              onTap: () =>
                                  widget.onOpenGrading(_id(team['id'])),
                            ),
                          ],
                        ),
                      ],
                    ),
                    onTap: () => widget.onOpenDeliverables(_id(team['id'])),
                  ),
                ],
                FacultyTeamPager(
                  total: teams.length,
                  page: visibleTeamPage,
                  viewAllLabel: teams.length > 4
                      ? 'View all ${teams.length} PIT teams'
                      : 'Open PIT Teams',
                  onPrevious: () =>
                      setState(() => _teamPage = visibleTeamPage - 1),
                  onNext: () => setState(() => _teamPage = visibleTeamPage + 1),
                  onViewAll: () => widget.onOpenDeliverables(null),
                ),
              ],
            ),
          ),
          bottomRight: _panel(
            'My actions',
            'Submission reviews and teams with scheduling clearance.',
            state.isLoading && details.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : state.error != null && details.isEmpty
                ? const Text(
                    'Unable to check team actions. Refresh to try again.',
                  )
                : actions.isEmpty
                ? const Text('No submissions need review right now.')
                : Column(children: actions),
          ),
        ),
      ],
    );
  }
}
