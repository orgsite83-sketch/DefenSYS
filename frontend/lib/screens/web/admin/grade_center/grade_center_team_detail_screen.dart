import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/grade_center_provider.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/error_banner.dart';
import '../widgets/defensys_admin_shell.dart';
import 'grade_center_shared.dart';

class GradeCenterTeamDetailScreen extends ConsumerStatefulWidget {
  const GradeCenterTeamDetailScreen({
    super.key,
    required this.gradeId,
    required this.isLocked,
    required this.onBack,
  });

  final int gradeId;
  final bool isLocked;
  final VoidCallback onBack;

  @override
  ConsumerState<GradeCenterTeamDetailScreen> createState() =>
      _GradeCenterTeamDetailScreenState();
}

class _GradeCenterTeamDetailScreenState
    extends ConsumerState<GradeCenterTeamDetailScreen> {
  int _activeViewIndex = 0; // 0: Master Grade Sheet, 1: Individual Rubric Breakdown
  int? _selectedStudentId;
  final ScrollController _detailMasterScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gradeCenterProvider.notifier).refreshGrade(widget.gradeId);
    });
  }

  @override
  void dispose() {
    _detailMasterScrollController.dispose();
    super.dispose();
  }

  Future<void> _reloadGrade() async {
    await ref.read(gradeCenterProvider.notifier).refreshGrade(widget.gradeId);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gradeCenterProvider);
    final grade = gradeById(state, widget.gradeId);

    if (grade == null && state.isRefreshingGrade) {
      return SingleChildScrollView(
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailHeader(
              title: 'Team Evaluation Details',
              subtitle: 'Loading evaluation records…',
              onBack: widget.onBack,
            ),
            const SizedBox(height: 48),
            const Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ],
        ),
      );
    }

    if (state.error != null && grade == null) {
      return SingleChildScrollView(
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailHeader(
              title: 'Team Evaluation Details',
              subtitle: '',
              onBack: widget.onBack,
            ),
            const SizedBox(height: 24),
            ErrorBanner(
              title: 'Failed to load grade details',
              message: state.error!,
              onRetry: _reloadGrade,
            ),
          ],
        ),
      );
    }

    if (grade == null) {
      return SingleChildScrollView(
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailHeader(
              title: 'Team Evaluation Details',
              subtitle: '',
              onBack: widget.onBack,
            ),
            const SizedBox(height: 24),
            const Text('Grade record not found.'),
          ],
        ),
      );
    }

    final isPit = grade['scope'] == 'pit';
    final breakdowns = parseBreakdowns(grade);
    final peers = parsePeerPerStudent(grade);
    final gradeIdValue = asInt(grade['id']);
    final canPublish = !isPit &&
        !widget.isLocked &&
        gradeIdValue != null &&
        grade['status'] != 'published' &&
        grade['grading_ready'] == true;
    final canEdit = !widget.isLocked && gradeIdValue != null;

    final panelWeight = asDouble(weightText(grade, 'panel')) ?? (isPit ? 70.0 : 50.0);
    final adviserWeight = asDouble(weightText(grade, 'adviser')) ?? (isPit ? 0.0 : 30.0);
    final peerWeight = asDouble(weightText(grade, 'peer')) ?? (isPit ? 30.0 : 20.0);

    // Build panelist lookup map
    final panelistList = grade['panelists'] is List ? (grade['panelists'] as List) : [];
    final panelistMap = <String, String>{};
    for (final p in panelistList) {
      if (p is Map) {
        final u = p['username']?.toString().trim();
        final n = p['name']?.toString().trim();
        if (u != null && n != null && u.isNotEmpty && n.isNotEmpty) {
          panelistMap[u] = n;
        }
      }
    }

    final panelists = _extractPanelists(grade, breakdowns, panelistMap);

    // Build unified student list
    final members = grade['members'] is List ? (grade['members'] as List) : [];
    final peerMapByStudentId = <int, Map<String, dynamic>>{};
    for (final p in peers) {
      final sid = asInt(p['student_id'] ?? p['id']);
      if (sid != null) peerMapByStudentId[sid] = p;
    }

    final students = <_StudentDetailData>[];
    if (members.isNotEmpty) {
      for (final m in members) {
        if (m is! Map) continue;
        final sid = asInt(m['student_id'] ?? m['id']);
        final name = m['name']?.toString() ?? 'Student';
        final isLeader = m['is_leader'] == true;
        final peerRecord = sid != null ? peerMapByStudentId[sid] : null;

        // Extract individual panelist scores for this student
        final panelistScores = <String, double?>{};
        double panelSum = 0;
        int panelCount = 0;
        for (final pan in panelists) {
          final pScore = _getPanelistScoreForStudent(
            breakdowns: breakdowns,
            panelistKey: pan.key,
            studentId: sid,
          );
          panelistScores[pan.key] = pScore;
          if (pScore != null) {
            panelSum += pScore;
            panelCount++;
          }
        }

        final pAvg = panelCount > 0
            ? (panelSum / panelCount)
            : (asDouble(peerRecord?['panel_score']) ?? asDouble(grade['panel_score']));
        final aScore = isPit ? null : (asDouble(peerRecord?['adviser_score']) ?? asDouble(grade['adviser_score']));
        final prScore = asDouble(peerRecord?['peer_score']) ?? asDouble(grade['peer_score']);
        final fGrade = asDouble(peerRecord?['final_grade']) ?? asDouble(grade['final_grade']);

        students.add(_StudentDetailData(
          studentId: sid,
          name: name,
          isLeader: isLeader,
          panelistScores: panelistScores,
          panelScore: pAvg,
          panelContrib: pAvg != null ? (pAvg * panelWeight / 100.0) : null,
          adviserScore: aScore,
          adviserContrib: aScore != null ? (aScore * adviserWeight / 100.0) : null,
          peerScore: prScore,
          peerContrib: prScore != null ? (prScore * peerWeight / 100.0) : null,
          finalGrade: fGrade,
        ));
      }
    } else if (peers.isNotEmpty) {
      for (final p in peers) {
        final sid = asInt(p['student_id'] ?? p['id']);
        final name = p['student_name']?.toString() ?? 'Student';

        final panelistScores = <String, double?>{};
        double panelSum = 0;
        int panelCount = 0;
        for (final pan in panelists) {
          final pScore = _getPanelistScoreForStudent(
            breakdowns: breakdowns,
            panelistKey: pan.key,
            studentId: sid,
          );
          panelistScores[pan.key] = pScore;
          if (pScore != null) {
            panelSum += pScore;
            panelCount++;
          }
        }

        final pAvg = panelCount > 0
            ? (panelSum / panelCount)
            : (asDouble(p['panel_score']) ?? asDouble(grade['panel_score']));
        final aScore = isPit ? null : (asDouble(p['adviser_score']) ?? asDouble(grade['adviser_score']));
        final prScore = asDouble(p['peer_score']) ?? asDouble(grade['peer_score']);
        final fGrade = asDouble(p['final_grade']) ?? asDouble(grade['final_grade']);

        students.add(_StudentDetailData(
          studentId: sid,
          name: name,
          isLeader: false,
          panelistScores: panelistScores,
          panelScore: pAvg,
          panelContrib: pAvg != null ? (pAvg * panelWeight / 100.0) : null,
          adviserScore: aScore,
          adviserContrib: aScore != null ? (aScore * adviserWeight / 100.0) : null,
          peerScore: prScore,
          peerContrib: prScore != null ? (prScore * peerWeight / 100.0) : null,
          finalGrade: fGrade,
        ));
      }
    }

    // Default selected student to leader or first student
    if (_selectedStudentId == null && students.isNotEmpty) {
      final leader = students.firstWhere((s) => s.isLeader, orElse: () => students.first);
      _selectedStudentId = leader.studentId;
    }

    final selectedStudent = students.firstWhere(
      (s) => s.studentId == _selectedStudentId,
      orElse: () => students.isNotEmpty ? students.first : const _StudentDetailData(name: 'Student'),
    );

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Detail Header Bar
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back to Grade Center',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          grade['stage_label']?.toString() ?? 'Defense Stage',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 14,
                          color: Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          grade['team_name']?.toString() ?? 'Team Details',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Evaluation Details',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh grades',
                onPressed: state.isRefreshingGrade ? null : _reloadGrade,
                icon: state.isRefreshingGrade
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 20),
              ),
              if (canEdit) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => GradeCenterActions.showEditScoresDialog(
                    context: context,
                    ref: ref,
                    grade: grade,
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 15),
                  label: const Text('Edit scores'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ],
              if (!isPit && canEdit) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => GradeCenterActions.showVerdictDialog(
                    context: context,
                    ref: ref,
                    grade: grade,
                  ),
                  icon: const Icon(Icons.gavel_rounded, size: 15),
                  label: Text(
                    (grade['verdict']?.toString() ?? '').isNotEmpty
                        ? 'Update Verdict'
                        : 'Issue Verdict',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ],
              if (canPublish) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: state.isSaving
                      ? null
                      : () => GradeCenterActions.confirmPublish(
                            context: context,
                            ref: ref,
                            gradeId: gradeIdValue,
                            teamName: grade['team_name']?.toString() ?? 'team',
                          ),
                  icon: const Icon(Icons.lock_outline, size: 15),
                  label: const Text('Publish Grade'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DefensysTokens.maroon,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ],
            ],
          ),

          if (state.error != null) ...[
            const SizedBox(height: 14),
            ErrorBanner(
              title: 'Failed to load grade details',
              message: state.error!,
              onRetry: _reloadGrade,
            ),
          ],

          const SizedBox(height: 16),

          // Locked event notification banner
          gradeCenterLockedBanner(isLocked: widget.isLocked),

          // Executive Hero Summary Header
          gradeCenterHeroSummaryCard(grade: grade),

          if (grade['attempt_history'] is List && (grade['attempt_history'] as List).isNotEmpty) ...[
            const SizedBox(height: 16),
            attemptHistoryCardWidget(
              attemptHistory: grade['attempt_history'] as List,
              currentAttemptCount: (grade['attempt_count'] is int)
                  ? grade['attempt_count'] as int
                  : int.tryParse(grade['attempt_count']?.toString() ?? '1') ?? 1,
            ),
          ],

          const SizedBox(height: 20),

          // Segmented View Mode Tabs (Master Grade Sheet vs Individual Rubric Breakdown)
          _buildViewModeTabs(),

          const SizedBox(height: 16),

          // Main View Body according to selected Tab
          if (_activeViewIndex == 0)
            _buildOfficialUniversityMasterSheet(
              students: students,
              panelists: panelists,
              isPit: isPit,
              panelWeight: panelWeight,
              adviserWeight: adviserWeight,
              peerWeight: peerWeight,
            )
          else
            _buildDetailedInspectorView(
              grade: grade,
              students: students,
              selectedStudent: selectedStudent,
              breakdowns: breakdowns,
              peers: peers,
              panelistMap: panelistMap,
              panelWeight: panelWeight,
              adviserWeight: adviserWeight,
              peerWeight: peerWeight,
              isPit: isPit,
            ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ==========================================
  // VIEW MODE SEGMENTED TABS
  // ==========================================
  Widget _buildViewModeTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewModeTabItem(
            index: 0,
            icon: Icons.table_chart_rounded,
            label: 'Master Grade Sheet',
            badge: 'Summary',
          ),
          const SizedBox(width: 4),
          _viewModeTabItem(
            index: 1,
            icon: Icons.assignment_outlined,
            label: 'Individual Rubric Breakdown',
            badge: 'Student Evaluations',
          ),
        ],
      ),
    );
  }

  Widget _viewModeTabItem({
    required int index,
    required IconData icon,
    required String label,
    required String badge,
  }) {
    final isSelected = _activeViewIndex == index;
    return InkWell(
      onTap: () => setState(() => _activeViewIndex = index),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: OFFICIAL UNIVERSITY MASTER GRADE SHEET
  // (Header: No. · Names · SCORES (Panelists) · Average · GRADE (50%) · Advisers Rating (30%) · Peer Rating (20%) · TOTAL · FINAL GRADE)
  // ==========================================
  Widget _buildOfficialUniversityMasterSheet({
    required List<_StudentDetailData> students,
    required List<_PanelistColumnDef> panelists,
    required bool isPit,
    required double panelWeight,
    required double adviserWeight,
    required double peerWeight,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.table_chart_rounded, size: 16, color: Color(0xFF2563EB)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Master Student Grade Sheet',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        isPit
                            ? 'Official Stage Grade Matrix · Panelist Scores (${panelWeight.toStringAsFixed(0)}%) + Peer Rating (${peerWeight.toStringAsFixed(0)}%)'
                            : 'Official Stage Grade Matrix · Panelist Scores (${panelWeight.toStringAsFixed(0)}%) + Adviser Rating (${adviserWeight.toStringAsFixed(0)}%) + Peer Rating (${peerWeight.toStringAsFixed(0)}%)',
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Master Spreadsheet DataTable with DefenSYS Design System Palette
          LayoutBuilder(
            builder: (context, constraints) {
              final totalCols = 6 + panelists.length + (!isPit && adviserWeight > 0 ? 2 : 0);
              final dynamicSpacing = ((constraints.maxWidth - 550) / totalCols).clamp(16.0, 42.0);

              return Scrollbar(
                controller: _detailMasterScrollController,
                thumbVisibility: true,
                trackVisibility: true,
                child: SingleChildScrollView(
                  controller: _detailMasterScrollController,
                  scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                  ),
                  child: DataTable(
                    showCheckboxColumn: false,
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: 64,
                    columnSpacing: dynamicSpacing,
                    horizontalMargin: 20,
                    dividerThickness: 1,
                    columns: [
                      // 1. No.
                      const DataColumn(
                        label: Text(
                          'No.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                      // 2. Names
                      const DataColumn(
                        label: Text(
                          'Names',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                      // 3. SCORES -> Panel 1, Panel 2, ...
                      ...panelists.asMap().entries.map((entry) {
                        final idx = entry.key + 1;
                        final pan = entry.value;
                        return DataColumn(
                          label: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Panel $idx',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                              Text(
                                pan.displayName,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      // 4. Average
                      const DataColumn(
                        label: Text(
                          'Average',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      // 5. GRADE 50% (DefenSYS Blue)
                      DataColumn(
                        label: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            'GRADE ${panelWeight.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ),
                      ),
                      // 6. Advisers Rating & 30% (DefenSYS Emerald)
                      if (!isPit && adviserWeight > 0) ...[
                        const DataColumn(
                          label: Text(
                            "Adviser's Rating",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.25)),
                            ),
                            child: Text(
                              '${adviserWeight.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ),
                        ),
                      ],
                      // 7. Peer Rating & 20% (Sky Blue)
                      const DataColumn(
                        label: Text(
                          'Peer Rating',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F9FF),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            '${peerWeight.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0284C7),
                            ),
                          ),
                        ),
                      ),
                      // 8. TOTAL
                      DataColumn(
                        label: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: const Text(
                            'TOTAL',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      // 9. FINAL GRADE
                      DataColumn(
                        label: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'FINAL GRADE',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                    rows: students.asMap().entries.map((studentEntry) {
                      final no = studentEntry.key + 1;
                      final s = studentEntry.value;
                      final isPassed = s.finalGrade != null && s.finalGrade! >= 75.0;

                      return DataRow(
                        cells: [
                          // 1. No.
                          DataCell(
                            Text(
                              '$no',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                          // 2. Names
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  s.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                if (s.isLeader) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                                    ),
                                    child: const Text(
                                      'LEADER',
                                      style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // 3. Panelist Individual Scores
                          ...panelists.map((pan) {
                            final score = s.panelistScores[pan.key];
                            return DataCell(
                              score != null
                                  ? Text(
                                      '${score.toStringAsFixed(1)}%',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF334155),
                                      ),
                                    )
                                  : const Text('—', style: TextStyle(color: Color(0xFF94A3B8))),
                            );
                          }),
                          // 4. Panel Average
                          DataCell(
                            s.panelScore != null
                                ? Text(
                                    '${s.panelScore!.toStringAsFixed(2)}%',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                      color: Color(0xFF1E293B),
                                    ),
                                  )
                                : const Text('—', style: TextStyle(color: Color(0xFF94A3B8))),
                          ),
                          // 5. GRADE 50% (DefenSYS Blue Pill)
                          DataCell(
                            s.panelContrib != null
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.25)),
                                    ),
                                    child: Text(
                                      s.panelContrib!.toStringAsFixed(2),
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF2563EB),
                                      ),
                                    ),
                                  )
                                : const Text('—', style: TextStyle(color: Color(0xFF94A3B8))),
                          ),
                          // 6. Advisers Rating & 30% (DefenSYS Emerald Pill)
                          if (!isPit && adviserWeight > 0) ...[
                            DataCell(
                              s.adviserScore != null
                                  ? Text(
                                      '${s.adviserScore!.toStringAsFixed(2)}%',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF334155),
                                      ),
                                    )
                                  : const Text('—', style: TextStyle(color: Color(0xFF94A3B8))),
                            ),
                            DataCell(
                              s.adviserContrib != null
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFECFDF5),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.25)),
                                      ),
                                      child: Text(
                                        s.adviserContrib!.toStringAsFixed(2),
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF059669),
                                        ),
                                      ),
                                    )
                                  : const Text('—', style: TextStyle(color: Color(0xFF94A3B8))),
                            ),
                          ],
                          // 7. Peer Rating & 20% (DefenSYS Violet Pill)
                          DataCell(
                            s.peerScore != null
                                ? Text(
                                    '${s.peerScore!.toStringAsFixed(2)}%',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF334155),
                                    ),
                                  )
                                : const Text('—', style: TextStyle(color: Color(0xFF94A3B8))),
                          ),
                          DataCell(
                            s.peerContrib != null
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0F9FF),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.25)),
                                    ),
                                    child: Text(
                                      s.peerContrib!.toStringAsFixed(2),
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0284C7),
                                      ),
                                    ),
                                  )
                                : const Text('—', style: TextStyle(color: Color(0xFF94A3B8))),
                          ),
                          // 8. TOTAL
                          DataCell(
                            s.finalGrade != null
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Text(
                                      s.finalGrade!.toStringAsFixed(2),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12.5,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  )
                                : const Text('—', style: TextStyle(color: Color(0xFF94A3B8))),
                          ),
                          // 9. FINAL GRADE & STATUS
                          DataCell(
                            s.finalGrade != null
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${s.finalGrade!.toStringAsFixed(2)}%',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildStatusBadgeCell(isPassed, s.finalGrade),
                                    ],
                                  )
                                : const Text('—', style: TextStyle(color: Color(0xFF94A3B8))),
                          ),
                        ],
                      );
                    }).toList(),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: INDIVIDUAL RUBRIC BREAKDOWN (SPLIT VIEW)
  // ==========================================
  Widget _buildDetailedInspectorView({
    required Map<String, dynamic> grade,
    required List<_StudentDetailData> students,
    required _StudentDetailData selectedStudent,
    required List<Map<String, dynamic>> breakdowns,
    required List<Map<String, dynamic>> peers,
    required Map<String, String> panelistMap,
    required double panelWeight,
    required double adviserWeight,
    required double peerWeight,
    required bool isPit,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1024;
        final leftPane = _buildStudentRosterPane(
          students: students,
          selectedStudentId: _selectedStudentId,
          onSelectStudent: (sid) => setState(() => _selectedStudentId = sid),
        );
        final rightPane = _buildCriteriaInspectorPane(
          grade: grade,
          selectedStudent: selectedStudent,
          students: students,
          breakdowns: breakdowns,
          peers: peers,
          panelistMap: panelistMap,
          panelWeight: panelWeight,
          adviserWeight: adviserWeight,
          peerWeight: peerWeight,
          isPit: isPit,
        );

        if (isDesktop) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 360, child: leftPane),
              const SizedBox(width: 18),
              Expanded(child: rightPane),
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leftPane,
              const SizedBox(height: 18),
              rightPane,
            ],
          );
        }
      },
    );
  }

  // ==========================================
  // LEFT PANE: STUDENT ROSTER MASTER LIST
  // ==========================================
  Widget _buildStudentRosterPane({
    required List<_StudentDetailData> students,
    required int? selectedStudentId,
    required ValueChanged<int?> onSelectStudent,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Pane Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.people_alt_rounded, size: 16, color: Color(0xFF2563EB)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Student Members',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${students.length}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      const Text(
                        'Select a student to view rubric evaluation',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Student List
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: students.map((s) {
                final isSelected = s.studentId == selectedStudentId;
                final isPassed = s.finalGrade != null && s.finalGrade! >= 75.0;
                final initials = s.name
                    .trim()
                    .split(' ')
                    .map((w) => w.isNotEmpty ? w[0] : '')
                    .take(2)
                    .join()
                    .toUpperCase();

                return InkWell(
                  onTap: () => onSelectStudent(s.studentId),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFF0F7FF) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                        width: isSelected ? 1.8 : 1.0,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Row: Avatar + Name + Final Grade
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: isSelected ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
                              child: Text(
                                initials.isEmpty ? 'S' : initials,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected ? Colors.white : const Color(0xFF475569),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      s.name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                                        color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (s.isLeader) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                                      ),
                                      child: const Text(
                                        'LEADER',
                                        style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // Final Grade Badge
                            if (s.finalGrade != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isPassed ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${s.finalGrade!.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: isPassed ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                  ),
                                ),
                              )
                            else
                              const Text('Pending', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Quick Formula Snippets
                        Row(
                          children: [
                            _miniFormulaTag('Panel', s.panelScore, const Color(0xFF2563EB)),
                            if (s.adviserScore != null) ...[
                              const SizedBox(width: 6),
                              _miniFormulaTag('Adv', s.adviserScore, const Color(0xFF059669)),
                            ],
                            const SizedBox(width: 6),
                            _miniFormulaTag('Peer', s.peerScore, const Color(0xFF0284C7)),
                            const Spacer(),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniFormulaTag(String label, double? score, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: ${score != null ? '${score.toStringAsFixed(0)}%' : '—'}',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // ==========================================
  // RIGHT PANE: LIVE CRITERIA & RUBRIC INSPECTOR
  // ==========================================
  Widget _buildCriteriaInspectorPane({
    required Map<String, dynamic> grade,
    required _StudentDetailData selectedStudent,
    required List<_StudentDetailData> students,
    required List<Map<String, dynamic>> breakdowns,
    required List<Map<String, dynamic>> peers,
    required Map<String, String> panelistMap,
    required double panelWeight,
    required double adviserWeight,
    required double peerWeight,
    required bool isPit,
  }) {
    final isPassed = selectedStudent.finalGrade != null && selectedStudent.finalGrade! >= 75.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Inspector Header Bar with Student Identity
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '🎓 ${selectedStudent.name}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (selectedStudent.isLeader) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                              ),
                              child: const Text(
                                'LEADER',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Individual rubric criteria evaluation & evaluator feedback',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                // Final Grade Capsule
                if (selectedStudent.finalGrade != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isPassed ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isPassed
                            ? const Color(0xFF059669).withValues(alpha: 0.3)
                            : const Color(0xFFDC2626).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPassed ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          size: 15,
                          color: isPassed ? const Color(0xFF059669) : const Color(0xFFDC2626),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'FINAL: ${selectedStudent.finalGrade!.toStringAsFixed(2)}%',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isPassed ? const Color(0xFF059669) : const Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. PANEL EVALUATION SECTION
                _buildEvaluatorSectionCard(
                  title: 'Panel Evaluation',
                  weightText: '${panelWeight.toStringAsFixed(0)}% Weight',
                  scoreText: selectedStudent.panelScore != null ? '${selectedStudent.panelScore!.toStringAsFixed(2)}%' : 'Pending',
                  contribText: selectedStudent.panelContrib != null ? '+${selectedStudent.panelContrib!.toStringAsFixed(2)} pts' : null,
                  icon: Icons.gavel_rounded,
                  themeColor: const Color(0xFF2563EB),
                  child: _buildCriteriaBreakdownList(
                    breakdowns: breakdowns,
                    evalType: 'panel',
                    selectedStudentId: selectedStudent.studentId,
                    panelistMap: panelistMap,
                    themeColor: const Color(0xFF2563EB),
                  ),
                ),

                // 2. ADVISER EVALUATION SECTION (if not PIT)
                if (!isPit && adviserWeight > 0) ...[
                  const SizedBox(height: 20),
                  _buildEvaluatorSectionCard(
                    title: 'Adviser Assessment',
                    weightText: '${adviserWeight.toStringAsFixed(0)}% Weight',
                    scoreText: selectedStudent.adviserScore != null ? '${selectedStudent.adviserScore!.toStringAsFixed(2)}%' : 'Pending',
                    contribText: selectedStudent.adviserContrib != null ? '+${selectedStudent.adviserContrib!.toStringAsFixed(2)} pts' : null,
                    icon: Icons.school_rounded,
                    themeColor: const Color(0xFF059669),
                    child: _buildCriteriaBreakdownList(
                      breakdowns: breakdowns,
                      evalType: 'adviser',
                      selectedStudentId: selectedStudent.studentId,
                      panelistMap: panelistMap,
                      themeColor: const Color(0xFF059669),
                    ),
                  ),
                ],

                // 3. PEER EVALUATION SECTION (Full Criteria + All Teammate Ratings)
                const SizedBox(height: 20),
                _buildEvaluatorSectionCard(
                  title: 'Peer Evaluation',
                  weightText: '${peerWeight.toStringAsFixed(0)}% Weight',
                  scoreText: selectedStudent.peerScore != null ? '${selectedStudent.peerScore!.toStringAsFixed(2)}%' : 'Pending',
                  contribText: selectedStudent.peerContrib != null ? '+${selectedStudent.peerContrib!.toStringAsFixed(2)} pts' : null,
                  icon: Icons.groups_rounded,
                  themeColor: const Color(0xFF0284C7),
                  child: _buildPeerStudentDetail(
                    peers: peers,
                    breakdowns: breakdowns,
                    selectedStudentId: selectedStudent.studentId,
                    studentName: selectedStudent.name,
                    students: students,
                    grade: grade,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvaluatorSectionCard({
    required String title,
    required String weightText,
    required String scoreText,
    required String? contribText,
    required IconData icon,
    required Color themeColor,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Top Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 15, color: themeColor),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    weightText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: themeColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  scoreText,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: themeColor,
                  ),
                ),
                if (contribText != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      contribText,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: themeColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildCriteriaBreakdownList({
    required List<Map<String, dynamic>> breakdowns,
    required String evalType,
    required int? selectedStudentId,
    required Map<String, String> panelistMap,
    required Color themeColor,
  }) {
    // Filter breakdown rows for this eval type
    final typeRows = breakdowns.where((b) => b['evaluation_type'] == evalType).toList();
    if (typeRows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No criterion breakdown posted yet.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
      );
    }

    // Group by criterion_name
    final criteriaMap = <String, List<Map<String, dynamic>>>{};
    for (final row in typeRows) {
      final name = (row['criterion_name']?.toString() ?? 'Criterion').trim();
      criteriaMap.putIfAbsent(name, () => []).add(row);
    }

    return Column(
      children: criteriaMap.entries.map((entry) {
        final critName = entry.key;
        final rows = entry.value;
        final isIndividual = rows.any((r) => r['student_id'] != null || r['student'] != null);

        // Filter for rows matching this student (if individual) or all rows (if team)
        final relevantRows = isIndividual
            ? rows.where((r) => asInt(r['student_id'] ?? r['student']) == selectedStudentId).toList()
            : rows;

        final maxScore = asDouble(rows.first['max_score']) ?? 10.0;
        double sum = 0;
        int count = 0;
        for (final r in relevantRows) {
          final s = asDouble(r['score']);
          if (s != null) {
            sum += s;
            count++;
          }
        }
        final avgScore = count > 0 ? (sum / count) : 0.0;
        final pct = maxScore > 0 ? (avgScore / maxScore * 100.0) : 0.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Criterion Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: isIndividual ? const Color(0xFFF5F3FF) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isIndividual ? const Color(0xFFDDD6FE) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Text(
                      isIndividual ? 'INDIVIDUAL' : 'TEAM',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: isIndividual ? const Color(0xFF7C3AED) : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      critName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  Text(
                    '${avgScore.toStringAsFixed(1)} / ${maxScore.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${pct.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: themeColor,
                      ),
                    ),
                  ),
                ],
              ),
              // Progress Bar
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (pct / 100.0).clamp(0.0, 1.0),
                  minHeight: 4.5,
                  backgroundColor: const Color(0xFFF1F5F9),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    pct >= 75 ? const Color(0xFF059669) : const Color(0xFFDC2626),
                  ),
                ),
              ),
              // Evaluator Detail Cards
              if (relevantRows.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...relevantRows.asMap().entries.map((e) {
                  final idx = e.key + 1;
                  final row = e.value;
                  final score = asDouble(row['score']) ?? 0.0;
                  final raw = row['remarks']?.toString() ?? '';
                  final lines = raw.split('\n');
                  final firstLine = lines.first.trim();
                  final rest = lines.sublist(1).join('\n').trim();

                  String evalName = '';
                  if (firstLine.startsWith('Panelist:')) {
                    final key = firstLine.substring('Panelist:'.length).trim();
                    evalName = panelistMap[key] ?? (key.isNotEmpty ? 'Panelist $key' : 'Panelist #$idx');
                  } else if (firstLine.startsWith('Guest panelist:')) {
                    evalName = firstLine.substring('Guest panelist:'.length).trim();
                  } else if (firstLine.isNotEmpty && lines.length == 1 && !firstLine.toLowerCase().startsWith('panelist:')) {
                    evalName = firstLine;
                  }

                  if (evalName.isEmpty) {
                    evalName = row['evaluator_name']?.toString() ??
                        (evalType == 'adviser' ? 'Adviser Analiza Corpuz' : 'Panelist #$idx');
                  }

                  final comment = rest.isNotEmpty
                      ? rest
                      : (raw.isNotEmpty && !raw.startsWith('Panelist:') && !raw.startsWith('Guest panelist:') ? raw : null);

                  return Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              evalType == 'adviser' ? Icons.school_rounded : Icons.person_rounded,
                              size: 13,
                              color: const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              evalName,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF334155),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${score.toStringAsFixed(1)} / ${maxScore.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        if (comment != null && comment.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '💬 "$comment"',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPeerStudentDetail({
    required List<Map<String, dynamic>> peers,
    required List<Map<String, dynamic>> breakdowns,
    required int? selectedStudentId,
    required String studentName,
    required List<_StudentDetailData> students,
    required Map<String, dynamic> grade,
  }) {
    final peerBreakdowns = breakdowns.where((b) => b['evaluation_type'] == 'peer').toList();

    final totalEvaluators = asInt(grade['peer_evaluators_total']) ?? students.length;
    final doneEvaluators = asInt(grade['peer_evaluators_done']) ?? students.length;
    final isComplete = grade['peer_eval_complete'] == true || (totalEvaluators > 0 && doneEvaluators >= totalEvaluators);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Peer Rubric Criteria Breakdown (if peer criteria exist in breakdowns)
        if (peerBreakdowns.isNotEmpty) ...[
          _buildCriteriaBreakdownList(
            breakdowns: breakdowns,
            evalType: 'peer',
            selectedStudentId: selectedStudentId,
            panelistMap: {},
            themeColor: const Color(0xFF0284C7),
          ),
          const SizedBox(height: 14),
        ],

        // 2. Intra-Team Member Ratings Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar
              Row(
                children: [
                  const Icon(Icons.people_outline_rounded, size: 16, color: Color(0xFF0284C7)),
                  const SizedBox(width: 8),
                  const Text(
                    'Intra-Team Peer Contribution Ratings',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isComplete ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isComplete
                            ? const Color(0xFF059669).withValues(alpha: 0.25)
                            : const Color(0xFFD97706).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      isComplete ? '$doneEvaluators / $totalEvaluators Evaluated · Complete' : '$doneEvaluators / $totalEvaluators Evaluated',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: isComplete ? const Color(0xFF059669) : const Color(0xFFD97706),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Teammate rows
              ...students.map((s) {
                final isCurrent = s.studentId == selectedStudentId;
                final pScore = s.peerScore;
                final pPct = pScore != null ? (pScore / 100.0).clamp(0.0, 1.0) : 0.0;
                final initials = s.name
                    .trim()
                    .split(' ')
                    .map((w) => w.isNotEmpty ? w[0] : '')
                    .take(2)
                    .join()
                    .toUpperCase();

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isCurrent ? const Color(0xFFF0F9FF) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isCurrent ? const Color(0xFF0284C7).withValues(alpha: 0.4) : const Color(0xFFE2E8F0),
                      width: isCurrent ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: isCurrent ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
                        child: Text(
                          initials.isEmpty ? 'S' : initials,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: isCurrent ? Colors.white : const Color(0xFF475569),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                s.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                                  color: isCurrent ? const Color(0xFF0F172A) : const Color(0xFF334155),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (s.isLeader) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  'LEADER',
                                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                                ),
                              ),
                            ],
                            if (isCurrent) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  'INSPECTED',
                                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF0284C7)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Mini progress bar
                      Expanded(
                        flex: 2,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: pPct,
                            minHeight: 4,
                            backgroundColor: const Color(0xFFE2E8F0),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              pScore != null && pScore >= 75 ? const Color(0xFF059669) : const Color(0xFF0284C7),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        pScore != null ? '${pScore.toStringAsFixed(1)}%' : 'Pending',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: pScore != null ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadgeCell(bool isPassed, double? finalGrade) {
    if (finalGrade == null) return const Text('—', style: TextStyle(color: Color(0xFF94A3B8)));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: isPassed ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isPassed
              ? const Color(0xFF059669).withValues(alpha: 0.25)
              : const Color(0xFFDC2626).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPassed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 12,
            color: isPassed ? const Color(0xFF059669) : const Color(0xFFDC2626),
          ),
          const SizedBox(width: 4),
          Text(
            isPassed ? 'PASSED' : 'FAILED',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isPassed ? const Color(0xFF059669) : const Color(0xFFDC2626),
            ),
          ),
        ],
      ),
    );
  }

  List<_PanelistColumnDef> _extractPanelists(
    Map<String, dynamic> grade,
    List<Map<String, dynamic>> breakdowns,
    Map<String, String> panelistMap,
  ) {
    final result = <_PanelistColumnDef>[];
    final seenKeys = <String>{};

    final panelistList = grade['panelists'] is List ? (grade['panelists'] as List) : [];
    for (final p in panelistList) {
      if (p is Map) {
        final u = p['username']?.toString().trim() ?? '';
        final n = p['name']?.toString().trim() ?? '';
        if (u.isNotEmpty && !seenKeys.contains(u)) {
          seenKeys.add(u);
          result.add(_PanelistColumnDef(key: u, displayName: n.isNotEmpty ? n : u));
        }
      }
    }

    for (final b in breakdowns) {
      if (b['evaluation_type'] != 'panel') continue;
      final raw = b['remarks']?.toString() ?? '';
      final firstLine = raw.split('\n').first.trim();
      if (firstLine.startsWith('Panelist:')) {
        final key = firstLine.substring('Panelist:'.length).trim();
        if (key.isNotEmpty && !seenKeys.contains(key)) {
          seenKeys.add(key);
          final name = panelistMap[key] ?? 'Panelist $key';
          result.add(_PanelistColumnDef(key: key, displayName: name));
        }
      } else if (firstLine.startsWith('Guest panelist:')) {
        final key = firstLine.substring('Guest panelist:'.length).trim();
        if (key.isNotEmpty && !seenKeys.contains(key)) {
          seenKeys.add(key);
          result.add(_PanelistColumnDef(key: key, displayName: key));
        }
      }
    }

    return result;
  }

  double? _getPanelistScoreForStudent({
    required List<Map<String, dynamic>> breakdowns,
    required String panelistKey,
    required int? studentId,
  }) {
    final rows = breakdowns.where((b) {
      if (b['evaluation_type'] != 'panel') return false;

      final raw = b['remarks']?.toString() ?? '';
      final firstLine = raw.split('\n').first.trim();
      bool isMatch = false;
      if (firstLine.startsWith('Panelist:')) {
        final key = firstLine.substring('Panelist:'.length).trim();
        isMatch = key == panelistKey;
      } else if (firstLine.startsWith('Guest panelist:')) {
        final key = firstLine.substring('Guest panelist:'.length).trim();
        isMatch = key == panelistKey;
      }

      if (!isMatch) return false;

      final bSid = asInt(b['student_id'] ?? b['student']);
      if (bSid != null && studentId != null) {
        return bSid == studentId;
      }
      return true;
    }).toList();

    if (rows.isEmpty) return null;

    double totalScore = 0;
    double totalMax = 0;
    for (final r in rows) {
      final s = asDouble(r['score']);
      final m = asDouble(r['max_score']) ?? 10.0;
      if (s != null && m > 0) {
        totalScore += s;
        totalMax += m;
      }
    }

    if (totalMax <= 0) return null;
    return (totalScore / totalMax * 100.0).clamp(0.0, 100.0);
  }

  Widget _detailHeader({
    required String title,
    required String subtitle,
    required VoidCallback onBack,
  }) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: DefensysUi.pageTitle),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: DefensysUi.subtitle),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelistColumnDef {
  final String key;
  final String displayName;

  const _PanelistColumnDef({required this.key, required this.displayName});
}

class _StudentDetailData {
  final int? studentId;
  final String name;
  final bool isLeader;
  final Map<String, double?> panelistScores;
  final double? panelScore;
  final double? panelContrib;
  final double? adviserScore;
  final double? adviserContrib;
  final double? peerScore;
  final double? peerContrib;
  final double? finalGrade;

  const _StudentDetailData({
    this.studentId,
    required this.name,
    this.isLeader = false,
    this.panelistScores = const {},
    this.panelScore,
    this.panelContrib,
    this.adviserScore,
    this.adviserContrib,
    this.peerScore,
    this.peerContrib,
    this.finalGrade,
  });
}
