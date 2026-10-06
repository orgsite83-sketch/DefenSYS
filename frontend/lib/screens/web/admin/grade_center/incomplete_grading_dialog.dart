import 'package:flutter/material.dart';

import '../../../../theme/defensys_tokens.dart';

/// Read-only grading blockers, with a fixed header and footer around the list.
class IncompleteGradingTeamsDialog extends StatefulWidget {
  const IncompleteGradingTeamsDialog({
    super.key,
    required this.teams,
    this.stageLabel,
    this.isPit = false,
    this.canComplete = false,
  });

  final List<Map<String, dynamic>> teams;
  final String? stageLabel;
  final bool isPit;
  final bool canComplete;

  @override
  State<IncompleteGradingTeamsDialog> createState() =>
      _IncompleteGradingTeamsDialogState();
}

class _IncompleteGradingTeamsDialogState
    extends State<IncompleteGradingTeamsDialog> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String _query = '';
  int _selectedTab = 0;

  static const _components = {
    'panel': 'Panel',
    'adviser': 'Adviser',
    'peer': 'Peer',
    'verdict': 'Chair verdict',
    'clearance': 'Revision clearance',
    'redefense': 'Re-defense required',
    'post_defense': 'Post-defense deliverables',
  };

  @override
  void initState() {
    super.initState();
    final hasEvalMissing = widget.teams.any((team) {
      final m = _missing(team);
      return m.any((k) => ['panel', 'adviser', 'peer', 'verdict'].contains(k));
    });
    final hasDeliverablesMissing = widget.teams.any((team) {
      final m = _missing(team);
      return m.any((k) => ['post_defense', 'clearance', 'redefense'].contains(k));
    });
    if (!hasEvalMissing && hasDeliverablesMissing) {
      _selectedTab = 1;
    }
  }

  int get _evaluatorBlockersCount => widget.teams.where((team) {
        final m = _missing(team);
        return m.any((k) => ['panel', 'adviser', 'peer', 'verdict'].contains(k));
      }).length;

  int get _clearanceBlockersCount => widget.teams.where((team) {
        final m = _missing(team);
        return m.any((k) => ['post_defense', 'clearance', 'redefense'].contains(k));
      }).length;

  String _teamName(Map<String, dynamic> team) =>
      team['team_name']?.toString() ?? 'Team';

  Set<String> _missing(Map<String, dynamic> team) {
    final components = team['missing_components'];
    if (components is List) {
      return components.map((value) => value.toString()).toSet();
    }
    final missing = {
      for (final component in _components.keys)
        if (team['${component}_complete'] == false) component,
    };
    return missing.isEmpty ? {'grading'} : missing;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 640;
    final availableHeight =
        size.height - MediaQuery.viewInsetsOf(context).vertical;
    final short = availableHeight < 540;
    final padding = short ? 16.0 : (compact ? 20.0 : 24.0);
    final visibleTeams = widget.teams
        .where((team) => _teamName(team).toLowerCase().contains(_query))
        .toList();
    final warningColor = DefensysTokens.goldOf(context);
    final successColor = const Color(0xFF16A34A);
    final borderColor = DefensysTokens.borderOf(context);
    final textColor = DefensysTokens.textPrimaryOf(context);
    final mutedColor = DefensysTokens.textSecondaryOf(context);
    final dark = DefensysTokens.isDark(context);
    final isReady = widget.canComplete;

    return Dialog(
      backgroundColor: DefensysTokens.surfaceOf(context),
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.all(compact ? 16 : 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusXl),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 760,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (availableHeight - (compact ? 32 : 48))
                .clamp(0.0, 720.0)
                .toDouble(),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  padding,
                  short ? 12 : padding,
                  padding,
                  short ? 8 : 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isReady
                                ? (dark
                                    ? successColor.withValues(alpha: 0.20)
                                    : const Color(0xFFECFDF5))
                                : warningColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isReady
                                ? Icons.verified_rounded
                                : Icons.fact_check_outlined,
                            color: isReady ? successColor : warningColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isReady
                                ? (widget.stageLabel != null
                                    ? 'Mark ${widget.stageLabel} Complete?'
                                    : 'Ready to mark complete')
                                : 'Grading not ready',
                            style: DefensysTokens.dialogTitle.copyWith(
                              color: textColor,
                              fontSize: compact ? 18 : 20,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(false),
                          icon: Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: mutedColor,
                          ),
                        ),
                      ],
                    ),
                    if (!short) ...[
                      const SizedBox(height: 12),
                      Text(
                        isReady
                            ? 'All required evaluations, verdicts, and deliverables are complete. '
                                'Review team readiness below before marking officially complete.'
                            : 'Complete the missing evaluations, verdicts, or clearance below before marking '
                                'the stage or event officially complete.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: mutedColor,
                        ),
                      ),
                    ],
                    SizedBox(height: short ? 8 : 16),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: short ? 8 : 12,
                      ),
                      decoration: BoxDecoration(
                        color: isReady
                            ? (dark
                                ? const Color(0xFF064E3B).withValues(alpha: 0.25)
                                : const Color(0xFFECFDF5))
                            : DefensysTokens.surfaceHigherOf(context),
                        borderRadius: BorderRadius.circular(
                          DefensysTokens.radiusMd,
                        ),
                        border: Border.all(
                          color: isReady
                              ? (dark
                                  ? const Color(0xFF064E3B)
                                  : const Color(0xFFA7F3D0))
                              : borderColor,
                        ),
                      ),
                      child: isReady
                          ? Row(
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 20,
                                  color: dark
                                      ? const Color(0xFF34D399)
                                      : const Color(0xFF16A34A),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'All ${widget.teams.length} teams are ready',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: dark
                                              ? const Color(0xFF34D399)
                                              : const Color(0xFF047857),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'All evaluator grades, defense verdicts, and post-defense deliverables have been verified.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: dark
                                              ? const Color(0xFFA7F3D0)
                                              : const Color(0xFF065F46),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${widget.teams.length} '
                                  '${widget.teams.length == 1 ? 'team needs' : 'teams need'} attention',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 20,
                                  runSpacing: 6,
                                  children: [
                                    for (final entry in _components.entries)
                                      if (widget.teams.any(
                                        (team) => _missing(team).contains(entry.key),
                                      ))
                                        Text(
                                          '${entry.value}: ${widget.teams.where((team) => _missing(team).contains(entry.key)).length} missing',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: entry.key == 'redefense'
                                                ? DefensysTokens.dangerText
                                                : entry.key == 'clearance'
                                                    ? DefensysTokens.warningText
                                                    : mutedColor,
                                            fontWeight: ['redefense', 'clearance'].contains(entry.key) ? FontWeight.w700 : FontWeight.normal,
                                          ),
                                        ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                    SizedBox(height: short ? 6 : 14),
                    // Two-tab selector
                    Container(
                      decoration: BoxDecoration(
                        color: DefensysTokens.surfaceHigherOf(context),
                        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                        border: Border.all(color: borderColor),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        children: [
                          Expanded(
                            child: _tabButton(
                              key: const ValueKey('tab-evaluator-grades'),
                              label: 'Evaluator Grades',
                              icon: Icons.rate_review_outlined,
                              pendingCount: _evaluatorBlockersCount,
                              isSelected: _selectedTab == 0,
                              onTap: () {
                                if (_selectedTab != 0) {
                                  setState(() => _selectedTab = 0);
                                  if (_scrollController.hasClients) {
                                    _scrollController.jumpTo(0);
                                  }
                                }
                              },
                              compact: compact,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _tabButton(
                              key: const ValueKey('tab-deliverables-clearance'),
                              label: 'Deliverables & Clearance',
                              icon: Icons.task_outlined,
                              pendingCount: _clearanceBlockersCount,
                              isSelected: _selectedTab == 1,
                              onTap: () {
                                if (_selectedTab != 1) {
                                  setState(() => _selectedTab = 1);
                                  if (_scrollController.hasClients) {
                                    _scrollController.jumpTo(0);
                                  }
                                }
                              },
                              compact: compact,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: short ? 6 : 14),
                    TextField(
                      controller: _searchController,
                      style: TextStyle(fontSize: 13, color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Search teams',
                        hintStyle: TextStyle(fontSize: 13, color: mutedColor),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: mutedColor,
                        ),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            DefensysTokens.radiusMd,
                          ),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            DefensysTokens.radiusMd,
                          ),
                          borderSide: BorderSide(
                            color: DefensysTokens.maroonOf(context),
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() => _query = value.trim().toLowerCase());
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(0);
                        }
                      },
                    ),
                  ],
                ),
              ),
              if (!compact)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: padding,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: borderColor),
                      bottom: BorderSide(color: borderColor),
                    ),
                  ),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: mutedColor,
                    ),
                    child: Row(
                      children: _selectedTab == 0
                          ? [
                              const Expanded(flex: 3, child: Text('Team')),
                              const Expanded(flex: 2, child: Text('Panel')),
                              if (!widget.isPit)
                                const Expanded(flex: 2, child: Text('Adviser')),
                              const Expanded(flex: 3, child: Text('Peer evaluation')),
                            ]
                          : const [
                              Expanded(flex: 3, child: Text('Team')),
                              Expanded(flex: 4, child: Text('Post-defense deliverable')),
                              Expanded(flex: 3, child: Text('Verdict & clearance')),
                            ],
                    ),
                  ),
                ),
              Flexible(
                child: SizedBox(
                  height: (visibleTeams.length * (compact ? 134.0 : 68.0))
                      .clamp(100.0, 360.0)
                      .toDouble(),
                  child: visibleTeams.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _query.isEmpty
                                  ? 'No incomplete teams to display.'
                                  : 'No teams match your search.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: mutedColor),
                            ),
                          ),
                        )
                      : Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          child: ListView.separated(
                            key: const ValueKey(
                              'incomplete-grading-teams-list',
                            ),
                            controller: _scrollController,
                            padding: EdgeInsets.symmetric(horizontal: padding),
                            itemCount: visibleTeams.length,
                            separatorBuilder: (_, _) =>
                                Divider(height: 1, color: borderColor),
                            itemBuilder: (_, index) =>
                                _teamRow(visibleTeams[index], compact),
                          ),
                        ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: padding,
                  vertical: short ? 10 : 14,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: borderColor)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Showing ${visibleTeams.length} of ${widget.teams.length} '
                        '${widget.teams.length == 1 ? 'team' : 'teams'}',
                        style: TextStyle(fontSize: 12, color: mutedColor),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textColor,
                        side: BorderSide(color: borderColor),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            DefensysTokens.radiusMd,
                          ),
                        ),
                      ),
                      child: Text(isReady ? 'Cancel' : 'Close'),
                    ),
                    if (isReady) ...[
                      const SizedBox(width: 10),
                      ElevatedButton(
                        key: const ValueKey('confirm-mark-stage-complete-button'),
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7F1D1D),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              DefensysTokens.radiusMd,
                            ),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_rounded, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Mark Complete',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabButton({
    required Key key,
    required String label,
    required IconData icon,
    required int pendingCount,
    required bool isSelected,
    required VoidCallback onTap,
    required bool compact,
  }) {
    final textColor = DefensysTokens.textPrimaryOf(context);
    final mutedColor = DefensysTokens.textSecondaryOf(context);
    final goldColor = DefensysTokens.goldOf(context);
    final isDone = pendingCount == 0;

    return Material(
      color: isSelected
          ? DefensysTokens.surfaceOf(context)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
      elevation: isSelected ? 1 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: 8,
            horizontal: compact ? 6 : 10,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? textColor : mutedColor,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? textColor : mutedColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDone
                      ? const Color(0xFF16A34A).withValues(alpha: 0.12)
                      : goldColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDone)
                      const Icon(
                        Icons.check_rounded,
                        size: 11,
                        color: Color(0xFF16A34A),
                      )
                    else
                      Text(
                        '$pendingCount',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: goldColor,
                        ),
                      ),
                    if (!compact) ...[
                      const SizedBox(width: 3),
                      Text(
                        isDone ? 'Complete' : 'Pending',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isDone
                              ? const Color(0xFF16A34A)
                              : goldColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _teamRow(Map<String, dynamic> team, bool compact) {
    final missing = _missing(team);
    final extra = missing.difference(_components.keys.toSet());
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _teamName(team),
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        if (extra.isNotEmpty)
          Text(
            extra.map((value) => value.replaceAll('_', ' ')).join(', '),
            style: TextStyle(
              fontSize: 12,
              color: DefensysTokens.goldOf(context),
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                name,
                const SizedBox(height: 10),
                if (_selectedTab == 0)
                  Wrap(
                    spacing: 18,
                    runSpacing: 10,
                    children: [
                      _evaluatorStatus(team, 'panel', compact: true),
                      if (!widget.isPit)
                        _evaluatorStatus(team, 'adviser', compact: true),
                      _evaluatorStatus(team, 'peer', compact: true),
                    ],
                  )
                else
                  Wrap(
                    spacing: 18,
                    runSpacing: 10,
                    children: [
                      _postDefenseStatus(team, compact: true),
                      _verdictClearanceStatus(team, compact: true),
                    ],
                  ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: name,
                  ),
                ),
                if (_selectedTab == 0) ...[
                  Expanded(
                    flex: 2,
                    child: _evaluatorStatus(team, 'panel'),
                  ),
                  if (!widget.isPit)
                    Expanded(
                      flex: 2,
                      child: _evaluatorStatus(team, 'adviser'),
                    ),
                  Expanded(
                    flex: 3,
                    child: _evaluatorStatus(team, 'peer'),
                  ),
                ] else ...[
                  Expanded(
                    flex: 4,
                    child: _postDefenseStatus(team),
                  ),
                  Expanded(
                    flex: 3,
                    child: _verdictClearanceStatus(team),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _evaluatorStatus(
    Map<String, dynamic> team,
    String component, {
    bool compact = false,
  }) {
    final missing = _missing(team);
    final isMissing = missing.contains(component);
    final unknown =
        missing.contains('grading') && team['${component}_complete'] != true;
    final color = isMissing
        ? DefensysTokens.goldOf(context)
        : (unknown
            ? DefensysTokens.textSecondaryOf(context)
            : const Color(0xFF16A34A));
    final label = isMissing
        ? (component == 'peer'
              ? '${team['evaluators_done'] ?? 0}/${team['evaluators_total'] ?? 0} evaluators'
              : 'Missing')
        : (unknown ? 'Check grading' : 'Ready');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact) ...[
          Text(
            _components[component]!,
            style: TextStyle(
              fontSize: 11,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isMissing
                  ? Icons.schedule_rounded
                  : (unknown
                        ? Icons.help_outline_rounded
                        : Icons.check_rounded),
              size: 14,
              color: color,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        if (component == 'peer' && isMissing) ...[
          const SizedBox(height: 3),
          Text(
            '${team['submitted'] ?? 0}/${team['required'] ?? 0} submissions',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _postDefenseStatus(
    Map<String, dynamic> team, {
    bool compact = false,
  }) {
    final missing = _missing(team);
    final isMissing = missing.contains('post_defense') ||
        team['post_defense_complete'] == false;
    final color = isMissing
        ? DefensysTokens.goldOf(context)
        : const Color(0xFF16A34A);
    final label = isMissing
        ? 'Awaiting Adviser Approval'
        : 'Approved & Cleared';
    final subLabel = isMissing
        ? 'Post-defense deliverable pending'
        : 'Archived successfully';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact) ...[
          Text(
            'Post-defense deliverable',
            style: TextStyle(
              fontSize: 11,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isMissing
                  ? Icons.schedule_rounded
                  : Icons.check_circle_outline_rounded,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: isMissing ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 2),
          Text(
            subLabel,
            style: TextStyle(
              fontSize: 11,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _verdictClearanceStatus(
    Map<String, dynamic> team, {
    bool compact = false,
  }) {
    final missing = _missing(team);
    final isRedefense = missing.contains('redefense');
    final isClearance = missing.contains('clearance');
    final isVerdict = missing.contains('verdict');

    final Color color;
    final IconData icon;
    final String label;
    final String subLabel;

    if (isRedefense) {
      color = DefensysTokens.dangerText;
      icon = Icons.error_outline_rounded;
      label = 'Re-defense Required';
      subLabel = 'Must pass re-defense';
    } else if (isClearance) {
      color = DefensysTokens.warningText;
      icon = Icons.published_with_changes_rounded;
      label = 'Revisions Pending Clearance';
      subLabel = 'Awaiting adviser verification';
    } else if (isVerdict) {
      color = DefensysTokens.goldOf(context);
      icon = Icons.gavel_rounded;
      label = 'Chair Verdict Pending';
      subLabel = 'No verdict entered';
    } else {
      color = const Color(0xFF16A34A);
      icon = Icons.check_circle_outline_rounded;
      label = 'Cleared';
      subLabel = 'Defense verdict satisfied';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact) ...[
          Text(
            'Verdict & clearance',
            style: TextStyle(
              fontSize: 11,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: (isRedefense || isClearance || isVerdict)
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        if (!compact) ...[
          const SizedBox(height: 2),
          Text(
            subLabel,
            style: TextStyle(
              fontSize: 11,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ],
    );
  }
}
