import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../models/defense_workflow_labels.dart';
import '../../../widgets/shadcn/defensys_shadcn_scope.dart';
import 'widgets/panelist_segmented_tabs.dart';

import '../../../theme/defensys_tokens.dart';

class OverallResultsTab extends StatefulWidget {
  final List<Map<String, dynamic>> results;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onOpenGradeSheet;
  final bool showStageFilters;
  final bool initiallyExpanded;
  final String emptyMessage;

  const OverallResultsTab({
    super.key,
    required this.results,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onRefresh,
    this.onOpenGradeSheet,
    this.showStageFilters = true,
    this.initiallyExpanded = true,
    this.emptyMessage = 'No graded teams yet.',
  });

  @override
  State<OverallResultsTab> createState() => _OverallResultsTabState();
}

class _OverallResultsTabState extends State<OverallResultsTab> {
  final Set<String> _expandedCards = {};
  bool _initialExpansionApplied = false;
  String _selectedStage = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _resultKey(Map<String, dynamic> result) =>
      '${result['schedule_id'] ?? result['grade_id'] ?? result['teamName']}|${result['stage']}|${result['scope']}';

  void _toggleExpand(String index) {
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
      return const Center(
        child: CircularProgressIndicator(color: DefensysTokens.maroon),
      );
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
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: DefensysTokens.danger,
                ),
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
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 64, 28, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: DefensysTokens.maroonOf(
                        context,
                      ).withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.bar_chart_rounded,
                      size: 26,
                      color: DefensysTokens.maroonTextOf(context),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.emptyMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: DefensysTokens.textPrimaryOf(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Submitted evaluations for this session will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: DefensysTokens.textSecondaryOf(context),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  if (widget.onOpenGradeSheet != null) ...[
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: widget.onOpenGradeSheet,
                      icon: const Icon(Icons.rate_review_outlined, size: 18),
                      label: const Text('Open grade sheet'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    final filtered = _getFilteredResults();
    if (!widget.showStageFilters) {
      filtered.sort(
        (a, b) => ((b['percentage'] as num?) ?? 0).compareTo(
          (a['percentage'] as num?) ?? 0,
        ),
      );
    }
    if (!_initialExpansionApplied && filtered.isNotEmpty) {
      if (widget.initiallyExpanded) {
        _expandedCards.add(_resultKey(filtered.first));
      }
      _initialExpansionApplied = true;
    }
    final uniqueStages = _getUniqueStages();

    final listContent = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        // ── Executive KPI Summary Strip ──
        _buildKpiSummary(filtered),

        const SizedBox(height: 14),

        // ── Multi-Stage Filter Chips (if multiple stages exist) ──
        if (widget.showStageFilters && uniqueStages.length > 1) ...[
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
            final key = _resultKey(result);
            final isExpanded = _expandedCards.contains(key);
            return _teamCard(key, rank, result, isExpanded);
          }),
      ],
    );

