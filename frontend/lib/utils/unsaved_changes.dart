import 'package:flutter/material.dart';

import '../l10n/l10n_ext.dart';
import '../widgets/confirm_dialog.dart';

/// Returns true if the user chose to discard unsaved work.
Future<bool> confirmDiscardUnsavedChanges(BuildContext context) {
  final l10n = context.l10n;
  return confirmDestructive(
    context,
    title: l10n.discardUnsavedTitle,
    message: l10n.discardUnsavedMessage,
    confirmLabel: l10n.discard,
  );
}

/// Runs [onExit] immediately when [isDirty] is false; otherwise asks to confirm.
Future<void> guardUnsavedExit(
  BuildContext context, {
  required bool isDirty,
  required VoidCallback onExit,
}) async {
  if (!isDirty) {
    onExit();
    return;
  }
  final discard = await confirmDiscardUnsavedChanges(context);
  if (discard && context.mounted) {
    onExit();
  }
}
