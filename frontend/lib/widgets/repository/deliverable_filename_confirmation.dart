import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';

Future<bool> confirmDeliverableFilename(
  BuildContext context, {
  required String originalName,
  required String repositoryName,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => DefensysShadcnScope(
      maroonActions: true,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ShadDialog(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.sizeOf(dialogContext).height - 24,
          ),
          removeBorderRadiusWhenTiny: false,
          expandActionsWhenTiny: false,
          actionsAxis:
              MediaQuery.sizeOf(dialogContext).width < 420 ||
                  MediaQuery.textScalerOf(dialogContext).scale(1) > 1.15
              ? Axis.vertical
              : Axis.horizontal,
          scrollable: true,
          titlePinned: true,
          actionsPinned: true,
          title: const Text('Filename will be adjusted'),
          description: const Text(
            'Your file will be saved with the required repository name.',
          ),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ShadButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Rename and upload'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in {
                'Your file': originalName,
                'Repository name': repositoryName,
              }.entries) ...[
                const SizedBox(height: 16),
                Text(
                  entry.key,
                  style: DefensysTokens.caption.copyWith(
                    color: DefensysTokens.textSecondaryOf(dialogContext),
                    fontFamily: DefensysTokens.fontFamilyInter,
                  ),
                ),
                const SizedBox(height: 4),
                Text(entry.value),
              ],
            ],
          ),
        ),
      ),
    ),
  );
  return confirmed == true;
}
