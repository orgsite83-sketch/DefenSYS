import 'package:flutter/material.dart';
import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/repository/document_policy_editor.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';

/// The cutoff is the only new outcome control. Repeat scoring is an existing
/// stage-wide policy, kept beside it with its own heading and explanation.
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
  final bool conceptSelection;
  final bool enabled;

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget panel(String title, List<Widget> content) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DefensysTokens.surfaceHigherOf(context),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...content,
        ],
      ),
    );
    final outcome = panel('Defense Outcome', [
      const Text('Based on the panel assessment only.'),
      const SizedBox(height: 16),
      SizedBox(
        width: 240,
        child: TextFormField(
          key: const ValueKey('minimum-qualifying-score'),
          controller: scoreController,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Minimum qualifying score',
            suffixText: '%',
            border: OutlineInputBorder(),
          ),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: validateScore,
          onChanged: (_) => onChanged(),
        ),
      ),
      const SizedBox(height: 16),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: scoreController,
        builder: (_, value, child) {
          if (validateScore(value.text) != null) {
            return const Text(
              'Set the qualifying score before scheduling new hearings.',
            );
          }
          return Text(
            conceptSelection
                ? 'Concepts scoring at least ${value.text}% qualify for panel selection. If none qualify, re-defense is required.'
                : 'A panel assessment of at least ${value.text}% qualifies the team for approval. Below it, re-defense is required.',
          );
        },
      ),
      const SizedBox(height: 8),
      Text(
        'Adviser and peer scores contribute to the academic grade.',
        style: theme.textTheme.bodySmall,
      ),
    ]);
    final repeat = panel('Re-defense Assessments', [
      const Text('Assessment policy for repeat attempts in this stage.'),
      const SizedBox(height: 16),
      const Text('Adviser and peer scores'),
      const SizedBox(height: 8),
      WorkflowChoice(
        value: scoreCarryover,
        enabled: enabled,
        options: const {
          'reassess': 'Require fresh assessments',
          'retain': 'Retain adviser and peer scores',
        },
        onChanged: onCarryoverChanged,
      ),
      const SizedBox(height: 16),
      Text(
        scoreCarryover == 'retain'
            ? 'Panel assessments are completed again. Previous adviser and peer scores are retained.'
            : 'Panel, adviser and peer assessments are completed again.',
      ),
      const SizedBox(height: 8),
      Text(
        'Required files still need faculty review and endorsement.',
        style: theme.textTheme.bodySmall,
      ),
    ]);
    return DefensysShadcnScope(
      child: LayoutBuilder(
        builder: (_, constraints) => constraints.maxWidth < 760
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [outcome, const SizedBox(height: 16), repeat],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: outcome),
                  const SizedBox(width: 16),
                  Expanded(child: repeat),
                ],
              ),
      ),
    );
  }
}
