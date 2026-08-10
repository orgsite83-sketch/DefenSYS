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
    final hubTitle = isCapstone ? 'Defense Stages' : 'PIT Events Showcase';
    final hubSubtitle = isCapstone
        ? 'Track Capstone defense stage schedules, submissions, and peer ratings.'
        : 'Track PIT event schedules, deliverable checklists, and peer ratings.';

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
              // Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroon,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: DefensysTokens.maroon.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isCapstone ? Icons.alt_route_rounded : Icons.event_note_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            hubTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        if (stageOptions.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              '${stageOptions.length} ${isCapstone ? "Stage" : "Event"}${stageOptions.length > 1 ? "s" : ""}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hubSubtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Stage / Event Selection Area
              if (delivState.isLoading && stageOptions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(color: DefensysTokens.maroon),
                  ),
                )
              else if (stageOptions.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isCapstone ? Icons.flag_outlined : Icons.event_rounded,
                            size: 18,
                            color: DefensysTokens.maroon,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isCapstone ? 'Defense Stage:' : 'Exhibition Event:',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: DefensysTokens.textPrimary,
                              ),
                            ),
                          ),
                          // Dropdown selector for easy switching when 5+ events exist
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: stageOptions.contains(selectedStage) ? selectedStage : stageOptions.first,
                                isDense: true,
                                icon: const Icon(Icons.arrow_drop_down_rounded, color: DefensysTokens.maroon),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: DefensysTokens.maroon,
                                ),
                                onChanged: (newValue) {
                                  if (newValue != null && newValue != selectedStage) {
                                    ref
                                        .read(capstoneDeliverablesProvider.notifier)
                                        .fetchDeliverables(
                                          scope: isCapstone ? 'capstone' : 'pit',
                                          yearLevel: isCapstone ? null : _studentYearLevel,
                                          selectedStage: newValue,
                                        );
                                  }
                                },
                                items: stageOptions.map<DropdownMenuItem<String>>((String stageName) {
                                  final isCurrentSelected = stageName.trim().toLowerCase() == selectedStage.trim().toLowerCase();
                                  final statusLabel = getStageStatusLabel(stageName);
                                  final badgeColor = statusLabel == 'Current'
                                      ? Colors.green.shade700
                                      : (statusLabel == 'Completed' ? Colors.blue.shade700 : Colors.amber.shade800);

                                  return DropdownMenuItem<String>(
                                    value: stageName,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isCurrentSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                                          size: 14,
                                          color: isCurrentSelected ? DefensysTokens.maroon : Colors.grey,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(stageName),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: badgeColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            statusLabel,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: badgeColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Horizontal Quick Selector Pills
                      SizedBox(
                        height: 38,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: stageOptions.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final stageName = stageOptions[index];
                            final isSelected = stageName.trim().toLowerCase() ==
                                selectedStage.trim().toLowerCase();
                            final statusLabel = getStageStatusLabel(stageName);
                            final dotColor = statusLabel == 'Current'
                                ? Colors.green.shade500
                                : (statusLabel == 'Completed' ? Colors.blue.shade400 : Colors.amber.shade500);

                            return InkWell(
                              onTap: () {
                                if (!isSelected) {
                                  ref
                                      .read(capstoneDeliverablesProvider.notifier)
                                      .fetchDeliverables(
                                        scope: isCapstone ? 'capstone' : 'pit',
                                        yearLevel: isCapstone ? null : _studentYearLevel,
                                        selectedStage: stageName,
                                      );
                                }
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? DefensysTokens.maroon
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? DefensysTokens.maroon
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected ? Colors.white : dotColor,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      stageName,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                        color: isSelected ? Colors.white : DefensysTokens.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white.withValues(alpha: 0.2)
                                            : dotColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        statusLabel,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? Colors.white : dotColor,
                                        ),
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
                const SizedBox(height: 16),
              ],

              // Sub-Tabs: Schedule, Deliverables, Peer Eval (Fixed to fit 100% of screen width)
              Container(
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
                  tabs: const [
                    Tab(
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
                          Icon(Icons.folder_outlined, size: 13),
                          SizedBox(width: 4),
                          Text('Deliverables'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.star_outline_rounded, size: 13),
                          SizedBox(width: 4),
                          Text('Peer Eval'),
                        ],
                      ),
                    ),
                  ],
                ),
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
}
