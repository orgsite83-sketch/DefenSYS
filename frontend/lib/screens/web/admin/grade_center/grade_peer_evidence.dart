import 'package:flutter/material.dart';

import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/table/table.dart';
import 'grade_table_values.dart';

/// Privileged, read-only received ratings. The API controls evidence visibility.
class GradePeerEvidence extends StatelessWidget {
  const GradePeerEvidence({super.key, required this.evidence, this.studentId});
  final List<GradeRow> evidence;
  final int? studentId;

  @override
  Widget build(BuildContext context) {
    final rows = evidence
        .where((row) => studentId == null || row['student_id'] == studentId)
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    final criteria = <String>{
      for (final row in rows)
        for (final criterion in gradeMaps(row['criteria']))
          '${criterion['criteriaName'] ?? criterion['criterion_name'] ?? 'Criterion'}',
    };
    Widget text(String label) => Text(
      label,
      style: TextStyle(
        fontSize: 12,
        color: DefensysTokens.textPrimaryOf(context),
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Received peer ratings',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Recorded ratings and rubric marks · Self-ratings are identified where present.',
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
          DefensysTableCard(
            child: DefensysDataTable<GradeRow>(
              items: rows,
              rowMinHeight: 56,
              columns: [
                if (studentId == null)
                  DefensysTableColumn(
                    title: 'Recipient',
                    minWidth: 190,
                    cellBuilder: (_, row, _) => text('${row['student_name']}'),
                  ),
                DefensysTableColumn(
                  title: 'Evaluator',
                  minWidth: 200,
                  cellBuilder: (_, row, _) => text('${row['evaluator_name']}'),
                ),
                DefensysTableColumn(
                  title: 'Rating type',
                  minWidth: 110,
                  cellBuilder: (_, row, _) =>
                      text(row['is_self'] == true ? 'Self' : 'Teammate'),
                ),
                for (final name in criteria)
                  DefensysTableColumn(
                    title: name,
                    minWidth: 155,
                    alignment: Alignment.centerRight,
                    cellBuilder: (_, row, _) {
                      final criterion = gradeMaps(row['criteria'])
                          .where(
                            (c) =>
                                '${c['criteriaName'] ?? c['criterion_name'] ?? 'Criterion'}' ==
                                name,
                          )
                          .firstOrNull;
                      final score = gradeNumber(criterion?['score']);
                      final maximum = gradeNumber(criterion?['max']);
                      return text(
                        score == null
                            ? '—'
                            : '${score.toStringAsFixed(2)} / ${maximum?.toStringAsFixed(2) ?? '—'}',
                      );
                    },
                  ),
                DefensysTableColumn(
                  title: 'Received rating',
                  minWidth: 140,
                  alignment: Alignment.centerRight,
                  cellBuilder: (_, row, _) => text(gradePercent(row['rating'])),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
