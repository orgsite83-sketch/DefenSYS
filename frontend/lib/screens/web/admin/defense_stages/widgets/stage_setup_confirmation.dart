import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../theme/defensys_tokens.dart';
import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';

Future<bool> showStageSetupConfirmation(
  BuildContext context, {
  required String title,
  required String description,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => DefensysShadcnScope(
      child: ShadDialog.alert(
        constraints: const BoxConstraints(maxWidth: 520),
        title: Text(title),
        description: Text(description),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          if (destructive)
            ShadButton.destructive(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel),
            )
          else
            ShadButton(
              backgroundColor: DefensysTokens.maroonOf(context),
              foregroundColor: Colors.white,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel),
            ),
        ],
      ),
    ),
  );
  return result == true;
}
