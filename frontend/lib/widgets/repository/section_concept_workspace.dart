import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../services/academic/section_concept_service.dart';
import '../../services/auth/auth_provider.dart';
import '../../services/network/authenticated_client.dart';
import '../../theme/defensys_tokens.dart';
import '../../theme/defensys_button_styles.dart';
import '../../models/team_workflow_status.dart';
import 'workflow_status_style.dart';
import 'shared_concept_review.dart';
import '../export/defensys_pdf_viewer.dart';
import '../shadcn/defensys_shadcn_scope.dart';

List<Map<String, dynamic>> _rows(dynamic value) => (value as List? ?? [])
    .whereType<Map>()
    .map((r) => Map<String, dynamic>.from(r))
    .toList();
String _error(Object error) => error.toString().replaceFirst('Exception: ', '');

Map<String, dynamic>? sharedReviewForTeam(
  Map<String, dynamic> team, {
  String? stageLabel,
}) {
  final stages = _rows(team['stages']);
  final selected = team['selected_stage'];
  final stage = stageLabel != null && stageLabel.isNotEmpty
      ? stages.where((s) => s['stage_label'] == stageLabel).firstOrNull ??
            (selected is Map && selected['stage_label'] == stageLabel
                ? Map<String, dynamic>.from(selected)
                : null)
      : selected is Map
      ? Map<String, dynamic>.from(selected)
      : stages.firstOrNull;
  final workflow = stage?['concept_workflow'] as Map?;
  final id = int.tryParse('${workflow?['section_project_id'] ?? ''}');
  if (id == null) return null;
  return {
    'project_id': id,
    'section': team['section'],
    'stage_label': stage?['stage_label'],
    'systems': (workflow?['config'] as Map?)?['system_concepts'] ?? [],
    ...Map<String, dynamic>.from(workflow?['shared_review'] as Map? ?? {}),
  };
}

List<Map<String, dynamic>> sharedReviewsForTeams(
  List<Map<String, dynamic>> teams, {
  String? stageLabel,
}) {
  final reviews = <int, Map<String, dynamic>>{};
  for (final team in teams) {
    final review = sharedReviewForTeam(team, stageLabel: stageLabel);
    if (review != null) reviews[review['project_id'] as int] = review;
  }
  return reviews.values.toList();
}

class SharedSectionStatus extends StatelessWidget {
  const SharedSectionStatus({
    super.key,
    required this.summary,
    required this.onOpen,
  });
  final Map<String, dynamic> summary;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final code = '${summary['status'] ?? 'needs_review'}';
    final tone = summary['cleared'] == true
        ? WorkflowStatusTone.success
        : code == 'failed'
        ? WorkflowStatusTone.destructive
        : code == 'awaiting_files'
        ? WorkflowStatusTone.neutral
        : const [
            'changes_requested',
            'revisions_pending',
            'replacement_concepts_needed',
          ].contains(code)
        ? WorkflowStatusTone.attention
        : WorkflowStatusTone.active;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TeamWorkflowBadge(
            status: TeamWorkflowStatus(
              summary['cleared'] == true ? 'ready_to_schedule' : code,
              '${summary['status_label'] ?? 'Shared papers awaiting review'}',
              tone,
            ),
          ),
          if (summary['acknowledgment_required'] == true &&
              summary['acknowledged'] == false)
            Text(
              summary['papers_available'] == true
                  ? 'Assigned adviser/instructor acknowledgment pending'
                  : 'Shared papers must be uploaded before adviser review',
              style: TextStyle(
                fontSize: 12,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          TextButton.icon(
            style: DefensysButtonStyles.tertiary(context),
            onPressed: onOpen,
            icon: const Icon(Icons.account_tree_outlined, size: 16),
            label: const Text('View shared papers'),
          ),
        ],
      ),
    );
  }
}

final sectionConceptIndexProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
      ref.watch(authProvider.select((s) => s.user?['id']));
      return ref.watch(sectionConceptServiceProvider).tasks();
    });

class SectionConceptTaskNotice extends ConsumerWidget {
  const SectionConceptTaskNotice({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authProvider).user == null) return const SizedBox.shrink();
    final tasks = _rows(
      ref.watch(sectionConceptIndexProvider).asData?.value['tasks'],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final task in tasks.where((t) => t['status'] != 'endorsed'))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.assignment_outlined),
            title: Text('${task['title']}'),
            subtitle: Text('${task['section']} · ${task['stage_label']}'),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SectionConceptWorkspace(
                    projectId: task['project_id'] as int,
                  ),
                ),
              );
              ref.invalidate(sectionConceptIndexProvider);
            },
          ),
      ],
    );
  }
}

/// Entry point shared by PM, faculty, students, administrators and panelists.
final _sectionProjectsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int?>((ref, teamId) {
      ref.watch(authProvider.select((s) => s.user?['id']));
      return ref.watch(sectionConceptServiceProvider).list(teamId: teamId);
    });

class SectionConceptHub extends ConsumerWidget {
  const SectionConceptHub({
    super.key,
    this.teamId,
    required this.section,
    this.onClosed,
  });
  final int? teamId;
  final String section;
  final Future<void> Function()? onClosed;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authProvider).user == null) return const SizedBox.shrink();
    final projects = _rows(
      ref.watch(_sectionProjectsProvider(teamId)).asData?.value['projects'],
    ).where((p) => p['section'] == section).toList();
    if (section.isEmpty || projects.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.account_tree_outlined),
        label: const Text('Shared system concepts'),
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  SectionConceptListScreen(teamId: teamId, section: section),
            ),
          );
          await onClosed?.call();
          ref.invalidate(_sectionProjectsProvider(teamId));
        },
      ),
    );
  }
}

