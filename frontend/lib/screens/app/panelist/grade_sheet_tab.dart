import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'panelist_models.dart';
import '../../../utils/universal_file_viewer.dart';
import '../../../config/api_config.dart';
import '../../../services/auth_provider.dart';
import '../../../services/authenticated_client.dart';
import '../../../services/authz_errors.dart';
import '../../../services/session_expired.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../toasts/feedback_toast.dart';
import '../../../widgets/tactile_button.dart';

class GradeSheetTab extends ConsumerStatefulWidget {
  final List<TeamData> teams;
  final int selectedTeamIndex;
  final void Function(int) onTeamChanged;
  final VoidCallback? onGradesSubmitted;
  final Future<void> Function()? onRefresh;

  const GradeSheetTab({
    super.key,
    required this.teams,
    required this.selectedTeamIndex,
    required this.onTeamChanged,
    this.onGradesSubmitted,
    this.onRefresh,
  });

  @override
  ConsumerState<GradeSheetTab> createState() => _GradeSheetTabState();
}

class _GradeSheetTabState extends ConsumerState<GradeSheetTab> {
  List<Criterion> _criteria = [];
  int _lastTeamIndex = -1;

  final Map<String, List<Criterion>> _studentCriteria = {};
  final Map<String, TextEditingController> _studentRemarksControllers = {};
  TextEditingController _teamRemarksController = TextEditingController();
  TextEditingController _verdictRemarksController = TextEditingController();
  String _selectedVerdict = 'approved';
  DateTime? _revisionDeadline;
  bool _isSubmittingVerdict = false;
  int _selectedStudentIndex = 0;
  String _selectedStageKey = 'all';

  String _teamStageEventKey(TeamData t) {
    if (t.isCapstone) {
      return t.displayStage.isNotEmpty ? t.displayStage : 'Capstone Defense';
    } else {
      if (t.displayEvent.isNotEmpty && t.displayStage.isNotEmpty && t.displayEvent != t.displayStage) {
        return '${t.displayEvent} • ${t.displayStage}';
      }
      return t.displayStage.isNotEmpty
          ? t.displayStage
          : (t.displayEvent.isNotEmpty ? t.displayEvent : 'PIT Expo');
    }
  }

  @override
  void initState() {
    super.initState();
    _syncRubricForCurrentTeam();
  }

