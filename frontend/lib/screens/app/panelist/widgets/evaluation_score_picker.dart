import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';

String formatEvaluationScore(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// Exact scores without opening a numeric keyboard. Nothing is selected until
/// the panelist taps a value or explicitly applies the precision picker.
class EvaluationScorePicker extends StatelessWidget {
  const EvaluationScorePicker({
    super.key,
    required this.label,
    required this.maximum,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final String label;
  final double maximum;
  final double? value;
  final bool enabled;
  final ValueChanged<double?> onChanged;

  Future<void> _chooseExact(BuildContext context) async {
    final result = await showDialog<double>(
      context: context,
      builder: (_) => DefensysShadcnScope(
        child: _ExactScoreDialog(label: label, maximum: maximum, value: value),
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = ((constraints.maxWidth + 6) / 50).floor().clamp(1, 6);
          final width = (constraints.maxWidth - (columns - 1) * 6) / columns;
          final step = maximum <= 10 ? 1 : (maximum / 10).ceil();
          final values = <double>[
            for (int n = 0; n <= maximum.floor(); n += step) n.toDouble(),
            if (maximum % step != 0) maximum,
          ];
          return Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final score in values)
                Semantics(
                  selected: value == score,
                  label:
                      '$label, ${formatEvaluationScore(score)} out of ${formatEvaluationScore(maximum)}',
                  child: ShadButton.raw(
                    key: ValueKey(
                      'score-value-${formatEvaluationScore(score)}',
                    ),
                    variant: value == score
                        ? ShadButtonVariant.primary
                        : ShadButtonVariant.outline,
                    enabled: enabled,
                    width: width,
                    height: 44,
                    padding: EdgeInsets.zero,
                    backgroundColor: value == score
                        ? DefensysTokens.maroonOf(context)
                        : null,
                    foregroundColor: value == score ? Colors.white : null,
                    onPressed: enabled ? () => onChanged(score) : null,
                    child: Text(formatEvaluationScore(score)),
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          ShadButton.outline(
            enabled: enabled && value != null && value! >= .5,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            onPressed: enabled && value != null && value! >= .5
                ? () => onChanged(((value! - .5) * 100).round() / 100)
                : null,
            child: const Text('−0.5'),
          ),
          ShadButton.outline(
            enabled: enabled && value != null && value! + .5 <= maximum,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            onPressed: enabled && value != null && value! + .5 <= maximum
                ? () => onChanged(((value! + .5) * 100).round() / 100)
                : null,
            child: const Text('+0.5'),
          ),
          ShadButton.ghost(
            enabled: enabled,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            onPressed: enabled ? () => _chooseExact(context) : null,
            child: const Text('Fine score'),
          ),
          ShadButton.ghost(
            enabled: enabled && value != null,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            onPressed: enabled && value != null ? () => onChanged(null) : null,
            child: const Text('Clear'),
          ),
        ],
      ),
    ],
  );
}

class _ExactScoreDialog extends StatefulWidget {
  const _ExactScoreDialog({
    required this.label,
    required this.maximum,
    this.value,
  });
  final String label;
  final double maximum;
  final double? value;

  @override
  State<_ExactScoreDialog> createState() => _ExactScoreDialogState();
}

class _ExactScoreDialogState extends State<_ExactScoreDialog> {
  late int _whole, _tenths, _hundredths;
  final List<FixedExtentScrollController> _controllers = [];
  double get _score => (_whole * 100 + _tenths * 10 + _hundredths) / 100;

  @override
  void initState() {
    super.initState();
    final initial = ((widget.value ?? 0) * 100).round();
    _whole = initial ~/ 100;
    _tenths = initial % 100 ~/ 10;
    _hundredths = initial % 10;
    for (final value in [_whole, _tenths, _hundredths]) {
      _controllers.add(FixedExtentScrollController(initialItem: value));
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _wheel(
    String label,
    int count,
    int index,
    ValueChanged<int> changed,
  ) => Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        SizedBox(
          height: 132,
          child: CupertinoPicker.builder(
            scrollController: _controllers[index],
            itemExtent: 44,
            childCount: count,
            onSelectedItemChanged: (value) => setState(() => changed(value)),
            itemBuilder: (context, value) => Center(
              child: Text(
                '$value',
                style: TextStyle(
                  fontSize: 18,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose an exact score'),
    content: SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.label),
          const SizedBox(height: 12),
          Text(
            '${formatEvaluationScore(_score)} / ${formatEvaluationScore(widget.maximum)}',
            key: const ValueKey('exact-score-preview'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _wheel(
                'Whole points',
                widget.maximum.floor() + 1,
                0,
                (value) => _whole = value,
              ),
              _wheel('Tenths', 10, 1, (value) => _tenths = value),
              _wheel('Hundredths', 10, 2, (value) => _hundredths = value),
            ],
          ),
          if (_score > widget.maximum)
            Text(
              'Maximum score: ${formatEvaluationScore(widget.maximum)}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      ShadButton.outline(
        height: 44,
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      ShadButton(
        height: 44,
        enabled: _score <= widget.maximum,
        onPressed: _score <= widget.maximum
            ? () => Navigator.pop(context, _score)
            : null,
        child: const Text('Apply score'),
      ),
    ],
  );
}
