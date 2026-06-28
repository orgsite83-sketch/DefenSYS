import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/defense_board_provider.dart';
import '../../../theme/app_theme.dart';
import 'defense_scheduler_screen.dart';
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
    final currentValue = state.stageOptions.contains(state.stage)
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
          ...state.stageOptions.map(
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
    final currentValue = state.statuses.contains(state.status)
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
          ...state.statuses.map(
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 1000) {
            return _buildScheduleCards(state);
          }
          return _buildScheduleTable(state);
        },
      ),
    );
  }

  Widget _buildScheduleTable(DefenseBoardState state) {
    return Column(
      children: [
        Container(
          height: 46,
          decoration: const BoxDecoration(
            color: Color(0xFFF3F5F9),
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: const Row(
            children: [
              _HeaderCell('Team', flex: 2),
              _HeaderCell('Stage', flex: 2),
              _HeaderCell('Date', flex: 1),
              _HeaderCell('Time', flex: 1),
              _HeaderCell('Room', flex: 1),
              _HeaderCell('Panel', flex: 2),
              _HeaderCell('Minutes', flex: 1),
              _HeaderCell('Status', flex: 1),
              _HeaderCell('Action', flex: 1),
            ],
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: state.schedules.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, thickness: 1, color: Color(0xFFE9EDF4)),
          itemBuilder: (context, index) {
            final schedule = state.schedules[index];

            return SizedBox(
              height: 58,
              child: Row(
                children: [
                  _BodyCell(
                    flex: 2,
                    child: Text(
                      schedule['team_name']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  _BodyCell(
                    flex: 2,
                    child: Text(schedule['stage_label']?.toString() ?? ''),
                  ),
                  _BodyCell(
                    flex: 1,
                    child: Text(schedule['scheduled_date']?.toString() ?? ''),
                  ),
                  _BodyCell(
                    flex: 1,
                    child: Text(_shortTime(schedule['start_time'])),
                  ),
                  _BodyCell(
                    flex: 1,
                    child: Text(schedule['room']?.toString() ?? ''),
                  ),
                  _BodyCell(
                    flex: 2,
                    child: Text(
                      _panelistNames(schedule),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _BodyCell(
                    flex: 1,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _minutesStatusChip(schedule),
                    ),
                  ),
                  _BodyCell(
                    flex: 1,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _statusChip(schedule['status']?.toString() ?? ''),
                    ),
                  ),
                  _BodyCell(
                    flex: 1,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _deleteAction(state, schedule),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildScheduleCards(DefenseBoardState state) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: state.schedules.map((schedule) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6E8EF)),
              color: const Color(0xFFFCFCFE),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schedule['team_name']?.toString() ?? '',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _infoChip(schedule['stage_label']?.toString() ?? ''),
                    _infoChip(schedule['scheduled_date']?.toString() ?? ''),
                    _infoChip(_shortTime(schedule['start_time'])),
                    _infoChip(schedule['room']?.toString() ?? ''),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Panel: ${_panelistNames(schedule)}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statusChip(schedule['status']?.toString() ?? ''),
                    if (schedule['scope'] == 'capstone') ...[
                      const SizedBox(width: 8),
                      _minutesStatusChip(schedule),
                    ],
                    const Spacer(),
                    _deleteAction(state, schedule),
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

  Widget _infoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
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
