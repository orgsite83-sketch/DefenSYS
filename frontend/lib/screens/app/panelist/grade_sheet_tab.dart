import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'panelist_models.dart';
import '../../../config/api_config.dart';

const _primaryColor = Color(0xFF7F1D1D);
const _goldColor = Color(0xFFD97706);

class GradeSheetTab extends StatefulWidget {
  final List<TeamData> teams;
  final int selectedTeamIndex;
  final String panelistId;
  final void Function(int) onTeamChanged;

  const GradeSheetTab({
    super.key,
    required this.teams,
    required this.selectedTeamIndex,
    required this.panelistId,
    required this.onTeamChanged,
  });

  @override
  State<GradeSheetTab> createState() => _GradeSheetTabState();
}

class _GradeSheetTabState extends State<GradeSheetTab> {
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
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No teams available', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final team = widget.teams[widget.selectedTeamIndex];
    final panelRubricName = _panelRubricName(team);
    final hasPanelRubric = team.panelRubric != null;
    final isLocked = team.isPosted;
    final canPost = hasPanelRubric && _criteria.isNotEmpty && !isLocked;

    final criteria = _criteria.isNotEmpty ? _criteria : team.criteria;
    final total = criteria.fold(0.0, (s, c) => s + c.score);
    final maxTotal = criteria.fold(0.0, (s, c) => s + c.maxScore);
    final panelPct = maxTotal > 0 ? (total / maxTotal * 100) : 0;

    final panelWeight = team.panelWeight;
    final peerWeight = team.peerWeight;
    final showAdviser = team.isCapstone && team.adviserWeight > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Panel Grade Sheet'),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: widget.selectedTeamIndex,
            decoration: InputDecoration(
              labelText: 'Select Team',
              prefixIcon: const Icon(Icons.group, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: widget.teams
                .asMap()
                .entries
                .map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value.name)))
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
                const Icon(Icons.assignment_outlined,
                    size: 18, color: _primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Panel rubric: $panelRubricName',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                            Text(team.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
                            Text(team.project,
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                            Text(
                              team.isCapstone ? 'Capstone' : 'PIT',
                              style: const TextStyle(
                                color: _primaryColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
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
                  const Divider(height: 24),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _primaryColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _weightChip('Panel', '$panelWeight%', _primaryColor),
                        if (showAdviser)
                          _weightChip('Adviser', '${team.adviserWeight}%', _goldColor),
                        _weightChip('Peer', '$peerWeight%', const Color(0xFF10B981)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Rubric Criteria',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                    ...criteria.map((c) => _criterionRow(c, isLocked)),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Panel Raw Score',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(
                        '${total.toStringAsFixed(1)} / ${maxTotal.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _primaryColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Score (normalized)',
                          style: TextStyle(fontSize: 13, color: Colors.grey)),
                      Text(
                        '${panelPct.toStringAsFixed(1)}%  ×  $panelWeight%  =  ${(panelPct * panelWeight / 100).toStringAsFixed(1)} pts',
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!isLocked) ...[
                    TextField(
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Remarks / Feedback',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
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
                              side: const BorderSide(color: _primaryColor),
                              foregroundColor: _primaryColor,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Draft saved.')),
                              );
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
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: canPost ? () => _confirmPost(team) : null,
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
  }

  void _confirmPost(TeamData team) {
    if (team.panelRubric == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Panel rubric is not configured for this schedule.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_criteria.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Score all criteria before posting.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red),
            SizedBox(width: 8),
            Text('Post Grades?', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const Text(
            'Once posted, grades are permanently saved to the database.\n\nAre you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 16),
                      Text('Submitting grades...'),
                    ],
                  ),
                  duration: Duration(seconds: 30),
                ),
              );

              final criteriaScores = _criteria.map((c) => {
                'name': c.name,
                'score': c.score,
                'max_score': c.maxScore,
              }).toList();

              final payload = <String, dynamic>{
                'panelist_id': widget.panelistId,
                'team_id': team.teamId,
                'criteria_scores': criteriaScores,
                'remarks': '',
              };
              if (team.scheduleId.isNotEmpty) {
                payload['schedule_id'] = int.tryParse(team.scheduleId) ?? team.scheduleId;
              }

              try {
                final submitUrl = '${ApiConfig.defenseSchedulesUrl}/submit-grades/';
                final response = await http.post(
                  Uri.parse(submitUrl),
                  headers: {
                    'Content-Type': 'application/json',
                  },
                  body: json.encode(payload),
                ).timeout(const Duration(seconds: 10));

                if (context.mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();

                  if (response.statusCode == 201) {
                    setState(() => team.isPosted = true);

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.white),
                            SizedBox(width: 8),
                            Text('Grades saved to database successfully!'),
                          ],
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to submit grades: ${response.body}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Submit to Database'),
          ),
        ],
      ),
    );
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
              Text(c.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              Text(
                '${c.score.toStringAsFixed(0)} / ${c.maxScore.toStringAsFixed(0)}',
                style: TextStyle(
                    fontSize: 13,
                    color: locked ? Colors.grey : _primaryColor,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: locked ? Colors.grey : _primaryColor,
              thumbColor: locked ? Colors.grey : _primaryColor,
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
        color: isPosted ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isPosted ? Colors.red : Colors.blue),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isPosted ? Icons.lock : Icons.edit,
              size: 12, color: isPosted ? Colors.red : Colors.blue),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: isPosted ? Colors.red : Colors.blue,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _weightChip(String label, String weight, Color color) {
    return Column(
      children: [
        Text(weight,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: color, fontSize: 15)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
                color: _primaryColor, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: _primaryColor)),
      ],
    );
  }
}
