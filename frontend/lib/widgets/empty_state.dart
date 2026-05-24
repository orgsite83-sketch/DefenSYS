import 'package:flutter/material.dart';

import '../theme/defensys_tokens.dart';

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
    this.iconSize = 80,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DefensysTokens.spacing2xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: iconSize,
              color: DefensysTokens.border,
            ),
            const SizedBox(height: DefensysTokens.spacingLg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: DefensysTokens.body.copyWith(
                color: DefensysTokens.textSecondary,
                fontSize: 16,
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