class SectionConceptListScreen extends ConsumerStatefulWidget {
  const SectionConceptListScreen({super.key, this.teamId, this.section});
  final int? teamId;
  final String? section;
  @override
  ConsumerState<SectionConceptListScreen> createState() =>
      _SectionConceptListScreenState();
}

class _SectionConceptListScreenState
    extends ConsumerState<SectionConceptListScreen> {
  List<Map<String, dynamic>>? projects;
  List<Map<String, dynamic>> tasks = [];
  String? error;
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load() async {
    setState(() => error = null);
    try {
      final result = await ref
          .read(sectionConceptServiceProvider)
          .list(teamId: widget.teamId);
      if (mounted) {
        setState(() {
          projects = _rows(result['projects'])
              .where(
                (p) => widget.section == null || p['section'] == widget.section,
              )
              .toList();
          tasks = _rows(result['tasks']);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Shared system concepts'),
      actions: [
        IconButton(
          onPressed: load,
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error!),
                TextButton(onPressed: load, child: const Text('Retry')),
              ],
            ),
          )
        : projects == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (projects!.isEmpty)
                const Text(
                  'No shared-system section is assigned to you. Faculty can configure one during team generation or Manage sections.',
                ),
              for (final project in projects!)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text(
                    '${project['section']} · ${project['stage_label']}',
                  ),
                  subtitle: Text(
                    tasks
                            .where((t) => t['project_id'] == project['id'])
                            .map((t) => t['title'])
                            .join('\n')
                            .isNotEmpty
                        ? tasks
                              .where((t) => t['project_id'] == project['id'])
                              .map((t) => t['title'])
                              .join('\n')
                        : project['verdict'] == ''
                        ? 'View system proposals, module progress and faculty review'
                        : 'System decision: ${project['verdict']}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SectionConceptWorkspace(
                          projectId: project['id'] as int,
                        ),
                      ),
                    );
                    if (mounted) load();
                  },
                ),
            ],
          ),
  );
}

/// A configured section's proposals, reviewed without leaving the team list.
class SectionConceptOverview extends StatefulWidget {
  const SectionConceptOverview({
    super.key,
    required this.projectId,
    required this.systems,
    required this.stageLabel,
    this.onChanged,
    this.collapsible = false,
    this.summary,
    this.section,
  });
  final int projectId;
  final List<Map<String, dynamic>> systems;
  final String stageLabel;
  final Future<void> Function()? onChanged;
  final bool collapsible;
  final Map<String, dynamic>? summary;
  final String? section;

  @override
  State<SectionConceptOverview> createState() => SectionConceptOverviewState();
}

class SectionConceptOverviewState extends State<SectionConceptOverview> {
  bool expanded = false;
  List<Map<String, dynamic>>? updatedSystems;
  Map<String, dynamic>? updatedSummary;

