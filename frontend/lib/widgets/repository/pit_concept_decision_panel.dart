import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../services/capstone_deliverables_provider.dart';
import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';
import 'concept_decision_fields.dart';
import 'shared_concept_review.dart';

class PitConceptDecisionPanel extends ConsumerStatefulWidget {
  const PitConceptDecisionPanel({
    super.key,
    required this.teamId,
    required this.stageLabel,
    required this.workflow,
  });
  final int teamId;
  final String stageLabel;
  final Map<String, dynamic> workflow;

  @override
  ConsumerState<PitConceptDecisionPanel> createState() =>
      _PitConceptDecisionPanelState();
}

class _PitConceptDecisionPanelState
    extends ConsumerState<PitConceptDecisionPanel> {
  List<Map<String, dynamic>> decisions = [];
  final notes = TextEditingController();
  bool busy = false;
  String? error;

  void reset() {
    decisions = (widget.workflow['concepts'] as List? ?? [])
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList();
    notes.text = widget.workflow['can_clear_concept_revisions'] == true
        ? ''
        : widget.workflow['decision_remarks']?.toString() ?? '';
    error = null;
  }

  @override
  void initState() {
    super.initState();
    reset();
  }

  @override
  void didUpdateWidget(covariant PitConceptDecisionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId ||
        oldWidget.stageLabel != widget.stageLabel ||
        oldWidget.workflow['decision_review_token'] !=
            widget.workflow['decision_review_token']) {
      reset();
    }
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> submit({bool clearRevisions = false}) async {
    if (busy) return;
    final selected = decisions
        .where(
          (c) =>
              ['approved', 'approved_with_revisions'].contains(c['decision']),
        )
        .toList();
    final outcome = selected.length == 1
        ? '${selected.single['decision']}'
        : 'for_redefense';
    String? validation = selected.length > 1
        ? 'Select exactly one concept.'
        : null;
    if (!clearRevisions) {
      validation ??= conceptDecisionError(
        decisions,
        outcome,
        requirePlan: true,
      );
      if (validation == null &&
          selected.isEmpty &&
          !decisions.any(
            (c) => ['rejected', 'revise'].contains(c['decision']),
          )) {
        validation =
            'Select one concept or request revisions or replacement concepts.';
      }
    }
    if (validation == null &&
        (clearRevisions || outcome != 'approved') &&
        notes.text.trim().isEmpty) {
      validation =
          'Describe the required changes or how the revisions were resolved.';
    }
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    final bool isSingle = decisions.length == 1;
    final token = widget.workflow['decision_review_token']?.toString();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => DefensysShadcnScope(
        child: ShadDialog(
          title: Text(
            clearRevisions
                ? 'Clear concept revisions?'
                : isSingle
                ? 'Save project verdict?'
                : 'Save concept decision?',
          ),
          description: Text(
            clearRevisions
                ? 'Record that the required concept changes have been reviewed and resolved.'
                : isSingle
                ? 'Submit official defense verdict for “${selected.isNotEmpty ? selected.single['title'] : (decisions.isNotEmpty ? decisions.first['title'] : '')}”.'
                : selected.isNotEmpty
                ? '“${selected.single['title']}” will become the team’s official project title.'
                : 'This records the current review and opens the next concept set. Earlier papers and feedback remain in the history.',
          ),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ShadButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                clearRevisions
                    ? 'Clear revisions'
                    : isSingle
                    ? 'Save verdict'
                    : 'Save decision',
              ),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saved = await ref
          .read(capstoneDeliverablesProvider.notifier)
          .conceptAction(
            widget.teamId,
            widget.stageLabel,
            clearRevisions ? 'clear_pit_revisions' : 'pit_decision',
            concepts: clearRevisions
                ? null
                : conceptDecisionsForOutcome(decisions, outcome),
            reason: notes.text.trim(),
            reviewToken: token,
          );
      if (mounted && !saved) {
        setState(
          () => error =
              ref.read(capstoneDeliverablesProvider).error ??
              'Could not save the concept decision.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not save the concept decision. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workflow = widget.workflow;
    if (isSharedConceptWorkflow(workflow)) return const SizedBox.shrink();
    final bool isSingle = decisions.length == 1;
    final manager = workflow['can_manage_decision'] == true;
    final recorded = '${workflow['decision'] ?? ''}'.isNotEmpty;
    final canClear = workflow['can_clear_concept_revisions'] == true;
    final canEdit = workflow['can_record_decision'] == true && !busy;
    final selectedTitle = '${workflow['selected_title'] ?? ''}';
    final secondary = DefensysTokens.textSecondaryOf(context);
    return DefensysShadcnScope(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ShadCard(
          key: const ValueKey('pit-concept-decision'),
          width: double.infinity,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  recorded
                      ? (isSingle
                            ? 'Team project verdict'
                            : 'Team concept decision')
                      : (isSingle
                            ? 'Team project verdict'
                            : 'Select team concept'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const ShadBadge.outline(child: Text('PIT Lead')),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isSingle
                    ? 'Evaluate this project proposal: determine whether it is approved, requires revisions, or needs re-defense.'
                    : 'Choose the official project topic for this team.',
                style: TextStyle(fontSize: 13, height: 1.5, color: secondary),
              ),
              const SizedBox(height: 16),
              if (recorded) ...[
                Text(
                  selectedTitle.isEmpty
                      ? (isSingle
                            ? 'Re-defense required'
                            : 'Another concept review is required')
                      : selectedTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  workflow['decision'] == 'approved_with_revisions'
                      ? workflow['concept_revisions_cleared'] == true
                            ? 'Approved · Revisions cleared'
                            : 'Approved · Revisions pending'
                      : selectedTitle.isEmpty
                      ? 'Review the feedback in the concept history.'
                      : (isSingle
                            ? 'Official project verdict'
                            : 'Selected concept'),
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
                if ('${workflow['decided_by_name'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Recorded by ${workflow['decided_by_name']}',
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                ],
                if ('${workflow['decision_remarks'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${workflow['decision_remarks']}',
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ] else if (!manager)
                Text(
                  'The assigned PIT Lead records the chosen concept after the panel evaluations are submitted.',
                  style: TextStyle(fontSize: 13, height: 1.5, color: secondary),
                )
              else ...[
                if (!canEdit) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 17,
                        color: secondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${workflow['decision_unavailable_reason'] ?? 'Complete the panel evaluations first.'}',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                ConceptVerdictFields(
                  concepts: decisions,
                  pit: true,
                  enabled: canEdit,
                  onChanged: (value) => setState(() {
                    decisions = value;
                    error = null;
                  }),
                ),
              ],
              if (manager && (!recorded || canClear)) ...[
                const SizedBox(height: 16),
                Text(
                  canClear ? 'Revision clearance notes' : 'Decision notes',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ShadInput(
                  controller: notes,
                  enabled: !busy && (canEdit || canClear),
                  minLines: 3,
                  maxLines: 5,
                  placeholder: Text(
                    canClear
                        ? 'Describe how the required revisions were resolved'
                        : 'Record the discussion and any required changes',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ShadButton(
                    enabled: !busy && (canEdit || canClear),
                    onPressed: () => submit(clearRevisions: canClear),
                    child: Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          busy
                              ? 'Saving…'
                              : canClear
                              ? 'Clear concept revisions'
                              : isSingle
                              ? 'Save project verdict'
                              : 'Save concept decision',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
