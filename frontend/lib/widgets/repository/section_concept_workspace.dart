import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/academic/section_concept_service.dart';
import '../../services/auth/auth_provider.dart';
import '../../services/network/authenticated_client.dart';
import '../export/defensys_pdf_viewer.dart';

List<Map<String, dynamic>> _rows(dynamic value) => (value as List? ?? [])
    .whereType<Map>()
    .map((r) => Map<String, dynamic>.from(r))
    .toList();
String _error(Object error) => error.toString().replaceFirst('Exception: ', '');

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

class SectionConceptWorkspace extends ConsumerStatefulWidget {
  const SectionConceptWorkspace({super.key, required this.projectId});
  final int projectId;
  @override
  ConsumerState<SectionConceptWorkspace> createState() =>
      _SectionConceptWorkspaceState();
}

class _SectionConceptWorkspaceState
    extends ConsumerState<SectionConceptWorkspace> {
  Map<String, dynamic>? project;
  String? error;
  bool busy = false;
  SectionConceptService get service => ref.read(sectionConceptServiceProvider);
  @override
  void initState() {
    super.initState();
    Future.microtask(load);
  }

  Future<void> load() async {
    try {
      final result = await service.get(widget.projectId);
      if (mounted) {
        setState(() {
          project = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    }
  }

  Future<void> perform(Future<Map<String, dynamic>> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await action();
      if (mounted) setState(() => project = result);
    } catch (e) {
      if (mounted) setState(() => error = _error(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editNames({Map<String, dynamic>? team}) async {
    final rows = team == null
        ? _rows(project!['systems'])
        : _rows(team['concepts']);
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
        project!,
        team == null ? 'save_titles' : 'confirm_modules',
        {'concepts': titles, if (team != null) 'team_id': team['id']},
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
    });
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
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _SectionDecisionDialog(
        systems: _rows(project!['systems']),
        teamName: team?['name']?.toString(),
        selectedKey: '${project!['selected_key']}',
      ),
    );
    if (result == null || !mounted) return;
    await perform(
      () => service.action(
        project!,
        team == null ? 'decide' : 'module_verdict',
        {...result, if (team != null) 'team_id': team['id']},
      ),
    );
  }

  Future<void> reassign() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ResponsibilityDialog(project: project!),
    );
    if (result != null && mounted) {
      await perform(() => service.action(project!, 'reassign', result));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = project;
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
      body: p == null
          ? Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error!),
                        TextButton(onPressed: load, child: const Text('Retry')),
                      ],
                    ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      '${p['stage_label']} · Attempt ${p['round']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Project manager: ${p['project_manager_name']}\nSystem reviewer: ${p['reviewer_name']}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      p['verdict'] != ''
                          ? 'System outcome: ${p['verdict']}\n${p['remarks']}'
                          : p['endorsed'] == true
                          ? 'Shared papers endorsed. Each team also needs module clearance before scheduling.'
                          : 'Submit three shared system papers. Faculty confirms names, reviews each paper and endorses the set.',
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (p['can_edit_names'] == true)
                          OutlinedButton.icon(
                            onPressed: busy ? null : () => editNames(),
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(
                              p['can_manage'] == true
                                  ? 'Confirm system names'
                                  : 'Propose system names',
                            ),
                          ),
                        if (p['can_review'] == true)
                          FilledButton(
                            onPressed: busy || p['endorsed'] == true
                                ? null
                                : () => perform(
                                    () => service.action(p, 'endorse'),
                                  ),
                            child: const Text('Endorse shared papers'),
                          ),
                        if (p['can_manage'] == true &&
                            p['can_reassign'] == true)
                          TextButton(
                            onPressed: busy ? null : reassign,
                            child: const Text('Reassign responsibilities'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
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
                    for (final system in _rows(p['systems'])) _system(system),
                    const SizedBox(height: 20),
                    Text(
                      'Corresponding team modules',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Each team proposes one module for each system. The selected system determines which module may proceed.',
                    ),
                    for (final team in _rows(p['teams'])) _team(team),
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
                                    () =>
                                        service.action(p, 'schedule_hearing', {
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
                    if (p['can_decide'] == true)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          onPressed: busy ? null : () => decide(),
                          child: const Text('Record section system decision'),
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
                                _rows((history['snapshot'] as Map?)?['systems'])
                                    .map(
                                      (s) => '${s['title']}: ${s['decision']}',
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
    );
  }

  Widget _system(Map<String, dynamic> system) {
    final papers = _rows(system['papers']);
    final current = papers.where((p) => p['is_current'] == true).firstOrNull;
    final selected = project!['selected_key'] == system['key'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System ${'${system['key']}'.substring(1) == '1'
                ? 'A'
                : system['key'] == 'c2'
                ? 'B'
                : 'C'} · ${system['title'] == '' ? 'Awaiting proposal name' : system['title']}${selected ? ' · Selected' : ''}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            system['confirmed'] == true
                ? 'Faculty-confirmed name'
                : 'Name awaiting faculty confirmation',
          ),
          if (current == null)
            const Text('Concept paper missing')
          else ...[
            Text('Revision ${current['revision']} · ${current['status']}'),
            if ('${current['feedback']}'.isNotEmpty)
              Text('${current['feedback']}'),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (project!['can_upload'] == true ||
                  system['can_upload'] == true)
                OutlinedButton.icon(
                  onPressed: busy ? null : () => upload(system),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(
                    current == null
                        ? 'Upload concept paper'
                        : 'Upload revised paper',
                  ),
                ),
              if (current != null)
                TextButton(
                  onPressed: busy ? null : () => viewPaper(current),
                  child: const Text('Read paper'),
                ),
              if (current != null &&
                  (project!['can_review'] == true ||
                      system['can_review'] == true)) ...[
                TextButton(
                  onPressed: busy || current['status'] == 'accepted'
                      ? null
                      : () => perform(
                          () => service.action(project!, 'review', {
                            'paper_id': current['id'],
                            'status': 'accepted',
                          }),
                        ),
                  child: const Text('Accept paper'),
                ),
                TextButton(
                  onPressed: busy ? null : () => requestCorrections(current),
                  child: const Text('Request corrections'),
                ),
              ],
            ],
          ),
          if (papers.length > 1)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Previous paper versions'),
              children: [
                for (final paper in papers.where(
                  (p) => p['is_current'] != true,
                ))
                  ListTile(
                    title: Text(
                      'Revision ${paper['revision']} · ${paper['status']}',
                    ),
                    onTap: busy ? null : () => viewPaper(paper),
                  ),
              ],
            ),
          const Divider(height: 24),
        ],
      ),
    );
  }

  Widget _team(Map<String, dynamic> team) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${team['name']}', style: Theme.of(context).textTheme.titleMedium),
        for (final module in _rows(team['concepts']))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '${module['system_title'] == '' ? '${module['key']}'.toUpperCase() : module['system_title']} → ${module['title'] == '' ? 'Module name needed' : module['title']}'
              '${module['faculty_confirmed'] == true ? ' · Confirmed' : ' · Awaiting confirmation'}'
              '${module['decision'] == null || module['decision'] == '' ? '' : ' · ${module['decision']}'}'
              '${module['documents_status'] == null ? '' : '\nPapers: ${'${module['documents_status']}'.replaceAll('_', ' ')}'}',
            ),
          ),
        if (team['verdict'] != '')
          Text('Module hearing outcome: ${team['verdict']}'),
        Wrap(
          spacing: 8,
          children: [
            if (team['can_confirm_names'] == true &&
                team['schedule_id'] == null)
              TextButton(
                onPressed: busy ? null : () => editNames(team: team),
                child: const Text('Confirm module names'),
              ),
            if (team['can_issue_verdict'] == true)
              FilledButton(
                onPressed: busy ? null : () => decide(team: team),
                child: const Text('Record module outcome'),
              ),
          ],
        ),
      ],
    ),
  );
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
  });
  final List<Map<String, dynamic>> systems;
  final String selectedKey;
  final String? teamName;
  @override
  State<_SectionDecisionDialog> createState() => _SectionDecisionDialogState();
}

