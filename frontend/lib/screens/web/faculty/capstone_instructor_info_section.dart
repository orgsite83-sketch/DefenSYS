import 'package:flutter/material.dart';
import '../../../theme/defensys_tokens.dart';
import '../admin/widgets/defensys_admin_shell.dart';

class CapstoneInstructorInfoSection extends StatefulWidget {
  final List<dynamic>? capstoneTeams;
  final List<String>? capstoneYears;

  const CapstoneInstructorInfoSection({
    super.key,
    required this.capstoneTeams,
    this.capstoneYears,
  });

  @override
  State<CapstoneInstructorInfoSection> createState() => _CapstoneInstructorInfoSectionState();
}

class _CapstoneInstructorInfoSectionState extends State<CapstoneInstructorInfoSection> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatus = 'All';

  static const _line = Color(0xFFF3F4F6);
  static const _ink = Color(0xFF111827);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rawTeams = widget.capstoneTeams ?? [];
    final teams = rawTeams.map((t) => Map<String, dynamic>.from(t as Map)).toList();

    if (teams.isEmpty) {
      return const SizedBox.shrink();
    }

    final statuses = <String>['All'];
    for (final t in teams) {
      final stat = t['status']?.toString() ?? '';
      if (stat.isNotEmpty && !statuses.contains(stat)) {
        statuses.add(stat);
      }
    }

    final filteredTeams = teams.where((team) {
      final name = team['name']?.toString().toLowerCase() ?? '';
      final title = team['projectTitle']?.toString().toLowerCase() ?? '';
      final adviser = team['adviserName']?.toString().toLowerCase() ?? '';
      final matchesSearch = name.contains(_searchQuery.toLowerCase()) ||
          title.contains(_searchQuery.toLowerCase()) ||
          adviser.contains(_searchQuery.toLowerCase());

      final status = team['status']?.toString() ?? '';
      final matchesStatus = _selectedStatus == 'All' || status == _selectedStatus;

      return matchesSearch && matchesStatus;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: DefensysUi.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.analytics_outlined,
                      color: Color(0xFF2563EB),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Capstone Teams Overview',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _ink,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: const Text(
                                'INFORMATIONAL VIEW ONLY',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF4B5563),
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Read-only overview of assigned section capstone teams. Capstone teams are managed by their respective Project Advisers.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: _line),
              const SizedBox(height: 16),

              // Search & Filter
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
                        hintText: 'Search capstone teams, project title, or adviser...',
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
                          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
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
              ...filteredTeams.map(_buildInfoTeamCard),

              if (filteredTeams.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  alignment: Alignment.center,
                  child: const Text(
                    'No capstone teams match the criteria.',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13.5),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTeamCard(Map<String, dynamic> team) {
    final name = team['name']?.toString() ?? 'Team';
    final projectTitle = team['projectTitle']?.toString() ?? 'No project title';
    final level = team['level']?.toString() ?? '';
    final section = team['section']?.toString() ?? '';
    final status = team['status']?.toString() ?? 'Pending';
    final adviserName = team['adviserName']?.toString() ?? 'Unassigned';
    final currentStage = team['currentStage']?.toString().trim() ?? '';
    final members = (team['members'] as List?) ?? [];

    Color statusBg = const Color(0xFFFEF3C7);
    Color statusText = const Color(0xFF92400E);
    Color statusBorder = const Color(0xFFFDE68A);

    switch (status.toLowerCase()) {
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
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _ink,
                          ),
                        ),
                        if (level.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFD1D5DB)),
                            ),
                            child: Text(
                              level,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4B5563),
                              ),
                            ),
                          ),
                        ],
                        if (section.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            section,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      projectTitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF374151),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBg,
                  border: Border.all(color: statusBorder),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 15, color: Color(0xFF6B7280)),
              const SizedBox(width: 6),
              Text(
                'Adviser: $adviserName',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4B5563),
                ),
              ),
              if (currentStage.isNotEmpty) ...[
                const Spacer(),
                const Icon(Icons.shield_outlined, size: 14, color: Color(0xFF6B7280)),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    currentStage,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF1E40AF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (members.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: members.map((m) {
                final memMap = (m as Map?)?.cast<String, dynamic>() ?? {};
                final isLeader = memMap['isLeader'] == true;
                final memName = memMap['name']?.toString() ?? 'Student';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isLeader ? const Color(0xFFFEF3C7) : Colors.white,
                    border: Border.all(
                      color: isLeader ? const Color(0xFFFDE68A) : const Color(0xFFE5E7EB),
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLeader) ...[
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFD97706),
                          size: 11,
                        ),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        memName,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isLeader ? FontWeight.w700 : FontWeight.w500,
                          color: isLeader ? const Color(0xFF92400E) : const Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
