import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/grade_center_provider.dart';
import '../../../theme/app_theme.dart';
import 'widgets/defensys_admin_shell.dart';

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
    'passed' => 'Passed',
    'failed' => 'Failed',
    'pending' => 'Pending',
    _ => status.isEmpty ? 'Pending' : status,
  };
}

/// Workflow status or pass/fail outcome (75% threshold) when scores are complete.
String gradeDisplayStatus(Map<String, dynamic> grade) {
  final workflow = grade['status']?.toString() ?? '';
  if (workflow == 'published' ||
      workflow == 'awaiting_peers') {
    return workflow;
  }
  if (asDouble(grade['final_grade']) != null) {
    final result = grade['result']?.toString() ?? '';
    if (result == 'passed' || result == 'failed') {
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
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        grade['team_name']?.toString() ?? '-',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: DefensysUi.textDark,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
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
            color: Color(0xFFB0B7C3),
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
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

Widget _statusChip(String label, String status) {
  final color = switch (status) {
    'published' => AppColors.success,
    'passed' => AppColors.success,
    'failed' => const Color(0xFFDC2626),
    'awaiting_peers' => Colors.blue,
    _ => AppColors.warning,
  };
  final icon = switch (status) {
    'published' => Icons.lock_outline,
    'passed' => Icons.check_circle_outline,
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

Widget gradeFormulaLine(Map<String, dynamic> grade) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.maroon.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      'Formula: Panel ${weightText(grade, 'panel')}% + '
      '${grade['scope'] == 'pit' ? '' : 'Adviser ${weightText(grade, 'adviser')}% + '}'
      'Peer ${weightText(grade, 'peer')}% = Final Grade. Pass threshold: 75.',
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

Widget breakdownSectionWidget(String type, List<Map<String, dynamic>> rows) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          evaluationLabel(type),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(2.4),
            1: FlexColumnWidth(),
            2: FlexColumnWidth(),
          },
          children: [
            const TableRow(
              children: [
                GradeBreakdownTableHeader('Criterion'),
                GradeBreakdownTableHeader('Score'),
                GradeBreakdownTableHeader('Max'),
              ],
            ),
            ...rows.map(
              (row) => TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(row['criterion_name']?.toString() ?? ''),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(row['score']?.toString() ?? ''),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(row['max_score']?.toString() ?? ''),
                  ),
                ],
              ),
            ),
          ],
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

Color gradeScopeAccentColor(String scope) {
  return scope == 'pit' ? const Color(0xFF2563EB) : DefensysUi.primaryMaroon;
}

/// KPI stat card aligned with Rubric Engine evaluation cards.
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
  final IconData icon;
  final String label;
  switch (status) {
    case CapstoneStageWorkflowStatus.gradesLocked:
      color = const Color(0xFFDC2626);
      bg = const Color(0xFFFEE2E2);
      icon = Icons.lock_outline_rounded;
      label = 'GRADES LOCKED';
    case CapstoneStageWorkflowStatus.inProgress:
      color = const Color(0xFFD97706);
      bg = const Color(0xFFFFEDD5);
      icon = Icons.hourglass_top_rounded;
      label = 'IN PROGRESS';
    case CapstoneStageWorkflowStatus.notStarted:
      color = const Color(0xFF6B7280);
      bg = const Color(0xFFF3F4F6);
      icon = Icons.assignment_outlined;
      label = 'NOT STARTED';
  }
  return Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
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
    width: 28,
    height: 28,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: DefensysUi.primaryMaroon.withValues(alpha: 0.12),
      shape: BoxShape.circle,
    ),
    child: Text(
      order.toString(),
      style: const TextStyle(
        color: DefensysUi.primaryMaroon,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

Widget officialCompleteToggleRow({
  required bool value,
  required bool enabled,
  required ValueChanged<bool> onChanged,
}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Switch(
        value: value,
        onChanged: enabled ? onChanged : null,
        activeThumbColor: DefensysUi.primaryMaroon,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      const SizedBox(width: 4),
      Text(
        value ? 'Yes' : 'No',
        style: TextStyle(
          color: value ? DefensysUi.primaryMaroon : const Color(0xFF98A2B3),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
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
  final bg = enabled ? const Color(0xFFD1FAE5) : const Color(0xFFF3F4F6);
  final fg = enabled ? const Color(0xFF059669) : const Color(0xFF9CA3AF);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$label ${enabled ? 'ON' : 'OFF'}',
      style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
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
          if (isOfficiallyComplete) gradeLockedStatusPill(),
          groupToggleRow(
            label: 'Officially complete',
            value: isOfficiallyComplete,
            enabled: !state.isSaving &&
                officialCompleteToggleEnabled &&
                (!closeBlocked || isOfficiallyComplete),
            onChanged: onOfficiallyCompleteChanged,
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
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF5D6678),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(width: 6),
      Switch(
        value: value,
        onChanged: enabled ? onChanged : null,
        activeThumbColor: DefensysUi.primaryMaroon,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ],
  );
}

Widget gradeScoreSummaryCard({
  required String title,
  required dynamic headlineScore,
  required Widget child,
}) {
  return DefensysCard(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: DefensysUi.textDark,
              ),
            ),
            const Spacer(),
            scoreTextWidget(headlineScore),
          ],
        ),
        const SizedBox(height: 12),
        child,
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
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save Scores'),
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
