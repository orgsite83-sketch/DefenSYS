import 'package:flutter/material.dart';

import 'package:defensys/services/defense_scheduler_provider.dart';
import 'package:defensys/theme/app_theme.dart';
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
  });

  final DefenseSchedulerState state;
  final String scope;
  final String activeStageOrEventName;
  final void Function(Map<String, dynamic> team, String stageLabel) onReviewTeamDeliverables;
  final void Function(dynamic teamId, String stageLabel) onSendReminder;
  final bool isSendingReminder;

  @override
  State<TeamReadinessTracker> createState() => _TeamReadinessTrackerState();
}

class _TeamReadinessTrackerState extends State<TeamReadinessTracker> {
  final TextEditingController _trackerSearchController = TextEditingController();
  final Map<String, String?> _selectedSectionAdviserFilter = {};

  @override
  void dispose() {
    _trackerSearchController.dispose();
    super.dispose();
  }

  Widget _schedulerCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
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
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF6B7280),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeStageOrEventName = widget.activeStageOrEventName;

    final teams = teamsForScope(widget.state, widget.scope).where((team) {
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
              const Icon(
                Icons.checklist_rtl_rounded,
                color: AppColors.maroon,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text(
                'Team Readiness Tracker',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                width: 260,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD0D5DD)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _trackerSearchController,
                        decoration: const InputDecoration(
                          hintText: 'Search teams...',
                          hintStyle: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_trackerSearchController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _trackerSearchController.clear();
                          setState(() {});
                        },
                        child: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Monitor team deliverable completeness. Teams must have all required pre-defense deliverables accepted by their instructor before they are ready for scheduling.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          if (teams.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: Text(
                _trackerSearchController.text.isEmpty
                    ? 'No teams found for the active scope.'
                    : 'No teams match your search query.',
                style: const TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
              ),
            )
          else ...[
            Builder(
              builder: (context) {
                final allScopeTeams = teamsForScope(widget.state, widget.scope);
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

                    final isSectionReady = activeStageOrEventName.isNotEmpty &&
                        sectionTeams.every((team) =>
                            team['ready_for_stage'] == activeStageOrEventName);

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
                          initiallyExpanded: false,
                          leading: const Icon(
                            Icons.class_rounded,
                            color: AppColors.maroon,
                            size: 20,
                          ),
                          title: Row(
                            children: [
                              Text(
                                section,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: AppColors.textPrimary,
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
                              if (isSectionReady) ...[
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDEF7EC),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        color: Color(0xFF03543F),
                                        size: 13,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Ready',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: Color(0xFF03543F),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        color: Color(0xFFB45309),
                                        size: 13,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Needs Endorsement',
                                        style: TextStyle(
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
                                        const Icon(
                                          Icons.person_outline_rounded,
                                          size: 16,
                                          color: AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          'Section Instructor: ',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        Text(
                                          instructorName.isEmpty ? 'Unassigned' : instructorName,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: instructorName.isEmpty ? AppColors.textSecondary : AppColors.textPrimary,
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
                                      const Icon(
                                        Icons.people_outline_rounded,
                                        size: 16,
                                        color: AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      const Padding(
                                        padding: EdgeInsets.only(top: 2.0),
                                        child: Text(
                                          'Section Advisers:',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textSecondary,
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
                                                    color: isAllSelected ? AppColors.maroon : const Color(0xFFF3F4F6),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: isAllSelected ? AppColors.maroon : const Color(0xFFE5E7EB),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    'All',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: isAllSelected ? Colors.white : AppColors.textPrimary,
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
                                                bgColor = AppColors.maroon;
                                                borderColor = AppColors.maroon;
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
                                                textColor = AppColors.textPrimary;
                                                countColor = AppColors.textSecondary;
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
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF9FAFB),
                                      border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                                    ),
                                    children: [
                                      _tableHeaderCell('TEAM & PROJECT TITLE'),
                                      _tableHeaderCell('READINESS STATUS'),
                                      _tableHeaderCell('ACTIONS'),
                                    ],
                                  ),
                                  ...displayedTeams.map((team) {
                                    final isReady = team['ready_for_stage'] == activeStageOrEventName && activeStageOrEventName.isNotEmpty;
                                    final readyForStage = team['ready_for_stage']?.toString() ?? '';
                                    final statusText = isReady
                                        ? 'Ready'
                                        : (readyForStage.isNotEmpty
                                            ? 'Endorsed for $readyForStage'
                                            : 'Awaiting Endorsement');

                                    return TableRow(
                                      decoration: const BoxDecoration(
                                        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
                                      ),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                team['name']?.toString() ?? '',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                team['project_title']?.toString() ?? '-',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                  color: AppColors.textSecondary,
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
                                                        const Icon(Icons.person_outline_rounded, size: 13, color: AppColors.textSecondary),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          instructorName.isEmpty ? 'Instructor: Unassigned' : 'Instructor: $instructorName',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: AppColors.textSecondary,
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
                                                      children: const [
                                                        Icon(Icons.person_outline_rounded, size: 13, color: AppColors.textSecondary),
                                                        SizedBox(width: 4),
                                                        Text(
                                                          'Adviser: Unassigned',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: AppColors.textSecondary,
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
                                                      const Icon(Icons.person_outline_rounded, size: 13, color: AppColors.textSecondary),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Adviser: $adviserName',
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: AppColors.textSecondary,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                        decoration: BoxDecoration(
                                                          color: isOverloaded ? const Color(0xFFFDE8E8) : const Color(0xFFF3F4F6),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          '$load/4 teams',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                            color: isOverloaded ? const Color(0xFF9B1C1C) : AppColors.textSecondary,
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
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: isReady ? Colors.green : Colors.amber,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  statusText,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: isReady ? Colors.green.shade800 : Colors.amber.shade900,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
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
                                                  foregroundColor: AppColors.maroon,
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              if (!isReady)
                                                TextButton.icon(
                                                  onPressed: widget.isSendingReminder || activeStageOrEventName.isEmpty
                                                      ? null
                                                      : () => widget.onSendReminder(team['id'], activeStageOrEventName),
                                                  icon: const Icon(Icons.notification_important_rounded, size: 16),
                                                  label: const Text('Remind'),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: const Color(0xFFD97706),
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
