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

/// Structured parsed result from raw exception messages.
class HumanizedToastMessage {
  final String title;
  final String description;
  final String? rawDetails;

  const HumanizedToastMessage({
    required this.title,
    required this.description,
    this.rawDetails,
  });
}

/// Sanitizes technical error messages (Dio, Socket, 500s, JSON) into user-friendly copy.
HumanizedToastMessage humanizeErrorMessage(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const HumanizedToastMessage(
      title: 'Operation Failed',
      description: 'An unexpected error occurred. Please try again.',
    );
  }

  // 1. Check for JSON payload e.g. {"detail": "..."} or {"error": "..."}
  final jsonMatch = RegExp(r'''["'](?:detail|error|message)["']\s*:\s*["']([^"']+)["']''')
      .firstMatch(trimmed);
  if (jsonMatch != null) {
    final detailText = jsonMatch.group(1)!.trim();
    if (detailText.isNotEmpty) {
      return HumanizedToastMessage(
        title: 'Operation Failed',
        description: detailText,
        rawDetails: trimmed != detailText ? trimmed : null,
      );
    }
  }

  final lower = trimmed.toLowerCase();

  // 2. Network & Connection errors
  if (lower.contains('socketexception') ||
      lower.contains('connection refused') ||
      lower.contains('network is unreachable') ||
      lower.contains('failed host lookup') ||
      lower.contains('clientexception') ||
      lower.contains('connection error') ||
      lower.contains('handshakeexception') ||
      lower.contains('no address associated')) {
    return HumanizedToastMessage(
      title: 'Connection Failed',
      description: 'Unable to reach the server. Please check your network and try again.',
      rawDetails: trimmed,
    );
  }

  // 3. Timeouts
  if (lower.contains('timeoutexception') ||
      lower.contains('connecttimeout') ||
      lower.contains('receivetimeout') ||
      lower.contains('sendtimeout') ||
      lower.contains('timed out')) {
    return HumanizedToastMessage(
      title: 'Request Timed Out',
      description: 'The server took too long to respond. Please try again.',
      rawDetails: trimmed,
    );
  }

  // 4. Authentication / Session
  if (lower.contains('401') ||
      lower.contains('unauthorized') ||
      lower.contains('token_not_valid') ||
      lower.contains('authenticationcredentialsnotfound') ||
      lower.contains('not authenticated')) {
    return HumanizedToastMessage(
      title: 'Session Expired',
      description: 'Your session has expired. Please log in again to continue.',
      rawDetails: trimmed,
    );
  }

  // 5. Permissions
  if (lower.contains('403') ||
      lower.contains('forbidden') ||
      lower.contains('permission denied') ||
      lower.contains('permission_denied')) {
    return HumanizedToastMessage(
      title: 'Access Denied',
      description: 'You do not have permission to perform this action.',
      rawDetails: trimmed,
    );
  }

  // 6. Not Found
  if (lower.contains('404') ||
      lower.contains('not found') ||
      lower.contains('does not exist')) {
    return HumanizedToastMessage(
      title: 'Resource Not Found',
      description: 'The requested data or document could not be located.',
      rawDetails: trimmed,
    );
  }

  // 7. Server 500s
  if (lower.contains('500') ||
      lower.contains('502') ||
      lower.contains('503') ||
      lower.contains('504') ||
      lower.contains('internal server error') ||
      lower.contains('bad gateway')) {
    return HumanizedToastMessage(
      title: 'Server Error',
      description: 'A temporary server error occurred. Please try again or contact support.',
      rawDetails: trimmed,
    );
  }

  // 8. Clean technical prefixes (e.g. "Exception: ", "Error: ", "DioException: ")
  String cleaned = trimmed;
  final prefixRegex = RegExp(
    r'^(?:(?:DioException\s*\[[^\]]+\]:\s*)|(?:[A-Za-z]*Exception:\s*)|(?:Error:\s*)|(?:ClientException:\s*))+',
    caseSensitive: false,
  );
  cleaned = cleaned.replaceFirst(prefixRegex, '').trim();

  // If the message is long or contains multiple lines / stack trace
  final isLongOrMultiLine = cleaned.contains('\n') || cleaned.length > 80;
  if (isLongOrMultiLine) {
    final firstLine = cleaned.split('\n').first.trim();
    final firstSentenceMatch = RegExp(r'^([^.?!]+[.?!])').firstMatch(firstLine);
    final summary = firstSentenceMatch?.group(1) ??
        (firstLine.length > 70 ? '${firstLine.substring(0, 67)}...' : firstLine);

    return HumanizedToastMessage(
      title: 'Operation Failed',
      description: summary.isNotEmpty ? summary : 'An unexpected error occurred.',
      rawDetails: trimmed,
    );
  }

  // Clean, short message
  return HumanizedToastMessage(
    title: 'Operation Failed',
    description: cleaned,
    rawDetails: trimmed != cleaned ? trimmed : null,
  );
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
    Duration duration = const Duration(seconds: 4),
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

  final mediaQuery = MediaQuery.maybeOf(context);
  final screenWidth = mediaQuery?.size.width ?? 1200.0;
  final isMobile = screenWidth < 600.0;

  final isDark = DefensysTokens.isDark(context);
  final surfaceColor = isDark ? DefensysTokens.mistSurface : Colors.white;
  final textColor = isDark ? DefensysTokens.mistTextPrimary : DefensysTokens.textPrimary;
  final subtitleColor = isDark ? DefensysTokens.mistTextSecondary : DefensysTokens.textSecondary;
  final borderColor = isDark ? DefensysTokens.mistBorder : DefensysTokens.border;

  final alignment = isMobile ? Alignment.topCenter : Alignment.topRight;
  final margin = isMobile
      ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
      : const EdgeInsets.only(top: 20, right: 24);
  final padding = isMobile
      ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
      : const EdgeInsets.symmetric(horizontal: 16, vertical: 12);

  final maxContentWidth = isMobile
      ? (screenWidth - 130).clamp(180.0, 340.0)
      : 340.0;

  final titleWidget = ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxContentWidth),
    child: Text(
      message,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: DefensysTokens.fontFamily,
        fontSize: isMobile ? 13.0 : 13.5,
        fontWeight: FontWeight.w600,
        color: textColor,
        letterSpacing: -0.1,
      ),
    ),
  );

  final descriptionWidget = (descriptionText != null || action != null)
      ? ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (descriptionText != null && descriptionText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0, bottom: 4.0),
                  child: Text(
                    descriptionText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: DefensysTokens.fontFamilyInter,
                      fontSize: isMobile ? 11.5 : 12.0,
                      fontWeight: FontWeight.w400,
                      color: subtitleColor,
                      height: 1.35,
                    ),
                  ),
                ),
              if (action != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: action.onPressed,
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: (action.textColor ?? primaryColor).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                          border: Border.all(
                            color: (action.textColor ?? primaryColor).withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          action.label,
                          style: TextStyle(
                            fontFamily: DefensysTokens.fontFamily,
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                            color: action.textColor ?? primaryColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        )
      : null;

  toastification.show(
    context: context,
    type: type,
    style: ToastificationStyle.flat,
    alignment: alignment,
    margin: margin,
    padding: padding,
    backgroundColor: surfaceColor,
    foregroundColor: textColor,
    primaryColor: primaryColor,
    borderSide: BorderSide(color: borderColor, width: 1.0),
    borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
    boxShadow: [
      BoxShadow(
        color: isDark ? const Color(0x44000000) : const Color(0x12000000),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: isDark ? const Color(0x22000000) : const Color(0x06000000),
        blurRadius: 3,
        offset: const Offset(0, 1),
      ),
    ],
    showProgressBar: false,
    closeButton: const ToastCloseButton(showType: CloseButtonShowType.always),
    dragToClose: true,
    pauseOnHover: true,
    title: titleWidget,
    description: descriptionWidget,
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
/// Automatically sanitizes technical stack traces into human-readable messages,
/// clamping text to 2 lines and providing a "Copy Details" button to keep full debug info.
void showErrorToast(
  BuildContext context,
  String message, {
  Duration? duration,
}) {
  final humanized = humanizeErrorMessage(message);
  final rawToCopy = humanized.rawDetails ?? (message.trim().isNotEmpty ? message.trim() : null);
  final hasDetails = rawToCopy != null && (rawToCopy.length > 30 || rawToCopy != humanized.description);

  _showFeedbackToast(
    context,
    humanized.title,
    type: ToastificationType.error,
    primaryColor: DefensysTokens.danger,
    descriptionText: humanized.description,
    duration: duration ?? const Duration(seconds: 6),
    action: hasDetails
        ? FeedbackToastAction(
            label: 'Copy Details',
            textColor: DefensysTokens.danger,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: rawToCopy));
              showInfoToast(
                context,
                'Error details copied to clipboard.',
                duration: const Duration(seconds: 2),
              );
            },
          )
        : null,
  );
}

/// Client-side validation before submit (missing fields, unrated criteria).
void showValidationToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
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
      textColor: DefensysTokens.darkGold,
      onPressed: onUndo,
    ),
  );
}