  @override
  void dispose() {
    for (var controller in _studentRemarksControllers.values) {
      controller.dispose();
    }
    _teamRemarksController.dispose();
    _verdictRemarksController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GradeSheetTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTeamIndex != widget.selectedTeamIndex ||
        oldWidget.teams != widget.teams) {
      _syncRubricForCurrentTeam();
    }
  }

  List<Criterion> _parseCriteriaFromRubricMap(Map<String, dynamic> rubric, {String? filterTargetType}) {
    final list = rubric['criteria'] as List? ?? [];
    return list.where((c) {
      if (filterTargetType == null) return true;
      final t = c['target_type']?.toString() ?? 'team';
      return t == filterTargetType;
    }).map((c) {
      return Criterion(
        (c['name'] ?? 'Criterion').toString(),
        ((c['max_score'] as num?) ?? 10).toDouble(),
        id: int.tryParse(c['id']?.toString() ?? ''),
      );
    }).toList();
  }

  void _syncRubricForCurrentTeam() {
    if (widget.teams.isEmpty) {
      return;
    }

    final team = widget.teams[widget.selectedTeamIndex];

    if (_lastTeamIndex != widget.selectedTeamIndex) {
      _lastTeamIndex = widget.selectedTeamIndex;
      _selectedStudentIndex = 0;

      _studentCriteria.clear();
      for (var controller in _studentRemarksControllers.values) {
        controller.dispose();
      }
      _studentRemarksControllers.clear();
      _teamRemarksController.dispose();
      _teamRemarksController = TextEditingController();
      _verdictRemarksController.dispose();
      _verdictRemarksController = TextEditingController(text: team.verdictRemarks ?? '');
      _selectedVerdict = (team.verdict != null && team.verdict!.isNotEmpty) ? team.verdict! : 'approved';
      _revisionDeadline = team.revisionDeadline != null ? DateTime.tryParse(team.revisionDeadline!) : null;

      final embedded = team.panelRubric;
      if (embedded != null) {
        if (team.targetType == 'both') {
          _criteria = _parseCriteriaFromRubricMap(embedded, filterTargetType: 'team');
          for (var member in team.memberDetails) {
            _studentCriteria[member.id] = _parseCriteriaFromRubricMap(embedded, filterTargetType: 'individual');
            _studentRemarksControllers[member.id] = TextEditingController();
          }
        } else if (team.isIndividualTarget) {
          for (var member in team.memberDetails) {
            _studentCriteria[member.id] = _parseCriteriaFromRubricMap(embedded);
            _studentRemarksControllers[member.id] = TextEditingController();
          }
        } else {
          _criteria = _parseCriteriaFromRubricMap(embedded);
        }
      } else {
        _criteria = [];
      }

      if (team.submittedSubmissions.isNotEmpty) {
        _hydrateSubmittedScores(team);
      }
    }
  }

  void _hydrateSubmittedScores(TeamData team) {
    for (final sub in team.submittedSubmissions) {
      final rawStudentId = sub['student_id']?.toString();
      final remarks = (sub['remarks'] ?? '').toString();
      final scoresList = sub['criteria_scores'] as List? ?? [];
      final scoreMap = <int, double>{};
      for (final s in scoresList) {
        if (s is Map) {
          final cId = int.tryParse(s['criterion_id']?.toString() ?? '');
          final scoreVal = (s['score'] as num?)?.toDouble();
          if (cId != null && scoreVal != null) {
            scoreMap[cId] = scoreVal;
          }
        }
      }

      if (rawStudentId == null || rawStudentId == 'null' || rawStudentId.isEmpty) {
        _teamRemarksController.text = remarks;
        for (var c in _criteria) {
          if (c.id != null && scoreMap.containsKey(c.id)) {
            c.score = scoreMap[c.id]!;
          }
        }
      } else {
        if (_studentRemarksControllers.containsKey(rawStudentId)) {
          _studentRemarksControllers[rawStudentId]!.text = remarks;
        }
        final memberCriteria = _studentCriteria[rawStudentId] ?? [];
        for (var c in memberCriteria) {
          if (c.id != null && scoreMap.containsKey(c.id)) {
            c.score = scoreMap[c.id]!;
          }
        }
      }
    }
  }

  String? _panelRubricName(TeamData team) {
    return team.panelRubric?['name']?.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.teams.isEmpty) {
      final emptyContent = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No teams available', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );

      if (widget.onRefresh == null) return emptyContent;
      return LayoutBuilder(
        builder: (context, constraints) {
          return RefreshIndicator(
            color: DefensysTokens.maroon,
            onRefresh: widget.onRefresh!,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: emptyContent,
              ),
            ),
          );
        },
      );
    }

    final team = widget.teams[widget.selectedTeamIndex];
    final panelRubricName = _panelRubricName(team);
    final hasPanelRubric = team.panelRubric != null;
    final isLocked = team.isPosted;
    final hasValidScope = team.hasValidScope;
    
    final isIndividual = team.isIndividualTarget;
    final isBoth = team.targetType == 'both';
    final canPost = hasValidScope &&
        hasPanelRubric &&
        (isBoth
            ? (_criteria.isNotEmpty || _studentCriteria.isNotEmpty)
            : (isIndividual ? _studentCriteria.isNotEmpty : _criteria.isNotEmpty)) &&
        !isLocked &&
        !team.isLockedByDate;

    final List<Criterion> currentTeamCriteria = _criteria;
    final List<Criterion> currentStudentCriteria = isIndividual || isBoth
        ? (team.memberDetails.isNotEmpty && _selectedStudentIndex < team.memberDetails.length
            ? (_studentCriteria[team.memberDetails[_selectedStudentIndex].id] ?? [])
            : <Criterion>[])
        : <Criterion>[];

    final activeCriteria = isIndividual ? currentStudentCriteria : (_criteria.isNotEmpty ? _criteria : team.criteria);

    final double total;
    final double maxTotal;
    if (isBoth) {
      final tScore = currentTeamCriteria.fold(0.0, (s, c) => s + c.score);
      final tMax = currentTeamCriteria.fold(0.0, (s, c) => s + c.maxScore);
      final sScore = currentStudentCriteria.fold(0.0, (s, c) => s + c.score);
      final sMax = currentStudentCriteria.fold(0.0, (s, c) => s + c.maxScore);
      total = tScore + sScore;
      maxTotal = tMax + sMax;
    } else if (isIndividual) {
      total = currentStudentCriteria.fold(0.0, (s, c) => s + c.score);
      maxTotal = currentStudentCriteria.fold(0.0, (s, c) => s + c.maxScore);
    } else {
      final criteriaList = _criteria.isNotEmpty ? _criteria : team.criteria;
      total = criteriaList.fold(0.0, (s, c) => s + c.score);
      maxTotal = criteriaList.fold(0.0, (s, c) => s + c.maxScore);
    }
    final double panelPct = maxTotal > 0 ? (total / maxTotal * 100) : 0.0;

    final panelWeight = team.panelWeight;
    final peerWeight = team.peerWeight;
    final showAdviser = team.isCapstone && team.adviserWeight > 0;

    final stageKeys = <String>{};
    for (final t in widget.teams) {
      stageKeys.add(_teamStageEventKey(t));
    }

    final List<int> filteredIndices;
    if (_selectedStageKey == 'all' || !stageKeys.contains(_selectedStageKey)) {
      filteredIndices = List.generate(widget.teams.length, (i) => i);
    } else {
      filteredIndices = [];
      for (int i = 0; i < widget.teams.length; i++) {
        if (_teamStageEventKey(widget.teams[i]) == _selectedStageKey) {
          filteredIndices.add(i);
        }
      }
    }
    final currentIndexInFilter = filteredIndices.indexOf(widget.selectedTeamIndex);

    final scrollContent = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStageSelector(team, stageKeys),
          _buildLineupStepper(
            team,
            filteredIndices,
            currentIndexInFilter >= 0 ? currentIndexInFilter : 0,
          ),
          const SizedBox(height: 12),
          _buildTeamDossier(team, isLocked, hasValidScope),
          const SizedBox(height: 14),
          _buildScoreHero(
            total: total,
            maxTotal: maxTotal,
            panelPct: panelPct,
            panelWeight: panelWeight,
            peerWeight: peerWeight,
            showAdviser: showAdviser,
            team: team,
            hasValidScope: hasValidScope,
          ),
          const SizedBox(height: 14),
          _buildDefenseMaterialsCard(team),
          const SizedBox(height: 14),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: DefensysTokens.border, width: 1),
            ),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.assignment_outlined,
                              size: 18,
                              color: DefensysTokens.maroon,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                panelRubricName != null ? 'Panel rubric: $panelRubricName' : 'Panel Rubric Criteria',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: DefensysTokens.maroon,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (team.panelRubric?['target_type'] != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            team.targetType.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (isIndividual) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Grade by Individual Student',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    _buildStudentSelector(team),
                  ],
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  if (!hasPanelRubric)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No panel rubric on this schedule. Ask the PIT lead or admin to set it in Defense Scheduler.',
                              style: TextStyle(color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isBoth) ...[
                    if (currentTeamCriteria.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.groups,
                            size: 18,
                            color: DefensysTokens.maroon,
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Team Criteria (Graded once for the team)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: DefensysTokens.maroon,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...currentTeamCriteria.map((c) => _criterionRow(c, isLocked || team.isLockedByDate)),
                    ],
                    if (_studentCriteria.values.any((list) => list.isNotEmpty)) ...[
                      if (currentTeamCriteria.isNotEmpty) const SizedBox(height: 20),
                      Row(
                        children: [
                          const Icon(
                            Icons.person,
                            size: 18,
                            color: DefensysTokens.maroon,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Individual Student Criteria',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: DefensysTokens.maroon,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Select a team member to evaluate individually:',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      _buildStudentSelector(team),
                      const SizedBox(height: 12),
                      if (currentStudentCriteria.isNotEmpty)
                        ...currentStudentCriteria.map((c) => _criterionRow(c, isLocked || team.isLockedByDate)),
                    ] else if (currentTeamCriteria.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.blue),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Rubric target is set to "Both", but all current criteria are set to Team.',
                                style: TextStyle(fontSize: 12, color: Colors.blue),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (currentTeamCriteria.isEmpty && currentStudentCriteria.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Assigned panel rubric has no criteria yet.',
                                style: TextStyle(color: Colors.orange),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ] else ...[
                    if (activeCriteria.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Assigned panel rubric has no criteria yet.',
                                style: TextStyle(color: Colors.orange),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...activeCriteria.map((c) => _criterionRow(c, isLocked || team.isLockedByDate)),
                  ],
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Panel Raw Score',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${total.toStringAsFixed(1)} / ${maxTotal.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: DefensysTokens.maroon,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (hasValidScope)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Score (normalized)',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${panelPct.toStringAsFixed(1)}%  ×  $panelWeight%  =  ${(panelPct * panelWeight / 100).toStringAsFixed(1)} pts',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Score weighting is unavailable until the schedule scope is repaired.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 16),
                   if (team.isLockedByDate)
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_clock,
                            size: 20,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'This defense is scheduled for ${team.scheduledDate != null ? DateFormat('MMMM d, yyyy').format(team.scheduledDate!) : 'scheduled date'}. Grading is not open yet.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (!isLocked) ...[
                    if (isBoth) ...[
                      TextField(
                        controller: _teamRemarksController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Team Remarks / Feedback',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (team.memberDetails.isNotEmpty && _selectedStudentIndex < team.memberDetails.length)
                        TextField(
                          controller: _studentRemarksControllers[team.memberDetails[_selectedStudentIndex].id],
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Individual Remarks for ${team.memberDetails[_selectedStudentIndex].name}',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignLabelWithHint: true,
                          ),
                        ),
                    ] else ...[
                      TextField(
                        controller: isIndividual
                            ? (team.memberDetails.isNotEmpty && _selectedStudentIndex < team.memberDetails.length
                                ? _studentRemarksControllers[team.memberDetails[_selectedStudentIndex].id]
                                : null)
                            : _teamRemarksController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: isIndividual
                              ? 'Remarks / Feedback for ${team.memberDetails[_selectedStudentIndex].name}'
                              : 'Remarks / Feedback',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TactileButton.secondary(
                            label: 'Save Draft',
                            onPressed: () {
                              showSuccessToast(context, 'Draft saved.');
                            },
                            icon: const Icon(Icons.save, size: 16, color: DefensysTokens.textDark),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TactileButton.primary(
                            label: 'Post Grades',
                            onPressed: canPost ? () => _confirmPost(team) : null,
                            icon: const Icon(Icons.lock, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (team.isCapstone) ...[
            const SizedBox(height: 14),
            team.isChair
                ? _buildChairVerdictCard(team)
                : _buildPanelistVerdictCard(team),
          ],
        ],
      ),
    );

    if (widget.onRefresh == null) return scrollContent;
    return RefreshIndicator(
      color: DefensysTokens.maroon,
      onRefresh: widget.onRefresh!,
      child: scrollContent,
    );
  }

  Future<void> _confirmPost(TeamData team) async {
    if (!team.hasValidScope) {
      showValidationToast(
        context,
        'Schedule scope is missing. Ask an admin to repair this schedule before grading.',
      );
      return;
    }
    if (team.panelRubric == null) {
      showValidationToast(
        context,
        'Panel rubric is not configured for this schedule.',
      );
      return;
    }

    final isBoth = team.targetType == 'both';
    if (isBoth) {
      if (team.memberDetails.isEmpty) {
        showValidationToast(context, 'This team has no members to grade.');
        return;
      }
      if (_criteria.isEmpty && _studentCriteria.isEmpty) {
        showValidationToast(context, 'Score all criteria before posting.');
        return;
      }
      for (var member in team.memberDetails) {
        final memberCriteria = _studentCriteria[member.id] ?? [];
        if (memberCriteria.isEmpty && _criteria.isEmpty) {
          showValidationToast(
            context,
            'Score all criteria for ${member.name} before posting.',
          );
          return;
        }
      }
    } else if (team.isIndividualTarget) {
      if (team.memberDetails.isEmpty) {
        showValidationToast(context, 'This team has no members to grade.');
        return;
      }
      for (var member in team.memberDetails) {
        final memberCriteria = _studentCriteria[member.id] ?? [];
        if (memberCriteria.isEmpty) {
          showValidationToast(
            context,
            'Score all criteria for ${member.name} before posting.',
          );
          return;
        }
      }
    } else {
      final criteria = _criteria.isNotEmpty ? _criteria : team.criteria;
      if (criteria.isEmpty) {
        showValidationToast(context, 'Score all criteria before posting.');
        return;
      }
    }

    final confirmed = await confirmLock(
      context,
      title: 'Submit Panel Grades?',
      message:
          'Once submitted, grades will be permanently saved and locked for this defense session.',
      confirmLabel: 'Submit Grades',
      icon: Icons.save_rounded,
      confirmColor: DefensysTokens.saveActionBg,
    );
    if (!confirmed || !mounted) return;

    await _submitGrades(team);
  }

  Future<void> _submitGrades(TeamData team) async {
    if (!team.hasValidScope) {
      showValidationToast(
        context,
        'Schedule scope is missing. Ask an admin to repair this schedule before grading.',
      );
      return;
    }

    showInfoToast(
      context,
      'Submitting grades...',
      duration: const Duration(seconds: 30),
    );

    final isIndividual = team.isIndividualTarget;
    final isBoth = team.targetType == 'both';
    final Map<String, dynamic> payload;

    if (isBoth) {
      final submissions = <Map<String, dynamic>>[];
      
      // 1. Team-wide submission
      final teamScores = _criteria
          .map((c) => {'criterion_id': c.id, 'score': c.score})
          .toList();
      submissions.add({
        'student_id': null,
        'criteria_scores': teamScores,
        'remarks': _teamRemarksController.text,
      });

      // 2. Individual student submissions
      for (var member in team.memberDetails) {
        final memberCriteria = _studentCriteria[member.id] ?? [];
        final criteriaScores = memberCriteria
            .map((c) => {'criterion_id': c.id, 'score': c.score})
            .toList();
        final remarks = _studentRemarksControllers[member.id]?.text ?? '';
        submissions.add({
          'student_id': int.tryParse(member.id) ?? member.id,
          'criteria_scores': criteriaScores,
          'remarks': remarks,
        });
      }

      payload = <String, dynamic>{
        'team_id': int.tryParse(team.teamId) ?? team.teamId,
        'submissions': submissions,
      };
    } else if (isIndividual) {
      final submissions = <Map<String, dynamic>>[];
      for (var member in team.memberDetails) {
        final memberCriteria = _studentCriteria[member.id] ?? [];
        final criteriaScores = memberCriteria
            .map((c) => {'criterion_id': c.id, 'score': c.score})
            .toList();
        final remarks = _studentRemarksControllers[member.id]?.text ?? '';
        submissions.add({
          'student_id': int.tryParse(member.id) ?? member.id,
          'criteria_scores': criteriaScores,
          'remarks': remarks,
        });
      }
      payload = <String, dynamic>{
        'team_id': int.tryParse(team.teamId) ?? team.teamId,
        'submissions': submissions,
      };
    } else {
      final criteria = _criteria.isNotEmpty ? _criteria : team.criteria;
      final criteriaScores = criteria
          .map((c) => {'criterion_id': c.id, 'score': c.score})
          .toList();
      payload = <String, dynamic>{
        'team_id': int.tryParse(team.teamId) ?? team.teamId,
        'criteria_scores': criteriaScores,
        'remarks': _teamRemarksController.text,
      };
    }

    if (team.scheduleId.isNotEmpty) {
      payload['schedule_id'] = int.tryParse(team.scheduleId) ?? team.scheduleId;
    }

    try {
      final isGuest = ref.read(authProvider).user?['role'] == 'guest_panelist';
      final httpClient = ref.read(authenticatedHttpClientProvider);
      final submitPath = isGuest ? 'guest-submit-grades/' : 'submit-grades/';
      final submitUrl = Uri.parse(
        '${ApiConfig.defenseSchedulesUrl}/$submitPath',
      );
      final response = await httpClient.post(
        submitUrl,
        body: json.encode(payload),
      );

      if (!mounted) return;
      dismissFeedbackToasts();

      if (response.statusCode == 201) {
        setState(() => team.isPosted = true);
        widget.onGradesSubmitted?.call();
        showSuccessToast(context, 'Grades saved to database successfully!');
      } else {
        showErrorToast(
          context,
          friendlyHttpErrorMessage(response.statusCode, response.body),
        );
      }
    } on SessionExpiredException {
      if (mounted) {
        dismissFeedbackToasts();
      }
    } catch (e) {
      if (mounted) {
        dismissFeedbackToasts();
        showErrorToast(context, 'Error: $e');
      }
    }
  }

  Widget _criterionRow(Criterion c, bool locked) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                c.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${c.score.toStringAsFixed(0)} / ${c.maxScore.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 13,
                  color: locked ? Colors.grey : DefensysTokens.maroon,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: locked ? Colors.grey : DefensysTokens.maroon,
              thumbColor: locked ? Colors.grey : DefensysTokens.maroon,
              disabledActiveTrackColor: Colors.grey,
              disabledThumbColor: Colors.grey.shade400,
            ),
            child: Slider(
              value: c.score,
              min: 0,
              max: c.maxScore,
              divisions: c.maxScore.toInt(),
              onChanged: locked ? null : (v) => setState(() => c.score = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String label) {
    final isPosted = label == 'Posted';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isPosted
            ? Colors.red.withValues(alpha: 0.1)
            : Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isPosted ? Colors.red : Colors.blue),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPosted ? Icons.lock : Icons.edit,
            size: 12,
            color: isPosted ? Colors.red : Colors.blue,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isPosted ? Colors.red : Colors.blue,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _weightChip(String label, String weight, Color color) {
    return Column(
      children: [
        Text(
          weight,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 15,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }


  Future<void> _viewDefenseMaterial(Map<String, dynamic> item) async {
    final fileUrl = item['file_url']?.toString();
    final fileName = item['file_name']?.toString() ?? 'Document';
    if (fileUrl == null || fileUrl.isEmpty) {
      showErrorToast(context, 'No file URL available for this material');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: DefensysTokens.maroon),
      ),
    );

    try {
      if (kIsWeb) {
        final bytes = await ref
            .read(authenticatedHttpClientProvider)
            .fetchAuthenticatedFile(fileUrl);
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
        if (!mounted) return;
        await viewFileInDialog(
          context: context,
          fileBytes: bytes,
          fileName: fileName,
        );
      } else {
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
        final resolvedUrl = ApiConfig.authenticatedMediaUrl(fileUrl);
        final uri = Uri.parse(resolvedUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) showErrorToast(context, 'Cannot open file: $resolvedUrl');
        }
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (mounted) {
        try {
          final uri = Uri.parse(ApiConfig.authenticatedMediaUrl(fileUrl));
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
          if (mounted) {
            showErrorToast(context, 'Error opening file: $e');
          }
        }
      }
    }
  }

  Widget _buildDefenseMaterialsCard(TeamData team) {
    final materials = team.defenseMaterials;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  size: 16,
                  color: DefensysTokens.maroon,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Defense Materials for Evaluation',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      'Pre-defense manuscripts & pitch decks submitted for panel review',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: materials.isEmpty
                      ? Colors.grey.shade100
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: materials.isEmpty
                        ? Colors.grey.shade300
                        : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Text(
                  materials.isEmpty
                      ? 'None uploaded'
                      : '${materials.length} ${materials.length == 1 ? 'file' : 'files'}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: materials.isEmpty
                        ? Colors.grey.shade600
                        : const Color(0xFF1D4ED8),
                  ),
                ),
              ),
            ],
          ),
          if (materials.isEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No defense manuscripts or pitch decks uploaded yet by this team.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            ...materials.map((mat) {
              final docName = mat['name']?.toString() ?? 'Defense Material';
              final fileName = mat['file_name']?.toString() ?? 'File';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.picture_as_pdf,
                      color: Color(0xFFDC2626),
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            docName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            fileName,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _viewDefenseMaterial(mat),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DefensysTokens.maroon,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 14),
                      label: const Text(
                        'View',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildStageSelector(TeamData currentTeam, Set<String> stageKeys) {
    if (stageKeys.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DefensysTokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: (currentTeam.isCapstone ? DefensysTokens.maroon : const Color(0xFF006666))
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.tune_rounded,
              size: 14,
              color: currentTeam.isCapstone ? DefensysTokens.maroon : const Color(0xFF006666),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Stage / Event:',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedStageKey,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: DefensysTokens.textDark,
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: 'all',
                    child: Text(
                      'All Sessions (${widget.teams.length})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ...stageKeys.map((k) {
                    final count = widget.teams.where((t) => _teamStageEventKey(t) == k).length;
                    return DropdownMenuItem<String>(
                      value: k,
                      child: Text(
                        '$k ($count)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                ],
                onChanged: (newKey) {
                  if (newKey == null) return;
                  setState(() {
                    _selectedStageKey = newKey;
                    if (newKey != 'all') {
                      final matchingIdx = widget.teams.indexWhere((t) => _teamStageEventKey(t) == newKey);
                      if (matchingIdx != -1 && matchingIdx != widget.selectedTeamIndex) {
                        _lastTeamIndex = -1;
                        widget.onTeamChanged(matchingIdx);
                        _syncRubricForCurrentTeam();
                      }
                    }
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineupStepper(TeamData team, List<int> filteredIndices, int currentFilteredPos) {
    final canPrev = currentFilteredPos > 0;
    final canNext = currentFilteredPos < filteredIndices.length - 1;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DefensysTokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous Defense Team',
              onPressed: canPrev
                  ? () {
                      _lastTeamIndex = -1;
                      widget.onTeamChanged(filteredIndices[currentFilteredPos - 1]);
                      _syncRubricForCurrentTeam();
                    }
                  : null,
            ),
            Expanded(
              child: InkWell(
                onTap: _showLineupSheet,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              team.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: DefensysTokens.textDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(${currentFilteredPos + 1}/${filteredIndices.length})',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.unfold_more, size: 14, color: Colors.grey.shade600),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: (team.isCapstone ? DefensysTokens.maroon : const Color(0xFF006666))
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              team.displayStage,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: team.isCapstone ? DefensysTokens.maroon : const Color(0xFF006666),
                              ),
                            ),
                          ),
                          Text(
                            '• ${team.formattedTime}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          if (team.displayRoom.isNotEmpty && team.displayRoom != 'Room TBD')
                            Text(
                              '• ${team.displayRoom}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next Defense Team',
              onPressed: canNext
                  ? () {
                      _lastTeamIndex = -1;
                      widget.onTeamChanged(filteredIndices[currentFilteredPos + 1]);
                      _syncRubricForCurrentTeam();
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  void _showLineupSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final stageKeys = <String>{};
            for (final t in widget.teams) {
              stageKeys.add(_teamStageEventKey(t));
            }

            final List<int> sheetFilteredIndices;
            if (_selectedStageKey == 'all' || !stageKeys.contains(_selectedStageKey)) {
              sheetFilteredIndices = List.generate(widget.teams.length, (i) => i);
            } else {
              sheetFilteredIndices = [];
              for (int i = 0; i < widget.teams.length; i++) {
                if (_teamStageEventKey(widget.teams[i]) == _selectedStageKey) {
                  sheetFilteredIndices.add(i);
                }
              }
            }

            return Container(
              color: Colors.white,
              child: SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.8,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Defense Schedule Lineup',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: DefensysTokens.textDark,
                              ),
                            ),
                            Text(
                              '${sheetFilteredIndices.length} ${sheetFilteredIndices.length == 1 ? 'Team' : 'Teams'}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Select a team to load their evaluation rubric and scores:',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        if (stageKeys.length > 1) ...[
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                FilterChip(
                                  label: Text('All (${widget.teams.length})'),
                                  selected: _selectedStageKey == 'all',
                                  onSelected: (_) {
                                    setState(() => _selectedStageKey = 'all');
                                    setModalState(() {});
                                  },
                                  selectedColor: DefensysTokens.maroon.withValues(alpha: 0.15),
                                  backgroundColor: Colors.grey.shade100,
                                  labelStyle: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: _selectedStageKey == 'all' ? FontWeight.bold : FontWeight.normal,
                                    color: _selectedStageKey == 'all' ? DefensysTokens.maroon : Colors.grey.shade800,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ...stageKeys.map((k) {
                                  final count = widget.teams.where((t) => _teamStageEventKey(t) == k).length;
                                  final isSel = _selectedStageKey == k;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: FilterChip(
                                      label: Text('$k ($count)'),
                                      selected: isSel,
                                      onSelected: (_) {
                                        setState(() => _selectedStageKey = k);
                                        setModalState(() {});
                                      },
                                      selectedColor: DefensysTokens.maroon.withValues(alpha: 0.15),
                                      backgroundColor: Colors.grey.shade100,
                                      labelStyle: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                        color: isSel ? DefensysTokens.maroon : Colors.grey.shade800,
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: sheetFilteredIndices.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final globalIndex = sheetFilteredIndices[idx];
                              final t = widget.teams[globalIndex];
                              final isSelected = globalIndex == widget.selectedTeamIndex;
                              final accentColor = t.isCapstone ? DefensysTokens.maroon : const Color(0xFF006666);

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                selected: isSelected,
                                selectedTileColor: accentColor.withValues(alpha: 0.06),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: isSelected ? accentColor : Colors.grey.shade200,
                                  foregroundColor: isSelected ? Colors.white : Colors.grey.shade800,
                                  child: Text(
                                    '${idx + 1}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        t.name,
                                        style: TextStyle(
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                          fontSize: 14,
                                          color: isSelected ? accentColor : DefensysTokens.textDark,
                                        ),
                                      ),
                                    ),
                                    if (t.isChair) ...[
                                      const SizedBox(width: 4),
                                      _chairBadge(),
                                    ],
                                    const SizedBox(width: 6),
                                    _statusBadge(t.isPosted ? 'Posted' : 'Draft'),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Row(
                                    children: [
                                      Text(
                                        t.displayStage,
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                      ),
                                      Text(
                                        ' • ${t.formattedTime}',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                      ),
                                      if (t.displayRoom.isNotEmpty && t.displayRoom != 'Room TBD')
                                        Text(
                                          ' • ${t.displayRoom}',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                        ),
                                    ],
                                  ),
                                ),
                                trailing: isSelected
                                    ? Icon(Icons.check_circle, size: 18, color: accentColor)
                                    : const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  if (globalIndex != widget.selectedTeamIndex) {
                                    _lastTeamIndex = -1;
                                    widget.onTeamChanged(globalIndex);
                                    _syncRubricForCurrentTeam();
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTeamDossier(TeamData team, bool isLocked, bool hasValidScope) {
    final isCapstone = team.isCapstone;
    final accentColor = isCapstone ? DefensysTokens.maroon : const Color(0xFF006666);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: DefensysTokens.border, width: 1),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Presiding Chair Banner
            if (team.isChair) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.gavel_rounded, size: 16, color: Color(0xFF92400E)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You are presiding as the Panel Chair for this defense hearing.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Team Name, Project & Status
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        team.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: DefensysTokens.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        team.project.isEmpty ? 'No project title specified' : team.project,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _statusBadge(isLocked ? 'Posted' : 'Draft'),
              ],
            ),

            const SizedBox(height: 10),

            // Badges wrap (Program, Stage, Attempt)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    team.scopeLabel.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    team.displayStage,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    'Attempt #${team.attemptCount}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Schedule & Venue Container
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: accentColor),
                      const SizedBox(width: 6),
                      Text(
                        team.formattedTime,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.room_outlined, size: 14, color: accentColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          team.displayRoom,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(team.isCapstone ? Icons.person_outline : Icons.badge_outlined, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            '${team.displaySupervisorLabel}: ${team.displaySupervisor}',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                      if (team.section.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.school_outlined, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              'Section: ${team.section}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Presenting Members Roster
            Row(
              children: [
                Icon(Icons.groups_outlined, size: 14, color: Colors.grey.shade700),
                const SizedBox(width: 6),
                Text(
                  'Presenting Members (${team.members.length}):',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade800),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: team.memberDetails.map((m) {
                final isLeader = m.isLeader || m.name == team.displayLeader;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isLeader ? const Color(0xFFFEF3C7) : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isLeader ? const Color(0xFFF59E0B) : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLeader) ...[
                        const Icon(Icons.star, size: 11, color: Color(0xFF92400E)),
                        const SizedBox(width: 3),
                      ] else ...[
                        Icon(Icons.person, size: 11, color: Colors.grey.shade600),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        isLeader ? '${m.name} (Leader)' : m.name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isLeader ? FontWeight.bold : FontWeight.w500,
                          color: isLeader ? const Color(0xFF92400E) : Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),

            // Lock Banner (if posted)
            if (isLocked) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock, size: 16, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Grades are permanently locked. Contact admin for corrections.',
                        style: TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (!hasValidScope) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This assignment is missing its schedule scope. Ask an admin to repair the schedule before grading.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScoreHero({
    required double total,
    required double maxTotal,
    required double panelPct,
    required int panelWeight,
    required int peerWeight,
    required bool showAdviser,
    required TeamData team,
    required bool hasValidScope,
  }) {
    final weightedPts = (panelPct * panelWeight / 100);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DefensysTokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
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
                    Text(
                      'PANEL RAW SCORE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${total.toStringAsFixed(1)} / ${maxTotal.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: DefensysTokens.maroon,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: DefensysTokens.maroon.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '${panelPct.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: DefensysTokens.maroon,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (hasValidScope) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'WEIGHTED SCORE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${weightedPts.toStringAsFixed(1)} / $panelWeight pts',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: DefensysTokens.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Weights:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
              ),
              const SizedBox(width: 8),
              _weightChip('Panel', '$panelWeight%', DefensysTokens.maroon),
              const SizedBox(width: 6),
              _weightChip('Peer', '$peerWeight%', const Color(0xFF10B981)),
              if (showAdviser) ...[
                const SizedBox(width: 6),
                _weightChip('Adviser', '${team.adviserWeight}%', DefensysTokens.gold),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _chairBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gavel_rounded, size: 10, color: Color(0xFF92400E)),
          SizedBox(width: 2.5),
          Text(
            'CHAIR',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Color(0xFF92400E),
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentSelector(TeamData team) {
    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: team.memberDetails.length,
        itemBuilder: (context, index) {
          final member = team.memberDetails[index];
          final isSelected = index == _selectedStudentIndex;
          final isLeader = member.isLeader || member.name == team.displayLeader;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: isLeader
                  ? Icon(Icons.star, size: 13, color: isSelected ? Colors.white : const Color(0xFF92400E))
                  : null,
              label: Text(isLeader ? '${member.name} (Leader)' : member.name),
              selected: isSelected,
              selectedColor: DefensysTokens.maroon,
              backgroundColor: isLeader ? const Color(0xFFFEF3C7) : Colors.grey.shade100,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : (isLeader ? const Color(0xFF92400E) : Colors.black87),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
              side: BorderSide(
                color: isSelected ? DefensysTokens.maroon : (isLeader ? const Color(0xFFF59E0B) : Colors.grey.shade300),
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedStudentIndex = index;
                  });
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildChairVerdictCard(TeamData team) {
    final hasVerdict = team.hasVerdict;
    final isForRedefense = _selectedVerdict == 'for_redefense';
    final isRevisions = _selectedVerdict == 'approved_with_revisions';

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: hasVerdict
              ? (team.isForRedefense
                  ? Colors.red.shade300
                  : team.isApprovedWithRevisions
                      ? Colors.amber.shade300
                      : Colors.green.shade300)
              : DefensysTokens.gold.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.gavel_rounded,
                    size: 20,
                    color: Color(0xFF92400E),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Panel Chair Official Verdict',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: DefensysTokens.maroon,
                        ),
                      ),
                      Text(
                        'Issue the official stage decision for ${team.name}.',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (hasVerdict) _verdictStatusChip(team.verdict!),
              ],
            ),

            if (team.isForRedefense) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Team marked for Re-defense (Attempt #${team.attemptCount}). The team is now eligible for Attempt #${team.attemptCount + 1} re-scheduling in the Defense Scheduler.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const Divider(height: 24),
            const Text(
              'OFFICIAL STAGE VERDICT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 8),

            // Radio Options
            _verdictRadioOption(
              value: 'approved',
              title: 'Approved',
              description: 'The team successfully passed with no mandatory re-defense.',
              icon: Icons.check_circle,
              color: const Color(0xFF10B981),
            ),
            const SizedBox(height: 8),
            _verdictRadioOption(
              value: 'approved_with_revisions',
              title: 'Approved with Revisions',
              description: 'Passed, but required manuscript or system changes must be submitted.',
              icon: Icons.edit_calendar,
              color: const Color(0xFFD97706),
            ),
            const SizedBox(height: 8),
            _verdictRadioOption(
              value: 'for_redefense',
              title: 'For Re-defense',
              description: 'Concept rejected, prototype unsatisfactory, or major deficiencies requiring re-presentation.',
              icon: Icons.replay_rounded,
              color: const Color(0xFFEF4444),
            ),

            if (isRevisions) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event, size: 18, color: Color(0xFF92400E)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Revision Deadline (Optional)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF92400E),
                            ),
                          ),
                          Text(
                            _revisionDeadline != null
                                ? DateFormat('MMMM d, yyyy').format(_revisionDeadline!)
                                : 'No deadline set',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _revisionDeadline ?? DateTime.now().add(const Duration(days: 14)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() => _revisionDeadline = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_today, size: 14),
                      label: Text(_revisionDeadline != null ? 'Change' : 'Set Date'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),
            const Text(
              'PANEL INSTRUCTIONS & DIRECTIVES FOR TEAM',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _verdictRemarksController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: isForRedefense
                    ? 'Enter reasons for re-defense and specific instructions for Attempt #${team.attemptCount + 1}...'
                    : 'Enter panel directives, recommendations, or required manuscript updates...',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TactileButton.primary(
                label: _isSubmittingVerdict
                    ? 'Submitting Verdict...'
                    : (hasVerdict ? 'Update Official Verdict' : 'Submit Official Verdict'),
                onPressed: _isSubmittingVerdict ? null : () => _confirmSubmitVerdict(team),
                icon: const Icon(Icons.gavel_rounded, size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _verdictRadioOption({
    required String value,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedVerdict == value;
    return InkWell(
      onTap: () => setState(() => _selectedVerdict = value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: _selectedVerdict,
              activeColor: color,
              onChanged: (val) {
                if (val != null) setState(() => _selectedVerdict = val);
              },
            ),
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? color : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
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

  Widget _buildPanelistVerdictCard(TeamData team) {
    if (!team.hasVerdict) {
      return Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 1,
        color: Colors.grey.shade50,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: Colors.grey.shade600),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'The official defense stage verdict will be rendered by the Panel Chair.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: team.isForRedefense
              ? Colors.red.shade300
              : team.isApprovedWithRevisions
                  ? Colors.amber.shade300
                  : Colors.green.shade300,
          width: 1.5,
        ),
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.gavel_rounded, size: 18, color: DefensysTokens.maroon),
                    const SizedBox(width: 8),
                    const Text(
                      'Official Stage Verdict',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: DefensysTokens.maroon,
                      ),
                    ),
                  ],
                ),
                _verdictStatusChip(team.verdict!),
              ],
            ),
            if (team.verdictByName != null && team.verdictByName!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Issued by Panel Chair: ${team.verdictByName}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
            if (team.verdictRemarks != null && team.verdictRemarks!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Panel Directives / Instructions:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      team.verdictRemarks!,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF1F2937)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _verdictStatusChip(String verdict) {
    final isApproved = verdict == 'approved';
    final isRevisions = verdict == 'approved_with_revisions';
    final isForRedefense = verdict == 'for_redefense';

    final Color color = isApproved
        ? const Color(0xFF10B981)
        : isRevisions
            ? const Color(0xFFD97706)
            : isForRedefense
                ? const Color(0xFFEF4444)
                : Colors.grey;

    final String label = isApproved
        ? 'APPROVED'
        : isRevisions
            ? 'APPROVED W/ REVISIONS'
            : isForRedefense
                ? 'FOR RE-DEFENSE'
                : verdict.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Future<void> _confirmSubmitVerdict(TeamData team) async {
    final directives = _verdictRemarksController.text.trim();
    if (_selectedVerdict == 'for_redefense' && directives.isEmpty) {
      showValidationToast(
        context,
        'Please enter the reasons / directives for Re-defense so the team knows what to address.',
      );
      return;
    }

    if (_selectedVerdict == 'for_redefense') {
      final confirmed = await confirmDestructive(
        context,
        title: 'Issue Re-defense Verdict?',
        message:
            'Marking this team for Re-defense will record Attempt #${team.attemptCount} into history and open the team for Attempt #${team.attemptCount + 1} re-scheduling in the Defense Scheduler.\n\nAre you sure you want to proceed?',
        confirmLabel: 'Issue Re-defense',
      );
      if (!confirmed || !mounted) return;
    }

    await _submitVerdict(team);
  }

  Future<void> _submitVerdict(TeamData team) async {
    if (team.scheduleId.isEmpty) {
      showValidationToast(context, 'Schedule ID is missing for this team.');
      return;
    }

    final directives = _verdictRemarksController.text.trim();
    setState(() => _isSubmittingVerdict = true);
    showInfoToast(context, 'Submitting official defense verdict...');

    try {
      final httpClient = ref.read(authenticatedHttpClientProvider);
      final verdictUrl = Uri.parse(
        '${ApiConfig.defenseSchedulesUrl}/${team.scheduleId}/verdict/',
      );

      final payload = <String, dynamic>{
        'verdict': _selectedVerdict,
        'verdict_remarks': directives,
        if (_revisionDeadline != null && _selectedVerdict == 'approved_with_revisions')
          'revision_deadline': DateFormat('yyyy-MM-dd').format(_revisionDeadline!),
      };

      final response = await httpClient.patch(
        verdictUrl,
        body: json.encode(payload),
      );

      if (!mounted) return;
      dismissFeedbackToasts();
      setState(() => _isSubmittingVerdict = false);

      if (response.statusCode == 200) {
        setState(() {
          team.verdict = _selectedVerdict;
          team.verdictRemarks = directives;
          if (_revisionDeadline != null && _selectedVerdict == 'approved_with_revisions') {
            team.revisionDeadline = DateFormat('yyyy-MM-dd').format(_revisionDeadline!);
          }
        });

        widget.onGradesSubmitted?.call();

        if (_selectedVerdict == 'for_redefense') {
          showSuccessToast(
            context,
            'Team marked for Re-defense. Eligible for Attempt #2 in Defense Scheduler.',
          );
        } else if (_selectedVerdict == 'approved_with_revisions') {
          showSuccessToast(context, 'Verdict recorded: Approved with Revisions.');
        } else {
          showSuccessToast(context, 'Verdict recorded: Approved.');
        }
      } else {
        showErrorToast(
          context,
          friendlyHttpErrorMessage(response.statusCode, response.body),
        );
      }
    } on SessionExpiredException {
      if (mounted) setState(() => _isSubmittingVerdict = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmittingVerdict = false);
        dismissFeedbackToasts();
        showErrorToast(context, 'Error submitting verdict: $e');
      }
    }
  }
}
