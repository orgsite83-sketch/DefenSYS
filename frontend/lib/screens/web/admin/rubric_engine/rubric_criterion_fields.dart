import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';

/// A responsive criterion row with the same controls as the rubric settings.
class RubricCriterionFields extends StatelessWidget {
  const RubricCriterionFields({
    super.key,
    required this.index,
    required this.name,
    required this.weight,
    required this.description,
    required this.maximum,
    required this.enabled,
    required this.showTarget,
    required this.target,
    required this.onTargetChanged,
    required this.onChanged,
    this.onMoveUp,
    this.onMoveDown,
    this.onRemove,
  });

  final int index, maximum;
  final TextEditingController name, weight, description;
  final bool enabled, showTarget;
  final String target;
  final ValueChanged<String> onTargetChanged;
  final VoidCallback onChanged;
  final VoidCallback? onMoveUp, onMoveDown, onRemove;

  TextStyle _body(BuildContext context) => DefensysTokens.body.copyWith(
    color: DefensysTokens.textPrimaryOf(context),
  );

  Widget _field(BuildContext context, String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: DefensysTokens.tableCell.copyWith(
          fontWeight: FontWeight.w600,
          color: DefensysTokens.textPrimaryOf(context),
        ),
      ),
      const SizedBox(height: 8),
      child,
    ],
  );

  Widget _action(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    bool destructive = false,
  }) => ShadTooltip(
    builder: (_) => Text(label),
    child: ShadButton.ghost(
      key: ValueKey('criterion-$index-$label'),
      size: ShadButtonSize.sm,
      width: 36,
      height: 36,
      padding: EdgeInsets.zero,
      enabled: enabled && onPressed != null,
      onPressed: enabled ? onPressed : null,
      child: Semantics(
        label: label,
        child: Icon(
          icon,
          size: 16,
          color: destructive ? const Color(0xFFDC2626) : null,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: ShadCard(
      padding: const EdgeInsets.all(20),
      radius: BorderRadius.circular(8),
      shadows: const [],
      backgroundColor: DefensysTokens.surfaceOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Criterion ${index + 1}',
                  style: DefensysTokens.tableCell.copyWith(
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ),
              _action('Move up', LucideIcons.arrowUp, onMoveUp),
              _action('Move down', LucideIcons.arrowDown, onMoveDown),
              if (onRemove != null)
                _action(
                  'Remove criterion',
                  LucideIcons.trash2,
                  onRemove,
                  destructive: true,
                ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final title = _field(
                context,
                'Criterion name',
                ShadInput(
                  key: ValueKey('criterion-name-$index'),
                  controller: name,
                  enabled: enabled,
                  style: _body(context),
                  padding: const EdgeInsets.all(12),
                  placeholder: const Text('e.g. Technical implementation'),
                  onChanged: (_) => onChanged(),
                ),
              );
              final allocation = _field(
                context,
                'Weight',
                ShadInput(
                  key: ValueKey('criterion-weight-$index'),
                  controller: weight,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: _body(context),
                  padding: const EdgeInsets.all(12),
                  trailing: Text('%', style: _body(context)),
                  onChanged: (_) => onChanged(),
                ),
              );
              if (constraints.maxWidth < 480) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [title, const SizedBox(height: 16), allocation],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 16),
                  SizedBox(width: 120, child: allocation),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _field(
            context,
            'Evaluation guidelines',
            ShadInput(
              key: ValueKey('criterion-description-$index'),
              controller: description,
              enabled: enabled,
              minLines: 2,
              maxLines: 5,
              style: _body(context),
              padding: const EdgeInsets.all(12),
              placeholder: const Text(
                'Describe what earns full or partial credit.',
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ShadBadge.secondary(child: Text('$maximum points maximum')),
              if (showTarget)
                ShadRadioGroup<String>(
                  initialValue: target,
                  enabled: enabled,
                  axis: Axis.horizontal,
                  spacing: 16,
                  runSpacing: 12,
                  onChanged: (value) {
                    if (value != null && value != target) {
                      onTargetChanged(value);
                    }
                  },
                  items: [
                    ShadRadio(
                      value: 'team',
                      label: Text('Team', style: _body(context)),
                    ),
                    ShadRadio(
                      value: 'individual',
                      label: Text('Individual', style: _body(context)),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
