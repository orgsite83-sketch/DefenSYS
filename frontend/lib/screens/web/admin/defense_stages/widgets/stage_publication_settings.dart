import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';

class StagePublicationSettings extends StatelessWidget {
  const StagePublicationSettings({
    super.key,
    required this.published,
    required this.onChanged,
    this.currentlyPublished = false,
    this.enabled = true,
    this.lockReason,
  });

  final bool published, currentlyPublished, enabled;
  final ValueChanged<bool> onChanged;
  final String? lockReason;

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DefensysTokens.backgroundOf(context),
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Published stage',
                  style: DefensysTokens.body.copyWith(
                    color: DefensysTokens.textPrimaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  lockReason ??
                      (published
                          ? 'Publish this stage when you save.'
                          : currentlyPublished
                          ? 'Save to return this stage to draft.'
                          : 'Keep this stage as a draft.'),
                  style: DefensysTokens.subtitle.copyWith(
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Semantics(
            label: 'Published stage',
            child: ShadSwitch(
              key: const ValueKey('stage-publication-switch'),
              value: published,
              enabled: enabled && lockReason == null,
              checkedTrackColor: DefensysTokens.maroonOf(context),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    ),
  );
}
