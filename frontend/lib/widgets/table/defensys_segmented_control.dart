import 'package:flutter/material.dart';
import '../../theme/defensys_tokens.dart';
import 'defensys_table_tokens.dart';

/// Item descriptor for [DefensysSegmentedControl].
class DefensysSegmentItem<T> {
  final T value;
  final String label;
  final IconData? icon;
  final Widget? badge;

  const DefensysSegmentItem({
    required this.value,
    required this.label,
    this.icon,
    this.badge,
  });
}

/// Standardized segmented toggle button group used in table command bars.
class DefensysSegmentedControl<T> extends StatelessWidget {
  final T value;
  final List<DefensysSegmentItem<T>> items;
  final ValueChanged<T> onChanged;
  final Color? activeColor;
  final double height;

  const DefensysSegmentedControl({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.activeColor,
    this.height = DefensysTableTokens.controlHeight,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveActiveColor = activeColor ?? DefensysTokens.maroon;

    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: DefensysTableTokens.segmentedControlBackground,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: DefensysTableTokens.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.map((item) {
          final isSelected = item.value == value;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: isSelected ? null : () => onChanged(item.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.icon != null) ...[
                        Icon(
                          item.icon,
                          size: 14,
                          color: isSelected
                              ? effectiveActiveColor
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        item.label,
                        style: TextStyle(
                          fontFamily: DefensysTokens.fontFamily,
                          color: isSelected
                              ? effectiveActiveColor
                              : const Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      if (item.badge != null) ...[
                        const SizedBox(width: 6),
                        item.badge!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
