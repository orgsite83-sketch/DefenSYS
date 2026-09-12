import 'package:flutter/material.dart';
import '../../../../../theme/defensys_tokens.dart';

/// An interactive, tactile drag-and-drop pipeline sequence selector.
///
/// Features:
/// 1. Real stage names on all cards instead of abstract numbered boxes.
/// 2. Tactile drag-and-drop: pick up the active stage and drop it anywhere along the pipeline.
/// 3. Visual drop zones with clear feedback for allowed slots vs locked completed milestones.
/// 4. Quick nudge arrows (◀ Move Earlier / Move Later ▶) for effortless 1-click repositioning.
/// 5. Direct click-to-place on any unlocked slot.
/// 6. Live pipeline sequence breadcrumb preview.
class PipelinePositionSelector extends StatefulWidget {
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
  State<PipelinePositionSelector> createState() => _PipelinePositionSelectorState();
}

class _PipelinePositionSelectorState extends State<PipelinePositionSelector> {
  int? _hoveredDropTarget;
  bool _isDragging = false;

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  /// Extracts other stages excluding the stage currently being edited
  List<Map<String, dynamic>> _getOtherStages() {
    if (!widget.editing) {
      return List<Map<String, dynamic>>.from(widget.existingStages);
    }

    final others = <Map<String, dynamic>>[];
    final initial = widget.initialOrder;

    for (int i = 0; i < widget.existingStages.length; i++) {
      final s = widget.existingStages[i];
      final order = _asInt(s['display_order']) ?? (i + 1);
      if (initial != null && order == initial) {
        continue; // Skip the stage being edited
      }
      others.add(s);
    }

    // Safety fallback: if initial wasn't matched, remove based on initialOrder index
    if (others.length == widget.existingStages.length && widget.existingStages.isNotEmpty) {
      final idx = ((initial ?? 1) - 1).clamp(0, widget.existingStages.length - 1);
      others.removeAt(idx);
    }

    return others;
  }

