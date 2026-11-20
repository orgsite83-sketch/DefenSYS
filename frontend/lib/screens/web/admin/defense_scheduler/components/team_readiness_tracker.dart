import 'package:defensys/widgets/repository/document_policy_editor.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/widgets/defense/re_demo_workspace.dart';
import 'package:defensys/widgets/export/report_export_menu.dart';

import 'package:defensys/models/defense_workflow_labels.dart';
import 'package:defensys/widgets/repository/workflow_status_style.dart';
import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/feedback/empty_state.dart';
import '../models/schedule_import_models.dart';
import '../models/team_status.dart';

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
    this.onReDemoChanged,
  });

  final DefenseSchedulerState state;
  final String scope;
  final String activeStageOrEventName;
  final void Function(Map<String, dynamic> team, String stageLabel)
  onReviewTeamDeliverables;
  final void Function(dynamic teamId, String stageLabel) onSendReminder;
  final bool isSendingReminder;
  final Widget? headerAction;
  final Widget? stageSelector;
  final String? title;
  final String? subtitle;
  final VoidCallback? onReDemoChanged;

  @override
  State<TeamReadinessTracker> createState() => _TeamReadinessTrackerState();
}

class _TeamReadinessTrackerState extends State<TeamReadinessTracker> {
  TeamStatusGroup _statusGroup = TeamStatusGroup.all;
  String _statusFilter = 'all';

  final TextEditingController _trackerSearchController =
      TextEditingController();
  final Map<String, String?> _selectedSectionAdviserFilter = {};
  String? _selectedPitYearLevel;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _selectedFilterBackground =>
      _isDark ? DefensysTokens.mistTextPrimary : DefensysTokens.mistBackground;
  Color get _selectedFilterForeground =>
      _isDark ? DefensysTokens.mistBackground : Colors.white;

