import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/auth_provider.dart';
import '../../../../services/defense_board_provider.dart';
import '../../../../theme/app_theme.dart';
import '../defense_scheduler/defense_scheduler_screen.dart';
import '../widgets/defensys_admin_shell.dart';
import '../../../../widgets/feedback/empty_state.dart';
import '../../faculty/minutes_form_screen.dart';

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
                icon: Icons.play_circle_fill_rounded,
                iconColor: const Color(0xFFD97706),
                label: 'Ongoing',
                value: _count(state, 'ongoing'),
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
            const SizedBox(width: 14),
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.access_time_filled,
                iconColor: const Color(0xFF2563EB),
                label: 'Upcoming',
                value: _count(state, 'scheduled'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.play_circle_fill_rounded,
                iconColor: const Color(0xFFD97706),
                label: 'Ongoing',
                value: _count(state, 'ongoing'),
              ),
            ),
            const SizedBox(width: 14),
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(DefenseBoardState state) {
    final showStageOrEventFilter = state.scope.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isStacked = constraints.maxWidth < 950;

          if (isStacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _buildScopeTabs(state),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (showStageOrEventFilter) ...[
                      Expanded(child: _buildStageOrEventDropdown(state, null)),
                      const SizedBox(width: 10),
                    ],
                    Expanded(child: _buildStatusDropdown(state, null)),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSearchField(state, double.infinity),
              ],
            );
          }

          return Row(
            children: [
              _buildScopeTabs(state),
              const SizedBox(width: 16),
              if (showStageOrEventFilter) ...[
                _buildStageOrEventDropdown(state, 160),
                const SizedBox(width: 12),
              ],
              _buildStatusDropdown(state, 160),
              const SizedBox(width: 12),
              Expanded(child: _buildSearchField(state, null)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScopeTabs(DefenseBoardState state) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildScopeTabItem(
            state: state,
            label: 'All Defenses',
            scopeValue: '',
            icon: Icons.grid_view_rounded,
          ),
          _buildScopeTabItem(
            state: state,
            label: 'Capstone',
            scopeValue: 'capstone',
            icon: Icons.school_rounded,
          ),
          _buildScopeTabItem(
            state: state,
            label: 'PIT',
            scopeValue: 'pit',
            icon: Icons.alt_route_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildScopeTabItem({
    required DefenseBoardState state,
    required String label,
    required String scopeValue,
    required IconData icon,
  }) {
    final isSelected = state.scope == scopeValue;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(defenseBoardProvider.notifier).fetchBoard(
                stage: '',
                status: state.status,
                scope: scopeValue,
                search: _searchController.text.trim(),
              );
        },
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected
                ? const [
                    BoxShadow(
                      color: Color(0x0F000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? AppColors.maroon : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? AppColors.maroon : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageOrEventDropdown(DefenseBoardState state, double? width) {
    final isPit = state.scope == 'pit';
    final defaultLabel = isPit ? 'All Events' : 'All Stages';
    final icon = isPit ? Icons.event_rounded : Icons.layers_outlined;

    final Set<String> scopeOptions = {};

    // 1. Gather stage/event labels directly from schedule records matching the selected scope
    for (final schedule in state.schedules) {
      final itemScope = schedule['scope']?.toString() ?? 'capstone';
      final stageLabel = schedule['stage_label']?.toString();
      if (stageLabel != null && stageLabel.isNotEmpty) {
        if (state.scope.isEmpty || itemScope == state.scope) {
          scopeOptions.add(stageLabel);
        }
      }
    }

    // 2. Fallback to state.stageOptions if schedules list is empty
    if (scopeOptions.isEmpty && state.stageOptions.isNotEmpty) {
      scopeOptions.addAll(state.stageOptions);
    }

    final List<String> options = scopeOptions.toList()..sort();
    final currentValue = options.contains(state.stage) ? state.stage : '';

    return SizedBox(
      width: width,
      height: 48,
      child: DropdownButtonFormField<String>(
        key: ValueKey('stage_or_event_${state.scope}'),
        initialValue: currentValue,
        decoration: _inputDecoration(
          prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
        ),
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(12),
        isExpanded: true,
        items: [
          DropdownMenuItem<String>(
            value: '',
            child: Text(
              defaultLabel,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          ...options.map(
            (opt) => DropdownMenuItem<String>(
              value: opt,
              child: Text(
                opt,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
        onChanged: (value) {
          ref.read(defenseBoardProvider.notifier).fetchBoard(
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
        decoration: _inputDecoration(
          prefixIcon: const Icon(Icons.filter_list_rounded, color: AppColors.textSecondary, size: 18),
        ),
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(12),
        isExpanded: true,
        items: [
          const DropdownMenuItem<String>(
            value: '',
            child: Text('All Statuses', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          ...statuses.map(
            (status) => DropdownMenuItem<String>(
              value: status,
              child: Text(_statusLabel(status), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        decoration: _inputDecoration(
          hintText: 'Search team or room...',
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textSecondary),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(defenseBoardProvider.notifier).fetchBoard(
                          stage: state.stage,
                          status: state.status,
                          scope: state.scope,
                          search: '',
                        );
                  },
                )
              : null,
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
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSessionHeader(group),
          const Divider(height: 1, thickness: 1, color: Color(0xFFEDF2F7)),
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

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Scope & Stage Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isPit
                      ? const Color(0xFFE0F2FE)
                      : AppColors.maroon.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isPit
                        ? const Color(0xFFBAE6FD)
                        : AppColors.maroon.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPit ? Icons.alt_route_rounded : Icons.school_rounded,
                      size: 15,
                      color: isPit ? const Color(0xFF0284C7) : AppColors.maroon,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPit ? 'PIT Scope • ${group.stageLabel}' : group.stageLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isPit ? const Color(0xFF0369A1) : AppColors.maroon,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Date Chip
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.textSecondary),
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
              // Room Chip
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.place_rounded, size: 15, color: AppColors.textSecondary),
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
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF2F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${group.schedules.length} ${group.schedules.length == 1 ? 'Team' : 'Teams'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
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
                  const Icon(Icons.people_outline_rounded, size: 16, color: AppColors.textSecondary),
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
                    const Icon(Icons.edit_note_rounded, size: 16, color: AppColors.textSecondary),
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
                      group.documenterName.isNotEmpty ? group.documenterName : 'Unassigned',
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
    final isPit = group.scope == 'pit';

    return Column(
      children: [
        // Sub-table Header
        Container(
          height: 42,
          color: const Color(0xFFF8FAFC),
          child: Row(
            children: [
              const _HeaderCell('Time Slot', flex: 1),
              _HeaderCell('Team & Project Title', flex: isPit ? 6 : 4),
              if (!isPit) const _HeaderCell('Minutes', flex: 2),
              const _HeaderCell('Status', flex: 2),
              const _HeaderCell('Action', flex: 1),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0xFFEDF2F7)),
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
              height: 58,
              child: Row(
                children: [
                  _BodyCell(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
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
                    flex: isPit ? 6 : 4,
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
                  if (!isPit)
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
    final isPit = group.scope == 'pit';

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: group.schedules.map((schedule) {
          final teamName = schedule['team_name']?.toString() ?? 'Unnamed Team';
          final projectTitle = schedule['project_title']?.toString() ?? '';

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
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
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          teamName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
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
                    _statusChip(
                      schedule['display_status']?.toString() ??
                          schedule['status']?.toString() ??
                          '',
                    ),
                    if (!isPit) ...[
                      const SizedBox(width: 8),
                      _minutesStatusChip(schedule),
                    ],
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

    final currentStatus = (schedule['display_status']?.toString() ??
            schedule['status']?.toString() ??
            '')
        .toLowerCase();
    if (['ongoing', 'done', 'completed', 'archived'].contains(currentStatus)) {
      return const SizedBox.shrink();
    }

    final scheduleId = _asInt(schedule['id']);

    return IconButton(
      tooltip: 'Delete schedule',
      splashRadius: 20,
      color: const Color(0xFFEF4444),
      style: IconButton.styleFrom(
        hoverColor: const Color(0xFFFEE2E2),
      ),
      onPressed: state.isSaving || scheduleId == null
          ? null
          : () => _confirmDelete(
              scheduleId,
              schedule['team_name']?.toString() ?? 'schedule',
            ),
      icon: const Icon(Icons.delete_outline_rounded, size: 20),
    );
  }

  Widget _statusChip(String status) {
    final normalized = status.toLowerCase();

    Color bg;
    Color fg;
    IconData iconData;
    String text;

    switch (normalized) {
      case 'ongoing':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        iconData = Icons.play_circle_rounded;
        text = 'ongoing';
        break;
      case 'done':
      case 'completed':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF15803D);
        iconData = Icons.check_circle_rounded;
        text = 'completed';
        break;
      case 'cancelled':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFB91C1C);
        iconData = Icons.cancel_rounded;
        text = 'cancelled';
        break;
      case 'archived':
        bg = const Color(0xFFF3F4F6);
        fg = const Color(0xFF4B5563);
        iconData = Icons.archive_rounded;
        text = 'archived';
        break;
      default:
        bg = const Color(0xFFE0F2FE);
        fg = const Color(0xFF0369A1);
        iconData = Icons.schedule_rounded;
        text = 'scheduled';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
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
      child: DefensysEmptyState(
        icon: Icons.table_chart_outlined,
        title: 'No Defense Schedules Found',
        description:
            'There are no defense hearings matching the selected criteria or active term.',
        size: DefensysEmptyStateSize.standard,
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



  InputDecoration _inputDecoration({String? hintText, Widget? prefixIcon, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
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
      return const SizedBox.shrink();
    }

    String label = 'No Minutes';
    Color bg = const Color(0xFFF1F5F9);
    Color fg = const Color(0xFF64748B);
    IconData icon = Icons.description_outlined;

    if (status == 'draft') {
      label = 'Draft';
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFF92400E);
      icon = Icons.edit_note_rounded;
    } else if (status == 'submitted') {
      label = 'Submitted';
      bg = const Color(0xFFDBEAFE);
      fg = const Color(0xFF1E40AF);
      icon = Icons.send_rounded;
    } else if (status == 'adviser_signed') {
      label = 'Adviser Signed';
      bg = const Color(0xFFF3E8FF);
      fg = const Color(0xFF6B21A8);
      icon = Icons.draw_rounded;
    } else if (status == 'completed') {
      label = 'Completed';
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF15803D);
      icon = Icons.task_alt_rounded;
    }

    return InkWell(
      onTap: () {
        setState(() {
          _selectedMinutesScheduleId = scheduleId;
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.open_in_new_rounded, size: 11, color: fg),
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

