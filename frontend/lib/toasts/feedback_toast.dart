import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Centralized Toast Notification Service for DefenSYS
class ToastService {
  ToastService._();

  static void dismissAll() {
    dismissFeedbackToasts();
  }

  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    FeedbackToastAction? action,
  }) {
    showSuccessToast(context, message, duration: duration, action: action);
  }

  static void error(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    showErrorToast(context, message, duration: duration);
  }

  static void warning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 5),
  }) {
    showValidationToast(context, message, duration: duration);
  }

  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    showInfoToast(context, message, duration: duration);
  }

  static void undo(
    BuildContext context,
    String message, {
    required VoidCallback onUndo,
    String undoLabel = 'Undo',
    Duration duration = const Duration(seconds: 5),
  }) {
    showUndoToast(
      context,
      message,
      onUndo: onUndo,
      undoLabel: undoLabel,
      duration: duration,
    );
  }
}

void dismissFeedbackToasts() {
  toastification.dismissAll(delayForAnimation: false);
}

void _showFeedbackToast(
  BuildContext context,
  String message, {
  required ToastificationType type,
  required Color primaryColor,
  String? descriptionText,
  Duration? duration = const Duration(seconds: 3),
  FeedbackToastAction? action,
}) {
  dismissFeedbackToasts();

  toastification.show(
    context: context,
    type: type,
    style: ToastificationStyle.flatColored,
    alignment: Alignment.topRight,
    title: Text(message),
    description: descriptionText != null || action != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (descriptionText != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Text(
                    descriptionText,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              if (action != null)
                Align(
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
            ],
          )
        : null,
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
/// Shows a title and description with an automatic copy button for long messages.
/// Short messages auto-close in 8 seconds; long messages persist until dismissed.
void showErrorToast(
  BuildContext context,
  String message, {
  Duration? duration,
}) {
  final isLong = message.contains('\n') || message.length > 80;
  final titleText = isLong ? 'Operation Failed' : message;
  final descText = isLong ? message : null;

  // Stays on screen if long so the user can copy/read, or 8s if short.
  final autoClose = duration ?? (isLong ? null : const Duration(seconds: 8));

  _showFeedbackToast(
    context,
    titleText,
    type: ToastificationType.error,
    primaryColor: DefensysTokens.danger,
    descriptionText: descText,
    duration: autoClose,
    action: isLong
        ? FeedbackToastAction(
            label: 'Copy Error Details',
            textColor: DefensysTokens.gold,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message));
              showInfoToast(context, 'Error details copied to clipboard.', duration: const Duration(seconds: 2));
            },
          )
        : null,
  );
}

/// Client-side validation before submit (missing fields, unrated criteria).
void showValidationToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 5),
}) {
  _showFeedbackToast(
    context,
    message,
    type: ToastificationType.warning,
    primaryColor: DefensysTokens.warning,
    duration: duration,
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

/// Destructive action with optional undo.
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
