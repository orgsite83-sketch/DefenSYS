import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/academic/team_formation_service.dart';
import '../services/academic/student_team_selection_provider.dart';
import '../services/auth/auth_provider.dart';
import '../services/capstone_deliverables_provider.dart';

class StudentTeamSetupTasks extends ConsumerStatefulWidget {
  const StudentTeamSetupTasks({
    super.key,
    this.onOpenRepository,
    this.onRefresh,
  });
  final VoidCallback? onOpenRepository;
  final Future<void> Function()? onRefresh;

  @override
  ConsumerState<StudentTeamSetupTasks> createState() =>
      _StudentTeamSetupTasksState();
}

class _StudentTeamSetupTasksState extends ConsumerState<StudentTeamSetupTasks> {
  List<Map<String, dynamic>> teams = [];
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
    load();
  }

  Future<void> load() async {
    if (ref.read(authProvider).user?['role'] != 'student') return;
    final revision = ++_requestRevision;
    try {
      final result = await ref.read(teamFormationServiceProvider).setupTasks();
      if (mounted && revision == _requestRevision) {
        setState(() {
          teams = _teams(result);
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
      builder: (_) => _TeamNameDialog(initialName: team['name'].toString()),
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

  @override
  Widget build(BuildContext context) {
    if (teams.isEmpty && error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Complete your team setup',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (busy) const LinearProgressIndicator(),
              if (error != null) ...[
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: busy ? null : load,
                  child: const Text('Retry'),
                ),
              ],
              ...teams.map(
                (team) => Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${team['name']} · ${team['section']}${team['event_name'] == '' ? '' : ' · ${team['event_name']}'}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (team['needs_name'] == true)
                        TextButton.icon(
                          onPressed: busy ? null : () => nameTeam(team),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Choose team name'),
                        ),
                      ...(team['concept_tasks'] as List? ?? []).map(
                        (task) => TextButton.icon(
                          onPressed: busy || widget.onOpenRepository == null
                              ? null
                              : () => openConcepts(team, task as Map),
                          icon: const Icon(Icons.description_outlined),
                          label: Text(
                            task['mode'] == 'assigned'
                                ? 'View assigned project · ${task['stage_label']}'
                                : 'Submit ${task['required_count']} concepts · ${task['stage_label']}',
                          ),
                        ),
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

class _TeamNameDialog extends StatefulWidget {
  const _TeamNameDialog({required this.initialName});
  final String initialName;
  @override
  State<_TeamNameDialog> createState() => _TeamNameDialogState();
}

class _TeamNameDialogState extends State<_TeamNameDialog> {
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
      child: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 120,
        decoration: const InputDecoration(labelText: 'Team name'),
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