  @override
  void didUpdateWidget(covariant TeamReadinessTracker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope ||
        oldWidget.activeStageOrEventName != widget.activeStageOrEventName) {
      _statusGroup = TeamStatusGroup.all;
      _statusFilter = 'all';
      _selectedSectionAdviserFilter.clear();
      if (oldWidget.scope != widget.scope) _selectedPitYearLevel = null;
    }
  }

  Widget _statusBadge(TeamStatus status) {
    final style = WorkflowStatusStyle.of(context, status.tone);
    return ShadBadge.outline(
      backgroundColor: style.background,
      foregroundColor: style.foreground,
      child: Text(
        status.label,
        style: const TextStyle(
          fontFamily: DefensysTokens.fontFamilyInter,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _adviserKey(Map<String, dynamic> team) => team['adviser'] == null
      ? 'name:${team['adviser_name']?.toString().trim() ?? ''}'
      : 'id:${team['adviser']}';

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
          color: _isDark
              ? DefensysTokens.textSecondaryDark
              : const Color(0xFF6B7280),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _readinessTable(String section, Widget table) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      // ExpansionTile saves a bool; scroll views save a double. Never let
      // either reuse the board's PageStorageKey or the section's state key.
      key: PageStorageKey(
        'readiness-table-${widget.scope}-${widget.activeStageOrEventName}-$section',
      ),
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: constraints.maxWidth < 900 ? 900 : constraints.maxWidth,
        child: table,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final activeStageOrEventName = widget.activeStageOrEventName;
    final activeEvent = widget.state.pitEvents.firstWhere(
      (event) => event['event_name'] == activeStageOrEventName,
      orElse: () => <String, dynamic>{},
    );

    final pitYearLevels = widget.scope == 'pit'
        ? (teamsForScope(widget.state, 'pit')
              .map((t) => t['level']?.toString().trim() ?? '')
              .where((l) => l.isNotEmpty)
              .toSet()
              .toList()
            ..sort())
        : <String>[];

    final scopeTeams =
        teamsForScope(
          widget.state,
          widget.scope,
          yearLevel: widget.scope == 'pit' ? _selectedPitYearLevel : null,
        ).where((team) {
          if (widget.scope == 'pit' &&
              !teamMatchesStatusEvent(team, activeEvent)) {
            return false;
          }
          return true;
        }).toList();
    final statuses = {
      for (final team in scopeTeams)
        team['id']: TeamStatus.fromTeam(
          team,
          activeStageOrEventName,
          scope: widget.scope,
          event: activeEvent,
        ),
    };
    final matchingTeams = scopeTeams.where((team) {
      final query = _trackerSearchController.text.toLowerCase().trim();
      if (query.isEmpty) return true;
      final name = (team['name']?.toString() ?? '').toLowerCase();
      final project = (team['project_title']?.toString() ?? '').toLowerCase();
      return name.contains(query) || project.contains(query);
    }).toList();
    final teams = matchingTeams.where((team) {
      final status = statuses[team['id']]!;
      return (_statusGroup == TeamStatusGroup.all ||
              status.group == _statusGroup) &&
          (_statusFilter == 'all' || status.code == _statusFilter);
    }).toList();
    final statusOptions = <String, String>{
      for (final status in statuses.values) status.code: status.label,
      if (_statusFilter != 'all' &&
          !statuses.values.any((s) => s.code == _statusFilter))
        _statusFilter: TeamStatus.describe(
          _statusFilter,
          scope: widget.scope,
        ).label,
    }.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

    return DefensysShadcnScope(
      child: _schedulerCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 12,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _isDark
                        ? DefensysTokens.mistMaroon.withValues(alpha: 0.18)
                        : DefensysTokens.maroonOf(
                            context,
                          ).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.checklist_rtl_rounded,
                    color: DefensysTokens.maroonTextOf(context),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  widget.title ?? 'Team status',
                  style: DefensysTokens.sectionTitle.copyWith(
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
                ReportExportMenu(
                  reportId: 'readiness',
                  params: {
                    'scope': widget.scope,
                    'stage': widget.activeStageOrEventName,
                    'search': _trackerSearchController.text.trim(),
                    'level': _selectedPitYearLevel ?? '',
                  },
                ),
                const SizedBox(width: 10),
                if (widget.headerAction != null) ...[
                  widget.headerAction!,
                  const SizedBox(width: 10),
                ],
                if (widget.scope == 'pit' && pitYearLevels.length > 1)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: WorkflowChoice(
                      value: _selectedPitYearLevel ?? 'all',
                      options: {
                        'all': 'All year levels',
                        for (final year in pitYearLevels) year: year,
                      },
                      onChanged: (value) => setState(() {
                        _selectedPitYearLevel = value == 'all' ? null : value;
                        _statusFilter = 'all';
                        _statusGroup = TeamStatusGroup.all;
                      }),
                    ),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: ShadInput(
                    key: const ValueKey('team-status-search'),
                    controller: _trackerSearchController,
                    placeholder: const Text('Search teams or projects...'),
                    leading: const Icon(Icons.search_rounded, size: 16),
                    onChanged: (_) => setState(() {}),
                    trailing: _trackerSearchController.text.isEmpty
                        ? null
                        : ShadButton.ghost(
                            size: ShadButtonSize.sm,
                            onPressed: () => setState(
                              () => _trackerSearchController.clear(),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 14,
                              semanticLabel: 'Clear search',
                            ),
                          ),
                  ),
                ),
              ],
            ),
            if (widget.stageSelector != null) ...[
              const SizedBox(height: 14),
              widget.stageSelector!,
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final group in TeamStatusGroup.values)
                  Semantics(
                    selected: _statusGroup == group,
                    child: ShadButton.ghost(
                      key: ValueKey('team-status-group-${group.name}'),
                      size: ShadButtonSize.sm,
                      backgroundColor: _statusGroup == group
                          ? _selectedFilterBackground
                          : Colors.transparent,
                      foregroundColor: _statusGroup == group
                          ? _selectedFilterForeground
                          : DefensysTokens.textSecondaryOf(context),
                      hoverBackgroundColor: _statusGroup == group
                          ? _selectedFilterBackground.withValues(alpha: 0.9)
                          : null,
                      hoverForegroundColor: _statusGroup == group
                          ? _selectedFilterForeground
                          : DefensysTokens.textSecondaryOf(context),
                      onPressed: () => setState(() {
                        _statusGroup = group;
                        _statusFilter = 'all';
                      }),
                      trailing: Text(
                        '${matchingTeams.where((team) => group == TeamStatusGroup.all || statuses[team['id']]!.group == group).length}',
                      ),
                      child: Flexible(
                        child: Text(
                          group.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            WorkflowChoice(
              key: const ValueKey('team-status-filter'),
              value: _statusFilter,
              options: {
                'all': 'All statuses',
                for (final option in statusOptions) option.key: option.value,
              },
              onChanged: (value) => setState(() {
                _statusFilter = value;
                _statusGroup = TeamStatusGroup.all;
              }),
            ),
            const SizedBox(height: 10),
            Text(
              widget.subtitle ??
                  'Progress and next steps for the selected stage or event.',
              style: TextStyle(
                color: _isDark
                    ? DefensysTokens.textSecondaryDark
                    : AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            if (teams.isEmpty || activeStageOrEventName.isEmpty)
              DefensysEmptyState(
                icon: Icons.assignment_turned_in_outlined,
                title: activeStageOrEventName.isEmpty
                    ? 'No stage or event selected'
                    : scopeTeams.isEmpty
                    ? 'No teams for this stage or event'
                    : 'No matching teams',
                description: activeStageOrEventName.isEmpty
                    ? 'Select or configure a defense stage or PIT event.'
                    : scopeTeams.isEmpty
                    ? 'No enrolled teams are available in this scope.'
                    : 'Adjust the search or status filters to see teams.',
                actions:
                    scopeTeams.isNotEmpty && activeStageOrEventName.isNotEmpty
                    ? ShadButton.outline(
                        onPressed: () => setState(() {
                          _statusGroup = TeamStatusGroup.all;
                          _statusFilter = 'all';
                          _trackerSearchController.clear();
                        }),
                        child: const Text('Clear filters'),
                      )
                    : null,
                size: DefensysEmptyStateSize.compact,
              )
            else ...[
              Builder(
                builder: (context) {
                  final allScopeTeams = teamsForScope(
                    widget.state,
                    widget.scope,
                    yearLevel: widget.scope == 'pit'
                        ? _selectedPitYearLevel
                        : null,
                  );
                  final Map<String, String> adviserNames = {};
                  final Map<String, Map> adviserCapacities = {};
                  for (final t in allScopeTeams) {
                    final adviser = t['adviser_name']?.toString().trim() ?? '';
                    if (adviser.isNotEmpty) {
                      final key = _adviserKey(t);
                      adviserNames[key] = adviser;
                      if (t['adviser_capacity'] is Map) {
                        final capacity = t['adviser_capacity'] as Map;
                        adviserCapacities[key] =
                            capacity['operating_capacity'] as Map? ?? capacity;
                      }
                    }
                  }

                  final Map<String, List<Map<String, dynamic>>> sectionsMap =
                      {};
                  for (final team in teams) {
                    final sectionVal = team['section']?.toString().trim() ?? '';
                    final section = sectionVal.isEmpty
                        ? 'No Section'
                        : sectionVal;
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
                      final selectedAdviser =
                          _selectedSectionAdviserFilter[section];

                      final displayedTeams =
                          (selectedAdviser == null ||
                              selectedAdviser == 'all' ||
                              widget.scope == 'pit')
                          ? sectionTeams
                          : sectionTeams.where((t) {
                              return _adviserKey(t) == selectedAdviser;
                            }).toList();

                      final sectionStatuses = sectionTeams
                          .map((team) => statuses[team['id']]!)
                          .toList();
                      final sameStatus =
                          sectionStatuses
                              .map((status) => status.code)
                              .toSet()
                              .length ==
                          1;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: _isDark
                              ? DefensysTokens.mistPanel
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isDark
                                ? DefensysTokens.mistBorder
                                : const Color(0xFFE5E7EB),
                          ),
                        ),
                        child: Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            key: PageStorageKey(
                              'readiness-section-${widget.scope}-$activeStageOrEventName-$section',
                            ),
                            initiallyExpanded: false,
                            collapsedIconColor: _isDark
                                ? DefensysTokens.textSecondaryDark
                                : AppColors.textSecondary,
                            iconColor: DefensysTokens.maroonTextOf(context),
                            leading: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: _isDark
                                    ? DefensysTokens.mistMaroon.withValues(
                                        alpha: 0.16,
                                      )
                                    : DefensysTokens.maroonOf(
                                        context,
                                      ).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                Icons.class_rounded,
                                color: DefensysTokens.maroonTextOf(context),
                                size: 18,
                              ),
                            ),
                            title: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 10,
                              runSpacing: 6,
                              children: [
                                Text(
                                  section,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: _isDark
                                        ? DefensysTokens.textPrimaryDark
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isDark
                                        ? DefensysTokens.mistInputFill
                                        : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _isDark
                                          ? DefensysTokens.mistBorder
                                          : const Color(0xFFE5E7EB),
                                    ),
                                  ),
                                  child: Text(
                                    '${sectionTeams.length} ${sectionTeams.length == 1 ? 'team' : 'teams'}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _isDark
                                          ? DefensysTokens.textSecondaryDark
                                          : const Color(0xFF4B5563),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (sameStatus)
                                  _statusBadge(sectionStatuses.first)
                                else
                                  Text(
                                    MediaQuery.sizeOf(context).width < 600
                                        ? 'Mixed statuses'
                                        : [
                                            for (final group
                                                in TeamStatusGroup.values.skip(
                                                  1,
                                                ))
                                              if (sectionStatuses.any(
                                                (status) =>
                                                    status.group == group,
                                              ))
                                                '${sectionStatuses.where((status) => status.group == group).length} ${group.label.toLowerCase()}',
                                          ].join(' · '),
                                    style: DefensysTokens.subtitle.copyWith(
                                      color: DefensysTokens.textSecondaryOf(
                                        context,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            children: [
                              Divider(
                                height: 1,
                                color: _isDark
                                    ? DefensysTokens.mistBorder
                                    : const Color(0xFFE5E7EB),
                              ),
                              Builder(
                                builder: (context) {
                                  if (widget.scope == 'pit') {
                                    final instructorName = sectionTeams
                                        .map(
                                          (t) =>
                                              t['instructor_name']
                                                  ?.toString()
                                                  .trim() ??
                                              '',
                                        )
                                        .firstWhere(
                                          (inst) => inst.isNotEmpty,
                                          orElse: () => '',
                                        );
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        left: 12,
                                        right: 12,
                                        top: 12,
                                        bottom: 4,
                                      ),
                                      child: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          Icon(
                                            Icons.person_outline_rounded,
                                            size: 16,
                                            color: _isDark
                                                ? DefensysTokens
                                                      .textSecondaryDark
                                                : AppColors.textSecondary,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Section Instructor: ',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: _isDark
                                                  ? DefensysTokens
                                                        .textSecondaryDark
                                                  : AppColors.textSecondary,
                                            ),
                                          ),
                                          Text(
                                            instructorName.isEmpty
                                                ? 'Unassigned'
                                                : instructorName,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: instructorName.isEmpty
                                                  ? (_isDark
                                                        ? DefensysTokens
                                                              .textSecondaryDark
                                                        : AppColors
                                                              .textSecondary)
                                                  : (_isDark
                                                        ? DefensysTokens
                                                              .textPrimaryDark
                                                        : AppColors
                                                              .textPrimary),
                                              fontStyle: instructorName.isEmpty
                                                  ? FontStyle.italic
                                                  : FontStyle.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  final sectionAdvisers =
                                      sectionTeams
                                          .map(_adviserKey)
                                          .where(adviserNames.containsKey)
                                          .toSet()
                                          .toList()
                                        ..sort(
                                          (a, b) => adviserNames[a]!.compareTo(
                                            adviserNames[b]!,
                                          ),
                                        );

                                  if (sectionAdvisers.isEmpty) {
                                    return const SizedBox.shrink();
                                  }

                                  final isAllSelected =
                                      selectedAdviser == null ||
                                      selectedAdviser == 'all';

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      left: 12,
                                      right: 12,
                                      top: 12,
                                      bottom: 4,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.people_outline_rounded,
                                                size: 16,
                                                color: _isDark
                                                    ? DefensysTokens
                                                          .textSecondaryDark
                                                    : AppColors.textSecondary,
                                              ),
                                              const SizedBox(width: 6),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 2.0,
                                                ),
                                                child: Text(
                                                  'Section Advisers:',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: _isDark
                                                        ? DefensysTokens
                                                              .textSecondaryDark
                                                        : AppColors
                                                              .textSecondary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _selectedSectionAdviserFilter[section] =
                                                    null;
                                              });
                                            },
                                            child: MouseRegion(
                                              cursor: SystemMouseCursors.click,
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 150,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: isAllSelected
                                                      ? (DefensysTokens.maroonOf(
                                                          context,
                                                        ))
                                                      : (_isDark
                                                            ? DefensysTokens
                                                                  .mistInputFill
                                                            : const Color(
                                                                0xFFF3F4F6,
                                                              )),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: isAllSelected
                                                        ? (DefensysTokens.maroonOf(
                                                            context,
                                                          ))
                                                        : (_isDark
                                                              ? DefensysTokens
                                                                    .mistBorder
                                                              : const Color(
                                                                  0xFFE5E7EB,
                                                                )),
                                                  ),
                                                ),
                                                child: Text(
                                                  'All',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: isAllSelected
                                                        ? Colors.white
                                                        : (_isDark
                                                              ? DefensysTokens
                                                                    .textSecondaryDark
                                                              : AppColors
                                                                    .textPrimary),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          ...sectionAdvisers.map((adv) {
                                            final isSelected =
                                                selectedAdviser == adv;
                                            final capacity =
                                                adviserCapacities[adv];
                                            final load = asInt(
                                              capacity?['active_count'],
                                            );
                                            final limit = asInt(
                                              capacity?['effective_limit'],
                                            );
                                            final isOverloaded =
                                                capacity?['is_overloaded'] ==
                                                true;

                                            Color bgColor;
                                            Color borderColor;
                                            Color textColor;
                                            Color countColor;

                                            if (isSelected) {
                                              bgColor = DefensysTokens.maroonOf(
                                                context,
                                              );
                                              borderColor =
                                                  DefensysTokens.maroonOf(
                                                    context,
                                                  );
                                              textColor = Colors.white;
                                              countColor = Colors.white
                                                  .withValues(alpha: 0.85);
                                            } else if (isOverloaded) {
                                              bgColor = _isDark
                                                  ? const Color(
                                                      0xFF7F1D1D,
                                                    ).withValues(alpha: 0.35)
                                                  : const Color(0xFFFDE8E8);
                                              borderColor = _isDark
                                                  ? const Color(
                                                      0xFFDC2626,
                                                    ).withValues(alpha: 0.45)
                                                  : const Color(0xFFF8B4B4);
                                              textColor = _isDark
                                                  ? const Color(0xFFFCA5A5)
                                                  : const Color(0xFF9B1C1C);
                                              countColor = _isDark
                                                  ? const Color(0xFFF87171)
                                                  : const Color(0xFFC81E1E);
                                            } else {
                                              bgColor = _isDark
                                                  ? DefensysTokens.mistInputFill
                                                  : const Color(0xFFF3F4F6);
                                              borderColor = _isDark
                                                  ? DefensysTokens.mistBorder
                                                  : const Color(0xFFE5E7EB);
                                              textColor = _isDark
                                                  ? DefensysTokens
                                                        .textPrimaryDark
                                                  : AppColors.textPrimary;
                                              countColor = _isDark
                                                  ? DefensysTokens
                                                        .textSecondaryDark
                                                  : AppColors.textSecondary;
                                            }

                                            return GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _selectedSectionAdviserFilter[section] =
                                                      isSelected ? null : adv;
                                                });
                                              },
                                              child: MouseRegion(
                                                cursor:
                                                    SystemMouseCursors.click,
                                                child: AnimatedContainer(
                                                  duration: const Duration(
                                                    milliseconds: 150,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: bgColor,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    border: Border.all(
                                                      color: borderColor,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          adviserNames[adv]!,
                                                          style: TextStyle(
                                                            fontFamily:
                                                                DefensysTokens
                                                                    .fontFamilyInter,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: textColor,
                                                          ),
                                                        ),
                                                      ),
                                                      if (load != null &&
                                                          limit != null) ...[
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Text(
                                                          '($load/$limit)',
                                                          style: TextStyle(
                                                            fontSize: 10.5,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: countColor,
                                                          ),
                                                        ),
                                                      ],
                                                      if (isOverloaded) ...[
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Icon(
                                                          Icons
                                                              .warning_amber_rounded,
                                                          size: 12,
                                                          color: isSelected
                                                              ? Colors.white
                                                              : (_isDark
                                                                    ? const Color(
                                                                        0xFFF87171,
                                                                      )
                                                                    : const Color(
                                                                        0xFFC81E1E,
                                                                      )),
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
                                  );
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: _readinessTable(
                                  section,
                                  Table(
                                    columnWidths: const {
                                      0: FlexColumnWidth(3.5),
                                      1: FlexColumnWidth(2.5),
                                      2: FlexColumnWidth(3),
                                      3: FlexColumnWidth(2.5),
                                    },
                                    defaultVerticalAlignment:
                                        TableCellVerticalAlignment.middle,
                                    children: [
                                      TableRow(
                                        decoration: BoxDecoration(
                                          color: _isDark
                                              ? DefensysTokens.mistInputFill
                                              : const Color(0xFFF9FAFB),
                                          border: Border(
                                            bottom: BorderSide(
                                              color: _isDark
                                                  ? DefensysTokens.mistBorder
                                                  : const Color(0xFFE5E7EB),
                                            ),
                                          ),
                                        ),
                                        children: [
                                          _tableHeaderCell(
                                            'TEAM & PROJECT TITLE',
                                          ),
                                          _tableHeaderCell('CURRENT STATUS'),
                                          _tableHeaderCell('NEXT STEP'),
                                          _tableHeaderCell('ACTIONS'),
                                        ],
                                      ),
                                      ...displayedTeams.map((team) {
                                        final status = statuses[team['id']]!;
                                        final verdict =
                                            (team['stage_verdicts']
                                                    as Map?)?[activeStageOrEventName]
                                                ?.toString() ??
                                            '';
                                        final hasVerdict = verdict.isNotEmpty;
                                        final reDemo =
                                            (team['re_demo_stages']
                                                    as Map?)?[activeStageOrEventName]
                                                as Map?;

                                        return TableRow(
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: _isDark
                                                    ? DefensysTokens.mistBorder
                                                    : const Color(0xFFF3F4F6),
                                              ),
                                            ),
                                          ),
                                          children: [
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                    horizontal: 10,
                                                  ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    team['name']?.toString() ??
                                                        '',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                      color: _isDark
                                                          ? DefensysTokens
                                                                .textPrimaryDark
                                                          : AppColors
                                                                .textPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    team['project_title']
                                                            ?.toString() ??
                                                        '-',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      color: _isDark
                                                          ? DefensysTokens
                                                                .textSecondaryDark
                                                          : AppColors
                                                                .textSecondary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Builder(
                                                    builder: (context) {
                                                      final isPit =
                                                          widget.scope ==
                                                              'pit' ||
                                                          (team['level']
                                                                  ?.toString()
                                                                  .contains(
                                                                    'PIT',
                                                                  ) ??
                                                              false);
                                                      if (isPit) {
                                                        final instructorName =
                                                            team['instructor_name']
                                                                ?.toString()
                                                                .trim() ??
                                                            '';
                                                        return Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .person_outline_rounded,
                                                              size: 13,
                                                              color: _isDark
                                                                  ? DefensysTokens
                                                                        .textSecondaryDark
                                                                  : AppColors
                                                                        .textSecondary,
                                                            ),
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                            Flexible(
                                                              child: Text(
                                                                instructorName
                                                                        .isEmpty
                                                                    ? 'Instructor: Unassigned'
                                                                    : 'Instructor: $instructorName',
                                                                style: TextStyle(
                                                                  fontFamily:
                                                                      DefensysTokens
                                                                          .fontFamilyInter,
                                                                  fontSize: 12,
                                                                  color: _isDark
                                                                      ? DefensysTokens
                                                                            .textSecondaryDark
                                                                      : AppColors
                                                                            .textSecondary,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                  fontStyle:
                                                                      instructorName
                                                                          .isEmpty
                                                                      ? FontStyle
                                                                            .italic
                                                                      : FontStyle
                                                                            .normal,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        );
                                                      }
                                                      final adviserName =
                                                          team['adviser_name']
                                                              ?.toString()
                                                              .trim() ??
                                                          '';
                                                      if (adviserName.isEmpty) {
                                                        return Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .person_outline_rounded,
                                                              size: 13,
                                                              color: _isDark
                                                                  ? DefensysTokens
                                                                        .textSecondaryDark
                                                                  : AppColors
                                                                        .textSecondary,
                                                            ),
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                            Text(
                                                              'Adviser: Unassigned',
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: _isDark
                                                                    ? DefensysTokens
                                                                          .textSecondaryDark
                                                                    : AppColors
                                                                          .textSecondary,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                fontStyle:
                                                                    FontStyle
                                                                        .italic,
                                                              ),
                                                            ),
                                                          ],
                                                        );
                                                      }
                                                      final capacity =
                                                          team['adviser_capacity']
                                                              as Map?;
                                                      final load = asInt(
                                                        capacity?['active_count'],
                                                      );
                                                      final limit = asInt(
                                                        capacity?['effective_limit'],
                                                      );
                                                      final isOverloaded =
                                                          capacity?['is_overloaded'] ==
                                                          true;
                                                      return Row(
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .person_outline_rounded,
                                                            size: 13,
                                                            color: _isDark
                                                                ? DefensysTokens
                                                                      .textSecondaryDark
                                                                : AppColors
                                                                      .textSecondary,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Flexible(
                                                            child: Text(
                                                              'Adviser: $adviserName',
                                                              style: TextStyle(
                                                                fontFamily:
                                                                    DefensysTokens
                                                                        .fontFamilyInter,
                                                                fontSize: 12,
                                                                color: _isDark
                                                                    ? DefensysTokens
                                                                          .textSecondaryDark
                                                                    : AppColors
                                                                          .textSecondary,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                            ),
                                                          ),
                                                          if (load != null &&
                                                              limit !=
                                                                  null) ...[
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        5,
                                                                    vertical:
                                                                        1.5,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    isOverloaded
                                                                    ? (_isDark
                                                                          ? const Color(
                                                                              0xFF7F1D1D,
                                                                            ).withValues(
                                                                              alpha: 0.35,
                                                                            )
                                                                          : const Color(
                                                                              0xFFFDE8E8,
                                                                            ))
                                                                    : (_isDark
                                                                          ? DefensysTokens.mistSurface
                                                                          : const Color(
                                                                              0xFFF3F4F6,
                                                                            )),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      4,
                                                                    ),
                                                                border: Border.all(
                                                                  color:
                                                                      isOverloaded
                                                                      ? (_isDark
                                                                            ? const Color(
                                                                                0xFFDC2626,
                                                                              ).withValues(
                                                                                alpha: 0.45,
                                                                              )
                                                                            : const Color(
                                                                                0xFFF8B4B4,
                                                                              ))
                                                                      : (_isDark
                                                                            ? DefensysTokens.mistBorder
                                                                            : const Color(
                                                                                0xFFE5E7EB,
                                                                              )),
                                                                ),
                                                              ),
                                                              child: Text(
                                                                '$load/$limit teams',
                                                                style: TextStyle(
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color:
                                                                      isOverloaded
                                                                      ? (_isDark
                                                                            ? const Color(
                                                                                0xFFFCA5A5,
                                                                              )
                                                                            : const Color(
                                                                                0xFF9B1C1C,
                                                                              ))
                                                                      : (_isDark
                                                                            ? DefensysTokens.textSecondaryDark
                                                                            : AppColors.textSecondary),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                    horizontal: 10,
                                                  ),
                                              child: Column(
                                                key: ValueKey(
                                                  'team-defense-status-${team['id']}-$activeStageOrEventName',
                                                ),
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  _statusBadge(status),
                                                  if (hasVerdict &&
                                                      defenseVerdictLabel(
                                                            verdict,
                                                          ).toLowerCase() !=
                                                          status.label
                                                              .toLowerCase()) ...[
                                                    const SizedBox(height: 5),
                                                    Text(
                                                      defenseVerdictLabel(
                                                        verdict,
                                                      ),
                                                      style: DefensysTokens
                                                          .subtitle
                                                          .copyWith(
                                                            color:
                                                                DefensysTokens.textSecondaryOf(
                                                                  context,
                                                                ),
                                                          ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                    horizontal: 10,
                                                  ),
                                              child: Text(
                                                status.nextStep,
                                                key: ValueKey(
                                                  'team-next-step-${team['id']}',
                                                ),
                                                style: DefensysTokens.subtitle
                                                    .copyWith(
                                                      color:
                                                          DefensysTokens.textSecondaryOf(
                                                            context,
                                                          ),
                                                    ),
                                              ),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 8,
                                                    horizontal: 10,
                                                  ),
                                              child: Wrap(
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                spacing: 8,
                                                runSpacing: 4,
                                                children: [
                                                  if (reDemo != null)
                                                    DefensysShadcnScope(
                                                      child: ShadButton.outline(
                                                        size: ShadButtonSize.sm,
                                                        onPressed: () async {
                                                          await showReDemoWorkspace(
                                                            context,
                                                            sourceScheduleId:
                                                                (reDemo['source_schedule_id']
                                                                        as num)
                                                                    .toInt(),
                                                            scheduleNow:
                                                                reDemo['can_schedule'] ==
                                                                true,
                                                          );
                                                          if (mounted) {
                                                            widget
                                                                .onReDemoChanged
                                                                ?.call();
                                                          }
                                                        },
                                                        child: Flexible(
                                                          child: Text(
                                                            reDemo['can_schedule'] ==
                                                                    true
                                                                ? 'Schedule re-demo'
                                                                : 'View re-demo',
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ShadButton.ghost(
                                                    size: ShadButtonSize.sm,
                                                    foregroundColor:
                                                        DefensysTokens.maroonTextOf(
                                                          context,
                                                        ),
                                                    onPressed:
                                                        activeStageOrEventName
                                                            .isEmpty
                                                        ? null
                                                        : () => widget
                                                              .onReviewTeamDeliverables(
                                                                team,
                                                                activeStageOrEventName,
                                                              ),
                                                    leading: const Icon(
                                                      Icons.folder_open_rounded,
                                                      size: 16,
                                                    ),
                                                    child: const Flexible(
                                                      child: Text(
                                                        'Review files',
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                  if (status.group ==
                                                          TeamStatusGroup
                                                              .beforeScheduling &&
                                                      !{
                                                        'ready_to_schedule',
                                                        'not_configured',
                                                        'unknown',
                                                      }.contains(status.code) &&
                                                      !hasVerdict)
                                                    ShadButton.ghost(
                                                      size: ShadButtonSize.sm,
                                                      onPressed:
                                                          widget.isSendingReminder ||
                                                              activeStageOrEventName
                                                                  .isEmpty
                                                          ? null
                                                          : () => widget
                                                                .onSendReminder(
                                                                  team['id'],
                                                                  activeStageOrEventName,
                                                                ),
                                                      leading: const Icon(
                                                        Icons
                                                            .notification_important_rounded,
                                                        size: 16,
                                                      ),
                                                      child: const Flexible(
                                                        child: Text(
                                                          'Remind',
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
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
      ),
    );
  }
}
