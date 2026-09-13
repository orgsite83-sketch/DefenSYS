import 'package:flutter/material.dart';

import '../../../theme/defensys_tokens.dart';
import 'panelist_models.dart';

class AssignmentsTab extends StatefulWidget {
  final List<TeamData> teams;
  final void Function(int teamIndex) onOpenGradeSheet;
  final Future<void> Function()? onRefresh;

  const AssignmentsTab({
    super.key,
    required this.teams,
    required this.onOpenGradeSheet,
    this.onRefresh,
  });

  @override
  State<AssignmentsTab> createState() => _AssignmentsTabState();
}

class _AssignmentsTabState extends State<AssignmentsTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'pending', 'completed'
  String _scopeFilter = 'all'; // 'all', 'capstone', 'pit'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.teams.isEmpty) {
      return _buildEmptyInitialView();
    }

    // Filter teams while preserving their original indices in widget.teams
    final filteredEntries = <MapEntry<int, TeamData>>[];
    for (var entry in widget.teams.asMap().entries) {
      final t = entry.value;

      // Status filter
      if (_statusFilter == 'pending' && (t.isPosted || t.isLockedByDate)) {
        continue;
      }
      if (_statusFilter == 'completed' && !t.isPosted) {
        continue;
      }

      // Scope filter
      if (_scopeFilter == 'capstone' && t.scope != 'capstone') {
        continue;
      }
      if (_scopeFilter == 'pit' && t.scope != 'pit') {
        continue;
      }

      // Search query filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchName = t.name.toLowerCase().contains(query);
        final matchProject = t.project.toLowerCase().contains(query);
        final matchStage = t.displayStage.toLowerCase().contains(query);
        final matchEvent = t.displayEvent.toLowerCase().contains(query);
        final matchMember = t.members.any((m) => m.toLowerCase().contains(query));
        if (!matchName && !matchProject && !matchStage && !matchEvent && !matchMember) {
          continue;
        }
      }

      filteredEntries.add(entry);
    }

    // Group filtered entries by event/stage
    final groupedEntries = <String, List<MapEntry<int, TeamData>>>{};
    for (var entry in filteredEntries) {
      final key = '${entry.value.displayEvent} • ${entry.value.displayStage}';
      groupedEntries.putIfAbsent(key, () => []).add(entry);
    }

    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _buildHeader(),
        const SizedBox(height: 12),
        _buildWorkloadTriageBar(),
        const SizedBox(height: 12),
        _buildSearchAndFilters(),
        const SizedBox(height: 16),
        if (filteredEntries.isEmpty)
          _buildEmptyFilteredView()
        else
          ...groupedEntries.entries.map((group) {
            return _buildGroupSection(group.key, group.value);
          }),
        const SizedBox(height: 32),
      ],
    );

    if (widget.onRefresh == null) return content;
    return RefreshIndicator(
      color: DefensysTokens.maroon,
      onRefresh: widget.onRefresh!,
      child: content,
    );
  }

  Widget _buildEmptyInitialView() {
    final Widget emptyContent = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        _buildHeader(),
        const SizedBox(height: 64),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.assignment_outlined,
                  size: 48,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Panel Assignments Yet',
                style: TextStyle(
                  color: DefensysTokens.textDark,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "You'll see defense sessions here once you're assigned to an evaluation panel.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.onRefresh == null) return emptyContent;
    return RefreshIndicator(
      color: DefensysTokens.maroon,
      onRefresh: widget.onRefresh!,
      child: emptyContent,
    );
  }

  Widget _buildEmptyFilteredView() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_alt_off_outlined, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'No matching defense assignments',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try adjusting your search query or active filters.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _searchQuery = '';
                _searchController.clear();
                _statusFilter = 'all';
                _scopeFilter = 'all';
              });
            },
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Reset Filters', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: DefensysTokens.maroon,
              side: const BorderSide(color: DefensysTokens.maroon),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final total = widget.teams.length;
    return Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: DefensysTokens.maroon,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'My Panel Assignments',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: DefensysTokens.maroon,
                  letterSpacing: -0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '$total ${total == 1 ? 'defense team' : 'defense teams'} assigned to you',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWorkloadTriageBar() {
    final total = widget.teams.length;
    final completed = widget.teams.where((t) => t.isPosted).length;
    final pending = widget.teams.where((t) => !t.isPosted && !t.isLockedByDate).length;
    final chairCount = widget.teams.where((t) => t.isChair).length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(color: DefensysTokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _triageStatPill(
                  label: 'All Teams',
                  count: total,
                  icon: Icons.list_alt,
                  isActive: _statusFilter == 'all',
                  color: DefensysTokens.textPrimary,
                  onTap: () => setState(() => _statusFilter = 'all'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _triageStatPill(
                  label: 'Needs Grading',
                  count: pending,
                  icon: Icons.edit_note,
                  isActive: _statusFilter == 'pending',
                  color: DefensysTokens.warningText,
                  badgeBg: DefensysTokens.warningBg,
                  onTap: () => setState(() => _statusFilter = 'pending'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _triageStatPill(
                  label: 'Completed',
                  count: completed,
                  icon: Icons.check_circle_outline,
                  isActive: _statusFilter == 'completed',
                  color: DefensysTokens.successText,
                  badgeBg: DefensysTokens.successBg,
                  onTap: () => setState(() => _statusFilter = 'completed'),
                ),
              ),
            ],
          ),
          if (chairCount > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.gavel_rounded, size: 14, color: Color(0xFF92400E)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'You are presiding as Panel Chair for $chairCount ${chairCount == 1 ? 'team' : 'teams'}.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _triageStatPill({
    required String label,
    required int count,
    required IconData icon,
    required bool isActive,
    required Color color,
    Color? badgeBg,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.08) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? color : Colors.grey.shade200,
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? color : Colors.grey.shade700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    final hasCapstone = widget.teams.any((t) => t.scope == 'capstone');
    final hasPit = widget.teams.any((t) => t.scope == 'pit');
    final showScopeFilters = hasCapstone && hasPit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search Input
        Container(
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: InputBorder.none,
              hintText: 'Search team, project, or member...',
              hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
              prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade500),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                          _searchController.clear();
                        });
                      },
                    )
                  : null,
            ),
          ),
        ),

        // Scope Filter Chips if mixed
        if (showScopeFilters) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _scopeFilterChip('All Programs', 'all'),
                const SizedBox(width: 6),
                _scopeFilterChip('Capstone Defenses', 'capstone', color: DefensysTokens.maroon),
                const SizedBox(width: 6),
                _scopeFilterChip('PIT Expos', 'pit', color: const Color(0xFF006666)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _scopeFilterChip(String label, String value, {Color? color}) {
    final isSelected = _scopeFilter == value;
    final activeColor = color ?? DefensysTokens.maroon;

    return FilterChip(
      selected: isSelected,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : Colors.grey.shade800,
      ),
      selectedColor: activeColor,
      backgroundColor: Colors.white,
      checkmarkColor: Colors.white,
      side: BorderSide(
        color: isSelected ? activeColor : Colors.grey.shade300,
        width: 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      onSelected: (_) => setState(() => _scopeFilter = value),
    );
  }

  Widget _buildGroupSection(String title, List<MapEntry<int, TeamData>> entries) {
    final firstTeam = entries.first.value;
    final isCapstone = firstTeam.scope == 'capstone';
    final accentColor = isCapstone ? DefensysTokens.maroon : const Color(0xFF006666);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title Banner
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Row(
              children: [
                Icon(
                  isCapstone ? Icons.school_outlined : Icons.badge_outlined,
                  size: 16,
                  color: accentColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                      letterSpacing: -0.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${entries.length} ${entries.length == 1 ? 'team' : 'teams'}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Team Cards in this Section
          ...entries.map((e) => _buildTimelineCard(e.key, e.value)),
        ],
      ),
    );
  }

  Widget _buildTimelineCard(int originalIndex, TeamData t) {
    final isPosted = t.isPosted;
    final isCapstone = t.scope == 'capstone';
    final isLockedByDate = t.isLockedByDate;
    final accentColor = isCapstone ? DefensysTokens.maroon : const Color(0xFF006666);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        border: Border.all(
          color: isPosted
              ? Colors.grey.shade200
              : accentColor.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 1.5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Time Column Anchor
            Container(
              width: 76,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              decoration: BoxDecoration(
                color: isPosted
                    ? Colors.grey.shade50
                    : accentColor.withValues(alpha: 0.05),
                border: Border(
                  right: BorderSide(
                    color: isPosted ? Colors.grey.shade200 : accentColor.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.access_time_filled,
                    size: 14,
                    color: isPosted ? Colors.grey.shade500 : accentColor,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.formattedTime,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: isPosted ? Colors.grey.shade700 : accentColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      t.displayRoom,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Main Info & Action Area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top Badge Row
                    Row(
                      children: [
                        // Program Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            t.scopeLabel.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),

                        if (t.isChair) ...[
                          const SizedBox(width: 4),
                          _chairBadge(),
                        ],

                        if (t.hasVerdict) ...[
                          const SizedBox(width: 4),
                          _verdictBadge(t.verdict),
                        ],

                        const Spacer(),

                        // Status Pill (Draft vs Posted vs Scheduled)
                        isLockedByDate
                            ? _statusBadge('Scheduled')
                            : _statusBadge(isPosted ? 'Posted' : 'Draft'),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // Team Name & Project
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t.project.isEmpty ? 'No project title specified' : t.project,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Bottom Row: Members Chip + Grade Action Button
                    Row(
                      children: [
                        // Roster button (opens modal)
                        InkWell(
                          onTap: () => _showMembersSheet(t),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.people_outline, size: 13, color: Colors.grey.shade700),
                                const SizedBox(width: 3),
                                Text(
                                  '${t.members.length} Members',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const Spacer(),

                        // Primary Action Button
                        if (isLockedByDate)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_outline, size: 12, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  'Locked',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (isPosted)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.visibility_outlined, size: 13),
                            label: const Text('View Grades', style: TextStyle(fontSize: 11.5)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accentColor,
                              side: BorderSide(color: accentColor.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            onPressed: () => widget.onOpenGradeSheet(originalIndex),
                          )
                        else
                          FilledButton.icon(
                            icon: const Icon(Icons.edit_note, size: 15),
                            label: const Text('Grade Team', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            style: FilledButton.styleFrom(
                              backgroundColor: accentColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            onPressed: () => widget.onOpenGradeSheet(originalIndex),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMembersSheet(TeamData t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Container(
          color: Colors.white,
          child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: t.scope == 'capstone'
                          ? DefensysTokens.maroon
                          : const Color(0xFF006666),
                      child: Text(
                        t.name.split(' ').last[0],
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: DefensysTokens.textDark,
                            ),
                          ),
                          Text(
                            t.project,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Team Members (${t.members.length})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: DefensysTokens.textDark,
                  ),
                ),
                const SizedBox(height: 10),
                if (t.members.isEmpty)
                  Text(
                    'No members listed.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  )
                else
                  ...t.memberDetails.map((m) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(Icons.person_outline, size: 18, color: Colors.grey.shade700),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              m.name,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (m.id.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'ID: ${m.id}',
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
    );
  }

  Widget _chairBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gavel_rounded, size: 10, color: Color(0xFF92400E)),
          SizedBox(width: 2.5),
          Text(
            'CHAIR',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Color(0xFF92400E),
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _verdictBadge(String? verdict) {
    if (verdict == null || verdict.isEmpty) return const SizedBox.shrink();
    final isApproved = verdict == 'approved';
    final isRevisions = verdict == 'approved_with_revisions';
    final isForRedefense = verdict == 'for_redefense';

    final Color color = isApproved
        ? const Color(0xFF10B981)
        : isRevisions
            ? const Color(0xFFD97706)
            : isForRedefense
                ? const Color(0xFFEF4444)
                : Colors.grey;

    final String label = isApproved
        ? 'APPROVED'
        : isRevisions
            ? 'REVISIONS'
            : isForRedefense
                ? 'RE-DEFENSE'
                : verdict.toUpperCase();

    final IconData icon = isApproved
        ? Icons.check_circle
        : isRevisions
            ? Icons.edit_calendar
            : isForRedefense
                ? Icons.replay_rounded
                : Icons.info_outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String label) {
    final isPosted = label == 'Posted';
    final isScheduled = label == 'Scheduled';

    final badgeColor = isPosted
        ? Colors.green.shade700
        : isScheduled
            ? Colors.orange.shade800
            : Colors.amber.shade900;

    final badgeBg = isPosted
        ? Colors.green.shade50
        : isScheduled
            ? Colors.orange.shade50
            : Colors.amber.shade50;

    final displayLabel = isPosted
        ? 'Posted'
        : isScheduled
            ? 'Scheduled'
            : 'Needs Grading';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPosted
                ? Icons.check_circle_outline
                : isScheduled
                    ? Icons.access_time
                    : Icons.edit_note,
            size: 11,
            color: badgeColor,
          ),
          const SizedBox(width: 3),
          Text(
            displayLabel,
            style: TextStyle(
              fontSize: 9.5,
              color: badgeColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
