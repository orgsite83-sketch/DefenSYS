import 'package:flutter/material.dart';

import '../../../../theme/defensys_tokens.dart';
import '../grade_center_shared.dart' show asDouble, asInt, statusLabel;

/// A read-only view of the same records used by Evaluation & Grades.
class AcademicProgressCard extends StatelessWidget {
  const AcademicProgressCard({
    super.key,
    required this.grades,
    required this.stageLabels,
    required this.isCapstone,
    required this.isLoading,
    required this.onRetry,
    required this.onViewEvaluation,
    this.currentStage,
    this.error,
  });

  final List<Map<String, dynamic>> grades;
  final List<String> stageLabels;
  final bool isCapstone;
  final bool isLoading;
  final String? currentStage;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<Map<String, dynamic>> onViewEvaluation;

  @override
  Widget build(BuildContext context) {
    final ink = DefensysTokens.textPrimaryOf(context);
    final muted = DefensysTokens.textSecondaryOf(context);
    final rows = <(String, Map<String, dynamic>?)>[];
    final labels = stageLabels.where((label) => label.isNotEmpty).toSet();
    for (final label in labels) {
      final records = grades.where((grade) => grade['stage_label'] == label);
      if (records.isEmpty) {
        rows.add((label, null));
      } else {
        rows.addAll(records.map((grade) => (label, grade)));
      }
    }
    for (final grade in grades) {
      final label = grade['stage_label']?.toString() ?? '';
      if (!labels.contains(label)) {
        rows.add((
          label.isEmpty ? (isCapstone ? 'Defense stage' : 'PIT event') : label,
          grade,
        ));
      }
    }

    return Container(
      key: const ValueKey('academic-progress-card'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: DefensysTokens.panelOf(context),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.assessment_outlined,
                size: 18,
                color: DefensysTokens.maroonTextOf(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ACADEMIC PROGRESS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: ink,
                  ),
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isCapstone
                ? 'Stage grades and recorded defense outcomes.'
                : 'Event grades and evaluation outcomes.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 16),
          if (error != null) ...[
            Text(error!, style: TextStyle(fontSize: 13, color: muted)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: isLoading ? null : onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry grades'),
              ),
            ),
          ] else if (rows.isEmpty) ...[
            Text(
              isLoading
                  ? 'Loading evaluations…'
                  : 'No evaluations recorded yet.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            if (!isLoading) ...[
              const SizedBox(height: 4),
              Text(
                'Grades will appear here when evaluations are recorded.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ] else
            for (var index = 0; index < rows.length; index++) ...[
              if (index > 0) ...[
                const SizedBox(height: 16),
                Divider(height: 1, color: DefensysTokens.borderOf(context)),
                const SizedBox(height: 16),
              ],
              _stageRow(context, rows[index].$1, rows[index].$2),
            ],
        ],
      ),
    );
  }

  Widget _stageRow(
    BuildContext context,
    String label,
    Map<String, dynamic>? grade,
  ) {
    final ink = DefensysTokens.textPrimaryOf(context);
    final muted = DefensysTokens.textSecondaryOf(context);
    final finalized =
        grade?['is_officially_complete'] == true ||
        grade?['status'] == 'published';
    final score = asDouble(grade?['final_grade']);
    final verdict = grade?['verdict']?.toString() ?? '';
    final evaluated =
        grade != null &&
        (verdict.isNotEmpty ||
            [
              'panel_score',
              'adviser_score',
              'peer_score',
              'final_grade',
            ].any((key) => asDouble(grade[key]) != null) ||
            (asInt(grade['panel_evaluators_submitted']) ?? 0) > 0 ||
            (asInt(grade['peer_submissions_submitted']) ?? 0) > 0 ||
            (grade['breakdowns'] is List &&
                (grade['breakdowns'] as List).isNotEmpty));
    final evaluationStatus = finalized
        ? 'Finalized'
        : evaluated
        ? 'In progress'
        : 'Not evaluated';
    final semester = grade?['display_semester']?.toString() ?? '';
    final students = (grade?['peer_per_student'] as List? ?? const [])
        .whereType<Map>();
    final isAverage =
        ['individual', 'both'].contains(grade?['rubric_target_type']) ||
        students.any((student) => asDouble(student['final_grade']) != null);
    // Only use a recorded verdict, or a finalized backend result. A provisional
    // numeric score alone is not evidence that the team passed its defense.
    final result = grade?['result']?.toString() ?? '';
    final outcome = verdict.isNotEmpty
        ? (verdict == 'approved_with_revisions'
              ? 'Approved with Revisions'
              : statusLabel(verdict))
        : finalized &&
              [
                'passed',
                'failed',
                'for_redefense',
                'revisions_pending',
              ].contains(result)
        ? statusLabel(result)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  if (semester.isNotEmpty || label == currentStage) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (semester.isNotEmpty) semester,
                        if (label == currentStage)
                          isCapstone ? 'Current stage' : 'Current event',
                      ].join(' · '),
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
                  ],
                ],
              ),
            ),
            if (score != null) ...[
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isAverage
                        ? 'Team average'
                        : isCapstone
                        ? 'Stage grade'
                        : 'Event grade',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                  Text(
                    score.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (!finalized)
                    Text(
                      'Provisional',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.goldOf(context),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: finalized
                    ? DefensysTokens.successBg
                    : DefensysTokens.surfaceHigherOf(context),
                borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
              ),
              child: Text(
                evaluationStatus,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: finalized ? DefensysTokens.successText : muted,
                ),
              ),
            ),
            if (outcome != null)
              Text(
                '${isCapstone ? 'Defense' : 'Outcome'}: $outcome',
                style: TextStyle(fontSize: 12, color: ink),
              ),
          ],
        ),
        if (isAverage && score != null) ...[
          const SizedBox(height: 8),
          Text(
            'Individual grades are available in evaluation details.',
            style: TextStyle(fontSize: 11.5, color: muted),
          ),
        ],
        if (grade != null && asInt(grade['id']) != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => onViewEvaluation(grade),
              style: TextButton.styleFrom(
                foregroundColor: DefensysTokens.maroonTextOf(context),
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
              ),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward, size: 15),
              label: const Text(
                'View evaluation details',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
