import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/academic/team_formation_service.dart';
import '../services/academic/team_roster_service.dart';
import 'shadcn/defensys_shadcn_scope.dart';
import 'shadcn/defensys_workflow_widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../services/academic/student_team_selection_provider.dart';
import '../services/auth/auth_provider.dart';
import '../services/capstone_deliverables_provider.dart';
import '../services/dashboard_provider.dart';
import '../theme/defensys_tokens.dart';
import 'repository/section_concept_workspace.dart';
import '../services/academic/student_team_tasks_provider.dart';

String conceptSetupLabel(Map task) {
  final remaining = task['remaining_count'] ?? task['required_count'];
  final partial = (task['provided_count'] as num? ?? 0) > 0;
  final noun = task['shared_system'] == true ? 'matching module concepts' : 'concepts';
  return partial ? 'Add $remaining remaining $noun' : 'Submit ${task['required_count']} $noun';
}

class StudentTeamSetupTasks extends ConsumerStatefulWidget {
  const StudentTeamSetupTasks({
    super.key,
    this.onOpenRepository,
    this.onRefresh,
    this.refreshKey,
    this.showConceptTasks = true,
  });
  final VoidCallback? onOpenRepository;
  final Future<void> Function()? onRefresh;
  final Object? refreshKey;
  final bool showConceptTasks;

  @override
  ConsumerState<StudentTeamSetupTasks> createState() =>
      _StudentTeamSetupTasksState();
}

