import 'package:flutter/material.dart';
import 'section_concept_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../services/auth_provider.dart';
import '../../services/capstone_deliverables_provider.dart';
import '../../utils/universal_file_viewer.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import '../../theme/defensys_tokens.dart';
import '../../models/defense_workflow_labels.dart';

import 'pit_concept_decision_panel.dart';
import 'shared_concept_review.dart';
import 'proposal_names_editor.dart';
import 'proposal_name_review.dart';
import 'title_review_card.dart';
import 'concept_review_section.dart';
export 'concept_decision_fields.dart';
export 'pit_concept_decision_panel.dart';

class ConceptWorkspace extends ConsumerStatefulWidget {
  const ConceptWorkspace({
    super.key,
    required this.teamId,
    required this.stageLabel,
    required this.stage,
    this.onOpenSharedReview,
    this.paperContent,
    this.showTitleCard = true,
    this.paperBuilder,
    this.initialConceptKey,
    this.onReviewFiles,
  });
  final int teamId;
  final String stageLabel;
  final Map<String, dynamic> stage;
  final ValueChanged<int>? onOpenSharedReview;
  final Widget? paperContent;
  final Widget Function(String conceptKey)? paperBuilder;
  final String? initialConceptKey;
  final ValueChanged<String>? onReviewFiles;

  /// Student title management lives in the Team tab; retain hearing context here.
  final bool showTitleCard;
  @override
  ConsumerState<ConceptWorkspace> createState() => _ConceptWorkspaceState();
}