  void openReview() {
    setState(() => expanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 250),
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant SectionConceptOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId ||
        oldWidget.systems != widget.systems) {
      updatedSystems = null;
      updatedSummary = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final systems = updatedSystems ?? widget.systems;
    final summary = updatedSummary ?? widget.summary;
    final progress = summary?['review_progress'] as Map?;
    final showReview = !widget.collapsible || expanded;
    final names = systems
        .where((s) => '${s['title'] ?? ''}'.trim().isNotEmpty)
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          border: Border.all(color: DefensysTokens.borderOf(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(
                Icons.account_tree_outlined,
                size: 20,
                color: DefensysTokens.maroonTextOf(context),
              ),
              title: Text(
                widget.section == null
                    ? 'Shared system proposals · ${widget.stageLabel}'
                    : 'Shared system papers · ${widget.section} · ${widget.stageLabel}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                progress != null && !showReview
                    ? '${progress['papers_accepted']}/3 papers accepted · ${summary?['status_label'] ?? ''}'
                    : names.isEmpty
                    ? 'Waiting for the section project manager to propose system names.'
                    : names
                          .map(
                            (s) =>
                                '${s['key'] == 'c1'
                                    ? 'A'
                                    : s['key'] == 'c2'
                                    ? 'B'
                                    : 'C'}. ${s['title']}',
                          )
                          .join('\n'),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
              trailing: widget.collapsible
                  ? Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                    )
                  : null,
              onTap: widget.collapsible
                  ? () => setState(() => expanded = !expanded)
                  : null,
            ),
            if (showReview)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SectionConceptWorkspace(
                  projectId: widget.projectId,
                  embedded: true,
                  onChanged: widget.onChanged,
                  onSnapshot: (p) => setState(() {
                    updatedSystems = _rows(p['systems']);
                    updatedSummary = Map<String, dynamic>.from(
                      p['shared_review'] as Map? ?? {},
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SectionConceptWorkspace extends ConsumerStatefulWidget {
  const SectionConceptWorkspace({
    super.key,
    required this.projectId,
    this.embedded = false,
    this.onChanged,
    this.onSnapshot,
  });
  final int projectId;
  final bool embedded;
  final Future<void> Function()? onChanged;
  final ValueChanged<Map<String, dynamic>>? onSnapshot;
  @override
  ConsumerState<SectionConceptWorkspace> createState() =>
      _SectionConceptWorkspaceState();
}

class _SectionConceptWorkspaceState
    extends ConsumerState<SectionConceptWorkspace> {
  Map<String, dynamic>? project;
  String? error;
  bool busy = false;
  String selectedSystem = 'c1';
  int requestVersion = 0;
  SectionConceptService get service => ref.read(sectionConceptServiceProvider);
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load() async {
    final version = ++requestVersion;
    try {
      final result = await service.get(widget.projectId);
      if (mounted && version == requestVersion) {
        setState(() {
          if (project == null && '${result['selected_key'] ?? ''}'.isNotEmpty) {
            selectedSystem = '${result['selected_key']}';
          }
          project = result;
          error = null;
        });
        widget.onSnapshot?.call(result);
      }
    } catch (e) {
      if (mounted && version == requestVersion) {
        setState(() => error = _error(e));
      }
    }
  }

  Future<void> perform(
    Future<Map<String, dynamic>> Function() action, {
    bool notifyChange = true,
  }) async {
    if (busy) return;
    final version = ++requestVersion;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await action();
      if (mounted && version == requestVersion) {
        setState(() {
          if (result['selected_key'] != project?['selected_key'] &&
              '${result['selected_key'] ?? ''}'.isNotEmpty) {
            selectedSystem = '${result['selected_key']}';
          }
          project = result;
        });
        if (notifyChange) widget.onSnapshot?.call(result);
        if (notifyChange) await widget.onChanged?.call();
      }
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editNames({Map<String, dynamic>? team}) async {
    final snapshot = Map<String, dynamic>.from(project!);
    final allRows = team == null
        ? _rows(project!['systems'])
        : _rows(team['concepts']);
    final selectedKey = '${snapshot['selected_key'] ?? ''}';
    final rows = team != null && selectedKey.isNotEmpty
        ? allRows.where((r) => r['key'] == selectedKey).toList()
        : allRows;
    final titles = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => _ProposalNamesDialog(
        rows: rows,
        title: team == null
            ? 'System proposal names'
            : '${team['name']} · Module names',
      ),
    );
    if (titles == null || !mounted) return;
    await perform(
      () => service.action(
        snapshot,
        team == null ? 'save_titles' : 'confirm_modules',
        {
          'concepts': [
            for (final original in allRows)
              titles.where((r) => r['key'] == original['key']).firstOrNull ??
                  original,
          ],
          if (team != null) 'team_id': team['id'],
        },
      ),
    );
  }

  Future<void> upload(Map<String, dynamic> system) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || !mounted) return;
    final file = result.files.single;
    if (file.bytes == null || file.size > 25 * 1024 * 1024) {
      setState(() => error = 'Choose a readable PDF of up to 25 MB.');
      return;
    }
    await perform(
      () =>
          service.upload(project!, '${system['key']}', file.name, file.bytes!),
    );
  }

  Future<void> viewPaper(Map<String, dynamic> paper) async {
    await perform(() async {
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile('${paper['file_url']}');
      if (!mounted) return project!;
      if (widget.embedded) {
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    '${paper['file_name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('Revision ${paper['revision']}'),
                  trailing: IconButton(
                    tooltip: 'Close paper',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Expanded(
                  child: DefensysPdfViewer(
                    pdfBytes: bytes,
                    title: '${paper['file_name']}',
                  ),
                ),
              ],
            ),
          ),
        );
        return project!;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text(
                '${paper['file_name']} · Revision ${paper['revision']}',
              ),
            ),
            body: DefensysPdfViewer(
              pdfBytes: bytes,
              title: '${paper['file_name']}',
            ),
          ),
        ),
      );
      return project!;
    }, notifyChange: false);
  }

  Future<void> requestCorrections(Map<String, dynamic> paper) async {
    final remarks = await _remarks(context, 'Request paper corrections');
    if (remarks == null || !mounted) return;
    await perform(
      () => service.action(project!, 'review', {
        'paper_id': paper['id'],
        'status': 'rejected',
        'remarks': remarks,
      }),
    );
  }

  Future<void> decide({Map<String, dynamic>? team}) async {
    final snapshot = Map<String, dynamic>.from(project!);
    final module = team == null
        ? null
        : (team['selected_module'] is Map
              ? Map<String, dynamic>.from(team['selected_module'] as Map)
              : _rows(team['concepts'])
                    .where((m) => m['key'] == snapshot['selected_key'])
                    .firstOrNull);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _SectionDecisionDialog(
        systems: _rows(snapshot['systems']),
        teamName: team?['name']?.toString(),
        selectedKey: '${snapshot['selected_key']}',
        pit: snapshot['scope'] == 'pit',
        module: module,
        onViewPaper: viewPaper,
      ),
    );
    if (result == null || !mounted) return;
    await perform(
      () => service.action(
        snapshot,
        team == null
            ? 'decide'
            : snapshot['scope'] == 'pit'
            ? 'module_decision'
            : 'module_verdict',
        {
          ...result,
          if (team != null) 'team_id': team['id'],
          if (team != null) 'module_key': snapshot['selected_key'],
          if (team != null && snapshot['scope'] == 'pit')
            'module_review_token': team['decision_review_token'],
        },
      ),
    );
  }

  Future<void> clearModuleRevisions(Map<String, dynamic> team) async {
    final snapshot = Map<String, dynamic>.from(project!);
    final token = team['decision_review_token'];
    final remarks = await _remarks(context, 'Clear module revisions');
    if (remarks == null || !mounted) return;
    await perform(
      () => service.action(snapshot, 'clear_module_revisions', {
        'team_id': team['id'],
        'module_key': snapshot['selected_key'],
        'module_review_token': token,
        'remarks': remarks,
      }),
    );
  }

  Widget moduleReviews(Map<String, dynamic> p) => SharedModuleReviewTable(
    project: p,
    busy: busy,
    onReview: (team) => decide(team: team),
    onConfirmNames: (team) => editNames(team: team),
    onClearRevisions: clearModuleRevisions,
  );

  Future<void> reassign() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ResponsibilityDialog(project: project!),
    );
    if (result != null && mounted) {
      await perform(() => service.action(project!, 'reassign', result));
    }
  }

  Widget _sharedAcknowledgment(Map<String, dynamic> p) {
    final shared = p['shared_review'] as Map? ?? {};
    if (shared['can_review_shared_context'] != true) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shared['acknowledged'] == true
                ? 'Your review of the current shared proposals is recorded.'
                : shared['papers_available'] == true
                ? 'Review all current shared proposals and check how your teams’ modules connect to each system. One acknowledgment covers your linked teams for this version.'
                : 'The project manager must upload all shared proposal papers before you can acknowledge their connection to your teams’ modules.',
          ),
          if (shared['can_acknowledge'] == true) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text(
                            'Acknowledge shared system alignment',
                          ),
                          content: const Text(
                            'I have reviewed the current shared system proposals and confirm that my teams’ modules align with them. This records my review of these versions; formal shared-paper acceptance is tracked separately.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('Confirm acknowledgment'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && mounted) {
                        await perform(() => service.action(p, 'acknowledge'));
                      }
                    },
              child: const Text('Acknowledge shared system alignment'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = project;
    if (widget.embedded) return _inlineReview(p);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          p == null ? 'Section concepts' : '${p['section']} · System concepts',
        ),
        actions: [
          IconButton(
            onPressed: busy ? null : load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: DefensysShadcnScope(
        child: p == null
            ? Center(
                child: error == null
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error!),
                          TextButton(
                            onPressed: load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      ShadCard(
                        width: double.infinity,
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${p['stage_label']} · Attempt ${p['round']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                            if (p['verdict'] != '')
                              ShadBadge(
                                backgroundColor: p['verdict'] == 'approved'
                                    ? const Color(0xFF16A34A)
                                    : null,
                                child: Text(
                                  '${p['verdict']}'
                                      .replaceAll('_', ' ')
                                      .toUpperCase(),
                                  style: const TextStyle(fontSize: 10),
                                ),
                              )
                            else if (p['endorsed'] == true)
                              const ShadBadge(
                                backgroundColor: Color(0xFF16A34A),
                                child: Text(
                                  'Shared papers cleared for hearing',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              )
                            else
                              const ShadBadge.secondary(
                                child: Text(
                                  'Review Phase',
                                  style: TextStyle(fontSize: 10),
                                ),
                              ),
                          ],
                        ),
                        description: Text(
                          'Project manager: ${p['project_manager_name']}\n${p['scope'] == 'pit' ? 'Section instructor' : 'System reviewer'}: ${p['reviewer_name']}',
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 8),
                            Text(
                              p['verdict'] != ''
                                  ? 'System outcome: ${p['verdict']}\n${p['remarks']}'
                                  : p['endorsed'] == true
                                  ? 'Shared papers cleared. Each team needs its own module review and endorsement before scheduling.'
                                  : 'The project manager submits three shared papers. Faculty confirms the titles and accepts each current paper for hearing.',
                              style: const TextStyle(fontSize: 13, height: 1.4),
                            ),
                            const SizedBox(height: 12),
                            _sharedAcknowledgment(p),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (p['can_edit_names'] == true)
                                  ShadButton.outline(
                                    size: ShadButtonSize.sm,
                                    onPressed: busy ? null : () => editNames(),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.edit_outlined,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          p['can_manage'] == true ||
                                                  p['can_review'] == true
                                              ? 'Confirm system names'
                                              : 'Propose system names',
                                        ),
                                      ],
                                    ),
                                  ),
                                if (p['can_manage'] == true &&
                                    p['can_reassign'] == true)
                                  ShadButton.ghost(
                                    size: ShadButtonSize.sm,
                                    onPressed: busy ? null : reassign,
                                    child: const Text(
                                      'Reassign responsibilities',
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (busy)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: LinearProgressIndicator(),
                        ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      SharedSystemSelectionBanner(project: p),
                      const SizedBox(height: 20),
                      if (p['shared_revisions_pending'] == true)
                        const Text(
                          'Shared system revisions are outstanding. Module approvals cannot complete progression until the revised system paper is accepted and cleared.',
                        ),
                      if (p['can_clear_shared_revisions'] == true)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    final remarks = await _remarks(
                                      context,
                                      'Clear shared system revisions',
                                    );
                                    if (remarks != null && mounted) {
                                      await perform(
                                        () => service.action(
                                          p,
                                          'clear_revisions',
                                          {'remarks': remarks},
                                        ),
                                      );
                                    }
                                  },
                            child: const Text('Clear shared system revisions'),
                          ),
                        ),
                      if ('${p['selected_key'] ?? ''}'.isEmpty)
                        for (final system in _rows(p['systems']))
                          _system(system),
                      if (p['can_decide'] == true)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ShadButton(
                            enabled: !busy,
                            onPressed: () => decide(),
                            child: const Text('Select section system'),
                          ),
                        ),
                      const SizedBox(height: 20),
                      if (p['shared_revisions_pending'] == true)
                        for (final system in _rows(
                          p['systems'],
                        ).where((s) => s['key'] == p['selected_key']))
                          _system(system),
                      moduleReviews(p),
                      if ('${p['selected_key'] ?? ''}'.isNotEmpty)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          initiallyExpanded: false,
                          title: const Text(
                            'Section system papers',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          children: [
                            for (final system in _rows(p['systems']).where(
                              (s) =>
                                  p['shared_revisions_pending'] != true ||
                                  s['key'] != p['selected_key'],
                            ))
                              _system(system),
                          ],
                        ),
                      const SizedBox(height: 24),
                      Text(
                        'Section hearing',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Schedule each participating team through the defense scheduler with the same day, room and chair, then assemble those schedules here. Team assessments stay separate.',
                      ),
                      if ((p['hearing_schedule_ids'] as List? ?? []).isNotEmpty)
                        Text(
                          'Hearing assembled with ${(p['hearing_schedule_ids'] as List).length} team schedules.',
                        ),
                      if (p['can_manage'] == true && p['verdict'] == '')
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => perform(
                                      () => service
                                          .action(p, 'schedule_hearing', {
                                            'schedule_ids': _rows(
                                              p['available_schedules'],
                                            ).map((s) => s['id']).toList(),
                                          }),
                                    ),
                              child: const Text(
                                'Assemble current team schedules',
                              ),
                            ),
                          ),
                        ),
                      if (_rows(p['history']).isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Earlier section hearings',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        for (final history in _rows(p['history']))
                          ExpansionTile(
                            title: Text(
                              'Attempt ${history['round']} · ${history['verdict']}',
                            ),
                            children: [
                              ListTile(
                                title: Text('${history['remarks']}'),
                                subtitle: Text(
                                  _rows(
                                        (history['snapshot']
                                            as Map?)?['systems'],
                                      )
                                      .map(
                                        (s) =>
                                            '${s['title']}: ${s['decision']}',
                                      )
                                      .join('\n'),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _inlineReview(Map<String, dynamic>? p) {
    if (p == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: error == null
            ? const LinearProgressIndicator()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(error!),
                  TextButton(
                    onPressed: load,
                    child: const Text('Retry shared system'),
                  ),
                ],
              ),
      );
    }
    final systems = _rows(p['systems']);
    final current =
        systems.where((s) => s['key'] == selectedSystem).firstOrNull ??
        systems.firstOrNull;
    final progress = p['review_progress'] as Map? ?? {};
    final accepted =
        progress['papers_accepted'] ??
        systems
            .where(
              (s) => _rows(s['papers']).any(
                (f) => f['is_current'] == true && f['status'] == 'accepted',
              ),
            )
            .length;
    final namesConfirmed =
        systems.length == 3 &&
        systems.every(
          (s) =>
              s['confirmed'] == true && '${s['title'] ?? ''}'.trim().isNotEmpty,
        );
    final secondary = DefensysTokens.textSecondaryOf(context);
    final brand = DefensysTokens.maroonTextOf(context);
    final verdict = '${p['verdict'] ?? ''}';
    final status = verdict.isNotEmpty
        ? verdict.replaceAll('_', ' ')
        : p['endorsed'] == true
        ? 'Shared papers cleared for hearing'
        : '$accepted of 3 papers accepted';
    return DefensysShadcnScope(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          border: Border.all(color: DefensysTokens.borderOf(context)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                const Text(
                  'Shared system review',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${p['section']} · ${p['stage_label']} · Attempt ${p['round']}',
              style: TextStyle(fontSize: 12, color: secondary),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 20,
              runSpacing: 6,
              children: [
                Text(
                  'Project manager: ${p['project_manager_name']}',
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
                Text(
                  '${p['scope'] == 'pit' ? 'Section instructor' : 'System reviewer'}: ${p['reviewer_name']}',
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
              ],
            ),
            _sharedAcknowledgment(p),
            const SizedBox(height: 16),
            SharedSystemSelectionBanner(project: p),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final system in systems)
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => setState(
                            () => selectedSystem = '${system['key']}',
                          ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: current?['key'] == system['key']
                          ? DefensysTokens.surfaceHigherOf(context)
                          : null,
                      foregroundColor: current?['key'] == system['key']
                          ? brand
                          : secondary,
                      side: BorderSide(
                        color: current?['key'] == system['key']
                            ? brand
                            : DefensysTokens.borderOf(context),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    icon: Icon(
                      system['key'] == p['selected_key']
                          ? Icons.check_circle_outline
                          : Icons.description_outlined,
                      size: 15,
                    ),
                    label: Text('System ${_letter(system['key'])}'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (current != null) _inlineSystem(current),
            Divider(height: 28, color: DefensysTokens.borderOf(context)),
            Text(
              p['shared_revisions_pending'] == true
                  ? 'Shared system revisions must be accepted and cleared before modules can proceed.'
                  : verdict.isNotEmpty
                  ? 'System outcome: ${verdict.replaceAll('_', ' ')}. ${p['remarks'] ?? ''}'
                  : p['endorsed'] == true
                  ? 'Shared papers are cleared for hearing. Each team needs its own module review and endorsement.'
                  : !namesConfirmed
                  ? 'Confirm the three system names, then accept their current concept papers.'
                  : accepted != 3
                  ? 'Accept all three current concept papers to clear the shared papers for hearing.'
                  : 'Confirmed titles and accepted current papers automatically clear the shared set for hearing.',
              style: TextStyle(fontSize: 12, height: 1.5, color: secondary),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (p['can_edit_names'] == true)
                  OutlinedButton.icon(
                    style: DefensysButtonStyles.secondary(context),
                    onPressed: busy ? null : () => editNames(),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: Text(
                      p['can_review'] == true || p['can_manage'] == true
                          ? 'Confirm system names'
                          : 'Propose system names',
                    ),
                  ),
                if (p['can_clear_shared_revisions'] == true)
                  FilledButton(
                    style: DefensysButtonStyles.primary(context),
                    onPressed: busy
                        ? null
                        : () async {
                            final remarks = await _remarks(
                              context,
                              'Clear shared system revisions',
                            );
                            if (remarks != null && mounted) {
                              await perform(
                                () => service.action(p, 'clear_revisions', {
                                  'remarks': remarks,
                                }),
                              );
                            }
                          },
                    child: const Text('Clear shared system revisions'),
                  ),
                if (p['can_decide'] == true)
                  FilledButton(
                    style: DefensysButtonStyles.primary(context),
                    onPressed: busy ? null : () => decide(),
                    child: const Text('Select section system'),
                  ),
                TextButton.icon(
                  style: DefensysButtonStyles.tertiary(context),
                  onPressed: busy ? null : load,
                  icon: const Icon(Icons.refresh, size: 15),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              p['scope'] == 'pit'
                  ? 'Title confirmation and paper acceptance clear the shared set for hearing. The assigned PIT Lead records the final system selection.'
                  : 'Title confirmation and paper acceptance clear the shared set for hearing. The panel chair records the final system selection.',
              style: TextStyle(fontSize: 11, height: 1.5, color: secondary),
            ),
            const SizedBox(height: 24),
            moduleReviews(p),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_rows(p['history']).isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Earlier system attempts'),
                children: [
                  for (final history in _rows(p['history']))
                    ListTile(
                      title: Text(
                        'Attempt ${history['round']} · ${history['verdict']}',
                      ),
                      subtitle: Text('${history['remarks']}'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _letter(dynamic key) => switch (key) {
    'c1' => 'A',
    'c2' => 'B',
    'c3' => 'C',
    _ => '$key',
  };

  Widget _inlineSystem(Map<String, dynamic> system) {
    final papers = _rows(system['papers']);
    final paper = papers.where((p) => p['is_current'] == true).firstOrNull;
    final secondary = DefensysTokens.textSecondaryOf(context);
    final status = switch (paper?['status']) {
      'accepted' => 'Accepted for hearing',
      'rejected' => 'Corrections requested',
      _ => paper == null ? 'Awaiting upload' : 'Awaiting review',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${system['title'] ?? ''}'.trim().isEmpty
              ? 'Awaiting system name'
              : '${system['title']}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          system['key'] == project!['selected_key']
              ? 'Selected system'
              : system['confirmed'] == true
              ? 'Name confirmed by faculty'
              : 'Name needs faculty confirmation',
          style: TextStyle(fontSize: 12, color: secondary),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceHigherOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.picture_as_pdf_outlined, size: 20, color: secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paper == null
                          ? 'Concept paper not submitted'
                          : '${paper['file_name']}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      paper == null
                          ? 'The section project manager uploads this paper.'
                          : 'Revision ${paper['revision']} · $status',
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if ('${paper?['feedback'] ?? ''}'.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Feedback: ${paper!['feedback']}',
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (paper != null)
              OutlinedButton.icon(
                style: DefensysButtonStyles.secondary(context),
                onPressed: busy ? null : () => viewPaper(paper),
                icon: const Icon(Icons.visibility_outlined, size: 15),
                label: const Text('Read paper'),
              ),
            if (paper != null &&
                (project!['can_review'] == true ||
                    system['can_review'] == true)) ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: DefensysTokens.saveActionBg,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                onPressed: busy || paper['status'] == 'accepted'
                    ? null
                    : () => perform(
                        () => service.action(project!, 'review', {
                          'paper_id': paper['id'],
                          'status': 'accepted',
                        }),
                      ),
                icon: const Icon(Icons.check, size: 15),
                label: const Text('Accept paper'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: DefensysTokens.maroonTextOf(context),
                ),
                onPressed: busy ? null : () => requestCorrections(paper),
                child: const Text('Request corrections'),
              ),
            ],
            if (system['can_upload'] == true)
              OutlinedButton.icon(
                style: DefensysButtonStyles.secondary(context),
                onPressed: busy ? null : () => upload(system),
                icon: const Icon(Icons.upload_file_outlined, size: 15),
                label: Text(
                  paper == null
                      ? 'Upload concept paper'
                      : 'Upload revised paper',
                ),
              ),
          ],
        ),
        if (papers.length > 1)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Previous paper versions (${papers.length - 1})',
              style: const TextStyle(fontSize: 12),
            ),
            children: [
              for (final old in papers.where((p) => p['is_current'] != true))
                ListTile(
                  dense: true,
                  title: Text(
                    '${old['file_name']} · Revision ${old['revision']}',
                  ),
                  trailing: const Icon(Icons.visibility_outlined, size: 16),
                  onTap: busy ? null : () => viewPaper(old),
                ),
            ],
          ),
      ],
    );
  }

  Widget _system(Map<String, dynamic> system) {
    final papers = _rows(system['papers']);
    final current = papers.where((p) => p['is_current'] == true).firstOrNull;
    final selected = project!['selected_key'] == system['key'];
    final keyStr = '${system['key']}';
    final letter = keyStr.substring(1) == '1'
        ? 'A'
        : (keyStr == 'c2' ? 'B' : 'C');
    final title = system['title'] == ''
        ? 'Awaiting proposal name'
        : system['title'];
    final isConfirmed = system['confirmed'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ShadCard(
        width: double.infinity,
        backgroundColor: selected
            ? const Color(0xFF720000).withValues(alpha: 0.03)
            : null,
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF720000).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: const Color(0xFF720000).withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                'System $letter',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF720000),
                ),
              ),
            ),
            Text(
              'System $letter · $title${selected ? ' · Selected' : ''}',
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (selected)
              const ShadBadge(
                backgroundColor: Color(0xFF16A34A),
                child: Text(
                  'Selected',
                  style: TextStyle(color: Colors.white, fontSize: 9.5),
                ),
              ),
            if (isConfirmed)
              const ShadBadge(
                child: Text(
                  'Faculty Confirmed',
                  style: TextStyle(fontSize: 9.5),
                ),
              )
            else
              const ShadBadge.secondary(
                child: Text(
                  'Pending Confirmation',
                  style: TextStyle(fontSize: 9.5),
                ),
              ),
          ],
        ),
        description: Text(
          isConfirmed
              ? 'Faculty-confirmed name'
              : 'Name awaiting faculty confirmation',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            if (current == null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Color(0xFFD97706),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Concept paper missing · Upload the shared system proposal manuscript.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.04)
                      : const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white12
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.picture_as_pdf_rounded,
                          size: 16,
                          color: Color(0xFF720000),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Revision ${current['revision']} · ${current['file_name'] ?? 'System Paper'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (current['status'] == 'accepted')
                          const ShadBadge(
                            backgroundColor: Color(0xFF16A34A),
                            child: Text(
                              'Accepted',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                              ),
                            ),
                          )
                        else if (current['status'] == 'rejected')
                          const ShadBadge.destructive(
                            child: Text(
                              'Revisions',
                              style: TextStyle(fontSize: 9.5),
                            ),
                          )
                        else
                          const ShadBadge.secondary(
                            child: Text(
                              'Pending Review',
                              style: TextStyle(fontSize: 9.5),
                            ),
                          ),
                      ],
                    ),
                    if ('${current['feedback']}'.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Feedback: ${current['feedback']}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (system['can_upload'] == true)
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: busy ? null : () => upload(system),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.upload_file_outlined, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          current == null
                              ? 'Upload concept paper'
                              : 'Upload revised paper',
                        ),
                      ],
                    ),
                  ),
                if (current != null)
                  ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    onPressed: busy ? null : () => viewPaper(current),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.visibility_outlined, size: 14),
                        SizedBox(width: 6),
                        Text('Read paper'),
                      ],
                    ),
                  ),
                if (current != null &&
                    (project!['can_review'] == true ||
                        system['can_review'] == true)) ...[
                  ShadButton(
                    size: ShadButtonSize.sm,
                    enabled: !busy && current['status'] != 'accepted',
                    onPressed: () => perform(
                      () => service.action(project!, 'review', {
                        'paper_id': current['id'],
                        'status': 'accepted',
                      }),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline, size: 14),
                        SizedBox(width: 6),
                        Text('Accept paper'),
                      ],
                    ),
                  ),
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    enabled: !busy,
                    onPressed: () => requestCorrections(current),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_note_rounded, size: 14),
                        SizedBox(width: 6),
                        Text('Request corrections'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            if (papers.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'Previous paper versions',
                    style: TextStyle(fontSize: 12),
                  ),
                  children: [
                    for (final paper in papers.where(
                      (p) => p['is_current'] != true,
                    ))
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.history_rounded, size: 16),
                        title: Text(
                          'Revision ${paper['revision']} · ${paper['status']}',
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 16),
                        onTap: busy ? null : () => viewPaper(paper),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProposalNamesDialog extends StatefulWidget {
  const _ProposalNamesDialog({required this.rows, required this.title});
  final List<Map<String, dynamic>> rows;
  final String title;
  @override
  State<_ProposalNamesDialog> createState() => _ProposalNamesDialogState();
}

class _ProposalNamesDialogState extends State<_ProposalNamesDialog> {
  late final controllers = [
    for (final row in widget.rows)
      TextEditingController(text: '${row['title']}'),
  ];
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 540,
      child: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                    controller: controllers[i],
                    maxLength: 255,
                    decoration: InputDecoration(
                      labelText:
                          'System ${String.fromCharCode(65 + i)}${widget.rows[i]['system_title'] == null ? '' : ' · ${widget.rows[i]['system_title']}'}',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter a proposal name.'
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, [
              for (var i = 0; i < widget.rows.length; i++)
                {
                  'key': widget.rows[i]['key'],
                  'title': controllers[i].text.trim(),
                },
            ]);
          }
        },
        child: const Text('Save names'),
      ),
    ],
  );
}

