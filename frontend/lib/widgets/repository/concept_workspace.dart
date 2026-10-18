import 'package:flutter/material.dart';
import 'section_concept_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../services/auth_provider.dart';
import '../../services/capstone_deliverables_provider.dart';
import '../../utils/universal_file_viewer.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import '../../theme/defensys_tokens.dart';
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
  bool reviewSharedSystem = false;
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
            identity ||
        (workflow['assigned'] == true &&
            '${oldWorkflow['concepts']}' != '${workflow['concepts']}')) {
      reviewSharedSystem = false;
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
    final titlesEditable =
        editable &&
        workflow['can_edit_titles'] != false &&
        (faculty ||
            (workflow['faculty_names_required'] != true &&
                workflow['module_names_confirmed'] != true));
    final assigned = workflow['assigned'] == true;
    final cleared = workflow['clearance_valid'] == true;
    final status = switch (workflow['status']) {
      'concepts_needed' => 'Concepts needed',
      'replacement_concepts_needed' => 'Replacement concepts needed',
      'concept_review_pending' =>
        workflow['section_project_id'] != null
            ? 'Module review pending'
            : 'Concept review pending',
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
    final content = DefensysShadcnScope(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ShadCard(
          width: double.infinity,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  assigned
                      ? 'Assigned concept review'
                      : workflow['section_project_id'] != null
                      ? 'Team module concepts'
                      : 'Concept hearing',
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
              for (final c in concepts)
                Builder(
                  builder: (context) {
                    final keyStr = '${c['key']}';
                    final isShared =
                        workflow['section_project_id'] != null ||
                        c['system_title'] != null;
                    final slotBadge = isShared
                        ? 'System ${keyStr == 'c1' ? 'A' : (keyStr == 'c2' ? 'B' : 'C')}'
                        : 'Concept ${keyStr == 'c1' ? '1' : (keyStr == 'c2' ? '2' : '3')}';

                    final decision = c['decision']?.toString();
                    final hasDecision = decision != null && decision.isNotEmpty;
                    final isConfirmed = c['faculty_confirmed'] == true;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.03)
                            : const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isConfirmed
                              ? (Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF4ADE80)
                                    : const Color(0xFF16A34A))
                              : (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white12
                                    : const Color(0xFFE5E7EB)),
                          width: isConfirmed ? 1.4 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF720000,
                                  ).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF720000,
                                    ).withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Text(
                                  slotBadge,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF720000),
                                  ),
                                ),
                              ),
                              if (hasDecision)
                                if (decision == 'approved' ||
                                    decision == 'approved_with_revisions')
                                  ShadBadge(
                                    backgroundColor: const Color(0xFF16A34A),
                                    child: Text(
                                      decision == 'approved'
                                          ? 'Approved'
                                          : 'Approved w/ Rev',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                      ),
                                    ),
                                  )
                                else if (decision == 'rejected')
                                  const ShadBadge.destructive(
                                    child: Text(
                                      'Rejected',
                                      style: TextStyle(fontSize: 10),
                                    ),
                                  )
                                else if (decision == 'revise')
                                  const ShadBadge.secondary(
                                    child: Text(
                                      'Revise',
                                      style: TextStyle(fontSize: 10),
                                    ),
                                  )
                                else
                                  ShadBadge.outline(
                                    child: Text(
                                      decision.replaceAll('_', ' '),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  )
                              else if (isConfirmed)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFF86EFAC),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_rounded,
                                        size: 10.5,
                                        color: Color(0xFF15803D),
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        'Confirmed',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF15803D),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                const ShadBadge.secondary(
                                  child: Text(
                                    'Draft',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ShadInput(
                            controller: controllers['${c['key']}'],
                            enabled: titlesEditable && !busy,
                            leading: Text('${c['key']}'.toUpperCase()),
                            placeholder: Text(
                              assigned
                                  ? 'Awaiting administrator assignment'
                                  : isShared
                                  ? 'Enter proposed module title'
                                  : 'Enter proposed concept title',
                            ),
                          ),
                          if (c['remarks'] != null &&
                              '${c['remarks']}'.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFFDE68A),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    size: 14,
                                    color: Color(0xFFD97706),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Feedback: ${c['remarks']}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF92400E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
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
                        child: Text(
                          workflow['section_project_id'] != null && faculty
                              ? 'Confirm module names'
                              : 'Save concept titles',
                        ),
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
    final projectId = int.tryParse('${workflow['section_project_id'] ?? ''}');
    if (!faculty || projectId == null) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final shared in [false, true])
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: reviewSharedSystem == shared
                        ? DefensysTokens.maroonTextOf(context)
                        : DefensysTokens.textSecondaryOf(context),
                    backgroundColor: reviewSharedSystem == shared
                        ? DefensysTokens.surfaceHigherOf(context)
                        : null,
                    side: BorderSide(
                      color: reviewSharedSystem == shared
                          ? DefensysTokens.maroonTextOf(context)
                          : DefensysTokens.borderOf(context),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  onPressed: () => setState(() => reviewSharedSystem = shared),
                  icon: Icon(
                    shared
                        ? Icons.account_tree_outlined
                        : Icons.groups_outlined,
                    size: 16,
                  ),
                  label: Text(shared ? 'Shared system' : 'Team modules'),
                ),
            ],
          ),
        ),
        if (reviewSharedSystem)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SectionConceptWorkspace(
              key: ValueKey('shared-review-$projectId'),
              projectId: projectId,
              embedded: true,
              onChanged: () => ref
                  .read(capstoneDeliverablesProvider.notifier)
                  .fetchDeliverables(),
            ),
          )
        else
          content,
      ],
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
                  enabled:
                      enabled &&
                      (!concepts[i].containsKey('system_title') ||
                          concepts.any((c) => c['section_selected'] == true)),
                  options: {
                    '': 'Choose concept decision',
                    if (!concepts[i].containsKey('system_title') ||
                        concepts[i]['section_selected'] == true)
                      'approved': 'Approved concept',
                    if (!concepts[i].containsKey('system_title') ||
                        concepts[i]['section_selected'] == true)
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
