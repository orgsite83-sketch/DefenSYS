import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/adviser_grading_provider.dart';
import '../../../../theme/app_theme.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/widgets.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _maroon = DefensysTokens.maroon;
const _bgLight = Color(0xFFF3F4F6);
const _neutralBorder = Color(0xFFE5E7EB);
const _steelGrey = Color(0xFF6B7280);
const _textDark = Color(0xFF1F2937);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class AdviserGradingScreen extends ConsumerStatefulWidget {
  const AdviserGradingScreen({super.key});

  @override
  ConsumerState<AdviserGradingScreen> createState() => _AdviserGradingScreenState();
}

class _AdviserGradingScreenState extends ConsumerState<AdviserGradingScreen> {
  int? _selectedGradeIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(adviserGradingProvider.notifier).fetchAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adviserGradingProvider);

    return Container(
      color: _bgLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header bar ────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.rate_review_rounded, color: _maroon, size: 22),
                    const SizedBox(width: 10),
                    const Text(
                      'Grade Students',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _maroon),
                    ),
                    const Spacer(),
                    _refreshButton(state),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select a team, score each criterion using the rubric assigned by your administrator, then submit.',
                  style: TextStyle(fontSize: 13, color: _steelGrey),
                ),
                const SizedBox(height: 16),
                _buildStats(state),
              ],
            ),
          ),
          if (state.error != null)
            _banner(state.error!, AppColors.danger, Icons.error_outline_rounded),
          if (state.message != null)
            _banner(state.message!, AppColors.success, Icons.check_circle_outline_rounded),
          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : !state.adviserGradingEnabled
                    ? _buildAdviserGradingDisabled()
                    : state.grades.isEmpty
                        ? _buildEmptyState()
                        : _buildBody(state),
          ),
        ],
      ),
    );
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  Widget _buildStats(AdviserGradingState state) {
    final all = (state.counts['all'] as num?)?.toInt() ?? state.grades.length;
    final graded = (state.counts['graded'] as num?)?.toInt() ?? 0;
    final pending = (state.counts['pending'] as num?)?.toInt() ?? 0;

    return Row(
      children: [
        _statChip('$all Teams', Icons.groups_rounded, _maroon),
        const SizedBox(width: 10),
        _statChip('$graded Graded', Icons.check_circle_outline_rounded, AppColors.success),
        const SizedBox(width: 10),
        _statChip('$pending Pending', Icons.hourglass_bottom_rounded, AppColors.warning),
      ],
    );
  }

  Widget _statChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ── Body: two-panel layout ─────────────────────────────────────────────

  Widget _buildBody(AdviserGradingState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left panel – team list
        Container(
          width: 300,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: _neutralBorder)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  'TEAMS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _steelGrey,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: state.grades.length,
                  itemBuilder: (_, i) => _TeamListTile(
                    grade: state.grades[i],
                    isSelected: _selectedGradeIndex == i,
                    onTap: () => setState(() => _selectedGradeIndex = i),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Right panel – grade form
        Expanded(
          child: _selectedGradeIndex == null
              ? _buildSelectPrompt()
              : _GradeForm(
                  key: ValueKey(state.grades[_selectedGradeIndex!]['id']),
                  grade: state.grades[_selectedGradeIndex!],
                  isSaving: state.isSaving,
                  onSubmit: ({
                    required int gradeId,
                    double? adviserScore,
                    int? rubricId,
                    List<Map<String, dynamic>> criteriaScores = const [],
                    List<Map<String, dynamic>> teamCriteriaScores = const [],
                    List<Map<String, dynamic>> studentSubmissions = const [],
                  }) async {
                    await ref.read(adviserGradingProvider.notifier).submitGrade(
                          gradeId: gradeId,
                          adviserScore: adviserScore,
                          rubricId: rubricId,
                          criteriaScores: criteriaScores,
                          teamCriteriaScores: teamCriteriaScores,
                          studentSubmissions: studentSubmissions,
                        );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSelectPrompt() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chevron_left_rounded, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('Select a team to grade',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildAdviserGradingDisabled() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Adviser grading is turned off',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textDark),
            ),
            const SizedBox(height: 10),
            Text(
              'An administrator has disabled adviser grading for this term. '
              'You can still review teams; submissions will open when grading is enabled again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _steelGrey, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const DefensysEmptyState(
      icon: Icons.groups_outlined,
      title: 'No Teams to Grade',
      description: 'There are no capstone teams assigned to you for grading yet.',
      size: DefensysEmptyStateSize.standard,
    );
  }

  Widget _refreshButton(AdviserGradingState state) {
    return OutlinedButton.icon(
      onPressed: state.isLoading ? null : () => ref.read(adviserGradingProvider.notifier).fetchAll(),
      icon: state.isLoading
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh_rounded, size: 16),
      label: const Text('Refresh'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _maroon,
        side: const BorderSide(color: _maroon),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }

  Widget _banner(String text, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team list tile
// ---------------------------------------------------------------------------

class _TeamListTile extends StatelessWidget {
  final Map<String, dynamic> grade;
  final bool isSelected;
  final VoidCallback onTap;

  const _TeamListTile({
    required this.grade,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isGraded = grade['adviser_score'] != null;
    final teamName = grade['team_name']?.toString() ?? 'Team';
    final stageLabel = grade['stage_label']?.toString() ?? '';

    return Material(
      color: isSelected ? const Color(0xFFFFF4F4) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: isSelected
                ? const Border(left: BorderSide(color: _maroon, width: 4))
                : const Border(bottom: BorderSide(color: _neutralBorder, width: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isGraded
                      ? AppColors.success.withValues(alpha: 0.12)
                      : _maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isGraded ? Icons.check_rounded : Icons.hourglass_empty_rounded,
                  size: 18,
                  color: isGraded ? AppColors.success : _maroon,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      teamName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? _maroon : _textDark,
                      ),
                    ),
                    if (stageLabel.isNotEmpty)
                      Text(stageLabel, style: const TextStyle(fontSize: 11, color: _steelGrey)),
                  ],
                ),
              ),
              if (isGraded)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${grade['adviser_score']}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grade form (right panel)
// ---------------------------------------------------------------------------

typedef _OnSubmit = Future<void> Function({
  required int gradeId,
  double? adviserScore,
  int? rubricId,
  List<Map<String, dynamic>> criteriaScores,
  List<Map<String, dynamic>> teamCriteriaScores,
  List<Map<String, dynamic>> studentSubmissions,
});

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

class _GradeForm extends StatefulWidget {
  final Map<String, dynamic> grade;
  final bool isSaving;
  final _OnSubmit onSubmit;

  const _GradeForm({
    super.key,
    required this.grade,
    required this.isSaving,
    required this.onSubmit,
  });

  @override
  State<_GradeForm> createState() => _GradeFormState();
}

class _GradeFormState extends State<_GradeForm> {
  Map<String, dynamic>? _selectedRubric;

  // Controllers
  final Map<String, TextEditingController> _teamScoreCtrl = {};
  final Map<dynamic, Map<String, TextEditingController>> _studentScoreCtrl = {};
  final TextEditingController _manualScoreCtrl = TextEditingController();

  int _selectedStudentIndex = 0;

  @override
  void initState() {
    super.initState();
    final existing = widget.grade['adviser_score'];
    if (existing != null) {
      _manualScoreCtrl.text = existing.toString();
    }
    final assigned = _assignedRubricFromGrade(widget.grade);
    if (assigned != null) {
      _selectRubric(assigned, hydrateFromGrade: true);
    }
  }

  @override
  void dispose() {
    for (final c in _teamScoreCtrl.values) {
      c.dispose();
    }
    for (final map in _studentScoreCtrl.values) {
      for (final c in map.values) {
        c.dispose();
      }
    }
    _manualScoreCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getMembers() {
    final raw = widget.grade['members'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final pps = widget.grade['peer_per_student'];
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

  void _selectRubric(
    Map<String, dynamic>? rubric, {
    bool hydrateFromGrade = false,
  }) {
    for (final c in _teamScoreCtrl.values) {
      c.dispose();
    }
    _teamScoreCtrl.clear();

    for (final map in _studentScoreCtrl.values) {
      for (final c in map.values) {
        c.dispose();
      }
    }
    _studentScoreCtrl.clear();

    _selectedRubric = rubric;
    if (rubric == null) {
      return;
    }

    final members = _getMembers();
    for (final m in members) {
      final sId = m['id'] ?? m['student_id'];
      _studentScoreCtrl[sId] = {};
    }

    final teamSaved = <String, String>{};
    final studentSaved = <dynamic, Map<String, String>>{};

    if (hydrateFromGrade && widget.grade['breakdowns'] is List) {
      for (final row in widget.grade['breakdowns'] as List) {
        if (row is! Map) continue;
        if (row['evaluation_type']?.toString() != 'adviser') continue;
        final name = row['criterion_name']?.toString() ?? '';
        final sId = row['student'];
        final scoreVal = row['score']?.toString() ?? '';
        if (name.isEmpty) continue;
        if (sId == null) {
          teamSaved[name] = scoreVal;
        } else {
          studentSaved.putIfAbsent(sId, () => {})[name] = scoreVal;
        }
      }
    }

    final criteria = (rubric['criteria'] as List? ?? []);
    final targetType = rubric['target_type']?.toString() ?? 'team';

    for (final c in criteria) {
      final cMap = c as Map;
      final name = cMap['name']?.toString() ?? '';
      final cTarget = cMap['target_type']?.toString() ?? 'team';

      final isTeamCrit = (targetType == 'team') || (targetType == 'both' && cTarget == 'team');
      final isIndCrit = (targetType == 'individual') || (targetType == 'both' && cTarget == 'individual');

      if (isTeamCrit) {
        _teamScoreCtrl[name] = TextEditingController(text: teamSaved[name] ?? '');
      }

      if (isIndCrit) {
        for (final m in members) {
          final sId = m['id'] ?? m['student_id'];
          final saved = studentSaved[sId]?[name] ?? '';
          _studentScoreCtrl[sId]?[name] = TextEditingController(text: saved);
        }
      }
    }
  }

  List<Map<String, dynamic>> _getTeamCriteria() {
    if (_selectedRubric == null) return [];
    final criteria = (_selectedRubric!['criteria'] as List? ?? []);
    final targetType = _selectedRubric!['target_type']?.toString() ?? 'team';
    if (targetType == 'individual') return [];
    if (targetType == 'team') {
      return criteria.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return criteria
        .where((c) => (c as Map)['target_type']?.toString() == 'team')
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  List<Map<String, dynamic>> _getIndividualCriteria() {
    if (_selectedRubric == null) return [];
    final criteria = (_selectedRubric!['criteria'] as List? ?? []);
    final targetType = _selectedRubric!['target_type']?.toString() ?? 'team';
    if (targetType == 'team') return [];
    if (targetType == 'individual') {
      return criteria.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return criteria
        .where((c) => (c as Map)['target_type']?.toString() == 'individual')
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  double _computeStudentScore(dynamic studentId) {
    if (_selectedRubric == null) return 0;
    final criteria = (_selectedRubric!['criteria'] as List? ?? []);
    final targetType = _selectedRubric!['target_type']?.toString() ?? 'team';

    double total = 0;
    double maxTotal = 0;

    for (final c in criteria) {
      final cMap = c as Map;
      final name = cMap['name']?.toString() ?? '';
      final maxScore = ((cMap['max_score'] as num?) ?? 10).toDouble();
      final cTarget = cMap['target_type']?.toString() ?? 'team';

      if (targetType == 'team' || (targetType == 'both' && cTarget == 'team')) {
        final entered = double.tryParse(_teamScoreCtrl[name]?.text ?? '') ?? 0;
        total += entered.clamp(0, maxScore);
        maxTotal += maxScore;
      } else if (targetType == 'individual' || (targetType == 'both' && cTarget == 'individual')) {
        final entered = double.tryParse(_studentScoreCtrl[studentId]?[name]?.text ?? '') ?? 0;
        total += entered.clamp(0, maxScore);
        maxTotal += maxScore;
      }
    }

    if (maxTotal == 0) return 0;
    return (total / maxTotal * 100).clamp(0, 100);
  }

  double _computeOverallTeamScore() {
    if (_selectedRubric == null) return 0;
    final targetType = _selectedRubric!['target_type']?.toString() ?? 'team';
    if (targetType == 'team') {
      return _computeStudentScore(null);
    }
    final members = _getMembers();
    if (members.isEmpty) {
      return _computeStudentScore(null);
    }
    double sum = 0;
    for (final m in members) {
      final sId = m['id'] ?? m['student_id'];
      sum += _computeStudentScore(sId);
    }
    return (sum / members.length).clamp(0, 100);
  }

  bool _isStudentComplete(dynamic studentId) {
    final indCrits = _getIndividualCriteria();
    if (indCrits.isEmpty) return true;
    final ctrlMap = _studentScoreCtrl[studentId];
    if (ctrlMap == null) return false;
    for (final c in indCrits) {
      final name = c['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final text = ctrlMap[name]?.text.trim() ?? '';
      if (text.isEmpty) return false;
      final val = double.tryParse(text);
      if (val == null || val < 0 || val > maxScore) return false;
    }
    return true;
  }

  bool _isTeamComplete() {
    final teamCrits = _getTeamCriteria();
    for (final c in teamCrits) {
      final name = c['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final text = _teamScoreCtrl[name]?.text.trim() ?? '';
      if (text.isEmpty) return false;
      final val = double.tryParse(text);
      if (val == null || val < 0 || val > maxScore) return false;
    }
    return true;
  }

  bool _allCriteriaFilled() {
    if (_selectedRubric == null) return false;
    if (!_isTeamComplete()) return false;
    final indCrits = _getIndividualCriteria();
    if (indCrits.isNotEmpty) {
      final members = _getMembers();
      if (members.isEmpty) return false;
      for (final m in members) {
        final sId = m['id'] ?? m['student_id'];
        if (!_isStudentComplete(sId)) return false;
      }
    }
    return true;
  }

  int _filledCount() {
    if (_selectedRubric == null) return 0;
    int count = 0;
    final teamCrits = _getTeamCriteria();
    for (final c in teamCrits) {
      final name = c['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final text = _teamScoreCtrl[name]?.text.trim() ?? '';
      final val = double.tryParse(text);
      if (text.isNotEmpty && val != null && val >= 0 && val <= maxScore) count++;
    }

    final indCrits = _getIndividualCriteria();
    if (indCrits.isNotEmpty) {
      final members = _getMembers();
      for (final m in members) {
        final sId = m['id'] ?? m['student_id'];
        final ctrlMap = _studentScoreCtrl[sId] ?? {};
        for (final c in indCrits) {
          final name = c['name']?.toString() ?? '';
          final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
          final text = ctrlMap[name]?.text.trim() ?? '';
          final val = double.tryParse(text);
          if (text.isNotEmpty && val != null && val >= 0 && val <= maxScore) count++;
        }
      }
    }
    return count;
  }

  int _totalCount() {
    if (_selectedRubric == null) return 0;
    final teamCrits = _getTeamCriteria();
    final indCrits = _getIndividualCriteria();
    final members = _getMembers();
    return teamCrits.length + (indCrits.length * (members.isEmpty ? 1 : members.length));
  }

  @override
  Widget build(BuildContext context) {
    final grade = widget.grade;
    final teamName = grade['team_name']?.toString() ?? 'Team';
    final projectTitle = grade['project_title']?.toString() ?? '';
    final stageLabel = grade['stage_label']?.toString() ?? '';
    final adviserWeight = (grade['weights'] as Map?)?['adviser'];
    final isAlreadyGraded = grade['adviser_score'] != null;

    final isOfficiallyComplete = grade['is_officially_complete'] == true;
    final isPublished = grade['status']?.toString() == 'published';
    final isGradingLocked = isOfficiallyComplete || isPublished;

    final targetType = _selectedRubric?['target_type']?.toString() ?? 'team';
    final teamCrits = _getTeamCriteria();
    final indCrits = _getIndividualCriteria();
    final members = _getMembers();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─ Team header ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _neutralBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _maroon.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.groups_rounded, color: _maroon, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(teamName,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800, color: _textDark)),
                      if (projectTitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(projectTitle,
                            style: const TextStyle(fontSize: 13, color: _steelGrey)),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (stageLabel.isNotEmpty) _tag(stageLabel, _maroon),
                          if (adviserWeight != null) _tag('Adviser Weight: $adviserWeight%', Colors.blueGrey),
                          if (isAlreadyGraded)
                            _tag('Previously Graded: ${grade['adviser_score']}', AppColors.success),
                          if (members.isNotEmpty)
                            _tag('${members.length} Members', Colors.indigo),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (isGradingLocked) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.only(bottom: 20),
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
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_selectedRubric == null) ...[
            _sectionLabel('Assigned adviser rubric'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No adviser rubric is assigned for this defense stage yet. '
                      'Ask your administrator to set panel, adviser, and peer rubrics in Defense Stages Setup or the scheduler.',
                      style: TextStyle(color: AppColors.warning, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // ─ Rubric details header bar ──────────────────────────────────
            _sectionLabel('Assigned adviser rubric'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _maroon.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _maroon.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_selectedRubric!['name']} (${_selectedRubric!['scale'] ?? 'Rubric'})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _textDark,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _maroon.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      targetType == 'both'
                          ? 'Both (Team & Individual)'
                          : targetType == 'individual'
                              ? 'Individual'
                              : 'Team',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _maroon,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // ─ Overall scoring progress pill ──────────────────────────────
            Row(
              children: [
                _sectionLabel('Scoring Form'),
                const Spacer(),
                Builder(builder: (_) {
                  final total = _totalCount();
                  final filled = _filledCount();
                  final allDone = filled == total && total > 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: allDone
                          ? AppColors.success.withValues(alpha: 0.1)
                          : AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$filled / $total scored',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: allDone ? AppColors.success : AppColors.warning,
                      ),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 14),

            // ─ Team Criteria Section (if present) ─────────────────────────
            if (teamCrits.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.groups_outlined, size: 18, color: _maroon),
                  const SizedBox(width: 8),
                  Text(
                    targetType == 'both' ? 'Team-Wide Criteria' : 'Criteria',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _textDark),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _isTeamComplete()
                          ? AppColors.success.withValues(alpha: 0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _isTeamComplete() ? '✓ Complete' : 'Required',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _isTeamComplete() ? AppColors.success : _steelGrey,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildCriteriaTable(teamCrits, isTeam: true, isReadOnly: isGradingLocked),
              const SizedBox(height: 24),
            ],

            // ─ Individual Student Criteria Section (if present) ────────────
            if (indCrits.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.person_outline_rounded, size: 18, color: _maroon),
                  const SizedBox(width: 8),
                  const Text(
                    'Individual Criteria (Score Each Member)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _textDark),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Student selection tabs
              if (members.isNotEmpty) ...[
                SizedBox(
                  height: 46,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: members.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, idx) {
                      final m = members[idx];
                      final sId = m['id'] ?? m['student_id'];
                      final isSelected = _selectedStudentIndex == idx;
                      final isComplete = _isStudentComplete(sId);
                      final isLeader = m['is_leader'] == true;
                      final sScore = _computeStudentScore(sId);

                      return InkWell(
                        onTap: () => setState(() => _selectedStudentIndex = idx),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? _maroon : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? _maroon : _neutralBorder,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (isLeader) ...[
                                Icon(Icons.star_rounded,
                                    size: 14, color: isSelected ? Colors.amberAccent : Colors.amber.shade700),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                m['name']?.toString() ?? 'Student',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                  color: isSelected ? Colors.white : _textDark,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? Colors.white
                                        : isComplete
                                            ? AppColors.success
                                            : _steelGrey,
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
                const SizedBox(height: 12),

                // Individual criteria form for active student
                if (_selectedStudentIndex < members.length) ...[
                  Builder(builder: (_) {
                    final activeMember = members[_selectedStudentIndex];
                    final sId = activeMember['id'] ?? activeMember['student_id'];
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _neutralBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: _maroon.withValues(alpha: 0.04),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                              border: const Border(bottom: BorderSide(color: _neutralBorder)),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'Scoring: ${activeMember['name']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 13, color: _maroon),
                                ),
                                const Spacer(),
                                Text(
                                  'Student Score: ${_computeStudentScore(sId).toStringAsFixed(2)} / 100',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 12, color: _steelGrey),
                                ),
                              ],
                            ),
                          ),
                          _buildCriteriaTable(indCrits, isTeam: false, studentId: sId, isReadOnly: isGradingLocked),
                        ],
                      ),
                    );
                  }),
                ],
              ] else ...[
                const Text('No members found in this team.', style: TextStyle(color: _steelGrey)),
              ],
              const SizedBox(height: 24),
            ],

            // ─ Summary Card ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _maroon.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _maroon.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  if (targetType != 'team' && members.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Student Scores Breakdown',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _maroon.withValues(alpha: 0.9),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...members.map((m) {
                      final sId = m['id'] ?? m['student_id'];
                      final sScore = _computeStudentScore(sId);
                      final isComplete = _isStudentComplete(sId);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Text(
                              m['name']?.toString() ?? 'Student',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textDark),
                            ),
                            const Spacer(),
                            Text(
                              isComplete ? '${sScore.toStringAsFixed(2)} / 100' : 'Incomplete',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isComplete ? _maroon : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 18, color: _neutralBorder),
                  ],
                  Row(
                    children: [
                      Text(
                        targetType != 'team' ? 'Overall Team Adviser Score (Avg):' : 'Computed Adviser Score:',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: _textDark, fontSize: 14),
                      ),
                      const Spacer(),
                      Text(
                        _computeOverallTeamScore().toStringAsFixed(2),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800, color: _maroon),
                      ),
                      const Text(' / 100',
                          style: TextStyle(color: _steelGrey, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ─ Submit button ─────────────────────────────────────────────────
            Builder(builder: (_) {
              if (isGradingLocked) {
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.lock_rounded, size: 18),
                    label: Text(
                      isOfficiallyComplete
                          ? 'Stage Officially Complete (Grades Locked)'
                          : 'Grade Finalized (Locked)',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      disabledBackgroundColor: const Color(0xFFE2E8F0),
                      disabledForegroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                );
              }

              final canSubmit = _allCriteriaFilled();
              final notReadyHint = !canSubmit;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (notReadyHint)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.08),
                        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              color: AppColors.warning, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Score all criteria across ${targetType == 'team' ? 'the rubric' : 'all members'} before submitting.',
                              style: const TextStyle(
                                  color: AppColors.warning,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: DefensysSaveButton(
                      onPressed: canSubmit ? _submit : null,
                      isSaving: widget.isSaving,
                      label: isAlreadyGraded ? 'Update Grade' : 'Submit Grade',
                      savingLabel: 'Submitting Grade…',
                      isPill: false,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      fontSize: 15,
                    ),
                  ),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildCriteriaTable(
    List<Map<String, dynamic>> criteria, {
    required bool isTeam,
    dynamic studentId,
    bool isReadOnly = false,
  }) {
    if (criteria.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('No criteria defined for this section.', style: TextStyle(color: _steelGrey)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _neutralBorder),
      ),
      child: Column(
        children: criteria.asMap().entries.map((entry) {
          final i = entry.key;
          final c = entry.value;
          final name = c['name']?.toString() ?? '';
          final desc = c['description']?.toString() ?? '';
          final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();

          final ctrl = isTeam
              ? (_teamScoreCtrl[name] ?? TextEditingController())
              : (_studentScoreCtrl[studentId]?[name] ?? TextEditingController());

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: i < criteria.length - 1
                  ? const Border(bottom: BorderSide(color: _neutralBorder, width: 0.5))
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700, color: _textDark)),
                      if (desc.isNotEmpty)
                        Text(desc, style: const TextStyle(fontSize: 12, color: _steelGrey)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text('/ $maxScore', style: const TextStyle(color: _steelGrey, fontSize: 13)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: isReadOnly
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            ctrl.text.isNotEmpty ? ctrl.text : '-',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _textDark,
                            ),
                          ),
                        )
                      : TextField(
                          controller: ctrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                          decoration: _inputDec('Score').copyWith(
                            hintStyle: const TextStyle(fontSize: 12),
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

  Future<void> _submit() async {
    final gradeId = widget.grade['id'] as int;
    final rubricId = _selectedRubric?['id'] as int?;

    if (_selectedRubric == null) {
      final adviserScore = (double.tryParse(_manualScoreCtrl.text) ?? 0).clamp(0, 100).toDouble();
      await widget.onSubmit(
        gradeId: gradeId,
        adviserScore: adviserScore,
        rubricId: null,
        criteriaScores: [],
        teamCriteriaScores: [],
        studentSubmissions: [],
      );
      return;
    }

    final teamCrits = _getTeamCriteria();
    final indCrits = _getIndividualCriteria();

    final teamCriteriaScores = <Map<String, dynamic>>[];
    for (final c in teamCrits) {
      final name = c['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final entered = (double.tryParse(_teamScoreCtrl[name]?.text ?? '') ?? 0).clamp(0, maxScore);
      teamCriteriaScores.add({
        'criterion_name': name,
        'score': entered,
        'max_score': maxScore,
        'display_order': c['display_order'] ?? 0,
      });
    }

    final studentSubmissions = <Map<String, dynamic>>[];
    final members = _getMembers();
    for (final m in members) {
      final sId = m['id'] ?? m['student_id'];
      final ctrlMap = _studentScoreCtrl[sId] ?? {};
      final studentCritScores = <Map<String, dynamic>>[];
      for (final c in indCrits) {
        final name = c['name']?.toString() ?? '';
        final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
        final entered = (double.tryParse(ctrlMap[name]?.text ?? '') ?? 0).clamp(0, maxScore);
        studentCritScores.add({
          'criterion_name': name,
          'score': entered,
          'max_score': maxScore,
          'display_order': c['display_order'] ?? 0,
        });
      }
      studentSubmissions.add({
        'student_id': sId,
        'criteria_scores': studentCritScores,
      });
    }

    final overallScore = _computeOverallTeamScore();

    await widget.onSubmit(
      gradeId: gradeId,
      adviserScore: overallScore,
      rubricId: rubricId,
      criteriaScores: teamCriteriaScores,
      teamCriteriaScores: teamCriteriaScores,
      studentSubmissions: studentSubmissions,
    );
  }

  Widget _sectionLabel(String label) {
    return Text(label,
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: _steelGrey, letterSpacing: 0.3));
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  InputDecoration _inputDec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _steelGrey, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _neutralBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _maroon, width: 1.5)),
      isDense: true,
      filled: true,
      fillColor: _bgLight,
    );
  }
}
