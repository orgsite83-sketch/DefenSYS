import 'package:flutter/material.dart';

import '../l10n/l10n_ext.dart';
import '../theme/defensys_tokens.dart';

/// Returns true if the user confirmed, false if cancelled or dismissed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = 'Cancel',
  String confirmLabel = 'Confirm',
  bool destructive = false,
  IconData? icon,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      title: icon != null
          ? Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (destructive ? DefensysTokens.danger : DefensysTokens.maroon).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: destructive ? DefensysTokens.danger : DefensysTokens.maroon,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: DefensysTokens.dialogTitle,
                  ),
                ),
              ],
            )
          : Text(title, style: DefensysTokens.dialogTitle),
      content: Text(
        message,
        style: DefensysTokens.dialogContent,
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: DefensysTokens.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: destructive ? DefensysTokens.danger : DefensysTokens.maroon,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
            ),
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}

Future<bool> confirmLogout(BuildContext context) {
  final l10n = context.l10n;
  return showConfirmDialog(
    context,
    title: l10n.logoutTitle,
    message: l10n.logoutMessage,
    confirmLabel: l10n.logoutConfirm,
    cancelLabel: l10n.cancel,
  );
}

Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) {
  return showConfirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    destructive: true,
    icon: Icons.warning_amber,
  );
}
