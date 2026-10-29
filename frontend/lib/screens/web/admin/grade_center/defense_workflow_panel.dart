import 'package:defensys/widgets/repository/concept_workspace.dart';
import 'package:defensys/widgets/repository/section_concept_workspace.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/auth_provider.dart';
import '../../../../services/grade_center_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../config/api_config.dart';
import '../../../../services/authenticated_client.dart';
import '../../../../utils/universal_file_viewer.dart';
import '../../../../widgets/grading/automatic_assessment_panel.dart';

class DefenseWorkflowPanel extends ConsumerWidget {
  const DefenseWorkflowPanel({super.key, required this.grade, this.onUpdated});

  final Map<String, dynamic> grade;
  final VoidCallback? onUpdated;

  Future<void> _openFile(BuildContext context, WidgetRef ref, Map file) async {
    final uri = Uri.parse(ApiConfig.baseUrl).resolve('${file['file_url']}');
    try {
      final response = await ref.read(authenticatedHttpClientProvider).get(uri);
      if (!context.mounted) return;
      if (response.statusCode != 200) {
        showErrorToast(context, 'Unable to load this preserved project file.');
        return;
      }
      await viewFileInDialog(
        context: context,
        fileBytes: response.bodyBytes,
        fileName: '${file['name']}',
      );
    } catch (_) {
      if (context.mounted) {
        showErrorToast(context, 'Unable to load this preserved project file.');
      }
    }
  }

