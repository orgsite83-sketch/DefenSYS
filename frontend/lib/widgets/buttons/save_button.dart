import 'package:flutter/material.dart';

import '../../theme/defensys_tokens.dart';

/// Standardized Dark Slate Navy Save Button for DefenSYS Web.
///
/// Implements the unified persistence pattern:
/// - Background: Dark Slate 800 (`#1E293B`)
/// - Foreground: White (`Colors.white`)
/// - Icon: `Icons.save_rounded` (floppy disk)
/// - State: Inline white spinner and `'Saving…'` text when [isSaving] is true
/// - Shape: Pill (`StadiumBorder()`) by default, configurable with [isPill]
class DefensysSaveButton extends StatelessWidget {
  final String label;
  final String? savingLabel;
  final VoidCallback? onPressed;
  final bool isSaving;
  final IconData icon;
  final bool isPill;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final double fontSize;
  final String? tooltip;

  const DefensysSaveButton({
    super.key,
    this.label = 'Save changes',
    this.savingLabel = 'Saving…',
    required this.onPressed,
    this.isSaving = false,
    this.icon = Icons.save_rounded,
    this.isPill = true,
    this.padding,
    this.width,
    this.height,
    this.fontSize = 13,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final bool canPress = !isSaving && onPressed != null;

    final button = FilledButton.icon(
      onPressed: canPress ? onPressed : null,
      style: DefensysTokens.saveButtonStyle(
        isPill: isPill,
        padding: padding ??
            const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        fontSize: fontSize,
      ),
      icon: isSaving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Icon(icon, size: 16),
      label: Text(
        isSaving ? (savingLabel ?? 'Saving…') : label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
        ),
      ),
    );

    Widget result = button;
    if (width != null || height != null) {
      result = SizedBox(
        width: width,
        height: height,
        child: result,
      );
    }

    if (tooltip != null && tooltip!.isNotEmpty) {
      result = Tooltip(message: tooltip!, child: result);
    }

    return result;
  }
}
