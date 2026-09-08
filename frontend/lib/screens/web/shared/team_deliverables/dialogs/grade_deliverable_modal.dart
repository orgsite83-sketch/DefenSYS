import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/toasts/feedback_toast.dart';
import 'package:defensys/widgets/widgets.dart';

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
  final Map<String, Map<String, TextEditingController>> teamCriteriaScoreCtrls;
  final Map<String, Map<dynamic, Map<String, TextEditingController>>> teamStudentCriteriaScoreCtrls;
  final Map<String, TextEditingController> teamManualScoreCtrls;
  final Map<String, Map<String, dynamic>?> teamSelectedRubrics;

  const GradeDeliverableTab({
    super.key,
    required this.team,
    required this.selectedStage,
    required this.isAdviser,
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

    double total = 0;
    double maxTotal = 0;

    final teamSubMap = widget.teamCriteriaScoreCtrls[key] ?? const {};
    if (targetType == 'team' || targetType == 'both') {
      for (final c in teamCrits) {
        final name = c['name']?.toString() ?? '';
        final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
        final entered = double.tryParse(teamSubMap[name]?.text ?? '') ?? 0;
        total += entered.clamp(0, maxScore);
        maxTotal += maxScore;
      }
    }

    if (studentId != null && (targetType == 'individual' || targetType == 'both')) {
      final studentSubMap = widget.teamStudentCriteriaScoreCtrls[key]?[studentId] ?? const {};
      for (final c in indCrits) {
        final name = c['name']?.toString() ?? '';
        final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
        final entered = double.tryParse(studentSubMap[name]?.text ?? '') ?? 0;
        total += entered.clamp(0, maxScore);
        maxTotal += maxScore;
      }
    }

    if (maxTotal == 0) return 0;
    return (total / maxTotal * 100).clamp(0, 100);
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

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _gradeBadge(String label, dynamic score) {
    final parsedScore = parseAsDouble(score);
    final hasScore = parsedScore != null;
    final valueText = hasScore ? parsedScore.toStringAsFixed(2) : 'Pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: hasScore ? const Color(0xFFF3F4F6) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasScore ? const Color(0xFFE5E7EB) : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            valueText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: hasScore ? AppColors.textPrimary : const Color(0xFFB45309),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overallGradeBadge(dynamic score, String result) {
    final parsedScore = parseAsDouble(score);
    final hasScore = parsedScore != null;
    final valueText = hasScore ? parsedScore.toStringAsFixed(2) : 'Pending';

    Color bg = const Color(0xFFF3F4F6);
    Color border = const Color(0xFFE5E7EB);
    Color text = AppColors.textPrimary;

    if (hasScore) {
      if (result == 'passed') {
        bg = const Color(0xFFECFDF5);
        border = const Color(0xFFA7F3D0);
        text = const Color(0xFF047857);
      } else {
        bg = const Color(0xFFFEF2F2);
        border = const Color(0xFFFCA5A5);
        text = const Color(0xFFB91C1C);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Overall Grade: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            valueText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: text,
            ),
          ),
          if (hasScore) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: result == 'passed' ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                result == 'passed' ? 'PASSED' : 'FAILED',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: result == 'passed' ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'No criteria defined for this section.',
          style: TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
        ),
      );
    }

    final key = '$teamId-$stageLabel';
    final subMap = isTeam
        ? (widget.teamCriteriaScoreCtrls[key] ?? const {})
        : (widget.teamStudentCriteriaScoreCtrls[key]?[studentId] ?? const {});

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                  ? const Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 0.5))
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          desc,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text('/ $maxScore', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: isReadOnly
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            ctrl.text.isNotEmpty ? ctrl.text : '-',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        )
                      : TextField(
                          controller: ctrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: 'Score',
                            hintStyle: const TextStyle(fontSize: 11),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                ),
              ],
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
    
    final stagePayload = (widget.team['stages'] is List)
        ? (widget.team['stages'] as List).firstWhere(
            (s) => s is Map && s['stage_label']?.toString() == widget.selectedStage,
            orElse: () => null,
          )
        : null;

    final gradeRecord = gradingState.grades.firstWhere(
      (g) => parseAsInt(g['team_id']) == teamId && g['stage_label']?.toString() == widget.selectedStage,
      orElse: () {
        if (widget.team['grade'] is Map && widget.team['grade']['stage_label']?.toString() == widget.selectedStage) {
          return Map<String, dynamic>.from(widget.team['grade'] as Map);
        }
        if (stagePayload is Map && stagePayload['grade'] is Map && stagePayload['grade']['stage_label']?.toString() == widget.selectedStage) {
          return Map<String, dynamic>.from(stagePayload['grade'] as Map);
        }
        return <String, dynamic>{};
      },
    );

    _initializeGradingControllersForTeam(teamId, widget.selectedStage, gradeRecord);

    final status = gradeRecord['status']?.toString() ?? 'pending';
    final panelScore = gradeRecord['panel_score'];
    final peerScore = gradeRecord['peer_score'];
    final adviserScore = gradeRecord['adviser_score'];
    final finalGrade = gradeRecord['final_grade'];
    final result = gradeRecord['result']?.toString() ?? 'pending';

    final isOfficiallyComplete = gradeRecord['is_officially_complete'] == true ||
        (widget.team['stages'] is List &&
            (widget.team['stages'] as List).any((s) =>
                s is Map &&
                s['stage_label']?.toString() == widget.selectedStage &&
                s['is_officially_complete'] == true));
    final isPublished = status == 'published';
    final isGradingLocked = isOfficiallyComplete || isPublished;

    Color statusBg = const Color(0xFFFEF3C7);
    Color statusText = const Color(0xFFD97706);
    String statusLabel = 'Pending';

    if (status == 'published') {
      statusBg = const Color(0xFFD1FAE5);
      statusText = const Color(0xFF047857);
      statusLabel = 'Published';
    } else if (status == 'awaiting_peers') {
      statusBg = const Color(0xFFDBEAFE);
      statusText = const Color(0xFF2563EB);
      statusLabel = 'Awaiting Peers';
    }

    final key = '$teamId-${widget.selectedStage}';
    final assignedRubric = widget.teamSelectedRubrics[key];
    final isAlreadyGraded = adviserScore != null;

    final targetType = assignedRubric?['target_type']?.toString() ?? 'team';
    final teamCrits = _getTeamCriteria(assignedRubric);
    final indCrits = _getIndividualCriteria(assignedRubric);
    final members = _getMembers(gradeRecord);

    if (_selectedStudentIndex >= members.length && members.isNotEmpty) {
      _selectedStudentIndex = 0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Overall Grade Badges
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Grade Overview · ${widget.selectedStage}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  color: statusText,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _gradeBadge('Panel', panelScore),
            _gradeBadge('Peer', peerScore),
            _gradeBadge('Adviser', adviserScore),
            _overallGradeBadge(finalGrade, result),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(color: Color(0xFFF1F5F9), height: 1),
        const SizedBox(height: 16),

        // Rubric Grading Form
        if (widget.isAdviser) ...[
          if (!gradingState.adviserGradingEnabled) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 48, color: AppColors.textSecondary),
                  SizedBox(height: 12),
                  Text(
                    'Adviser Grading is Disabled',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Adviser grading is currently turned off by the administrator for this stage/period.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ] else if (assignedRubric == null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No adviser rubric is assigned for this defense stage yet. Ask your administrator to set panel, adviser, and peer rubrics in Defense Stages Setup or the scheduler.',
                      style: TextStyle(color: AppColors.warning, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            if (isGradingLocked) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isOfficiallyComplete
                            ? 'This defense stage is officially complete. Adviser grades are locked and cannot be edited.'
                            : 'Grades for this stage have been finalized and published. Modifications are locked.',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              children: [
                _sectionTitle('Rubric: ${assignedRubric['name']} (${assignedRubric['scale'] ?? ''})'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: AppColors.maroon.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    targetType == 'both'
                        ? 'Both (Team & Individual)'
                        : targetType == 'individual'
                            ? 'Individual'
                            : 'Team',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.maroon,
                    ),
                  ),
                ),
                const Spacer(),
                Builder(builder: (_) {
                  final total = _totalCountForTeam(teamId, widget.selectedStage, gradeRecord);
                  final filled = _filledCountForTeam(teamId, widget.selectedStage, gradeRecord);
                  final allDone = filled == total && total > 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: allDone
                          ? AppColors.success.withValues(alpha: 0.1)
                          : AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$filled / $total scored',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: allDone ? AppColors.success : AppColors.warning,
                      ),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 10),

            // Team-wide criteria section
            if (teamCrits.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.groups_outlined, size: 16, color: AppColors.maroon),
                  const SizedBox(width: 6),
                  Text(
                    targetType == 'both' ? 'Team-Wide Criteria' : 'Criteria',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _isTeamCriteriaComplete(teamId, widget.selectedStage)
                          ? AppColors.success.withValues(alpha: 0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _isTeamCriteriaComplete(teamId, widget.selectedStage) ? '✓ Complete' : 'Required',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _isTeamCriteriaComplete(teamId, widget.selectedStage)
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildCriteriaTable(
                criteria: teamCrits,
                isTeam: true,
                teamId: teamId,
                stageLabel: widget.selectedStage,
                isReadOnly: isGradingLocked,
              ),
              const SizedBox(height: 16),
            ],

            // Individual criteria section
            if (indCrits.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.person_outline_rounded, size: 16, color: AppColors.maroon),
                  const SizedBox(width: 6),
                  const Text(
                    'Individual Criteria (Score Each Member)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (members.isNotEmpty) ...[
                // Horizontal student tabs
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: members.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, idx) {
                      final m = members[idx];
                      final sId = m['id'] ?? m['student_id'];
                      final isSelected = _selectedStudentIndex == idx;
                      final isComplete = _isStudentCriteriaComplete(teamId, widget.selectedStage, sId);
                      final isLeader = m['is_leader'] == true || m['role']?.toString() == 'leader';
                      final sScore = _computeStudentScore(teamId, widget.selectedStage, sId, gradeRecord);

                      return InkWell(
                        onTap: () => setState(() => _selectedStudentIndex = idx),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.maroon : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? AppColors.maroon : const Color(0xFFE2E8F0),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isLeader) ...[
                                Icon(Icons.star_rounded,
                                    size: 14, color: isSelected ? Colors.amberAccent : Colors.amber.shade700),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                m['name']?.toString() ?? 'Student',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  color: isSelected ? Colors.white : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : isComplete
                                          ? AppColors.success.withValues(alpha: 0.1)
                                          : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isComplete ? '${sScore.toStringAsFixed(1)}%' : 'Pending',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : isComplete
                                            ? AppColors.success
                                            : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),

                // Active student criteria form
                if (_selectedStudentIndex < members.length) ...[
                  Builder(builder: (_) {
                    final activeMember = members[_selectedStudentIndex];
                    final sId = activeMember['id'] ?? activeMember['student_id'];
                    final sScore = _computeStudentScore(teamId, widget.selectedStage, sId, gradeRecord);
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.maroon.withValues(alpha: 0.04),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                              border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'Scoring: ${activeMember['name']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                    color: AppColors.maroon,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'Student Score: ${sScore.toStringAsFixed(2)} / 100',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildCriteriaTable(
                            criteria: indCrits,
                            isTeam: false,
                            studentId: sId,
                            teamId: teamId,
                            stageLabel: widget.selectedStage,
                            isReadOnly: isGradingLocked,
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ] else ...[
                const Text('No members found in this team.', style: TextStyle(color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 16),
            ],

            // Score Summary Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.maroon.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.maroon.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  if (targetType != 'team' && members.isNotEmpty) ...[
                    ...members.map((m) {
                      final sId = m['id'] ?? m['student_id'];
                      final sScore = _computeStudentScore(teamId, widget.selectedStage, sId, gradeRecord);
                      final isComplete = _isStudentCriteriaComplete(teamId, widget.selectedStage, sId);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Text(
                              m['name']?.toString() ?? 'Student',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            ),
                            const Spacer(),
                            Text(
                              isComplete ? '${sScore.toStringAsFixed(2)} / 100' : 'Incomplete',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isComplete ? AppColors.maroon : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                  ],
                  Row(
                    children: [
                      Text(
                        targetType != 'team' ? 'Overall Team Adviser Score (Avg):' : 'Computed Adviser Score:',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                      ),
                      const Spacer(),
                      Text(
                        _computeOverallTeamScore(teamId, widget.selectedStage, gradeRecord).toStringAsFixed(2),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.maroon),
                      ),
                      const Text(' / 100', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Submit Button
            Builder(builder: (_) {
              if (isGradingLocked) {
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.lock_rounded, size: 14),
                    label: Text(
                      isOfficiallyComplete
                          ? 'Stage Officially Complete (Grades Locked)'
                          : 'Grade Finalized (Locked)',
                    ),
                    style: ElevatedButton.styleFrom(
                      disabledBackgroundColor: const Color(0xFFE2E8F0),
                      disabledForegroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                );
              }
              final canSubmit = _allCriteriaFilledForTeam(teamId, widget.selectedStage, gradeRecord);
              return SizedBox(
                width: double.infinity,
                child: DefensysSaveButton(
                  onPressed: canSubmit
                      ? () => _submitAdviserGrade(
                            teamId: teamId,
                            stageLabel: widget.selectedStage,
                            gradeRecord: gradeRecord,
                          )
                      : null,
                  isSaving: gradingState.isSaving,
                  label: isAlreadyGraded ? 'Update Adviser Grade' : 'Submit Adviser Grade',
                  savingLabel: 'Submitting Grade…',
                  isPill: false,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              );
            }),
          ],
        ],
      ],
    );
  }
}
