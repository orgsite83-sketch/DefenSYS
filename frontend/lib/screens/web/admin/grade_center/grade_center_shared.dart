import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/grade_center_provider.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/dialogs/confirm_dialog.dart';
import '../widgets/defensys_admin_shell.dart';

String gradeGroupKey(String scope, String stageLabel) =>
    '$scope|${stageLabel.trim()}';

String gradeGroupTitle(String groupKey) {
  final scope = groupKey.split('|').first;
  final label = groupKey.contains('|')
      ? groupKey.split('|').sublist(1).join('|')
      : 'Unscheduled';
  final prefix = scope == 'pit' ? 'PIT' : 'Capstone';
  return '$prefix · $label';
}

Map<String, List<Map<String, dynamic>>> groupGradesFromState(
  GradeCenterState state,
) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final grade in state.grades) {
    final scope = grade['scope']?.toString() ?? '';
    final label = grade['stage_label']?.toString() ?? '';
    final key = gradeGroupKey(scope, label);
    groups.putIfAbsent(key, () => []).add(grade);
  }

  // Include configured PIT events so they display in the list even with 0 teams
  if (state.scope == 'pit' || state.scope == 'all' || state.scope.isEmpty) {
    for (final event in state.pitEvents) {
      final eventName = event['event_name']?.toString() ?? '';
      if (eventName.isNotEmpty) {
        final key = gradeGroupKey('pit', eventName);
        groups.putIfAbsent(key, () => []);
      }
    }
  }
  final sortedKeys = groups.keys.toList()
    ..sort((a, b) {
      final aScope = a.split('|').first;
      final bScope = b.split('|').first;
      if (aScope != bScope) {
        return aScope == 'capstone' ? -1 : 1;
      }
      final aLabel = a.contains('|') ? a.split('|').sublist(1).join('|') : '';
      final bLabel = b.contains('|') ? b.split('|').sublist(1).join('|') : '';
      return aLabel.compareTo(bLabel);
    });
  return {for (final key in sortedKeys) key: groups[key]!};
}

const String kUnscheduledStageLabel = 'Unscheduled';

bool _isUnscheduledCapstoneGrade(Map<String, dynamic> grade) {
  if (grade['scope']?.toString() != 'capstone') return false;
  final label = grade['stage_label']?.toString() ?? '';
  return label.isEmpty || label == kUnscheduledStageLabel;
}

int unscheduledCapstoneTeamCount(GradeCenterState state) {
  return state.grades.where(_isUnscheduledCapstoneGrade).length;
}

Widget gradeCenterUnscheduledBanner({required int teamCount}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFFED7AA)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.event_busy_rounded,
          color: Color(0xFFD97706),
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$teamCount capstone team${teamCount == 1 ? '' : 's'} '
            'are unscheduled (no defense slot yet). Open Unscheduled below to grade or review.',
            style: const TextStyle(
              color: Color(0xFF92400E),
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

List<Map<String, dynamic>> gradesForGroup(
  GradeCenterState state,
  String scope,
  String stageLabel,
) {
  if (scope == 'capstone' && stageLabel == kUnscheduledStageLabel) {
    return state.grades.where(_isUnscheduledCapstoneGrade).toList();
  }
  return state.grades.where((grade) {
    return grade['scope']?.toString() == scope &&
        (grade['stage_label']?.toString() ?? '') == stageLabel;
  }).toList();
}

Map<String, dynamic> groupSettingsForKey(
  GradeCenterState state,
  String groupKey,
) {
  final raw = state.groupSettings[groupKey];
  if (raw != null) {
    return raw;
  }
  final scope = groupKey.split('|').first;
  final label = groupKey.contains('|')
      ? groupKey.split('|').sublist(1).join('|')
      : '';
  return {
    'scope': scope,
    'stage_label': label,
    'is_officially_complete': false,
    'peer_grading_enabled': false,
  };
}

Map<String, dynamic>? gradeById(GradeCenterState state, int gradeId) {
  for (final grade in state.grades) {
    if (asInt(grade['id']) == gradeId) {
      return grade;
    }
  }
  return null;
}

List<Map<String, dynamic>> parseBreakdowns(Map<String, dynamic> grade) {
  if (grade['breakdowns'] is! List) {
    return [];
  }
  return List<Map<String, dynamic>>.from(
    (grade['breakdowns'] as List).whereType<Map>().map(
      (item) => Map<String, dynamic>.from(item),
    ),
  );
}

List<Map<String, dynamic>> parsePeerPerStudent(Map<String, dynamic> grade) {
  if (grade['peer_per_student'] is! List) {
    return [];
  }
  return List<Map<String, dynamic>>.from(
    (grade['peer_per_student'] as List).whereType<Map>().map(
      (item) => Map<String, dynamic>.from(item),
    ),
  );
}

int? asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? asDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String statusLabel(String status) {
  return switch (status) {
    'published' => 'Published',
    'awaiting_peers' => 'Awaiting Peers',
    'approved' => 'Approved',
    'approved_with_revisions' => 'Approved w/ Revisions',
    'for_redefense' => 'For Re-defense',
    'passed' => 'Passed',
    'failed' => 'Failed',
    'pending' => 'Pending',
    _ => status.isEmpty ? 'Pending' : status,
  };
}

/// Workflow status or pass/fail outcome (75% threshold) when scores are complete.
String gradeDisplayStatus(Map<String, dynamic> grade) {
  final verdict = grade['verdict']?.toString() ?? '';
  if (verdict.isNotEmpty) {
    return verdict;
  }
  final workflow = grade['status']?.toString() ?? '';
  if (workflow == 'published' ||
      workflow == 'awaiting_peers') {
    return workflow;
  }
  if (asDouble(grade['final_grade']) != null) {
    final result = grade['result']?.toString() ?? '';
    if (result == 'passed' || result == 'failed' || result == 'for_redefense') {
      return result;
    }
    final finalGrade = asDouble(grade['final_grade'])!;
    return finalGrade >= 75 ? 'passed' : 'failed';
  }
  return workflow.isEmpty ? 'pending' : workflow;
}

String evaluationLabel(String value) {
  return switch (value) {
    'adviser' => 'Adviser Evaluation',
    'peer' => 'Peer Evaluation',
    _ => 'Panel Evaluation',
  };
}

String weightText(Map<String, dynamic> grade, String key) {
  final weights = grade['weights'];
  if (weights is Map) {
    return weights[key]?.toString() ?? '0';
  }
  return '0';
}

String scoreInput(dynamic value) {
  final score = asDouble(value);
  return score == null ? '' : score.toStringAsFixed(2);
}

dynamic scorePayload(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return double.tryParse(trimmed);
}

Widget scoreTextWidget(dynamic value) {
  final score = asDouble(value);
  return Text(
    score == null ? 'Pending' : score.toStringAsFixed(2),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: score == null ? const Color(0xFF98A2B3) : DefensysUi.textDark,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    ),
  );
}

Widget finalGradeTextWidget(Map<String, dynamic> grade) {
  final score = asDouble(grade['final_grade']);
  return Text(
    score == null ? '--' : score.toStringAsFixed(2),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: score == null
          ? const Color(0xFF98A2B3)
          : score >= 75
          ? const Color(0xFF10B981)
          : const Color(0xFFDC2626),
      fontSize: 13,
      fontWeight: FontWeight.w900,
    ),
  );
}

Widget teamDetailsWidget(
  Map<String, dynamic> grade, {
  bool showStageLabel = false,
}) {
  final attemptCount = (grade['attempt_count'] is int)
      ? grade['attempt_count'] as int
      : int.tryParse(grade['attempt_count']?.toString() ?? '1') ?? 1;

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              grade['team_name']?.toString() ?? '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: DefensysUi.textDark,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (attemptCount > 1) ...[
            const SizedBox(width: 6),
            attemptBadgeWidget(attemptCount),
          ],
        ],
      ),
      const SizedBox(height: 3),
      Text(
        grade['project_title']?.toString() ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF98A2B3),
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      if (showStageLabel &&
          (grade['stage_label']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(
          grade['stage_label']?.toString() ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: DefensysUi.primaryMaroon,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ],
  );
}

Widget statusChipWidget(String status) {
  return _statusChip(statusLabel(status), status);
}

Widget gradeStatusChipWidget(Map<String, dynamic> grade) {
  final status = gradeDisplayStatus(grade);
  return _statusChip(statusLabel(status), status);
}