class _SectionDecisionDialogState extends State<_SectionDecisionDialog> {
  String? selected;
  String verdict = 'approved';
  final notes = TextEditingController();
  final form = GlobalKey<FormState>();
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
      widget.teamName == null
          ? 'Select the section system'
          : '${widget.teamName} · Module outcome',
    ),
    content: SizedBox(
      width: 560,
      child: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                decoration: const InputDecoration(labelText: 'Outcome'),
                items: const [
                  DropdownMenuItem(value: 'approved', child: Text('Approved')),
                  DropdownMenuItem(
                    value: 'approved_with_revisions',
                    child: Text('Approved with revisions'),
                  ),
                  DropdownMenuItem(
                    value: 'for_redefense',
                    child: Text('For re-defense'),
                  ),
                ],
                onChanged: (v) => setState(() => verdict = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: notes,
                minLines: 3,
                maxLines: 6,
                maxLength: 5000,
                decoration: const InputDecoration(
                  labelText: 'Panel feedback / required revisions',
                ),
                validator: (v) =>
                    verdict != 'approved' && (v == null || v.trim().isEmpty)
                    ? 'Explain the required action.'
                    : null,
              ),
              const Text(
                'System selection and team module approval are separate decisions. Each team retains its own assessment and outcome.',
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
        child: const Text('Record decision'),
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
