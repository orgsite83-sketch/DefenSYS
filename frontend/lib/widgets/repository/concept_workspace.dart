import 'package:flutter/material.dart';
import 'section_concept_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../services/auth_provider.dart';
import '../../services/capstone_deliverables_provider.dart';
import '../../utils/universal_file_viewer.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'document_policy_editor.dart';

String? conceptDecisionError(
  List<Map<String, dynamic>> concepts,
  String verdict,
) {
  if (concepts.isEmpty) return null;
  final selected = <Map<String, dynamic>>[];
  for (final concept in concepts) {
    final decision = concept['decision'];
    if (!const [
      'approved',
      'approved_with_revisions',
      'rejected',
      'not_selected',
      'revise',
    ].contains(decision)) {
      return 'Choose a decision for every concept.';
    }
    if (const [
          'rejected',
          'revise',
          'approved_with_revisions',
        ].contains(decision) &&
        '${concept['remarks'] ?? ''}'.trim().isEmpty) {
      return 'Explain each rejected concept or required revision.';
    }
    if (decision == 'approved' || decision == 'approved_with_revisions') {
      selected.add(concept);
    }
  }
  if (verdict == 'approved' || verdict == 'approved_with_revisions') {
    if (selected.length != 1 || selected.single['decision'] != verdict) {
      return 'Select exactly one concept matching the hearing approval verdict.';
    }
  } else if (selected.isNotEmpty) {
    return 'An approved concept requires an approval verdict for this hearing.';
  }
  return null;
}

class ConceptWorkspace extends ConsumerStatefulWidget {
  const ConceptWorkspace({
    super.key,
    required this.teamId,
    required this.stageLabel,
    required this.stage,
  });
  final int teamId;
  final String stageLabel;
  final Map<String, dynamic> stage;
  @override
  ConsumerState<ConceptWorkspace> createState() => _ConceptWorkspaceState();
}

class _ConceptWorkspaceState extends ConsumerState<ConceptWorkspace> {
  final controllers = <String, TextEditingController>{};
  bool busy = false;
  String? error;
  Map<String, dynamic> get workflow =>
      Map<String, dynamic>.from(widget.stage['concept_workflow'] as Map? ?? {});
  List<Map<String, dynamic>> get concepts =>
      (workflow['concepts'] as List? ?? [])
          .whereType<Map>()
          .map((c) => Map<String, dynamic>.from(c))
          .toList();
  String get identity =>
      '${widget.teamId}:${widget.stageLabel}:${workflow['round']}';
  @override
  void initState() {
    super.initState();
    resetControllers();
  }

  void resetControllers() {
    for (final c in controllers.values) {
      c.dispose();
    }
    controllers.clear();
    for (final c in concepts) {
      controllers['${c['key']}'] = TextEditingController(
        text: '${c['title'] ?? ''}',
      );
    }
  }

