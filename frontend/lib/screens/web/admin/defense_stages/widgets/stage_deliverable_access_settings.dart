import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/repository/deliverable_timing_fields.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';

/// File access choices stay visible beside the basic requirement settings.
class StageDeliverableAccessSettings extends StatelessWidget {
  const StageDeliverableAccessSettings({
    super.key,
    required this.isPost,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool isPost, value, enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!isPost) {
      return DefenseMaterialToggle(
        key: const ValueKey('stage-deliverable-defense-material'),
        value: value,
        enabled: enabled,
        onChanged: onChanged,
      );
    }
    return DefensysShadcnScope(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ShadCheckbox(
              key: const ValueKey('stage-deliverable-restricted'),
              value: value,
              enabled: enabled,
              onChanged: onChanged,
              label: Text(
                'Restricted (private institutional archive)',
                style: DefensysTokens.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message:
                'Private for faculty and admin records only; hidden from students.',
            constraints: const BoxConstraints(maxWidth: 240),
            child: Icon(
              Icons.help_outline_rounded,
              size: 14,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}
