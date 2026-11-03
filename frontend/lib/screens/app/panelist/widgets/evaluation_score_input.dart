import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';

String formatEvaluationScore(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// A blank score stays unanswered; invalid text never retains a previous score.
class EvaluationScoreInput extends StatefulWidget {
  const EvaluationScoreInput({
    super.key,
    required this.label,
    required this.maximum,
    required this.value,
    required this.onChanged,
    this.description = '',
    this.enabled = true,
    this.onNext,
  });

  final String label;
  final String description;
  final double maximum;
  final double? value;
  final bool enabled;
  final ValueChanged<double?> onChanged;
  final VoidCallback? onNext;

  @override
  State<EvaluationScoreInput> createState() => EvaluationScoreInputState();
}

class EvaluationScoreInputState extends State<EvaluationScoreInput> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  bool _showErrors = false;

  String get _text => _controller.text.trim();

  double? get _parsedScore {
    // Some phone keyboards use a decimal comma. Accept either separator, but
    // never strip arbitrary pasted characters into a different numeric score.
    if (!RegExp(r'^(?:\d+(?:[.,]\d{0,2})?|[.,]\d{1,2})$').hasMatch(_text)) {
      return null;
    }
    final value = double.tryParse(_text.replaceAll(',', '.'));
    return value != null &&
            value.isFinite &&
            value >= 0 &&
            value <= widget.maximum
        ? value
        : null;
  }

  bool get hasInvalidValue => _text.isNotEmpty && _parsedScore == null;

  String get _error {
    final numeric = double.tryParse(_text.replaceAll(',', '.'));
    if (numeric != null && numeric.isFinite) {
      if (numeric < 0 || numeric > widget.maximum) {
        return 'Enter a score from 0 to ${formatEvaluationScore(widget.maximum)}.';
      }
      if (RegExp(r'^\d*[.,]\d{3,}$').hasMatch(_text)) {
        return 'Use up to 2 decimal places.';
      }
    }
    return 'Enter a number from 0 to ${formatEvaluationScore(widget.maximum)}.';
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value == null ? '' : formatEvaluationScore(widget.value!),
    );
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(EvaluationScoreInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _parsedScore) {
      _controller.text = widget.value == null
          ? ''
          : formatEvaluationScore(widget.value!);
      _showErrors = false;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) validate();
  }

  bool validate({bool requestFocus = false}) {
    if (!mounted) return true;
    if (hasInvalidValue) {
      if (!_showErrors) setState(() => _showErrors = true);
      if (requestFocus) requestScoreFocus();
      return false;
    }
    return true;
  }

  void requestScoreFocus() => _focusNode.requestFocus();

  void _finishEditing() {
    if (!validate(requestFocus: true)) return;
    if (widget.onNext != null) {
      widget.onNext!();
    } else {
      _focusNode.unfocus();
    }
  }

  Widget _keyboardToolbar(BuildContext context) => TextFieldTapRegion(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceOf(context),
        border: Border(
          top: BorderSide(color: DefensysTokens.borderOf(context)),
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DefensysTokens.caption.copyWith(
                  color: DefensysTokens.textSecondaryOf(context),
                ),
              ),
            ),
            if (widget.onNext != null)
              ShadButton.ghost(
                height: 44,
                onPressed: _finishEditing,
                child: const Text('Next'),
              ),
            ShadButton.ghost(
              height: 44,
              onPressed: () {
                if (validate(requestFocus: true)) _focusNode.unfocus();
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final showError = _showErrors && hasInvalidValue;
    final label = Text(
      widget.label,
      style: DefensysTokens.body.copyWith(
        color: DefensysTokens.textPrimaryOf(context),
        fontWeight: FontWeight.w600,
      ),
    );
    final input = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label:
              '${widget.label}, score out of ${formatEvaluationScore(widget.maximum)}',
          child: SizedBox(
            width: 88,
            child: ShadInput(
              key: const ValueKey('evaluation-score-field'),
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              placeholder: const Text('—'),
              placeholderAlignment: Alignment.centerRight,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              ),
              textInputAction: widget.onNext == null
                  ? TextInputAction.done
                  : TextInputAction.next,
              textAlign: TextAlign.right,
              autocorrect: false,
              enableSuggestions: false,
              style: DefensysTokens.body.copyWith(
                fontSize: 16,
                color: DefensysTokens.textPrimaryOf(context),
              ),
              constraints: const BoxConstraints(minHeight: 44),
              scrollPadding: const EdgeInsets.fromLTRB(16, 24, 16, 132),
              decoration: showError
                  ? ShadDecoration(
                      border: ShadBorder.all(
                        color: Theme.of(context).colorScheme.error,
                        radius: BorderRadius.circular(DefensysTokens.radiusMd),
                      ),
                    )
                  : null,
              keyboardToolbarBuilder: _keyboardToolbar,
              onChanged: (_) {
                setState(() {
                  _showErrors = _text != '.' && _text != ',';
                });
                widget.onChanged(_parsedScore);
              },
              // Own traversal so Next/Done cannot submit grades or skip an error.
              onEditingComplete: () {},
              onSubmitted: (_) => _finishEditing(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '/ ${formatEvaluationScore(widget.maximum)}',
          style: DefensysTokens.tableCell.copyWith(
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: label,
              ),
            ),
            const SizedBox(width: 12),
            input,
          ],
        ),
        if (widget.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            widget.description,
            style: DefensysTokens.caption.copyWith(
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
        if (showError) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              _error,
              style: DefensysTokens.caption.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
