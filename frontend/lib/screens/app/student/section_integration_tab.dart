import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/defensys_tokens.dart';
import '../../../services/student_teams_provider.dart';
import '../../../services/dashboard_provider.dart';

class SectionIntegrationTab extends ConsumerStatefulWidget {
  final Map<String, dynamic> studentData;

  const SectionIntegrationTab({
    super.key,
    required this.studentData,
  });

  @override
  ConsumerState<SectionIntegrationTab> createState() =>
      _SectionIntegrationTabState();
}

class _SectionIntegrationTabState extends ConsumerState<SectionIntegrationTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(studentTeamsProvider.notifier).fetchTeams();
    });
  }

  @override
  Widget build(BuildContext context) {
    final teamsState = ref.watch(studentTeamsProvider);
    final userSection = widget.studentData['student']?['managed_section'] ??
        widget.studentData['team']?['section'] ??
        '';

    final systemName = widget.studentData['team']?['system_name'] ??
        widget.studentData['student']?['system_name'] ??
        'Unified System';

    // Filter teams to only show teams in the same section
    final sectionTeams = teamsState.teams.where((t) {
      final tSec = t['section']?.toString() ?? '';
      return tSec.isNotEmpty && tSec.toLowerCase() == userSection.toLowerCase();
    }).toList();

    return RefreshIndicator(
      color: DefensysTokens.maroon,
      onRefresh: () async {
        await Future.wait([
          ref.read(studentTeamsProvider.notifier).fetchTeams(),
          ref.read(dashboardProvider('student').notifier).fetchDashboardData(),
        ]);
      },
      child: teamsState.isLoading && sectionTeams.isEmpty
          ? const Center(child: CircularProgressIndicator(color: DefensysTokens.maroon))
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // System Header Card
                  Card(
                    color: const Color(0xFFF0FDF4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFBBF7D0)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.hub_rounded, color: Color(0xFF16A34A), size: 24),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  systemName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF14532D),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Section: $userSection · Project Manager Workspace',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF166534),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _sectionHeader('Modules Integration'),
                  const SizedBox(height: 12),
                  if (sectionTeams.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No other modules found in this section.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: sectionTeams.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final team = sectionTeams[index];
                        final isOwnTeam = team['id']?.toString() ==
                            widget.studentData['team']?['id']?.toString();

                        final defContext = team['defense_context'] as Map<String, dynamic>?;
                        final eventLabel = defContext?['event_label'] ?? 'Not scheduled';
                        final scheduledDate = defContext?['scheduled_date'] ?? '';

                        final leadName = team['leader_name'] ?? 'No Leader';
                        final moduleName = team['project_title'] ?? 'General';

                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: isOwnTeam
                                ? const BorderSide(color: DefensysTokens.maroon, width: 1.5)
                                : BorderSide(color: Colors.grey.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        moduleName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    if (isOwnTeam)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: DefensysTokens.maroon.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          'Your Module',
                                          style: TextStyle(
                                            color: DefensysTokens.maroon,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Team: ${team['name'] ?? ''} · Lead: $leadName',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const Divider(height: 20),
                                Row(
                                  children: [
                                    const Icon(Icons.event_note, size: 14, color: Colors.grey),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        scheduledDate.isNotEmpty
                                            ? '$eventLabel ($scheduledDate)'
                                            : eventLabel,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: scheduledDate.isNotEmpty ? Colors.black87 : Colors.grey,
                                          fontWeight: scheduledDate.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.description_outlined, size: 14, color: Colors.grey),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Deliverables Uploaded: ${team['deliverable_count'] ?? 0}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: DefensysTokens.maroon,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: DefensysTokens.maroon,
          ),
        ),
      ],
    );
  }
}
