import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../theme/defensys_tokens.dart';

List<Map<String, dynamic>> detailRows(dynamic value) => (value as List? ?? [])
    .whereType<Map>()
    .map((row) => Map<String, dynamic>.from(row))
    .toList();

class TeamContextSelect extends StatelessWidget {
  const TeamContextSelect({
    super.key,
    required this.labels,
    required this.value,
    required this.label,
    required this.onChanged,
    this.enabled = true,
  });
  final List<String> labels;
  final String value;
  final String label;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: DefensysTokens.caption.copyWith(
          color: DefensysTokens.textSecondaryOf(context),
        ),
      ),
      const SizedBox(height: 6),
      if (labels.length <= 1)
        Text(
          labels.firstOrNull ?? 'None assigned',
          style: DefensysTokens.body.copyWith(
            fontWeight: FontWeight.w600,
            color: DefensysTokens.textPrimaryOf(context),
          ),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) => ShadSelect<String>(
            key: ValueKey('team-context-$value'),
            initialValue: value,
            enabled: enabled,
            minWidth: 200,
            maxWidth: constraints.maxWidth.clamp(200, 420),
            options: [
              for (final text in labels)
                ShadOption(value: text, child: Text(text, softWrap: true)),
            ],
            selectedOptionBuilder: (context, selected) =>
                Text(selected, overflow: TextOverflow.ellipsis),
            onChanged: (selected) {
              if (selected != null) onChanged(selected);
            },
          ),
        ),
    ],
  );
}

class TeamDetailNotice extends StatelessWidget {
  const TeamDetailNotice({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: DefensysTokens.body.copyWith(
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ],
    ),
  );
}