Widget attemptBadgeWidget(int attemptCount) {
  if (attemptCount <= 1) return const SizedBox.shrink();
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFF6366F1).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3), width: 1),
    ),
    child: Text(
      'Attempt #$attemptCount',
      style: const TextStyle(
        color: Color(0xFF4F46E5),
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

Widget verdictBadgeWidget(String? verdict, {String? deadline}) {
  if (verdict == null || verdict.isEmpty) return const SizedBox.shrink();
  final color = switch (verdict) {
    'approved' => const Color(0xFF16A34A),
    'approved_with_revisions' => const Color(0xFFD97706),
    'for_redefense' => const Color(0xFFDC2626),
    _ => const Color(0xFF64748B),
  };
  final label = switch (verdict) {
    'approved' => 'Approved',
    'approved_with_revisions' => 'Approved with Revisions',
    'for_redefense' => 'For Re-defense',
    _ => verdict.replaceAll('_', ' ').toUpperCase(),
  };
  final icon = switch (verdict) {
    'approved' => Icons.check_circle_outline,
    'approved_with_revisions' => Icons.assignment_late_outlined,
    'for_redefense' => Icons.replay_outlined,
    _ => Icons.info_outline,
  };

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.30)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (deadline != null && deadline.isNotEmpty) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Due $deadline',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

Widget _statusChip(String label, String status) {
  final color = switch (status) {
    'published' => AppColors.success,
    'approved' => AppColors.success,
    'approved_with_revisions' => const Color(0xFFD97706),
    'passed' => AppColors.success,
    'for_redefense' => const Color(0xFFDC2626),
    'failed' => const Color(0xFFDC2626),
    'awaiting_peers' => Colors.blue,
    _ => AppColors.warning,
  };
  final icon = switch (status) {
    'published' => Icons.lock_outline,
    'approved' => Icons.check_circle_outline,
    'approved_with_revisions' => Icons.assignment_late_outlined,
    'passed' => Icons.check_circle_outline,
    'for_redefense' => Icons.replay_outlined,
    'failed' => Icons.cancel_outlined,
    'awaiting_peers' => Icons.people_outline,
    _ => Icons.hourglass_empty,
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class CriterionEvaluatorEntry {
  final String evaluatorName;
  final String? evaluatorRole;
  final int? studentId;
  final String? studentName;
  final String? studentUsername;
  final double score;
  final double maxScore;
  final double percentage;
  final String? comment;

  const CriterionEvaluatorEntry({
    required this.evaluatorName,
    this.evaluatorRole,
    this.studentId,
    this.studentName,
    this.studentUsername,
    required this.score,
    required this.maxScore,
    required this.percentage,
    this.comment,
  });

  bool get isIndividual =>
      studentId != null || (studentName != null && studentName!.trim().isNotEmpty);
}

class AggregatedCriterion {
  final String name;
  final double averageScore;
  final double maxScore;
  final double percentage;
  final int count;
  final List<CriterionEvaluatorEntry> evaluators;
  final bool isIndividual;
  final int distinctEvaluatorsCount;
  final int distinctStudentsCount;

  const AggregatedCriterion({
    required this.name,
    required this.averageScore,
    required this.maxScore,
    required this.percentage,
    required this.count,
    required this.evaluators,
    required this.isIndividual,
    required this.distinctEvaluatorsCount,
    required this.distinctStudentsCount,
  });
}

List<AggregatedCriterion> aggregateBreakdowns(
  List<Map<String, dynamic>> rows, {
  List<dynamic>? panelists,
}) {
  final panelistMap = <String, String>{};
  if (panelists != null) {
    for (final p in panelists) {
      if (p is Map) {
        final username = p['username']?.toString().trim() ?? '';
        final id = p['id']?.toString().trim() ?? '';
        final name = p['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) {
          if (username.isNotEmpty) panelistMap[username] = name;
          if (id.isNotEmpty) panelistMap[id] = name;
        }
      }
    }
  }

  final map = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final name = (row['criterion_name']?.toString() ?? 'Criterion').trim();
    map.putIfAbsent(name, () => []).add(row);
  }

  return map.entries.map((entry) {
    final group = entry.value;
    final count = group.length;
    final totalScore = group.fold<double>(
      0.0,
      (sum, r) => sum + (asDouble(r['score']) ?? 0.0),
    );
    final maxScore = asDouble(group.first['max_score']) ?? 10.0;
    final avgScore = count > 0 ? (totalScore / count) : 0.0;
    final pct = maxScore > 0
        ? (avgScore / maxScore * 100.0).clamp(0.0, 100.0)
        : 0.0;

    final evaluators = <CriterionEvaluatorEntry>[];
    final evaluatorNamesSet = <String>{};
    final studentNamesSet = <String>{};
    int unnamedIndex = 1;

    for (final row in group) {
      final score = asDouble(row['score']) ?? 0.0;
      final rowMax = asDouble(row['max_score']) ?? maxScore;
      final rowPct = rowMax > 0 ? (score / rowMax * 100.0).clamp(0.0, 100.0) : 0.0;

      final studentId = asInt(row['student_id'] ?? row['student']);
      final studentName = row['student_name']?.toString().trim();
      final studentUsername = row['student_username']?.toString().trim();

      if (studentName != null && studentName.isNotEmpty) {
        studentNamesSet.add(studentName);
      } else if (studentId != null) {
        studentNamesSet.add('Student #$studentId');
      }

      final raw = row['remarks']?.toString() ?? '';
      final lines = raw.split('\n');
      final firstLine = lines.first.trim();
      final rest = lines.sublist(1).join('\n').trim();

      String evaluatorName = '';
      if (firstLine.startsWith('Panelist:')) {
        final key = firstLine.substring('Panelist:'.length).trim();
        evaluatorName = panelistMap[key] ?? (key.isNotEmpty ? 'Panelist $key' : 'Panelist #$unnamedIndex');
      } else if (firstLine.startsWith('Guest panelist:')) {
        evaluatorName = firstLine.substring('Guest panelist:'.length).trim();
      } else if (firstLine.isNotEmpty && rest.isEmpty) {
        if (!firstLine.toLowerCase().startsWith('panelist:')) {
          evaluatorName = 'Evaluator #$unnamedIndex';
        }
      }

      if (evaluatorName.isEmpty) {
        evaluatorName = row['evaluator_name']?.toString() ??
            row['panelist_name']?.toString() ??
            'Evaluator #$unnamedIndex';
      }
      unnamedIndex++;
      evaluatorNamesSet.add(evaluatorName);

      final comment = rest.isNotEmpty
          ? rest
          : (raw.isNotEmpty && !raw.startsWith('Panelist:') && !raw.startsWith('Guest panelist:') ? raw : null);

      evaluators.add(
        CriterionEvaluatorEntry(
          evaluatorName: evaluatorName,
          studentId: studentId,
          studentName: (studentName != null && studentName.isNotEmpty) ? studentName : null,
          studentUsername: studentUsername,
          score: score,
          maxScore: rowMax,
          percentage: rowPct,
          comment: comment,
        ),
      );
    }

    final isIndividual = evaluators.any((e) => e.isIndividual);

    return AggregatedCriterion(
      name: entry.key,
      averageScore: avgScore,
      maxScore: maxScore,
      percentage: pct,
      count: count,
      evaluators: evaluators,
      isIndividual: isIndividual,
      distinctEvaluatorsCount: evaluatorNamesSet.length,
      distinctStudentsCount: studentNamesSet.length,
    );
  }).toList();
}

class ExpandableCriterionCard extends StatefulWidget {
  const ExpandableCriterionCard({
    super.key,
    required this.criterion,
    this.initiallyExpanded = false,
  });

  final AggregatedCriterion criterion;
  final bool initiallyExpanded;

  @override
  State<ExpandableCriterionCard> createState() => _ExpandableCriterionCardState();
}

class _ExpandableCriterionCardState extends State<ExpandableCriterionCard> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant ExpandableCriterionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiallyExpanded != widget.initiallyExpanded) {
      _isExpanded = widget.initiallyExpanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final crit = widget.criterion;
    final pct = crit.percentage;
    final scoreColor = pct >= 75
        ? const Color(0xFF059669)
        : pct >= 60
            ? const Color(0xFFD97706)
            : const Color(0xFFDC2626);
    final scoreBg = pct >= 75
        ? const Color(0xFFECFDF5)
        : pct >= 60
            ? const Color(0xFFFFFBEB)
            : const Color(0xFFFEF2F2);

    final hasMultiple = crit.evaluators.length > 1 ||
        (crit.evaluators.isNotEmpty && crit.evaluators.first.comment != null);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isExpanded ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header / Summary Row
          InkWell(
            onTap: hasMultiple
                ? () => setState(() => _isExpanded = !_isExpanded)
                : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    crit.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: crit.isIndividual
                                        ? const Color(0xFFF5F3FF)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: crit.isIndividual
                                          ? const Color(0xFFDDD6FE)
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Text(
                                    crit.isIndividual ? 'INDIVIDUAL' : 'TEAM',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                      color: crit.isIndividual
                                          ? const Color(0xFF7C3AED)
                                          : const Color(0xFF475569),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  crit.isIndividual
                                      ? '${crit.distinctEvaluatorsCount} evaluators × ${crit.distinctStudentsCount > 0 ? crit.distinctStudentsCount : 'all'} students'
                                      : 'Average from ${crit.count} panel evaluations',
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: _isExpanded
                                        ? const Color(0xFFDBEAFE)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _isExpanded ? 'Hide details' : '${crit.evaluators.length} grades',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: _isExpanded
                                              ? const Color(0xFF1D4ED8)
                                              : const Color(0xFF475569),
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        _isExpanded
                                            ? Icons.keyboard_arrow_up_rounded
                                            : Icons.keyboard_arrow_down_rounded,
                                        size: 13,
                                        color: _isExpanded
                                            ? const Color(0xFF1D4ED8)
                                            : const Color(0xFF475569),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: scoreBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: scoreColor.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          '${pct.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: scoreColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${crit.averageScore.toStringAsFixed(2)} / ${crit.maxScore.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (pct / 100.0).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Individual Breakdown Section (When expanded)
          if (_isExpanded && crit.evaluators.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          crit.isIndividual
                              ? Icons.grid_view_rounded
                              : Icons.how_to_reg_outlined,
                          size: 13,
                          color: const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          crit.isIndividual
                              ? 'STUDENT EVALUATION MATRIX'
                              : 'PANEL EVALUATIONS',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (crit.isIndividual)
                      _buildIndividualMatrixTable(crit)
                    else
                      _buildTeamEvaluationsList(crit),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIndividualMatrixTable(AggregatedCriterion crit) {
    // Extract distinct evaluators (ordered by first appearance)
    final evaluators = <String>[];
    for (final ev in crit.evaluators) {
      if (!evaluators.contains(ev.evaluatorName)) {
        evaluators.add(ev.evaluatorName);
      }
    }

    // Extract distinct students (ordered by first appearance)
    final students = <String>[];
    final studentMap = <String, Map<String, CriterionEvaluatorEntry>>{};
    final studentRemarks = <Map<String, String>>[];

    for (final ev in crit.evaluators) {
      final sName = ev.studentName ?? 'Student';
      if (!students.contains(sName)) {
        students.add(sName);
      }
      studentMap.putIfAbsent(sName, () => {})[ev.evaluatorName] = ev;

      if (ev.comment != null && ev.comment!.trim().isNotEmpty) {
        studentRemarks.add({
          'evaluator': ev.evaluatorName,
          'student': sName,
          'comment': ev.comment!.trim(),
        });
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
              dataRowMinHeight: 44,
              dataRowMaxHeight: 50,
              columnSpacing: 24,
              horizontalMargin: 16,
              dividerThickness: 1,
              columns: [
                const DataColumn(
                  label: Text(
                    'STUDENT MEMBER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
                ...evaluators.map((evalName) {
                  final initials = evalName
                      .trim()
                      .split(' ')
                      .map((s) => s.isNotEmpty ? s[0] : '')
                      .take(2)
                      .join()
                      .toUpperCase();
                  return DataColumn(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: const Color(0xFFEFF6FF),
                          child: Text(
                            initials.isEmpty ? 'P' : initials,
                            style: const TextStyle(
                              color: Color(0xFF2563EB),
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          evalName,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const DataColumn(
                  label: Text(
                    'STUDENT AVERAGE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ],
              rows: students.map((sName) {
                final evMap = studentMap[sName] ?? {};
                final sScores = evMap.values.toList();
                final sTotal = sScores.fold<double>(0.0, (sum, e) => sum + e.score);
                final sAvg = sScores.isNotEmpty ? (sTotal / sScores.length) : 0.0;
                final sPct = crit.maxScore > 0 ? (sAvg / crit.maxScore * 100.0).clamp(0.0, 100.0) : 0.0;

                final avgScoreColor = sPct >= 75
                    ? const Color(0xFF059669)
                    : sPct >= 60
                        ? const Color(0xFFD97706)
                        : const Color(0xFFDC2626);
                final avgScoreBg = sPct >= 75
                    ? const Color(0xFFECFDF5)
                    : sPct >= 60
                        ? const Color(0xFFFFFBEB)
                        : const Color(0xFFFEF2F2);

                return DataRow(
                  cells: [
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F3FF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.school_outlined,
                              size: 13,
                              color: Color(0xFF7C3AED),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            sName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...evaluators.map((evalName) {
                      final entry = evMap[evalName];
                      if (entry == null) {
                        return const DataCell(
                          Text('—', style: TextStyle(color: Color(0xFF94A3B8))),
                        );
                      }
                      final ePct = entry.percentage;
                      final eScoreColor = ePct >= 75
                          ? const Color(0xFF059669)
                          : ePct >= 60
                              ? const Color(0xFFD97706)
                              : const Color(0xFFDC2626);

                      return DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: eScoreColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '${entry.score.toStringAsFixed(1)} / ${entry.maxScore.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: eScoreColor,
                                ),
                              ),
                            ),
                            if (entry.comment != null && entry.comment!.trim().isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Tooltip(
                                message: '${entry.evaluatorName}: "${entry.comment}"',
                                child: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: avgScoreBg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: avgScoreColor.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              '${sPct.toStringAsFixed(0)}%',
                              style: TextStyle(
                                color: avgScoreColor,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${sAvg.toStringAsFixed(2)} / ${crit.maxScore.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        if (studentRemarks.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.rate_review_outlined, size: 13, color: Color(0xFF64748B)),
                    SizedBox(width: 5),
                    Text(
                      'REMARKS & FEEDBACK PER STUDENT',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...studentRemarks.map((r) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), height: 1.35),
                        children: [
                          TextSpan(
                            text: '${r['evaluator']} ',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                          ),
                          const TextSpan(
                            text: 'on ',
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                          TextSpan(
                            text: '${r['student']}: ',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7C3AED)),
                          ),
                          TextSpan(
                            text: '"${r['comment']}"',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTeamEvaluationsList(AggregatedCriterion crit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: crit.evaluators.asMap().entries.map((entry) {
        final idx = entry.key;
        final ev = entry.value;
        final evPct = ev.percentage;
        final evScoreColor = evPct >= 75
            ? const Color(0xFF059669)
            : evPct >= 60
                ? const Color(0xFFD97706)
                : const Color(0xFFDC2626);

        final initials = ev.evaluatorName
            .trim()
            .split(' ')
            .map((s) => s.isNotEmpty ? s[0] : '')
            .take(2)
            .join()
            .toUpperCase();

        return Container(
          padding: EdgeInsets.only(
            top: idx > 0 ? 8 : 0,
            bottom: idx < crit.evaluators.length - 1 ? 8 : 0,
          ),
          decoration: BoxDecoration(
            border: idx < crit.evaluators.length - 1
                ? const Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: const Color(0xFFEFF6FF),
                    child: Text(
                      initials.isEmpty ? 'P' : initials,
                      style: const TextStyle(
                        color: Color(0xFF2563EB),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      ev.evaluatorName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: evScoreColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${evPct.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: evScoreColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${ev.score.toStringAsFixed(1)} / ${ev.maxScore.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (evPct / 100.0).clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: const Color(0xFFF1F5F9),
                  valueColor: AlwaysStoppedAnimation<Color>(evScoreColor),
                ),
              ),
              if (ev.comment != null && ev.comment!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 11,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          ev.comment!,
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            height: 1.3,
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
      }).toList(),
    );
  }
}

Widget breakdownSectionWidget(
  String type,
  List<Map<String, dynamic>> rows, {
  List<dynamic>? panelists,
  bool? forceExpandAll,
}) {
  if (rows.isEmpty) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'No criterion breakdown posted yet.',
        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      ),
    );
  }

  final aggregated = aggregateBreakdowns(rows, panelists: panelists);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: aggregated.map((crit) {
      return ExpandableCriterionCard(
        key: ValueKey('${type}_${crit.name}_$forceExpandAll'),
        criterion: crit,
        initiallyExpanded: forceExpandAll ?? false,
      );
    }).toList(),
  );
}

Widget gradeFormulaLine(Map<String, dynamic> grade) {
  final isPit = grade['scope'] == 'pit';
  final panelScore = asDouble(grade['panel_score']);
  final adviserScore = asDouble(grade['adviser_score']);
  final peerScore = asDouble(grade['peer_score']);

  final panelWeight = asDouble(weightText(grade, 'panel')) ?? (isPit ? 70.0 : 50.0);
  final adviserWeight = asDouble(weightText(grade, 'adviser')) ?? (isPit ? 0.0 : 30.0);
  final peerWeight = asDouble(weightText(grade, 'peer')) ?? (isPit ? 30.0 : 20.0);

  final panelContrib = panelScore != null ? (panelScore * panelWeight / 100.0) : null;
  final adviserContrib = adviserScore != null ? (adviserScore * adviserWeight / 100.0) : null;
  final peerContrib = peerScore != null ? (peerScore * peerWeight / 100.0) : null;

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.calculate_outlined, size: 16, color: Color(0xFF2563EB)),
            SizedBox(width: 6),
            Text(
              'Calculation Formula (Passing threshold: 75.00%)',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _formulaBadge(
              'Panel',
              '${panelWeight.toStringAsFixed(0)}%',
              panelScore != null ? '${panelScore.toStringAsFixed(2)}%' : 'Pending',
              panelContrib != null ? '+${panelContrib.toStringAsFixed(2)} pts' : null,
              accentColor: const Color(0xFF2563EB),
            ),
            if (!isPit && adviserWeight > 0) ...[
              const Text('+', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
              _formulaBadge(
                'Adviser',
                '${adviserWeight.toStringAsFixed(0)}%',
                adviserScore != null ? '${adviserScore.toStringAsFixed(2)}%' : 'Pending',
                adviserContrib != null ? '+${adviserContrib.toStringAsFixed(2)} pts' : null,
                accentColor: const Color(0xFF059669),
              ),
            ],
            const Text('+', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
            _formulaBadge(
              'Peer',
              '${peerWeight.toStringAsFixed(0)}%',
              peerScore != null ? '${peerScore.toStringAsFixed(2)}%' : 'Pending',
              peerContrib != null ? '+${peerContrib.toStringAsFixed(2)} pts' : null,
              accentColor: const Color(0xFF7C3AED),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _formulaBadge(
  String label,
  String weight,
  String score,
  String? contrib, {
  Color accentColor = const Color(0xFF334155),
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: accentColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          contrib != null ? '$label ($weight): $contrib' : '$label ($weight): $score',
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
      ],
    ),
  );
}

class GradeBreakdownTableHeader extends StatelessWidget {
  const GradeBreakdownTableHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

Widget gradeCenterLockedBanner({required bool isLocked}) {
  if (!isLocked) return const SizedBox.shrink();
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Defense Event Completed & Finalized',
                style: TextStyle(
                  color: Color(0xFF1E293B),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Grades for this stage are locked. Evaluations and breakdowns are preserved for official academic records.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget gradeCenterPeerMemberTile(
  Map<String, dynamic> peer, {
  bool isLeader = false,
}) {
  final name = peer['student_name']?.toString() ?? 'Student';
  final initials = name.trim().split(' ').map((s) => s.isNotEmpty ? s[0] : '').take(2).join().toUpperCase();

  // Extract individual peer score from StudentStageGradeSerializer
  final score = asDouble(peer['peer_score']) ??
      asDouble(peer['normalized_score']) ??
      asDouble(peer['average_score']);

  final scoreColor = score == null
      ? const Color(0xFF94A3B8)
      : score >= 75
          ? const Color(0xFF059669)
          : score >= 60
              ? const Color(0xFFD97706)
              : const Color(0xFFDC2626);

  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.1),
          child: Text(
            initials.isEmpty ? 'S' : initials,
            style: const TextStyle(
              color: Color(0xFF7C3AED),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isLeader) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: const Text(
                        'LEADER',
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: score != null ? (score / 100.0).clamp(0.0, 1.0) : 0.0,
                  minHeight: 4,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              score == null ? 'Pending' : '${score.toStringAsFixed(1)}%',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: scoreColor,
              ),
            ),
            Text(
              score == null ? 'Not evaluated' : 'Peer Contribution',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget gradeCenterHeroSummaryCard({
  required Map<String, dynamic> grade,
}) {
  final finalGrade = asDouble(grade['final_grade']);
  final result = grade['result']?.toString() ??
      (finalGrade != null && finalGrade >= 75 ? 'passed' : 'pending');
  final status = gradeDisplayStatus(grade);
  final isPit = grade['scope'] == 'pit';

  final panelScore = asDouble(grade['panel_score']);
  final adviserScore = asDouble(grade['adviser_score']);
  final peerScore = asDouble(grade['peer_score']);

  final panelWeight = asDouble(weightText(grade, 'panel')) ?? (isPit ? 70.0 : 50.0);
  final adviserWeight = asDouble(weightText(grade, 'adviser')) ?? (isPit ? 0.0 : 30.0);
  final peerWeight = asDouble(weightText(grade, 'peer')) ?? (isPit ? 30.0 : 20.0);

  final panelContrib = panelScore != null ? (panelScore * panelWeight / 100.0) : null;
  final adviserContrib = adviserScore != null ? (adviserScore * adviserWeight / 100.0) : null;
  final peerContrib = peerScore != null ? (peerScore * peerWeight / 100.0) : null;

  final stageLabel = grade['stage_label']?.toString() ?? 'Defense Stage';
  final semester = grade['display_semester']?.toString() ?? '';
  final adviserName = grade['adviser_name']?.toString() ?? '';
  final panelistsList = grade['panelists'] is List ? (grade['panelists'] as List) : [];

  return DefensysCard(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final headerInfo = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Text(
                        isPit ? 'PIT EVENT' : 'CAPSTONE DEFENSE',
                        style: const TextStyle(
                          color: Color(0xFF1D4ED8),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    if (stageLabel.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          stageLabel,
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (semester.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          semester,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    if (!isPit && asInt(grade['attempt_count']) != null && (asInt(grade['attempt_count']) ?? 1) > 1)
                      attemptBadgeWidget(asInt(grade['attempt_count']) ?? 1),
                    if (!isPit)
                      defenseMinutesStatusBadgeWidget(grade),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  grade['team_name']?.toString() ?? 'Team',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.4,
                  ),
                ),
                if ((grade['project_title']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    grade['project_title']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    if (adviserName.isNotEmpty && !isPit)
                      _metaIconLabel(Icons.school_outlined, 'Adviser: $adviserName'),
                    if (panelistsList.isNotEmpty)
                      _metaIconLabel(Icons.gavel_outlined, '${panelistsList.length} Panelists Assigned'),
                    _metaIconLabel(Icons.flag_outlined, 'Passing Mark: 75.00%'),
                  ],
                ),
              ],
            );

            final scoreCallout = Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: isWide ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'FINAL GRADE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        finalGrade == null ? '--' : finalGrade.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                          color: finalGrade == null
                              ? const Color(0xFF94A3B8)
                              : finalGrade >= 75
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFFDC2626),
                        ),
                      ),
                      if (finalGrade != null)
                        const Text(
                          '%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _resultOutcomeBadge(result),
                      if (!isPit && grade['verdict'] != null && (grade['verdict']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(width: 8),
                        verdictBadgeWidget(grade['verdict']?.toString()),
                      ],
                      const SizedBox(width: 8),
                      statusChipWidget(status),
                    ],
                  ),
                ],
              ),
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: headerInfo),
                  const SizedBox(width: 24),
                  scoreCallout,
                ],
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  headerInfo,
                  const SizedBox(height: 16),
                  scoreCallout,
                ],
              );
            }
          },
        ),

        const SizedBox(height: 20),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        const SizedBox(height: 16),

        const Text(
          'WEIGHT FORMULA & CONTRIBUTIONS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _formulaPill(
              label: 'Panel',
              weight: '${panelWeight.toStringAsFixed(0)}%',
              score: panelScore != null ? '${panelScore.toStringAsFixed(2)}%' : 'Pending',
              contrib: panelContrib != null ? '+${panelContrib.toStringAsFixed(2)}' : null,
              icon: Icons.gavel_rounded,
              accentColor: const Color(0xFF2563EB),
              badgeBg: const Color(0xFFEFF6FF),
              badgeBorder: const Color(0xFFDBEAFE),
            ),
            if (!isPit && adviserWeight > 0) ...[
              const Icon(Icons.add_rounded, size: 16, color: Color(0xFF94A3B8)),
              _formulaPill(
                label: 'Adviser',
                weight: '${adviserWeight.toStringAsFixed(0)}%',
                score: adviserScore != null ? '${adviserScore.toStringAsFixed(2)}%' : 'Pending',
                contrib: adviserContrib != null ? '+${adviserContrib.toStringAsFixed(2)}' : null,
                icon: Icons.school_rounded,
                accentColor: const Color(0xFF059669),
                badgeBg: const Color(0xFFECFDF5),
                badgeBorder: const Color(0xFFA7F3D0),
              ),
            ],
            const Icon(Icons.add_rounded, size: 16, color: Color(0xFF94A3B8)),
            _formulaPill(
              label: 'Peer',
              weight: '${peerWeight.toStringAsFixed(0)}%',
              score: peerScore != null ? '${peerScore.toStringAsFixed(2)}%' : 'Pending',
              contrib: peerContrib != null ? '+${peerContrib.toStringAsFixed(2)}' : null,
              icon: Icons.groups_rounded,
              accentColor: const Color(0xFF7C3AED),
              badgeBg: const Color(0xFFF5F3FF),
              badgeBorder: const Color(0xFFDDD6FE),
            ),
            const Icon(Icons.drag_handle_rounded, size: 16, color: Color(0xFF94A3B8)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Final: ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    finalGrade != null ? '${finalGrade.toStringAsFixed(2)}%' : 'Incomplete',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!isPit && (grade['verdict'] != null || (grade['verdict_remarks']?.toString() ?? '').isNotEmpty)) ...[
          const SizedBox(height: 16),
          _verdictDirectivesCard(grade),
        ],
      ],
    ),
  );
}

Widget _metaIconLabel(IconData icon, String text) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: const Color(0xFF64748B)),
      const SizedBox(width: 4),
      Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

Widget _resultOutcomeBadge(String result) {
  final isPassed = result == 'passed';
  final isFailed = result == 'failed';
  final color = isPassed
      ? const Color(0xFF047857)
      : isFailed
          ? const Color(0xFFB91C1C)
          : const Color(0xFFB45309);
  final bg = isPassed
      ? const Color(0xFFECFDF5)
      : isFailed
          ? const Color(0xFFFEF2F2)
          : const Color(0xFFFFFBEB);
  final border = isPassed
      ? const Color(0xFFA7F3D0)
      : isFailed
          ? const Color(0xFFFECACA)
          : const Color(0xFFFDE68A);
  final icon = isPassed
      ? Icons.check_circle_outline_rounded
      : isFailed
          ? Icons.highlight_off_rounded
          : Icons.pending_outlined;
  final label = isPassed
      ? 'PASSED'
      : isFailed
          ? 'FAILED'
          : 'PENDING';

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

Widget _formulaPill({
  required String label,
  required String weight,
  required String score,
  String? contrib,
  required IconData icon,
  Color accentColor = const Color(0xFF2563EB),
  Color badgeBg = const Color(0xFFF8FAFC),
  Color badgeBorder = const Color(0xFFE2E8F0),
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: badgeBg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: badgeBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: accentColor),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '($weight)',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              contrib != null ? '$score → $contrib pts' : score,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF334155),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Color gradeScopeAccentColor(String scope) {
  return scope == 'pit' ? const Color(0xFF2563EB) : DefensysUi.primaryMaroon;
}

/// KPI stat card aligned with Rubrics evaluation cards.
Widget gradeCenterKpiStatCard({
  required String title,
  required String value,
  required IconData icon,
  required Color accent,
  required Color iconBg,
  double progress = 1.0,
}) {
  final clamped = progress.clamp(0.0, 1.0);
  return Container(
    height: 112,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F2743),
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: clamped,
                  minHeight: 5,
                  backgroundColor: const Color(0xFFE5E7EB),
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget gradeCenterOnOffChip({required bool enabled}) {
  final bg = enabled ? const Color(0xFFD1FAE5) : const Color(0xFFF3F4F6);
  final fg = enabled ? const Color(0xFF059669) : const Color(0xFF9CA3AF);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      enabled ? 'ON' : 'OFF',
      style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w800),
    ),
  );
}

Widget gradeCenterTermTogglePanel({
  required String title,
  required String subtitle,
  required bool value,
  required bool enabled,
  required ValueChanged<bool> onChanged,
}) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: DefensysUi.textDark,
                        ),
                      ),
                    ),
                    gradeCenterOnOffChip(enabled: value),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: DefensysUi.steelGrey,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: DefensysUi.primaryMaroon,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    ),
  );
}

Widget gradeCenterFilterField({
  required String label,
  required IconData icon,
  required Widget dropdown,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Icon(icon, size: 14, color: DefensysUi.steelGrey),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF98A2B3),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      dropdown,
    ],
  );
}

Widget gradeCenterFilterDropdownShell({required Widget child}) {
  return Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: const Color(0xFFD1D5DB)),
    ),
    child: child,
  );
}

/// Capstone stage pipeline status for the Grade Center table.
enum CapstoneStageWorkflowStatus { gradesLocked, inProgress, notStarted }

CapstoneStageWorkflowStatus capstoneStageWorkflowStatus({
  required bool isOfficiallyComplete,
  required int teamCount,
}) {
  if (isOfficiallyComplete) {
    return CapstoneStageWorkflowStatus.gradesLocked;
  }
  if (teamCount > 0) {
    return CapstoneStageWorkflowStatus.inProgress;
  }
  return CapstoneStageWorkflowStatus.notStarted;
}

class CapstoneStageRow {
  const CapstoneStageRow({
    required this.displayOrder,
    required this.label,
    required this.description,
    required this.teamCount,
    required this.isOfficiallyComplete,
    required this.peerGradingEnabled,
    required this.workflowStatus,
    required this.groupKey,
  });

  final int displayOrder;
  final String label;
  final String description;
  final int teamCount;
  final bool isOfficiallyComplete;
  final bool peerGradingEnabled;
  final CapstoneStageWorkflowStatus workflowStatus;
  final String groupKey;

  String get title => gradeGroupTitle(groupKey);
}

List<CapstoneStageRow> buildCapstoneStageRows({
  required GradeCenterState state,
  required List<Map<String, dynamic>> defenseStages,
}) {
  final active =
      defenseStages.where((stage) => stage['is_active'] != false).toList()
        ..sort((a, b) {
          final aOrder = asInt(a['display_order']) ?? 0;
          final bOrder = asInt(b['display_order']) ?? 0;
          if (aOrder != bOrder) {
            return aOrder.compareTo(bOrder);
          }
          return (a['label']?.toString() ?? '').compareTo(
            b['label']?.toString() ?? '',
          );
        });

  final rows = active.map((stage) {
    final label = stage['label']?.toString() ?? '';
    final groupKey = gradeGroupKey('capstone', label);
    final settings = groupSettingsForKey(state, groupKey);
    final teamCount = gradesForGroup(state, 'capstone', label).length;
    final isComplete = settings['is_officially_complete'] == true;
    return CapstoneStageRow(
      displayOrder: asInt(stage['display_order']) ?? 0,
      label: label,
      description: stage['description']?.toString() ?? '',
      teamCount: teamCount,
      isOfficiallyComplete: isComplete,
      peerGradingEnabled: settings['peer_grading_enabled'] == true,
      workflowStatus: capstoneStageWorkflowStatus(
        isOfficiallyComplete: isComplete,
        teamCount: teamCount,
      ),
      groupKey: groupKey,
    );
  }).toList();

  final unscheduledCount = unscheduledCapstoneTeamCount(state);
  if (unscheduledCount > 0) {
    final groupKey = gradeGroupKey('capstone', kUnscheduledStageLabel);
    final settings = groupSettingsForKey(state, groupKey);
    final isComplete = settings['is_officially_complete'] == true;
    rows.add(
      CapstoneStageRow(
        displayOrder: 9999,
        label: kUnscheduledStageLabel,
        description: 'Teams without a scheduled defense slot',
        teamCount: unscheduledCount,
        isOfficiallyComplete: isComplete,
        peerGradingEnabled: settings['peer_grading_enabled'] == true,
        workflowStatus: capstoneStageWorkflowStatus(
          isOfficiallyComplete: isComplete,
          teamCount: unscheduledCount,
        ),
        groupKey: groupKey,
      ),
    );
  }

  return rows;
}

const double kCapstoneStagesTableBodyMaxHeight = 520;
const double kCapstoneStagesTableHeaderBlockHeight = 40;
const double kCapstoneStagesTableRowHeight = 24;

double capstoneStagesTableBodyHeight(int rowCount) {
  if (rowCount <= 0) return 0;
  final raw = kCapstoneStagesTableHeaderBlockHeight +
      rowCount * kCapstoneStagesTableRowHeight;
  return raw > kCapstoneStagesTableBodyMaxHeight
      ? kCapstoneStagesTableBodyMaxHeight
      : raw;
}

Widget capstoneStageWorkflowPill(CapstoneStageWorkflowStatus status) {
  final Color color;
  final Color bg;
  final Color borderColor;
  final IconData icon;
  final String label;
  switch (status) {
    case CapstoneStageWorkflowStatus.gradesLocked:
      color = const Color(0xFF047857);
      bg = const Color(0xFFECFDF5);
      borderColor = const Color(0xFFA7F3D0);
      icon = Icons.lock_rounded;
      label = 'OFFICIALLY COMPLETE';
    case CapstoneStageWorkflowStatus.inProgress:
      color = const Color(0xFFB45309);
      bg = const Color(0xFFFFFBEB);
      borderColor = const Color(0xFFFDE68A);
      icon = Icons.hourglass_top_rounded;
      label = 'IN PROGRESS';
    case CapstoneStageWorkflowStatus.notStarted:
      color = const Color(0xFF475467);
      bg = const Color(0xFFF8FAFC);
      borderColor = const Color(0xFFE2E8F0);
      icon = Icons.schedule_rounded;
      label = 'NOT STARTED';
  }
  return Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget capstoneStageOrderBadge(int order) {
  return Container(
    width: 26,
    height: 26,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
    ),
    child: Text(
      order.toString(),
      style: const TextStyle(
        color: Color(0xFF344054),
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Authoritative milestone button for marking a stage/event officially complete or reopening it.
Widget officialCompleteMilestoneButton({
  required BuildContext context,
  required bool isComplete,
  required bool enabled,
  required ValueChanged<bool> onChanged,
  String stageLabel = 'Stage',
  int teamCount = 0,
}) {
  final hasTeams = teamCount > 0;
  final teamNotice = hasTeams
      ? '\n\n$teamCount team${teamCount == 1 ? '' : 's'} will be affected.'
      : '';

  if (isComplete) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Read-only status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.5, vertical: 4.5),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFA7F3D0), width: 1),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 13,
                  color: Color(0xFF047857),
                ),
                SizedBox(width: 4.5),
                Text(
                  'Officially Complete',
                  style: TextStyle(
                    color: Color(0xFF047857),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
          if (enabled) ...[
            const SizedBox(width: 6),
            // Explicit Reopen action button
            Tooltip(
              message: 'Reopen $stageLabel to allow editing faculty & panel grades',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () async {
                    final confirmed = await showConfirmDialog(
                      context,
                      title: 'Reopen $stageLabel?',
                      message:
                          'Reopening this defense stage will allow faculty to edit grades again and unlock defense stage settings.$teamNotice\n\nAre you sure you want to reopen $stageLabel?',
                      confirmLabel: 'Reopen Stage',
                      cancelLabel: 'Cancel',
                      destructive: false,
                      icon: Icons.lock_open_rounded,
                    );
                    if (confirmed) {
                      onChanged(false);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7.5,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFD0D5DD),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          offset: const Offset(0, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.replay_rounded,
                          size: 12,
                          color: Color(0xFF475467),
                        ),
                        SizedBox(width: 3.5),
                        Text(
                          'Reopen',
                          style: TextStyle(
                            color: Color(0xFF344054),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  return Tooltip(
    message: enabled
        ? 'Mark this stage officially complete and lock grades'
        : 'Complete all required evaluations before marking officially complete',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: enabled
            ? () async {
                final confirmed = await showConfirmDialog(
                  context,
                  title: 'Mark $stageLabel Complete?',
                  message:
                      'Marking this stage officially complete will lock faculty and panel grades, finalize student scores, and make passed teams eligible for project archiving.$teamNotice\n\nAre you sure you want to mark $stageLabel officially complete?',
                  confirmLabel: 'Mark Complete',
                  cancelLabel: 'Cancel',
                  destructive: false,
                  icon: Icons.verified_rounded,
                );
                if (confirmed) {
                  onChanged(true);
                }
              }
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFFF8FAFC) : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: enabled ? const Color(0xFFCBD5E1) : const Color(0xFFEAECF0),
              width: 1,
            ),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      offset: const Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_outlined,
                  size: 13.5,
                  color: enabled ? const Color(0xFF334155) : const Color(0xFF98A2B3),
                ),
                const SizedBox(width: 5),
                Text(
                  'Mark Complete',
                  style: TextStyle(
                    color: enabled ? const Color(0xFF1E293B) : const Color(0xFF98A2B3),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget officialCompleteToggleRow({
  required bool value,
  required bool enabled,
  required ValueChanged<bool> onChanged,
  String stageLabel = 'Stage',
  int teamCount = 0,
}) {
  return Builder(
    builder: (context) => officialCompleteMilestoneButton(
      context: context,
      isComplete: value,
      enabled: enabled,
      stageLabel: stageLabel,
      teamCount: teamCount,
      onChanged: onChanged,
    ),
  );
}

Widget capstoneTermSettingsChips(GradeCenterState state) {
  return Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      capstoneTermStatusChip(
        label: 'Adviser grading',
        enabled: capstoneTermAdviserGradingEnabled(state),
      ),
      capstoneTermStatusChip(
        label: 'Peer evaluation',
        enabled: capstoneTermPeerEvalEnabled(state),
      ),
    ],
  );
}

Widget gradeLockedStatusPill() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFFEE2E2),
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Text(
      'Grades locked',
      style: TextStyle(
        color: Color(0xFFDC2626),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

Widget gradeTeamCountBadge(int count) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$count team${count == 1 ? '' : 's'}',
      style: const TextStyle(
        color: Color(0xFF5D6678),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Show the Capstone term controls card when the scope filter is Capstone or All.
bool showCapstoneTermControls(GradeCenterState state) {
  final scope = state.scope.isEmpty ? 'capstone' : state.scope;
  return scope == 'capstone' || scope == 'all';
}

bool capstoneTermPeerEvalEnabled(GradeCenterState state) {
  final sem = state.activeSemester;
  if (sem == null) {
    return true;
  }
  return sem['capstone_peer_evaluation_enabled'] != false;
}

bool capstoneTermAdviserGradingEnabled(GradeCenterState state) {
  final sem = state.activeSemester;
  if (sem == null) {
    return true;
  }
  return sem['capstone_adviser_grading_enabled'] != false;
}

bool pitPeerStageToggleEnabled({
  required GradeCenterState state,
  required bool isOfficiallyComplete,
}) {
  return !state.isSaving && !isOfficiallyComplete;
}

bool groupOfficialCloseBlocked({
  required List<Map<String, dynamic>> grades,
}) {
  return grades.any((grade) => grade['grading_ready'] != true);
}

@Deprecated('Use groupOfficialCloseBlocked')
bool groupPeerCloseBlocked({
  required List<Map<String, dynamic>> grades,
  required Map<String, dynamic> settings,
}) {
  return groupOfficialCloseBlocked(grades: grades);
}

String groupGradingReadinessSummary(
  Map<String, dynamic> settings, {
  List<Map<String, dynamic>> grades = const [],
}) {
  if (grades.isNotEmpty) {
    final ready =
        grades.where((grade) => grade['grading_ready'] == true).length;
    return '$ready of ${grades.length} teams grading-ready';
  }
  final ready = asInt(settings['grading_ready_team_count']) ?? 0;
  final total = asInt(settings['grading_total_team_count']) ?? 0;
  if (total == 0) {
    return 'No teams in this group';
  }
  return '$ready of $total teams grading-ready';
}

@Deprecated('Use groupGradingReadinessSummary')
String groupPeerCompletionSummary(
  Map<String, dynamic> settings, {
  List<Map<String, dynamic>> grades = const [],
}) {
  return groupGradingReadinessSummary(settings, grades: grades);
}

Widget panelGradingStatusWidget(Map<String, dynamic> grade) {
  final complete = grade['panel_complete'] == true;
  return Text(
    complete ? 'Complete' : 'Missing',
    style: TextStyle(
      color: complete ? const Color(0xFF059669) : const Color(0xFFD97706),
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ),
  );
}

Widget adviserGradingStatusWidget(Map<String, dynamic> grade) {
  if (grade['adviser_required'] != true) {
    return const Text(
      'N/A',
      style: TextStyle(color: Color(0xFF98A2B3), fontSize: 12),
    );
  }
  final complete = grade['adviser_complete'] == true;
  return Text(
    complete ? 'Complete' : 'Missing',
    style: TextStyle(
      color: complete ? const Color(0xFF059669) : const Color(0xFFD97706),
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ),
  );
}

String _missingComponentLabel(String component, Map<String, dynamic> team) {
  switch (component) {
    case 'panel':
      return 'Panel missing';
    case 'adviser':
      return 'Adviser missing';
    case 'peer':
      return 'Peer ${team['evaluators_done'] ?? 0}/${team['evaluators_total'] ?? 0} '
          'evaluators · ${team['submitted'] ?? 0}/${team['required'] ?? 0} submissions';
    default:
      return component;
  }
}

Widget peerEvalFormsStatusWidget(Map<String, dynamic> grade) {
  final complete = grade['peer_eval_complete'] == true;
  final submitted = asInt(grade['peer_submissions_submitted']) ?? 0;
  final required = asInt(grade['peer_submissions_required']) ?? 0;
  final evaluatorsDone = asInt(grade['peer_evaluators_done']) ?? 0;
  final evaluatorsTotal = asInt(grade['peer_evaluators_total']) ?? 0;

  if (required == 0) {
    return const Text(
      'N/A',
      style: TextStyle(color: Color(0xFF98A2B3), fontSize: 12),
    );
  }
  if (complete) {
    return const Text(
      'Complete',
      style: TextStyle(
        color: Color(0xFF059669),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
  return Text(
    '$evaluatorsDone/$evaluatorsTotal evaluators · $submitted/$required',
    style: const TextStyle(
      color: Color(0xFFD97706),
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
    ),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}

Future<void> showIncompleteGradingTeamsDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> teams,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Grading not ready'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'These teams must complete all required grading before you '
                'can mark the event or stage officially complete:',
              ),
              const SizedBox(height: 12),
              ...teams.map((team) {
                final missing = team['missing_components'];
                final parts = missing is List
                    ? missing
                        .map((c) => _missingComponentLabel(c.toString(), team))
                        .join(' · ')
                    : 'Incomplete';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '• ${team['team_name'] ?? 'Team'} — $parts',
                    style: const TextStyle(fontSize: 13),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

@Deprecated('Use showIncompleteGradingTeamsDialog')
Future<void> showIncompletePeerTeamsDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> teams,
}) {
  return showIncompleteGradingTeamsDialog(context, teams: teams);
}

Widget capstoneTermStatusBadgeRow(
  GradeCenterState state, {
  bool showPeerEvaluation = false,
}) {
  final adviserOn = capstoneTermAdviserGradingEnabled(state);
  return Wrap(
    spacing: 8,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      const Text(
        'Term:',
        style: TextStyle(
          color: Color(0xFF98A2B3),
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      capstoneTermStatusChip(label: 'Adviser grading', enabled: adviserOn),
      if (showPeerEvaluation)
        capstoneTermStatusChip(
          label: 'Peer evaluation',
          enabled: capstoneTermPeerEvalEnabled(state),
        ),
    ],
  );
}

Widget capstoneTermStatusChip({required String label, required bool enabled}) {
  final bg = enabled ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC);
  final border = enabled ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0);
  final fg = enabled ? const Color(0xFF15803D) : const Color(0xFF64748B);
  final dotColor = enabled ? const Color(0xFF16A34A) : const Color(0xFF94A3B8);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: border, width: 1),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5.5,
          height: 5.5,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '$label ${enabled ? 'ON' : 'OFF'}',
          style: TextStyle(
            color: fg,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// Stage-level toggles and scope-specific hints for a grade group row or detail card.
Widget gradeGroupStageControlsSection({
  required GradeCenterState state,
  required String scope,
  required bool isOfficiallyComplete,
  required bool peerGradingEnabled,
  required ValueChanged<bool> onOfficiallyCompleteChanged,
  required ValueChanged<bool> onPeerGradingChanged,
  bool showCapstonePeerTermBadge = false,
  Map<String, dynamic>? groupSettings,
  List<Map<String, dynamic>> grades = const [],
  bool officialCompleteToggleEnabled = true,
}) {
  final isPit = scope == 'pit';
  final settings = groupSettings ?? const <String, dynamic>{};
  final peerSummary = groupGradingReadinessSummary(settings, grades: grades);
  final closeBlocked = groupOfficialCloseBlocked(grades: grades);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (grades.isNotEmpty ||
          (settings['peer_total_team_count'] as num? ?? 0) > 0) ...[
        Text(
          peerSummary,
          style: TextStyle(
            color: closeBlocked ? const Color(0xFFD97706) : const Color(0xFF667085),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
      ],
      Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Builder(
            builder: (context) => officialCompleteMilestoneButton(
              context: context,
              isComplete: isOfficiallyComplete,
              enabled: !state.isSaving &&
                  officialCompleteToggleEnabled &&
                  (!closeBlocked || isOfficiallyComplete),
              stageLabel: scope == 'pit' ? 'Event' : 'Stage',
              teamCount: grades.length,
              onChanged: onOfficiallyCompleteChanged,
            ),
          ),
          if (isPit)
            groupToggleRow(
              label: 'Peer grading open',
              value: peerGradingEnabled,
              enabled: pitPeerStageToggleEnabled(
                state: state,
                isOfficiallyComplete: isOfficiallyComplete,
              ),
              onChanged: onPeerGradingChanged,
            ),
          if (isOfficiallyComplete && isPit)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Ready for archive',
                style: TextStyle(
                  color: Color(0xFF059669),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (scope == 'capstone')
            capstoneTermStatusBadgeRow(
              state,
              showPeerEvaluation: showCapstonePeerTermBadge,
            ),
        ],
      ),
      if (isPit) ...[
        const SizedBox(height: 8),
        const Text(
          'PIT uses panel and peer weights only.',
          style: TextStyle(
            color: Color(0xFF98A2B3),
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
      ],
    ],
  );
}

Widget groupToggleRow({
  required String label,
  required bool value,
  required bool enabled,
  required ValueChanged<bool> onChanged,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: enabled ? const Color(0xFFF8FAFC) : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: const Color(0xFFE2E8F0),
        width: 1,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: enabled ? const Color(0xFF344054) : const Color(0xFF98A2B3),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          height: 20,
          width: 32,
          child: Transform.scale(
            scale: 0.75,
            child: Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeThumbColor: Colors.white,
              activeTrackColor: DefensysUi.primaryMaroon,
              inactiveThumbColor: const Color(0xFFD0D5DD),
              inactiveTrackColor: const Color(0xFFF2F4F7),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget gradeScoreSummaryCard({
  required String title,
  required dynamic headlineScore,
  required Widget child,
  IconData? icon,
  Color? iconColor,
  Color? iconBg,
  String? weightText,
  Widget? trailing,
}) {
  final score = asDouble(headlineScore);
  final scoreColor = score == null
      ? const Color(0xFF94A3B8)
      : score >= 75
          ? const Color(0xFF059669)
          : score >= 60
              ? const Color(0xFFD97706)
              : const Color(0xFFDC2626);

  final resolvedIconColor = iconColor ?? const Color(0xFF2563EB);
  final resolvedIconBg = iconBg ?? resolvedIconColor.withValues(alpha: 0.1);

  return DefensysCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: resolvedIconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 17, color: resolvedIconColor),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (weightText != null && weightText.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        weightText,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scoreColor.withValues(alpha: 0.2)),
                ),
                child: Text(
                  score == null ? 'Pending' : '${score.toStringAsFixed(2)}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: scoreColor,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

Widget defenseMinutesStatusBadgeWidget(Map<String, dynamic> grade) {
  final scheduleId = asInt(grade['schedule_id']);
  final minutesStatus = grade['minutes_status']?.toString();
  final hasPdf = grade['minutes_has_pdf'] == true;

  if (scheduleId == null || minutesStatus == null || minutesStatus.isEmpty) {
    return const SizedBox.shrink();
  }

  final isCompleted = minutesStatus == 'completed' || hasPdf;
  final label = isCompleted
      ? 'Official Minutes: Signed & Completed'
      : minutesStatus == 'adviser_signed'
          ? 'Minutes: Awaiting Chair Sign'
          : minutesStatus == 'submitted'
              ? 'Minutes: Awaiting Adviser Sign'
              : 'Minutes: In Progress by Documenter';

  final color = isCompleted
      ? const Color(0xFF047857)
      : minutesStatus == 'adviser_signed' || minutesStatus == 'submitted'
          ? const Color(0xFF2563EB)
          : const Color(0xFF64748B);

  final icon = isCompleted
      ? Icons.verified_outlined
      : minutesStatus == 'adviser_signed' || minutesStatus == 'submitted'
          ? Icons.draw_outlined
          : Icons.edit_note_outlined;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );
}

Widget _verdictDirectivesCard(Map<String, dynamic> grade) {
  final verdict = grade['verdict']?.toString();
  final remarks = grade['verdict_remarks']?.toString() ?? '';
  final verdictByName = grade['verdict_by_name']?.toString() ?? '';
  final deadline = grade['revision_deadline']?.toString();

  final isApproved = verdict == 'approved';
  final isApprovedRevisions = verdict == 'approved_with_revisions';
  final isForRedefense = verdict == 'for_redefense';

  final accentColor = isApproved
      ? const Color(0xFF16A34A)
      : isApprovedRevisions
          ? const Color(0xFFD97706)
          : isForRedefense
              ? const Color(0xFFDC2626)
              : const Color(0xFF64748B);

  final bgColor = isApproved
      ? const Color(0xFFF0FDF4)
      : isApprovedRevisions
          ? const Color(0xFFFFFBEB)
          : isForRedefense
              ? const Color(0xFFFEF2F2)
              : const Color(0xFFF8FAFC);

  final borderColor = isApproved
      ? const Color(0xFFBBF7D0)
      : isApprovedRevisions
          ? const Color(0xFFFDE68A)
          : isForRedefense
              ? const Color(0xFFFECACA)
              : const Color(0xFFE2E8F0);

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: borderColor, width: 1.2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.gavel_rounded, size: 16, color: accentColor),
            ),
            const SizedBox(width: 8),
            Text(
              'Official Panel Decision & Directives',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: accentColor,
              ),
            ),
            const SizedBox(width: 8),
            verdictBadgeWidget(verdict),
            const Spacer(),
            if (deadline != null && deadline.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event_available_rounded, size: 13, color: Color(0xFFD97706)),
                    const SizedBox(width: 4),
                    Text(
                      'Revision Due: $deadline',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        if (remarks.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor.withValues(alpha: 0.7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (verdictByName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      'Issued by $verdictByName:',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                Text(
                  remarks,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1E293B),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

Widget attemptHistoryCardWidget({
  required List<dynamic> attemptHistory,
  required int currentAttemptCount,
}) {
  if (attemptHistory.isEmpty && currentAttemptCount <= 1) {
    return const SizedBox.shrink();
  }

  return DefensysCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.history_edu_rounded, size: 18, color: Color(0xFF4F46E5)),
            ),
            const SizedBox(width: 10),
            const Text(
              'Defense Attempt History & ISO Traceability',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Current: Attempt #$currentAttemptCount',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Historical evaluation attempts preserved for accreditation, ISO 9001:2015 audit retention, and re-defense tracking.',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 14),
        ...attemptHistory.map((item) {
          if (item is! Map) return const SizedBox.shrink();
          final attNum = item['attempt_number'] ?? '?';
          final sDate = item['scheduled_date']?.toString() ?? '—';
          final room = item['room']?.toString() ?? '—';
          final fGrade = asDouble(item['final_grade']);
          final pScore = asDouble(item['panel_score']);
          final vVerdict = item['verdict']?.toString();
          final vRemarks = item['verdict_remarks']?.toString() ?? '';
          final vByName = item['verdict_by_name']?.toString() ?? '';

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Attempt #$attNum',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Date: $sDate · Room: $room',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const Spacer(),
                    if (pScore != null) ...[
                      Text(
                        'Panel: ${pScore.toStringAsFixed(2)}%',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Text(
                      fGrade != null ? 'Final: ${fGrade.toStringAsFixed(2)}%' : 'Incomplete',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 10),
                    verdictBadgeWidget(vVerdict),
                  ],
                ),
                if (vRemarks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (vByName.isNotEmpty)
                          Text(
                            'Directive by $vByName:',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                          ),
                        Text(
                          vRemarks,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    ),
  );
}

class GradeCenterActions {
  static Future<void> showEditScoresDialog({
    required BuildContext context,
    required WidgetRef ref,
    required Map<String, dynamic> grade,
  }) async {
    final gradeId = asInt(grade['id']);
    if (gradeId == null) {
      return;
    }

    final panel = TextEditingController(text: scoreInput(grade['panel_score']));
    final adviser = TextEditingController(
      text: scoreInput(grade['adviser_score']),
    );
    final peer = TextEditingController(text: scoreInput(grade['peer_score']));
    final isPit = grade['scope'] == 'pit';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Grade Scores'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                grade['team_name']?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Text(
                'Scores are percentages from 0 to 100.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: panel,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Panel Score (${weightText(grade, 'panel')}%)',
                ),
              ),
              const SizedBox(height: 12),
              if (!isPit) ...[
                TextField(
                  controller: adviser,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText:
                        'Adviser Score (${weightText(grade, 'adviser')}%)',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: peer,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Peer Score (${weightText(grade, 'peer')}%)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.save_rounded, size: 16),
            label: const Text('Save Scores'),
            style: DefensysTokens.saveButtonStyle(isPill: false),
          ),
        ],
      ),
    );

    final panelText = panel.text;
    final adviserText = adviser.text;
    final peerText = peer.text;
    panel.dispose();
    adviser.dispose();
    peer.dispose();

    if (!context.mounted || saved != true) {
      return;
    }

    await ref.read(gradeCenterProvider.notifier).updateGrade(gradeId, {
      'panel_score': scorePayload(panelText),
      if (!isPit) 'adviser_score': scorePayload(adviserText),
      'peer_score': scorePayload(peerText),
    });
  }

  static Widget _verdictRadioOption({
    required String title,
    required String subtitle,
    required String value,
    required String groupValue,
    required Color color,
    required ValueChanged<String?> onChanged,
  }) {
    final isSelected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: color,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? color : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> showVerdictDialog({
    required BuildContext context,
    required WidgetRef ref,
    required Map<String, dynamic> grade,
  }) async {
    final gradeId = asInt(grade['id']);
    if (gradeId == null) return;

    String selectedVerdict = grade['verdict']?.toString() ?? 'approved';
    if (selectedVerdict.isEmpty) selectedVerdict = 'approved';
    final remarksController = TextEditingController(text: grade['verdict_remarks']?.toString() ?? '');
    DateTime? revisionDeadline;
    if (grade['revision_deadline'] != null) {
      revisionDeadline = DateTime.tryParse(grade['revision_deadline'].toString());
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.maroon.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.gavel_rounded, color: AppColors.maroon, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Render Defense Verdict',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${grade['team_name'] ?? 'Team'} · ${grade['stage_label'] ?? 'Defense Stage'}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF475569)),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'OFFICIAL VERDICT',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 8),
                    _verdictRadioOption(
                      title: 'Approved',
                      subtitle: 'The team successfully passed with no mandatory re-defense.',
                      value: 'approved',
                      groupValue: selectedVerdict,
                      color: const Color(0xFF16A34A),
                      onChanged: (val) => setState(() => selectedVerdict = val!),
                    ),
                    const SizedBox(height: 8),
                    _verdictRadioOption(
                      title: 'Approved with Revisions',
                      subtitle: 'Passed, but required manuscript or system changes must be submitted by a deadline.',
                      value: 'approved_with_revisions',
                      groupValue: selectedVerdict,
                      color: const Color(0xFFD97706),
                      onChanged: (val) => setState(() => selectedVerdict = val!),
                    ),
                    const SizedBox(height: 8),
                    _verdictRadioOption(
                      title: 'For Re-defense',
                      subtitle: 'Concept rejected, prototype unsatisfactory, or major deficiencies requiring re-presentation.',
                      value: 'for_redefense',
                      groupValue: selectedVerdict,
                      color: const Color(0xFFDC2626),
                      onChanged: (val) => setState(() => selectedVerdict = val!),
                    ),
                    if (selectedVerdict == 'approved_with_revisions') ...[
                      const SizedBox(height: 16),
                      const Text(
                        'REVISION SUBMISSION DEADLINE',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: revisionDeadline ?? DateTime.now().add(const Duration(days: 14)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() => revisionDeadline = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_today_rounded, size: 16),
                        label: Text(
                          revisionDeadline != null
                              ? '${revisionDeadline!.year}-${revisionDeadline!.month.toString().padLeft(2, '0')}-${revisionDeadline!.day.toString().padLeft(2, '0')}'
                              : 'Select deadline date (optional)',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'PANEL INSTRUCTIONS & DIRECTIVES FOR TEAM',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: remarksController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Enter panel directives, recommendations, required changes, or new title instructions…',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.maroon,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                child: const Text('Submit Verdict'),
              ),
            ],
          );
        },
      ),
    );

    final remarks = remarksController.text.trim();
    remarksController.dispose();

    if (!context.mounted || saved != true) return;

    final deadlineStr = revisionDeadline != null
        ? '${revisionDeadline!.year}-${revisionDeadline!.month.toString().padLeft(2, '0')}-${revisionDeadline!.day.toString().padLeft(2, '0')}'
        : null;

    await ref.read(gradeCenterProvider.notifier).submitVerdict(
      gradeId,
      verdict: selectedVerdict,
      remarks: remarks,
      revisionDeadline: deadlineStr,
    );
  }

  static Future<void> confirmPublish({
    required BuildContext context,
    required WidgetRef ref,
    required int gradeId,
    required String teamName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Publish Grade'),
        content: Text(
          'Publish the final grade for $teamName? This marks the defense done and updates the team result.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );

    if (!context.mounted || confirmed != true) {
      return;
    }
    await ref.read(gradeCenterProvider.notifier).publishGrade(gradeId);
  }
}
