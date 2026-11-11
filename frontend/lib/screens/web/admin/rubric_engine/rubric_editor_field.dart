import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';

String formatRubricPercentage(num value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

String? rubricPointsError(String text) {
  final value = int.tryParse(text.trim());
  return value == null || value < 1 || value > 32767
      ? 'Enter a whole number from 1 to 32767.'
      : null;
}

String? rubricWeightError(String text) {
  final value = num.tryParse(text.trim());
  if (value == null || !value.isFinite || value <= 0 || value > 100) {
    return 'Enter a weight greater than 0% and at most 100%.';
  }
  if ((value * 100 - (value * 100).round()).abs() > 0.000001) {
    return 'Use at most two decimal places.';
  }
  return null;
}

/// A rubric input with neutral required hints and validation after blur or save.
class RubricEditorField extends StatefulWidget {
  const RubricEditorField({
    super.key,
    required this.label,
    required this.controller,
    required this.inputKey,
    required this.enabled,
    required this.onChanged,
    this.validator,
    this.showValidation = false,
    this.placeholder,
    this.trailing,
    this.hint,
    this.keyboardType,
    this.maxLength,
    this.minLines = 1,
    this.maxLines = 1,
    this.labelAction,
  });

  final String label;
  final TextEditingController controller;
  final Key inputKey;
  final bool enabled, showValidation;
  final ValueChanged<String> onChanged;
  final String? Function(String)? validator;
  final String? placeholder, hint;
  final Widget? trailing, labelAction;
  final TextInputType? keyboardType;
  final int? maxLength;
  final int minLines, maxLines;

  @override
  State<RubricEditorField> createState() => RubricEditorFieldState();
}

class RubricEditorFieldState extends State<RubricEditorField> {
  final _focus = FocusNode();
  bool _touched = false;

  String? get error => widget.validator?.call(widget.controller.text);

  void focus() {
    if (!mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.25,
      duration: const Duration(milliseconds: 180),
    );
    _focus.requestFocus();
  }

  void focusError() {
    if (!mounted) return;
    setState(() => _touched = true);
    focus();
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (!_focus.hasFocus && mounted) setState(() => _touched = true);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.enabled && (_touched || widget.showValidation)
        ? error
        : null;
    final primary = DefensysTokens.textPrimaryOf(context);
    final secondary = DefensysTokens.textSecondaryOf(context);
    final errorColor = DefensysTokens.maroonTextOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text.rich(
              TextSpan(
                text: widget.label,
                children: [
                  if (widget.validator != null && widget.enabled)
                    TextSpan(
                      text: ' · Required',
                      style: DefensysTokens.caption.copyWith(color: secondary),
                    ),
                ],
              ),
              style: DefensysTokens.tableCell.copyWith(
                color: primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.labelAction != null) widget.labelAction!,
          ],
        ),
        const SizedBox(height: 6),
        ShadInput(
          key: widget.inputKey,
          controller: widget.controller,
          focusNode: _focus,
          enabled: widget.enabled,
          style: DefensysTokens.body.copyWith(color: primary),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          placeholder: widget.placeholder == null
              ? null
              : Text(widget.placeholder!),
          trailing: widget.trailing,
          keyboardType: widget.keyboardType,
          maxLength: widget.maxLength,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          decoration: message == null
              ? null
              : ShadDecoration(
                  border: ShadBorder.all(
                    color: errorColor,
                    width: 1,
                    radius: BorderRadius.circular(DefensysTokens.radiusMd),
                  ),
                ),
          onChanged: (value) {
            setState(() {});
            widget.onChanged(value);
          },
        ),
        if (message != null || widget.hint != null) ...[
          const SizedBox(height: 5),
          Semantics(
            liveRegion: message != null,
            child: Text(
              message ?? widget.hint!,
              style: DefensysTokens.caption.copyWith(color: errorColor),
            ),
          ),
        ],
      ],
    );
  }
}
