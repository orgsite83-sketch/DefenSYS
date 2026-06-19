import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'panelist_models.dart';
import '../../../config/api_config.dart';
import '../../../services/auth_provider.dart';
import '../../../services/authenticated_client.dart';
import '../../../services/authz_errors.dart';
import '../../../services/session_expired.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/feedback_toast.dart';

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

  @override
  void initState() {
    super.initState();
    _syncRubricForCurrentTeam();
  }

  @override
  void didUpdateWidget(GradeSheetTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTeamIndex != widget.selectedTeamIndex ||
        oldWidget.teams != widget.teams) {
      _syncRubricForCurrentTeam();
    }
  }

  void _loadCriteriaFromRubricMap(Map<String, dynamic> rubric) {
    final criteriaList = (rubric['criteria'] as List? ?? []).map((c) {
      return Criterion(
        (c['name'] ?? 'Criterion').toString(),
        ((c['max_score'] as num?) ?? 10).toDouble(),
        id: int.tryParse(c['id']?.toString() ?? ''),
      );
    }).toList();

    setState(() {
      _criteria = criteriaList;
    });
  }

  void _syncRubricForCurrentTeam() {
    if (widget.teams.isEmpty) {
      return;
    }
    if (_lastTeamIndex == widget.selectedTeamIndex && _criteria.isNotEmpty) {
      return;
    }
    _lastTeamIndex = widget.selectedTeamIndex;

    final team = widget.teams[widget.selectedTeamIndex];
    final embedded = team.panelRubric;
    if (embedded != null) {
      _loadCriteriaFromRubricMap(embedded);
    } else {
      setState(() {
        _criteria = [];
      });
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
    final canPost =
        hasValidScope && hasPanelRubric && _criteria.isNotEmpty && !isLocked && !team.isLockedByDate;

    final criteria = _criteria.isNotEmpty ? _criteria : team.criteria;
    final total = criteria.fold(0.0, (s, c) => s + c.score);
    final maxTotal = criteria.fold(0.0, (s, c) => s + c.maxScore);
    final panelPct = maxTotal > 0 ? (total / maxTotal * 100) : 0;

    final panelWeight = team.panelWeight;
    final peerWeight = team.peerWeight;
    final showAdviser = team.isCapstone && team.adviserWeight > 0;

    final scrollContent = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Panel Grade Sheet'),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: widget.selectedTeamIndex,
            decoration: InputDecoration(
              labelText: 'Select Team',
              prefixIcon: const Icon(Icons.group, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            items: widget.teams
                .asMap()
                .entries
                .map(
                  (e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value.name)),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) {
                return;
              }
              _lastTeamIndex = -1;
              widget.onTeamChanged(v);
              _syncRubricForCurrentTeam();
            },
          ),
          if (panelRubricName != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.assignment_outlined,
                  size: 18,
                  color: DefensysTokens.maroon,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Panel rubric: $panelRubricName',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DefensysTokens.maroon,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              team.project,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              team.scopeLabel,
                              style: TextStyle(
                                color: hasValidScope
                                    ? DefensysTokens.maroon
                                    : Colors.orange.shade800,
                                fontSize: 11,
                                fontWeight: hasValidScope
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _statusBadge(isLocked ? 'Posted' : 'Draft'),
                    ],
                  ),
                  if (isLocked)
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(10),
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
                  if (!hasValidScope)
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 16,
                            color: Colors.orange,
                          ),
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
                  const Divider(height: 24),
                  if (hasValidScope)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: DefensysTokens.maroon.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _weightChip(
                            'Panel',
                            '$panelWeight%',
                            DefensysTokens.maroon,
                          ),
                          if (showAdviser)
                            _weightChip(
                              'Adviser',
                              '${team.adviserWeight}%',
                              DefensysTokens.gold,
                            ),
                          _weightChip(
                            'Peer',
                            '$peerWeight%',
                            const Color(0xFF10B981),
                          ),
                        ],
                      ),
                    )
                  else
                    _scopeWeightUnavailable(),
                  const SizedBox(height: 16),
                  const Text(
                    'Rubric Criteria',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
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
                  else if (criteria.isEmpty)
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
                    ...criteria.map((c) => _criterionRow(c, isLocked || team.isLockedByDate)),
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
                        Text(
                          '${panelPct.toStringAsFixed(1)}%  ×  $panelWeight%  =  ${(panelPct * panelWeight / 100).toStringAsFixed(1)} pts',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
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
                    TextField(
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Remarks / Feedback',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.save, size: 16),
                            label: const Text('Save Draft'),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: DefensysTokens.maroon,
                              ),
                              foregroundColor: DefensysTokens.maroon,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () {
                              showSuccessToast(context, 'Draft saved.');
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.lock, size: 16),
                            label: const Text('Post Grades'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: canPost
                                ? () => _confirmPost(team)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
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
    if (_criteria.isEmpty) {
      showValidationToast(context, 'Score all criteria before posting.');
      return;
    }

    final confirmed = await confirmDestructive(
      context,
      title: 'Post Grades?',
      message:
          'Once posted, grades are permanently saved to the database.\n\nAre you sure?',
      confirmLabel: 'Submit to Database',
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

    final criteriaScores = _criteria
        .map((c) => {'criterion_id': c.id, 'score': c.score})
        .toList();

    final payload = <String, dynamic>{
      'team_id': int.tryParse(team.teamId) ?? team.teamId,
      'criteria_scores': criteriaScores,
      'remarks': '',
    };
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

  Widget _scopeWeightUnavailable() {
    return Container(
      width: double.infinity,
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
              'Grading weights cannot be shown because this schedule has no scope.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: DefensysTokens.maroon,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: DefensysTokens.maroon,
          ),
        ),
      ],
    );
  }
}
