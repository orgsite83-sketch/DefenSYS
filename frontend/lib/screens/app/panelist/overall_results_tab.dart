import 'package:flutter/material.dart';

import '../../../theme/defensys_tokens.dart';

class OverallResultsTab extends StatefulWidget {
  final List<Map<String, dynamic>> results;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;

  const OverallResultsTab({
    super.key,
    required this.results,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onRefresh,
  });

  @override
  State<OverallResultsTab> createState() => _OverallResultsTabState();
}

class _OverallResultsTabState extends State<OverallResultsTab> {
  final Set<int> _expandedCards = {0};
  String _selectedStage = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleExpand(int index) {
    setState(() {
      if (_expandedCards.contains(index)) {
        _expandedCards.remove(index);
      } else {
        _expandedCards.add(index);
      }
    });
  }

  List<Map<String, dynamic>> _getFilteredResults() {
    return widget.results.where((r) {
      if (_selectedStage != 'all') {
        final stage = (r['stage'] ?? '').toString().trim();
        if (stage != _selectedStage) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final name = (r['teamName'] ?? '').toString().toLowerCase();
        final proj = (r['projectTitle'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !proj.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  Set<String> _getUniqueStages() {
    final stages = <String>{};
    for (final r in widget.results) {
      final s = (r['stage'] ?? '').toString().trim();
      if (s.isNotEmpty) stages.add(s);
    }
    return stages;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator(color: DefensysTokens.maroon));
    }

    Widget refreshWrapper(Widget child) {
      if (widget.onRefresh == null) return child;
      return LayoutBuilder(
        builder: (context, constraints) {
          return RefreshIndicator(
            color: DefensysTokens.maroon,
            onRefresh: widget.onRefresh!,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: child,
              ),
            ),
          );
        },
      );
    }

    if (widget.error != null && widget.results.isEmpty) {
      return refreshWrapper(
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: DefensysTokens.danger),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load results',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: DefensysTokens.textSecondary),
                ),
                if (widget.onRetry != null) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: widget.onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DefensysTokens.maroon,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (widget.results.isEmpty) {
      return refreshWrapper(
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bar_chart, size: 52, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              const Text('No graded teams yet.',
                  style: TextStyle(color: DefensysTokens.textSecondary, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text('Post grades to see evaluated scores and rankings here.',
                  style: TextStyle(color: DefensysTokens.steelGrey, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final filtered = _getFilteredResults();
    final uniqueStages = _getUniqueStages();

    final listContent = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        // ── Executive KPI Summary Strip ──
        _buildKpiSummary(filtered),

        const SizedBox(height: 14),

        // ── Multi-Stage Filter Chips (if multiple stages exist) ──
        if (uniqueStages.length > 1) ...[
          _buildStageFilterChips(uniqueStages),
          const SizedBox(height: 12),
        ],

        // ── Search field if teams >= 3 ──
        if (widget.results.length >= 3) ...[
          _buildSearchField(),
          const SizedBox(height: 14),
        ],

        // ── Team Cards ──
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'No teams match the filter.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ),
          )
        else
          ...filtered.asMap().entries.map((e) {
            final rank = e.key + 1;
            final result = e.value;
            final isExpanded = _expandedCards.contains(e.key);
            return _teamCard(e.key, rank, result, isExpanded);
          }),
      ],
    );

    if (widget.onRefresh == null) return listContent;
    return RefreshIndicator(
      color: DefensysTokens.maroon,
      onRefresh: widget.onRefresh!,
      child: listContent,
    );
  }

  // ── Executive KPI Summary Strip ──
  Widget _buildKpiSummary(List<Map<String, dynamic>> teams) {
    final total = teams.length;
    final avgScore = total > 0
        ? (teams.fold<double>(0.0, (sum, r) => sum + ((r['percentage'] as num?)?.toDouble() ?? 0.0)) / total)
        : 0.0;
    final topScore = teams.isNotEmpty
        ? teams.map((r) => (r['percentage'] as num?)?.toDouble() ?? 0.0).reduce((a, b) => a > b ? a : b)
        : 0.0;
    final passedCount = teams.where((r) {
      final st = (r['teamStatus'] ?? '').toString();
      final pct = (r['percentage'] as num?)?.toDouble() ?? 0.0;
      return st == 'Approved' || pct >= 75.0;
    }).length;
    final passRate = total > 0 ? (passedCount / total * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DefensysTokens.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildMetricTile(
              label: 'Class Avg',
              value: '${avgScore.toStringAsFixed(1)}%',
              icon: Icons.query_stats_rounded,
              iconColor: DefensysTokens.maroon,
              iconBg: DefensysTokens.maroon.withValues(alpha: 0.08),
            ),
          ),
          Container(width: 1, height: 36, color: DefensysTokens.border),
          Expanded(
            child: _buildMetricTile(
              label: 'Top Score',
              value: '${topScore.toStringAsFixed(1)}%',
              icon: Icons.emoji_events_rounded,
              iconColor: DefensysTokens.gold,
              iconBg: const Color(0xFFFEF3C7),
            ),
          ),
          Container(width: 1, height: 36, color: DefensysTokens.border),
          Expanded(
            child: _buildMetricTile(
              label: 'Pass Rate',
              value: '${passRate.toStringAsFixed(0)}%',
              icon: Icons.check_circle_rounded,
              iconColor: DefensysTokens.success,
              iconBg: DefensysTokens.successBg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, size: 14, color: iconColor),
            ),
            const SizedBox(width: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: DefensysTokens.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: DefensysTokens.steelGrey,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ── Stage Filter Chips ──
  Widget _buildStageFilterChips(Set<String> stages) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildStageChip('all', 'All Stages (${widget.results.length})'),
          const SizedBox(width: 8),
          ...stages.map((st) {
            final count = widget.results.where((r) => (r['stage'] ?? '') == st).length;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildStageChip(st, '$st ($count)'),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStageChip(String key, String label) {
    final isSelected = _selectedStage == key;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _selectedStage = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? DefensysTokens.maroon : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? DefensysTokens.maroon : DefensysTokens.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : DefensysTokens.steelGrey,
          ),
        ),
      ),
    );
  }

  // ── Search Field ──
  Widget _buildSearchField() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DefensysTokens.border),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search team or project title...',
          hintStyle: const TextStyle(fontSize: 12, color: DefensysTokens.steelGrey),
          prefixIcon: const Icon(Icons.search, size: 18, color: DefensysTokens.steelGrey),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16, color: DefensysTokens.steelGrey),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
      ),
    );
  }