  @override
  void didUpdateWidget(covariant ConceptWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldWorkflow = oldWidget.stage['concept_workflow'] as Map? ?? {};
    if ('${oldWidget.teamId}:${oldWidget.stageLabel}:${oldWorkflow['round']}' !=
        identity || (workflow['assigned'] == true && '${oldWorkflow['concepts']}' != '${workflow['concepts']}')) {
      resetControllers();
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> perform(Future<bool> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ok = await action();
      if (mounted && !ok) {
        setState(
          () => error =
              ref.read(capstoneDeliverablesProvider).error ??
              'Could not save the concept set.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> overrideClearance() async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => DefensysShadcnScope(
        child: ShadDialog(
          title: const Text('Override adviser clearance'),
          description: const Text(
            'Required papers must still be present. This exception is recorded with the concept attempt.',
          ),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ShadButton(
              onPressed: () {
                if (reason.text.trim().isNotEmpty) Navigator.pop(context, true);
              },
              child: const Text('Record exception'),
            ),
          ],
          child: ShadInput(
            controller: reason,
            minLines: 3,
            maxLines: 5,
            placeholder: const Text('Reason for the clearance exception'),
          ),
        ),
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok == true && mounted) {
      await perform(
        () => ref
            .read(capstoneDeliverablesProvider.notifier)
            .conceptAction(
              widget.teamId,
              widget.stageLabel,
              'override_clearance',
              reason: text,
            ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (workflow['enabled'] != true) return const SizedBox.shrink();
    final user = ref.watch(authProvider).user ?? {};
    final admin = user['role'] == 'admin' || user['is_superuser'] == true;
    final faculty = admin || user['role'] == 'faculty';
    final editable = workflow['can_edit'] == true;
    final titlesEditable = editable && workflow['can_edit_titles'] != false &&
        (faculty || (workflow['faculty_names_required'] != true && workflow['module_names_confirmed'] != true));
    final assigned = workflow['assigned'] == true;
    final cleared = workflow['clearance_valid'] == true;
    final status = switch (workflow['status']) {
      'concepts_needed' => 'Concepts needed',
      'replacement_concepts_needed' => 'Replacement concepts needed',
      'concept_review_pending' => 'Adviser review pending',
      'concept_endorsement_pending' => 'Awaiting endorsement',
      'ready_to_schedule_redefense' => 'Ready to schedule re-defense',
      'ready_to_schedule' => 'Ready to schedule',
      'scheduled' => 'Hearing scheduled',
      'approved' => 'Concept approved',
      'approved_with_revisions' => 'Approved with revisions',
      'failed' => 'Failed',
      'project_rejected' => 'Project rejected',
      _ => 'Concept selection',
    };
    return DefensysShadcnScope(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ShadCard(
          width: double.infinity,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  assigned ? 'Assigned concept review' : 'Concept hearing',
                ),
              ),
              ShadBadge.secondary(
                child: Text('Attempt ${workflow['round'] ?? 1}'),
              ),
            ],
          ),
          description: Text('$status\n${workflow['next_step'] ?? ''}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              if (workflow['section_project_id'] != null) ...[
                const Text('Propose one corresponding module for each shared system. Faculty confirms module names and connections.'),
                TextButton.icon(icon: const Icon(Icons.account_tree_outlined), label: const Text('Open shared system proposals'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
                    SectionConceptWorkspace(projectId: workflow['section_project_id'] as int)))),
              ],
              for (final c in concepts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ShadInput(
                    controller: controllers['${c['key']}'],
                    enabled: titlesEditable && !busy,
                    leading: Text('${c['key']}'.toUpperCase()),
                    placeholder: Text(
                      assigned
                          ? 'Awaiting administrator assignment'
                          : c['system_title'] != null ? 'Module for ${c['system_title'] == '' ? c['key'] : c['system_title']}'
                          : 'Proposed concept title',
                    ),
                  ),
                ),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (editable)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (titlesEditable)
                      ShadButton.outline(
                        enabled: !busy,
                        child: const Text('Save concept titles'),
                        onPressed: () => perform(
                          () => ref
                              .read(capstoneDeliverablesProvider.notifier)
                              .conceptAction(
                                widget.teamId,
                                widget.stageLabel,
                                'save_titles',
                                concepts: [
                                  for (final c in concepts)
                                    {
                                      ...c,
                                      'title':
                                          controllers['${c['key']}']?.text
                                              .trim() ??
                                          '',
                                    },
                                ],
                              ),
                        ),
                      ),
                    if (faculty && !cleared)
                      ShadButton(
                        enabled:
                            !busy && widget.stage['required_complete'] == true,
                        child: const Text('Endorse concept set'),
                        onPressed: () => perform(
                          () => ref
                              .read(capstoneDeliverablesProvider.notifier)
                              .endorseTeam(widget.teamId, widget.stageLabel),
                        ),
                      ),
                    if (admin && !cleared)
                      ShadButton.ghost(
                        enabled: !busy,
                        onPressed: overrideClearance,
                        child: const Text('Clearance exception'),
                      ),
                  ],
                ),
              if (cleared)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Clearance applies to these concept titles and document versions.',
                  ),
                ),
              ConceptHistory(workflow: workflow),
            ],
          ),
        ),
      ),
    );
  }
}

