import 'package:flutter/material.dart';
import '../../../../../theme/defensys_tokens.dart';

/// An interactive, tactile pipeline position selector that replaces standard dropdowns.
/// Displays connected milestone cards representing sequence order and a live preview strip.
/// Strictly enforces sequence locking for completed milestones.
class PipelinePositionSelector extends StatelessWidget {
  final int selectedPosition;
  final int totalSlots;
  final List<Map<String, dynamic>> existingStages;
  final String currentStageName;
  final bool editing;
  final int? initialOrder;
  final bool isLocked;
  final int minPosition;
  final String? lockReason;
  final ValueChanged<int> onPositionChanged;

  const PipelinePositionSelector({
    super.key,
    required this.selectedPosition,
    required this.totalSlots,
    required this.existingStages,
    required this.currentStageName,
    required this.editing,
    required this.onPositionChanged,
    this.initialOrder,
    this.isLocked = false,
    this.minPosition = 1,
    this.lockReason,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTotal = totalSlots < 1 ? 1 : totalSlots;
    final clampedPos = selectedPosition.clamp(1, effectiveTotal);
    final effectiveStageName = currentStageName.trim().isEmpty
        ? (editing ? 'This Stage' : 'New Stage')
        : currentStageName.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header Row
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.linear_scale_rounded,
              size: 16,
              color: DefensysTokens.maroon,
            ),
            const SizedBox(width: 7),
            const Text(
              'Sequence Position in Pipeline',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: DefensysTokens.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: isLocked
                    ? const Color(0xFFEFF6FF)
                    : DefensysTokens.maroon.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                border: Border.all(
                  color: isLocked
                      ? const Color(0xFFBFDBFE)
                      : DefensysTokens.maroon.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLocked) ...[
                    const Icon(
                      Icons.lock_rounded,
                      size: 11,
                      color: Color(0xFF1D4ED8),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    isLocked
                        ? 'Position $clampedPos (Locked)'
                        : 'Position $clampedPos of $effectiveTotal',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isLocked
                          ? const Color(0xFF1D4ED8)
                          : DefensysTokens.maroon,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          isLocked
              ? 'This stage is completed/finalized for the active semester. Its sequence position is locked.'
              : 'Sets milestone order in the defense lifecycle. Other stages will shift automatically.',
          style: TextStyle(
            fontSize: 11.5,
            color: isLocked ? const Color(0xFF1E40AF) : DefensysTokens.textSecondary,
            height: 1.3,
            fontWeight: isLocked ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        const SizedBox(height: 10),

        // Interactive Pipeline Canvas
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isLocked ? const Color(0xFFF8FAFC) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
            border: Border.all(
              color: isLocked ? const Color(0xFFCBD5E1) : DefensysTokens.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Locked Stage Banner (if stage is locked)
              if (isLocked) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: Color(0xFF1D4ED8),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          lockReason ?? 'Completed stage records are finalized. Sequence cannot be changed.',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Scrollable Milestone Stepper Track
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(effectiveTotal, (index) {
                    final pos = index + 1;
                    final isSelected = pos == clampedPos;
                    final isOriginal = editing && initialOrder == pos;
                    final isSlotDisabled = isLocked || (pos < minPosition);

                    String contextLabel;
                    if (pos == 1) {
                      contextLabel = effectiveTotal == 1 ? 'Only Stage' : 'Start of Pipeline';
                    } else if (pos == effectiveTotal && !editing) {
                      contextLabel = 'End of Pipeline';
                    } else {
                      // Determine preceding stage
                      final prevIndex = pos - 2;
                      if (prevIndex >= 0 && prevIndex < existingStages.length) {
                        final prevLabel = existingStages[prevIndex]['label']?.toString() ?? 'Stage $pos';
                        contextLabel = 'After $prevLabel';
                      } else {
                        contextLabel = 'Position $pos';
                      }
                    }

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildPositionCard(
                          context: context,
                          position: pos,
                          isSelected: isSelected,
                          isOriginal: isOriginal,
                          isSlotDisabled: isSlotDisabled,
                          contextLabel: contextLabel,
                          onTap: isSlotDisabled
                              ? null
                              : () {
                                  if (pos != selectedPosition) {
                                    onPositionChanged(pos);
                                  }
                                },
                        ),
                        if (pos < effectiveTotal)
                          _buildConnector(
                            isPastOrSelected: pos < clampedPos,
                          ),
                      ],
                    );
                  }),
                ),
              ),
              const SizedBox(height: 10),

              // Live Pipeline Flow Breadcrumb Strip
              _buildLivePreview(
                clampedPos: clampedPos,
                effectiveTotal: effectiveTotal,
                stageLabel: effectiveStageName,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPositionCard({
    required BuildContext context,
    required int position,
    required bool isSelected,
    required bool isOriginal,
    required bool isSlotDisabled,
    required String contextLabel,
    required VoidCallback? onTap,
  }) {
    Color cardBg;
    Color borderColor;
    double borderWidth = 1.0;
    List<BoxShadow>? shadows;

    if (isSlotDisabled) {
      cardBg = const Color(0xFFF1F5F9);
      borderColor = const Color(0xFFE2E8F0);
    } else if (isSelected) {
      cardBg = Colors.white;
      borderColor = DefensysTokens.maroon;
      borderWidth = 2.0;
      shadows = [
        BoxShadow(
          color: DefensysTokens.maroon.withValues(alpha: 0.12),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
    } else {
      cardBg = const Color(0xFFF1F5F9);
      borderColor = const Color(0xFFCBD5E1);
    }

    final cardContent = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(minWidth: 125, maxWidth: 165),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
        boxShadow: shadows,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: isSlotDisabled
                      ? const Color(0xFF94A3B8)
                      : (isSelected ? DefensysTokens.maroon : const Color(0xFF64748B)),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$position',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Position $position',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSlotDisabled
                        ? const Color(0xFF64748B)
                        : (isSelected ? DefensysTokens.maroonDark : DefensysTokens.textPrimary),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSlotDisabled && !isSelected)
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 13,
                  color: Color(0xFF94A3B8),
                )
              else if (isOriginal && !isSelected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Current',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                )
              else if (isSelected)
                Icon(
                  isLocked ? Icons.lock_rounded : Icons.check_circle_rounded,
                  size: 14,
                  color: isLocked ? const Color(0xFF1D4ED8) : DefensysTokens.maroon,
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            isSlotDisabled && !isSelected ? 'Locked (Completed)' : contextLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSlotDisabled
                  ? const Color(0xFF94A3B8)
                  : (isSelected ? DefensysTokens.maroon : DefensysTokens.textSecondary),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (isSlotDisabled) {
      return Tooltip(
        message: isLocked
            ? 'Completed stages cannot change sequence order'
            : 'Cannot place before an already completed defense stage',
        child: cardContent,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        hoverColor: DefensysTokens.maroon.withValues(alpha: 0.05),
        child: cardContent,
      ),
    );
  }

  Widget _buildConnector({required bool isPastOrSelected}) {
    return Container(
      width: 22,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 2,
              color: isPastOrSelected ? DefensysTokens.maroon.withValues(alpha: 0.4) : const Color(0xFFCBD5E1),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 14,
            color: isPastOrSelected ? DefensysTokens.maroon.withValues(alpha: 0.6) : const Color(0xFF94A3B8),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePreview({
    required int clampedPos,
    required int effectiveTotal,
    required String stageLabel,
  }) {
    // Generate simulated pipeline list
    final previewList = <String>[];
    final originalIndex = (editing && initialOrder != null) ? initialOrder! - 1 : -1;

    for (int i = 0; i < existingStages.length; i++) {
      if (editing && i == originalIndex) {
        continue; // Exclude original spot while moving
      }
      previewList.add(existingStages[i]['label']?.toString() ?? 'Stage ${i + 1}');
    }

    int insertIdx = clampedPos - 1;
    if (insertIdx < 0) insertIdx = 0;
    if (insertIdx > previewList.length) insertIdx = previewList.length;

    previewList.insert(insertIdx, stageLabel);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.alt_route_rounded,
            size: 13.5,
            color: isLocked ? const Color(0xFF1D4ED8) : DefensysTokens.maroon,
          ),
          const SizedBox(width: 6),
          const Text(
            'Live Pipeline Flow:',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: List.generate(previewList.length, (i) {
                  final name = previewList[i];
                  final isCurrent = i == insertIdx;

                  Color pillBg;
                  Color pillBorder;
                  Color textColor;
                  Color iconColor;

                  if (isCurrent && isLocked) {
                    pillBg = const Color(0xFFEFF6FF);
                    pillBorder = const Color(0xFFBFDBFE);
                    textColor = const Color(0xFF1E40AF);
                    iconColor = const Color(0xFF1D4ED8);
                  } else if (isCurrent) {
                    pillBg = DefensysTokens.maroon.withValues(alpha: 0.1);
                    pillBorder = DefensysTokens.maroonLight;
                    textColor = DefensysTokens.maroonDark;
                    iconColor = DefensysTokens.maroon;
                  } else {
                    pillBg = const Color(0xFFF1F5F9);
                    pillBorder = const Color(0xFFCBD5E1);
                    textColor = DefensysTokens.textPrimary;
                    iconColor = const Color(0xFF64748B);
                  }

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: pillBg,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: pillBorder,
                            width: isCurrent ? 1.2 : 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isCurrent) ...[
                              Icon(
                                isLocked ? Icons.lock_rounded : Icons.stars_rounded,
                                size: 11,
                                color: iconColor,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              '${i + 1}. $name',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (i < previewList.length - 1)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 11,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
