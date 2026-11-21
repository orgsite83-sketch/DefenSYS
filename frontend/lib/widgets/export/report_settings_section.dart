import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';

/// A neutral disclosure header keeps secondary report settings together.
class ReportSettingsSection extends StatelessWidget {
  const ReportSettingsSection({
    super.key,
    required this.title,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.triggerKey,
  });

  final String title;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final Key? triggerKey;

  @override
  Widget build(BuildContext context) {
    final foreground = DefensysTokens.textPrimaryOf(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: DefensysTokens.borderOf(context)),
        borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: expanded,
            child: ShadButton.ghost(
              key: triggerKey,
              onPressed: onToggle,
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              backgroundColor: DefensysTokens.backgroundOf(context),
              hoverBackgroundColor: DefensysTokens.surfaceHigherOf(context),
              foregroundColor: foreground,
              hoverForegroundColor: foreground,
              leading: Icon(icon, size: 17),
              child: Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontFamily: DefensysTokens.fontFamilyInter,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: foreground,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, color: DefensysTokens.borderOf(context)),
            Padding(padding: const EdgeInsets.all(14), child: child),
          ],
        ],
      ),
    );
  }
}
