import 'package:flutter/material.dart';

import '../../theme/defensys_tokens.dart';

/// Centered empty-list placeholder with optional primary action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double iconSize;

  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.iconSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DefensysTokens.spacing2xl,
          vertical: DefensysTokens.spacing3xl,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(DefensysTokens.spacingLg),
              decoration: BoxDecoration(
                color: DefensysTokens.neutralBg,
                borderRadius: BorderRadius.circular(DefensysTokens.radiusXl),
                border: Border.all(color: DefensysTokens.border, width: 1.0),
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: DefensysTokens.steelGrey,
              ),
            ),
            const SizedBox(height: DefensysTokens.spacingLg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: DefensysTokens.body.copyWith(
                color: DefensysTokens.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: DefensysTokens.spacingXl),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
