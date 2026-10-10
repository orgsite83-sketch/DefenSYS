import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';

/// A shared, quiet tab treatment for the evaluator workspace.
/// Selection and filtering remain owned by the calling screen.
class PanelistSegment<T> {
  const PanelistSegment({
    required this.value,
    required this.label,
    required this.icon,
    this.count,
    this.key,
  });

  final T value;
  final String label;
  final IconData icon;
  final String? count;
  final Key? key;
}

class PanelistSegmentedTabs<T> extends StatelessWidget {
  const PanelistSegmentedTabs({
    super.key,
    required this.segments,
    required this.onChanged,
    this.value,
    this.controller,
    this.scrollable = false,
    this.stacked = false,
    this.secondary = false,
  }) : assert((value == null) != (controller == null));

  final List<PanelistSegment<T>> segments;
  final ValueChanged<T> onChanged;
  final T? value;
  final ShadTabsController<T>? controller;
  final bool scrollable;
  final bool stacked;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final selected = controller?.selected ?? value;
    final accent = DefensysTokens.maroonOf(context);
    final muted = DefensysTokens.textSecondaryOf(context);
    final surface = DefensysTokens.surfaceOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final tabWidth = !scrollable && constraints.hasBoundedWidth
            ? stacked
                  ? (constraints.maxWidth - 8 - (segments.length - 1) * 4) /
                            segments.length -
                        16
                  : (constraints.maxWidth - 20 - (segments.length - 1) * 4) /
                            segments.length -
                        32
            : null;
        return DefensysShadcnScope(
          child: ShadTabs<T>(
            value: controller == null ? value : null,
            controller: controller,
            onChanged: onChanged,
            scrollable: scrollable,
            tabsGap: 4,
            gap: 0,
            padding: const EdgeInsets.all(4),
            decoration: ShadDecoration(
              color: surface,
              border: ShadBorder.all(
                color: DefensysTokens.borderOf(context),
                radius: BorderRadius.circular(12),
              ),
            ),
            tabs: [
              for (final segment in segments)
                ShadTab<T>(
                  key: segment.key,
                  value: segment.value,
                  height: stacked ? 64 : 44,
                  padding: EdgeInsets.symmetric(
                    horizontal: stacked ? 4 : 11,
                    vertical: stacked ? 5 : 8,
                  ),
                  backgroundColor: surface,
                  selectedBackgroundColor: secondary
                      ? accent.withValues(alpha: .06)
                      : accent,
                  foregroundColor: muted,
                  selectedForegroundColor: secondary ? accent : Colors.white,
                  hoverBackgroundColor: DefensysTokens.surfaceHigherOf(context),
                  selectedHoverBackgroundColor: secondary
                      ? accent.withValues(alpha: .09)
                      : accent,
                  shadows: const [],
                  selectedShadows: const [],
                  decoration: ShadDecoration(
                    border: ShadBorder.all(
                      width: 0,
                      radius: BorderRadius.circular(8),
                    ),
                  ),
                  child: SizedBox(
                    width: tabWidth,
                    child: _SegmentLabel(
                      label: segment.label,
                      icon: segment.icon,
                      count: segment.count,
                      selected: selected == segment.value,
                      bounded: tabWidth != null,
                      stacked: stacked,
                      secondary: secondary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.bounded,
    required this.stacked,
    required this.secondary,
  });

  final String label;
  final IconData icon;
  final String? count;
  final bool selected;
  final bool bounded;
  final bool stacked;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? secondary
              ? DefensysTokens.maroonTextOf(context)
              : Colors.white
        : DefensysTokens.textPrimaryOf(context);
    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: foreground),
              if (count != null) ...[
                const SizedBox(width: 5),
                _countBadge(context),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: 10.5,
              height: 1.05,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (secondary) ...[const SizedBox(height: 3), _indicator(context)],
        ],
      );
    }
    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: foreground),
        const SizedBox(width: 7),
        if (bounded)
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (count != null) ...[const SizedBox(width: 7), _countBadge(context)],
      ],
    );
    if (!secondary) return labelRow;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [labelRow, const SizedBox(height: 3), _indicator(context)],
    );
  }

  Widget _indicator(BuildContext context) => Container(
    height: 2,
    width: 26,
    decoration: BoxDecoration(
      color: selected ? DefensysTokens.maroonOf(context) : Colors.transparent,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _countBadge(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 22),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: selected
          ? secondary
                ? DefensysTokens.maroonOf(context).withValues(alpha: .10)
                : Colors.white.withValues(alpha: .18)
          : DefensysTokens.surfaceHigherOf(context),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      count!,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: selected
            ? secondary
                  ? DefensysTokens.maroonTextOf(context)
                  : Colors.white
            : DefensysTokens.textSecondaryOf(context),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
