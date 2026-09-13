import 'package:flutter/material.dart';

import 'package:defensys/services/student_teams_provider.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/widgets/feedback/empty_state.dart';

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

int _count(StudentTeamsState state, String key) {
  final value = state.counts[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _projectTitle(Map<String, dynamic> team) {
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
  return _teamIsPit(team) ? 'No PIT event scheduled' : 'No defense scheduled';
}

Widget statusBadge(String status) {
  const green = Color(0xFF10B981);
  const red = Color(0xFFDC2626);
  const gold = DefensysUi.accentGold;

  final color = switch (status) {
    'Approved' => green,
    'Failed' => red,
    'Delayed/Extended' => gold,
    _ => const Color(0xFFB45309),
  };
  final bg = switch (status) {
    'Approved' => const Color(0xFFD1FAE5),
    'Failed' => const Color(0xFFFEE2E2),
    'Delayed/Extended' => const Color(0xFFFEF3C7),
    _ => const Color(0xFFFEF3C7),
  };

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      status,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class StudentTeamsSummaryCards extends StatelessWidget {
  const StudentTeamsSummaryCards({
    super.key,
    required this.state,
    required this.isPitContext,
  });

  final StudentTeamsState state;
  final bool isPitContext;

  @override
  Widget build(BuildContext context) {
    final hideAdviser = isPitContext;
    final cards = <Widget>[
      Expanded(
        child: _summaryCard(
          title: 'All Teams',
          value: _count(state, 'all'),
          subtitle: '',
          icon: Icons.groups_2_rounded,
          selected: true,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _summaryCard(
          title: 'Result Pending',
          value: _count(state, 'pending'),
          subtitle: 'Awaiting decision',
          icon: Icons.schedule_rounded,
          iconColor: const Color(0xFFB45309),
          iconBg: const Color(0xFFFEF3C7),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _summaryCard(
          title: 'Approved',
          value: _count(state, 'approved'),
          subtitle: 'Passed',
          icon: Icons.check_circle_rounded,
          iconColor: const Color(0xFF047857),
          iconBg: const Color(0xFFD1FAE5),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _summaryCard(
          title: 'Failed',
          value: _count(state, 'failed'),
          subtitle: 'Teams',
          icon: Icons.cancel_rounded,
          iconColor: const Color(0xFFB91C1C),
          iconBg: const Color(0xFFFEE2E2),
        ),
      ),
    ];
    if (!hideAdviser) {
      cards.addAll([
        const SizedBox(width: 12),
        Expanded(
          child: _summaryCard(
            title: 'Adviser Review',
            value: _count(state, 'no_adviser'),
            subtitle: 'Needs Review',
            icon: Icons.warning_rounded,
            iconColor: const Color(0xFFD97706),
            iconBg: const Color(0xFFFEF3C7),
          ),
        ),
      ]);
    }
    return Row(children: cards);
  }

  Widget _summaryCard({
    required String title,
    required int value,
    required String subtitle,
    required IconData icon,
    bool selected = false,
    Color iconColor = DefensysUi.techBlue,
    Color iconBg = const Color(0xFFEFF6FF),
  }) {
    return Container(
      height: 101,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF4F4) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? DefensysUi.primaryMaroon : Colors.transparent),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFF1F2F4) : iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: selected ? DefensysUi.textDark : iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F2743),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF98A2B3),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
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
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_rounded, color: Color(0xFF16A34A), size: 20),
              const SizedBox(width: 8),
              Text(
                'Unified Section Integration: $section',
                style: const TextStyle(
                  color: Color(0xFF14532D),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('System Name: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF14532D))),
              Text(systemName ?? 'Not specified', style: const TextStyle(fontSize: 13, color: Color(0xFF166534))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Project Manager: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF14532D))),
              Text(projectManager ?? 'Not specified', style: const TextStyle(fontSize: 13, color: Color(0xFF166534))),
              const SizedBox(width: 6),
              if (bulkPreview != null && bulkPreview!['section_assignment'] != null) ...[
                if (bulkPreview!['section_assignment']['project_manager_valid'] == true)
                  const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 15)
                else if (bulkPreview!['section_assignment']['project_manager_error'] != null)
                  Tooltip(
                    message: bulkPreview!['section_assignment']['project_manager_error'],
                    child: const Icon(Icons.error_outline_rounded, color: Colors.red, size: 15),
                  )
              ]
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
  });

  final StudentTeamsState state;
  final bool isPit;
  final String searchQuery;
  final ValueChanged<int> onOpenTeamDetail;

  @override
  State<GroupedSectionView> createState() => _GroupedSectionViewState();
}

