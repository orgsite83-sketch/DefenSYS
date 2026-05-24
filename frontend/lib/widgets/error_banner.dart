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
        borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
        border: Border.all(color: DefensysTokens.dangerBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: DefensysTokens.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: DefensysTokens.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: DefensysTokens.dangerText,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(retry)),
        ],
      ),
    );
  }
}
