import 'package:flutter/material.dart';
import 'package:defensys/theme/defensys_tokens.dart';

class StageMinutesSettings extends StatelessWidget {
  const StageMinutesSettings({
    super.key,
    required this.requiredMinutes,
    required this.enabled,
    required this.onChanged,
  });
  final bool requiredMinutes, enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget option(bool value, String title, String description) => Semantics(
      selected: requiredMinutes == value,
      child: InkWell(
        onTap: enabled ? () => onChanged(value) : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: requiredMinutes == value
                ? theme.colorScheme.primary.withValues(alpha: .06)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: requiredMinutes == value
                  ? theme.colorScheme.primary
                  : theme.dividerColor,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                requiredMinutes == value
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(description, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Session documentation', style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final yes = option(
              true,
              'Signed minutes required',
              'Assign a documenter to prepare and sign official minutes.',
            );
            final no = option(
              false,
              'Minutes not required',
              'For exhibits and showcases without official minutes.',
            );
            return constraints.maxWidth < 600
                ? Column(children: [yes, const SizedBox(height: 10), no])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: yes),
                      const SizedBox(width: 12),
                      Expanded(child: no),
                    ],
                  );
          },
        ),
        const SizedBox(height: 8),
        Text(
          requiredMinutes
              ? 'Adds a system-generated signed-minutes deliverable in Step 3. Documenter assignment is required when scheduling.'
              : 'No documenter assignment or signed-minutes requirement for this stage.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class StageMinutesDeliverableCard extends StatelessWidget {
  const StageMinutesDeliverableCard({
    super.key,
    required this.number,
    required this.name,
    required this.stageName,
    required this.enabled,
    required this.onConfigure,
  });
  final TextEditingController number, name;
  final String stageName;
  final bool enabled;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DefensysTokens.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'System-generated Defense Records',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text('1 item', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'The signed PDF is provided automatically by the documenter workflow.',
            style: theme.textTheme.bodySmall,
          ),
          const Divider(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              final numberField = TextField(
                key: const ValueKey('minutes-deliverable-number'),
                controller: number,
                readOnly: !enabled,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: 'Official deliverable number',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              );
              final nameField = TextField(
                key: const ValueKey('minutes-deliverable-name'),
                controller: name,
                readOnly: !enabled,
                maxLength: 180,
                decoration: InputDecoration(
                  labelText: 'Official deliverable name',
                  hintText: 'Signed Minutes - $stageName',
                  counterText: '',
                  border: const OutlineInputBorder(),
                ),
              );
              return constraints.maxWidth < 600
                  ? Column(
                      children: [
                        numberField,
                        const SizedBox(height: 12),
                        nameField,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: numberField),
                        const SizedBox(width: 12),
                        Expanded(flex: 3, child: nameField),
                      ],
                    );
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: const [
              Text('Responsible: Assigned documenter'),
              Text('Source: System generated'),
              Text('Format: PDF'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Completed after all required signatures. Applies to conducted defenses regardless of result.',
            style: theme.textTheme.bodySmall,
          ),
          TextButton.icon(
            onPressed: onConfigure,
            icon: const Icon(Icons.settings_outlined, size: 16),
            label: const Text('Required · Set in Stage Details'),
          ),
        ],
      ),
    );
  }
}