class _GroupedSectionViewState extends State<GroupedSectionView> {
  final Map<String, String?> _selectedSectionAdviserFilter = {};
  final Map<String, bool> _sectionExpansionStates = {};

  Widget _sectionTableHeaderCell(String label, {required double flex}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF5D6678),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTableCell(Widget child, {required double flex}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ),
    );
  }

  Widget _sectionTeamRow(
    Map<String, dynamic> team, {
    required bool isPit,
  }) {
    final teamId = _asInt(team['id']);
    if (teamId == null) {
      return const SizedBox.shrink();
    }
    final teamName = team['name']?.toString() ?? 'Team';
    final projectTitle = _projectTitle(team);
    final adviserName = team['adviser_name']?.toString().trim() ?? '';
    final leaderName = team['leader_name']?.toString() ?? '-';
    final members = team['members'] as List? ?? const [];
    final leaderId = team['leader_id'];
    final leaderMember = members.whereType<Map>().where((m) => m['id'] == leaderId).firstOrNull;
    final leaderEnrolled = leaderMember == null || leaderMember['is_enrolled'] == true;
    final hasUnenrolled = members.any((m) => m is Map && m['is_enrolled'] == false);

    final rawPitEvent = team['pit_event_name']?.toString().trim() ??
        team['current_defense_stage']?.toString().trim() ??
        (team['defense_context'] is Map ? (team['defense_context']['event_label']?.toString().trim() ?? '') : '');
    final hasAssignedPitEvent = rawPitEvent.isNotEmpty &&
        rawPitEvent != 'No PIT event scheduled' &&
        rawPitEvent != 'No PIT Event';
    final defenseText = isPit
        ? (hasAssignedPitEvent ? rawPitEvent : 'No PIT Event')
        : _defenseContext(team);
    final status = team['status']?.toString() ?? 'Pending';

    final titleCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          teamName,
          style: const TextStyle(
            color: DefensysUi.textDark,
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          projectTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: DefensysUi.steelGrey,
            fontSize: 12,
          ),
        ),
        if (!isPit) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 12, color: DefensysUi.steelGrey),
              const SizedBox(width: 4),
              Text(
                adviserName.isEmpty ? 'Adviser: Unassigned' : 'Adviser: $adviserName',
                style: TextStyle(
                  fontSize: 11.5,
                  color: DefensysUi.steelGrey,
                  fontWeight: FontWeight.w500,
                  fontStyle: adviserName.isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
          ),
        ],
      ],
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
            style: const TextStyle(color: DefensysUi.textDark, fontSize: 12.5, fontWeight: FontWeight.w500),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: const Text(
              'Not Enrolled',
              style: TextStyle(color: Color(0xFFB91C1C), fontSize: 8.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      );
    } else {
      leaderWidget = Text(
        leaderName,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: DefensysUi.textDark, fontSize: 12.5, fontWeight: FontWeight.w500),
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
            style: const TextStyle(color: DefensysUi.steelGrey, fontSize: 11.5, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4),
          const Tooltip(
            message: 'Contains non-enrolled members',
            child: Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 14),
          ),
        ],
      );
    } else {
      membersWidget = Text(
        memberCountStr,
        style: const TextStyle(color: DefensysUi.steelGrey, fontSize: 11.5, fontWeight: FontWeight.w500),
      );
    }

    final leaderAndMembersCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        leaderWidget,
        const SizedBox(height: 2),
        membersWidget,
      ],
    );

    final flexes = isPit
        ? const [4.0, 2.5, 2.5, 1.0, 0.5]
        : const [3.5, 2.2, 2.2, 1.1, 0.5];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          _sectionTableCell(titleCol, flex: flexes[0]),
          _sectionTableCell(leaderAndMembersCol, flex: flexes[1]),
          _sectionTableCell(
            isPit && hasAssignedPitEvent
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Text(
                        defenseText,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF1D4ED8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                : Text(
                    defenseText.isEmpty ? '-' : defenseText,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isPit && !hasAssignedPitEvent ? DefensysUi.steelGrey : DefensysUi.textDark,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      fontStyle: isPit && !hasAssignedPitEvent ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
            flex: flexes[2],
          ),
          _sectionTableCell(
            statusBadge(status),
            flex: flexes[3],
          ),
          _sectionTableCell(
            Tooltip(
              message: 'View team details',
              child: InkWell(
                onTap: () => widget.onOpenTeamDetail(teamId),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.info_outline, color: DefensysUi.techBlue, size: 18),
                ),
              ),
            ),
            flex: flexes[4],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isPit = widget.isPit;

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
        description: 'No student teams found matching the active filters or search parameters.',
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

        final selectedAdviser = _selectedSectionAdviserFilter[section];
        final displayedTeams = (selectedAdviser == null || selectedAdviser == 'all')
            ? sectionTeams
            : sectionTeams.where((t) {
                final adviser = t['adviser_name']?.toString().trim() ?? '';
                return adviser == selectedAdviser;
              }).toList();

        final isExpanded = _sectionExpansionStates[section] ?? (widget.searchQuery.trim().isNotEmpty);

        final pendingCount = sectionTeams.where((t) {
          final status = t['status']?.toString().toLowerCase() ?? '';
          return status != 'approved' && status != 'failed';
        }).length;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
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
              title: Row(
                children: [
                  Text(
                    section,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: DefensysUi.textDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${sectionTeams.length} ${sectionTeams.length == 1 ? 'team' : 'teams'}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4B5563),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFB45309),
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$pendingCount Pending',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFFB45309),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              children: [
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                if (!isPit) ...[
                  Builder(
                    builder: (context) {
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
                        padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.people_outline_rounded,
                              size: 16,
                              color: DefensysUi.steelGrey,
                            ),
                            const SizedBox(width: 6),
                            const Padding(
                              padding: EdgeInsets.only(top: 2.0),
                              child: Text(
                                'Section Advisers:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: DefensysUi.steelGrey,
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
                                        _selectedSectionAdviserFilter[section] = null;
                                      });
                                    },
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 150),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isAllSelected ? DefensysUi.primaryMaroon : const Color(0xFFF3F4F6),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isAllSelected ? DefensysUi.primaryMaroon : const Color(0xFFE5E7EB),
                                          ),
                                        ),
                                        child: Text(
                                          'All',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isAllSelected ? Colors.white : DefensysUi.textDark,
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
                                      countColor = Colors.white.withValues(alpha: 0.8);
                                    } else if (isOverloaded) {
                                      bgColor = const Color(0xFFFDE8E8);
                                      borderColor = const Color(0xFFF8B4B4);
                                      textColor = const Color(0xFF9B1C1C);
                                      countColor = const Color(0xFFC81E1E);
                                    } else {
                                      bgColor = const Color(0xFFF3F4F6);
                                      borderColor = const Color(0xFFE5E7EB);
                                      textColor = DefensysUi.textDark;
                                      countColor = DefensysUi.steelGrey;
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
                                                  color: isSelected ? Colors.white : const Color(0xFFC81E1E),
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
                  child: displayedTeams.isEmpty
                      ? DefensysEmptyState(
                          icon: Icons.person_search_outlined,
                          title: 'No Teams for Selected Adviser',
                          description: 'No teams are assigned to this adviser under this section.',
                          size: DefensysEmptyStateSize.compact,
                        )
                      : Column(
                          children: [
                            Builder(
                              builder: (context) {
                                final flexes = isPit
                                    ? const [4.0, 2.5, 2.5, 1.0, 0.5]
                                    : const [3.5, 2.2, 2.2, 1.1, 0.5];
                                return Container(
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF9FAFB),
                                    border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                                  ),
                                  child: Row(
                                    children: [
                                      _sectionTableHeaderCell('TEAM & PROJECT TITLE', flex: flexes[0]),
                                      _sectionTableHeaderCell('LEADER & MEMBERS', flex: flexes[1]),
                                      _sectionTableHeaderCell(isPit ? 'PIT EVENT' : 'DEFENSE CONTEXT', flex: flexes[2]),
                                      _sectionTableHeaderCell('TEAM RESULT', flex: flexes[3]),
                                      _sectionTableHeaderCell('DETAILS', flex: flexes[4]),
                                    ],
                                  ),
                                );
                              },
                            ),
                            ...displayedTeams.map((team) => _sectionTeamRow(team, isPit: isPit)),
                          ],
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