class _ConceptWorkspaceState extends ConsumerState<ConceptWorkspace> {
  final controllers = <String, TextEditingController>{};
  bool busy = false;
  String? error;
  bool editingNames = false;
  String? nameReviewToken;
  String? selectedConcept;
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
      '${widget.teamId}:${widget.stageLabel}:${workflow['round_id'] ?? workflow['round']}';
  @override
  void initState() {
    super.initState();
    resetControllers();
    selectedConcept = widget.initialConceptKey;
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
    if (oldWidget.initialConceptKey != widget.initialConceptKey &&
        widget.initialConceptKey != null) {
      selectedConcept = widget.initialConceptKey;
    }
    if ('${oldWidget.teamId}:${oldWidget.stageLabel}:${oldWorkflow['round_id'] ?? oldWorkflow['round']}' !=
            identity ||
        '${(oldWorkflow['concepts'] as List? ?? []).map((c) => c['key']).toList()}' !=
            '${concepts.map((c) => c['key']).toList()}' ||
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

  Future<bool> perform(Future<bool> Function() action) async {
    var saved = false;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ok = await action();
      saved = ok;
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
    return saved;
  }

  Widget compactReview(bool titlesEditable, bool shared, bool admin) {
    if (widget.paperBuilder != null && visibleConcepts.isEmpty) {
      return widget.paperBuilder!('');
    }
    if (widget.paperBuilder != null && visibleConcepts.isNotEmpty) {
      final visible = visibleConcepts;
      final active =
          visible.where((c) => c['key'] == selectedConcept).firstOrNull ??
          visible.first;
      final reviewSnapshot = workflow;
      final key = '${active['key']}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (shared)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Names: ${workflow['module_names_confirmed_count'] ?? concepts.where((c) => c['faculty_confirmed'] == true).length}/${concepts.length} confirmed',
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ),
          if (shared && widget.onOpenSharedReview != null)
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: openSharedWorkspace,
                child: const Text('Review shared systems'),
              ),
            ),
          if (visible.length > 1)
            ShadTabs<String>(
              scrollable: true,
              tabBarAlignment: Alignment.centerLeft,
              value: key,
              gap: 0,
              onChanged: (value) => setState(() => selectedConcept = value),
              tabs: [
                for (final c in visible)
                  ShadTab(
                    value: '${c['key']}',
                    child: Text(
                      'Concept ${'${c['key']}'.replaceFirst('c', '')}',
                    ),
                  ),
              ],
            ),
          if (shared)
            ProposalNameReview(
              key: ValueKey('module-name-$identity-$key'),
              title: '${active['title'] ?? ''}',
              linkedSystem: '${active['system_title'] ?? ''}',
              confirmed: active['faculty_confirmed'] == true,
              system: false,
              canConfirm: workflow['can_confirm_titles'] == true && !busy,
              onConfirm: (title) => perform(
                () => ref
                    .read(capstoneDeliverablesProvider.notifier)
                    .confirmConceptTitle(
                      widget.teamId,
                      widget.stageLabel,
                      conceptKey: key,
                      title: title,
                      roundId: reviewSnapshot['round_id'] as int,
                      reviewToken: '${reviewSnapshot['module_review_token']}',
                    ),
              ),
            )
          else ...[
            const SizedBox(height: 10),
            Text('${active['title'] ?? ''}', style: DefensysTokens.body),
            if (titlesEditable)
              Align(
                alignment: Alignment.centerLeft,
                child: ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () => setState(() => editingNames = true),
                  child: const Text('Edit concept names'),
                ),
              ),
            if (editingNames)
              ProposalNamesEditor(
                rows: visible,
                shared: false,
                busy: busy,
                onBack: () => setState(() => editingNames = false),
                onConfirm: (rows) async {
                  final ok = await perform(
                    () => ref
                        .read(capstoneDeliverablesProvider.notifier)
                        .conceptAction(
                          widget.teamId,
                          widget.stageLabel,
                          'save_titles',
                          concepts: rows,
                        ),
                  );
                  if (ok && mounted) setState(() => editingNames = false);
                },
              ),
          ],
          repeatInstructions(),
          widget.paperBuilder!(key),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!shared && workflow['decision_scope'] == 'pit')
            PitConceptDecisionPanel(
              teamId: widget.teamId,
              stageLabel: widget.stageLabel,
              workflow: workflow,
            ),
          ConceptHistory(workflow: workflow),
        ],
      );
    }
    final confirmed =
        concepts.isNotEmpty &&
        concepts.every((c) => c['faculty_confirmed'] == true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (editingNames)
          ProposalNamesEditor(
            key: ValueKey('names-$identity'),
            rows: visibleConcepts,
            lockedKeys: ref.read(authProvider).user?['role'] == 'student'
                ? {
                    for (final c in visibleConcepts)
                      if (c['faculty_confirmed'] == true) '${c['key']}',
                  }
                : {},
            shared: shared,
            busy: busy,
            onBack: () => setState(() => editingNames = false),
            onConfirm: (rows) async {
              final saved = await perform(
                () => ref
                    .read(capstoneDeliverablesProvider.notifier)
                    .conceptAction(
                      widget.teamId,
                      widget.stageLabel,
                      'save_titles',
                      concepts: [
                        for (final c in concepts)
                          rows
                                  .where((row) => row['key'] == c['key'])
                                  .firstOrNull ??
                              c,
                      ],
                      reviewToken: shared ? nameReviewToken : null,
                    ),
              );
              if (saved && mounted) setState(() => editingNames = false);
            },
          )
        else ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                shared
                    ? (confirmed
                          ? 'Module names confirmed'
                          : 'Module names need confirmation')
                    : 'Project concepts',
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
              if (titlesEditable)
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  enabled: !busy,
                  onPressed: () => setState(() {
                    nameReviewToken = workflow['module_review_token']
                        ?.toString();
                    editingNames = true;
                  }),
                  child: Text(
                    shared ? 'Complete module names' : 'Edit concept names',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          repeatInstructions(),
          widget.paperContent!,
        ],
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (!shared && workflow['decision_scope'] == 'pit')
          PitConceptDecisionPanel(
            teamId: widget.teamId,
            stageLabel: widget.stageLabel,
            workflow: workflow,
          ),
        if (admin &&
            workflow['can_edit'] == true &&
            workflow['clearance_valid'] != true)
          Align(
            alignment: Alignment.centerRight,
            child: ShadButton.ghost(
              size: ShadButtonSize.sm,
              enabled: !busy,
              onPressed: overrideClearance,
              child: const Text('Clearance exception'),
            ),
          ),
        ConceptHistory(workflow: workflow),
      ],
    );
  }

  Widget repeatInstructions() {
    final requested = concepts.where(
      (c) => '${c['panel_feedback'] ?? ''}'.trim().isNotEmpty,
    );
    if (requested.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final concept in requested) ...[
            Text(
              '${concept['requested_action'] == 'replace' ? 'Replace' : 'Revise'} · ${'${concept['title'] ?? ''}'.isEmpty ? concept['previous_title'] : concept['title']}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${concept['panel_feedback']}',
              style: TextStyle(color: DefensysTokens.textSecondaryOf(context)),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
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
                        'System ${systemLetter(c['key'])} · ${'${c['system_title'] ?? ''}'.trim().isEmpty ? 'Shared name pending' : c['system_title']}',
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

  Widget titleFirstReview() {
    final rows = visibleConcepts;
    if (rows.isEmpty) return const Text('No concept titles are configured.');
    final active =
        rows.where((c) => c['key'] == selectedConcept).firstOrNull ??
        rows.first;
    final key = '${active['key']}';
    final snapshot = workflow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${rows.where((c) => (c['title_review'] as Map?)?['state'] == 'accepted').length}/${rows.length} titles accepted',
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        if (workflow['section_project_id'] != null)
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.ghost(
              onPressed: openSharedWorkspace,
              child: const Text('Review shared systems'),
            ),
          ),
        if (rows.length > 1)
          ShadTabs<String>(
            value: key,
            scrollable: true,
            tabBarAlignment: Alignment.centerLeft,
            gap: 0,
            onChanged: (value) => setState(() => selectedConcept = value),
            tabs: [
              for (final row in rows)
                ShadTab(
                  value: '${row['key']}',
                  child: Text(
                    'Concept ${'${row['key']}'.replaceFirst('c', '')}',
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        ConceptReviewSection(
          onReviewFiles: widget.onReviewFiles == null
              ? null
              : () => widget.onReviewFiles!(key),
          titleReview: TitleReviewCard(
            key: ValueKey('title-$identity-$key'),
            concept: active,
            onAction: (action, title, reason) => perform(
              () => ref
                  .read(capstoneDeliverablesProvider.notifier)
                  .titleAction(
                    widget.teamId,
                    widget.stageLabel,
                    action,
                    conceptKey: key,
                    roundId: snapshot['round_id'] as int?,
                    reviewToken: '${snapshot['module_review_token']}',
                    title: title,
                    reason: reason,
                  ),
            ),
          ),
          deliverables: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.paperBuilder != null) widget.paperBuilder!(key),
              if (widget.paperContent != null) widget.paperContent!,
              if (widget.paperBuilder == null && widget.paperContent == null)
                Text(
                  'Review the supporting files in By team.',
                  style: TextStyle(
                    fontSize: 12,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
            ],
          ),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ConceptHistory(workflow: workflow),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showTitleCard) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.paperContent != null) widget.paperContent!,
          ConceptHistory(workflow: workflow),
        ],
      );
    }
    if (workflow['enabled'] == true &&
        (workflow['title_workflow_version'] == 2 ||
            concepts.any((concept) => concept['title_review'] is Map))) {
      return DefensysShadcnScope(child: titleFirstReview());
    }
    if (workflow['enabled'] != true) {
      return ConceptHistory(
        workflow: {'history': widget.stage['hearing_history']},
      );
    }
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
    if (widget.paperContent != null || widget.paperBuilder != null) {
      return DefensysShadcnScope(
        child: compactReview(titlesEditable, shared, admin),
      );
    }
    final confirmedCount = concepts
        .where((c) => c['faculty_confirmed'] == true)
        .length;
    final namesMissing = concepts.any(
      (c) => '${c['title'] ?? ''}'.trim().isEmpty,
    );
    if (!widget.showTitleCard ||
        (assigned &&
            !shared &&
            '${(workflow['config'] as Map?)?['assigned_title'] ?? ''}'
                .trim()
                .isNotEmpty)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConceptHistory(workflow: workflow),
          repeatInstructions(),
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
                        ? 'System ${systemLetter(keyStr)}'
                        : 'Concept ${keyStr.replaceFirst(RegExp(r'^c'), '')}';

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
                                  (faculty || c['faculty_confirmed'] != true) &&
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
                          if ('${c['panel_feedback'] ?? c['remarks'] ?? ''}'
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: DefensysTokens.surfaceHigherOf(context),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: DefensysTokens.borderOf(context),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 14,
                                    color: DefensysTokens.goldOf(context),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${c['requested_action'] == 'replace' ? 'Replacement requested' : 'Panel feedback'}: ${c['panel_feedback'] ?? c['remarks']}',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: DefensysTokens.textPrimaryOf(
                                          context,
                                        ),
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
    return DefensysShadcnScope(
      child: Column(
        children: [
          for (final round in history)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'Attempt ${round['round']} · ${'${round['verdict'] ?? ''}'.isEmpty ? 'Scheduled' : defenseProgressLabel('${round['verdict']}')}',
              ),
              children: [
                if ('${round['remarks'] ?? ''}'.isNotEmpty)
                  ListTile(title: Text('${round['remarks']}')),
                for (final c
                    in (round['concepts'] as List? ?? []).whereType<Map>())
                  ListTile(
                    title: Text('${c['title']}'),
                    subtitle: Text(
                      '${c['decision'] ?? ''}${c.containsKey('panel_score') ? ' · Panel: ${c['panel_score']}%' : ''}\n${c['remarks'] ?? ''}${c['next_action'] == null ? '' : '\nNext hearing: ${c['next_action'] == 'omit' ? 'Not requested' : c['next_action']}'}',
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
                        'Revision ${file['revision']} · ${file['status'] == 'accepted' ? 'Faculty accepted' : '${file['status'] ?? 'Submitted'}'} · Presented at this hearing',
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
      ),
    );
  }
}