class ConceptHistory extends StatelessWidget {
  const ConceptHistory({super.key, required this.workflow});
  final Map<String, dynamic> workflow;
  @override
  Widget build(BuildContext context) {
    final history = (workflow['history'] as List? ?? [])
        .whereType<Map>()
        .toList();
    if (history.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final round in history)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Attempt ${round['round']} · ${'${round['verdict']}'.isEmpty ? 'Scheduled' : '${round['verdict']}'.replaceAll('_', ' ')}',
            ),
            children: [
              if ('${round['remarks'] ?? ''}'.isNotEmpty)
                ListTile(title: Text('${round['remarks']}')),
              for (final c
                  in (round['concepts'] as List? ?? []).whereType<Map>())
                ListTile(
                  title: Text('${c['title']}'),
                  subtitle: Text(
                    '${c['decision'] ?? ''}\n${c['remarks'] ?? ''}',
                  ),
                ),
              for (final group
                  in (round['documents'] as List? ?? []).whereType<Map>())
                for (final file
                    in (group['files'] as List? ?? []).whereType<Map>())
                  ListTile(
                    dense: true,
                    title: Text('${file['file_name']}'),
                    subtitle: Text(
                      'Revision ${file['revision']} · Presented at this hearing',
                    ),
                    trailing: ShadButton.ghost(
                      size: ShadButtonSize.sm,
                      onPressed: file['file_url'] == null
                          ? null
                          : () => viewFileInDialog(
                              context: context,
                              fileUrl: '${file['file_url']}',
                              fileName: '${file['file_name']}',
                            ),
                      child: const Text('View'),
                    ),
                  ),
              if ('${round['override_reason'] ?? ''}'.isNotEmpty)
                ListTile(
                  title: const Text('Clearance exception'),
                  subtitle: Text('${round['override_reason']}'),
                ),
            ],
          ),
      ],
    );
  }
}

class ConceptVerdictFields extends StatelessWidget {
  const ConceptVerdictFields({
    super.key,
    required this.concepts,
    required this.onChanged,
    this.enabled = true,
  });
  final List<Map<String, dynamic>> concepts;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Decisions for this concept set',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          'Select one approved concept for an approval verdict. If all are rejected, choose For re-defense to request replacement concepts.',
        ),
        for (var i = 0; i < concepts.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${concepts[i]['system_title'] == null ? '' : '${concepts[i]['system_title']} → '}${concepts[i]['title']}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                WorkflowChoice(
                  value: '${concepts[i]['decision'] ?? ''}',
                  enabled: enabled && (!concepts[i].containsKey('system_title') || concepts.any((c) => c['section_selected'] == true)),
                  options: {
                    '': 'Choose concept decision',
                    if (!concepts[i].containsKey('system_title') || concepts[i]['section_selected'] == true)
                      'approved': 'Approved concept',
                    if (!concepts[i].containsKey('system_title') || concepts[i]['section_selected'] == true)
                      'approved_with_revisions': 'Approved with revisions',
                    'rejected': 'Rejected',
                    'not_selected': 'Not selected',
                    'revise': 'Revise and present again',
                  },
                  onChanged: (v) {
                    final updated = [
                      for (final c in concepts) Map<String, dynamic>.from(c),
                    ];
                    updated[i]['decision'] = v;
                    onChanged(updated);
                  },
                ),
                const SizedBox(height: 6),
                ShadInput(
                  key: ValueKey('${concepts[i]['key']}-remarks'),
                  enabled: enabled,
                  initialValue: '${concepts[i]['remarks'] ?? ''}',
                  placeholder: const Text('Reason or required corrections'),
                  onChanged: (v) {
                    final updated = [
                      for (final c in concepts) Map<String, dynamic>.from(c),
                    ];
                    updated[i]['remarks'] = v;
                    onChanged(updated);
                  },
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
