import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../shadcn/defensys_action_menu.dart';
import '../shadcn/defensys_shadcn_scope.dart';

/// Secondary history access, shared by defense outcomes and section systems.
class DefenseHistoryMenu extends StatelessWidget {
  const DefenseHistoryMenu({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: DefensysActionMenu(
      label: 'More history actions',
      items: [
        DefensysMenuItem(
          label: label,
          icon: LucideIcons.history,
          onPressed: onPressed,
        ),
      ],
    ),
  );
}

Future<void> showDefenseHistoryDialog(
  BuildContext context, {
  required String title,
  required Widget child,
}) => showDialog<void>(
  context: context,
  builder: (context) => DefensysShadcnScope(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: ShadDialog(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: MediaQuery.sizeOf(context).height - 48,
        ),
        removeBorderRadiusWhenTiny: false,
        scrollable: true,
        titlePinned: true,
        actionsPinned: true,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        title: Text(title),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
        child: Material(type: MaterialType.transparency, child: child),
      ),
    ),
  ),
);
