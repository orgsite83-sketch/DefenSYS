import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../admin/widgets/defensys_admin_shell.dart';
import '../../../theme/defensys_tokens.dart';

class PitInstructorDashboardContent extends StatefulWidget {
  final Map<String, dynamic>? data;
  final String facultyName;
  final String? yearLevel;
  final VoidCallback onOpenDeliverables;
  final VoidCallback onOpenGrading;

  const PitInstructorDashboardContent({
    super.key,
    required this.data,
    required this.facultyName,
    this.yearLevel,
    required this.onOpenDeliverables,
    required this.onOpenGrading,
  });

  @override
  State<PitInstructorDashboardContent> createState() => _PitInstructorDashboardContentState();
}

class _PitInstructorDashboardContentState extends State<PitInstructorDashboardContent> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatus = 'All';
  String _selectedLevel = 'All';

  static const _line = Color(0xFFF3F4F6);
  static const _ink = DefensysUi.textDark;
  static const _maroon = DefensysUi.primaryMaroon;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rawTeams = (widget.data?['pit_teams'] as List?) ?? [];
    final allPitTeams = rawTeams.map((t) => Map<String, dynamic>.from(t as Map)).toList();
    final pitTeams = widget.yearLevel != null
        ? allPitTeams.where((t) => t['yearLevel']?.toString().toLowerCase() == widget.yearLevel!.toLowerCase()).toList()
        : allPitTeams;

    // Calculate metrics
    final totalTeams = pitTeams.length;
    final endorsedTeams = pitTeams.where((t) => t['status']?.toString().toLowerCase() == 'approved').length;
    final pendingTeams = totalTeams - endorsedTeams;
    final totalSubmissions = pitTeams.fold<int>(0, (sum, t) => sum + (t['deliverableCount'] as int? ?? 0));

    final allStudents = <String>{};
    for (final team in pitTeams) {
      final members = team['members'] as List? ?? [];
      for (final m in members) {
        if (m is Map && m['id'] != null) {
          allStudents.add(m['id'].toString());
        }
      }
    }
    final totalStudentsCount = allStudents.length;

    // Filter options
    final List<String> levels = ['All'];
    for (final team in pitTeams) {
      final lvl = team['level']?.toString() ?? '';
      if (lvl.isNotEmpty && !levels.contains(lvl)) {
        levels.add(lvl);
      }
    }

    final List<String> statuses = ['All'];
    for (final team in pitTeams) {
      final stat = team['status']?.toString() ?? '';
      if (stat.isNotEmpty && !statuses.contains(stat)) {
        statuses.add(stat);
      }
    }

    // Filter teams list
    final filteredTeams = pitTeams.where((team) {
      final name = team['name']?.toString().toLowerCase() ?? '';
      final projectTitle = team['projectTitle']?.toString().toLowerCase() ?? '';
      final matchesSearch = name.contains(_searchQuery.toLowerCase()) ||
          projectTitle.contains(_searchQuery.toLowerCase());

      final status = team['status']?.toString() ?? '';
      final matchesStatus = _selectedStatus == 'All' || status == _selectedStatus;

      final level = team['level']?.toString() ?? '';
      final matchesLevel = _selectedLevel == 'All' || level == _selectedLevel;

      return matchesSearch && matchesStatus && matchesLevel;
    }).toList();

    const titleLabel = 'PIT Instructor workspace';

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DefensysPageHeader(
          icon: Icons.school_outlined,
          title: 'Welcome, ${widget.facultyName}',
          subtitle: '$titleLabel${widget.yearLevel != null ? " — ${widget.yearLevel}" : ""} · ${widget.data?['active_semester'] ?? 'Active Semester'}',
        ),
        const SizedBox(height: 20),

        // Metrics Section
        Row(
          children: [
            Expanded(
              child: _metricCard(
                value: totalTeams.toString(),
                label: 'Assigned PIT Teams',
                icon: Icons.groups_2_rounded,
                iconColor: const Color(0xFF7C3AED),
                iconBackground: const Color(0xFFEDE3FF),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _metricCard(
                value: totalStudentsCount.toString(),
                label: 'Total Students',
                icon: Icons.people_alt_rounded,
                iconColor: const Color(0xFF047857),
                iconBackground: const Color(0xFFCFFAE7),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _metricCard(
                value: totalSubmissions.toString(),
                label: 'Submitted Documents',
                icon: Icons.description_outlined,
                iconColor: const Color(0xFF2563EB),
                iconBackground: const Color(0xFFDCEBFF),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _metricCard(
                value: pendingTeams.toString(),
                label: 'Awaiting Endorsement',
                icon: Icons.pending_actions_rounded,
                iconColor: const Color(0xFFB45309),
                iconBackground: const Color(0xFFFFEDB8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Desktop vs Mobile Layout Grid
        isDesktop
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildTeamsSection(filteredTeams, levels, statuses),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _quickActionsCard(),
                        const SizedBox(height: 20),
                        _teamsOverviewCard(pitTeams),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _quickActionsCard(),
                  const SizedBox(height: 20),
                  _teamsOverviewCard(pitTeams),
                  const SizedBox(height: 20),
                  _buildTeamsSection(filteredTeams, levels, statuses),
                ],
              ),
      ],
    );
  }

  Widget _buildTeamsSection(
    List<Map<String, dynamic>> filteredTeams,
    List<String> levels,
    List<String> statuses,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'My Assigned PIT Teams',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: DefensysUi.textDark,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                filteredTeams.length.toString(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4B5563),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Search & Filters Row
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search teams or project titles...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF6B7280)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _maroon, width: 1.5),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            if (levels.length > 1) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedLevel,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedLevel = val;
                        });
                      }
                    },
                    items: levels.map((lvl) {
                      return DropdownMenuItem<String>(
                        value: lvl,
                        child: Text(
                          lvl == 'All' ? 'All Levels' : lvl,
                          style: const TextStyle(fontSize: 13),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
            if (statuses.length > 1) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedStatus,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedStatus = val;
                        });
                      }
                    },
                    items: statuses.map((status) {
                      return DropdownMenuItem<String>(
                        value: status,
                        child: Text(
                          status == 'All' ? 'All Statuses' : status,
                          style: const TextStyle(fontSize: 13),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // Teams List
        ...filteredTeams.map((team) => _teamCard(team)),
        if (filteredTeams.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 48),
            decoration: DefensysUi.cardDecoration(),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.folder_off_outlined, size: 48, color: Color(0xFFD1D5DB)),
                  SizedBox(height: 16),
                  Text(
                    'No assigned teams found matching criteria.',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _metricCard({
    required String value,
    required String label,
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
  }) {
    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: DefensysUi.cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 20,
                    height: 0.95,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF4B5565),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionsCard() {
    return _dashboardCard(
      title: 'Quick Actions',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            _quickAction(
              icon: Icons.folder_open_outlined,
              iconColor: const Color(0xFF7C3AED),
              iconBackground: const Color(0xFFEDE3FF),
              title: 'PIT Deliverables',
              subtitle: 'Review uploads & progress',
              onTap: widget.onOpenDeliverables,
            ),
            _quickAction(
              icon: Icons.rate_review_rounded,
              iconColor: const Color(0xFF2563EB),
              iconBackground: const Color(0xFFDCEBFF),
              title: 'View Grades',
              subtitle: 'See student final grades',
              onTap: widget.onOpenGrading,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamsOverviewCard(List<Map<String, dynamic>> pitTeams) {
    int approvedCount = 0;
    int pendingCount = 0;
    int delayedCount = 0;
    int failedCount = 0;

    for (final team in pitTeams) {
      final status = team['status']?.toString() ?? 'Pending';
      final statusLower = status.toLowerCase();
      if (statusLower == 'approved') {
        approvedCount++;
      } else if (statusLower == 'failed') {
        failedCount++;
      } else if (statusLower == 'delayed/extended' || statusLower == 'delayed' || statusLower == 'extended') {
        delayedCount++;
      } else {
        pendingCount++;
      }
    }

    final totalCount = pitTeams.length;

    Widget buildStatusRow({
      required String label,
      required int count,
      required Color color,
      required Color progressBgColor,
    }) {
      final double progress = totalCount > 0 ? count / totalCount : 0.0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ],
                ),
                Text(
                  '$count ${count == 1 ? "team" : "teams"}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: progressBgColor,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 6,
              ),
            ),
          ],
        ),
      );
    }

    final stageCounts = <String, int>{};
    for (final team in pitTeams) {
      final stage = team['currentStage']?.toString().trim() ?? '';
      if (stage.isNotEmpty) {
        stageCounts[stage] = (stageCounts[stage] ?? 0) + 1;
      }
    }

    return _dashboardCard(
      title: 'PIT Teams Overview',
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'STATUS DISTRIBUTION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF9CA3AF),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            buildStatusRow(
              label: 'Endorsed',
              count: approvedCount,
              color: const Color(0xFF10B981),
              progressBgColor: const Color(0xFFD1FAE5),
            ),
            buildStatusRow(
              label: 'Awaiting Review',
              count: pendingCount,
              color: const Color(0xFFF59E0B),
              progressBgColor: const Color(0xFFFEF3C7),
            ),
            buildStatusRow(
              label: 'Delayed/Extended',
              count: delayedCount,
              color: const Color(0xFF3B82F6),
              progressBgColor: const Color(0xFFDBEAFE),
            ),
            buildStatusRow(
              label: 'Failed',
              count: failedCount,
              color: const Color(0xFFEF4444),
              progressBgColor: const Color(0xFFFEE2E2),
            ),
            if (stageCounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: _line),
              const SizedBox(height: 16),
              const Text(
                'DEFENSE STAGE DISTRIBUTION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF9CA3AF),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              ...stageCounts.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, size: 16, color: Color(0xFF6B7280)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF374151),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Text(
                          '${entry.value} ${entry.value == 1 ? "team" : "teams"}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dashboardCard({
    required String title,
    required Widget child,
    double? height,
    String? actionLabel,
    VoidCallback? onActionTap,
  }) {
    return Container(
      height: height,
      decoration: DefensysUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (actionLabel != null)
                  InkWell(
                    onTap: onActionTap,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        actionLabel,
                        style: const TextStyle(
                          color: _maroon,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _teamCard(Map<String, dynamic> map) {
    final id = map['id'];
    final name = map['name']?.toString() ?? 'Team';
    final projectTitle = map['projectTitle']?.toString() ?? 'No project title';
    final level = map['level']?.toString() ?? '';
    final section = map['section']?.toString() ?? '';
    final status = map['status']?.toString() ?? 'Pending';
    final currentStage = map['currentStage']?.toString().trim() ?? '';
    final deliverableCount = (map['deliverableCount'] as num?)?.toInt() ?? 0;
    final members = (map['members'] as List?) ?? [];

    // Resolve status color and label
    Color statusBg;
    Color statusText;
    Color statusBorder;

    final statusLower = status.toLowerCase();
    final isEndorsed = statusLower == 'approved';
    final statusLabel = isEndorsed ? 'Endorsed' : 'Awaiting Review';

    switch (statusLower) {
      case 'approved':
        statusBg = DefensysTokens.successBg;
        statusText = DefensysTokens.successText;
        statusBorder = DefensysTokens.successBorder;
        break;
      case 'failed':
        statusBg = DefensysTokens.dangerBg;
        statusText = DefensysTokens.dangerText;
        statusBorder = DefensysTokens.dangerBorder;
        break;
      case 'delayed/extended':
      case 'delayed':
      case 'extended':
        statusBg = DefensysTokens.infoBg;
        statusText = DefensysTokens.infoText;
        statusBorder = DefensysTokens.infoBorder;
        break;
      case 'pending':
      default:
        statusBg = DefensysTokens.warningBg;
        statusText = DefensysTokens.warningText;
        statusBorder = DefensysTokens.warningBorder;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: DefensysUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line)),
            ),
            child: Row(
              children: [
                if (level.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Text(
                      level,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (section.isNotEmpty) ...[
                  Text(
                    section,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    border: Border.all(color: statusBorder),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusText,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Card Body
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: id != null ? () => context.go('/faculty/student-teams/$id') : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _ink,
                              ),
                            ),
                          ),
                          if (id != null)
                            const Icon(
                              Icons.arrow_outward_rounded,
                              size: 16,
                              color: Color(0xFF9CA3AF),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        projectTitle,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF4B5563),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Members List
                const Text(
                  'TEAM MEMBERS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF9CA3AF),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: members.map((m) {
                    final memMap = (m as Map?)?.cast<String, dynamic>() ?? {};
                    final isLeader = memMap['isLeader'] == true;
                    final memName = memMap['name']?.toString() ?? 'Student';

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isLeader ? const Color(0xFFFEF3C7) : const Color(0xFFF9FAFB),
                        border: Border.all(
                          color: isLeader ? const Color(0xFFFDE68A) : const Color(0xFFF3F4F6),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isLeader) ...[
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFD97706),
                              size: 13,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            memName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isLeader ? FontWeight.w700 : FontWeight.w500,
                              color: isLeader ? const Color(0xFF92400E) : const Color(0xFF374151),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),
                const Divider(height: 1, color: _line),
                const SizedBox(height: 16),

                // Details row (deliverables and stage)
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.folder_open_rounded, size: 16, color: Color(0xFF6B7280)),
                          const SizedBox(width: 8),
                          Text(
                            '$deliverableCount Deliverables',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (currentStage.isNotEmpty) ...[
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Icon(Icons.shield_outlined, size: 16, color: Color(0xFF6B7280)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                currentStage,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF1E40AF),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Action Buttons Row
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF9FAFB),
              border: Border(top: BorderSide(color: _line)),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                TextButton.icon(
                  onPressed: widget.onOpenDeliverables,
                  icon: const Icon(Icons.folder_open_outlined, size: 14),
                  label: const Text('Deliverables', style: TextStyle(fontSize: 11.5)),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF4B5563),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.onOpenGrading,
                  icon: const Icon(Icons.rate_review_rounded, size: 14),
                  label: const Text('View Grades', style: TextStyle(fontSize: 11.5)),
                  style: TextButton.styleFrom(
                    foregroundColor: _maroon,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
