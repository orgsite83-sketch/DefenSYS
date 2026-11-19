import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';

/// Scope saved grading assignments independently from the library's filters.
class RubricExportFilters extends StatelessWidget {
  const RubricExportFilters({
    super.key,
    required this.params,
    required this.options,
    required this.loading,
    required this.error,
    required this.onChanged,
    required this.onRetry,
  });

  final Map<String, String> params;
  final Map<String, dynamic> options;
  final bool loading;
  final String? error;
  final ValueChanged<Map<String, String>> onChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final pit = params['scope'] == 'pit';
    final destinationKey = pit ? 'pit_event_config_id' : 'stage_id';
    final destinations = <String, String>{
      '': pit ? 'All events' : 'All stages',
      for (final row
          in (options[pit ? 'pit_events' : 'stages'] as List? ?? [])
              .whereType<Map>())
        if ((row['semester_id'] == null ||
                '${row['semester_id']}' == params['semester_id']) &&
            (row['year_level'] == null ||
                (params['year_level'] ?? '').isEmpty ||
                row['year_level'] == params['year_level']))
          '${row['id']}': '${row['label']}',
    };
    final semester = (options['semesters'] as List? ?? [])
        .whereType<Map>()
        .where((row) => '${row['id']}' == params['semester_id'])
        .firstOrNull;
    return DefensysShadcnScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Rubric selection',
            style: DefensysTokens.sectionTitle.copyWith(
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${pit ? 'PIT' : 'Capstone'} · ${semester?['label'] ?? 'Selected academic period'}',
            style: DefensysTokens.caption.copyWith(
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 20),
          if (loading) const LinearProgressIndicator(),
          if (error != null) ...[
            Text(
              error!,
              style: DefensysTokens.caption.copyWith(
                color: DefensysTokens.textPrimaryOf(context),
              ),
            ),
            ShadButton.outline(
              onPressed: onRetry,
              child: const Text('Retry selections'),
            ),
            const SizedBox(height: 12),
          ],
          _selector(
            context,
            destinationKey,
            pit ? 'PIT event' : 'Defense stage',
            destinations,
          ),
          const SizedBox(height: 20),
          _selector(context, 'evaluation_type', 'Evaluation type', {
            '': 'All evaluation types',
            'panel': 'Panel only',
            if (!pit) 'adviser': 'Adviser only',
            'peer': 'Peer only',
          }),
          const SizedBox(height: 20),
          Text(
            'Exports include saved rubrics. Save changes before exporting.',
            style: DefensysTokens.caption.copyWith(
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selector(
    BuildContext context,
    String key,
    String label,
    Map<String, String> choices,
  ) {
    final value = params[key] ?? '';
    if (!choices.containsKey(value)) {
      choices[value] = loading
          ? 'Loading selection…'
          : 'Selected record unavailable';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: DefensysTokens.tableCell.copyWith(
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 8),
        ShadSelect<String>(
          key: ValueKey('rubric-export-$key:$value:$loading'),
          enabled: !loading && error == null,
          initialValue: value,
          options: choices.entries.map(
            (entry) => ShadOption(
              value: entry.key,
              child: Text(
                entry.value,
                style: DefensysTokens.tableCell.copyWith(
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
            ),
          ),
          selectedOptionBuilder: (_, selected) => Text(
            choices[selected] ?? '',
            overflow: TextOverflow.ellipsis,
            style: DefensysTokens.tableCell.copyWith(
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          onChanged: (selected) => onChanged({...params, key: selected ?? ''}),
        ),
      ],
    );
  }
}