Future<String?> _remarks(BuildContext context, String title) =>
    showDialog<String>(
      context: context,
      builder: (_) => _RemarksDialog(title: title),
    );

class _RemarksDialog extends StatefulWidget {
  const _RemarksDialog({required this.title});
  final String title;
  @override
  State<_RemarksDialog> createState() => _RemarksDialogState();
}

class _RemarksDialogState extends State<_RemarksDialog> {
  final controller = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: Form(
        key: form,
        child: TextFormField(
          controller: controller,
          minLines: 3,
          maxLines: 7,
          maxLength: 5000,
          decoration: const InputDecoration(labelText: 'Required changes'),
          validator: (v) => v == null || v.trim().isEmpty
              ? 'Explain the required changes.'
              : null,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: const Text('Save feedback'),
      ),
    ],
  );
}

class _SectionDecisionDialog extends StatefulWidget {
  const _SectionDecisionDialog({
    required this.systems,
    required this.selectedKey,
    this.teamName,
    this.pit = false,
    this.module,
    this.onViewPaper,
  });
  final List<Map<String, dynamic>> systems;
  final String selectedKey;
  final String? teamName;
  final bool pit;
  final Map<String, dynamic>? module;
  final Future<void> Function(Map<String, dynamic>)? onViewPaper;
  @override
  State<_SectionDecisionDialog> createState() => _SectionDecisionDialogState();
}

