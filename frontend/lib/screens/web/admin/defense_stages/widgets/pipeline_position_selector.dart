import 'package:flutter/material.dart';
import 'package:defensys/theme/defensys_tokens.dart';

/// Compact position context. Reordering belongs on the main stage sequence.
/// Constructor compatibility keeps the existing create/edit forms small.
class PipelinePositionSelector extends StatelessWidget {
  const PipelinePositionSelector({
    super.key,
    required this.selectedPosition,
    required this.totalSlots,
    required this.existingStages,
    required this.currentStageName,
    required this.onPositionChanged,
    this.editing = false,
    this.initialOrder,
    this.isLocked = false,
    this.minPosition = 1,
    this.lockReason,
  });
  final int selectedPosition, totalSlots, minPosition;
  final List<Map<String, dynamic>> existingStages;
  final String currentStageName;
  final bool editing, isLocked;
  final int? initialOrder;
  final String? lockReason;
  final ValueChanged<int> onPositionChanged;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        Icons.format_list_numbered_rounded,
        size: 17,
        color: DefensysTokens.textSecondaryOf(context),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Position $selectedPosition of $totalSlots',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              isLocked && lockReason != null
                  ? lockReason!
                  : 'Manage the order on the main stage sequence.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: DefensysTokens.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
