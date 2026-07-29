import 'package:flutter/material.dart';

import '../l10n/l10n_ext.dart';
import '../theme/defensys_tokens.dart';

/// Inline error card with optional Retry — for page-level load failures.
class ErrorBanner extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  const ErrorBanner({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel,
  });

  @override
  Widget build(BuildContext context) {
    final retry = retryLabel ?? context.l10n.retry;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DefensysTokens.dangerBg,
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        border: Border.all(color: DefensysTokens.dangerBorder, width: 1.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: DefensysTokens.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: DefensysTokens.danger,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DefensysTokens.body.copyWith(
                    color: DefensysTokens.dangerText,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: DefensysTokens.caption.copyWith(
                    color: DefensysTokens.dangerText,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (onRetry != null)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: DefensysTokens.dangerText,
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onPressed: onRetry,
              child: Text(retry),
            ),
        ],
      ),
    );
  }
}
