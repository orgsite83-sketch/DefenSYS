import 'package:flutter/material.dart';

import 'package:defensys/models/defense_workflow_labels.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/feedback/empty_state.dart';
import '../models/schedule_import_models.dart';

class TeamReadinessTracker extends StatefulWidget {
  const TeamReadinessTracker({
    super.key,
    required this.state,
    required this.scope,
    required this.activeStageOrEventName,
    required this.onReviewTeamDeliverables,
    required this.onSendReminder,
    required this.isSendingReminder,
    this.headerAction,
    this.stageSelector,
    this.title,
    this.subtitle,
  });

  final DefenseSchedulerState state;
  final String scope;
  final String activeStageOrEventName;
  final void Function(Map<String, dynamic> team, String stageLabel) onReviewTeamDeliverables;
  final void Function(dynamic teamId, String stageLabel) onSendReminder;
  final bool isSendingReminder;
  final Widget? headerAction;
  final Widget? stageSelector;
  final String? title;
  final String? subtitle;

  @override
  State<TeamReadinessTracker> createState() => _TeamReadinessTrackerState();
}

class _TeamReadinessTrackerState extends State<TeamReadinessTracker> {
  final TextEditingController _trackerSearchController = TextEditingController();
  final Map<String, String?> _selectedSectionAdviserFilter = {};
  String? _selectedPitYearLevel;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  @override
  void dispose() {
    _trackerSearchController.dispose();
    super.dispose();
  }