  Future<void> _action(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final titles = {
      'clear_revisions': 'Verify and clear required revisions',
      'schedule_compliance_review': 'Schedule a compliance review',
      'verify_redefense': 'Verify required re-defense corrections',
    };
    final heading = titles[action];
    if (heading == null) return;
    final reason = TextEditingController();
    DateTime? reviewDate;
    final review = action == 'schedule_compliance_review';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => DefensysShadcnScope(
          child: ShadDialog(
            constraints: const BoxConstraints(maxWidth: 560),
            title: Text(heading),
            description: Text(
              '${grade['team_name']} · ${grade['stage_label']}',
            ),
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ShadButton(
                onPressed:
                    (review
                        ? reviewDate != null
                        : reason.text.trim().isNotEmpty)
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: const Text('Save'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: SizedBox(
                width: 480,
                child: review
                    ? ShadButton.outline(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: reviewDate ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 1),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 730),
                            ),
                          );
                          if (date != null) update(() => reviewDate = date);
                        },
                        child: Text(
                          reviewDate?.toIso8601String().split('T').first ??
                              'Choose review date',
                        ),
                      )
                    : ShadInput(
                        controller: reason,
                        maxLines: 4,
                        placeholder: const Text(
                          'Verified corrections and evidence',
                        ),
                        onChanged: (_) => update(() {}),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    final body = <String, dynamic>{
      'action': action,
      'reason': reason.text.trim(),
      if (reviewDate != null)
        'review_date': reviewDate!.toIso8601String().split('T').first,
    };
    reason.dispose();
    if (saved != true || !context.mounted) return;
    final id = int.tryParse('${grade['id']}');
    if (id == null) return;
    final ok = await ref
        .read(gradeCenterProvider.notifier)
        .applyDefenseWorkflow(id, body);
    if (!context.mounted) return;
    if (!ok) {
      showErrorToast(
        context,
        ref.read(gradeCenterProvider).error ??
            'Unable to update defense workflow.',
      );
      return;
    }
    onUpdated?.call();
    showSuccessToast(context, 'Defense workflow updated.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (grade['scope'] != 'capstone') return const SizedBox.shrink();
    final user = ref.watch(authProvider).user ?? <String, dynamic>{};
    final workflow = Map<String, dynamic>.from(grade['workflow'] as Map? ?? {});
    final admin = user['role'] == 'admin' || user['is_superuser'] == true;
    final id = int.tryParse('${user['id']}');
    if ((workflow['outcome_rule'] as Map?)?['automatic'] == true) {
      return AutomaticAssessmentPanel(
        grade: grade,
        isChair: id != null && id == workflow['chair_id'],
        onUpdated: onUpdated,
      );
    }
    final chair = admin || id != null && id == workflow['chair_id'];
    final adviser = admin || id != null && id == workflow['adviser_id'];
    final busy = ref.watch(gradeCenterProvider).isSaving;
    final verdict = grade['verdict']?.toString() ?? '';
    final conceptWorkflow = workflow['concept_workflow'] as Map?;
    final failed = verdict == 'failed' || verdict == 'project_rejected';
    final revisions =
        verdict == 'approved_with_revisions' &&
        grade['revisions_cleared_at'] == null;
    final redefense = verdict == 'for_redefense';
    final published = grade['status'] == 'published';
    final policy = workflow['assessment_policy'] as Map? ?? const {};
    final progress = workflow['assessment_progress'] as Map?;
    final configured = policy['version'] == 1;
    final verificationPending =
        !configured &&
        grade['redefense_verification_required'] == true &&
        grade['redefense_verified_at'] == null;
    final filesPending = progress?['post_defense_complete'] == false;
    final selectionPending =
        progress?['display_status'] == 'awaiting_concept_selection';
    final heading = failed
        ? 'Participation closed as Failed'
        : revisions
        ? 'Revision clearance pending'
        : redefense
        ? (conceptWorkflow == null
              ? 'Graded re-defense required'
              : 'Concept re-defense · Attempt ${conceptWorkflow['round']}')
        : filesPending
        ? 'Approved · post-defense files pending'
        : selectionPending
        ? 'Select a qualifying concept'
        : published
        ? 'Stage complete · eligible for this stage’s archiving'
        : workflow['passed_and_cleared'] == true
        ? 'Approved and cleared · finish required grading and stage completion'
        : 'Awaiting panel evaluations and the chair verdict';
    final explanation = failed
        ? 'Returning students must join a new regular Capstone 1 intake. Previous assessments remain in History.'
        : revisions
        ? grade['scope'] == 'pit'
              ? 'Keep the hearing and its grades. Verify the required concept corrections before clearance.'
              : 'Keep all grades and the existing adviser. Verify the corrections; schedule a compliance presentation if needed.'
        : redefense && conceptWorkflow != null
        ? '${conceptWorkflow['next_step']} Score carry-over follows the configured stage policy.'
        : redefense && configured
        ? 'Submit the requested materials for faculty review and obtain a fresh adviser endorsement before scheduling. Panel assessment is repeated; adviser and peer scores follow the configured stage policy.'
        : redefense
        ? verificationPending
              ? 'The panel requested adviser verification of corrections before scheduling. The existing endorsement is retained.'
              : 'Schedule the next attempt directly. Retain adviser endorsement, adviser grades, and peer grades; redo panel assessment and verdict.'
        : filesPending
        ? 'The defense outcome is approved. Every configured required post-defense deliverable still needs acceptance before this stage is complete.'
        : selectionPending
        ? 'The panel chair selects one concept that meets the qualifying score. Its assessment contributes to the official grade once.'
        : published
        ? 'Archive this stage’s project records. Next-stage preparation is available after a passed and cleared result.'
        : 'Schedule dates control grading availability. Submitted evaluations, approval, and clearance determine completion.';
    final color = failed
        ? DefensysTokens.dangerText
        : revisions || redefense
        ? DefensysTokens.warningText
        : DefensysTokens.textPrimaryOf(context);
    Widget action(String label, String key) => OutlinedButton(
      onPressed: busy ? null : () => _action(context, ref, key),
      child: Text(label),
    );
    return Container(
      key: const ValueKey('defense-workflow-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: TextStyle(fontWeight: FontWeight.w600, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            explanation,
            style: TextStyle(color: DefensysTokens.textSecondaryOf(context)),
          ),
          if (grade['compliance_review_date'] != null) ...[
            const SizedBox(height: 6),
            Text('Compliance review: ${grade['compliance_review_date']}'),
          ],
          if (conceptWorkflow != null)
            DefensysShadcnScope(
              child: ConceptHistory(
                workflow: Map<String, dynamic>.from(conceptWorkflow),
              ),
            ),
          if (conceptWorkflow?['section_project_id'] != null) ...[
            if (conceptWorkflow?['section_revisions_pending'] == true)
              const Text(
                'Shared system revisions are pending. The designated system reviewer must clear them before progression.',
              ),
            TextButton.icon(
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('Open section system and module decisions'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SectionConceptWorkspace(
                    projectId: conceptWorkflow!['section_project_id'] as int,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (revisions && (chair || adviser) && !published) ...[
                action('Verify and clear revisions', 'clear_revisions'),
                if (grade['scope'] == 'capstone')
                  action(
                    'Schedule compliance review',
                    'schedule_compliance_review',
                  ),
              ],
              if (redefense &&
                  verificationPending &&
                  adviser &&
                  conceptWorkflow == null)
                action('Verify required corrections', 'verify_redefense'),
              if (admin &&
                  redefense &&
                  !failed &&
                  !verificationPending &&
                  (!configured || workflow['redefense_ready'] == true) &&
                  (conceptWorkflow == null ||
                      workflow['redefense_ready'] == true))
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => context.go(AdminRoutes.defenseScheduler),
                  child: const Text('Open Defense Scheduler'),
                ),
              if (admin &&
                  published &&
                  !filesPending &&
                  workflow['passed_and_cleared'] == true)
                OutlinedButton(
                  onPressed: () => context.go(AdminRoutes.projectArchive),
                  child: const Text('Open Project Archiving'),
                ),
            ],
          ),
          if ((workflow['previous_projects'] as List? ?? []).isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Previous project assessments'),
              children: [
                for (final raw in workflow['previous_projects'] as List)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${raw['title']} · ${raw['stage_label']}'),
                    subtitle: Text(
                      'Project ${raw['version']} · ${raw['verdict']}',
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        final old = await ref
                            .read(gradeCenterProvider.notifier)
                            .readHistoricalGrade(
                              int.parse('${raw['grade_id']}'),
                            );
                        if (!context.mounted) return;
                        if (old == null) {
                          showErrorToast(
                            context,
                            'Unable to load the previous project assessment.',
                          );
                          return;
                        }
                        await showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(
                              old['project_title']?.toString() ??
                                  'Previous project',
                            ),
                            content: SizedBox(
                              width: 500,
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${old['stage_label']} · ${old['verdict']}',
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Panel: ${old['panel_score'] ?? 'Pending'} · Adviser: ${old['adviser_score'] ?? 'Pending'} · Peer: ${old['peer_score'] ?? 'Pending'}',
                                    ),
                                    Text(
                                      'Final grade: ${old['final_grade'] ?? 'Pending'} · Attempts: ${old['attempt_count']}',
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      old['verdict_remarks']?.toString() ?? '',
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Preserved project files',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    for (final file
                                        in (old['workflow']?['project_files']
                                                as List? ??
                                            []))
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text('${file['name']}'),
                                        subtitle: Text(
                                          '${file['stage_label']} · ${file['status']}',
                                        ),
                                        trailing: file['file_url'] == null
                                            ? null
                                            : TextButton(
                                                onPressed: () => _openFile(
                                                  context,
                                                  ref,
                                                  file as Map,
                                                ),
                                                child: const Text('View file'),
                                              ),
                                      ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Preserved defense records',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    for (final record
                                        in (old['workflow']?['defense_records']
                                                as List? ??
                                            []))
                                      Text(
                                        '${record['stage_label']} · ${record['date']} · ${record['minutes_id'] == null ? 'No minutes' : 'Minutes #${record['minutes_id']}'}',
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('View'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
