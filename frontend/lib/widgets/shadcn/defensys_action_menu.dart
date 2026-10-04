import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';
import 'defensys_shadcn_scope.dart';

/// A single, keyboard-accessible entry point for a row's secondary actions.
class DefensysActionMenu extends StatefulWidget {
  const DefensysActionMenu({
    super.key,
    required this.label,
    required this.items,
    this.enabled = true,
    this.triggerLabel,
  });
  final String label;
  final List<Widget> items;
  final bool enabled;
  final String? triggerLabel;

  @override
  State<DefensysActionMenu> createState() => _DefensysActionMenuState();
}

class _DefensysActionMenuState extends State<DefensysActionMenu> {
  final _controller = ShadContextMenuController();

  @override
  void didUpdateWidget(covariant DefensysActionMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _controller.hide();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: TapRegion(
      groupId: _controller,
      onTapOutside: (_) => _controller.hide(),
      child: ShadContextMenu(
        controller: _controller,
        groupId: widget.key ?? _controller,
        anchor: const ShadAnchorAuto(
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.bottomLeft,
          offset: Offset(0, 4),
          fallback: ShadAnchorAuto(
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.topLeft,
            offset: Offset(0, -4),
          ),
        ),
        constraints: const BoxConstraints(minWidth: 228, maxWidth: 280),
        items: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .7,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in widget.items)
                    TapRegion(groupId: _controller, child: item),
                ],
              ),
            ),
          ),
        ],
        child: Semantics(
          button: true,
          label: widget.label,
          child: Tooltip(
            message: widget.label,
            child: widget.triggerLabel != null
                ? ShadButton.outline(
                    enabled: widget.enabled,
                    height: 36,
                    onPressed: widget.enabled ? _controller.toggle : null,
                    trailing: const Icon(LucideIcons.ellipsis, size: 16),
                    child: Text(widget.triggerLabel!),
                  )
                : ShadButton.ghost(
                    enabled: widget.enabled,
                    width: 32,
                    height: 32,
                    padding: EdgeInsets.zero,
                    onPressed: widget.enabled ? _controller.toggle : null,
                    child: const Icon(LucideIcons.ellipsis, size: 18),
                  ),
          ),
        ),
      ),
    ),
  );
}

class DefensysMenuItem extends StatelessWidget {
  const DefensysMenuItem({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.destructive = false,
    this.hint,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final color = onPressed == null
        ? DefensysTokens.textSecondaryOf(context)
        : destructive
        ? Theme.of(context).colorScheme.error
        : DefensysTokens.textPrimaryOf(context);
    return Tooltip(
      message: hint ?? '',
      child: ShadContextMenuItem(
        enabled: onPressed != null,
        onPressed: onPressed,
        leading: Icon(icon, size: 16, color: color),
        textStyle: ShadTheme.of(context).textTheme.small.copyWith(
          fontSize: 13,
          color: color,
          fontWeight: FontWeight.w400,
        ),
        child: Text(label),
      ),
    );
  }
}
