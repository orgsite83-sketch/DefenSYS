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
      title: icon != null
          ? Row(
              children: [
                Icon(icon, color: destructive ? DefensysTokens.danger : DefensysTokens.maroon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            )
          : Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: destructive ? DefensysTokens.danger : DefensysTokens.maroon,
            foregroundColor: Colors.white,
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
