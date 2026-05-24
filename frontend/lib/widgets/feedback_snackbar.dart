import 'package:flutter/material.dart';

import '../theme/defensys_tokens.dart';

/// Transient success feedback (submit OK, upload OK, post grades OK).
void showSuccessSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
  SnackBarAction? action,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: DefensysTokens.success,
        duration: duration,
        action: action,
      ),
    );
}

/// Network/server failure or unexpected errors.
void showErrorSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: DefensysTokens.danger,
        duration: const Duration(seconds: 4),
      ),
    );
}

/// Client-side validation before submit (missing fields, unrated criteria).
void showValidationSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: DefensysTokens.warning,
        duration: const Duration(seconds: 3),
      ),
    );
}

/// Destructive action with optional undo (Phase 7F pilot).
void showUndoSnackBar(
  BuildContext context,
  String message, {
  required VoidCallback onUndo,
  String undoLabel = 'Undo',
  Duration duration = const Duration(seconds: 5),
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: DefensysTokens.textDark,
        duration: duration,
        action: SnackBarAction(
          label: undoLabel,
          textColor: DefensysTokens.gold,
          onPressed: onUndo,
        ),
      ),
    );
}
