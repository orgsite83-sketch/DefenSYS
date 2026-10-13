import 'package:flutter/material.dart';

import '../../../../../theme/defensys_tokens.dart';

class StageSetupDraftNotice extends StatelessWidget {
  const StageSetupDraftNotice({
    super.key,
    required this.title,
    required this.onDiscard,
    this.onResume,
  });

  final String title;
  final VoidCallback onDiscard;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: DefensysTokens.surfaceOf(context),
      border: Border.all(color: DefensysTokens.borderOf(context)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.save_outlined, color: DefensysTokens.maroonOf(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Saved in this browser. Continue your setup when ready.',
                    style: TextStyle(
                      fontSize: 12,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (onResume != null)
              OutlinedButton(
                onPressed: onResume,
                child: const Text('Resume draft'),
              ),
            TextButton(
              onPressed: onDiscard,
              child: const Text('Discard draft'),
            ),
          ],
        ),
      ],
    ),
  );
}
