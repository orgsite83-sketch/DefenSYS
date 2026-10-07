import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../../services/academic/curriculum_explorer_provider.dart';
import '../../../../../theme/defensys_tokens.dart';

TextStyle _caption(BuildContext context) => TextStyle(
  fontSize: 12,
  height: 1.5,
  color: DefensysTokens.textSecondaryOf(context),
);

/// Final published grades are kept separate from role-specific rubric scores.
class CurriculumCohortSummary extends StatelessWidget {
  const CurriculumCohortSummary({
    super.key,
    required this.query,
    required this.data,
    required this.contextLabel,
    required this.projects,
  });
  final CurriculumExplorerQuery query;
  final Map<String, dynamic> data;
  final String? contextLabel;
  final bool projects;

  @override
  Widget build(BuildContext context) {
    final summary = data['assessment_summary'] is Map
        ? Map<String, dynamic>.from(data['assessment_summary'] as Map)
        : <String, dynamic>{};
    final score = explorerNumber(summary['score']);
    final total = (explorerNumber(data['projects_count']) ?? 0).toInt();
    final distribution = explorerRows(data['project_distribution']);
    final unclassified = distribution
        .where((r) => r['category'] == 'Unclassified')
        .fold(0, (sum, r) => sum + (explorerNumber(r['count']) ?? 0).toInt());
    final categories = distribution
        .where(
          (r) =>
              r['category'] != 'Unclassified' &&
              (explorerNumber(r['count']) ?? 0) > 0,
        )
        .length;
    final inProgress = explorerRows(
      data['annual_performance'],
    ).any((r) => r['academic_year'] == query.year && r['in_progress'] == true);
    final scope = query.scope == 'capstone'
        ? 'Capstone'
        : 'PIT · Year ${query.yearLevel}';
    final heading = projects
        ? 'Project research profile'
        : contextLabel ?? 'Assessment overview';
    final metric = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          projects ? 'Unique team projects' : 'Published average',
          style: _caption(context),
        ),
        const SizedBox(height: 4),
        Text(
          projects
              ? '$total'
              : score == null
              ? '—'
              : '${score.toStringAsFixed(1)}%',
          key: const ValueKey('cohort-primary-metric'),
          style: TextStyle(
            fontSize: 42,
            height: 1.1,
            letterSpacing: -1.5,
            fontWeight: FontWeight.w700,
            color: DefensysTokens.maroonTextOf(context),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          projects
              ? 'One project per team in the selected period.'
              : 'Latest published final grade per team in this assessment.',
          style: _caption(context),
        ),
      ],
    );
    final details = Wrap(
      spacing: 32,
      runSpacing: 20,
      children: projects
          ? [
              _metric(
                context,
                '${total - unclassified} / $total',
                'Computing focus estimated',
                'Supported by project documents',
              ),
              _metric(
                context,
                '$categories',
                'Computing focus areas',
                '$unclassified unresolved estimates',
              ),
            ]
          : [
              _metric(
                context,
                '${summary['assessed'] ?? 0} / ${summary['eligible'] ?? 0}',
                'Teams with published grades',
                'Selected stage or event',
              ),
              _metric(
                context,
                '${summary['pending'] ?? 0}',
                'Awaiting publication',
                'Missing grades excluded from average',
              ),
            ],
    );
    return ShadCard(
      key: const ValueKey('cohort-summary'),
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$scope · ${query.year.isEmpty ? 'All academic years' : query.year}',
                style: _caption(context).copyWith(fontWeight: FontWeight.w600),
              ),
              if (inProgress)
                Text(
                  'Year in progress',
                  style: _caption(
                    context,
                  ).copyWith(color: DefensysTokens.goldOf(context)),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            heading,
            style: TextStyle(
              fontSize: 21,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (_, c) => c.maxWidth < 780
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [metric, const SizedBox(height: 24), details],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 5, child: metric),
                      const SizedBox(width: 32),
                      Expanded(flex: 6, child: details),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    String value,
    String label,
    String detail,
  ) => Column(
    key: ValueKey('summary-$label-$value'),
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 25,
          height: 1.2,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      const SizedBox(height: 6),
      Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 3),
      Text(detail, style: _caption(context).copyWith(fontSize: 11)),
    ],
  );
}

class CurriculumReviewPriorities extends StatelessWidget {
  const CurriculumReviewPriorities({
    super.key,
    required this.criteria,
    required this.reference,
    required this.onCriterion,
  });
  final List<Map<String, dynamic>> criteria;
  final double reference;
  final ValueChanged<String> onCriterion;

