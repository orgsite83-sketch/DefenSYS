import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/capstone_deliverables_provider.dart';
import '../../../services/dashboard_provider.dart';
import '../../../theme/defensys_tokens.dart';
import 'peer_eval_tab.dart';
import 'student_deliverables_tab.dart';

class StudentEventsTab extends ConsumerStatefulWidget {
  final bool isCapstone;
  final Map<String, dynamic>? studentData;

  const StudentEventsTab({
    super.key,
    required this.isCapstone,
    required this.studentData,
  });

  @override
  ConsumerState<StudentEventsTab> createState() => _StudentEventsTabState();
}

class _StudentEventsTabState extends ConsumerState<StudentEventsTab>
    with SingleTickerProviderStateMixin {
  late TabController _subTabController;
  int _activeSubIndex = 0;

  String? get _studentYearLevel {
    final y = widget.studentData?['year_level']?.toString().trim();
    return (y != null && y.isNotEmpty) ? y : null;
  }

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 3, vsync: this);
    _subTabController.addListener(() {
      if (_subTabController.indexIsChanging) {
        setState(() {
          _activeSubIndex = _subTabController.index;
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
            scope: widget.isCapstone ? 'capstone' : 'pit',
            yearLevel: widget.isCapstone ? null : _studentYearLevel,
          );
    });
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
            scope: widget.isCapstone ? 'capstone' : 'pit',
            yearLevel: widget.isCapstone ? null : _studentYearLevel,
          ),
      ref.read(dashboardProvider('student').notifier).fetchDashboardData(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final delivState = ref.watch(capstoneDeliverablesProvider);
    final isCapstone = widget.isCapstone;

    final stageOptions = delivState.stageOptions;
    final selectedStage = delivState.selectedStage;

    final team = widget.studentData?['team'] as Map<String, dynamic>?;
    final scheduleData = widget.studentData?['schedule'] as Map<String, dynamic>? ??
        widget.studentData?['defense_schedule'] as Map<String, dynamic>?;

    final peerEvalAllowed = widget.studentData?['peerEvalEnabled'] == true;
    final teammates = (widget.studentData?['members'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where(
          (m) =>
              m['id']?.toString() !=
              widget.studentData?['student']?['id']?.toString(),
        )
        .toList();
    final peerCriteria = (widget.studentData?['peerCriteria'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final myPeerSubmissions =
        (widget.studentData?['myPeerSubmissions'] as List? ?? [])
            .cast<Map<String, dynamic>>();

    final activeStageName = delivState.teams.firstOrNull?['current_defense_stage']?.toString() ??
        delivState.teams.firstOrNull?['ready_for_stage']?.toString() ??
        (stageOptions.isNotEmpty ? stageOptions.first : '');

    String getStageStatusLabel(String stageName) {
      final normStage = stageName.trim().toLowerCase();
      final normActive = activeStageName.trim().toLowerCase();
      if (normStage == normActive) return 'Current';
      final stageIndex = stageOptions.indexWhere((s) => s.trim().toLowerCase() == normStage);
      final activeIndex = stageOptions.indexWhere((s) => s.trim().toLowerCase() == normActive);
      if (stageIndex != -1 && activeIndex != -1 && stageIndex < activeIndex) {
        return 'Completed';
      }
      return 'Upcoming';
    }

    final isSelectedStageActive = selectedStage.trim().toLowerCase() == activeStageName.trim().toLowerCase();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: RefreshIndicator(
        color: DefensysTokens.maroon,
        onRefresh: _refreshAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stage / Event Selection Area
              if (delivState.isLoading && stageOptions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(color: DefensysTokens.maroon),
                  ),
                )
              else if (stageOptions.isNotEmpty) ...[
                // Ultra-Compact Stage Selector Bar
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _showStagePickerBottomSheet(
                          context,
                          stageOptions,
                          selectedStage,
                          activeStageName,
                          isCapstone,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: DefensysTokens.maroon.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  isCapstone ? Icons.alt_route_rounded : Icons.event_available_rounded,
                                  size: 16,
                                  color: DefensysTokens.maroon,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isCapstone ? 'DEFENSE STAGE' : 'EXHIBITION EVENT',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        letterSpacing: 0.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            selectedStage.isNotEmpty
                                                ? selectedStage
                                                : (stageOptions.firstOrNull ?? 'Select Event'),
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.bold,
                                              color: DefensysTokens.textPrimary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        _buildStatusBadge(getStageStatusLabel(selectedStage)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${stageOptions.length} ${isCapstone ? "Stages" : "Events"}',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: DefensysTokens.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 16,
                                      color: DefensysTokens.textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Contextual Archive Notice Banner (Only shown when viewing past/inactive stages)
                if (!isSelectedStageActive && activeStageName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.history_rounded, size: 16, color: Color(0xFFB45309)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Viewing archive for "$selectedStage"',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF92400E),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
                                  scope: isCapstone ? 'capstone' : 'pit',
                                  yearLevel: isCapstone ? null : _studentYearLevel,
                                  selectedStage: activeStageName,
                                );
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                            ),
                            child: const Text(
                              'Jump to Current',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),
              ],

              // Sub-Tabs: Schedule, Deliverables, Peer Eval (Fixed to fit 100% of screen width)
              Builder(
                builder: (context) {
                  final hasPendingDeliverables = delivState.hasPendingDeliverables;
                  final hasPendingPeer = StudentTaskBadgeHelper.hasPendingPeerEval(widget.studentData);

                  return Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TabBar(
                      controller: _subTabController,
                      isScrollable: false,
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelPadding: EdgeInsets.zero,
                      indicator: BoxDecoration(
                        color: DefensysTokens.maroon,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: DefensysTokens.textSecondary,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
                      padding: const EdgeInsets.all(3),
                      dividerColor: Colors.transparent,
                      tabs: [
                        const Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 13),
                              SizedBox(width: 4),
                              Text('Schedule'),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.folder_outlined, size: 13),
                              const SizedBox(width: 4),
                              const Text('Deliverables'),
                              if (hasPendingDeliverables) ...[
                                const SizedBox(width: 5),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.star_outline_rounded, size: 13),
                              const SizedBox(width: 4),
                              const Text('Peer Eval'),
                              if (hasPendingPeer) ...[
                                const SizedBox(width: 5),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // Active Sub-Tab View
              IndexedStack(
                index: _activeSubIndex,
                children: [
                  // 1. Schedule & Info Card
                  _buildScheduleTab(scheduleData, selectedStage, team),

                  // 2. Deliverables View
                  StudentDeliverablesTab(
                    isCapstone: isCapstone,
                    studentData: widget.studentData,
                    isEmbedded: true,
                    hideHeader: true,
                  ),

                  // 3. Peer Eval View
                  PeerEvalTab(
                    isCapstone: isCapstone,
                    peerEvalAllowed: peerEvalAllowed,
                    teammates: teammates,
                    peerCriteria: peerCriteria,
                    myPeerSubmissions: myPeerSubmissions,
                    studentId: widget.studentData?['student']?['id']?.toString() ?? '',
                    teamId: team?['id']?.toString() ?? '',
                    peerWeight: (widget.studentData?['weights']?['peer'] as num?)?.toInt() ?? 20,
                    onPeerSubmitted: _refreshAll,
                    onRefresh: _refreshAll,
                    isEmbedded: true,
                    hideHistory: !isSelectedStageActive,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleTab(
    Map<String, dynamic>? schedule,
    String stageName,
    Map<String, dynamic>? team,
  ) {
    if (schedule == null || schedule.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Icon(Icons.event_available_outlined, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            Text(
              'No active defense schedule posted for "$stageName" yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Once scheduled by faculty, room assignment and panelists will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    final scheduledDate = schedule['scheduled_date']?.toString() ?? '—';
    final startTime = schedule['start_time']?.toString() ?? '—';
    final room = schedule['room']?.toString() ?? 'TBD';
    final panelists = schedule['panelists'] as List? ?? [];
    final documenter = schedule['documenter'] as Map? ?? {};

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.event_seat_rounded, color: DefensysTokens.maroon, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Defense Schedule for $stageName',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: DefensysTokens.textPrimary,
                      ),
                    ),
                    Text(
                      team?['name']?.toString() ?? 'Team',
                      style: const TextStyle(
                        fontSize: 12,
                        color: DefensysTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: Color(0xFFE2E8F0)),

          // Info Rows
          _scheduleMetaRow(Icons.calendar_month_outlined, 'Date & Time', '$scheduledDate at $startTime'),
          const SizedBox(height: 10),
          _scheduleMetaRow(Icons.location_on_outlined, 'Room / Venue', room),

          if (panelists.isNotEmpty) ...[
            const SizedBox(height: 10),
            _scheduleMetaRow(
              Icons.people_outline_rounded,
              'Defense Panelists',
              panelists.map((p) => p['name'] ?? p['username'] ?? 'Panelist').join(', '),
            ),
          ],

          if (documenter.isNotEmpty) ...[
            const SizedBox(height: 10),
            _scheduleMetaRow(
              Icons.edit_note_rounded,
              'Assigned Documenter',
              documenter['name']?.toString() ?? documenter['username']?.toString() ?? '—',
            ),
          ],
        ],
      ),
    );
  }

  Widget _scheduleMetaRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: DefensysTokens.maroon),
        const SizedBox(width: 10),
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String statusLabel) {
    Color badgeBg;
    Color badgeTextColor;
    IconData? statusIcon;

    if (statusLabel == 'Current') {
      badgeBg = Colors.green.shade50;
      badgeTextColor = Colors.green.shade700;
      statusIcon = Icons.bolt_rounded;
    } else if (statusLabel == 'Completed') {
      badgeBg = Colors.blue.shade50;
      badgeTextColor = Colors.blue.shade700;
      statusIcon = Icons.check_rounded;
    } else {
      badgeBg = Colors.amber.shade50;
      badgeTextColor = Colors.amber.shade800;
      statusIcon = Icons.lock_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: badgeTextColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 11, color: badgeTextColor),
          const SizedBox(width: 2),
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: badgeTextColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showStagePickerBottomSheet(
    BuildContext context,
    List<String> stageOptions,
    String selectedStage,
    String activeStageName,
    bool isCapstone,
  ) {
    String getStatus(String stageName) {
      final normStage = stageName.trim().toLowerCase();
      final normActive = activeStageName.trim().toLowerCase();
      if (normStage == normActive) return 'Current';
      final stageIndex = stageOptions.indexWhere((s) => s.trim().toLowerCase() == normStage);
      final activeIndex = stageOptions.indexWhere((s) => s.trim().toLowerCase() == normActive);
      if (stageIndex != -1 && activeIndex != -1 && stageIndex < activeIndex) {
        return 'Completed';
      }
      return 'Upcoming';
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: DefensysTokens.maroon.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isCapstone ? Icons.alt_route_rounded : Icons.event_available_rounded,
                        color: DefensysTokens.maroon,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isCapstone ? 'Select Defense Stage' : 'Select Exhibition Event',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: DefensysTokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Switch milestone to review past or active requirements.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24, color: Color(0xFFE2E8F0)),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: stageOptions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final stageName = stageOptions[index];
                      final isSelected = stageName.trim().toLowerCase() == selectedStage.trim().toLowerCase();
                      final statusLabel = getStatus(stageName);

                      Color badgeBg;
                      Color badgeTextColor;
                      IconData statusIcon;

                      if (statusLabel == 'Current') {
                        badgeBg = Colors.green.shade50;
                        badgeTextColor = Colors.green.shade700;
                        statusIcon = Icons.bolt_rounded;
                      } else if (statusLabel == 'Completed') {
                        badgeBg = Colors.blue.shade50;
                        badgeTextColor = Colors.blue.shade700;
                        statusIcon = Icons.check_circle_outline_rounded;
                      } else {
                        badgeBg = Colors.amber.shade50;
                        badgeTextColor = Colors.amber.shade800;
                        statusIcon = Icons.lock_outline_rounded;
                      }

                      return InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          if (!isSelected) {
                            ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
                                  scope: isCapstone ? 'capstone' : 'pit',
                                  yearLevel: isCapstone ? null : _studentYearLevel,
                                  selectedStage: stageName,
                                );
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? DefensysTokens.maroon.withValues(alpha: 0.05)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? DefensysTokens.maroon
                                  : const Color(0xFFE2E8F0),
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? DefensysTokens.maroon
                                      : const Color(0xFFE2E8F0),
                                ),
                                child: Center(
                                  child: isSelected
                                      ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                                      : Text(
                                          '${index + 1}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      stageName,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                        color: isSelected ? DefensysTokens.maroon : DefensysTokens.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      statusLabel == 'Current'
                                          ? 'Active milestone submissions'
                                          : (statusLabel == 'Completed' ? 'Passed milestone archive' : 'Upcoming milestone'),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: badgeTextColor.withValues(alpha: 0.2)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(statusIcon, size: 12, color: badgeTextColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      statusLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: badgeTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
