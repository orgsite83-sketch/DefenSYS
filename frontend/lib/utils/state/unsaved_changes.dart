import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';
import '../../theme/defensys_tokens.dart';
import '../../widgets/confirm_dialog.dart';

enum UnsavedChangesAction { cancel, discard, saveDraft }

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

/// Displays the discard unsaved changes warning dialog.
/// If [onSaveDraft] is provided, it adds a "Save as Draft" option.
Future<UnsavedChangesAction> showDiscardUnsavedChangesDialog(
  BuildContext context, {
  Future<bool> Function()? onSaveDraft,
}) async {
  final l10n = context.l10n;

  if (onSaveDraft == null) {
    final discard = await confirmDiscardUnsavedChanges(context);
    return discard ? UnsavedChangesAction.discard : UnsavedChangesAction.cancel;
  }

  final result = await showDialog<UnsavedChangesAction>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Row(
        children: [
          Icon(Icons.warning_amber, color: DefensysTokens.danger),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Unsaved Changes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: const Text(
        'You have unsaved changes. Would you like to save them as a draft or discard them?',
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, UnsavedChangesAction.cancel),
          child: Text(l10n.cancel),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: DefensysTokens.danger,
              ),
              onPressed: () => Navigator.pop(dialogContext, UnsavedChangesAction.discard),
              child: Text(l10n.discard),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: DefensysTokens.maroon,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, UnsavedChangesAction.saveDraft),
              child: const Text('Save as Draft'),
            ),
          ],
        ),
      ],
    ),
  );

  return result ?? UnsavedChangesAction.cancel;
}

/// Runs [onExit] immediately when [isDirty] is false; otherwise asks to confirm.
Future<void> guardUnsavedExit(
  BuildContext context, {
  required bool isDirty,
  required VoidCallback onExit,
  Future<bool> Function()? onSaveDraft,
}) async {
  if (!isDirty) {
    onExit();
    return;
  }
  final action = await showDiscardUnsavedChangesDialog(context, onSaveDraft: onSaveDraft);
  if (action == UnsavedChangesAction.discard && context.mounted) {
    onExit();
  } else if (action == UnsavedChangesAction.saveDraft && onSaveDraft != null && context.mounted) {
    final ok = await onSaveDraft();
    if (ok && context.mounted) {
      onExit();
    }
  }
}
