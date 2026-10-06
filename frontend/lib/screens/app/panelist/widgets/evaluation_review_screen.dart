import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../panelist_models.dart';
import 'evaluation_score_picker.dart';

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
  });
  final TeamData team;
  final List<Criterion> teamCriteria;
  final Map<String, List<Criterion>> studentCriteria;
  final bool complete;

  Widget _section(
    BuildContext context,
    String label,
    List<Criterion> criteria,
    String? studentId,
  ) => Padding(
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
            ),
          if (criteria.every((criterion) => criterion.isScored)) ...[
            const Divider(height: 20),
            Text(
              'Total: ${formatEvaluationScore(criteria.fold(0.0, (sum, criterion) => sum + criterion.score!))} / ${formatEvaluationScore(criteria.fold(0.0, (sum, criterion) => sum + criterion.maxScore))}',
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
                  ? 'Submitted · Locked'
                  : complete
                  ? 'Scores complete'
                  : 'Some scores are missing',
            ),
            description: Text(
              team.isPosted
                  ? 'Your scores are saved and locked. The official verdict is separate.'
                  : complete
                  ? 'Check the team identity and each score before submitting.'
                  : 'Use Edit to finish the required criteria.',
            ),
          ),
          if (teamCriteria.isNotEmpty)
            _section(context, 'Team criteria', teamCriteria, null),
          for (final member in team.memberDetails)
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
