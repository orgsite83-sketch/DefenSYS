import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/widgets/feedback_toast.dart';

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
  final Map<String, TextEditingController> teamManualScoreCtrls;
  final Map<String, Map<String, dynamic>?> teamSelectedRubrics;

  const GradeDeliverableTab({
    super.key,
    required this.team,
    required this.selectedStage,
    required this.isAdviser,
    required this.teamCriteriaScoreCtrls,
    required this.teamManualScoreCtrls,
    required this.teamSelectedRubrics,
  });

  @override
  ConsumerState<GradeDeliverableTab> createState() => _GradeDeliverableTabState();
}

class _GradeDeliverableTabState extends ConsumerState<GradeDeliverableTab> {
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
      'criteria': criteria is List ? criteria : [],
    };
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
    final assigned = _assignedRubricFromGrade(gradeRecord);
    widget.teamSelectedRubrics[key] = assigned;

    if (assigned != null) {
      final savedScores = <String, String>{};
      if (gradeRecord['breakdowns'] is List) {
        for (final row in gradeRecord['breakdowns'] as List) {
          if (row is! Map) continue;
          if (row['evaluation_type']?.toString() != 'adviser') continue;
          final name = row['criterion_name']?.toString() ?? '';
          if (name.isNotEmpty) {
            savedScores[name] = row['score']?.toString() ?? '';
          }
        }
      }

      for (final c in (assigned['criteria'] as List? ?? [])) {
        final cMap = c as Map;
        final name = cMap['name']?.toString() ?? '';
        criteriaCtrls[name] = TextEditingController(text: savedScores[name] ?? '');
      }
    }
    widget.teamCriteriaScoreCtrls[key] = criteriaCtrls;
  }

  double _computeTotalScoreForTeam(int teamId, String stageLabel) {
    final key = '$teamId-$stageLabel';
    final rubric = widget.teamSelectedRubrics[key];
    if (rubric == null) return 0;
    final criteria = (rubric['criteria'] as List? ?? []);
    if (criteria.isEmpty) return 0;
    double total = 0;
    double maxTotal = 0;
    final subMap = widget.teamCriteriaScoreCtrls[key] ?? const {};
    for (final c in criteria) {
      final name = (c as Map)['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final entered = double.tryParse(subMap[name]?.text ?? '') ?? 0;
      total += entered.clamp(0, maxScore);
      maxTotal += maxScore;
    }
    if (maxTotal == 0) return 0;
    return (total / maxTotal * 100).clamp(0, 100);
  }

  bool _allCriteriaFilledForTeam(int teamId, String stageLabel) {
    final key = '$teamId-$stageLabel';
    final rubric = widget.teamSelectedRubrics[key];
    if (rubric == null) return false;
    final criteria = (rubric['criteria'] as List? ?? []);
    if (criteria.isEmpty) return false;
    final subMap = widget.teamCriteriaScoreCtrls[key] ?? const {};
    for (final c in criteria) {
      final name = (c as Map)['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final text = subMap[name]?.text.trim() ?? '';
      if (text.isEmpty) return false;
      final value = double.tryParse(text);
      if (value == null || value < 0 || value > maxScore) return false;
    }
    return true;
  }

  int _filledCountForTeam(int teamId, String stageLabel) {
    final key = '$teamId-$stageLabel';
    final rubric = widget.teamSelectedRubrics[key];
    if (rubric == null) return 0;
    final criteria = (rubric['criteria'] as List? ?? []);
    int count = 0;
    final subMap = widget.teamCriteriaScoreCtrls[key] ?? const {};
    for (final c in criteria) {
      final name = (c as Map)['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final text = subMap[name]?.text.trim() ?? '';
      final value = double.tryParse(text);
      if (text.isNotEmpty && value != null && value >= 0 && value <= maxScore) count++;
    }
    return count;
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
    final subMap = widget.teamCriteriaScoreCtrls[key] ?? const {};
    final manualCtrl = widget.teamManualScoreCtrls[key];

    double adviserScore;
    List<Map<String, dynamic>> criteriaScores = [];
    int? rubricId;

    if (rubric != null) {
      final criteria = (rubric['criteria'] as List? ?? []);
      for (final c in criteria) {
        final cMap = c as Map;
        final name = cMap['name']?.toString() ?? '';
        final maxScore = ((cMap['max_score'] as num?) ?? 10).toDouble();
        final entered = (double.tryParse(subMap[name]?.text ?? '') ?? 0).clamp(0, maxScore);
        criteriaScores.add({
          'criterion_name': name,
          'score': entered,
          'max_score': maxScore,
          'display_order': cMap['display_order'] ?? 0,
        });
      }
      adviserScore = _computeTotalScoreForTeam(teamId, stageLabel);
      rubricId = rubric['id'] as int?;
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

  Widget _buildCriteriaTableForTeam(int teamId, String stageLabel, Map<String, dynamic> rubric) {
    final criteria = (rubric['criteria'] as List? ?? []);
    if (criteria.isEmpty) {
      return const Text(
        'This rubric has no criteria defined.',
        style: TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
      );
    }

    final key = '$teamId-$stageLabel';
    final subMap = widget.teamCriteriaScoreCtrls[key] ?? const {};

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: criteria.asMap().entries.map((entry) {
          final i = entry.key;
          final c = entry.value as Map;
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
                  child: TextField(
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
    
    final gradeRecord = gradingState.grades.firstWhere(
      (g) => parseAsInt(g['team_id']) == teamId && g['stage_label']?.toString() == widget.selectedStage,
      orElse: () => widget.team['grade'] is Map ? Map<String, dynamic>.from(widget.team['grade'] as Map) : <String, dynamic>{},
    );

    _initializeGradingControllersForTeam(teamId, widget.selectedStage, gradeRecord);

    final status = gradeRecord['status']?.toString() ?? 'pending';
    final panelScore = gradeRecord['panel_score'];
    final peerScore = gradeRecord['peer_score'];
    final adviserScore = gradeRecord['adviser_score'];
    final finalGrade = gradeRecord['final_grade'];
    final result = gradeRecord['result']?.toString() ?? 'pending';

    final scheduleId = gradeRecord['schedule_id'];
    final rawScheduledDate = gradeRecord['scheduled_date'];

    DateTime? scheduledDate;
    if (rawScheduledDate != null) {
      scheduledDate = DateTime.tryParse(rawScheduledDate.toString());
    }

    bool isLockedBySchedule = false;
    String lockReason = '';

    if (scheduleId == null) {
      isLockedBySchedule = true;
      lockReason = "Adviser grading is locked because this team's defense has not been scheduled yet.";
    } else {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (scheduledDate != null && today.isBefore(scheduledDate)) {
        final formattedDate = "${scheduledDate.year}-${scheduledDate.month.toString().padLeft(2, '0')}-${scheduledDate.day.toString().padLeft(2, '0')}";
        isLockedBySchedule = true;
        lockReason = "Adviser grading is locked until the scheduled defense date: $formattedDate.";
      }
    }

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Overall Grade Badges
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Grade Overview',
              style: TextStyle(
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
          ] else if (isLockedBySchedule) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 48, color: AppColors.textSecondary),
                  const SizedBox(height: 12),
                  const Text(
                    'Adviser Grading is Locked',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    lockReason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
            Row(
              children: [
                _sectionTitle('Rubric: ${assignedRubric['name']} (${assignedRubric['scale'] ?? ''})'),
                const Spacer(),
                Builder(builder: (_) {
                  final total = (assignedRubric['criteria'] as List? ?? []).length;
                  final filled = _filledCountForTeam(teamId, widget.selectedStage);
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
            _buildCriteriaTableForTeam(teamId, widget.selectedStage, assignedRubric),
            const SizedBox(height: 16),
            // Computed score
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.maroon.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.maroon.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Text(
                    'Computed Adviser Score:',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                  ),
                  const Spacer(),
                  Text(
                    _computeTotalScoreForTeam(teamId, widget.selectedStage).toStringAsFixed(2),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.maroon),
                  ),
                  Text(' / 100', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Submit Button
            Builder(builder: (_) {
              final canSubmit = _allCriteriaFilledForTeam(teamId, widget.selectedStage);
              return SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (gradingState.isSaving || !canSubmit)
                      ? null
                      : () => _submitAdviserGrade(
                            teamId: teamId,
                            stageLabel: widget.selectedStage,
                            gradeRecord: gradeRecord,
                          ),
                  icon: gradingState.isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded, size: 14),
                  label: Text(isAlreadyGraded ? 'Update Adviser Grade' : 'Submit Adviser Grade'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canSubmit ? AppColors.maroon : Colors.grey.shade300,
                    foregroundColor: canSubmit ? Colors.white : Colors.grey.shade500,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              );
            }),
          ],
        ],
      ],
    );
  }
}
