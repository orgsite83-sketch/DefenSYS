import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/adviser_grading_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/defensys_tokens.dart';

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
                    required double adviserScore,
                    int? rubricId,
                    required List<Map<String, dynamic>> criteriaScores,
                  }) async {
                    await ref.read(adviserGradingProvider.notifier).submitGrade(
                          gradeId: gradeId,
                          adviserScore: adviserScore,
                          rubricId: rubricId,
                          criteriaScores: criteriaScores,
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text('No teams to grade', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _textDark)),
          const SizedBox(height: 8),
          const Text(
            'There are no capstone teams assigned to you yet.',
            style: TextStyle(color: _steelGrey),
          ),
        ],
      ),
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
  required double adviserScore,
  int? rubricId,
  required List<Map<String, dynamic>> criteriaScores,
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

  // Per-criterion score controllers: key = criterion name
  final Map<String, TextEditingController> _scoreCtrl = {};

  // Manual override controller (when no rubric selected)
  final TextEditingController _manualScoreCtrl = TextEditingController();

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
    for (final c in _scoreCtrl.values) {
      c.dispose();
    }
    _manualScoreCtrl.dispose();
    super.dispose();
  }

  void _selectRubric(
    Map<String, dynamic>? rubric, {
    bool hydrateFromGrade = false,
  }) {
    for (final c in _scoreCtrl.values) {
      c.dispose();
    }
    _scoreCtrl.clear();

    _selectedRubric = rubric;
    if (rubric == null) {
      return;
    }

    final savedScores = <String, String>{};
    if (hydrateFromGrade && widget.grade['breakdowns'] is List) {
      for (final row in widget.grade['breakdowns'] as List) {
        if (row is! Map) continue;
        if (row['evaluation_type']?.toString() != 'adviser') continue;
        final name = row['criterion_name']?.toString() ?? '';
        if (name.isNotEmpty) {
          savedScores[name] = row['score']?.toString() ?? '';
        }
      }
    }

    for (final c in (rubric['criteria'] as List? ?? [])) {
      final cMap = c as Map;
      final name = cMap['name']?.toString() ?? '';
      final ctrl = TextEditingController(text: savedScores[name] ?? '');
      _scoreCtrl[name] = ctrl;
    }
  }

  double _computeTotalScore() {
    if (_selectedRubric == null) return 0;
    final criteria = (_selectedRubric!['criteria'] as List? ?? []);
    if (criteria.isEmpty) return 0;
    double total = 0;
    double maxTotal = 0;
    for (final c in criteria) {
      final name = (c as Map)['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final entered = double.tryParse(_scoreCtrl[name]?.text ?? '') ?? 0;
      total += entered.clamp(0, maxScore);
      maxTotal += maxScore;
    }
    if (maxTotal == 0) return 0;
    return (total / maxTotal * 100).clamp(0, 100);
  }

  /// Returns true only when every criterion in the selected rubric has a
  /// valid numeric score entered (and the score is within range).
  bool _allCriteriaFilled() {
    if (_selectedRubric == null) return false;
    final criteria = (_selectedRubric!['criteria'] as List? ?? []);
    if (criteria.isEmpty) return false;
    for (final c in criteria) {
      final name = (c as Map)['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final text = _scoreCtrl[name]?.text.trim() ?? '';
      if (text.isEmpty) return false;
      final value = double.tryParse(text);
      if (value == null || value < 0 || value > maxScore) return false;
    }
    return true;
  }

  /// How many criteria have valid scores entered.
  int _filledCount() {
    if (_selectedRubric == null) return 0;
    final criteria = (_selectedRubric!['criteria'] as List? ?? []);
    int count = 0;
    for (final c in criteria) {
      final name = (c as Map)['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final text = _scoreCtrl[name]?.text.trim() ?? '';
      final value = double.tryParse(text);
      if (text.isNotEmpty && value != null && value >= 0 && value <= maxScore) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final grade = widget.grade;
    final teamName = grade['team_name']?.toString() ?? 'Team';
    final projectTitle = grade['project_title']?.toString() ?? '';
    final stageLabel = grade['stage_label']?.toString() ?? '';
    final adviserWeight = (grade['weights'] as Map?)?['adviser'];
    final isAlreadyGraded = grade['adviser_score'] != null;

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
                        children: [
                          if (stageLabel.isNotEmpty) _tag(stageLabel, _maroon),
                          if (adviserWeight != null) _tag('Adviser Weight: $adviserWeight%', Colors.blueGrey),
                          if (isAlreadyGraded)
                            _tag('Previously Graded: ${grade['adviser_score']}', AppColors.success),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _sectionLabel('Assigned adviser rubric'),
          const SizedBox(height: 8),
          _selectedRubric == null
              ? Container(
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
                          'Ask your administrator to set panel, adviser, and peer rubrics in Defense Stages or the scheduler.',
                          style: TextStyle(color: AppColors.warning, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _maroon.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _maroon.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    '${_selectedRubric!['name']} (${_selectedRubric!['scale'] ?? 'Rubric'})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _textDark,
                      fontSize: 14,
                    ),
                  ),
                ),
          const SizedBox(height: 22),

          // ─ Criteria scoring table ────────────────────────────────────────
          if (_selectedRubric != null) ...[
            Row(
              children: [
                _sectionLabel('Score Each Criterion'),
                const Spacer(),
                Builder(builder: (_) {
                  final total = (_selectedRubric!['criteria'] as List? ?? []).length;
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
            const SizedBox(height: 10),
            _buildCriteriaTable(),
            const SizedBox(height: 16),
            // Computed total
            StatefulBuilder(
              builder: (_, setInner) {
                final score = _computeTotalScore();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _maroon.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _maroon.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Text('Computed Adviser Score:',
                          style: TextStyle(fontWeight: FontWeight.w700, color: _textDark)),
                      const Spacer(),
                      Text(
                        score.toStringAsFixed(2),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800, color: _maroon),
                      ),
                      const Text(' / 100',
                          style: TextStyle(color: _steelGrey, fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              },
            ),
          ] else ...[
            // Manual score fallback
            _sectionLabel('Adviser Score (0 – 100)'),
            const SizedBox(height: 8),
            SizedBox(
              width: 220,
              child: TextFormField(
                controller: _manualScoreCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _inputDec('e.g. 87.50'),
              ),
            ),
          ],
          const SizedBox(height: 28),

          // ─ Submit button ─────────────────────────────────────────────────
          Builder(builder: (_) {
            // When a rubric is selected, require all criteria to be filled.
            // When no rubric (manual mode), the button is always active.
            final canSubmit = _selectedRubric != null
                ? _allCriteriaFilled()
                : (double.tryParse(_manualScoreCtrl.text.trim()) != null);

            final notReadyHint = _selectedRubric != null && !canSubmit;

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
                            'Score all ${(_selectedRubric!['criteria'] as List? ?? []).length} criteria before submitting.',
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
                  child: ElevatedButton.icon(
                    onPressed: (widget.isSaving || !canSubmit) ? null : _submit,
                    icon: widget.isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(
                      isAlreadyGraded ? 'Update Grade' : 'Submit Grade',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canSubmit ? _maroon : Colors.grey.shade300,
                      foregroundColor: canSubmit ? Colors.white : Colors.grey.shade500,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCriteriaTable() {
    final criteria = (_selectedRubric!['criteria'] as List? ?? []);
    if (criteria.isEmpty) {
      return const Text('This rubric has no criteria defined.',
          style: TextStyle(color: _steelGrey));
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
          final c = entry.value as Map;
          final name = c['name']?.toString() ?? '';
          final desc = c['description']?.toString() ?? '';
          final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
          final ctrl = _scoreCtrl[name] ?? TextEditingController();

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
                  child: TextField(
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

    double adviserScore;
    List<Map<String, dynamic>> criteriaScores = [];
    int? rubricId;

    if (_selectedRubric != null) {
      final criteria = (_selectedRubric!['criteria'] as List? ?? []);
      for (final c in criteria) {
        final cMap = c as Map;
        final name = cMap['name']?.toString() ?? '';
        final maxScore = ((cMap['max_score'] as num?) ?? 10).toDouble();
        final entered = (double.tryParse(_scoreCtrl[name]?.text ?? '') ?? 0).clamp(0, maxScore);
        criteriaScores.add({
          'criterion_name': name,
          'score': entered,
          'max_score': maxScore,
          'display_order': cMap['display_order'] ?? 0,
        });
      }
      adviserScore = _computeTotalScore();
      rubricId = _selectedRubric!['id'] as int?;
    } else {
      adviserScore = double.tryParse(_manualScoreCtrl.text) ?? 0;
      adviserScore = adviserScore.clamp(0, 100);
    }

    await widget.onSubmit(
      gradeId: gradeId,
      adviserScore: adviserScore,
      rubricId: rubricId,
      criteriaScores: criteriaScores,
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