  Widget _schedulerCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistSurface : Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: _isDark ? const Color(0x33000000) : const Color(0x0A000000),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: child,
    );
  }

  Widget _tableHeaderCell(String label) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF6B7280),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSectionStatusBadge({
    required IconData icon,
    required String label,
    required bool isSuccess,
  }) {
    final bgColor = isSuccess
        ? (_isDark ? const Color(0xFF064E3B).withValues(alpha: 0.38) : const Color(0xFFDEF7EC))
        : (_isDark ? const Color(0xFF78350F).withValues(alpha: 0.38) : const Color(0xFFFEF3C7));
    final borderColor = isSuccess
        ? (_isDark ? const Color(0xFF059669).withValues(alpha: 0.45) : const Color(0xFFB9F1D6))
        : (_isDark ? const Color(0xFFD97706).withValues(alpha: 0.45) : const Color(0xFFFDE68A));
    final fgColor = isSuccess
        ? (_isDark ? const Color(0xFF34D399) : const Color(0xFF03543F))
        : (_isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fgColor, size: 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: fgColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeStageOrEventName = widget.activeStageOrEventName;

    final pitYearLevels = widget.scope == 'pit'
        ? (teamsForScope(widget.state, 'pit')
            .map((t) => t['level']?.toString().trim() ?? '')
            .where((l) => l.isNotEmpty)
            .toSet()
            .toList()
          ..sort())
        : <String>[];

    final teams = teamsForScope(
      widget.state,
      widget.scope,
      yearLevel: widget.scope == 'pit' ? _selectedPitYearLevel : null,
    ).where((team) {
      final query = _trackerSearchController.text.toLowerCase().trim();
      if (query.isEmpty) return true;
      final name = (team['name']?.toString() ?? '').toLowerCase();
      final project = (team['project_title']?.toString() ?? '').toLowerCase();
      return name.contains(query) || project.contains(query);
    }).toList();

    return _schedulerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _isDark
                      ? DefensysTokens.mistMaroon.withValues(alpha: 0.18)
                      : AppColors.maroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.checklist_rtl_rounded,
                  color: _isDark ? DefensysTokens.mistMaroonText : AppColors.maroon,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.title ?? 'Team Readiness Tracker',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: _isDark ? DefensysTokens.textPrimaryDark : AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              if (widget.headerAction != null) ...[
                widget.headerAction!,
                const SizedBox(width: 10),
              ],
              if (widget.scope == 'pit' && pitYearLevels.length > 1) ...[
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _isDark ? DefensysTokens.mistInputFill : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFD0D5DD)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      dropdownColor: _isDark ? DefensysTokens.mistSurface : Colors.white,
                      value: pitYearLevels.contains(_selectedPitYearLevel)
                          ? _selectedPitYearLevel
                          : 'all',
                      isDense: true,
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: _isDark ? DefensysTokens.textPrimaryDark : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('All Year Levels'),
                        ),
                        ...pitYearLevels.map(
                          (lvl) => DropdownMenuItem(value: lvl, child: Text(lvl)),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedPitYearLevel = val == 'all' ? null : val;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Container(
                width: 260,
                height: 38,
                decoration: BoxDecoration(
                  color: _isDark ? DefensysTokens.mistInputFill : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFD0D5DD)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 18, color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _trackerSearchController,
                        decoration: InputDecoration(
                          hintText: 'Search teams...',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: _isDark
                                ? DefensysTokens.textSecondaryDark.withValues(alpha: 0.7)
                                : AppColors.textSecondary.withValues(alpha: 0.8),
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: _isDark ? DefensysTokens.textPrimaryDark : AppColors.textPrimary,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_trackerSearchController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _trackerSearchController.clear();
                          setState(() {});
                        },
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.stageSelector != null) ...[
            const SizedBox(height: 14),
            widget.stageSelector!,
          ],
          const SizedBox(height: 10),
          Text(
            widget.subtitle ??
                'Monitor team deliverable completeness. Teams must have all required pre-defense deliverables accepted by their instructor before they are ready for scheduling.',
            style: TextStyle(
              color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          if (teams.isEmpty)
            DefensysEmptyState.table(
              icon: Icons.assignment_turned_in_outlined,
              title: _trackerSearchController.text.isEmpty
                  ? 'No Teams for Active Scope'
                  : 'No Teams Match Query',
              description: _trackerSearchController.text.isEmpty
                  ? 'There are no teams enrolled or ready for evaluation in this scope.'
                  : 'No teams found matching "${_trackerSearchController.text.trim()}".',
              size: DefensysEmptyStateSize.compact,
            )
          else ...[
            Builder(
              builder: (context) {
                final allScopeTeams = teamsForScope(
                  widget.state,
                  widget.scope,
                  yearLevel: widget.scope == 'pit' ? _selectedPitYearLevel : null,
                );
                final Map<String, int> adviserLoadCounts = {};
                for (final t in allScopeTeams) {
                  final adviser = t['adviser_name']?.toString().trim() ?? '';
                  if (adviser.isNotEmpty) {
                    adviserLoadCounts[adviser] = (adviserLoadCounts[adviser] ?? 0) + 1;
                  }
                }

                final Map<String, List<Map<String, dynamic>>> sectionsMap = {};
                for (final team in teams) {
                  final sectionVal = team['section']?.toString().trim() ?? '';
                  final section = sectionVal.isEmpty ? 'No Section' : sectionVal;
                  sectionsMap.putIfAbsent(section, () => []).add(team);
                }

                final sortedSections = sectionsMap.keys.toList()
                  ..sort((a, b) {
                    if (a == 'No Section') return 1;
                    if (b == 'No Section') return -1;
                    return a.compareTo(b);
                  });

                return Column(
                  children: sortedSections.map((section) {
                    final sectionTeams = sectionsMap[section]!;
                    final selectedAdviser = _selectedSectionAdviserFilter[section];

                    final displayedTeams = (selectedAdviser == null || selectedAdviser == 'all' || widget.scope == 'pit')
                        ? sectionTeams
                        : sectionTeams.where((t) {
                            final adviser = t['adviser_name']?.toString().trim() ?? '';
                            return adviser == selectedAdviser;
                          }).toList();

                    final isSectionCompleted = activeStageOrEventName.isNotEmpty &&
                        sectionTeams.every((team) =>
                            isTeamStageCompleted(team, activeStageOrEventName));
                    final isSectionReady = activeStageOrEventName.isNotEmpty &&
                        sectionTeams.every((team) =>
                            isTeamStageReady(team, activeStageOrEventName));
                    final sectionReadyCount = activeStageOrEventName.isNotEmpty
                        ? sectionTeams
                            .where((team) => isTeamStageReady(team, activeStageOrEventName))
                            .length
                        : 0;
                    final sectionPendingCount = sectionTeams.where((team) =>
                        getTeamStageStatus(team, activeStageOrEventName) == 'pending').length;
                    final sectionAwaitingCompletion = sectionTeams.every((team) =>
                        getTeamStageStatus(team, activeStageOrEventName) == 'awaiting_completion');
                    final sectionHasVerdicts = sectionTeams.every((team) =>
                        ((team['stage_verdicts'] as Map?)?[activeStageOrEventName]?.toString() ?? '').isNotEmpty);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: _isDark ? DefensysTokens.mistPanel : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB)),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                          initiallyExpanded: false,
                          collapsedIconColor: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
                          iconColor: _isDark ? DefensysTokens.mistMaroonText : AppColors.maroon,
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _isDark
                                  ? DefensysTokens.mistMaroon.withValues(alpha: 0.16)
                                  : AppColors.maroon.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.class_rounded,
                              color: _isDark ? DefensysTokens.mistMaroonText : AppColors.maroon,
                              size: 18,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                section,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: _isDark ? DefensysTokens.textPrimaryDark : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB),
                                  ),
                                ),
                                child: Text(
                                  '${sectionTeams.length} ${sectionTeams.length == 1 ? 'team' : 'teams'}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _isDark ? DefensysTokens.textSecondaryDark : const Color(0xFF4B5563),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (isSectionCompleted) ...[
                                const SizedBox(width: 10),
                                _buildSectionStatusBadge(
                                  icon: Icons.check_circle_rounded,
                                  label: 'Completed',
                                  isSuccess: true,
                                ),
                              ] else if (isSectionReady) ...[
                                const SizedBox(width: 10),
                                _buildSectionStatusBadge(
                                  icon: Icons.auto_awesome_rounded,
                                  label: 'Ready',
                                  isSuccess: true,
                                ),
                              ] else if (sectionReadyCount > 0) ...[
                                const SizedBox(width: 10),
                                _buildSectionStatusBadge(
                                  icon: Icons.auto_awesome_rounded,
                                  label: '$sectionReadyCount Ready',
                                  isSuccess: true,
                                ),
                              ] else ...[
                                const SizedBox(width: 10),
                                _buildSectionStatusBadge(
                                  icon: Icons.warning_amber_rounded,
                                  label: sectionPendingCount > 0
                                      ? 'Needs Endorsement'
                                      : sectionAwaitingCompletion
                                          ? 'Awaiting Completion'
                                          : sectionHasVerdicts ? 'Outcomes Recorded' : 'Defense in Progress',
                                  isSuccess: false,
                                ),
                              ],
                            ],
                          ),
                          children: [
                            Divider(height: 1, color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB)),
                            Builder(
                              builder: (context) {
                                if (widget.scope == 'pit') {
                                  final instructorName = sectionTeams
                                      .map((t) => t['instructor_name']?.toString().trim() ?? '')
                                      .firstWhere((inst) => inst.isNotEmpty, orElse: () => '');
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.person_outline_rounded,
                                          size: 16,
                                          color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Section Instructor: ',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
                                          ),
                                        ),
                                        Text(
                                          instructorName.isEmpty ? 'Unassigned' : instructorName,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: instructorName.isEmpty
                                                ? (_isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary)
                                                : (_isDark ? DefensysTokens.textPrimaryDark : AppColors.textPrimary),
                                            fontStyle: instructorName.isEmpty ? FontStyle.italic : FontStyle.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                final sectionAdvisers = sectionTeams
                                    .map((t) => t['adviser_name']?.toString().trim() ?? '')
                                    .where((adv) => adv.isNotEmpty)
                                    .toSet()
                                    .toList()
                                  ..sort();

                                if (sectionAdvisers.isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                final isAllSelected = selectedAdviser == null || selectedAdviser == 'all';

                                return Padding(
                                  padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 4),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.people_outline_rounded,
                                        size: 16,
                                        color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2.0),
                                        child: Text(
                                          'Section Advisers:',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _selectedSectionAdviserFilter[section] = null;
                                                });
                                              },
                                              child: MouseRegion(
                                                cursor: SystemMouseCursors.click,
                                                child: AnimatedContainer(
                                                  duration: const Duration(milliseconds: 150),
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: isAllSelected
                                                        ? (_isDark ? DefensysTokens.mistMaroon : AppColors.maroon)
                                                        : (_isDark ? DefensysTokens.mistInputFill : const Color(0xFFF3F4F6)),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: isAllSelected
                                                          ? (_isDark ? DefensysTokens.mistMaroon : AppColors.maroon)
                                                          : (_isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB)),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    'All',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: isAllSelected
                                                          ? Colors.white
                                                          : (_isDark ? DefensysTokens.textSecondaryDark : AppColors.textPrimary),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            ...sectionAdvisers.map((adv) {
                                              final isSelected = selectedAdviser == adv;
                                              final load = adviserLoadCounts[adv] ?? 0;
                                              final isOverloaded = load > 4;

                                              Color bgColor;
                                              Color borderColor;
                                              Color textColor;
                                              Color countColor;

                                              if (isSelected) {
                                                bgColor = _isDark ? DefensysTokens.mistMaroon : AppColors.maroon;
                                                borderColor = _isDark ? DefensysTokens.mistMaroon : AppColors.maroon;
                                                textColor = Colors.white;
                                                countColor = Colors.white.withValues(alpha: 0.85);
                                              } else if (isOverloaded) {
                                                bgColor = _isDark
                                                    ? const Color(0xFF7F1D1D).withValues(alpha: 0.35)
                                                    : const Color(0xFFFDE8E8);
                                                borderColor = _isDark
                                                    ? const Color(0xFFDC2626).withValues(alpha: 0.45)
                                                    : const Color(0xFFF8B4B4);
                                                textColor = _isDark ? const Color(0xFFFCA5A5) : const Color(0xFF9B1C1C);
                                                countColor = _isDark ? const Color(0xFFF87171) : const Color(0xFFC81E1E);
                                              } else {
                                                bgColor = _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF3F4F6);
                                                borderColor = _isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB);
                                                textColor = _isDark ? DefensysTokens.textPrimaryDark : AppColors.textPrimary;
                                                countColor = _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary;
                                              }

                                              return GestureDetector(
                                                onTap: () {
                                                  setState(() {
                                                    _selectedSectionAdviserFilter[section] = isSelected ? null : adv;
                                                  });
                                                },
                                                child: MouseRegion(
                                                  cursor: SystemMouseCursors.click,
                                                  child: AnimatedContainer(
                                                    duration: const Duration(milliseconds: 150),
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: bgColor,
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: borderColor),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          adv,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                            color: textColor,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          '($load/4)',
                                                          style: TextStyle(
                                                            fontSize: 10.5,
                                                            fontWeight: FontWeight.bold,
                                                            color: countColor,
                                                          ),
                                                        ),
                                                        if (isOverloaded) ...[
                                                          const SizedBox(width: 4),
                                                          Icon(
                                                            Icons.warning_amber_rounded,
                                                            size: 12,
                                                            color: isSelected
                                                                ? Colors.white
                                                                : (_isDark ? const Color(0xFFF87171) : const Color(0xFFC81E1E)),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Table(
                                columnWidths: const {
                                  0: FlexColumnWidth(4),
                                  1: FlexColumnWidth(2.5),
                                  2: FlexColumnWidth(3),
                                },
                                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(
                                      color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF9FAFB),
                                      border: Border(bottom: BorderSide(color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB))),
                                    ),
                                    children: [
                                      _tableHeaderCell('TEAM & PROJECT TITLE'),
                                      _tableHeaderCell('DEFENSE STATUS'),
                                      _tableHeaderCell('ACTIONS'),
                                    ],
                                  ),
                                  ...displayedTeams.map((team) {
                                    final stageStatus = getTeamStageStatus(team, activeStageOrEventName);
                                    final isCompleted = stageStatus == 'completed';
                                    final isScheduled = stageStatus == 'scheduled';
                                    final isReady = isTeamStageReady(team, activeStageOrEventName);
                                    final isPending = stageStatus == 'pending';
                                    final verdict = (team['stage_verdicts'] as Map?)?[activeStageOrEventName]?.toString() ?? '';
                                    final hasVerdict = verdict.isNotEmpty;

                                    Color dotColor;
                                    Color statusTextColor;
                                    String statusText;
                                    IconData statusIcon;

                                    if (isCompleted) {
                                      dotColor = _isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
                                      statusTextColor = _isDark ? const Color(0xFF34D399) : const Color(0xFF047857);
                                      statusText = 'Completed (Passed)';
                                      statusIcon = Icons.check_circle_rounded;
                                    } else if (isScheduled) {
                                      dotColor = _isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
                                      statusTextColor = _isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);
                                      statusText = 'Defense Scheduled';
                                      statusIcon = Icons.event_available_rounded;
                                    } else if (isReady) {
                                      dotColor = _isDark ? const Color(0xFF34D399) : const Color(0xFF10B981);
                                      statusTextColor = _isDark ? const Color(0xFF34D399) : const Color(0xFF065F46);
                                      statusText = stageStatus == 'redefense_required'
                                          ? 'Ready for Re-defense'
                                          : stageStatus == 'failed'
                                              ? 'Ready for Retake'
                                              : 'Ready for Defense';
                                      statusIcon = Icons.auto_awesome_rounded;
                                    } else if (isPending) {
                                      dotColor = _isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B);
                                      statusTextColor = _isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
                                      statusText = 'Awaiting Endorsement';
                                      statusIcon = Icons.hourglass_top_rounded;
                                    } else {
                                      final isBlocked = stageStatus == 'failed' || stageStatus == 'project_rejected';
                                      dotColor = isBlocked
                                          ? (_isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626))
                                          : (_isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B));
                                      statusTextColor = dotColor;
                                      statusText = defenseProgressLabel(stageStatus);
                                      statusIcon = isBlocked ? Icons.block_rounded : Icons.assignment_turned_in_outlined;
                                    }

                                    final progressText = isCompleted
                                        ? 'Completed'
                                        : hasVerdict && stageStatus == 'redefense_required' && !isReady
                                            ? 'Awaiting re-defense eligibility'
                                            : statusText;
                                    if (hasVerdict) {
                                      statusText = defenseVerdictLabel(verdict);
                                      final isPassing = verdict == 'approved' || verdict == 'approved_with_revisions';
                                      final isFailed = verdict == 'failed' || verdict == 'project_rejected';
                                      dotColor = isPassing
                                          ? (_isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                                          : isFailed
                                              ? (_isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626))
                                              : (_isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309));
                                      statusTextColor = dotColor;
                                      statusIcon = isPassing
                                          ? Icons.check_circle_rounded
                                          : isFailed ? Icons.block_rounded : Icons.replay_rounded;
                                    }

                                    return TableRow(
                                      decoration: BoxDecoration(
                                        border: Border(bottom: BorderSide(color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFF3F4F6))),
                                      ),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                team['name']?.toString() ?? '',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: _isDark ? DefensysTokens.textPrimaryDark : AppColors.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                team['project_title']?.toString() ?? '-',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Builder(
                                                builder: (context) {
                                                  final isPit = widget.scope == 'pit' || (team['level']?.toString().contains('PIT') ?? false);
                                                  if (isPit) {
                                                    final instructorName = team['instructor_name']?.toString().trim() ?? '';
                                                    return Row(
                                                      children: [
                                                        Icon(Icons.person_outline_rounded, size: 13, color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          instructorName.isEmpty ? 'Instructor: Unassigned' : 'Instructor: $instructorName',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
                                                            fontWeight: FontWeight.w500,
                                                            fontStyle: instructorName.isEmpty ? FontStyle.italic : FontStyle.normal,
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  }
                                                  final adviserName = team['adviser_name']?.toString().trim() ?? '';
                                                  if (adviserName.isEmpty) {
                                                    return Row(
                                                      children: [
                                                        Icon(Icons.person_outline_rounded, size: 13, color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'Adviser: Unassigned',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
                                                            fontWeight: FontWeight.w500,
                                                            fontStyle: FontStyle.italic,
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  }
                                                  final load = adviserLoadCounts[adviserName] ?? 0;
                                                  final isOverloaded = load > 4;
                                                  return Row(
                                                    children: [
                                                      Icon(Icons.person_outline_rounded, size: 13, color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Adviser: $adviserName',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: _isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                        decoration: BoxDecoration(
                                                          color: isOverloaded
                                                              ? (_isDark ? const Color(0xFF7F1D1D).withValues(alpha: 0.35) : const Color(0xFFFDE8E8))
                                                              : (_isDark ? DefensysTokens.mistSurface : const Color(0xFFF3F4F6)),
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(
                                                            color: isOverloaded
                                                                ? (_isDark ? const Color(0xFFDC2626).withValues(alpha: 0.45) : const Color(0xFFF8B4B4))
                                                                : (_isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB)),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          '$load/4 teams',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                            color: isOverloaded
                                                                ? (_isDark ? const Color(0xFFFCA5A5) : const Color(0xFF9B1C1C))
                                                                : (_isDark ? DefensysTokens.textSecondaryDark : AppColors.textSecondary),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                                          child: Row(
                                            children: [
                                              Icon(
                                                statusIcon,
                                                size: 15,
                                                color: dotColor,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  key: ValueKey('team-defense-status-${team['id']}-$activeStageOrEventName'),
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      statusText,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w700,
                                                        color: statusTextColor,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    if (hasVerdict && progressText.toLowerCase() != statusText.toLowerCase()) ...[
                                                      const SizedBox(height: 3),
                                                      Text(
                                                        progressText,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: DefensysTokens.textSecondaryOf(context),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                          child: Row(
                                            children: [
                                              TextButton.icon(
                                                onPressed: activeStageOrEventName.isEmpty
                                                    ? null
                                                    : () => widget.onReviewTeamDeliverables(team, activeStageOrEventName),
                                                icon: const Icon(Icons.folder_open_rounded, size: 16),
                                                label: const Text('Review Files'),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: _isDark ? DefensysTokens.mistMaroonText : AppColors.maroon,
                                                  disabledForegroundColor: _isDark ? DefensysTokens.textSecondaryDark.withValues(alpha: 0.4) : null,
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              if (isPending && !hasVerdict)
                                                TextButton.icon(
                                                  onPressed: widget.isSendingReminder || activeStageOrEventName.isEmpty
                                                      ? null
                                                      : () => widget.onSendReminder(team['id'], activeStageOrEventName),
                                                  icon: const Icon(Icons.notification_important_rounded, size: 16),
                                                  label: const Text('Remind'),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: _isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                                                    disabledForegroundColor: _isDark ? DefensysTokens.textSecondaryDark.withValues(alpha: 0.4) : null,
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ),
                            ],
                          ),
                        ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