class _SectionDecisionDialogState extends State<_SectionDecisionDialog> {
  String? selected;
  String verdict = 'approved';
  final notes = TextEditingController();
  final form = GlobalKey<FormState>();
  bool openingPaper = false;
  @override
  void initState() {
    super.initState();
    selected = widget.selectedKey.isEmpty ? null : widget.selectedKey;
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.teamName == null ? 'Select section system' : 'Review module',
    ),
    content: SizedBox(
      width: 560,
      child: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.module != null) ...[
                Text(
                  '${widget.teamName}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Selected section system',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.module!['system_title']}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Linked module', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  '${widget.module!['title']}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                for (final paper in _rows(widget.module!['documents']))
                  TextButton.icon(
                    onPressed: openingPaper || widget.onViewPaper == null
                        ? null
                        : () async {
                            setState(() => openingPaper = true);
                            try {
                              await widget.onViewPaper!(paper);
                            } finally {
                              if (mounted) setState(() => openingPaper = false);
                            }
                          },
                    icon: const Icon(Icons.description_outlined, size: 16),
                    label: Text(
                      '${paper['file_name']} · Revision ${paper['revision']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 20),
              ],
              if (widget.teamName == null && verdict != 'for_redefense')
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Selected system',
                  ),
                  items: [
                    for (final s in widget.systems)
                      DropdownMenuItem(
                        value: '${s['key']}',
                        child: Text(
                          '${s['title']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  validator: (v) => v == null ? 'Select one system.' : null,
                  onChanged: (v) => setState(() => selected = v),
                ),
              DropdownButtonFormField<String>(
                initialValue: verdict,
                decoration: InputDecoration(
                  labelText: widget.module == null
                      ? 'System decision'
                      : 'Module review',
                ),
                items: [
                  DropdownMenuItem(
                    value: 'approved',
                    child: Text(
                      !widget.pit
                          ? 'Approved'
                          : widget.module == null
                          ? 'Select system'
                          : 'Accept module',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'approved_with_revisions',
                    child: Text(
                      !widget.pit
                          ? 'Approved with revisions'
                          : widget.module == null
                          ? 'Select with revisions'
                          : 'Request module revisions',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'for_redefense',
                    child: Text(
                      !widget.pit
                          ? 'For re-defense'
                          : widget.module == null
                          ? 'Request replacement proposals'
                          : 'Request another module review',
                    ),
                  ),
                ],
                onChanged: openingPaper
                    ? null
                    : (v) => setState(() => verdict = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: notes,
                minLines: 3,
                maxLines: 6,
                maxLength: 5000,
                enabled: !openingPaper,
                decoration: InputDecoration(
                  labelText: widget.module == null
                      ? 'Selection notes / required revisions'
                      : 'Module feedback / required changes',
                ),
                validator: (v) =>
                    verdict != 'approved' && (v == null || v.trim().isEmpty)
                    ? 'Explain the required action.'
                    : null,
              ),
              Text(
                widget.module == null
                    ? 'This selection applies to the whole section. Each team’s linked module receives a separate review.'
                    : 'This review applies to the linked module for this team. Its grades and revision clearance remain separate.',
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: openingPaper ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: openingPaper
            ? null
            : () {
                if (!form.currentState!.validate()) return;
                final remarks = notes.text.trim();
                Navigator.pop(context, {
                  'verdict': verdict,
                  'remarks': remarks,
                  if (widget.teamName == null)
                    'concepts': [
                      for (final s in widget.systems)
                        {
                          'key': s['key'],
                          'decision': verdict == 'for_redefense'
                              ? 'rejected'
                              : s['key'] == selected
                              ? verdict
                              : 'not_selected',
                          'remarks':
                              verdict == 'for_redefense' || s['key'] == selected
                              ? remarks
                              : '',
                        },
                    ],
                });
              },
        child: Text(
          widget.module == null
              ? 'Save section decision'
              : 'Save module review',
        ),
      ),
    ],
  );
}

class _ResponsibilityDialog extends StatefulWidget {
  const _ResponsibilityDialog({required this.project});
  final Map<String, dynamic> project;
  @override
  State<_ResponsibilityDialog> createState() => _ResponsibilityDialogState();
}

class _ResponsibilityDialogState extends State<_ResponsibilityDialog> {
  late int? manager = widget.project['project_manager_id'] as int?;
  late int? reviewer = widget.project['reviewer_id'] as int?;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Section responsibilities'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            initialValue: manager,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Student project manager',
            ),
            items: [
              for (final p in _rows(widget.project['manager_options']))
                DropdownMenuItem(
                  value: p['id'] as int,
                  child: Text('${p['name']}'),
                ),
            ],
            onChanged: (v) => setState(() => manager = v),
          ),
          if (widget.project['reviewer_automatic'] == true)
            Text('Section instructor: ${widget.project['reviewer_name']}')
          else
            DropdownButtonFormField<int>(
              initialValue: reviewer,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'System faculty reviewer',
              ),
              items: [
                for (final p in _rows(widget.project['reviewer_options']))
                  DropdownMenuItem(
                    value: p['id'] as int,
                    child: Text('${p['name']}'),
                  ),
              ],
              onChanged: (v) => setState(() => reviewer = v),
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
        onPressed: manager == null || reviewer == null
            ? null
            : () => Navigator.pop(context, {
                'project_manager_id': manager,
                'reviewer_id': reviewer,
              }),
        child: const Text('Save responsibilities'),
      ),
    ],
  );
}
