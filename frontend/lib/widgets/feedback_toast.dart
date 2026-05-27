import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

import '../theme/defensys_tokens.dart';

class FeedbackToastAction {
  const FeedbackToastAction({
    required this.label,
    required this.onPressed,
    this.textColor,
  });

  final String label;
  final VoidCallback onPressed;
  final Color? textColor;
}

void dismissFeedbackToasts() {
  toastification.dismissAll(delayForAnimation: false);
}

void _showFeedbackToast(
  BuildContext context,
  String message, {
  required ToastificationType type,
  required Color primaryColor,
  Duration duration = const Duration(seconds: 3),
  FeedbackToastAction? action,
}) {
  dismissFeedbackToasts();

  toastification.show(
    context: context,
    type: type,
    style: ToastificationStyle.flatColored,
    alignment: Alignment.topRight,
    title: Text(message),
    description: action == null
        ? null
        : Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: action.onPressed,
              style: TextButton.styleFrom(
                foregroundColor: action.textColor ?? primaryColor,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(action.label),
            ),
          ),
    primaryColor: primaryColor,
    autoCloseDuration: duration,
  );
}

/// Transient success feedback (submit OK, upload OK, post grades OK).
void showSuccessToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
  FeedbackToastAction? action,
}) {
  _showFeedbackToast(
    context,
    message,
    type: ToastificationType.success,
    primaryColor: DefensysTokens.success,
    duration: duration,
    action: action,
  );
}

/// Network/server failure or unexpected errors.
void showErrorToast(BuildContext context, String message) {
  _showFeedbackToast(
    context,
    message,
    type: ToastificationType.error,
    primaryColor: DefensysTokens.danger,
    duration: const Duration(seconds: 4),
  );
}

/// Client-side validation before submit (missing fields, unrated criteria).
void showValidationToast(BuildContext context, String message) {
  _showFeedbackToast(
    context,
    message,
    type: ToastificationType.warning,
    primaryColor: DefensysTokens.warning,
  );
}

/// Neutral transient feedback (copy, download, informational progress).
void showInfoToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
}) {
  _showFeedbackToast(
    context,
    message,
    type: ToastificationType.info,
    primaryColor: DefensysTokens.infoText,
    duration: duration,
  );
}

/// Destructive action with optional undo (Phase 7F pilot).
void showUndoToast(
  BuildContext context,
  String message, {
  required VoidCallback onUndo,
  String undoLabel = 'Undo',
  Duration duration = const Duration(seconds: 5),
}) {
  _showFeedbackToast(
    context,
    message,
    type: ToastificationType.info,
    primaryColor: DefensysTokens.textDark,
    duration: duration,
    action: FeedbackToastAction(
      label: undoLabel,
      textColor: DefensysTokens.gold,
      onPressed: onUndo,
    ),
  );
}