  /// Builds the simulated sequence of stage objects reflecting the currently selected position
  List<Map<String, dynamic>> _buildPipelineSequence({
    required List<Map<String, dynamic>> otherStages,
    required int clampedPos,
    required String activeStageName,
  }) {
    final sequence = <Map<String, dynamic>>[];
    final insertIdx = (clampedPos - 1).clamp(0, otherStages.length);

    for (int i = 0; i < insertIdx; i++) {
      sequence.add(otherStages[i]);
    }

    // Current active/draggable stage
    sequence.add({
      '_isCurrentStage': true,
      'label': activeStageName,
      'display_order': clampedPos,
      'is_locked': widget.isLocked,
    });

    for (int i = insertIdx; i < otherStages.length; i++) {
      sequence.add(otherStages[i]);
    }

    return sequence;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTotal = widget.totalSlots < 1 ? 1 : widget.totalSlots;
    final clampedPos = widget.selectedPosition.clamp(1, effectiveTotal);
    final effectiveStageName = widget.currentStageName.trim().isEmpty
        ? (widget.editing ? 'This Stage' : 'New Stage')
        : widget.currentStageName.trim();

    final otherStages = _getOtherStages();
    final sequence = _buildPipelineSequence(
      otherStages: otherStages,
      clampedPos: clampedPos,
      activeStageName: effectiveStageName,
    );

    final canMoveEarlier = !widget.isLocked && clampedPos > widget.minPosition;
    final canMoveLater = !widget.isLocked && clampedPos < effectiveTotal;

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
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
              decoration: BoxDecoration(
                color: widget.isLocked
                    ? const Color(0xFFEFF6FF)
                    : DefensysTokens.maroon.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
                border: Border.all(
                  color: widget.isLocked
                      ? const Color(0xFFBFDBFE)
                      : DefensysTokens.maroon.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isLocked) ...[
                    const Icon(
                      Icons.lock_rounded,
                      size: 11,
                      color: Color(0xFF1D4ED8),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    widget.isLocked
                        ? 'Position $clampedPos (Locked)'
                        : 'Position $clampedPos of $effectiveTotal',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: widget.isLocked
                          ? const Color(0xFF1D4ED8)
                          : DefensysTokens.maroon,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),

        // Interactive Guide / Status Bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.isLocked ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isLocked ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.isLocked ? Icons.lock_outline_rounded : Icons.touch_app_rounded,
                size: 13.5,
                color: widget.isLocked ? const Color(0xFF1D4ED8) : DefensysTokens.maroon,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.isLocked
                      ? (widget.lockReason ??
                          'This stage is finalized for the active semester. Its sequence position cannot be moved.')
                      : 'Drag the highlighted stage card, click any target slot, or use ◀ ▶ arrows to reposition.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: widget.isLocked ? FontWeight.w600 : FontWeight.w500,
                    color: widget.isLocked ? const Color(0xFF1E40AF) : DefensysTokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Interactive Pipeline Canvas
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
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
              // Horizontal Drag & Drop Milestone Track
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Start of pipeline drop zone (Slot 1) if not slot 1
                    if (clampedPos > 1) ...[
                      _buildSlotDropTarget(
                        targetSlot: 1,
                        isLockedSlot: 1 < widget.minPosition,
                        lockedMessage: 'Cannot place before completed milestone',
                      ),
                      _buildConnector(isPast: false),
                    ],

                    // Render all stages in sequence order
                    for (int i = 0; i < sequence.length; i++) ...[
                      Builder(
                        builder: (context) {
                          final slotPos = i + 1;
                          final item = sequence[i];
                          final isCurrent = item['_isCurrentStage'] == true;

                          if (isCurrent) {
                            return _buildCurrentDraggableStageCard(
                              position: slotPos,
                              stageName: effectiveStageName,
                              totalSlots: effectiveTotal,
                              canMoveEarlier: canMoveEarlier,
                              canMoveLater: canMoveLater,
                            );
                          } else {
                            final isItemLocked = item['is_locked'] == true ||
                                item['status'] == 'locked' ||
                                slotPos < widget.minPosition;

                            return _buildOtherStageNode(
                              position: slotPos,
                              stageData: item,
                              isItemLocked: isItemLocked,
                              targetSlot: slotPos,
                            );
                          }
                        },
                      ),

                      // Connector / Drop zone between stages
                      if (i < sequence.length - 1)
                        _buildConnector(
                          isPast: (i + 1) < clampedPos,
                        ),
                    ],

                    // End of pipeline drop zone if not already at end
                    if (clampedPos < effectiveTotal) ...[
                      _buildConnector(isPast: false),
                      _buildSlotDropTarget(
                        targetSlot: effectiveTotal,
                        isLockedSlot: false,
                        isEndZone: true,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Live Pipeline Flow Breadcrumb Strip
              _buildLivePreviewStrip(
                sequence: sequence,
                clampedPos: clampedPos,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds the current active stage as a prominent, tactile draggable card with grab handle and nudge buttons
  Widget _buildCurrentDraggableStageCard({
    required int position,
    required String stageName,
    required int totalSlots,
    required bool canMoveEarlier,
    required bool canMoveLater,
  }) {
    final cardWidget = Container(
      constraints: const BoxConstraints(minWidth: 175, maxWidth: 215),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DefensysTokens.maroon,
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: DefensysTokens.maroon.withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Drag handle + Badge + Step Number
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: DefensysTokens.maroon,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$position',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: DefensysTokens.maroon.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.editing ? 'Active Stage' : 'New Stage (Draft)',
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.maroonDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (!widget.isLocked) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Click & drag to reorder position in pipeline',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.drag_indicator_rounded,
                        size: 15,
                        color: DefensysTokens.maroon,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),

          // Stage Title
          Text(
            stageName,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: DefensysTokens.textPrimary,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            'Position $position of $totalSlots',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.maroon,
            ),
          ),
          const SizedBox(height: 8),

          // Quick 1-Click Nudge Controls (◀ Move Earlier / Move Later ▶)
          if (!widget.isLocked) ...[
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: canMoveEarlier
                          ? 'Move Earlier (Position ${position - 1})'
                          : 'Cannot move earlier (locked or at start)',
                      child: InkWell(
                        onTap: canMoveEarlier
                            ? () => widget.onPositionChanged(position - 1)
                            : null,
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.arrow_back_rounded,
                                size: 11,
                                color: canMoveEarlier ? DefensysTokens.maroon : const Color(0xFFCBD5E1),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'Earlier',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: canMoveEarlier ? DefensysTokens.maroonDark : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 16, color: const Color(0xFFE2E8F0)),
                  Expanded(
                    child: Tooltip(
                      message: canMoveLater
                          ? 'Move Later (Position ${position + 1})'
                          : 'Already at end of pipeline',
                      child: InkWell(
                        onTap: canMoveLater
                            ? () => widget.onPositionChanged(position + 1)
                            : null,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Later',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: canMoveLater ? DefensysTokens.maroonDark : const Color(0xFF94A3B8),
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 11,
                                color: canMoveLater ? DefensysTokens.maroon : const Color(0xFFCBD5E1),
                              ),
                            ],
                          ),
                        ),
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

    if (widget.isLocked) {
      return cardWidget;
    }

    return Draggable<int>(
      data: position,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => setState(() => _isDragging = true),
      onDragEnd: (_) => setState(() {
        _isDragging = false;
        _hoveredDropTarget = null;
      }),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(minWidth: 175, maxWidth: 215),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DefensysTokens.maroon, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: DefensysTokens.maroon.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: DefensysTokens.maroon,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.drag_indicator_rounded, size: 14, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stageName,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: DefensysTokens.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Text(
                      'Drop into desired slot...',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.maroon,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Container(
        constraints: const BoxConstraints(minWidth: 165, maxWidth: 200),
        height: 100,
        decoration: BoxDecoration(
          color: DefensysTokens.maroon.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: DefensysTokens.maroon.withValues(alpha: 0.3),
            style: BorderStyle.solid,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            'Slot $position (Current)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: DefensysTokens.maroon.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
      child: cardWidget,
    );
  }

  /// Builds cards for other stages along the pipeline, serving also as drop targets and clickable positions
  Widget _buildOtherStageNode({
    required int position,
    required Map<String, dynamic> stageData,
    required bool isItemLocked,
    required int targetSlot,
  }) {
    final label = stageData['label']?.toString() ?? 'Stage $position';
    final isHovered = _hoveredDropTarget == targetSlot;
    final isDropCandidate = _isDragging && !isItemLocked && targetSlot >= widget.minPosition;

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 175),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: isHovered
            ? DefensysTokens.maroon.withValues(alpha: 0.08)
            : (isItemLocked
                ? const Color(0xFFF1F5F9)
                : (isDropCandidate
                    ? DefensysTokens.maroon.withValues(alpha: 0.03)
                    : const Color(0xFFF8FAFC))),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHovered
              ? DefensysTokens.maroon
              : (isItemLocked
                  ? const Color(0xFFCBD5E1)
                  : (isDropCandidate
                      ? DefensysTokens.maroon.withValues(alpha: 0.4)
                      : const Color(0xFFE2E8F0))),
          width: isHovered ? 2.0 : (isDropCandidate ? 1.4 : 1.0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 19,
                height: 19,
                decoration: BoxDecoration(
                  color: isItemLocked
                      ? const Color(0xFF94A3B8)
                      : (isHovered ? DefensysTokens.maroon : const Color(0xFF64748B)),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$position',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
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
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isItemLocked ? const Color(0xFF64748B) : DefensysTokens.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isItemLocked)
                const Icon(
                  Icons.lock_rounded,
                  size: 12.5,
                  color: Color(0xFF94A3B8),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isItemLocked ? const Color(0xFF475569) : DefensysTokens.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            isItemLocked
                ? 'Locked (Completed)'
                : (isHovered ? 'Release to place here' : 'Click or drop to place here'),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: isHovered ? FontWeight.w700 : FontWeight.w500,
              color: isHovered
                  ? DefensysTokens.maroon
                  : (isItemLocked ? const Color(0xFF94A3B8) : DefensysTokens.textSecondary),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    // If item is locked, user cannot drop or click on it
    if (isItemLocked) {
      return Tooltip(
        message: 'Completed stage is finalized. Cannot place before or replace this position.',
        child: content,
      );
    }

    // Unlocked stage: can receive drop and can be clicked
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) {
        final canAccept = targetSlot >= widget.minPosition && !widget.isLocked;
        if (canAccept && _hoveredDropTarget != targetSlot) {
          setState(() => _hoveredDropTarget = targetSlot);
        }
        return canAccept;
      },
      onLeave: (_) {
        if (_hoveredDropTarget == targetSlot) {
          setState(() => _hoveredDropTarget = null);
        }
      },
      onAcceptWithDetails: (details) {
        setState(() => _hoveredDropTarget = null);
        if (targetSlot != widget.selectedPosition) {
          widget.onPositionChanged(targetSlot);
        }
      },
      builder: (context, candidateData, rejectedData) {
        return Tooltip(
          message: 'Click or drop to place "${widget.currentStageName.trim().isEmpty ? "this stage" : widget.currentStageName.trim()}" at Position $targetSlot',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.isLocked
                  ? null
                  : () {
                      if (targetSlot != widget.selectedPosition) {
                        widget.onPositionChanged(targetSlot);
                      }
                    },
              borderRadius: BorderRadius.circular(8),
              hoverColor: DefensysTokens.maroon.withValues(alpha: 0.05),
              child: content,
            ),
          ),
        );
      },
    );
  }

  /// Builds dedicated drop zone targets at the beginning or end of the track
  Widget _buildSlotDropTarget({
    required int targetSlot,
    required bool isLockedSlot,
    String? lockedMessage,
    bool isEndZone = false,
  }) {
    final isHovered = _hoveredDropTarget == targetSlot;
    final isDropCandidate = _isDragging && !isLockedSlot && targetSlot >= widget.minPosition;

    final targetBox = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      constraints: const BoxConstraints(minWidth: 105, maxWidth: 135),
      decoration: BoxDecoration(
        color: isLockedSlot
            ? const Color(0xFFF1F5F9)
            : (isHovered
                ? DefensysTokens.maroon.withValues(alpha: 0.1)
                : (isDropCandidate
                    ? DefensysTokens.maroon.withValues(alpha: 0.04)
                    : const Color(0xFFF8FAFC))),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLockedSlot
              ? const Color(0xFFCBD5E1)
              : (isHovered
                  ? DefensysTokens.maroon
                  : (isDropCandidate
                      ? DefensysTokens.maroon.withValues(alpha: 0.45)
                      : const Color(0xFFCBD5E1))),
          style: BorderStyle.solid,
          width: isHovered ? 2.0 : (isDropCandidate ? 1.4 : 1.0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLockedSlot
                ? Icons.lock_outline_rounded
                : (isHovered ? Icons.add_circle_rounded : Icons.move_to_inbox_rounded),
            size: 16,
            color: isLockedSlot
                ? const Color(0xFF94A3B8)
                : (isHovered ? DefensysTokens.maroon : const Color(0xFF64748B)),
          ),
          const SizedBox(height: 3),
          Text(
            isEndZone ? 'End of Pipeline' : 'Start of Pipeline',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isLockedSlot
                  ? const Color(0xFF94A3B8)
                  : (isHovered ? DefensysTokens.maroon : DefensysTokens.textPrimary),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            isLockedSlot ? 'Locked' : 'Slot $targetSlot',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isLockedSlot ? const Color(0xFF94A3B8) : DefensysTokens.textSecondary,
            ),
          ),
        ],
      ),
    );

    if (isLockedSlot) {
      return Tooltip(
        message: lockedMessage ?? 'Cannot place before completed milestone',
        child: targetBox,
      );
    }

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) {
        final canAccept = targetSlot >= widget.minPosition && !widget.isLocked;
        if (canAccept && _hoveredDropTarget != targetSlot) {
          setState(() => _hoveredDropTarget = targetSlot);
        }
        return canAccept;
      },
      onLeave: (_) {
        if (_hoveredDropTarget == targetSlot) {
          setState(() => _hoveredDropTarget = null);
        }
      },
      onAcceptWithDetails: (details) {
        setState(() => _hoveredDropTarget = null);
        if (targetSlot != widget.selectedPosition) {
          widget.onPositionChanged(targetSlot);
        }
      },
      builder: (context, candidateData, rejectedData) {
        return Tooltip(
          message: 'Click or drop here to place at Position $targetSlot',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.isLocked
                  ? null
                  : () {
                      if (targetSlot != widget.selectedPosition) {
                        widget.onPositionChanged(targetSlot);
                      }
                    },
              borderRadius: BorderRadius.circular(8),
              child: targetBox,
            ),
          ),
        );
      },
    );
  }

  /// Builds visual connector arrows linking stages along the rail
  Widget _buildConnector({required bool isPast}) {
    return Container(
      width: 22,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 2,
              color: isPast
                  ? DefensysTokens.maroon.withValues(alpha: 0.4)
                  : const Color(0xFFCBD5E1),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 14,
            color: isPast
                ? DefensysTokens.maroon.withValues(alpha: 0.6)
                : const Color(0xFF94A3B8),
          ),
        ],
      ),
    );
  }

  /// Builds the live breadcrumb strip reflecting the complete sequence order
  Widget _buildLivePreviewStrip({
    required List<Map<String, dynamic>> sequence,
    required int clampedPos,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.alt_route_rounded,
            size: 13.5,
            color: widget.isLocked ? const Color(0xFF1D4ED8) : DefensysTokens.maroon,
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
                children: List.generate(sequence.length, (i) {
                  final item = sequence[i];
                  final name = item['label']?.toString() ?? 'Stage ${i + 1}';
                  final isCurrent = item['_isCurrentStage'] == true;
                  final isLocked = item['is_locked'] == true || item['status'] == 'locked';

                  Color pillBg;
                  Color pillBorder;
                  Color textColor;
                  Color iconColor;

                  if (isCurrent && widget.isLocked) {
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
                    pillBg = Colors.white;
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
                                widget.isLocked ? Icons.lock_rounded : Icons.stars_rounded,
                                size: 11,
                                color: iconColor,
                              ),
                              const SizedBox(width: 4),
                            ] else if (isLocked) ...[
                              const Icon(
                                Icons.lock_outline_rounded,
                                size: 10,
                                color: Color(0xFF94A3B8),
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
                      if (i < sequence.length - 1)
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
