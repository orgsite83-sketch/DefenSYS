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
    this.isNew = false,
  });

  final bool published, currentlyPublished, enabled;
  final ValueChanged<bool> onChanged;
  final String? lockReason;
  final bool isNew;

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  currentlyPublished ? 'Published' : 'Draft',
                  key: const ValueKey('stage-saved-publication-status'),
                  style: DefensysTokens.body.copyWith(
                    color: DefensysTokens.textPrimaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  lockReason ??
                      (published && !currentlyPublished
                          ? 'Will publish when you save.'
                          : currentlyPublished
                          ? (published
                                ? 'Changes apply when you save.'
                                : 'Will return to draft when you save.')
                          : isNew
                          ? 'Not yet saved to Defense Stages.'
                          : 'Saved as an unpublished stage.'),
                  style: DefensysTokens.subtitle.copyWith(
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Publish on save',
                style: DefensysTokens.caption.copyWith(
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 4),
              Semantics(
                label: 'Publish on save',
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
        ],
      ),
    ),
  );
}
