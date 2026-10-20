import 'package:flutter/material.dart';
import 'section_concept_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../services/auth_provider.dart';
import '../../services/capstone_deliverables_provider.dart';
import '../../utils/universal_file_viewer.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import '../../theme/defensys_tokens.dart';

import 'pit_concept_decision_panel.dart';
import 'shared_concept_review.dart';
export 'concept_decision_fields.dart';
export 'pit_concept_decision_panel.dart';

class ConceptWorkspace extends ConsumerStatefulWidget {
  const ConceptWorkspace({
    super.key,
    required this.teamId,
    required this.stageLabel,
    required this.stage,
    this.onOpenSharedReview,
  });
  final int teamId;
  final String stageLabel;
  final Map<String, dynamic> stage;
  final ValueChanged<int>? onOpenSharedReview;
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
  List<Map<String, dynamic>> get visibleConcepts {
    final key = '${workflow['section_selected_key'] ?? ''}';
    return isSharedConceptWorkflow(workflow) && key.isNotEmpty
        ? concepts.where((c) => c['key'] == key).toList()
        : concepts;
  }

  Future<void> openSharedWorkspace() async {
    final id = int.tryParse('${workflow['section_project_id'] ?? ''}');
    if (id == null) return;
    if (widget.onOpenSharedReview != null) {
      widget.onOpenSharedReview!(id);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SectionConceptWorkspace(projectId: id),
      ),
    );
    if (mounted) {
      await ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables();
    }
  }

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
        ((workflow['assigned'] == true ||
                workflow['section_project_id'] != null) &&
            '${oldWorkflow['concepts']}' != '${workflow['concepts']}')) {
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

  Future<void> reviewModules() async {
    final reviewToken = workflow['module_review_token']?.toString();
    final editors = {
      for (final c in concepts)
        '${c['key']}': TextEditingController(text: '${c['title'] ?? ''}'),
    };
    final form = GlobalKey<FormState>();
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (dialogContext) => DefensysShadcnScope(
        child: AlertDialog(
          title: const Text('Review & confirm modules'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Check each module name and its connection to the matching shared system. You can correct the names before confirming.',
                    ),
                    for (final c in visibleConcepts) ...[
                      const SizedBox(height: 18),
                      Text(
                        'System ${c['key'] == 'c1'
                            ? 'A'
                            : c['key'] == 'c2'
                            ? 'B'
                            : 'C'} · ${'${c['system_title'] ?? ''}'.trim().isEmpty ? 'Shared name pending' : c['system_title']}',
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: editors['${c['key']}'],
                        maxLength: 255,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Module name',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a module name.'
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(dialogContext, [
                    for (final c in concepts)
                      {...c, 'title': editors['${c['key']}']!.text.trim()},
                  ]);
                }
              },
              child: const Text('Confirm module names & connections'),
            ),
          ],
        ),
      ),
    );
    // Dialog fields finish their exit animation before their controllers retire.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    for (final editor in editors.values) {
      editor.dispose();
    }
    if (result != null && mounted) {
      await perform(
        () => ref
            .read(capstoneDeliverablesProvider.notifier)
            .conceptAction(
              widget.teamId,
              widget.stageLabel,
              'save_titles',
              concepts: result,
              reviewToken: reviewToken,
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
    final shared = workflow['section_project_id'] != null;
    final confirmedCount = concepts
        .where((c) => c['faculty_confirmed'] == true)
        .length;
    final namesMissing = concepts.any(
      (c) => '${c['title'] ?? ''}'.trim().isEmpty,
    );
    if (assigned &&
        !shared &&
        '${(workflow['config'] as Map?)?['assigned_title'] ?? ''}'
            .trim()
            .isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConceptHistory(workflow: workflow),
          if (workflow['decision_scope'] == 'pit')
            PitConceptDecisionPanel(
              teamId: widget.teamId,
              stageLabel: widget.stageLabel,
              workflow: workflow,
            ),
        ],
      );
    }
    final cleared = workflow['clearance_valid'] == true;
    final status = shared && editable
        ? '${confirmedCount == concepts.length
              ? 'Module names confirmed'
              : namesMissing
              ? 'Module names needed'
              : 'Module confirmation required'} · $confirmedCount/${concepts.length} confirmed'
        : switch (workflow['status']) {
            'concepts_needed' => 'Concepts needed',
            'replacement_concepts_needed' => 'Replacement concepts needed',
            'concept_review_pending' =>
              workflow['section_project_id'] != null
                  ? 'Module review pending'
                  : 'Concept review pending',
            'concept_endorsement_pending' => 'Awaiting endorsement',
            'shared_clearance_pending' => 'Awaiting shared paper clearance',
            'module_confirmation_pending' => 'Module confirmation required',
            'shared_acknowledgment_pending' => 'Review shared systems',
            'ready_to_schedule_redefense' => 'Ready to schedule re-defense',
            'ready_to_schedule' => 'Ready to schedule',
            'scheduled' => 'Hearing scheduled',
            'approved' => 'Concept approved',
            'approved_with_revisions' => 'Approved with revisions',
            'failed' => 'Failed',
            'project_rejected' => 'Project rejected',
            _ => 'Concept selection',
          };
    final conceptContent = DefensysShadcnScope(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ShadCard(
          width: double.infinity,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  shared &&
                          '${workflow['section_selected_key'] ?? ''}'.isNotEmpty
                      ? 'Linked module proposal'
                      : assigned
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
          description: Text(
            status,
            style: TextStyle(
              fontSize: 12.5,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white70
                  : const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              for (final c in visibleConcepts)
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
                                    ? const Color(
                                        0xFF4ADE80,
                                      ).withValues(alpha: 0.6)
                                    : const Color(0xFF86EFAC))
                              : (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white12
                                    : const Color(0xFFE5E7EB)),
                          width: 1.0,
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
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: DefensysTokens.maroonTextOf(context),
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
                                ShadBadge.secondary(
                                  child: Text(
                                    shared
                                        ? ('${c['title'] ?? ''}'.trim().isEmpty
                                              ? 'Name needed'
                                              : 'Needs confirmation')
                                        : 'Draft',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (shared && faculty) ...[
                            if ('${c['system_title'] ?? ''}'
                                .trim()
                                .isNotEmpty) ...[
                              Text(
                                '${c['system_title']}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: DefensysTokens.textSecondaryOf(
                                    context,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 5),
                            ],
                            Text(
                              '${c['title'] ?? ''}'.trim().isEmpty
                                  ? 'Module name needed'
                                  : '${c['title']}',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: DefensysTokens.textPrimaryOf(context),
                              ),
                            ),
                          ] else
                            ShadInput(
                              controller: controllers['${c['key']}'],
                              enabled:
                                  titlesEditable &&
                                  !busy &&
                                  !(shared && faculty),
                              minLines: 1,
                              maxLines: 2,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                              leading: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  '${c['key']}'.toUpperCase(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: DefensysTokens.maroonOf(context),
                                  ),
                                ),
                              ),
                              placeholder: Text(
                                assigned
                                    ? 'Awaiting administrator assignment'
                                    : isShared
                                    ? 'Enter proposed module title'
                                    : 'Enter proposed concept title',
                                style: const TextStyle(fontSize: 13),
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
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (titlesEditable && shared && faculty)
                      ShadButton.outline(
                        enabled: !busy,
                        onPressed: reviewModules,
                        child: Text(
                          confirmedCount == concepts.length
                              ? 'Edit module names'
                              : namesMissing
                              ? 'Set module names'
                              : 'Review & confirm modules',
                        ),
                      ),
                    if (titlesEditable && !(shared && faculty))
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
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        conceptContent,
        if (!shared && workflow['decision_scope'] == 'pit')
          PitConceptDecisionPanel(
            teamId: widget.teamId,
            stageLabel: widget.stageLabel,
            workflow: workflow,
          ),
      ],
    );
    if (!shared) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SharedTeamModuleSummary(
          workflow: workflow,
          onOpen: openSharedWorkspace,
        ),
        if (editable) conceptContent else ConceptHistory(workflow: workflow),
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
