import 'package:flutter/material.dart';

import '../theme/defensys_tokens.dart';

/// Consistent spinners (use [DefensysSkeleton] for layout placeholders).
class DefensysLoading {
  DefensysLoading._();

  static const Color _color = DefensysTokens.maroon;

  static Widget full({String? label}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: _color),
          if (label != null) ...[
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(color: DefensysTokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  static Widget section({double height = 170, String? label}) {
    return SizedBox(
      height: height,
      child: full(label: label),
    );
  }

  static Widget inline({double size = 20, Color? color}) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: color ?? _color,
      ),
    );
  }
}
