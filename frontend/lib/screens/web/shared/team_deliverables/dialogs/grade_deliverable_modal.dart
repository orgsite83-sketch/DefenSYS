import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/rubric_scoring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/models/adviser_workflow.dart';
import 'package:defensys/widgets/adviser/workflow_reminder.dart';
import 'package:defensys/widgets/export/report_export_menu.dart';

int parseAsInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

double? parseAsDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

Widget buildRosterAndIndividualGrades(Map<String, dynamic> team, Map<String, dynamic>? grade) {
  final List<dynamic> members = team['members'] as List? ?? [];
  final List<dynamic> peerGrades = grade?['peer_per_student'] as List? ?? [];

  if (members.isEmpty) {
    return const Text(
      'No members assigned to this team.',
      style: TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
    );
  }

  return Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFF3F4F6)),
    ),
    child: ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: members.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE5E7EB)),
      itemBuilder: (context, index) {
        final rawMember = members[index];
        if (rawMember is! Map) return const SizedBox.shrink();
        final member = Map<String, dynamic>.from(rawMember);
        final studentId = member['id'];
        final name = member['name']?.toString() ?? member['username']?.toString() ?? 'Student';
        final role = member['role']?.toString() ?? 'member';
        final isLeader = role == 'leader';

        final peerDetails = peerGrades.firstWhere(
          (g) => g is Map && g['student_id'] == studentId,
          orElse: () => null,
        );

        final double? avgScore = parseAsDouble(peerDetails?['average_score']);
        final double maxScore = parseAsDouble(peerDetails?['max_score']) ?? 5.0;
        final double? normScore = parseAsDouble(peerDetails?['normalized_score']);

        final sanitizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
        final parts = sanitizedName.split(' ');
        final initials = parts.isNotEmpty
            ? (parts.first.isNotEmpty ? parts.first[0] : '') +
                (parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '')
            : '';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.maroon.withValues(alpha: 0.1),
                child: Text(
                  initials.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.maroon,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (isLeader) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Leader',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.gold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      member['username']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (avgScore != null) ...[
                          Text(
                            'Peer Score: ${avgScore.toStringAsFixed(2)} / ${maxScore.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Normalized: ${normScore?.toStringAsFixed(2)}%',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ] else ...[
                          const Text(
                            'Peer Score: Pending',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class GradeDeliverableTab extends ConsumerStatefulWidget {
  final Map<String, dynamic> team;
  final String selectedStage;
  final bool isAdviser;
  final String? programScope;
  final Map<String, Map<String, TextEditingController>> teamCriteriaScoreCtrls;
  final Map<String, Map<dynamic, Map<String, TextEditingController>>> teamStudentCriteriaScoreCtrls;
  final Map<String, TextEditingController> teamManualScoreCtrls;
  final Map<String, Map<String, dynamic>?> teamSelectedRubrics;

  const GradeDeliverableTab({
    super.key,
    required this.team,
    required this.selectedStage,
    required this.isAdviser,
    this.programScope,
    required this.teamCriteriaScoreCtrls,
    required this.teamStudentCriteriaScoreCtrls,
    required this.teamManualScoreCtrls,
    required this.teamSelectedRubrics,
  });

  @override
  ConsumerState<GradeDeliverableTab> createState() => _GradeDeliverableTabState();
}

class _GradeDeliverableTabState extends ConsumerState<GradeDeliverableTab> {
  int _selectedStudentIndex = 0;
  int? _exportStudentId;

  @override
  void didUpdateWidget(covariant GradeDeliverableTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.team['id'] != widget.team['id'] ||
        oldWidget.selectedStage != widget.selectedStage) {
      _exportStudentId = null;
    }
  }

  Map<String, dynamic>? _assignedRubricFromGrade(Map<String, dynamic> grade) {
    final rubricId = grade['assigned_adviser_rubric_id'];
    if (rubricId == null) {
      return null;
    }
    final criteria = grade['assigned_adviser_criteria'];
    return {
      'id': rubricId,
      'name': grade['assigned_adviser_rubric_name']?.toString() ?? 'Adviser rubric',
      'scale': grade['assigned_adviser_rubric_scale'],
      'target_type': grade['assigned_adviser_rubric_target_type']?.toString() ?? 'team',
      'criteria': criteria is List ? criteria : [],
    };
  }

  List<Map<String, dynamic>> _getMembers(Map<String, dynamic> gradeRecord) {
    final raw = widget.team['members'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final gradeMembers = gradeRecord['members'];
    if (gradeMembers is List && gradeMembers.isNotEmpty) {
      return gradeMembers.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final pps = gradeRecord['peer_per_student'];
    if (pps is List && pps.isNotEmpty) {
      return pps.map((e) {
        final m = e as Map;
        return {
          'id': m['student_id'] ?? m['id'],
          'student_id': m['student_id'] ?? m['id'],
          'name': m['student_name'] ?? 'Student',
          'is_leader': false,
        };
      }).toList();
    }
    return [];
  }

  List<Map<String, dynamic>> _getTeamCriteria(Map<String, dynamic>? rubric) {
    if (rubric == null) return [];
    final criteria = (rubric['criteria'] as List? ?? []);
    final targetType = rubric['target_type']?.toString() ?? 'team';
    if (targetType == 'individual') return [];
    if (targetType == 'team') {
      return criteria.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return criteria
        .where((c) => (c as Map)['target_type']?.toString() == 'team')
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  List<Map<String, dynamic>> _getIndividualCriteria(Map<String, dynamic>? rubric) {
    if (rubric == null) return [];
    final criteria = (rubric['criteria'] as List? ?? []);
    final targetType = rubric['target_type']?.toString() ?? 'team';
    if (targetType == 'team') return [];
    if (targetType == 'individual') {
      return criteria.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return criteria
        .where((c) => (c as Map)['target_type']?.toString() == 'individual')
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  void _initializeGradingControllersForTeam(
    int teamId,
    String stageLabel,
    Map<String, dynamic> gradeRecord,
  ) {
    final key = '$teamId-$stageLabel';
    // A dossier can open before the grading request completes. Do not cache
    // an empty rubric and prevent the returned scoring form from initializing.
    if (gradeRecord['assigned_adviser_rubric_id'] == null) return;
    if (widget.teamManualScoreCtrls.containsKey(key)) {
      return; // Already initialized for this team and stage
    }

    final manualCtrl = TextEditingController();
    final existing = gradeRecord['adviser_score'];
    if (existing != null) {
      manualCtrl.text = existing.toString();
    }
    widget.teamManualScoreCtrls[key] = manualCtrl;

    final criteriaCtrls = <String, TextEditingController>{};
    final studentCriteriaCtrls = <dynamic, Map<String, TextEditingController>>{};
    final assigned = _assignedRubricFromGrade(gradeRecord);
    widget.teamSelectedRubrics[key] = assigned;

    if (assigned != null) {
      final teamSaved = <String, String>{};
      final studentSaved = <dynamic, Map<String, String>>{};
      if (gradeRecord['breakdowns'] is List) {
        for (final row in gradeRecord['breakdowns'] as List) {
          if (row is! Map) continue;
          if (row['evaluation_type']?.toString() != 'adviser') continue;
          final name = row['criterion_name']?.toString() ?? '';
          final sId = row['student_id'] ?? row['student'];
          final scoreVal = row['score']?.toString() ?? '';
          if (name.isEmpty) continue;
          if (sId == null) {
            teamSaved[name] = scoreVal;
          } else {
            studentSaved.putIfAbsent(sId, () => {})[name] = scoreVal;
          }
        }
      }

      final teamCrits = _getTeamCriteria(assigned);
      final indCrits = _getIndividualCriteria(assigned);
      final members = _getMembers(gradeRecord);

      for (final c in teamCrits) {
        final name = c['name']?.toString() ?? '';
        criteriaCtrls[name] = TextEditingController(text: teamSaved[name] ?? '');
      }

      for (final m in members) {
        final sId = m['id'] ?? m['student_id'];
        final subMap = <String, TextEditingController>{};
        for (final c in indCrits) {
          final name = c['name']?.toString() ?? '';
          subMap[name] = TextEditingController(text: studentSaved[sId]?[name] ?? '');
        }
        studentCriteriaCtrls[sId] = subMap;
      }
    }
    widget.teamCriteriaScoreCtrls[key] = criteriaCtrls;
    widget.teamStudentCriteriaScoreCtrls[key] = studentCriteriaCtrls;
  }

  double _computeStudentScore(
    int teamId,
    String stageLabel,
    dynamic studentId,
    Map<String, dynamic> gradeRecord,
  ) {
    final key = '$teamId-$stageLabel';
    final rubric = widget.teamSelectedRubrics[key];
    if (rubric == null) return 0;
    final targetType = rubric['target_type']?.toString() ?? 'team';
    final teamCrits = _getTeamCriteria(rubric);
    final indCrits = _getIndividualCriteria(rubric);

    final scoreRows = <RubricScore>[];

    final teamSubMap = widget.teamCriteriaScoreCtrls[key] ?? const {};
    if (targetType == 'team' || targetType == 'both') {
      for (final c in teamCrits) {
        final name = c['name']?.toString() ?? '';
        final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
        final entered = double.tryParse(teamSubMap[name]?.text ?? '') ?? 0;
        scoreRows.add(RubricScore(entered.clamp(0, maxScore).toDouble(), maxScore, rubricWeight(c['weight'])));
      }
    }

    if (studentId != null && (targetType == 'individual' || targetType == 'both')) {
      final studentSubMap = widget.teamStudentCriteriaScoreCtrls[key]?[studentId] ?? const {};
      for (final c in indCrits) {
        final name = c['name']?.toString() ?? '';
        final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
        final entered = double.tryParse(studentSubMap[name]?.text ?? '') ?? 0;
        scoreRows.add(RubricScore(entered.clamp(0, maxScore).toDouble(), maxScore, rubricWeight(c['weight'])));
      }
    }

    return rubricPercentage(scoreRows) ?? 0;
  }

  double _computeOverallTeamScore(
    int teamId,
    String stageLabel,
    Map<String, dynamic> gradeRecord,
  ) {
    final key = '$teamId-$stageLabel';
    final rubric = widget.teamSelectedRubrics[key];
    if (rubric == null) {
      final manualCtrl = widget.teamManualScoreCtrls[key];
      return (double.tryParse(manualCtrl?.text ?? '') ?? 0).clamp(0, 100);
    }
    final targetType = rubric['target_type']?.toString() ?? 'team';
    if (targetType == 'team') {
      return _computeStudentScore(teamId, stageLabel, null, gradeRecord);
    }
    final members = _getMembers(gradeRecord);
    if (members.isEmpty) {
      return _computeStudentScore(teamId, stageLabel, null, gradeRecord);
    }
    double sum = 0;
    for (final m in members) {
      final sId = m['id'] ?? m['student_id'];
      sum += _computeStudentScore(teamId, stageLabel, sId, gradeRecord);
    }
    return (sum / members.length).clamp(0, 100);
  }

  bool _isTeamCriteriaComplete(int teamId, String stageLabel) {
    final key = '$teamId-$stageLabel';
    final rubric = widget.teamSelectedRubrics[key];
    if (rubric == null) return false;
    final teamCrits = _getTeamCriteria(rubric);
    final teamSubMap = widget.teamCriteriaScoreCtrls[key] ?? const {};
    for (final c in teamCrits) {
      final name = c['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final text = teamSubMap[name]?.text.trim() ?? '';
      if (text.isEmpty) return false;
      final value = double.tryParse(text);
      if (value == null || value < 0 || value > maxScore) return false;
    }
    return true;
  }

  bool _isStudentCriteriaComplete(int teamId, String stageLabel, dynamic studentId) {
    final key = '$teamId-$stageLabel';
    final rubric = widget.teamSelectedRubrics[key];
    if (rubric == null) return false;
    final indCrits = _getIndividualCriteria(rubric);
    if (indCrits.isEmpty) return true;
    final studentSubMap = widget.teamStudentCriteriaScoreCtrls[key]?[studentId] ?? const {};
    for (final c in indCrits) {
      final name = c['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final text = studentSubMap[name]?.text.trim() ?? '';
      if (text.isEmpty) return false;
      final value = double.tryParse(text);
      if (value == null || value < 0 || value > maxScore) return false;
    }
    return true;
  }

  bool _allCriteriaFilledForTeam(int teamId, String stageLabel, Map<String, dynamic> gradeRecord) {
    final key = '$teamId-$stageLabel';
    final rubric = widget.teamSelectedRubrics[key];
    if (rubric == null) return false;
    if (!_isTeamCriteriaComplete(teamId, stageLabel)) return false;
    final indCrits = _getIndividualCriteria(rubric);
    if (indCrits.isNotEmpty) {
      final members = _getMembers(gradeRecord);
      if (members.isEmpty) return false;
      for (final m in members) {
        final sId = m['id'] ?? m['student_id'];
        if (!_isStudentCriteriaComplete(teamId, stageLabel, sId)) return false;
      }
    }
    return true;
  }

  int _filledCountForTeam(int teamId, String stageLabel, Map<String, dynamic> gradeRecord) {
    final key = '$teamId-$stageLabel';
    final rubric = widget.teamSelectedRubrics[key];
    if (rubric == null) return 0;
    int count = 0;
    final teamCrits = _getTeamCriteria(rubric);
    final teamSubMap = widget.teamCriteriaScoreCtrls[key] ?? const {};
    for (final c in teamCrits) {
      final name = c['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final text = teamSubMap[name]?.text.trim() ?? '';
      final value = double.tryParse(text);
      if (text.isNotEmpty && value != null && value >= 0 && value <= maxScore) count++;
    }

    final indCrits = _getIndividualCriteria(rubric);
    if (indCrits.isNotEmpty) {
      final members = _getMembers(gradeRecord);
      for (final m in members) {
        final sId = m['id'] ?? m['student_id'];
        final studentSubMap = widget.teamStudentCriteriaScoreCtrls[key]?[sId] ?? const {};
        for (final c in indCrits) {
          final name = c['name']?.toString() ?? '';
          final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
          final text = studentSubMap[name]?.text.trim() ?? '';
          final value = double.tryParse(text);
          if (text.isNotEmpty && value != null && value >= 0 && value <= maxScore) count++;
        }
      }
    }
    return count;
  }

  int _totalCountForTeam(int teamId, String stageLabel, Map<String, dynamic> gradeRecord) {
    final key = '$teamId-$stageLabel';
    final rubric = widget.teamSelectedRubrics[key];
    if (rubric == null) return 0;
    final teamCrits = _getTeamCriteria(rubric);
    final indCrits = _getIndividualCriteria(rubric);
    final members = _getMembers(gradeRecord);
    return teamCrits.length + (indCrits.length * (members.isEmpty ? 1 : members.length));
  }

  Future<void> _submitAdviserGrade({
    required int teamId,
    required String stageLabel,
    required Map<String, dynamic> gradeRecord,
  }) async {
    final key = '$teamId-$stageLabel';
    final gradeId = gradeRecord['id'] as int?;
    if (gradeId == null) {
      showErrorToast(context, 'No grading record available for this team and stage.');
      return;
    }

    final rubric = widget.teamSelectedRubrics[key];
    final manualCtrl = widget.teamManualScoreCtrls[key];

    double adviserScore;
    List<Map<String, dynamic>> criteriaScores = [];
    List<Map<String, dynamic>> teamCriteriaScores = [];
    List<Map<String, dynamic>> studentSubmissions = [];
    int? rubricId;

    if (rubric != null) {
      rubricId = rubric['id'] as int?;
      final targetType = rubric['target_type']?.toString() ?? 'team';
      final teamCrits = _getTeamCriteria(rubric);
      final indCrits = _getIndividualCriteria(rubric);
      final members = _getMembers(gradeRecord);
      final teamSubMap = widget.teamCriteriaScoreCtrls[key] ?? const {};

      for (final c in teamCrits) {
        final name = c['name']?.toString() ?? '';
        final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
        final entered = (double.tryParse(teamSubMap[name]?.text ?? '') ?? 0).clamp(0, maxScore);
        final entry = {
          'criterion_id': c['id'],
          'criterion_name': name,
          'score': entered,
          'max_score': maxScore,
          'display_order': c['display_order'] ?? 0,
        };
        teamCriteriaScores.add(entry);
        if (targetType == 'team') {
          criteriaScores.add(entry);
        }
      }

      for (final m in members) {
        final sId = m['id'] ?? m['student_id'];
        final studentSubMap = widget.teamStudentCriteriaScoreCtrls[key]?[sId] ?? const {};
        final sScores = <Map<String, dynamic>>[];
        for (final c in indCrits) {
          final name = c['name']?.toString() ?? '';
          final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
          final entered = (double.tryParse(studentSubMap[name]?.text ?? '') ?? 0).clamp(0, maxScore);
          sScores.add({
            'criterion_id': c['id'],
          'criterion_name': name,
            'score': entered,
            'max_score': maxScore,
            'display_order': c['display_order'] ?? 0,
          });
        }
        studentSubmissions.add({
          'student_id': sId,
          'criteria_scores': sScores,
        });
      }

      adviserScore = _computeOverallTeamScore(teamId, stageLabel, gradeRecord);
    } else {
      if (manualCtrl == null) return;
      adviserScore = double.tryParse(manualCtrl.text) ?? 0;
      adviserScore = adviserScore.clamp(0, 100);
    }

    final success = await ref.read(adviserGradingProvider.notifier).submitGrade(
          gradeId: gradeId,
          adviserScore: adviserScore,
          rubricId: rubricId,
          criteriaScores: criteriaScores,
          teamCriteriaScores: teamCriteriaScores,
          studentSubmissions: studentSubmissions,
        );

    if (success && mounted) {
      showSuccessToast(context, 'Grade submitted successfully!');
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables();
    }
  }

  Widget _buildCriteriaTable({
    required List<Map<String, dynamic>> criteria,
    required bool isTeam,
    dynamic studentId,
    required int teamId,
    required String stageLabel,
    bool isReadOnly = false,
  }) {
    if (criteria.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'No criteria defined for this section.',
          style: TextStyle(
            color: DefensysTokens.textSecondaryOf(context),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    final key = '$teamId-$stageLabel';
    final subMap = isTeam
        ? (widget.teamCriteriaScoreCtrls[key] ?? const {})
        : (widget.teamStudentCriteriaScoreCtrls[key]?[studentId] ?? const {});

    return Container(
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      child: Column(
        children: criteria.asMap().entries.map((entry) {
          final i = entry.key;
          final c = entry.value;
          final name = c['name']?.toString() ?? '';
          final desc = c['description']?.toString() ?? '';
          final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
          final ctrl = subMap[name] ?? TextEditingController();

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: i < criteria.length - 1
                  ? Border(
                      bottom: BorderSide(
                        color: DefensysTokens.borderOf(context),
                        width: 0.5,
                      ),
                    )
                  : null,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final label = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        style: TextStyle(
                          fontSize: 11,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ],
                );
                final score = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '/ $maxScore',
                      style: TextStyle(
                        color: DefensysTokens.textSecondaryOf(context),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 80,
                      child: isReadOnly
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: DefensysTokens.surfaceHigherOf(context),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: DefensysTokens.borderOf(context),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                ctrl.text.isNotEmpty ? ctrl.text : '-',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: DefensysTokens.textPrimaryOf(context),
                                ),
                              ),
                            )
                          : ShadInput(
                              controller: ctrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textAlign: TextAlign.center,
                              placeholder: const Text('Score'),
                              style: TextStyle(
                                fontFamily: DefensysTokens.fontFamilyInter,
                                fontSize: 13,
                                color: DefensysTokens.textPrimaryOf(context),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                    ),
                  ],
                );
                if (constraints.maxWidth < 420) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      label,
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerRight, child: score),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: label),
                    const SizedBox(width: 16),
                    score,
                  ],
                );
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teamId = parseAsInt(widget.team['id']);
    final gradingState = ref.watch(adviserGradingProvider);
    final gradeRecord =
        adviserGradeForTeam(
          widget.team,
          widget.selectedStage,
          gradingState.grades,
        ) ??
        <String, dynamic>{};
    final scope =
        (widget.programScope == 'pit' || widget.programScope == 'capstone'
            ? widget.programScope
            : null) ??
        gradeRecord['scope']?.toString() ??
        widget.team['scope']?.toString() ??
        'capstone';
    final isPit = scope == 'pit';
    final canEnterAdviserGrades = widget.isAdviser && !isPit;
    if (canEnterAdviserGrades)
      _initializeGradingControllersForTeam(
        teamId,
        widget.selectedStage,
        gradeRecord,
      );
    final officiallyComplete =
        gradeRecord['is_officially_complete'] == true ||
        (widget.team['stages'] is List &&
            (widget.team['stages'] as List).any(
              (s) =>
                  s is Map &&
                  s['stage_label']?.toString() == widget.selectedStage &&
                  s['is_officially_complete'] == true,
            ));
    final guidance = AdviserGradingStatus.fromGrade(
      gradeRecord,
      enabled: gradingState.adviserGradingEnabled,
      loading: gradingState.isLoading,
      error: gradingState.error,
      officiallyComplete: officiallyComplete,
    );
    final key = '$teamId-${widget.selectedStage}';
    final rubric = widget.teamSelectedRubrics[key];
    final teamCriteria = _getTeamCriteria(rubric);
    final individualCriteria = _getIndividualCriteria(rubric);
    final members = _getMembers(gradeRecord);
    if (_selectedStudentIndex >= members.length) _selectedStudentIndex = 0;
    final complete = _allCriteriaFilledForTeam(
      teamId,
      widget.selectedStage,
      gradeRecord,
    );
    final filled = _filledCountForTeam(
      teamId,
      widget.selectedStage,
      gradeRecord,
    );
    final total = _totalCountForTeam(teamId, widget.selectedStage, gradeRecord);
    final completedMembers = members
        .where(
          (m) => _isStudentCriteriaComplete(
            teamId,
            widget.selectedStage,
            m['id'] ?? m['student_id'],
          ),
        )
        .length;
    final progressLabel = individualCriteria.isNotEmpty
        ? '$completedMembers of ${members.length} members scored'
        : '$filled of $total criteria completed';
    final secondary = DefensysTokens.textSecondaryOf(context);
    final primary = DefensysTokens.textPrimaryOf(context);
    final brand = DefensysTokens.maroonTextOf(context);
    final showAssessment = [
      'panel_score',
      'peer_score',
      'adviser_score',
      'final_grade',
    ].any((field) => gradeRecord[field] != null);

    Widget heading(String text) => Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
    );

    Widget memberList() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('Members'),
        const SizedBox(height: 10),
        for (var index = 0; index < members.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Builder(
              builder: (_) {
                final member = members[index];
                final id = member['id'] ?? member['student_id'];
                final selected = _selectedStudentIndex == index;
                final done = _isStudentCriteriaComplete(
                  teamId,
                  widget.selectedStage,
                  id,
                );
                final started =
                    widget.teamStudentCriteriaScoreCtrls[key]?[id]?.values.any(
                      (c) => c.text.trim().isNotEmpty,
                    ) ??
                    false;
                return Semantics(
                  selected: selected,
                  child: ShadButton.outline(
                    key: ValueKey('adviser-member-$id'),
                    height: 0,
                    expands: true,
                    padding: const EdgeInsets.all(12),
                    backgroundColor: selected
                        ? DefensysTokens.surfaceHigherOf(context)
                        : null,
                    onPressed: () =>
                        setState(() => _selectedStudentIndex = index),
                    child: Row(
                      children: [
                        if (selected) ...[
                          Icon(Icons.person_outline, size: 16, color: brand),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member['name']?.toString() ?? 'Student',
                                style: TextStyle(
                                  fontFamily: DefensysTokens.fontFamilyInter,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: selected ? brand : primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                done
                                    ? '${_computeStudentScore(teamId, widget.selectedStage, id, gradeRecord).toStringAsFixed(1)} / 100'
                                    : started
                                    ? 'In progress'
                                    : 'Not scored',
                                style: TextStyle(
                                  fontFamily: DefensysTokens.fontFamilyInter,
                                  fontSize: 11,
                                  color: secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (done)
                          Icon(Icons.check_rounded, size: 16, color: secondary),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );

    Widget activeMember() {
      final member = members[_selectedStudentIndex];
      final id = member['id'] ?? member['student_id'];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading('Scoring: ${member['name']}'),
          const SizedBox(height: 6),
          Text(
            _isStudentCriteriaComplete(teamId, widget.selectedStage, id) &&
                    _isTeamCriteriaComplete(teamId, widget.selectedStage)
                ? 'Student score: ${_computeStudentScore(teamId, widget.selectedStage, id, gradeRecord).toStringAsFixed(2)} / 100'
                : 'Score each criterion for this member.',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
          const SizedBox(height: 14),
          _buildCriteriaTable(
            criteria: individualCriteria,
            isTeam: false,
            studentId: id,
            teamId: teamId,
            stageLabel: widget.selectedStage,
            isReadOnly: !guidance.canGrade || gradingState.isSaving,
          ),
        ],
      );
    }

    final scoreSummary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Adviser score${individualCriteria.isNotEmpty ? ' · Team average' : ''}',
          style: TextStyle(fontSize: 12, color: secondary),
        ),
        const SizedBox(height: 4),
        Text(
          complete
              ? '${_computeOverallTeamScore(teamId, widget.selectedStage, gradeRecord).toStringAsFixed(2)} / 100'
              : 'Not complete',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: primary,
          ),
        ),
      ],
    );
    final submit = ShadButton(
      enabled: guidance.canGrade && complete && !gradingState.isSaving,
      backgroundColor: DefensysTokens.maroonOf(context),
      hoverBackgroundColor: DefensysTokens.maroonOf(
        context,
      ).withValues(alpha: 0.9),
      foregroundColor: Colors.white,
      onPressed: guidance.canGrade && complete && !gradingState.isSaving
          ? () => _submitAdviserGrade(
              teamId: teamId,
              stageLabel: widget.selectedStage,
              gradeRecord: gradeRecord,
            )
          : null,
      child: Flexible(
        child: Text(
          gradingState.isSaving
              ? 'Submitting grade…'
              : !guidance.canGrade
              ? 'Grading unavailable'
              : gradeRecord['adviser_score'] != null
              ? 'Update Adviser Grade'
              : 'Submit Adviser Grade',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    final remainingMembers = members.length - completedMembers;
    final incompleteReason = individualCriteria.isNotEmpty && members.isEmpty
        ? 'No members found in this team.'
        : !_isTeamCriteriaComplete(teamId, widget.selectedStage)
        ? 'Complete the team criteria to submit.'
        : remainingMembers > 0 && individualCriteria.isNotEmpty
        ? 'Score the remaining $remainingMembers ${remainingMembers == 1 ? 'member' : 'members'} to submit.'
        : 'Complete all criteria to submit.';

    return DefensysShadcnScope(
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: DefensysTokens.fontFamilyInter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                heading(isPit ? 'Event grades' : 'Grades'),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 240,
                      child: ShadSelect<int>(
                        key: ValueKey(
                          'grade-export-recipient-$teamId-${gradeRecord['id']}',
                        ),
                        minWidth: 0,
                        maxWidth: 240,
                        initialValue: 0,
                        placeholder: const Text('Team and all members'),
                        selectedOptionBuilder: (_, id) => Text(
                          id == 0
                              ? 'Team and all members'
                              : members
                                        .where(
                                          (m) =>
                                              parseAsInt(
                                                m['id'] ?? m['student_id'],
                                              ) ==
                                              id,
                                        )
                                        .firstOrNull?['name']
                                        ?.toString() ??
                                    'Student',
                          overflow: TextOverflow.ellipsis,
                        ),
                        options: [
                          const ShadOption(
                            value: 0,
                            child: Text('Team and all members'),
                          ),
                          for (final member in members)
                            if (parseAsInt(
                                  member['id'] ?? member['student_id'],
                                ) >
                                0)
                              ShadOption(
                                value: parseAsInt(
                                  member['id'] ?? member['student_id'],
                                ),
                                child: Text(
                                  member['name']?.toString() ?? 'Student',
                                ),
                              ),
                        ],
                        onChanged: (id) => setState(
                          () => _exportStudentId = id == 0 ? null : id,
                        ),
                      ),
                    ),
                    ReportExportMenu(
                      reportId: _exportStudentId == null
                          ? 'team-grade'
                          : 'individual-grade',
                      enabled:
                          parseAsInt(gradeRecord['id']) > 0 &&
                          !gradingState.isLoading,
                      configureExport: true,
                      params: {
                        'coverage': 'specific',
                        'grade_id': '${gradeRecord['id'] ?? ''}',
                        'team_id': '$teamId',
                        'scope': scope,
                        if (gradeRecord['semester_id'] ??
                                widget.team['semester_id']
                            case final Object semesterId)
                          'semester_id': '$semesterId',
                        if (_exportStudentId != null)
                          'student_id': '$_exportStudentId',
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (canEnterAdviserGrades) ...[
              Text(
                'Adviser evaluation',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  widget.selectedStage,
                  if (rubric != null) '${rubric['name']}',
                  if (rubric?['scale'] != null) '${rubric!['scale']}',
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: secondary),
              ),
              const SizedBox(height: 16),
              if (!guidance.canGrade)
                AdviserWorkflowReminder(
                  key: const Key('adviser-grading-reminder'),
                  onLightSurface: true,
                  title: guidance.title,
                  detail: guidance.detail,
                  tone: guidance.tone,
                )
              else
                Text(
                  gradeRecord['adviser_score'] != null
                      ? 'Grade submitted · You can update it before finalization.'
                      : 'You can grade this team now',
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
              const SizedBox(height: 20),
              if (gradingState.adviserGradingEnabled && rubric != null) ...[
                Text(
                  progressLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: total == 0 ? 0 : filled / total,
                  minHeight: 3,
                  color: DefensysTokens.maroonOf(context),
                  backgroundColor: DefensysTokens.borderOf(context),
                ),
                const SizedBox(height: 24),
                if (teamCriteria.isNotEmpty) ...[
                  heading(
                    individualCriteria.isNotEmpty
                        ? 'Team criteria'
                        : 'Criteria',
                  ),
                  const SizedBox(height: 12),
                  _buildCriteriaTable(
                    criteria: teamCriteria,
                    isTeam: true,
                    teamId: teamId,
                    stageLabel: widget.selectedStage,
                    isReadOnly: !guidance.canGrade || gradingState.isSaving,
                  ),
                  const SizedBox(height: 24),
                ],
                if (individualCriteria.isNotEmpty)
                  if (members.isEmpty)
                    Text(
                      'No members found in this team.',
                      style: TextStyle(color: secondary),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 760) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              memberList(),
                              const SizedBox(height: 18),
                              activeMember(),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 230, child: memberList()),
                            const SizedBox(width: 24),
                            Expanded(child: activeMember()),
                          ],
                        );
                      },
                    ),
                const SizedBox(height: 24),
                Divider(color: DefensysTokens.borderOf(context), height: 1),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth < 540
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            scoreSummary,
                            const SizedBox(height: 16),
                            submit,
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: scoreSummary),
                            const SizedBox(width: 16),
                            submit,
                          ],
                        ),
                ),
                if (guidance.canGrade && !complete) ...[
                  const SizedBox(height: 10),
                  Text(
                    incompleteReason,
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                ],
              ],
            ],
            if (showAssessment) ...[
              const SizedBox(height: 24),
              ShadAccordion<String>(
                children: [
                  ShadAccordionItem(
                    value: 'stage-grades',
                    title: heading(
                      isPit ? 'Event grade breakdown' : 'Stage grade breakdown',
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.selectedStage,
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                        const SizedBox(height: 12),
                        for (final entry in {
                          'Panel': 'panel_score',
                          'Peer': 'peer_score',
                          if (!isPit) 'Adviser': 'adviser_score',
                          'Overall grade': 'final_grade',
                        }.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(child: Text(entry.key)),
                                Text(
                                  parseAsDouble(
                                        gradeRecord[entry.value],
                                      )?.toStringAsFixed(2) ??
                                      'Pending',
                                ),
                              ],
                            ),
                          ),
                        if (gradeRecord['status'] == 'published')
                          Text(
                            'Published · ${gradeRecord['result'] ?? 'pending'}',
                            style: TextStyle(fontSize: 12, color: secondary),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else if (!canEnterAdviserGrades)
              Text(
                'No grades are available for this ${isPit ? 'event' : 'stage'} yet.',
                style: TextStyle(fontSize: 12, color: secondary),
              ),
          ],
        ),
      ),
    );
  }
}