  // ── Team Card ──
  Widget _teamCard(int index, int rank, Map<String, dynamic> result, bool isExpanded) {
    final pct = (result['percentage'] as num?)?.toDouble() ?? 0;
    final total = (result['total'] as num?)?.toDouble() ?? 0;
    final max = (result['max'] as num?)?.toDouble() ?? 0;
    final teamStatus = result['teamStatus'] as String? ?? 'Pending';
    final level = (result['level'] as String? ?? '').trim();
    final stage = (result['stage'] as String? ?? '').trim();
    final criteria = result['criteria'] as List? ?? [];
    final memberGrades = result['memberGrades'] as List? ?? [];
    final weights = result['weights'] as Map<String, dynamic>? ?? {};
    final panelW = (weights['panel'] as num?)?.toInt() ?? 80;
    final peerW = (weights['peer'] as num?)?.toInt() ?? 20;

    // Podium colors
    final isFirst = rank == 1;
    final isSecond = rank == 2;
    final isThird = rank == 3;

    final rankColor = isFirst
        ? const Color(0xFFD97706)
        : isSecond
            ? const Color(0xFF475569)
            : isThird
                ? const Color(0xFFC2410C)
                : DefensysTokens.maroon;

    final rankBg = isFirst
        ? const Color(0xFFFEF3C7)
        : isSecond
            ? const Color(0xFFF1F5F9)
            : isThird
                ? const Color(0xFFFFEDD5)
                : const Color(0xFFF8FAFC);

    final rankBorder = isFirst
        ? const Color(0xFFF59E0B)
        : isSecond
            ? const Color(0xFFCBD5E1)
            : isThird
                ? const Color(0xFFFB923C)
                : DefensysTokens.border;

    final isApproved = teamStatus == 'Approved' || pct >= 75.0;
    final isFailed = teamStatus == 'Failed';
    final statusColor = isApproved
        ? DefensysTokens.successText
        : isFailed
            ? DefensysTokens.dangerText
            : DefensysTokens.warningText;
    final statusBg = isApproved
        ? DefensysTokens.successBg
        : isFailed
            ? DefensysTokens.dangerBg
            : DefensysTokens.warningBg;
    final statusBorderColor = isApproved
        ? DefensysTokens.successBorder
        : isFailed
            ? DefensysTokens.dangerBorder
            : DefensysTokens.warningBorder;
    final statusLabel = isApproved
        ? 'Passed'
        : isFailed
            ? 'Failed'
            : 'Pending';

    final verdict = result['verdict']?.toString() ?? '';
    final verdictRemarks = result['verdict_remarks']?.toString() ?? '';
    final verdictByName = result['verdict_by_name']?.toString() ?? '';
    final attemptCount = result['attempt_count'] ?? 1;
    final hasVerdict = verdict.isNotEmpty;
    final isForRedefense = verdict == 'for_redefense';
    final isRevisions = verdict == 'approved_with_revisions';

    // Separate shared vs member criteria
    final sharedCriteria = <Map<String, dynamic>>[];
    final memberCriteriaByStudent = <String, List<Map<String, dynamic>>>{};

    for (final raw in criteria) {
      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        final studentName = map['student_name']?.toString();
        if (studentName != null && studentName.isNotEmpty) {
          memberCriteriaByStudent.putIfAbsent(studentName, () => []).add(map);
        } else {
          sharedCriteria.add(map);
        }
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1,
      color: Colors.white,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isFirst ? const Color(0xFFFDE68A) : DefensysTokens.border,
          width: isFirst ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rank Podium Circle
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: rankBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: rankBorder, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: rankColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Team Title & Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result['teamName'] ?? '—',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: DefensysTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result['projectTitle'] ?? '—',
                        style: const TextStyle(fontSize: 12, color: DefensysTokens.textSecondary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (level.isNotEmpty)
                            _buildMiniBadge(level, Colors.grey.shade100, DefensysTokens.steelGrey),
                          if (stage.isNotEmpty)
                            _buildMiniBadge(stage, DefensysTokens.maroon.withValues(alpha: 0.08), DefensysTokens.maroon),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Score Hero & Status Pill
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${pct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: rankColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusBorderColor),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Official Verdict Banner (if available) ──
          if (hasVerdict) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isForRedefense
                      ? DefensysTokens.dangerBg
                      : isRevisions
                          ? DefensysTokens.revisionBg
                          : DefensysTokens.successBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isForRedefense
                        ? DefensysTokens.dangerBorder
                        : isRevisions
                            ? DefensysTokens.revisionBorder
                            : DefensysTokens.successBorder,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isForRedefense
                              ? Icons.replay_rounded
                              : isRevisions
                                  ? Icons.edit_calendar
                                  : Icons.check_circle,
                          size: 15,
                          color: isForRedefense
                              ? DefensysTokens.dangerText
                              : isRevisions
                                  ? DefensysTokens.revisionText
                                  : DefensysTokens.successText,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isForRedefense
                                ? 'VERDICT: FOR RE-DEFENSE (Attempt #$attemptCount)'
                                : isRevisions
                                    ? 'VERDICT: APPROVED WITH REVISIONS'
                                    : 'VERDICT: APPROVED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isForRedefense
                                  ? DefensysTokens.dangerText
                                  : isRevisions
                                      ? DefensysTokens.revisionText
                                      : DefensysTokens.successText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (verdictByName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Rendered by Chair: $verdictByName',
                        style: const TextStyle(fontSize: 10, color: DefensysTokens.steelGrey),
                      ),
                    ],
                    if (verdictRemarks.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Directives: $verdictRemarks',
                        style: const TextStyle(fontSize: 11, color: DefensysTokens.textDark),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          // ── Panel Score Bar ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: DefensysTokens.maroon.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DefensysTokens.maroon.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Panel Score ($panelW%)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DefensysTokens.textPrimary),
                      ),
                      Text(
                        '${total.toStringAsFixed(1)} / ${max.toStringAsFixed(0)} pts',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: DefensysTokens.maroon,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (pct / 100).clamp(0.0, 1.0),
                      minHeight: 7,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        pct >= 75 ? DefensysTokens.success : pct >= 60 ? DefensysTokens.gold : DefensysTokens.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ── Progressive Disclosure Toggle Button ──
          InkWell(
            onTap: () => _toggleExpand(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade100)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    size: 15,
                    color: DefensysTokens.steelGrey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isExpanded
                          ? 'Hide Detailed Breakdown'
                          : 'View Criteria & Member Breakdown (${criteria.length} items)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.maroon,
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: DefensysTokens.maroon,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),

          // ── Collapsible Content ──
          if (isExpanded) ...[
            Container(
              color: const Color(0xFFFAFAFA),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Shared Team Criteria
                  if (sharedCriteria.isNotEmpty) ...[
                    _subSectionLabel('Shared Team Criteria'),
                    const SizedBox(height: 6),
                    ...sharedCriteria.map((c) => _buildCriteriaBar(c)),
                    const SizedBox(height: 12),
                  ],

                  // 2. Individual Member Criteria (Grouped by Student!)
                  if (memberCriteriaByStudent.isNotEmpty) ...[
                    _subSectionLabel('Individual Member Criteria'),
                    const SizedBox(height: 8),
                    ...memberCriteriaByStudent.entries.map((entry) {
                      final studentName = entry.key;
                      final studentCriteriaList = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: DefensysTokens.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 10,
                                  backgroundColor: DefensysTokens.maroon.withValues(alpha: 0.1),
                                  child: Text(
                                    studentName.isNotEmpty ? studentName[0].toUpperCase() : '?',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: DefensysTokens.maroon,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    studentName,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: DefensysTokens.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ...studentCriteriaList.map((c) => _buildCriteriaBar(c)),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 10),
                  ],

                  // Fallback: If no student names were captured and no shared split
                  if (sharedCriteria.isEmpty && memberCriteriaByStudent.isEmpty && criteria.isNotEmpty) ...[
                    _subSectionLabel('Criteria Breakdown'),
                    const SizedBox(height: 6),
                    ...criteria.map((c) => _buildCriteriaBar(Map<String, dynamic>.from(c))),
                    const SizedBox(height: 12),
                  ],

                  // 3. Member Final Grades Table
                  if (memberGrades.isNotEmpty) ...[
                    _subSectionLabel('Individual Final Grades'),
                    const SizedBox(height: 8),
                    _buildMemberGradesTable(memberGrades, panelW, peerW),
                  ],

                  const SizedBox(height: 10),

                  // 4. Formula Footnote
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 12, color: Colors.grey.shade500),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Formula: Panel ($panelW%) + Peer ($peerW%) = Final Grade  ·  Pass ≥ 75',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniBadge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _buildCriteriaBar(Map<String, dynamic> c) {
    final cName = c['criteriaName'] ?? '';
    final cScore = (c['score'] as num?)?.toDouble() ?? 0;
    final cMax = (c['max'] as num?)?.toDouble() ?? 1;
    final cPct = cMax > 0 ? cScore / cMax : 0.0;
    final color = cPct >= 0.85
        ? DefensysTokens.success
        : cPct >= 0.65
            ? DefensysTokens.gold
            : DefensysTokens.danger;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              cName,
              style: const TextStyle(fontSize: 11, color: Color(0xFF374151)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: cPct.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${cScore.toStringAsFixed(0)}/${cMax.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.maroon,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberGradesTable(List memberGrades, int panelW, int peerW) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DefensysTokens.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text('Member',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: DefensysTokens.steelGrey)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Panel ($panelW%)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: DefensysTokens.steelGrey)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Peer ($peerW%)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: DefensysTokens.steelGrey)),
                ),
                const Expanded(
                  flex: 2,
                  child: Text('Final',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: DefensysTokens.steelGrey)),
                ),
              ],
            ),
          ),
          ...memberGrades.map((m) {
            final name = m['name'] ?? '';
            final isLeader = m['isLeader'] == true;
            final panelContrib = (m['panelContrib'] as num?)?.toDouble();
            final peerScore = m['peerScore'];
            final peerMax = m['peerMax'];
            final finalGrade = m['finalGrade'];
            final hasFinish = finalGrade != null;
            final fg = hasFinish ? (finalGrade as num).toDouble() : 0.0;
            final finalColor = hasFinish
                ? (fg >= 75 ? DefensysTokens.success : DefensysTokens.danger)
                : DefensysTokens.steelGrey;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade100, width: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: isLeader ? DefensysTokens.maroon : const Color(0xFFE2E8F0),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: isLeader ? Colors.white : DefensysTokens.steelGrey,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (isLeader)
                                Container(
                                  margin: const EdgeInsets.only(top: 1),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('Leader',
                                      style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w700, color: Color(0xFF92400E))),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      panelContrib != null ? panelContrib.toStringAsFixed(1) : '—',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      peerScore != null
                          ? '${(peerScore as num).toStringAsFixed(1)}/${(peerMax as num).toStringAsFixed(0)}'
                          : '—',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: peerScore != null ? Colors.grey.shade700 : Colors.grey.shade400,
                        fontStyle: peerScore != null ? FontStyle.normal : FontStyle.italic,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: hasFinish ? finalColor.withValues(alpha: 0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        hasFinish ? fg.toStringAsFixed(1) : '—',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: finalColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _subSectionLabel(String text) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: DefensysTokens.maroon,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: DefensysTokens.steelGrey,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
