import 'package:flutter/material.dart';

import '../../theme/defensys_tokens.dart';

/// A sleek, accessible filter chip built according to Shadcn UI aesthetics.
/// Replaces Material ChoiceChip / FilterChip with crisp hairline borders,
/// subtle zinc / brand surface tints, and an optional numerical badge.
class DefensysFilterChip extends StatefulWidget {
  const DefensysFilterChip({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
    this.count,
    this.countLabel,
    this.icon,
    this.activeColor,
    this.selectedTextColor,
    this.selectedBgColor,
    this.height = 30.0,
    this.padding,
    this.tooltip,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final int? count;
  final String? countLabel;
  final IconData? icon;
  final Color? activeColor;
  final Color? selectedTextColor;
  final Color? selectedBgColor;
  final double height;
  final EdgeInsetsGeometry? padding;
  final String? tooltip;

  @override
  State<DefensysFilterChip> createState() => _DefensysFilterChipState();
}

class _DefensysFilterChipState extends State<DefensysFilterChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveActiveColor =
        widget.activeColor ?? DefensysTokens.maroonOf(context);
    final effectiveActiveText =
        widget.selectedTextColor ??
        (widget.activeColor != null
            ? widget.activeColor!
            : DefensysTokens.maroonTextOf(context));

    final effectiveBg = widget.selected
        ? (widget.selectedBgColor ??
            effectiveActiveColor.withValues(alpha: 0.08))
        : (_isHovered
            ? DefensysTokens.surfaceHigherOf(context)
            : DefensysTokens.surfaceOf(context));

    final effectiveBorderColor = widget.selected
        ? effectiveActiveColor
        : (_isHovered
            ? DefensysTokens.textSecondaryOf(context).withValues(alpha: 0.4)
            : DefensysTokens.borderOf(context));

    final effectiveTextColor = widget.selected
        ? effectiveActiveText
        : DefensysTokens.textSecondaryOf(context);

    final displayCount = widget.countLabel ?? (widget.count != null ? '${widget.count}' : null);

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      constraints: BoxConstraints(
        minHeight: widget.height,
      ),
      padding: widget.padding ??
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
        border: Border.all(
          color: effectiveBorderColor,
          width: widget.selected ? 1.2 : 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            Icon(
              widget.icon,
              size: 13,
              color: effectiveTextColor,
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontSize: 12,
                fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                color: effectiveTextColor,
                height: 1.15,
              ),
            ),
          ),
          if (displayCount != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: widget.selected
                    ? effectiveActiveColor.withValues(alpha: 0.14)
                    : DefensysTokens.surfaceHigherOf(context),
                borderRadius: BorderRadius.circular(DefensysTokens.radiusPill),
              ),
              child: Text(
                displayCount,
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: widget.selected
                      ? effectiveActiveText
                      : DefensysTokens.textSecondaryOf(context),
                  height: 1.1,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    Widget chip = MouseRegion(
      cursor: widget.onSelected != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelected != null
            ? () => widget.onSelected!(!widget.selected)
            : null,
        child: content,
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      chip = Tooltip(
        message: widget.tooltip!,
        child: chip,
      );
    }

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.tooltip ?? widget.label,
      child: chip,
    );
  }
}
