import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../shadcn/defensys_shadcn_scope.dart';

class DefenseMaterialToggle extends StatelessWidget {
  const DefenseMaterialToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = isDark
        ? const Color(0xFFF1F5F9)
        : const Color(0xFF1E293B);
    final secondaryColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: DefensysShadcnScope(
            child: ShadCheckbox(
              value: value,
              enabled: enabled,
              onChanged: onChanged,
              label: Text(
                'Defense material for panelists',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message:
              'Panelists use this file during oral defense. Required files still need faculty acceptance before endorsement.',
          constraints: const BoxConstraints(maxWidth: 240),
          child: Icon(
            Icons.help_outline_rounded,
            size: 14,
            color: secondaryColor,
          ),
        ),
      ],
    );
  }
}

/// One review rule for all pre-defense files. Retired arguments are accepted
/// for existing callers; they never enable another timing option.
class DeliverableTimingFields extends StatelessWidget {
  const DeliverableTimingFields({
    super.key,
    this.timing = 'scheduling',
    this.hoursBefore = 24,
    this.onTimingChanged,
    this.onHoursChanged,
    this.enabled = true,
    this.showTimingChoices = false,
    this.isDefenseMaterial = false,
  });

  final String timing;
  final int hoursBefore;
  final ValueChanged<String>? onTimingChanged;
  final ValueChanged<int>? onHoursChanged;
  final bool enabled;
  final bool showTimingChoices;
  final bool isDefenseMaterial;

  @override
  Widget build(BuildContext context) => Text(
    'Required pre-defense files need adviser/instructor acceptance before '
    'endorsement and scheduling.',
    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
  );
}