    if (widget.onRefresh == null) {
      return DefensysShadcnScope(child: listContent);
    }
    return DefensysShadcnScope(
      child: RefreshIndicator(
        color: DefensysTokens.maroon,
        onRefresh: widget.onRefresh!,
        child: listContent,
      ),
    );
  }

  // ── Executive KPI Summary Strip ──
  Widget _buildKpiSummary(List<Map<String, dynamic>> teams) {
    final total = teams.length;
    final avgScore = total > 0
        ? (teams.fold<double>(
                0.0,
                (sum, r) =>
                    sum + ((r['percentage'] as num?)?.toDouble() ?? 0.0),
              ) /
              total)
        : 0.0;
    final topScore = teams.isNotEmpty
        ? teams
              .map((r) => (r['percentage'] as num?)?.toDouble() ?? 0.0)
              .reduce((a, b) => a > b ? a : b)
        : 0.0;

    return ShadCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: _buildMetricTile(
              label: 'Panel average',
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
              label: 'Evaluated teams',
              value: '$total',
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
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: DefensysTokens.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
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
    return PanelistSegmentedTabs<String>(
      key: const ValueKey('results-stage-tabs'),
      value: _selectedStage,
      scrollable: true,
      secondary: true,
      onChanged: (value) => setState(() => _selectedStage = value),
      segments: [
        PanelistSegment(
          value: 'all',
          label: 'All Stages',
          icon: Icons.layers_outlined,
          count: '${widget.results.length}',
        ),
        for (final stage in stages)
          PanelistSegment(
            value: stage,
            label: stage,
            icon: Icons.school_outlined,
            count:
                '${widget.results.where((r) => (r['stage'] ?? '') == stage).length}',
          ),
      ],
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
          hintStyle: const TextStyle(
            fontSize: 12,
            color: DefensysTokens.steelGrey,
          ),
          prefixIcon: const Icon(
            Icons.search,
            size: 18,
            color: DefensysTokens.steelGrey,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.clear,
                    size: 16,
                    color: DefensysTokens.steelGrey,
                  ),
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
  Widget _teamCard(
    String index,
    int rank,
    Map<String, dynamic> result,
    bool isExpanded,
  ) {
    final pct = (result['percentage'] as num?)?.toDouble() ?? 0;
    final total = (result['total'] as num?)?.toDouble() ?? 0;
    final max = (result['max'] as num?)?.toDouble() ?? 0;
    final teamStatus = result['teamStatus'] as String? ?? 'Pending';
    final level = (result['level'] as String? ?? '').trim();
    final stage = (result['stage'] as String? ?? '').trim();
    final criteria = result['criteria'] as List? ?? [];

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

    final isApproved = teamStatus == 'Approved';
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
    final isForRedefense = [
      'for_redefense',
      'failed',
      'project_rejected',
    ].contains(verdict);
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
                        style: const TextStyle(
                          fontSize: 12,
                          color: DefensysTokens.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (level.isNotEmpty)
                            _buildMiniBadge(
                              level,
                              Colors.grey.shade100,
                              DefensysTokens.steelGrey,
                            ),
                          if (stage.isNotEmpty)
                            _buildMiniBadge(
                              stage,
                              DefensysTokens.maroon.withValues(alpha: 0.08),
                              DefensysTokens.maroon,
                            ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2.5,
                      ),
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
                            'VERDICT: ${defenseVerdictLabel(verdict).toUpperCase()} (Attempt #$attemptCount)',
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
                        style: const TextStyle(
                          fontSize: 10,
                          color: DefensysTokens.steelGrey,
                        ),
                      ),
                    ],
                    if (verdictRemarks.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Directives: $verdictRemarks',
                        style: const TextStyle(
                          fontSize: 11,
                          color: DefensysTokens.textDark,
                        ),
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
                border: Border.all(
                  color: DefensysTokens.maroon.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Text(
                        'Your panel evaluation',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: DefensysTokens.textPrimary,
                        ),
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
                        pct >= 75
                            ? DefensysTokens.success
                            : pct >= 60
                            ? DefensysTokens.gold
                            : DefensysTokens.danger,
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
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
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
                                  backgroundColor: DefensysTokens.maroon
                                      .withValues(alpha: 0.1),
                                  child: Text(
                                    studentName.isNotEmpty
                                        ? studentName[0].toUpperCase()
                                        : '?',
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
                            ...studentCriteriaList.map(
                              (c) => _buildCriteriaBar(c),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 10),
                  ],

                  // Fallback: If no student names were captured and no shared split
                  if (sharedCriteria.isEmpty &&
                      memberCriteriaByStudent.isEmpty &&
                      criteria.isNotEmpty) ...[
                    _subSectionLabel('Criteria Breakdown'),
                    const SizedBox(height: 6),
                    ...criteria.map(
                      (c) => _buildCriteriaBar(Map<String, dynamic>.from(c)),
                    ),
                    const SizedBox(height: 12),
                  ],
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
