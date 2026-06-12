import 'package:flutter/material.dart';
import '../admin/widgets/defensys_admin_shell.dart';
import '../../../theme/app_theme.dart';

class PitInstructorDashboardContent extends StatefulWidget {
  final Map<String, dynamic>? data;
  final String facultyName;
  final VoidCallback onOpenDeliverables;

  const PitInstructorDashboardContent({
    super.key,
    required this.data,
    required this.facultyName,
    required this.onOpenDeliverables,
  });

  @override
  State<PitInstructorDashboardContent> createState() => _PitInstructorDashboardContentState();
}

class _PitInstructorDashboardContentState extends State<PitInstructorDashboardContent> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatus = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rawTeams = (widget.data?['pit_teams'] as List?) ?? [];
    final pitTeams = rawTeams.map((t) => Map<String, dynamic>.from(t as Map)).toList();

    // Calculate metrics
    final totalTeams = pitTeams.length;
    final endorsedTeams = pitTeams.where((t) => t['status']?.toString().toLowerCase() == 'approved').length;
    final pendingTeams = totalTeams - endorsedTeams;
    final totalSubmissions = pitTeams.fold<int>(0, (sum, t) => sum + (t['deliverableCount'] as int? ?? 0));

    // Filter teams based on search query and status selection
    final filteredTeams = pitTeams.where((team) {
      final name = team['name']?.toString().toLowerCase() ?? '';
      final project = team['projectTitle']?.toString().toLowerCase() ?? '';
      final matchesSearch = name.contains(_searchQuery) || project.contains(_searchQuery);

      if (_selectedStatus == 'All') return matchesSearch;
      final status = team['status']?.toString().toLowerCase() ?? '';
      if (_selectedStatus == 'Endorsed') {
        return matchesSearch && status == 'approved';
      } else {
        return matchesSearch && status != 'approved';
      }
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DefensysPageHeader(
          icon: Icons.school_outlined,
          title: 'PIT Instructor workspace',
          subtitle: 'Review deliverables and manage pre-defense endorsement for your assigned PIT teams.',
        ),
        const SizedBox(height: 8),
        Text(
          'Welcome, ${widget.facultyName}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 20),

        // Metrics Section
        Row(
          children: [
            Expanded(
              child: _metricCard(
                value: totalTeams.toString(),
                label: 'Assigned Teams',
                icon: Icons.groups_2_rounded,
                iconColor: const Color(0xFF7C3AED),
                iconBackground: const Color(0xFFEDE3FF),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _metricCard(
                value: pendingTeams.toString(),
                label: 'Awaiting Endorsement',
                icon: Icons.pending_actions_rounded,
                iconColor: const Color(0xFFD97706),
                iconBackground: const Color(0xFFFFEDB8),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _metricCard(
                value: endorsedTeams.toString(),
                label: 'Endorsed Teams',
                icon: Icons.verified_outlined,
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
          ],
        ),
        const SizedBox(height: 24),

        // Quick Actions & Teams Header Row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Filter and Teams List
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'My Assigned PIT Teams',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      // Filter Chips
                      Row(
                        children: [
                          _filterChip('All'),
                          const SizedBox(width: 8),
                          _filterChip('Awaiting'),
                          const SizedBox(width: 8),
                          _filterChip('Endorsed'),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Search Bar
                  TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.toLowerCase().trim();
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search team name or project title...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (filteredTeams.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.folder_off_outlined, size: 40, color: Colors.grey),
                            SizedBox(height: 12),
                            Text(
                              'No matching teams found.',
                              style: TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredTeams.length,
                      itemBuilder: (context, index) {
                        final team = filteredTeams[index];
                        return _teamCard(team);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            // Right Column: Quick Shortcuts Panel
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Shortcuts',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _shortcutAction(
                      icon: Icons.folder_open_outlined,
                      label: 'Review Deliverables',
                      subtitle: 'Review uploads & endorse teams',
                      onTap: widget.onOpenDeliverables,
                      iconColor: const Color(0xFF2563EB),
                      iconBackground: const Color(0xFFDCEBFF),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _filterChip(String label) {
    final isSelected = _selectedStatus == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) {
          setState(() {
            _selectedStatus = label;
          });
        }
      },
      selectedColor: AppColors.maroon,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : const Color(0xFF374151),
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shortcutAction({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    required Color iconColor,
    required Color iconBackground,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _teamCard(Map<String, dynamic> team) {
    final status = team['status']?.toString() ?? 'pending';
    final isEndorsed = status.toLowerCase() == 'approved';
    final deliverableCount = team['deliverableCount'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Status Icon indicator
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isEndorsed ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isEndorsed ? Icons.verified_outlined : Icons.pending_actions_rounded,
                color: isEndorsed ? const Color(0xFF047857) : const Color(0xFFD97706),
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        team['name']?.toString() ?? 'Team',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Level Tag
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${team['level'] ?? ''} - ${team['section'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    team['projectTitle']?.toString() ?? 'No Project Title',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF4B5563),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.leaderboard_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Leader: ${team['leaderName'] ?? 'N/A'}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(width: 16),
                      const Icon(Icons.file_present_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '$deliverableCount file(s) submitted',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Action & Status indicator
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isEndorsed ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isEndorsed ? 'Endorsed' : 'Awaiting Review',
                    style: TextStyle(
                      color: isEndorsed ? const Color(0xFF065F46) : const Color(0xFF92400E),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.onOpenDeliverables,
                  icon: const Icon(Icons.folder_open_outlined, size: 14),
                  label: const Text('Deliverables', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.maroon),
                    foregroundColor: AppColors.maroon,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
