import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';
import '../../theme/defensys_tokens.dart';

/// Returns true if the user confirmed, false if cancelled or dismissed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = 'Cancel',
  String confirmLabel = 'Confirm',
  bool destructive = false,
  IconData? icon,
  Color? confirmColor,
  Color? iconColor,
  Color? iconBgColor,
}) async {
  final effectiveIconColor = iconColor ??
      (destructive
          ? DefensysTokens.danger
          : (confirmColor ?? DefensysTokens.maroon));
  final effectiveIconBgColor =
      iconBgColor ?? effectiveIconColor.withValues(alpha: 0.08);
  final effectiveConfirmColor = confirmColor ??
      (destructive ? DefensysTokens.danger : DefensysTokens.maroon);

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
                    color: effectiveIconBgColor,
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: effectiveIconColor,
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
            backgroundColor: effectiveConfirmColor,
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

/// Standardized confirmation dialog for irreversible lock / finalization actions
/// (e.g. submitting peer evaluations, posting grades, issuing verdicts).
///
/// Unlike [confirmDestructive], this uses non-destructive styling (Dark Slate Navy
/// or Brand Maroon) and lock/save iconography to prevent user anxiety.
Future<bool> confirmLock(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Submit',
  String cancelLabel = 'Cancel',
  IconData icon = Icons.lock_outline_rounded,
  Color confirmColor = DefensysTokens.saveActionBg,
}) {
  return showConfirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
    destructive: false,
    icon: icon,
    confirmColor: confirmColor,
  );
}

/// Displays a high-security destructive confirmation modal that requires the user
/// to type a specific verification string (such as the username or student ID)
/// before the destructive action button becomes enabled.
Future<bool> showDestructiveTypeConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String matchTarget,
  String inputLabel = 'Type to confirm',
  String confirmLabel = 'Permanently Delete',
  String cancelLabel = 'Cancel',
  String? warningBanner,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      String typedText = '';
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isMatched =
              typedText.trim().toLowerCase() == matchTarget.trim().toLowerCase();

          return AlertDialog(
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: const Icon(
                    Icons.delete_forever_rounded,
                    size: 20,
                    color: Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: DefensysTokens.dialogTitle.copyWith(
                      color: const Color(0xFF991B1B),
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (warningBanner != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 16, color: Color(0xFFDC2626)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              warningBanner,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF991B1B),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Text(
                    message,
                    style: DefensysTokens.dialogContent,
                  ),
                  const SizedBox(height: 16),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: DefensysTokens.textDark,
                        height: 1.4,
                      ),
                      children: [
                        const TextSpan(text: 'To confirm deletion, please type '),
                        TextSpan(
                          text: matchTarget,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                        const TextSpan(text: ' in the field below:'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    autofocus: true,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DefensysTokens.textDark,
                    ),
                    decoration: InputDecoration(
                      hintText: matchTarget,
                      hintStyle: const TextStyle(
                        fontSize: 12.5,
                        color: DefensysTokens.steelGrey,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: DefensysTokens.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isMatched
                              ? const Color(0xFF16A34A)
                              : DefensysTokens.border,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isMatched
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (val) {
                      setDialogState(() {
                        typedText = val;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: DefensysTokens.textSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(cancelLabel),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isMatched
                      ? const Color(0xFFDC2626)
                      : const Color(0xFFFCA5A5),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                  ),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: Text(confirmLabel),
                onPressed: isMatched
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
              ),
            ],
          );
        },
      );
    },
  );
  return confirmed == true;
}
