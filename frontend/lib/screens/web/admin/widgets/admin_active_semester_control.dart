import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';

/// Opens period management without implying that the active term can be
/// switched independently of the academic-period workflow.
class AdminActiveSemesterControl extends StatelessWidget {
  const AdminActiveSemesterControl({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final value = label.replaceFirst(RegExp(r'^Active(?: Sem)?:\s*'), '');
    final hasSemester = value.toLowerCase() != 'no active semester';
    final foreground = DefensysTokens.textPrimaryOf(context);
    return DefensysShadcnScope(
      maroonActions: true,
      child: Tooltip(
        message: '$value\nManage academic periods',
        child: ShadButton.outline(
          key: const ValueKey('admin-active-semester'),
          height: 56 * MediaQuery.textScalerOf(context).scale(1),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          backgroundColor: DefensysTokens.panelOf(context),
          onPressed: onPressed,
          child: Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: DefensysTokens.textSecondaryOf(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasSemester ? 'Active semester' : 'Academic period',
                        style: DefensysTokens.caption.copyWith(
                          fontSize: 11,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DefensysTokens.body.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: foreground,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.chevron_right_rounded, size: 16, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