  @override
  Widget build(BuildContext context) {
    final below =
        criteria.where((c) {
          final score = explorerNumber(c['score']);
          return score != null && score < reference;
        }).toList()..sort(
          (a, b) => explorerNumber(
            a['score'],
          )!.compareTo(explorerNumber(b['score'])!),
        );
    final pending = criteria
        .where((c) => explorerNumber(c['score']) == null)
        .toList();
    return ShadCard(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      title: const Text(
        'Review priorities',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      description: Text(
        'Based on the selected rubric results.',
        style: _caption(context),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${below.length} ${below.length == 1 ? 'criterion' : 'criteria'} below reference',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: below.isEmpty
                    ? DefensysTokens.textPrimaryOf(context)
                    : DefensysTokens.goldOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${reference.toStringAsFixed(0)}% analysis reference · separate from passing rules',
              style: _caption(context),
            ),
            if (below.isEmpty && pending.isEmpty) ...[
              const SizedBox(height: 16),
              Text(
                criteria.isEmpty
                    ? 'Choose an assessment with recorded rubric results to identify review priorities.'
                    : 'All recorded criterion averages meet the reference. Open a criterion to check individual team results.',
                style: _caption(context),
              ),
            ],
            for (final c in [...below, ...pending].take(3)) ...[
              const SizedBox(height: 12),
              ShadButton.ghost(
                key: ValueKey('review-${c['id']}'),
                width: double.infinity,
                height: 100,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                mainAxisAlignment: MainAxisAlignment.start,
                onPressed: () => onCriterion('${c['id']}'),
                child: Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${c['name']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        explorerNumber(c['score']) == null
                            ? 'Awaiting rubric scores'
                            : '${explorerNumber(c['score'])!.toStringAsFixed(1)}% average · ${c['below']} / ${c['assessed']} below reference',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _caption(context),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'View supporting results →',
                        style: _caption(
                          context,
                        ).copyWith(color: DefensysTokens.maroonTextOf(context)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (below.length + pending.length > 3) ...[
              const SizedBox(height: 8),
              Text(
                'Explore the full criterion list for more results.',
                style: _caption(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Grade bands describe the spread; they do not imply institutional verdicts.
class CurriculumGradeDistribution extends StatelessWidget {
  const CurriculumGradeDistribution({super.key, required this.summary});
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final scores = explorerRows(
      summary['teams'],
    ).map((t) => explorerNumber(t['score'])).whereType<double>().toList();
    final bands = [
      (0, 50, 'Below 50%'),
      (50, 75, '50–<75%'),
      (75, 90, '75–<90%'),
      (90, 101, '90–100%'),
    ];
    return ShadCard(
      key: const ValueKey('published-grade-distribution'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      title: const Text(
        'Published grade distribution',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      description: Text(
        '${scores.length} teams · selected assessment',
        style: _caption(context),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: scores.isEmpty
            ? Text(
                'No published grades yet. Recorded rubric scores remain available separately.',
                style: _caption(context),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (low, high, label) in bands)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Builder(
                        builder: (context) {
                          final count = scores
                              .where((s) => s >= low && s < high)
                              .length;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: _caption(context),
                                    ),
                                  ),
                                  Text(
                                    '$count',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Semantics(
                                label:
                                    '$label: $count of ${scores.length} teams',
                                child: SizedBox(
                                  height: 7,
                                  child: LayoutBuilder(
                                    builder: (_, c) => Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        width:
                                            c.maxWidth * count / scores.length,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: DefensysTokens.maroonOf(
                                            context,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  Text(
                    'Final grades across all evaluation sources. Bands describe score ranges.',
                    style: _caption(context).copyWith(fontSize: 11),
                  ),
                ],
              ),
      ),
    );
  }
}

class CurriculumClassificationStatus extends StatelessWidget {
  const CurriculumClassificationStatus({
    super.key,
    required this.count,
    required this.allUnclassified,
    required this.onView,
  });
  final int count;
  final bool allUnclassified;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('classification-status'),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: DefensysTokens.isDark(context)
          ? DefensysTokens.mistPanel
          : DefensysTokens.warningBg,
      border: Border.all(
        color: DefensysTokens.isDark(context)
            ? DefensysTokens.mistBorder
            : DefensysTokens.warningBorder,
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          LucideIcons.fileSearch,
          size: 23,
          color: DefensysTokens.goldOf(context),
        ),
        const SizedBox(height: 12),
        Text(
          '$count ${count == 1 ? 'project has' : 'projects have'} no supported category',
          style: const TextStyle(
            fontSize: 16,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          allUnclassified
              ? 'Category insights will appear when project documents support a computing category. Open a project to inspect its documents and classification reason.'
              : 'These projects remain in the total. Open their evidence to see why a category could not be assigned.',
          style: _caption(context),
        ),
        const SizedBox(height: 16),
        ShadButton.outline(
          key: const ValueKey('category-Unclassified'),
          size: ShadButtonSize.sm,
          onPressed: onView,
          trailing: const Icon(LucideIcons.arrowRight, size: 14),
          child: const Text('View unclassified'),
        ),
      ],
    ),
  );
}