class _StudentTeamSetupTasksState extends ConsumerState<StudentTeamSetupTasks> {
  List<Map<String, dynamic>> teams = [];
  List<Map<String, dynamic>> sectionTasks = [];
  List<Map<String, dynamic>> eventTeams = [];
  String? error;
  bool busy = false;
  int _requestRevision = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  @override
  void didUpdateWidget(covariant StudentTeamSetupTasks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      load(refresh: true);
    }
  }

  Future<void> load({bool refresh = false}) async {
    if (ref.read(authProvider).user?['role'] != 'student') return;
    final revision = ++_requestRevision;
    try {
      final result = await (refresh ? ref.refresh(studentTeamTasksProvider.future) : ref.read(studentTeamTasksProvider.future));
      if (mounted && revision == _requestRevision) {
        setState(() {
          teams = _teams(result);
          eventTeams = (result['event_teams'] as List? ?? []).whereType<Map>()
              .map((t) => Map<String, dynamic>.from(t)).toList();
          sectionTasks = (result['section_tasks'] as List? ?? []).whereType<Map>()
              .map((t) => Map<String, dynamic>.from(t)).toList();
          error = null;
        });
      }
    } catch (e) {
      if (mounted && revision == _requestRevision) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  List<Map<String, dynamic>> _teams(Map<String, dynamic> result) =>
      (result['teams'] as List? ?? [])
          .map((t) => Map<String, dynamic>.from(t as Map))
          .toList();

  Future<void> nameTeam(Map<String, dynamic> team) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _TeamNameDialog(initialName: team['needs_name'] == true ? '' : team['name'].toString()),
    );
    if (name == null || !mounted) return;
    ++_requestRevision;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ref
          .read(teamFormationServiceProvider)
          .completeName(team['id'] as int, name);
      if (mounted) setState(() => teams = _teams(result));
      await load(refresh: true);
      await widget.onRefresh?.call();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openConcepts(Map<String, dynamic> team, Map task) async {
    setState(() {
      busy = true;
      error = null;
    });
    ref.read(studentTeamSelectionProvider.notifier).select(team['id'] as int);
    // Wait for the selected team's dashboard before opening its concept stage.
    // This shares an in-flight refresh with the dashboard's team listener.
    await ref
        .read(dashboardProvider('student').notifier)
        .fetchDashboardData(silent: true);
    if (!mounted) return;
    final dashboardError = ref.read(dashboardProvider('student')).error;
    if (dashboardError != null) {
      setState(() {
        busy = false;
        error = dashboardError;
      });
      return;
    }
    await ref
        .read(capstoneDeliverablesProvider.notifier)
        .fetchDeliverables(
          scope: team['scope'].toString(),
          yearLevel: team['year_level'].toString(),
          selectedStage: task['stage_label'].toString(),
        );
    if (!mounted) return;
    final failure = ref.read(capstoneDeliverablesProvider).error;
    setState(() {
      busy = false;
      error = failure;
    });
    if (failure != null) return;
    widget.onOpenRepository?.call();
  }

  Future<void> confirmEventTeam(Map<String, dynamic> team) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EventTeamDetailsDialog(team: team),
    );
    if (saved != true || !mounted) return;
    await load(refresh: true);
    await widget.onRefresh?.call();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(studentTeamTasksProvider, (previous, next) {
      next.whenData((result) {
        if (mounted) { setState(() {
          this.teams = _teams(result);
          this.eventTeams = (result['event_teams'] as List? ?? []).whereType<Map>().map((t) => Map<String, dynamic>.from(t)).toList();
          sectionTasks = (result['section_tasks'] as List? ?? []).whereType<Map>().map((t) => Map<String, dynamic>.from(t)).toList();
          error = null;
        }); }
      });
    });
    final teams = this.teams.where((t) => widget.showConceptTasks || t['needs_name'] == true).toList();
    final eventTeams = this.eventTeams.where((t) => widget.showConceptTasks || t['needs_name'] == true || t['needs_details'] == true).toList();
    if (teams.isEmpty && sectionTasks.isEmpty && eventTeams.isEmpty && error == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                color: DefensysTokens.maroonOf(context),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: DefensysTokens.maroonOf(context).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.task_alt_rounded,
                              size: 16,
                              color: DefensysTokens.maroonOf(context),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              sectionTasks.isEmpty ? 'Action Required: Complete Team Setup' : 'Your Section & Team Tasks',
                              style: TextStyle(
                                fontFamily: DefensysTokens.fontFamilyInter,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                color: DefensysTokens.textPrimaryOf(context),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: DefensysTokens.panelOf(context),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: DefensysTokens.borderOf(context)),
                            ),
                            child: Text(
                              '${sectionTasks.length + teams.length + eventTeams.length} Action',
                              style: TextStyle(
                                fontFamily: DefensysTokens.fontFamilyInter,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: DefensysTokens.textSecondaryOf(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (busy) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                        ),
                        TextButton(
                          onPressed: busy ? null : () => load(refresh: true),
                          child: const Text('Retry'),
                        ),
                      ],
                      for (final task in sectionTasks) ...[
                        () {
                          final statusText = task['status_label'] ?? '${task['status']}'.replaceAll('_', ' ');
                          final isMissing = statusText.toString().toLowerCase().contains('missing');

                          return Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: DefensysTokens.panelOf(context),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: DefensysTokens.borderOf(context)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: DefensysTokens.maroonOf(context).withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.account_tree_outlined,
                                    size: 17,
                                    color: DefensysTokens.maroonOf(context),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${task['title']}',
                                        style: TextStyle(
                                          fontFamily: DefensysTokens.fontFamilyInter,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.2,
                                          height: 1.25,
                                          color: DefensysTokens.textPrimaryOf(context),
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: DefensysTokens.surfaceOf(context),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: DefensysTokens.borderOf(context)),
                                            ),
                                            child: Text(
                                              '${task['section']}',
                                              style: TextStyle(
                                                fontFamily: DefensysTokens.fontFamilyInter,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: DefensysTokens.textSecondaryOf(context),
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${task['stage_label']}',
                                            style: TextStyle(
                                              fontFamily: DefensysTokens.fontFamilyInter,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: DefensysTokens.textSecondaryOf(context),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isMissing ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                color: isMissing ? const Color(0xFFFDE68A) : const Color(0xFF86EFAC),
                                              ),
                                            ),
                                            child: Text(
                                              statusText.toString(),
                                              style: TextStyle(
                                                fontFamily: DefensysTokens.fontFamilyInter,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w700,
                                                color: isMissing ? const Color(0xFFB45309) : const Color(0xFF15803D),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  height: 32,
                                  child: OutlinedButton(
                                    onPressed: busy ? null : () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => SectionConceptWorkspace(
                                            projectId: task['project_id'] as int,
                                          ),
                                        ),
                                      );
                                      if (mounted) await load(refresh: true);
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: DefensysTokens.maroonOf(context),
                                      backgroundColor: DefensysTokens.maroonOf(context).withValues(alpha: 0.05),
                                      side: BorderSide(
                                        color: DefensysTokens.maroonOf(context).withValues(alpha: 0.28),
                                      ),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(horizontal: 11),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Open',
                                          style: TextStyle(
                                            fontFamily: DefensysTokens.fontFamilyInter,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 3),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 13,
                                          color: DefensysTokens.maroonOf(context),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }(),
                      ],
                      for (final team in eventTeams)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: DefensysShadcnScope(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${team['event_name']} · ${team['section']} · ${team['name']}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: DefensysTokens.textPrimaryOf(
                                      context,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (team['needs_details'] == true)
                                      ShadButton.outline(
                                        height: 0,
                                        enabled: !busy,
                                        onPressed: () => confirmEventTeam(team),
                                        leading: const Icon(
                                          Icons.assignment_outlined,
                                          size: 15,
                                        ),
                                        child: const Flexible(child: Text(
                                          'Confirm event team details',
                                          textAlign: TextAlign.center,
                                        )),
                                      ),
                                    for (final task
                                        in (widget.showConceptTasks ? team['concept_tasks'] as List? ??
                                                [] :
                                                [])
                                            .whereType<Map>())
                                      ShadButton(
                                        height: 0,
                                        enabled:
                                            !busy &&
                                            widget.onOpenRepository != null,
                                        onPressed: () =>
                                            openConcepts(team, task),
                                        child: Flexible(child: Text(
                                          conceptSetupLabel(task),
                                          textAlign: TextAlign.center,
                                        )),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ...teams.map(
                        (team) {
                          final conceptTasks = (widget.showConceptTasks ? team['concept_tasks'] as List? ?? [] : []).cast<Map>();
                          final needsName = team['needs_name'] == true;
                          if (!needsName && conceptTasks.isEmpty) return const SizedBox.shrink();

                          return Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: DefensysTokens.panelOf(context),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: DefensysTokens.borderOf(context)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${team['name']} · ${team['section']}${team['event_name'] == '' ? '' : ' · ${team['event_name']}'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: DefensysTokens.textSecondaryOf(context),
                                  ),
                                ),
                                if (needsName) ...[
                                  const SizedBox(height: 6),
                                  OutlinedButton.icon(
                                    onPressed: busy ? null : () => nameTeam(team),
                                    icon: const Icon(Icons.edit_outlined, size: 13),
                                    label: const Text('Choose team name', style: TextStyle(fontSize: 11.5)),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ],
                                for (final task in conceptTasks) ...[
                                  const SizedBox(height: 6),
                                  ElevatedButton.icon(
                                    onPressed: busy || widget.onOpenRepository == null
                                        ? null
                                        : () => openConcepts(team, task),
                                    icon: const Icon(Icons.description_outlined, size: 13),
                                    label: Text(
                                      task['mode'] == 'assigned'
                                          ? 'View assigned project · ${task['stage_label']}'
                                          : '${conceptSetupLabel(task)} · ${task['stage_label']}',
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: DefensysTokens.maroonOf(context),
                                      foregroundColor: Colors.white,
                                      visualDensity: VisualDensity.compact,
                                      elevation: 0,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> showTeamNameDialog(BuildContext context, {required String initialName}) {
  return showDialog<String>(
    context: context,
    builder: (_) => TeamNameDialog(initialName: initialName),
  );
}

class TeamNameDialog extends StatefulWidget {
  const TeamNameDialog({super.key, required this.initialName});
  final String initialName;
  @override
  State<TeamNameDialog> createState() => _TeamNameDialogState();
}

class _TeamNameDialogState extends State<TeamNameDialog> {
  late final controller = TextEditingController(text: widget.initialName);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose your team name'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Team name'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Official team names can only be submitted once during setup. Subsequent name changes require administrator approval.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (controller.text.trim().isNotEmpty) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: const Text('Save team name'),
      ),
    ],
  );
}

typedef _TeamNameDialog = TeamNameDialog;

class _EventTeamDetailsDialog extends ConsumerStatefulWidget {
  const _EventTeamDetailsDialog({required this.team});
  final Map<String, dynamic> team;
  @override
  ConsumerState<_EventTeamDetailsDialog> createState() =>
      _EventTeamDetailsDialogState();
}

class _EventTeamDetailsDialogState
    extends ConsumerState<_EventTeamDetailsDialog> {
  late final name = TextEditingController(text: widget.team['needs_name'] == true ? '' : '${widget.team['name']}');
  late final project = TextEditingController(
    text: '${widget.team['project_title'] ?? ''}',
  );
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    project.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty ||
        widget.team['concept_enabled'] != true && project.text.trim().isEmpty) {
      setState(
        () => error = 'Enter your team name and the required project title.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(teamRosterServiceProvider)
          .confirm(widget.team['id'] as int, widget.team['event_id'] as int, {
            'name': name.text.trim(),
            'project_title': project.text.trim(),
            'revision': widget.team['revision'],
          });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: ShadDialog(
      title: const Text('Confirm event team details'),
      description: Text(
        '${widget.team['event_name']} · ${widget.team['section']}',
      ),
      constraints: const BoxConstraints(maxWidth: 520),
      actions: [
        ShadButton.outline(
          enabled: !saving,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ShadButton(
          enabled: !saving,
          onPressed: save,
          child: Text(saving ? 'Confirming…' : 'Confirm details'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null)
              WorkflowNotice(
                title: 'Unable to confirm',
                message: error!,
                error: true,
              ),
            WorkflowField(
              label: 'Team name for this event',
              child: ShadInput(
                controller: name,
                enabled: !saving,
                maxLength: 120,
              ),
            ),
            if (widget.team['concept_enabled'] != true)
              WorkflowField(
                label: 'Project title',
                helper:
                    'This registers your project for this event. It does not imply concept approval.',
                child: ShadInput(
                  controller: project,
                  enabled: !saving,
                  maxLength: 255,
                ),
              )
            else
              WorkflowNotice(
                title: 'Project concepts',
                message: project.text.isNotEmpty
                    ? 'Your project continues as: ${project.text}. Its papers and approval follow this event’s concept workflow.'
                    : 'Complete your required titles in the existing concept workspace. Your roster members and leader stay the same.',
              ),
            Text(
              'These details belong to this event. Earlier events keep their saved team information.',
              style: TextStyle(
                fontSize: 12,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
