import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/defensys_skeleton.dart';
import 'overview_panel_row.dart';

/// Reserves the overview's responsive layout while its first response loads.
class AdminOverviewSkeleton extends StatelessWidget {
  const AdminOverviewSkeleton({super.key, required this.scope});

  final String scope;

  @override
  Widget build(BuildContext context) {
    Widget bone(double width, {double height = 14}) => FractionallySizedBox(
      widthFactor: width,
      alignment: Alignment.centerLeft,
      child: DefensysSkeleton.box(
        height: height,
        borderRadius: DefensysTokens.radiusSm,
        color: DefensysTokens.borderOf(context),
      ),
    );

    Widget card(List<Widget> children, {Key? key}) => ShadCard(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      backgroundColor: DefensysTokens.surfaceOf(context),
      border: ShadBorder.all(color: DefensysTokens.borderOf(context)),
      radius: BorderRadius.circular(DefensysTokens.radiusLg),
      shadows: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );

    Widget attention() => card([
      bone(.45, height: 16),
      for (var i = 0; i < 2; i++) ...[
        const SizedBox(height: 20),
        Divider(height: 1, color: DefensysTokens.borderOf(context)),
        const SizedBox(height: 16),
        bone(.65),
        const SizedBox(height: 10),
        bone(.9, height: 12),
        const SizedBox(height: 14),
        bone(.25, height: 12),
      ],
    ]);

    final readiness = card([
      bone(.4, height: 16),
      const SizedBox(height: 24),
      bone(.15, height: 32),
      const SizedBox(height: 10),
      bone(.5, height: 12),
      const SizedBox(height: 16),
      Divider(height: 1, color: DefensysTokens.borderOf(context)),
      const SizedBox(height: 16),
      bone(.8, height: 12),
      const SizedBox(height: 18),
      bone(.25, height: 12),
    ], key: const ValueKey('overview-skeleton-readiness'));
    final schedule = card([
      bone(.3, height: 16),
      const SizedBox(height: 32),
      bone(.4),
      const SizedBox(height: 20),
      bone(.2, height: 36),
      const SizedBox(height: 16),
      bone(.6, height: 12),
      const SizedBox(height: 20),
      Row(
        children: [
          for (var day = 0; day < 7; day++) ...[
            if (day > 0) const SizedBox(width: 4),
            Expanded(
              child: Column(
                children: [
                  bone(.4, height: 10),
                  const SizedBox(height: 10),
                  bone(1, height: 58),
                ],
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 16),
      Divider(height: 1, color: DefensysTokens.borderOf(context)),
      const SizedBox(height: 20),
      bone(.7),
      const SizedBox(height: 16),
      bone(.4, height: 12),
    ], key: const ValueKey('overview-skeleton-schedule'));

    return Semantics(
      label: 'Loading overview',
      liveRegion: true,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pit = scope == 'pit';
            final width = constraints.maxWidth;
            final columns = pit
                ? (width / MediaQuery.textScalerOf(context).scale(1) >= 1000
                      ? 3
                      : width / MediaQuery.textScalerOf(context).scale(1) >= 650
                      ? 2
                      : 1)
                : width >= 1000
                ? 5
                : width >= 650
                ? 3
                : width >= 480
                ? 2
                : 1;
            final gap = pit ? 16.0 : 12.0;
            final leading = Column(
              children: [readiness, const SizedBox(height: 16), attention()],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                bone(.15),
                const SizedBox(height: 12),
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (var i = 0; i < (pit ? 3 : 5); i++)
                      SizedBox(
                        width: (width - (columns - 1) * gap) / columns,
                        child: card([
                          bone(.5),
                          const SizedBox(height: 20),
                          bone(.25, height: 28),
                          const SizedBox(height: 12),
                          bone(.65, height: 12),
                          if (pit) ...[
                            const SizedBox(height: 24),
                            bone(.8, height: 32),
                            const SizedBox(height: 24),
                            bone(.5),
                            const SizedBox(height: 24),
                            bone(.4, height: 32),
                          ],
                        ], key: ValueKey('overview-skeleton-card-$i')),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (pit)
                  attention()
                else if (width < 900) ...[
                  leading,
                  const SizedBox(height: 16),
                  schedule,
                ] else
                  OverviewPanelRow(leading: leading, schedule: schedule),
                const SizedBox(height: 16),
                card([bone(.15)]),
              ],
            );
          },
        ),
      ),
    );
  }
}
