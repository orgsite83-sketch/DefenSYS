import 'package:defensys/theme/program_colors.dart';
import 'package:flutter/material.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/feedback/empty_state.dart';
import 'package:defensys/widgets/table/table.dart';
import 'package:defensys/widgets/repository/proposal_title_summary.dart';
import 'package:defensys/widgets/repository/shared_concept_review.dart';
import 'package:defensys/utils/section_instructors.dart';

import 'student_teams_stage_summary.dart';
import 'historical_team_dialog.dart';

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _projectTitle(Map<String, dynamic> team) {
  if (team['project_pending'] == true) return 'Project not selected';
  final title = team['project_title']?.toString();
  if (title != null && title.trim().isNotEmpty) {
    return title;
  }
  return team['name']?.toString() ?? '-';
}

bool _teamIsPit(Map<String, dynamic> team) =>
    team['level']?.toString().toUpperCase().contains('PIT') ?? false;

String _defenseContext(Map<String, dynamic> team) {
  final context = team['defense_context'];
  if (context is Map) {
    if (context['is_pit'] == true || _teamIsPit(team)) {
      final label = context['event_label']?.toString() ?? '';
      final date = context['scheduled_date']?.toString() ?? '';
      if (label.isNotEmpty && date.isNotEmpty) {
        return '$label ($date)';
      }
      if (label.isNotEmpty) {
        return label;
      }
      return 'No PIT event scheduled';
    }
    final stage = context['current_stage']?.toString();
    if (stage != null && stage.isNotEmpty) {
      return stage;
    }
    final readyForStage = context['ready_for_stage']?.toString();
    if (readyForStage != null && readyForStage.isNotEmpty) {
      return readyForStage;
    }
  }
  if (context is String && context.trim().isNotEmpty) {
    return context;
  }
  return _teamIsPit(team) ? 'No PIT event scheduled' : 'No stage selected';
}

class UnifiedSectionMetadataCard extends StatelessWidget {
  const UnifiedSectionMetadataCard({
    super.key,
    required this.section,
    required this.systemName,
    required this.projectManager,
    required this.bulkPreview,
  });

  final String? section;
  final String? systemName;
  final String? projectManager;
  final Map<String, dynamic>? bulkPreview;

