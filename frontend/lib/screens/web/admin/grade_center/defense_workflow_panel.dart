import 'package:flutter/material.dart';
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

class DefenseWorkflowPanel extends ConsumerWidget {
  const DefenseWorkflowPanel({
    super.key,
    required this.grade,
    this.onProjectReplaced,
    this.onUpdated,
  });

  final Map<String, dynamic> grade;
  final VoidCallback? onProjectReplaced;
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
      if (context.mounted)
        showErrorToast(context, 'Unable to load this preserved project file.');
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
      'authorize_retake': 'Authorize another attempt',
      'authorize_new_concept': 'Authorize a replacement concept',
      'keep_blocked': 'Keep failed / no further attempt',
    };
    final reason = TextEditingController();
    final title = TextEditingController();
    final form = GlobalKey<FormState>();
    DateTime? reviewDate;
    bool acknowledged = false;
    final replacement = action == 'authorize_new_concept';
    final review = action == 'schedule_compliance_review';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(titles[action]!),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${grade['team_name']} · ${grade['stage_label']}'),
                    const SizedBox(height: 12),
                    Text(
                      replacement
                          ? 'Keep the current adviser and team members. Preserve the old project, files, minutes, and assessments. The replacement starts at the first defense stage with fresh requirements and grades.'
                          : action == 'authorize_retake'
                          ? 'Record the institution’s authorization for another attempt in this stage. Keep the adviser, adviser grade, and peer grade; redo panel grades and the verdict. Progression stays blocked until approval and clearance.'
                          : review
                          ? 'This presentation verifies corrections. It retains the same attempt, verdict, and all grades. The chair must still save revision clearance.'
                          : action == 'keep_blocked'
                          ? 'Retain the failed outcome and withdraw any unused retake authorization. Scheduling and progression stay blocked.'
                          : 'Record the corrections and evidence you verified. All existing grades and adviser assignment are retained.',
                    ),
                    if (replacement) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: title,
                        maxLength: 255,
                        decoration: const InputDecoration(
                          labelText: 'Replacement concept title',
                        ),
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? 'Enter the new concept title.'
                            : null,
                      ),
                    ],
                    if (review) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
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
                          if (date != null) setState(() => reviewDate = date);
                        },
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(
                          reviewDate == null
                              ? 'Choose review date'
                              : reviewDate!.toIso8601String().split('T').first,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: reason,
                        minLines: 3,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText:
                              action.startsWith('authorize') ||
                                  action == 'keep_blocked'
                              ? 'Decision reason / authorization reference'
                              : 'Verified corrections and evidence',
                        ),
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? 'Record the decision or verified corrections.'
                            : null,
                      ),
                    ],
                    if (replacement)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'I understand that the replacement starts with fresh project grades and requirements.',
                        ),
                        value: acknowledged,
                        onChanged: (value) =>
                            setState(() => acknowledged = value ?? false),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  (replacement && !acknowledged) ||
                      (review && reviewDate == null)
                  ? null
                  : () {
                      if (form.currentState!.validate())
                        Navigator.pop(dialogContext, true);
                    },
              child: Text(review ? 'Schedule review' : 'Save decision'),
            ),
          ],
        ),
      ),
    );
    final body = <String, dynamic>{
      'action': action,
      'reason': reason.text.trim(),
      if (replacement) 'project_title': title.text.trim(),
      if (reviewDate != null)
        'review_date': reviewDate!.toIso8601String().split('T').first,
    };
    reason.dispose();
    title.dispose();
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
    if (replacement) onProjectReplaced?.call();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (grade['scope'] != 'capstone') return const SizedBox.shrink();
    final user = ref.watch(authProvider).user ?? <String, dynamic>{};
    final workflow = Map<String, dynamic>.from(grade['workflow'] as Map? ?? {});
    final admin = user['role'] == 'admin' || user['is_superuser'] == true;
    final id = int.tryParse('${user['id']}');
    final chair = admin || id != null && id == workflow['chair_id'];
    final adviser = admin || id != null && id == workflow['adviser_id'];
    final busy = ref.watch(gradeCenterProvider).isSaving;
    final verdict = grade['verdict']?.toString() ?? '';
    final failed = verdict == 'failed' || verdict == 'project_rejected';
    final revisions =
        verdict == 'approved_with_revisions' &&
        grade['revisions_cleared_at'] == null;
    final redefense = verdict == 'for_redefense';
    final authorized = workflow['retake_authorized'] == true;
    final verificationPending =
        grade['redefense_verification_required'] == true &&
        grade['redefense_verified_at'] == null;
    final published = grade['status'] == 'published';
    final heading = failed
        ? (authorized ? 'Another attempt authorized' : 'Progression blocked')
        : revisions
        ? 'Revision clearance pending'
        : redefense
        ? 'Graded re-defense required'
        : published
        ? 'Stage complete · eligible for this stage’s archiving'
        : workflow['passed_and_cleared'] == true
        ? 'Approved and cleared · finish required grading and stage completion'
        : 'Awaiting panel evaluations and the chair verdict';
    final explanation = failed
        ? authorized
              ? 'The authorized retake keeps adviser and peer grades. The previous failure remains in history.'
              : 'An admin must record an authorized recovery decision before another defense can be scheduled.'
        : revisions
        ? 'Keep all grades and the existing adviser. Verify the corrections; schedule a compliance presentation if needed.'
        : redefense
        ? verificationPending
              ? 'The panel requested adviser verification of corrections before scheduling. The existing endorsement is retained.'
              : 'Schedule the next attempt directly. Retain adviser endorsement, adviser grades, and peer grades; redo panel assessment and verdict.'
        : published
        ? 'Archive this stage’s project records. Next-stage preparation is available after a passed and cleared result.'
        : 'Schedule dates control grading availability. Submitted evaluations, approval, and clearance determine completion.';
    final color = failed || redefense
        ? DefensysTokens.dangerText
        : revisions
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
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (revisions && (chair || adviser) && !published) ...[
                action('Verify and clear revisions', 'clear_revisions'),
                action(
                  'Schedule compliance review',
                  'schedule_compliance_review',
                ),
              ],
              if (redefense && verificationPending && adviser)
                action('Verify required corrections', 'verify_redefense'),
              if (failed && admin) ...[
                if (verdict == 'failed' && !authorized)
                  action('Authorize another attempt', 'authorize_retake'),
                action(
                  'Authorize replacement concept',
                  'authorize_new_concept',
                ),
                action('Keep failed / no further attempt', 'keep_blocked'),
              ],
              if (admin && (authorized || redefense && !verificationPending))
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => context.go(AdminRoutes.defenseScheduler),
                  child: const Text('Open Defense Scheduler'),
                ),
              if (admin && published && workflow['passed_and_cleared'] == true)
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
          if ((workflow['recovery_history'] as List? ?? []).isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Recovery decisions'),
              children: [
                for (final raw in workflow['recovery_history'] as List)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${raw['action']} · ${raw['stage_label']}'),
                    subtitle: Text(
                      '${raw['reason']}\n${raw['authorized_by']} · ${raw['academic_period']}',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
