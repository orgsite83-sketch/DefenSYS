import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../panelist_models.dart';
import 'evaluation_score_input.dart';

class EvaluationReviewAction {
  const EvaluationReviewAction.submit() : submit = true, studentId = null;
  const EvaluationReviewAction.edit(this.studentId) : submit = false;
  final bool submit;
  final String? studentId;
}

class EvaluationReviewScreen extends StatelessWidget {
  const EvaluationReviewScreen({
    super.key,
    required this.team,
    required this.teamCriteria,
    required this.studentCriteria,
    required this.complete,
    this.conceptSubmissions = const [],
  });
  final TeamData team;
  final List<Criterion> teamCriteria;
  final Map<String, List<Criterion>> studentCriteria;
  final bool complete;
  final List<Map<String, dynamic>> conceptSubmissions;

  List<Widget> _conceptSections(BuildContext context) {
    final definitions = (team.panelRubric?['criteria'] as List? ?? []).whereType<Map>().toList();
    return [for (final concept in team.assessmentConcepts)
      Padding(padding: const EdgeInsets.only(top: 16), child: ShadCard(
        padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(concept['title'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final submission in conceptSubmissions.where((s) => s['concept_key'] == concept['key'])) ...[
            const SizedBox(height: 10),
            Text(submission['student_id'] == null ? 'Team criteria' : team.memberDetails.firstWhere((m) => m.id == submission['student_id'].toString()).name),
            for (final criterion in definitions.where((c) => team.targetType != 'both' || c['target_type'] == (submission['student_id'] == null ? 'team' : 'individual')))
              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
                Expanded(child: Text(criterion['name'].toString())),
                Text('${(submission['criteria_scores'] as List).whereType<Map>().where((s) => s['criterion_id'].toString() == criterion['id'].toString()).firstOrNull?['score'] ?? '—'} / ${criterion['max_score']}'),
              ])),
            if (submission['remarks']?.toString().isNotEmpty == true) Text(submission['remarks'].toString()),
          ],
        ]))),
    ];
  }

  Widget _section(
    BuildContext context,
    String label,
    List<Criterion> criteria,
    String? studentId,
  ) {
    final hasSections = criteria.any((c) => c.section.trim().isNotEmpty);
    final grouped = <String, List<Criterion>>{};
    for (final c in criteria) {
      final s = c.section.trim();
      grouped.putIfAbsent(s, () => []).add(c);
    }
    final isAllScored =
        criteria.isNotEmpty && criteria.every((criterion) => criterion.isScored);
    final totalScore = criteria.fold(0.0, (sum, c) => sum + (c.score ?? 0.0));
    final totalMax = criteria.fold(0.0, (sum, c) => sum + c.maxScore);
    final totalWeight = criteria.fold(0.0, (sum, c) => sum + (c.weight ?? 0.0));
    final effectiveTotalWeight = totalWeight > 0 ? totalWeight : 100.0;
    final weightedEarned = criteria.fold(
      0.0,
      (sum, c) =>
          sum +
          (c.maxScore > 0
              ? ((c.score ?? 0.0) / c.maxScore) * (c.weight ?? 0.0)
              : 0.0),
    );
    final weightedPct = (weightedEarned / effectiveTotalWeight) * 100.0;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ShadCard(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (!hasSections)
              for (final criterion in criteria)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(criterion.name)),
                      const SizedBox(width: 12),
                      Text(
                        '${criterion.isScored ? formatEvaluationScore(criterion.score!) : '—'} / ${formatEvaluationScore(criterion.maxScore)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                )
            else
              for (final entry in grouped.entries) ...[
                if (entry.key.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.maroonOf(context),
                          ),
                        ),
                        Text(
                          '${entry.value.fold<double>(0, (s, c) => s + (c.weight ?? 0)).toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final criterion in entry.value)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(criterion.name)),
                        const SizedBox(width: 12),
                        Text(
                          '${criterion.isScored ? formatEvaluationScore(criterion.score!) : '—'} / ${formatEvaluationScore(criterion.maxScore)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            if (isAllScored) ...[
              const Divider(height: 20),
              Text(
                'Total: ${formatEvaluationScore(totalScore)} / ${formatEvaluationScore(totalMax)} (${weightedPct.toStringAsFixed(1)}%)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if (!team.isPosted) ...[
              const SizedBox(height: 10),
              ShadButton.outline(
                height: 0,
                expands: true,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                key: ValueKey('review-edit-${studentId ?? 'team'}'),
                onPressed: () => Navigator.pop(
                  context,
                  EvaluationReviewAction.edit(studentId),
                ),
                child: Text('Edit $label'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Scaffold(
      backgroundColor: DefensysTokens.surfaceOf(context),
      appBar: AppBar(
        title: Text(team.isPosted ? 'Submitted grades' : 'Review grades'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            team.name,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(team.project),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(team.displayStage),
              if (team.scheduledDate != null)
                Text(DateFormat('MMM d, yyyy').format(team.scheduledDate!)),
              Text(team.formattedTime),
              Text(team.displayRoom),
            ],
          ),
          const SizedBox(height: 16),
          ShadAlert(
            title: Text(
              team.isPosted
                  ? 'Submitted'
                  : complete
                  ? 'Scores complete'
                  : 'Some scores are missing',
            ),
            description: Text(
              team.isPosted
                  ? team.isCapstone
                        ? 'Your scores are saved and locked.'
                        : 'Your scores are saved and locked. The PIT event result follows the final numeric grade.'
                  : complete
                  ? 'Check the team identity and each score before submitting.'
                  : 'Use Edit to finish the required criteria.',
            ),
          ),
          if (conceptSubmissions.isNotEmpty) ..._conceptSections(context),
          if (conceptSubmissions.isEmpty && teamCriteria.isNotEmpty)
            _section(context, 'Team criteria', teamCriteria, null),
          for (final member in conceptSubmissions.isEmpty ? team.memberDetails : <TeamMember>[])
            if ((studentCriteria[member.id] ?? []).isNotEmpty)
              _section(
                context,
                member.name,
                studentCriteria[member.id]!,
                member.id,
              ),
          if (team.targetType == 'both' && teamCriteria.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Team scores apply to every student and combine with their individual scores.',
                style: TextStyle(
                  fontSize: 12,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: team.isPosted
              ? ShadButton.outline(
                  height: 48,
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to grade sheet'),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ShadButton(
                      key: const ValueKey('submit-reviewed-grades'),
                      enabled: complete,
                      height: 0,
                      expands: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      backgroundColor: DefensysTokens.maroonOf(context),
                      foregroundColor: Colors.white,
                      onPressed: complete
                          ? () => Navigator.pop(
                              context,
                              const EvaluationReviewAction.submit(),
                            )
                          : null,
                      child: Text(
                        'Submit grades for ${team.name}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Submitting locks your scores for this defense.',
                      style: TextStyle(
                        fontSize: 12,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}