  @override
  Widget build(BuildContext context) {
    if (section == null || section!.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF064E3B).withValues(alpha: 0.25)
            : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF065F46) : const Color(0xFFBBF7D0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.hub_rounded,
                color: isDark
                    ? const Color(0xFF34D399)
                    : const Color(0xFF16A34A),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Unified Section Integration: $section',
                style: TextStyle(
                  color: isDark
                      ? const Color(0xFF6EE7B7)
                      : const Color(0xFF14532D),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'System Name: ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark
                      ? const Color(0xFF6EE7B7)
                      : const Color(0xFF14532D),
                ),
              ),
              Text(
                systemName ?? 'Not specified',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? const Color(0xFFA7F3D0)
                      : const Color(0xFF166534),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Project Manager: ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark
                      ? const Color(0xFF6EE7B7)
                      : const Color(0xFF14532D),
                ),
              ),
              Text(
                projectManager ?? 'Not specified',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? const Color(0xFFA7F3D0)
                      : const Color(0xFF166534),
                ),
              ),
              const SizedBox(width: 6),
              if (bulkPreview != null &&
                  bulkPreview!['section_assignment'] != null) ...[
                if (bulkPreview!['section_assignment']['project_manager_valid'] ==
                    true)
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    color: Colors.green,
                    size: 15,
                  )
                else if (bulkPreview!['section_assignment']['project_manager_error'] !=
                    null)
                  Tooltip(
                    message:
                        bulkPreview!['section_assignment']['project_manager_error'],
                    child: const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.red,
                      size: 15,
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class GroupedSectionView extends StatefulWidget {
  const GroupedSectionView({
    super.key,
    required this.state,
    required this.isPit,
    required this.searchQuery,
    required this.onOpenTeamDetail,
    this.sharedProposalNamesOnly = false,
    this.canManageTeams = false,
  });

  final StudentTeamsState state;
  final bool isPit;
  final String searchQuery;
  final ValueChanged<int> onOpenTeamDetail;
  final bool sharedProposalNamesOnly;
  final bool canManageTeams;

  @override
  State<GroupedSectionView> createState() => _GroupedSectionViewState();
}

class _GroupedSectionViewState extends State<GroupedSectionView> {
  final Map<String, String?> _selectedSectionAdviserFilter = {};
  final Map<String, bool> _sectionExpansionStates = {};

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textPrimary =>
      _isDark ? DefensysTokens.textPrimaryDark : DefensysUi.textDark;
  Color get _textSecondary =>
      _isDark ? DefensysTokens.textSecondaryDark : DefensysUi.steelGrey;

  Widget _sharedProposalNames(Map workflow) {
    final systems = conceptRows(workflow['system_concepts']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: DefensysTokens.surfaceOf(context),
          border: Border.all(color: DefensysTokens.borderOf(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(padding: const EdgeInsets.all(16), child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Icon(
            Icons.account_tree_outlined,
            size: 20,
            color: DefensysTokens.maroonTextOf(context),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 16, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('Shared system proposals · ${workflow['stage_label']}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                  color: DefensysTokens.textPrimaryOf(context))),
              ProposalTitleProgressBadge(rows: systems),
            ]),
            const SizedBox(height: 4),
            ProposalTitleSummary(rows: systems, title: 'Shared systems', systems: true, showHeading: false),
          ])),
        ])),
      ),
    );
  }

  void _openTeam(Map<String, dynamic> team) {
    if (team['participation_id'] != null &&
        team['term_status'] == 'historical') {
      showHistoricalTeam(context, team);
      return;
    }
    final id = _asInt(team['id']);
    if (id != null) widget.onOpenTeamDetail(id);
  }

  Widget _buildTeamTitleCell(Map<String, dynamic> team, {required bool isPit}) {
    final teamName = team['name']?.toString() ?? 'Team';
    final projectTitle = _projectTitle(team);
    final adviserName = team['adviser_name']?.toString().trim() ?? '';
    final defense = team['defense_context'];
    final workflow = defense is Map && defense['concept_workflow'] is Map
        ? defense['concept_workflow'] as Map
        : <String, dynamic>{};
    final proposals = (workflow['concepts'] as List? ?? [])
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          teamName,
          style: TextStyle(
            color: DefensysTokens.textPrimaryOf(context),
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        if (team['capstone_phase'] == 'extended')
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: DefensysTokens.surfaceHigherOf(context),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'Extended',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: DefensysTokens.maroonTextOf(context),
                ),
              ),
            ),
          ),
        if (team['term_status'] == 'historical')
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              '${team['display_semester']} · ${team['status']}',
              style: TextStyle(fontSize: 11, color: _textSecondary),
            ),
          ),
          Text(
            hasOpenConceptProposals(workflow)
                ? 'Concept selection · ${proposals.where((c) => '${c['title'] ?? ''}'.trim().isNotEmpty).length} of ${proposals.length} titles provided'
                : projectTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _textSecondary, fontSize: 12),
        ),
        if (!isPit) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 12,
                color: _textSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  adviserName.isEmpty
                      ? 'Adviser: Unassigned'
                      : 'Adviser: $adviserName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: _textSecondary,
                    fontWeight: FontWeight.w500,
                    fontStyle: adviserName.isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLeaderAndMembersCell(Map<String, dynamic> team) {
    final leaderName = team['leader_name']?.toString() ?? '-';
    final members = team['members'] as List? ?? const [];
    final leaderId = team['leader_id'];
    final leaderMember = members
        .whereType<Map>()
        .where((m) => m['id'] == leaderId)
        .firstOrNull;
    final leaderEnrolled =
        leaderMember == null || leaderMember['is_enrolled'] == true;
    final hasUnenrolled = members.any(
      (m) => m is Map && m['is_enrolled'] == false,
    );

    Widget leaderWidget;
    if (!leaderEnrolled && leaderName != '-') {
      leaderWidget = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text(
            leaderName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: _isDark
                  ? const Color(0xFF7F1D1D).withValues(alpha: 0.3)
                  : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _isDark
                    ? const Color(0xFF991B1B)
                    : const Color(0xFFFCA5A5),
              ),
            ),
            child: Text(
              'Not Enrolled',
              style: TextStyle(
                color: _isDark
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFFB91C1C),
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
    } else {
      leaderWidget = Text(
        leaderName,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _textPrimary,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final memberCountStr = '${team['member_count'] ?? 0} members';
    Widget membersWidget;
    if (hasUnenrolled) {
      membersWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            memberCountStr,
            style: TextStyle(
              color: _textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          const Tooltip(
            message: 'Contains non-enrolled members',
            child: Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFD97706),
              size: 14,
            ),
          ),
        ],
      );
    } else {
      membersWidget = Text(
        memberCountStr,
        style: TextStyle(
          color: _textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [leaderWidget, const SizedBox(height: 2), membersWidget],
    );
  }

  Widget _buildDefenseContextCell(
    Map<String, dynamic> team, {
    required bool isPit,
  }) {
    final rawPitEvent =
        team['pit_event_name']?.toString().trim() ??
        team['current_defense_stage']?.toString().trim() ??
        (team['defense_context'] is Map
            ? (team['defense_context']['event_label']?.toString().trim() ?? '')
            : '');
    final hasAssignedPitEvent =
        rawPitEvent.isNotEmpty &&
        rawPitEvent != 'No PIT event scheduled' &&
        rawPitEvent != 'No PIT Event';
    final defenseText = isPit
        ? (hasAssignedPitEvent ? rawPitEvent : 'No PIT Event')
        : _defenseContext(team);

    if (isPit && hasAssignedPitEvent) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: ProgramColors.of(context, data: team).tint,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: ProgramColors.of(context, data: team).border,
            ),
          ),
          child: Text(
            defenseText,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ProgramColors.of(context, data: team).text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Text(
      defenseText.isEmpty ? '-' : defenseText,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: isPit && !hasAssignedPitEvent ? _textSecondary : _textPrimary,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        fontStyle: isPit && !hasAssignedPitEvent
            ? FontStyle.italic
            : FontStyle.normal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isPit = widget.isPit;
    final isDark = _isDark;

    final Map<String, int> adviserLoadCounts = {};
    if (!isPit) {
      for (final t in state.teams) {
        final adviser = t['adviser_name']?.toString().trim() ?? '';
        if (adviser.isNotEmpty) {
          adviserLoadCounts[adviser] = (adviserLoadCounts[adviser] ?? 0) + 1;
        }
      }
    }

    final Map<String, List<Map<String, dynamic>>> sectionsMap = {};
    for (final team in state.teams) {
      final sectionVal = team['section']?.toString().trim() ?? '';
      final section = sectionVal.isEmpty ? 'Unassigned Section' : sectionVal;
      sectionsMap.putIfAbsent(section, () => []).add(team);
    }

    final sortedSections = sectionsMap.keys.toList()..sort();

    if (sortedSections.isEmpty) {
      return DefensysEmptyState(
        icon: Icons.groups_outlined,
        title: 'No Teams Found',
        description:
            'No student teams found matching the active filters or search parameters.',
        size: DefensysEmptyStateSize.standard,
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedSections.length,
      itemBuilder: (context, index) {
        final section = sortedSections[index];
        final sectionTeams = sectionsMap[section]!;
        final systemName =
            sectionTeams.first['system_name']?.toString().trim() ?? '';
        final managerName =
            sectionTeams.first['project_manager_name']?.toString().trim() ?? '';
        final instructors = sectionInstructorsForTeam(sectionTeams.first);
        final sharedWorkflows = <String, Map>{};
        for (final team in sectionTeams) {
          final defense = team['defense_context'];
          final workflow = defense is Map ? defense['concept_workflow'] : null;
          final projectId = workflow is Map
              ? _asInt(workflow['section_project_id'])
              : null;
          if (workflow is Map && (projectId != null || workflow['shared_import_pending'] == true)) {
            sharedWorkflows[projectId == null ? 'imported:$section' : '$projectId'] = {
              ...workflow,
              'stage_label': defense is Map
                  ? defense['event_label'] ?? defense['current_stage'] ?? ''
                  : '',
            };
          }
        }

        final selectedAdviser = _selectedSectionAdviserFilter[section];
        final displayedTeams =
            (selectedAdviser == null || selectedAdviser == 'all')
            ? sectionTeams
            : sectionTeams.where((t) {
                final adviser = t['adviser_name']?.toString().trim() ?? '';
                return adviser == selectedAdviser;
              }).toList();

        final isExpanded =
            _sectionExpansionStates[section] ??
            (widget.searchQuery.trim().isNotEmpty);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? DefensysTokens.mistSurface : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark
                  ? DefensysTokens.mistBorder
                  : const Color(0xFFE5E7EB),
            ),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: Key('${section}_${widget.searchQuery.trim().isNotEmpty}'),
              initiallyExpanded: isExpanded,
              onExpansionChanged: (expanded) {
                setState(() {
                  _sectionExpansionStates[section] = expanded;
                });
              },
              shape: const Border(),
              collapsedShape: const Border(),
              leading: const Icon(
                Icons.class_rounded,
                color: DefensysUi.primaryMaroon,
                size: 20,
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
                      color: isDark
                          ? DefensysTokens.textPrimaryDark
                          : DefensysUi.textDark,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? DefensysTokens.mistInputFill
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${sectionTeams.length} ${sectionTeams.length == 1 ? 'team' : 'teams'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? DefensysTokens.textSecondaryDark
                            : const Color(0xFF4B5563),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              children: [
                Divider(
                  height: 1,
                  color: isDark
                      ? DefensysTokens.mistBorder
                      : const Color(0xFFE5E7EB),
                ),
                for (final entry in sharedWorkflows.entries)
                  _sharedProposalNames(entry.value),
                if (isPit || systemName.isNotEmpty || managerName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 24,
                        runSpacing: 8,
                        children: [
                          if (isPit)
                            Text(
                              instructors.isEmpty
                                  ? 'Instructor: Unassigned'
                                  : 'Instructor: ${instructors.map((i) => i['faculty_name']).join(', ')}',
                              style: TextStyle(
                                color: _textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          if (systemName.isNotEmpty && sharedWorkflows.isEmpty)
                            Text(
                              'Shared system: $systemName',
                              style: TextStyle(
                                color: _textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          if (managerName.isNotEmpty)
                            Text(
                              'Project manager: $managerName',
                              style: TextStyle(
                                color: _textSecondary,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (!isPit) ...[
                  Builder(
                    builder: (context) {
                      final sectionAdvisers =
                          sectionTeams
                              .map(
                                (t) =>
                                    t['adviser_name']?.toString().trim() ?? '',
                              )
                              .where((adv) => adv.isNotEmpty)
                              .toSet()
                              .toList()
                            ..sort();

                      if (sectionAdvisers.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      final isAllSelected =
                          selectedAdviser == null || selectedAdviser == 'all';

                      return Padding(
                        padding: const EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 12,
                          bottom: 4,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.people_outline_rounded,
                              size: 16,
                              color: isDark
                                  ? DefensysTokens.textSecondaryDark
                                  : DefensysUi.steelGrey,
                            ),
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Text(
                                'Section Advisers:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? DefensysTokens.textSecondaryDark
                                      : DefensysUi.steelGrey,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
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
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isAllSelected
                                              ? DefensysUi.primaryMaroon
                                              : (isDark
                                                    ? DefensysTokens
                                                          .mistInputFill
                                                    : const Color(0xFFF3F4F6)),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: isAllSelected
                                                ? DefensysUi.primaryMaroon
                                                : (isDark
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
                                                : (isDark
                                                      ? DefensysTokens
                                                            .textPrimaryDark
                                                      : DefensysUi.textDark),
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
                                      bgColor = DefensysUi.primaryMaroon;
                                      borderColor = DefensysUi.primaryMaroon;
                                      textColor = Colors.white;
                                      countColor = Colors.white.withValues(
                                        alpha: 0.8,
                                      );
                                    } else if (isOverloaded) {
                                      bgColor = isDark
                                          ? const Color(
                                              0xFF7F1D1D,
                                            ).withValues(alpha: 0.3)
                                          : const Color(0xFFFDE8E8);
                                      borderColor = isDark
                                          ? const Color(0xFF991B1B)
                                          : const Color(0xFFF8B4B4);
                                      textColor = isDark
                                          ? const Color(0xFFFCA5A5)
                                          : const Color(0xFF9B1C1C);
                                      countColor = isDark
                                          ? const Color(0xFFF87171)
                                          : const Color(0xFFC81E1E);
                                    } else {
                                      bgColor = isDark
                                          ? DefensysTokens.mistInputFill
                                          : const Color(0xFFF3F4F6);
                                      borderColor = isDark
                                          ? DefensysTokens.mistBorder
                                          : const Color(0xFFE5E7EB);
                                      textColor = isDark
                                          ? DefensysTokens.textPrimaryDark
                                          : DefensysUi.textDark;
                                      countColor = isDark
                                          ? DefensysTokens.textSecondaryDark
                                          : DefensysUi.steelGrey;
                                    }

                                    return GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedSectionAdviserFilter[section] =
                                              isSelected ? null : adv;
                                        });
                                      },
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 150,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: bgColor,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: borderColor,
                                            ),
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
                                                      : const Color(0xFFC81E1E),
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
                ],
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? DefensysTokens.mistSurface
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark
                              ? DefensysTokens.mistBorder
                              : DefensysTableTokens.cardBorder,
                        ),
                      ),
                      child: DefensysDataTable<Map<String, dynamic>>(
                        items: displayedTeams,
                        rowMinHeight: DefensysTableTokens.rowHeightMultiline,
                        onRowTap: (team) {
                          final teamId = _asInt(team['id']);
                          if (teamId != null) _openTeam(team);
                        },
                        emptyState: const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 24,
                            horizontal: 16,
                          ),
                          child: DefensysEmptyState(
                            icon: Icons.person_search_outlined,
                            title: 'No Teams for Selected Adviser',
                            description:
                                'No teams are assigned to this adviser under this section.',
                            size: DefensysEmptyStateSize.compact,
                          ),
                        ),
                        columns: [
                          DefensysTableColumn<Map<String, dynamic>>(
                            title: 'TEAM & PROJECT TITLE',
                            flex: isPit ? 3.5 : 3.0,
                            minWidth: 240,
                            cellBuilder: (context, team, index) =>
                                _buildTeamTitleCell(team, isPit: isPit),
                          ),
                          DefensysTableColumn<Map<String, dynamic>>(
                            title: 'LEADER & MEMBERS',
                            flex: 2.2,
                            minWidth: 170,
                            cellBuilder: (context, team, index) =>
                                _buildLeaderAndMembersCell(team),
                          ),
                          DefensysTableColumn<Map<String, dynamic>>(
                            title: isPit ? 'PIT EVENT' : 'CURRENT STAGE',
                            flex: 2.2,
                            minWidth: 170,
                            cellBuilder: (context, team, index) =>
                                _buildDefenseContextCell(team, isPit: isPit),
                          ),
                          if (!isPit)
                            DefensysTableColumn<Map<String, dynamic>>(
                              title: 'STAGE & DELIVERABLES',
                              flex: 1.6,
                              minWidth: 175,
                              cellBuilder: (context, team, index) {
                                final deliverableCount =
                                    (team['defense_context'] is Map
                                            ? team['defense_context']['deliverable_count']
                                            : null)
                                        as num? ??
                                    team['deliverable_count'] as num? ??
                                    0;
                                final teamId = _asInt(team['id']);
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    currentStageBadge(context, team),
                                    const SizedBox(height: 3),
                                    InkWell(
                                      onTap: teamId == null
                                          ? null
                                          : () => _openTeam(team),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 2,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              deliverableCount > 0
                                                  ? Icons
                                                        .check_circle_outline_rounded
                                                  : Icons.description_outlined,
                                              size: 11,
                                              color: deliverableCount > 0
                                                  ? const Color(0xFF059669)
                                                  : _textSecondary,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              deliverableCount > 0
                                                  ? '$deliverableCount ${deliverableCount == 1 ? 'file' : 'files'} submitted'
                                                  : 'No files yet',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                color: deliverableCount > 0
                                                    ? (_isDark
                                                          ? const Color(
                                                              0xFF6EE7B7,
                                                            )
                                                          : const Color(
                                                              0xFF047857,
                                                            ))
                                                    : _textSecondary,
                                                fontWeight: deliverableCount > 0
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              size: 12,
                                              color: deliverableCount > 0
                                                  ? (_isDark
                                                        ? const Color(
                                                            0xFF6EE7B7,
                                                          )
                                                        : const Color(
                                                            0xFF047857,
                                                          ))
                                                  : _textSecondary,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          DefensysTableColumn<Map<String, dynamic>>(
                            title: 'DETAILS',
                            flex: 0.9,
                            minWidth: 100,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            headerPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            cellBuilder: (context, team, index) {
                              final teamId = _asInt(team['id']);
                              return TextButton.icon(
                                onPressed: teamId == null
                                    ? null
                                    : () => _openTeam(team),
                                icon: const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 15,
                                ),
                                label: const Text('View'),
                                style: TextButton.styleFrom(
                                  foregroundColor: DefensysTokens.maroonTextOf(
                                    context,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
