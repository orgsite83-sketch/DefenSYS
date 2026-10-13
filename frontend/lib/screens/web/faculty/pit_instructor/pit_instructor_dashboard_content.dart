import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/capstone_deliverables_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../admin/widgets/defensys_admin_shell.dart';
import '../../shared/team_deliverables/deliverables_view_types.dart';

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  void _refresh() => ref
      .read(capstoneDeliverablesProvider.notifier)
      .fetchDeliverables(
        scope: 'pit',
        search: '',
        status: '',
        selectedStage: '',
        yearLevel: widget.yearLevel ?? '',
        section: widget.section ?? '',
      );

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
    final state = ref.watch(capstoneDeliverablesProvider);
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
    final progress = <Widget>[];
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
                ? 'Scheduling checks clear; $submitted/$total defense files uploaded'
                : 'Scheduling checks clear; ready for endorsement',
            () => widget.onOpenDeliverables(id),
          ),
        );
      }
      if (total > 0) {
        progress.add(
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              team['name']?.toString() ?? 'Team',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            subtitle: Text(
              '$submitted/$total defense materials uploaded',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => widget.onOpenDeliverables(id),
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
        'Defense files pending',
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
        LayoutBuilder(
          builder: (context, constraints) {
            final myActions = _panel(
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
            );
            final materials = _panel(
              'Defense materials',
              'Required files due before the scheduled defense.',
              progress.isEmpty
                  ? const Text(
                      'No defense material uploads are configured for these teams.',
                    )
                  : Column(children: progress),
            );
            if (constraints.maxWidth < 1000) {
              return Column(
                children: [myActions, const SizedBox(height: 16), materials],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: myActions),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: materials),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _panel(
          'My teams',
          'Assigned teams in this PIT section.',
          Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => widget.onOpenDeliverables(null),
                  child: const Text('Open PIT Teams'),
                ),
              ),
              if (teams.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No PIT teams are assigned to you for this term.',
                  ),
                ),
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
                    team['projectTitle']?.toString() ?? 'No project title',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => widget.onOpenDeliverables(_id(team['id'])),
                ),
                if (details[_id(team['id'])] case final detail?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      DeliverablesTriageHelper.hasPendingReview(detail)
                          ? '${DeliverablesTriageHelper.pendingReviewCount(detail)} submission(s) awaiting review'
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
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: teams.isEmpty
                ? null
                : () => widget.onOpenGrading(_id(teams.first['id'])),
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('View PIT grades'),
          ),
        ),
      ],
    );
  }
}
