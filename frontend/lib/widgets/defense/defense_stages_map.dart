import 'package:flutter/material.dart';
import '../../theme/defensys_tokens.dart';
import '../../services/capstone_deliverables_provider.dart';

/// The existing stage map, shared by the student defense and integration views.
class DefenseStagesMap extends StatelessWidget {
  const DefenseStagesMap({
    super.key,
    required this.stageOptions,
    required this.activeStageName,
    required this.selectedStageName,
    required this.stagesList,
    this.grades,
    this.isCapstone = true,
    required this.onStageSelected,
    this.title,
    this.inferEarlierComplete = true,
  });
  final List<String> stageOptions;
  final String activeStageName, selectedStageName;
  final List<Map<String, dynamic>> stagesList;
  final Map<String, dynamic>? grades;
  final bool isCapstone;
  final ValueChanged<String> onStageSelected;
  final String? title;
  final bool inferEarlierComplete;
  @override
  Widget build(BuildContext context) {
    if (stageOptions.isEmpty) return const SizedBox.shrink();
    final activeStageIdx = stageOptions.indexWhere(
      (s) => s.trim().toLowerCase() == activeStageName.trim().toLowerCase(),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: DefensysTokens.maroonOf(
                          context,
                        ).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(
                        isCapstone
                            ? Icons.alt_route_rounded
                            : Icons.event_available_rounded,
                        size: 16,
                        color: DefensysTokens.maroonTextOf(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title ??
                            (isCapstone
                                ? 'Capstone Defense Stages'
                                : 'Milestone Stages'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: DefensysTokens.textPrimaryOf(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: DefensysTokens.maroonOf(
                    context,
                  ).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Stage ${activeStageIdx >= 0 ? activeStageIdx + 1 : 1} of ${stageOptions.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.maroonTextOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Horizontal Progress Track
          LayoutBuilder(
            builder: (context, constraints) {
              final stepCount = stageOptions.length;

              final track = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(stepCount * 2 - 1, (index) {
                  // Even index: Milestone Node
                  if (index % 2 == 0) {
                    final stageIdx = index ~/ 2;
                    final stageLabel = stageOptions[stageIdx];
                    final normStage = stageLabel.trim().toLowerCase();
                    final normSelected = selectedStageName.trim().toLowerCase();
                    final isSelected = normStage == normSelected;

                    final stageInfo = stagesList.firstWhere(
                      (s) =>
                          s['stage_label']?.toString().trim().toLowerCase() ==
                          normStage,
                      orElse: () => <String, dynamic>{},
                    );

                    final isCleared =
                        stageInfo['is_officially_complete'] == true ||
                        stageInfo['stage_status_detail']?.toString() ==
                            'passed' ||
                        stageInfo['stage_progress_status']?.toString() ==
                            'passed' ||
                        (inferEarlierComplete &&
                            stageIdx < activeStageIdx &&
                            activeStageIdx != -1);

                    final isActive =
                        (stageIdx == activeStageIdx) ||
                        (!isCleared &&
                            (stageIdx == 0 || stageIdx <= activeStageIdx));

                    final hasPendingPost =
                        StudentTaskBadgeHelper.hasPendingPostDeliverables(
                          stageInfo,
                        );
                    final gradeData =
                        (stageInfo['grade'] as Map<String, dynamic>?) ??
                        (stageInfo['grade'] is Map
                            ? Map<String, dynamic>.from(
                                stageInfo['grade'] as Map,
                              )
                            : null);
                    final verdict =
                        gradeData?['verdict']?.toString() ??
                        stageInfo['verdict']?.toString();

                    final isForRedefense = verdict == 'for_redefense';
                    final isRevisionsDue =
                        isCleared &&
                        hasPendingPost &&
                        verdict == 'approved_with_revisions';
                    final isRequirementsDue =
                        isCleared &&
                        hasPendingPost &&
                        !isRevisionsDue &&
                        !isForRedefense;
                    final isStagePassed =
                        isCleared && !hasPendingPost && !isForRedefense;

                    String statusLabel;
                    Color statusColor;
                    IconData? statusIcon;
                    if (isForRedefense) {
                      statusLabel = 'For Re-defense';
                      statusColor = const Color(0xFFDC2626);
                      statusIcon = Icons.replay_rounded;
                    } else if (isRevisionsDue) {
                      statusLabel = 'Revisions Due';
                      statusColor = const Color(0xFFD97706);
                      statusIcon = Icons.pending_actions_rounded;
                    } else if (isRequirementsDue) {
                      statusLabel = 'Requirements Due';
                      statusColor = const Color(0xFF2563EB);
                      statusIcon = Icons.assignment_late_rounded;
                    } else if (isStagePassed) {
                      statusLabel = 'Passed';
                      statusColor = const Color(0xFF15803D);
                      statusIcon = Icons.check_circle_rounded;
                    } else {
                      statusLabel = isActive ? 'Current' : 'Upcoming';
                      statusColor = isActive
                          ? DefensysTokens.maroonOf(context)
                          : const Color(0xFF94A3B8);
                      statusIcon = null;
                    }

                    Color nodeBg;
                    Color nodeBorder;
                    if (isForRedefense) {
                      nodeBg = const Color(0xFFEF4444);
                      nodeBorder = const Color(0xFFDC2626);
                    } else if (isRevisionsDue) {
                      nodeBg = const Color(0xFFF59E0B);
                      nodeBorder = const Color(0xFFD97706);
                    } else if (isRequirementsDue) {
                      nodeBg = const Color(0xFF3B82F6);
                      nodeBorder = const Color(0xFF2563EB);
                    } else if (isStagePassed) {
                      nodeBg = const Color(0xFF16A34A);
                      nodeBorder = const Color(0xFF15803D);
                    } else {
                      nodeBg = isActive
                          ? DefensysTokens.maroonOf(context)
                          : const Color(0xFFF1F5F9);
                      nodeBorder = isActive
                          ? DefensysTokens.maroonOf(context)
                          : const Color(0xFFCBD5E1);
                    }

                    Widget nodeInner;
                    if (isForRedefense) {
                      nodeInner = const Icon(
                        Icons.replay_rounded,
                        size: 18,
                        color: Colors.white,
                      );
                    } else if (isRevisionsDue) {
                      nodeInner = const Icon(
                        Icons.pending_actions_rounded,
                        size: 18,
                        color: Colors.white,
                      );
                    } else if (isRequirementsDue) {
                      nodeInner = const Icon(
                        Icons.upload_file_rounded,
                        size: 18,
                        color: Colors.white,
                      );
                    } else if (isStagePassed) {
                      nodeInner = const Icon(
                        Icons.check_rounded,
                        size: 19,
                        color: Colors.white,
                      );
                    } else if (isActive) {
                      nodeInner = Text(
                        '${stageIdx + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      );
                    } else {
                      nodeInner = Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: DefensysTokens.textSecondaryOf(context),
                      );
                    }

                    return Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: () {
                          onStageSelected(stageLabel);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 2,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Status label
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (statusIcon != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 2),
                                      child: Icon(
                                        statusIcon,
                                        size: 9,
                                        color: statusColor,
                                      ),
                                    ),
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),

                              // Node Circle with Selection Ring
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: nodeBg,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? nodeBorder : nodeBg,
                                    width: isSelected
                                        ? 3.0
                                        : (isActive ? 2.5 : 1.5),
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: nodeBorder.withValues(
                                              alpha: 0.45,
                                            ),
                                            blurRadius: 10,
                                            spreadRadius: 2,
                                          ),
                                        ]
                                      : (isActive
                                            ? [
                                                BoxShadow(
                                                  color:
                                                      DefensysTokens.maroonOf(
                                                        context,
                                                      ).withValues(alpha: 0.35),
                                                  blurRadius: 8,
                                                  spreadRadius: 1,
                                                ),
                                              ]
                                            : (isCleared
                                                  ? [
                                                      BoxShadow(
                                                        color: nodeBorder
                                                            .withValues(
                                                              alpha: 0.25,
                                                            ),
                                                        blurRadius: 6,
                                                        offset: const Offset(
                                                          0,
                                                          2,
                                                        ),
                                                      ),
                                                    ]
                                                  : null)),
                                ),
                                child: Center(child: nodeInner),
                              ),
                              const SizedBox(height: 6),

                              // Stage Title
                              Text(
                                stageLabel,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isSelected
                                      ? FontWeight.w900
                                      : (isActive
                                            ? FontWeight.w800
                                            : (isCleared
                                                  ? FontWeight.w700
                                                  : FontWeight.w600)),
                                  color: isSelected
                                      ? statusColor
                                      : (isActive
                                            ? DefensysTokens.textPrimaryOf(
                                                context,
                                              )
                                            : (isCleared
                                                  ? DefensysTokens.textPrimaryOf(
                                                      context,
                                                    )
                                                  : DefensysTokens.textSecondaryOf(
                                                      context,
                                                    ))),
                                ),
                              ),
                              if (isSelected) ...[
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Viewing',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  } else {
                    // Odd index: Connecting track line
                    final stageBeforeIdx = index ~/ 2;
                    final before = stagesList
                        .where(
                          (row) =>
                              row['stage_label'] ==
                              stageOptions[stageBeforeIdx],
                        )
                        .firstOrNull;
                    final isLineCompleted = inferEarlierComplete
                        ? stageBeforeIdx < activeStageIdx
                        : before?['is_officially_complete'] == true ||
                              before?['stage_progress_status'] == 'passed';

                    return Expanded(
                      flex: 1,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 28),
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: isLineCompleted
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    );
                  }
                }),
              );
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final trackWidth = (stepCount * 4 - 1) / 3 * 96 * (scale > 1 ? scale : 1);
              if (constraints.maxWidth < trackWidth) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: trackWidth, child: track),
                );
              }
              return track;
            },
          ),
        ],
      ),
    );
  }
}
