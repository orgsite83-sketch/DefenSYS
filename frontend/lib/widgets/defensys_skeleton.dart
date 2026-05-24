import 'package:flutter/material.dart';

import '../theme/defensys_tokens.dart';

/// Shared skeleton placeholders (static grey blocks; no external package).
class DefensysSkeleton {
  DefensysSkeleton._();

  static const _boneColor = Color(0xFFE5E7EB);

  /// Wrap [child] — when [enabled] is false, shows [child] as-is.
  static Widget wrap({
    required bool enabled,
    required Widget child,
  }) {
    if (!enabled) return child;
    return Opacity(opacity: 0.55, child: child);
  }

  /// Single rectangular placeholder.
  static Widget box({
    double? width,
    double height = 16,
    double borderRadius = 8,
    EdgeInsetsGeometry? margin,
  }) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: _boneColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }

  /// Stacked list rows for tables / assignment lists.
  static Widget list({
    int count = 5,
    double rowHeight = 56,
    double gap = 12,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Padding(
      padding: padding,
      child: Column(
        children: List.generate(count, (i) {
          return Padding(
            padding: EdgeInsets.only(bottom: i < count - 1 ? gap : 0),
            child: box(height: rowHeight, borderRadius: 10),
          );
        }),
      ),
    );
  }

  /// Team summary card placeholder (student dashboard).
  static Widget teamSummaryCard() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DefensysTokens.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ShimmerBox(width: 160, height: 20),
          SizedBox(height: 10),
          _ShimmerBox(width: double.infinity, height: 14),
          SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _ShimmerBox(height: 12)),
              SizedBox(width: 12),
              Expanded(child: _ShimmerBox(height: 12)),
            ],
          ),
        ],
      ),
    );
  }

  /// Generic tab content area placeholder.
  static Widget tabContent({double minHeight = 200}) {
    return SizedBox(
      height: minHeight,
      child: list(count: 4, rowHeight: 48),
    );
  }

  /// Admin metric tiles row.
  static Widget metricRow({int count = 4}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: List.generate(
          count,
          (i) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
              child: box(height: 72, borderRadius: 12),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    this.width,
    this.height = 16,
  });

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return DefensysSkeleton.box(width: width, height: height);
  }
}
