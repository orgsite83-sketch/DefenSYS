import 'package:flutter/material.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/screens/web/shared/team_deliverables/deliverables_view_types.dart';

int _asInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

class CohortSubmissionsMatrix extends StatelessWidget {
  final List<Map<String, dynamic>> teams;
  final CapstoneDeliverablesState state;
  final bool isAdviser;
  final ValueChanged<int> onSelectTeam;

  const CohortSubmissionsMatrix({
    super.key,
    required this.teams,
    required this.state,
    required this.isAdviser,
    required this.onSelectTeam,
  });

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (teams.isEmpty) {
      return Container(
        decoration: _cardDecoration(),
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text(
              'No teams match the selected filter.',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Try changing your search term or switching the triage filter above.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1050),
          child: SizedBox(
            width: MediaQuery.of(context).size.width.clamp(1050.0, double.infinity),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Table Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
            child: const Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    'TEAM & PROJECT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'CURRENT STAGE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'STAGE DELIVERABLES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'ADVISER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'STATUS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    'ACTIONS',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Rows
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: teams.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
            itemBuilder: (context, index) {
              final team = teams[index];
              final teamId = _asInt(team['id']);
              final name = team['name']?.toString() ?? 'Team';
              final projectTitle = team['project_title']?.toString() ?? 'No Project Title';
              final currentStage = team['current_stage']?.toString() ?? 'Concept Proposal';
              final adviserName = team['adviser_name']?.toString() ?? 'Unassigned';

              final activeStage = DeliverablesTriageHelper.resolveActiveStage(team);
              final reqUploaded = _asInt(activeStage?['required_uploaded']);
              final reqTotal = _asInt(activeStage?['required_total']);
              final isPresentationOnly = activeStage?['is_presentation_only'] == true;
              final isEndorsed = activeStage?['endorsed'] == true;
              final hasPending = DeliverablesTriageHelper.hasPendingReview(team);
              final isMissing = DeliverablesTriageHelper.isOverdueOrMissing(team);

              // Progress bar value
              final progress = reqTotal > 0 ? (reqUploaded / reqTotal).clamp(0.0, 1.0) : (isPresentationOnly ? 1.0 : 0.0);

              return Material(
                color: Colors.white,
                child: InkWell(
                  onTap: () => onSelectTeam(teamId),
                  hoverColor: const Color(0xFFF8FAFC),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        // Team & Project
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
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
                          ),
                        ),
                        // Current Stage
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Text(
                                currentStage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Stage Deliverables Progress
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      isPresentationOnly ? 'Oral Presentation' : '$reqUploaded / $reqTotal Submitted',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: reqTotal > 0 && reqUploaded >= reqTotal
                                            ? const Color(0xFF047857)
                                            : AppColors.textPrimary,
                                      ),
                                    ),
                                    if (hasPending)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEE2E2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Pending',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFB91C1C),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 5,
                                    backgroundColor: const Color(0xFFE2E8F0),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      progress >= 1.0
                                          ? const Color(0xFF10B981)
                                          : (progress > 0 ? AppColors.maroon : const Color(0xFF94A3B8)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Adviser
                        Expanded(
                          flex: 2,
                          child: Row(
                            children: [
                              const Icon(Icons.person_outline, size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  adviserName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Status Pill
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _buildStatusPill(
                              isEndorsed: isEndorsed,
                              hasPending: hasPending,
                              isMissing: isMissing,
                              reqComplete: reqTotal > 0 && reqUploaded >= reqTotal,
                            ),
                          ),
                        ),
                        // Action Button
                        SizedBox(
                          width: 110,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: () => onSelectTeam(teamId),
                              icon: const Icon(Icons.remove_red_eye_outlined, size: 14),
                              label: const Text('Review'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.maroon,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ),
  ),
),
    );
  }

  Widget _buildStatusPill({
    required bool isEndorsed,
    required bool hasPending,
    required bool isMissing,
    required bool reqComplete,
  }) {
    Color bg;
    Color border;
    Color text;
    String label;
    IconData icon;

    if (isEndorsed) {
      bg = const Color(0xFFD1FAE5);
      border = const Color(0xFFA7F3D0);
      text = const Color(0xFF047857);
      label = 'Endorsed';
      icon = Icons.verified_rounded;
    } else if (hasPending) {
      bg = const Color(0xFFFEF3C7);
      border = const Color(0xFFFDE68A);
      text = const Color(0xFFB45309);
      label = 'Needs Review';
      icon = Icons.rate_review_rounded;
    } else if (reqComplete) {
      bg = const Color(0xFFDBEAFE);
      border = const Color(0xFFBFDBFE);
      text = const Color(0xFF1D4ED8);
      label = 'Ready';
      icon = Icons.check_circle_outline_rounded;
    } else if (isMissing) {
      bg = const Color(0xFFFEE2E2);
      border = const Color(0xFFFECACA);
      text = const Color(0xFFB91C1C);
      label = 'Missing Req.';
      icon = Icons.warning_amber_rounded;
    } else {
      bg = const Color(0xFFF1F5F9);
      border = const Color(0xFFCBD5E1);
      text = const Color(0xFF475569);
      label = 'In Progress';
      icon = Icons.hourglass_empty_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: text),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: text,
            ),
          ),
        ],
      ),
    );
  }
}
