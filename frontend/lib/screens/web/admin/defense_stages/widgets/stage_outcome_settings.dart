import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';

class StageOutcomeSettings extends StatelessWidget {
  const StageOutcomeSettings({
    super.key,
    required this.scoreController,
    required this.scoreCarryover,
    required this.onCarryoverChanged,
    required this.onChanged,
    this.conceptSelection = false,
    this.enabled = true,
  });
  final TextEditingController scoreController;
  final String scoreCarryover;
  final ValueChanged<String> onCarryoverChanged;
  final VoidCallback onChanged;
  final bool conceptSelection, enabled;

  static String? validateScore(String? text) {
    final value = double.tryParse(text?.trim() ?? '');
    if (value == null || !value.isFinite || value < 0 || value > 100) {
      return 'Enter a score from 0 to 100%.';
    }
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text!.trim())) {
      return 'Use up to two decimal places.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Builder(
      builder: (context) {
        final muted = DefensysTokens.caption.copyWith(
          color: DefensysTokens.textSecondaryOf(context),
        );
        final labelStyle = DefensysTokens.body.copyWith(
          color: DefensysTokens.textPrimaryOf(context),
        );
        final controlStyle = DefensysTokens.tableCell.copyWith(
          color: DefensysTokens.textPrimaryOf(context),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Defense rules',
              style: DefensysTokens.sectionTitle.copyWith(
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text('Panel qualifying score', style: labelStyle),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: Semantics(
                    label: 'Panel qualifying score',
                    child: ShadInput(
                      key: const ValueKey('minimum-qualifying-score'),
                      controller: scoreController,
                      style: controlStyle,
                      enabled: enabled,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      trailing: Text('%', style: controlStyle),
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: scoreController,
              builder: (_, value, _) {
                final error = validateScore(value.text);
                return Semantics(
                  liveRegion: true,
                  child: Text(
                    error ??
                        (conceptSelection
                            ? 'Concepts need ${value.text.trim()}% to qualify for panel selection.'
                            : 'Below ${value.text.trim()}% requires re-defense.'),
                    style: error == null
                        ? muted
                        : muted.copyWith(
                            color: DefensysTokens.isDark(context)
                                ? DefensysTokens.danger
                                : DefensysTokens.dangerText,
                          ),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Divider(
                height: 1,
                color: DefensysTokens.borderOf(context),
              ),
            ),
            Text('Adviser and peer scores on re-defense', style: labelStyle),
            const SizedBox(height: 12),
            ShadRadioGroup<String>(
              key: ValueKey('repeat-scores-$scoreCarryover'),
              initialValue: scoreCarryover,
              enabled: enabled,
              axis: Axis.horizontal,
              spacing: 24,
              runSpacing: 12,
              items: [
                ShadRadio(
                  value: 'reassess',
                  label: Text('Collect new scores', style: controlStyle),
                ),
                ShadRadio(
                  value: 'retain',
                  label: Text('Keep previous scores', style: controlStyle),
                ),
              ],
              onChanged: (value) {
                if (value != null && value != scoreCarryover) {
                  onCarryoverChanged(value);
                }
              },
            ),
            const SizedBox(height: 8),
            Text('Panelists evaluate again on every attempt.', style: muted),
          ],
        );
      },
    ),
  );
}
