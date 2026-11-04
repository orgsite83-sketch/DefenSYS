import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';

class CapstoneBatchFilters extends ConsumerWidget {
  const CapstoneBatchFilters({super.key, required this.state});
  final CapstoneDeliverablesState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 340 ? constraints.maxWidth : 320.0;
        Widget picker(
          String label,
          String value,
          Map<String, String> options,
          ValueChanged<String> onChanged,
        ) {
          return DefensysShadcnScope(
            child: Semantics(
              label: label,
              child: ShadSelect<String>(
                key: ValueKey('$label:$value'),
                initialValue: value,
                enabled: !state.isLoading && !state.isSaving,
                minWidth: width,
                maxWidth: width,
                maxHeight: 320,
              decoration: ShadDecoration(
                color: DefensysTokens.surfaceHigherOf(context),
                border: ShadBorder.all(
                  color: DefensysTokens.borderOf(context),
                  radius: BorderRadius.circular(8),
                ),
              ),
                options: options.entries
                    .map(
                      (entry) => ShadOption<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                selectedOptionBuilder: (context, value) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 10,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                    Text(
                      options[value] ?? value,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: DefensysTokens.fontFamilyInter,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                onChanged: (value) {
                  if (value != null) onChanged(value);
                },
              ),
            ),
          );
        }

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            picker(
              'Capstone batch',
              state.batchId,
              {
                '': 'All batches',
                for (final option in state.batchOptions)
                  '${option['value']}': '${option['label']}',
              },
              (batch) => ref
                  .read(capstoneDeliverablesProvider.notifier)
                  .selectBatchFilters(batch, state.participation),
            ),
            picker(
              'Participation',
              state.participation,
              const {
                'ongoing': 'Ongoing',
                'completed': 'Completed',
                'failed': 'Failed',
                'all': 'All participations',
              },
              (participation) => ref
                  .read(capstoneDeliverablesProvider.notifier)
                  .selectBatchFilters(state.batchId, participation),
            ),
          ],
        );
      },
    );
  }
}
