import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/theme/defensys_tokens.dart';

class DocumenterWorkload {
  const DocumenterWorkload({
    required this.id,
    required this.name,
    required this.teams,
    required this.eligible,
  });
  final int id, teams;
  final String name;
  final bool eligible;
}

/// Read-only distribution of the current roster's documenter assignments.
class DocumenterWorkloadSummary extends StatelessWidget {
  const DocumenterWorkloadSummary({super.key, required this.items});

  final List<DocumenterWorkload> items;

  TextStyle _muted(BuildContext context) => TextStyle(
    fontFamily: DefensysTokens.fontFamilyInter,
    fontSize: 12,
    color: DefensysTokens.textSecondaryOf(context),
  );

  Widget _assignment(BuildContext context, DocumenterWorkload item, int total) {
    final label = item.teams == 0
        ? 'Unassigned'
        : '${item.teams} ${item.teams == 1 ? 'team' : 'teams'}';
    return Semantics(
      container: true,
      label:
          '${item.name}: $label. '
          '${item.teams} of $total assigned teams.'
          '${item.eligible ? '' : ' Existing assignment outside the available role list.'}',
      excludeSemantics: true,
      child: Column(
        key: ValueKey('documenter-workload-${item.id}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                key: ValueKey('documenter-${item.id}-teams'),
                style: TextStyle(
                  fontFamily: DefensysTokens.fontFamilyInter,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontSize: 13,
                  fontWeight: item.teams == 0
                      ? FontWeight.w400
                      : FontWeight.w600,
                  color: item.teams == 0
                      ? DefensysTokens.textSecondaryOf(context)
                      : DefensysTokens.textPrimaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ShadProgress(
            value: total == 0 ? 0 : item.teams / total,
            minHeight: 5,
            color: DefensysTokens.maroonOf(context),
            backgroundColor: DefensysTokens.borderOf(context),
            borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
            innerBorderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
          ),
          if (!item.eligible) ...[
            const SizedBox(height: 8),
            Text(
              'Existing assignment · outside the available role list',
              style: _muted(context),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(
        'No eligible documenters are available. Assign the Documenter role in User Management.',
        style: _muted(context),
      );
    }
    final total = items.fold<int>(0, (sum, item) => sum + item.teams);
    return LayoutBuilder(
      builder: (context, constraints) {
        var columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        if (items.length < columns) {
          columns = items.length;
        }
        const gap = 32.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: 24,
              children: [
                for (final item in items)
                  SizedBox(
                    width: width,
                    child: _assignment(context, item, total),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              total == 0
                  ? 'Workload updates as you choose documenters above.'
                  : 'Bar length shows each documenter’s share of the assigned teams.',
              style: _muted(context),
            ),
          ],
        );
      },
    );
  }
}
