import 'package:flutter/material.dart';
import '../../theme/defensys_tokens.dart';

/// Item descriptor for [DefensysSegmentedControl].
class DefensysSegmentItem<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final String? badgeLabel;
  final Widget? badge;

  const DefensysSegmentItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.badgeLabel,
    this.badge,
  });
}

/// Shared filled-maroon tab group for page navigation and table filters.
class DefensysSegmentedControl<T> extends StatelessWidget {
  final T value;
  final List<DefensysSegmentItem<T>> items;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final double height;

  const DefensysSegmentedControl({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.height = 50,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = DefensysTokens.isDark(context);
    final activeColor = DefensysTokens.maroonOf(context);

    final group = Container(
      height: height,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: DefensysTokens.panelOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(width: 6),
            _SegmentButton<T>(
              item: items[index],
              selected: items[index].value == value,
              enabled: enabled,
              activeColor: activeColor,
              onTap: () => onChanged(items[index].value),
            ),
          ],
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) => constraints.hasBoundedWidth
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: group,
            )
          : group,
    );
  }
}

class _SegmentButton<T> extends StatelessWidget {
  final DefensysSegmentItem<T> item;
  final bool selected;
  final bool enabled;
  final Color activeColor;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.item,
    required this.selected,
    required this.enabled,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? Colors.white
        : DefensysTokens.textPrimaryOf(context);
    final muted = selected
        ? Colors.white
        : DefensysTokens.textSecondaryOf(context);

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled && !selected ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? activeColor : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: 17, color: muted),
                  const SizedBox(width: 8),
                ],
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamily,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    if (item.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle!,
                        style: TextStyle(
                          fontFamily: DefensysTokens.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: selected
                              ? Colors.white.withValues(alpha: 0.9)
                              : DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ],
                ),
                if (item.badgeLabel != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.22)
                          : (DefensysTokens.isDark(context)
                                ? DefensysTokens.mistInputFill
                                : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      item.badgeLabel!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                  ),
                ],
                if (item.badge != null) ...[
                  const SizedBox(width: 8),
                  item.badge!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
