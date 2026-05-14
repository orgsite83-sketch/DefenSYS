import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/auth_provider.dart';
import '../../../services/grade_center_provider.dart';
import '../../../theme/app_theme.dart';
import 'widgets/defensys_admin_shell.dart';

class GradeCenterScreen extends ConsumerStatefulWidget {
  const GradeCenterScreen({super.key});

  @override
  ConsumerState<GradeCenterScreen> createState() => _GradeCenterScreenState();
}

class _GradeCenterScreenState extends ConsumerState<GradeCenterScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gradeCenterProvider.notifier).fetchGrades();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gradeCenterProvider);

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.star_rounded,
            title: 'Evaluation & Grade Center',
            subtitle:
                'Monitor real-time grading from Panelists, Advisors, and Peer-to-Peer rubrics.',
            actions: _primaryButton(
              icon: Icons.file_download_rounded,
              label: 'Export Grading Sheet',
              onTap: state.grades.isEmpty
                  ? null
                  : () => _showExportDialog(state),
            ),
          ),
          const SizedBox(height: 26),
          _buildStats(state),
          if (_isGradeCenterAdmin(ref.watch(authProvider).user)) ...[
            const SizedBox(height: 18),
            _capstoneEvaluationCard(state),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 14),
            _buildNotice(
              icon: Icons.error_outline_rounded,
              text: state.error!,
              color: const Color(0xFFDC2626),
            ),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 14),
            _buildNotice(
              icon: Icons.check_circle_outline_rounded,
              text: state.message!,
              color: const Color(0xFF10B981),
            ),
          ],
          const SizedBox(height: 22),
          _gradeTableCard(state),
        ],
      ),
    );
  }

  Widget _buildStats(GradeCenterState state) {
    return Row(
      children: [
        Expanded(
          child: _statPanel(
            title: 'TOTAL TEAMS',
            value: _count(state, 'all').toString(),
            accentColor: DefensysUi.techBlue,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _statPanel(
            title: 'FULLY GRADED (100%)',
            value:
                '${_count(state, 'published')} (${_percent(state, 'published')}%)',
            valueColor: const Color(0xFF10B981),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _statPanel(
            title: 'AWAITING PANELISTS',
            value: _count(state, 'pending').toString(),
            valueColor: const Color(0xFFF59E0B),
          ),
        ),
      ],
    );
  }

  bool _isGradeCenterAdmin(Map<String, dynamic>? user) {
    if (user == null) return false;
    if (user['role']?.toString() == 'admin') return true;
    if (user['is_superuser'] == true) return true;
    return false;
  }

  Widget _capstoneEvaluationCard(GradeCenterState state) {
    final sem = state.activeSemester;
    if (sem == null) {
      return DefensysCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: DefensysUi.steelGrey, size: 22),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Set an active academic term under Academic Periods to use Capstone evaluation switches.',
                style: TextStyle(
                  color: Color(0xFF5D6678),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final peerOn = sem['capstone_peer_evaluation_enabled'] != false;
    final advOn = sem['capstone_adviser_grading_enabled'] != false;

    return DefensysCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.tune_rounded, color: DefensysUi.primaryMaroon, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Capstone evaluation controls',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: DefensysUi.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Turn peer evaluation and adviser grading on or off for the active term.',
                      style: TextStyle(
                        fontSize: 13,
                        color: DefensysUi.steelGrey,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.only(left: 0, right: 4),
            title: const Text(
              'Peer evaluation',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            subtitle: const Text(
              'Students can use the Peer Eval tab for Capstone teams.',
              style: TextStyle(fontSize: 12, color: DefensysUi.steelGrey),
            ),
            value: peerOn,
            onChanged: state.isSaving
                ? null
                : (value) {
                    ref
                        .read(gradeCenterProvider.notifier)
                        .updateCapstoneEvaluationSettings(peerEvaluationEnabled: value);
                  },
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.only(left: 0, right: 4),
            title: const Text(
              'Adviser grading',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            subtitle: const Text(
              'Advisers can submit scores for teams they advise.',
              style: TextStyle(fontSize: 12, color: DefensysUi.steelGrey),
            ),
            value: advOn,
            onChanged: state.isSaving
                ? null
                : (value) {
                    ref
                        .read(gradeCenterProvider.notifier)
                        .updateCapstoneEvaluationSettings(adviserGradingEnabled: value);
                  },
          ),
        ],
      ),
    );
  }

  Widget _statPanel({
    required String title,
    required String value,
    Color valueColor = DefensysUi.textDark,
    Color accentColor = const Color(0xFFE5E7EB),
  }) {
    return Container(
      height: 122,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF5D6678),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            height: 5,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradeTableCard(GradeCenterState state) {
    return DefensysCard(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        children: [
          Row(
            children: [
              _yearLevelFilter(state),
              const SizedBox(width: 14),
              _statusFilter(state),
            ],
          ),
          const SizedBox(height: 20),
          if (state.isLoading)
            const SizedBox(
              height: 170,
              child: Center(
                child: CircularProgressIndicator(
                  color: DefensysUi.primaryMaroon,
                ),
              ),
            )
          else if (state.grades.isEmpty)
            _gradeEmptyTable()
          else
            _gradeTable(state),
        ],
      ),
    );
  }

  Widget _yearLevelFilter(GradeCenterState state) {
    return Container(
      width: 180,
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: state.yearLevel,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: DefensysUi.textDark,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('All Year Levels')),
            ...state.yearLevels.map(
              (level) => DropdownMenuItem(value: level, child: Text(level)),
            ),
          ],
          onChanged: state.isSaving
              ? null
              : (value) {
                  ref
                      .read(gradeCenterProvider.notifier)
                      .fetchGrades(yearLevel: value ?? '');
                },
        ),
      ),
    );
  }

  Widget _statusFilter(GradeCenterState state) {
    return Container(
      width: 180,
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: state.status,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: DefensysUi.textDark,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Status: All')),
            ...state.statuses.map(
              (status) => DropdownMenuItem(
                value: status,
                child: Text(_statusLabel(status)),
              ),
            ),
          ],
          onChanged: state.isSaving
              ? null
              : (value) {
                  ref
                      .read(gradeCenterProvider.notifier)
                      .fetchGrades(status: value ?? '');
                },
        ),
      ),
    );
  }

  Widget _gradeTable(GradeCenterState state) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 1515,
        child: Column(
          children: [
            _gradeHeader(),
            ...state.grades.map((grade) => _gradeRow(state, grade)),
          ],
        ),
      ),
    );
  }

  Widget _gradeHeader() {
    return Container(
      height: 51,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: const [
          _HeaderCell('Team Details', flex: 1.45),
          _HeaderCell('Panelist', flex: 0.92),
          _HeaderCell('Adviser', flex: 0.92),
          _HeaderCell('Peer', flex: 0.7),
          _HeaderCell('Final Grade', flex: 0.82),
          _HeaderCell('System Status', flex: 1.42),
          _HeaderCell('Action', flex: 0.84),
        ],
      ),
    );
  }

  Widget _gradeEmptyTable() {
    return Column(
      children: [
        _gradeHeader(),
        Container(
          height: 78,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: const Text(
            'No teams found.',
            style: TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _gradeRow(GradeCenterState state, Map<String, dynamic> grade) {
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          _TableCell(_teamDetails(grade), flex: 1.45),
          _TableCell(_scoreText(grade['panel_score']), flex: 0.92),
          _TableCell(
            grade['scope'] == 'pit'
                ? _bodyText('N/A')
                : _scoreText(grade['adviser_score']),
            flex: 0.92,
          ),
          _TableCell(_scoreText(grade['peer_score']), flex: 0.7),
          _TableCell(_finalGradeText(grade), flex: 0.82),
          _TableCell(
            _statusChip(grade['status']?.toString() ?? ''),
            flex: 1.42,
          ),
          _TableCell(_actions(state, grade), flex: 0.84),
        ],
      ),
    );
  }

  Widget _teamDetails(Map<String, dynamic> grade) {
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
      ],
    );
  }

  Widget _scoreText(dynamic value) {
    final score = _asDouble(value);
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

  Widget _finalGradeText(Map<String, dynamic> grade) {
    final score = _asDouble(grade['final_grade']);
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

  Widget _bodyText(String value) {
    return Text(
      value.isEmpty ? '-' : value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: DefensysUi.textDark,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: DefensysUi.primaryMaroon,
          foregroundColor: DefensysUi.accentGold,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  int _percent(GradeCenterState state, String key) {
    final total = _count(state, 'all');
    if (total == 0) {
      return 0;
    }
    return ((_count(state, key) / total) * 100).round();
  }

  Widget _actions(GradeCenterState state, Map<String, dynamic> grade) {
    final gradeId = _asInt(grade['id']);
    final canPublish =
        gradeId != null &&
        grade['status'] != 'published' &&
        _asDouble(grade['final_grade']) != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: state.isSaving || gradeId == null
              ? null
              : () => _showScoreDialog(grade),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(
              Icons.edit_square,
              color: DefensysUi.techBlue,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 3),
        InkWell(
          onTap: () => _showBreakdownDialog(grade),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(
              Icons.assessment_outlined,
              color: DefensysUi.steelGrey,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 3),
        InkWell(
          onTap: state.isSaving || !canPublish
              ? null
              : () => _confirmPublish(
                  gradeId,
                  grade['team_name']?.toString() ?? 'team',
                ),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              Icons.lock_outline,
              color: canPublish
                  ? DefensysUi.primaryMaroon
                  : const Color(0xFFC9CED8),
              size: 18,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showScoreDialog(Map<String, dynamic> grade) async {
    final gradeId = _asInt(grade['id']);
    if (gradeId == null) {
      return;
    }

    final panel = TextEditingController(
      text: _scoreInput(grade['panel_score']),
    );
    final adviser = TextEditingController(
      text: _scoreInput(grade['adviser_score']),
    );
    final peer = TextEditingController(text: _scoreInput(grade['peer_score']));
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
              Text(
                'Scores are percentages from 0 to 100.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: panel,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Panel Score (${_weightText(grade, 'panel')}%)',
                ),
              ),
              const SizedBox(height: 12),
              if (!isPit) ...[
                TextField(
                  controller: adviser,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText:
                        'Adviser Score (${_weightText(grade, 'adviser')}%)',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: peer,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Peer Score (${_weightText(grade, 'peer')}%)',
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

    if (!mounted || saved != true) {
      return;
    }

    await ref.read(gradeCenterProvider.notifier).updateGrade(gradeId, {
      'panel_score': _scorePayload(panelText),
      if (!isPit) 'adviser_score': _scorePayload(adviserText),
      'peer_score': _scorePayload(peerText),
    });
  }

  Future<void> _confirmPublish(int gradeId, String teamName) async {
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

    if (!mounted || confirmed != true) {
      return;
    }
    await ref.read(gradeCenterProvider.notifier).publishGrade(gradeId);
  }

  void _showBreakdownDialog(Map<String, dynamic> grade) {
    final breakdowns = grade['breakdowns'] is List
        ? List<Map<String, dynamic>>.from(
            (grade['breakdowns'] as List).whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ),
          )
        : <Map<String, dynamic>>[];
    final peers = grade['peer_per_student'] is List
        ? List<Map<String, dynamic>>.from(
            (grade['peer_per_student'] as List).whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ),
          )
        : <Map<String, dynamic>>[];

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Grade Breakdown - ${grade['team_name'] ?? ''}'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _formulaLine(grade),
                const SizedBox(height: 16),
                if (breakdowns.isEmpty)
                  const Text(
                    'No criterion breakdown has been posted yet.',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else
                  ...['panel', 'adviser', 'peer'].map((type) {
                    final rows = breakdowns
                        .where((item) => item['evaluation_type'] == type)
                        .toList();
                    if (rows.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return _breakdownSection(type, rows);
                  }),
                if (peers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Peer Per Student',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ...peers.map(
                    (peer) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(peer['student_name']?.toString() ?? ''),
                      trailing: Text(
                        '${peer['average_score']} / ${peer['max_score']} (${peer['normalized_score']}%)',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _formulaLine(Map<String, dynamic> grade) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.maroon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Formula: Panel ${_weightText(grade, 'panel')}% + '
        '${grade['scope'] == 'pit' ? '' : 'Adviser ${_weightText(grade, 'adviser')}% + '}'
        'Peer ${_weightText(grade, 'peer')}% = Final Grade. Pass threshold: 75.',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _breakdownSection(String type, List<Map<String, dynamic>> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _evaluationLabel(type),
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
                  _TableHeader('Criterion'),
                  _TableHeader('Score'),
                  _TableHeader('Max'),
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

  void _showExportDialog(GradeCenterState state) {
    final csv = _csvFor(state.grades);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export Grading Sheet'),
        content: SizedBox(
          width: 720,
          height: 420,
          child: SingleChildScrollView(child: SelectableText(csv)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _csvFor(List<Map<String, dynamic>> grades) {
    final rows = [
      'Team,Scope,Year Level,Stage,Panel,Adviser,Peer,Final,Status',
      ...grades.map((grade) {
        return [
          grade['team_name'],
          grade['scope'],
          grade['year_level'],
          grade['stage_label'],
          grade['panel_score'],
          grade['adviser_score'],
          grade['peer_score'],
          grade['final_grade'],
          grade['status'],
        ].map(_csvCell).join(',');
      }),
    ];
    return rows.join('\n');
  }

  String _csvCell(dynamic value) {
    final text = (value ?? '').toString().replaceAll('"', '""');
    return '"$text"';
  }

  Widget _statusChip(String status) {
    final color = switch (status) {
      'published' => AppColors.success,
      'awaiting_peers' => Colors.blue,
      _ => AppColors.warning,
    };
    final icon = switch (status) {
      'published' => Icons.lock_outline,
      'awaiting_peers' => Icons.people_outline,
      _ => Icons.hourglass_empty,
    };
    return _chip(_statusLabel(status), color, icon: icon);
  }

  Widget _chip(String label, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
          ],
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

  Widget _buildNotice({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'published' => 'Published',
      'awaiting_peers' => 'Awaiting Peers',
      'pending' => 'Pending',
      _ => status.isEmpty ? 'Pending' : status,
    };
  }

  String _evaluationLabel(String value) {
    return switch (value) {
      'adviser' => 'Adviser Evaluation',
      'peer' => 'Peer Evaluation',
      _ => 'Panel Evaluation',
    };
  }

  String _weightText(Map<String, dynamic> grade, String key) {
    final weights = grade['weights'];
    if (weights is Map) {
      return weights[key]?.toString() ?? '0';
    }
    return '0';
  }

  String _scoreInput(dynamic value) {
    final score = _asDouble(value);
    return score == null ? '' : score.toStringAsFixed(2);
  }

  dynamic _scorePayload(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed);
  }

  int _count(GradeCenterState state, String key) {
    final value = state.counts[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.text);

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

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text, {required this.flex});

  final String text;
  final double flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF5D6678),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  const _TableCell(this.child, {required this.flex});

  final Widget child;
  final double flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}
