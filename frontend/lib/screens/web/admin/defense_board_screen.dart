import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/auth_provider.dart';
import '../../../services/defense_board_provider.dart';
import '../../../theme/app_theme.dart';
import 'defense_scheduler/defense_scheduler_screen.dart';
import 'widgets/defensys_admin_shell.dart';
import '../faculty/minutes_form_screen.dart';

class DefenseBoardScreen extends ConsumerStatefulWidget {
  const DefenseBoardScreen({super.key});

  @override
  ConsumerState<DefenseBoardScreen> createState() => _DefenseBoardScreenState();
}

class _DefenseBoardScreenState extends ConsumerState<DefenseBoardScreen> {
  final TextEditingController _searchController = TextEditingController();
  int? _selectedMinutesScheduleId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(defenseBoardProvider.notifier).fetchBoard();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedMinutesScheduleId != null) {
      return MinutesFormScreen(
        scheduleId: _selectedMinutesScheduleId!,
        onBack: () {
          setState(() {
            _selectedMinutesScheduleId = null;
          });
          ref.read(defenseBoardProvider.notifier).fetchBoard();
        },
      );
    }

    final state = ref.watch(defenseBoardProvider);

    final cp = DefensysUi.contentPadding;

    return Scaffold(
      backgroundColor: DefensysUi.bgLight,
      body: RefreshIndicator(
        color: AppColors.maroon,
        onRefresh: () => ref.read(defenseBoardProvider.notifier).fetchBoard(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(cp.left, cp.top, cp.right, 22),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(state),
                    const SizedBox(height: 26),
                    _buildSummaryCards(state),

                    const SizedBox(height: 22),
                    _buildFilterBar(state),
                  ],
                ),
              ),
            ),
            if (state.isLoading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: SizedBox.expand(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(cp.left, 0, cp.right, cp.bottom),
                    child: _buildLoadingState(),
                  ),
                ),
              )
            else if (state.schedules.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: SizedBox.expand(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(cp.left, 0, cp.right, cp.bottom),
                    child: _buildEmptyBoard(),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(cp.left, 0, cp.right, cp.bottom),
                sliver: SliverToBoxAdapter(
                  child: _buildBoardSection(state),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(DefenseBoardState state) {
    final user = ref.watch(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;
    final canSchedule = isAdmin || isPitLead;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.view_agenda_outlined,
                    color: AppColors.maroon,
                    size: 24,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Defense Board',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: AppColors.maroon,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                state.activeSemester?['display_name']?.toString() ??
                    'View all scheduled defense slots across stages and dates.',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (canSchedule) ...[
          const SizedBox(width: 20),
          SizedBox(
            height: 42,
            child: ElevatedButton.icon(
              onPressed: _openScheduler,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.maroon,
                foregroundColor: AppColors.gold,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text(
                'New Schedule Run',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryCards(DefenseBoardState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1100;

        if (compact) {
          return Column(
            children: [
              _buildSummaryCard(
                icon: Icons.event,
                iconColor: const Color(0xFF7C3AED),
                label: 'Total Schedules',
                value: _count(state, 'all'),
              ),
              const SizedBox(height: 14),
              _buildSummaryCard(
                icon: Icons.access_time_filled,
                iconColor: const Color(0xFF2563EB),
                label: 'Upcoming',
                value: _count(state, 'scheduled'),
              ),
              const SizedBox(height: 14),
              _buildSummaryCard(
                icon: Icons.check_circle,
                iconColor: const Color(0xFF0F9D58),
                label: 'Completed',
                value: _count(state, 'done'),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.event,
                iconColor: const Color(0xFF7C3AED),
                label: 'Total Schedules',
                value: _count(state, 'all'),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.access_time_filled,
                iconColor: const Color(0xFF2563EB),
                label: 'Upcoming',
                value: _count(state, 'scheduled'),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.check_circle,
                iconColor: const Color(0xFF0F9D58),
                label: 'Completed',
                value: _count(state, 'done'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required int value,
  }) {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: iconColor, size: 23),
          ),
          const SizedBox(width: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(DefenseBoardState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 980;

          if (stacked) {
            return Column(
              children: [
                _buildStageDropdown(state, double.infinity),
                const SizedBox(height: 12),
                _buildStatusDropdown(state, double.infinity),
                const SizedBox(height: 12),
                _buildSearchField(state, double.infinity),
              ],
            );
          }

          return Row(
            children: [
              _buildStageDropdown(state, 155),
              const SizedBox(width: 12),
              _buildStatusDropdown(state, 155),
              const SizedBox(width: 12),
              Expanded(child: _buildSearchField(state, null)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStageDropdown(DefenseBoardState state, double? width) {
    final stages = state.stageOptions.toSet().toList();
    final currentValue = stages.contains(state.stage)
        ? state.stage
        : '';

    return SizedBox(
      width: width,
      height: 48,
      child: DropdownButtonFormField<String>(
        initialValue: currentValue,
        decoration: _inputDecoration(),
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(12),
        isExpanded: true,
        items: [
          const DropdownMenuItem<String>(
            value: '',
            child: Text('All Stages', overflow: TextOverflow.ellipsis),
          ),
          ...stages.map(
            (stage) => DropdownMenuItem<String>(
              value: stage,
              child: Text(stage, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (value) {
          ref
              .read(defenseBoardProvider.notifier)
              .fetchBoard(
                stage: value ?? '',
                status: state.status,
                scope: state.scope,
                search: _searchController.text.trim(),
              );
        },
      ),
    );
  }

  Widget _buildStatusDropdown(DefenseBoardState state, double? width) {
    final statuses = state.statuses.toSet().toList();
    final currentValue = statuses.contains(state.status)
        ? state.status
        : '';

    return SizedBox(
      width: width,
      height: 48,
      child: DropdownButtonFormField<String>(
        initialValue: currentValue,
        decoration: _inputDecoration(),
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(12),
        isExpanded: true,
        items: [
          const DropdownMenuItem<String>(
            value: '',
            child: Text('All Statuses', overflow: TextOverflow.ellipsis),
          ),
          ...statuses.map(
            (status) => DropdownMenuItem<String>(
              value: status,
              child: Text(_statusLabel(status), overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (value) {
          ref
              .read(defenseBoardProvider.notifier)
              .fetchBoard(
                stage: state.stage,
                status: value ?? '',
                scope: state.scope,
                search: _searchController.text.trim(),
              );
        },
      ),
    );
  }

  Widget _buildSearchField(DefenseBoardState state, double? width) {
    return SizedBox(
      width: width,
      height: 48,
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        decoration: _inputDecoration(
          hintText: 'Search team or room...',
          prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
        ),
        onSubmitted: (value) {
          ref
              .read(defenseBoardProvider.notifier)
              .fetchBoard(
                stage: state.stage,
                status: state.status,
                scope: state.scope,
                search: value.trim(),
              );
        },
      ),
    );
  }

  Widget _buildBoardSection(DefenseBoardState state) {
    if (state.schedules.isEmpty) {
      return _buildEmptyBoard();
    }

    final groups = _groupSchedules(state.schedules);

    return Column(
      children: groups.map((group) => _buildSessionCard(group, state)).toList(),
    );
  }

  List<_SessionGroup> _groupSchedules(List<dynamic> rawSchedules) {
    final Map<String, _SessionGroup> groupMap = {};

    for (final item in rawSchedules) {
      if (item is! Map<String, dynamic>) continue;

      final stageLabel = item['stage_label']?.toString() ?? 'Unspecified Stage';
      final date = item['scheduled_date']?.toString() ?? 'TBD';
      final room = item['room']?.toString() ?? 'TBD';
      final panel = _panelistNames(item);
      final documenter = item['documenter_name']?.toString() ?? '';
      final scope = item['scope']?.toString() ?? 'capstone';

      final key = '$stageLabel|$date|$room|$panel|$documenter';

      if (!groupMap.containsKey(key)) {
        groupMap[key] = _SessionGroup(
          key: key,
          stageLabel: stageLabel,
          scheduledDate: date,
          room: room,
          panelNames: panel,
          documenterName: documenter,
          scope: scope,
          schedules: [],
        );
      }
      groupMap[key]!.schedules.add(item);
    }

    // Sort schedules inside each group by start_time
    for (final group in groupMap.values) {
      group.schedules.sort((a, b) {
        final tA = a['start_time']?.toString() ?? '';
        final tB = b['start_time']?.toString() ?? '';
        return tA.compareTo(tB);
      });
    }

    return groupMap.values.toList();
  }

  Widget _buildSessionCard(_SessionGroup group, DefenseBoardState state) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6E8EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSessionHeader(group),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE9EDF4)),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 900) {
                return _buildCompactTeamList(group, state);
              }
              return _buildDesktopTeamTable(group, state);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSessionHeader(_SessionGroup group) {
    final isPit = group.scope == 'pit';
    final docDisplay = group.documenterName.isNotEmpty
        ? group.documenterName
        : (isPit ? '-' : 'Unassigned');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFD),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Stage badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isPit
                      ? const Color(0xFFE0F2FE)
                      : AppColors.maroon.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isPit
                        ? const Color(0xFFBAE6FD)
                        : AppColors.maroon.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPit ? Icons.alt_route : Icons.assignment,
                      size: 14,
                      color: isPit ? const Color(0xFF0369A1) : AppColors.maroon,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      group.stageLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isPit ? const Color(0xFF0369A1) : AppColors.maroon,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Date chip
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today, size: 15, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    group.scheduledDate,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // Room chip
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    group.room,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Teams count badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${group.schedules.length} ${group.schedules.length == 1 ? 'Team' : 'Teams'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Sub-header info: Panelists & Documenter
          Wrap(
            spacing: 24,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_outline, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  const Text(
                    'Panel: ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      group.panelNames,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (!isPit)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.edit_note, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    const Text(
                      'Documenter: ',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      docDisplay,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: group.documenterName.isEmpty ? FontWeight.w600 : FontWeight.w700,
                        color: group.documenterName.isEmpty
                            ? Colors.amber.shade900
                            : AppColors.textPrimary,
                        fontStyle: group.documenterName.isEmpty ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTeamTable(_SessionGroup group, DefenseBoardState state) {
    return Column(
      children: [
        // Sub-table Header
        Container(
          height: 40,
          color: const Color(0xFFF8FAFC),
          child: const Row(
            children: [
              _HeaderCell('Time Slot', flex: 1),
              _HeaderCell('Team & Project Title', flex: 4),
              _HeaderCell('Minutes', flex: 2),
              _HeaderCell('Status', flex: 2),
              _HeaderCell('Action', flex: 1),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE9EDF4)),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: group.schedules.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
          itemBuilder: (context, index) {
            final schedule = group.schedules[index];
            final projectTitle = schedule['project_title']?.toString() ?? '';

            return SizedBox(
              height: 56,
              child: Row(
                children: [
                  _BodyCell(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _shortTime(schedule['start_time']),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  _BodyCell(
                    flex: 4,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          schedule['team_name']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (projectTitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            projectTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _BodyCell(
                    flex: 2,
                    child: _minutesStatusChip(schedule),
                  ),
                  _BodyCell(
                    flex: 2,
                    child: _statusChip(schedule['status']?.toString() ?? ''),
                  ),
                  _BodyCell(
                    flex: 1,
                    child: _deleteAction(state, schedule),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCompactTeamList(_SessionGroup group, DefenseBoardState state) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: group.schedules.map((schedule) {
          final projectTitle = schedule['project_title']?.toString() ?? '';

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE9EDF4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Text(
                        _shortTime(schedule['start_time']),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        schedule['team_name']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    _deleteAction(state, schedule),
                  ],
                ),
                if (projectTitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    projectTitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    _statusChip(schedule['status']?.toString() ?? ''),
                    const SizedBox(width: 8),
                    _minutesStatusChip(schedule),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _deleteAction(DefenseBoardState state, Map<String, dynamic> schedule) {
    final user = ref.watch(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;
    final isSchedulePit = schedule['scope'] == 'pit';
    final canDelete = isAdmin || (isPitLead && isSchedulePit);

    if (!canDelete) return const SizedBox.shrink();

    final scheduleId = _asInt(schedule['id']);

    return IconButton(
      tooltip: 'Delete schedule',
      splashRadius: 20,
      color: const Color(0xFF3B82F6),
      onPressed: state.isSaving || scheduleId == null
          ? null
          : () => _confirmDelete(
              scheduleId,
              schedule['team_name']?.toString() ?? 'schedule',
            ),
      icon: const Icon(Icons.delete, size: 20),
    );
  }

  Widget _statusChip(String status) {
    final normalized = status.toLowerCase();

    Color bg;
    Color fg;
    String text;

    switch (normalized) {
      case 'done':
      case 'completed':
        bg = const Color(0xFFDDF5E8);
        fg = const Color(0xFF15803D);
        text = 'completed';
        break;
      case 'cancelled':
        bg = const Color(0xFFFDE2E2);
        fg = const Color(0xFFDC2626);
        text = 'cancelled';
        break;
      case 'archived':
        bg = const Color(0xFFE5E7EB);
        fg = const Color(0xFF6B7280);
        text = 'archived';
        break;
      default:
        bg = const Color(0xFFDCEAFE);
        fg = const Color(0xFF2563EB);
        text = 'scheduled';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildEmptyBoard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.table_chart_outlined,
              size: 44,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 10),
            Text(
              'No schedules found.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EF)),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.maroon),
      ),
    );
  }



  InputDecoration _inputDecoration({String? hintText, Widget? prefixIcon}) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: prefixIcon,
      hintStyle: const TextStyle(color: AppColors.textSecondary),
      filled: true,
      fillColor: const Color(0xFFFBFCFE),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD7DDE8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.maroon),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD7DDE8)),
      ),
    );
  }

  Future<void> _openScheduler() async {
    final user = ref.read(authProvider).user;
    final isAdmin = user?['role'] == 'admin' || user?['is_superuser'] == true;
    final isPitLead = user?['is_pit_lead'] == true;
    if (!isAdmin && !isPitLead) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DefenseSchedulerScreen()),
    );

    if (!mounted) return;
    ref.read(defenseBoardProvider.notifier).fetchBoard();
  }

  Future<void> _confirmDelete(int scheduleId, String teamName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Schedule'),
          content: Text('Delete schedule for $teamName?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;
    await ref.read(defenseBoardProvider.notifier).deleteSchedule(scheduleId);
  }

  String _panelistNames(Map<String, dynamic> schedule) {
    final panelists = schedule['panelists'];
    if (panelists is! List || panelists.isEmpty) {
      return 'No panel assigned';
    }

    return panelists
        .whereType<Map>()
        .map((panelist) => panelist['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .join(', ');
  }

  String _shortTime(dynamic value) {
    final text = value?.toString() ?? '';
    return text.length >= 5 ? text.substring(0, 5) : text;
  }

  String _statusLabel(String status) {
    if (status.isEmpty) return '';
    return status[0].toUpperCase() + status.substring(1);
  }

  int _count(DefenseBoardState state, String key) {
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

  Widget _minutesStatusChip(Map<String, dynamic> schedule) {
    final status = schedule['minutes_status']?.toString();
    final scheduleId = _asInt(schedule['id']);
    if (scheduleId == null || schedule['scope'] != 'capstone') {
      return const Text('-');
    }

    String label = 'No Minutes';
    Color bg = Colors.grey.shade100;
    Color fg = Colors.grey.shade700;

    if (status == 'draft') {
      label = 'Draft';
      bg = const Color(0xFFFFF3CD);
      fg = const Color(0xFF856404);
    } else if (status == 'submitted') {
      label = 'Submitted';
      bg = const Color(0xFFCCE5FF);
      fg = const Color(0xFF004085);
    } else if (status == 'adviser_signed') {
      label = 'Adviser Signed';
      bg = const Color(0xFFE2E3E5);
      fg = const Color(0xFF383D41);
    } else if (status == 'completed') {
      label = 'Completed';
      bg = const Color(0xFFD4EDDA);
      fg = const Color(0xFF155724);
    }

    return InkWell(
      onTap: () {
        setState(() {
          _selectedMinutesScheduleId = scheduleId;
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.open_in_new, size: 10, color: fg),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final int flex;

  const _HeaderCell(this.text, {required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  final Widget child;
  final int flex;

  const _BodyCell({required this.child, required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}

class _SessionGroup {
  final String key;
  final String stageLabel;
  final String scheduledDate;
  final String room;
  final String panelNames;
  final String documenterName;
  final String scope;
  final List<Map<String, dynamic>> schedules;

  _SessionGroup({
    required this.key,
    required this.stageLabel,
    required this.scheduledDate,
    required this.room,
    required this.panelNames,
    required this.documenterName,
    required this.scope,
    required this.schedules,
  });
}

