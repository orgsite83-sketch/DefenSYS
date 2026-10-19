import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';
import 'defensys_shadcn_scope.dart';

export 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;

/// A breadcrumb item representing a single step in navigation hierarchy.
class DefensysBreadcrumbItem {
  final String label;
  final Widget? icon;
  final VoidCallback? onTap;
  final bool isCurrent;

  const DefensysBreadcrumbItem({
    required this.label,
    this.icon,
    this.onTap,
    this.isCurrent = false,
  });
}

/// A shadcn-styled breadcrumb navigation bar with optional back button,
/// smooth hover transitions, and clean active hierarchy states.
class DefensysBreadcrumb extends StatelessWidget {
  final List<DefensysBreadcrumbItem> items;
  final VoidCallback? onBack;
  final String backLabel;
  final Widget? separator;
  final double spacing;
  final Widget? trailing;

  const DefensysBreadcrumb({
    super.key,
    required this.items,
    this.onBack,
    this.backLabel = 'Back',
    this.separator,
    this.spacing = 6.0,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final dark = DefensysTokens.isDark(context);

    final effectiveSeparator = separator ??
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing),
          child: Icon(
            LucideIcons.chevronRight,
            size: 13.5,
            color: dark ? const Color(0xFF71717A) : const Color(0xFF94A3B8),
          ),
        );

    final List<Widget> breadcrumbWidgets = [];
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final isLast = i == items.length - 1;
      final isCurrent = item.isCurrent || (isLast && item.onTap == null);

      if (isCurrent) {
        breadcrumbWidgets.add(
          _BreadcrumbCurrent(
            item: item,
            isDark: dark,
          ),
        );
      } else {
        breadcrumbWidgets.add(
          _BreadcrumbLink(
            item: item,
            isDark: dark,
          ),
        );
      }

      if (!isLast) {
        breadcrumbWidgets.add(effectiveSeparator);
      }
    }

    return DefensysShadcnScope(
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 6,
        children: [
          if (onBack != null) ...[
            ShadButton.outline(
              size: ShadButtonSize.sm,
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              leading: const Icon(LucideIcons.arrowLeft, size: 14),
              onPressed: onBack,
              child: Text(
                backLabel,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              height: 16,
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: dark ? DefensysTokens.mistBorder : const Color(0xFFE2E8F0),
            ),
          ],
          ...breadcrumbWidgets,
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _BreadcrumbLink extends StatefulWidget {
  final DefensysBreadcrumbItem item;
  final bool isDark;

  const _BreadcrumbLink({
    required this.item,
    required this.isDark,
  });

  @override
  State<_BreadcrumbLink> createState() => _BreadcrumbLinkState();
}

class _BreadcrumbLinkState extends State<_BreadcrumbLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final normalColor = widget.isDark
        ? DefensysTokens.textSecondaryDark
        : const Color(0xFF64748B);
    final hoverColor = widget.isDark
        ? DefensysTokens.textPrimaryDark
        : const Color(0xFF0F172A);
    final currentColor = _hovered ? hoverColor : normalColor;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.item.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.isDark
                    ? const Color(0xFF27272A)
                    : const Color(0xFFF1F5F9))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.item.icon != null) ...[
                IconTheme.merge(
                  data: IconThemeData(
                    size: 14,
                    color: currentColor,
                  ),
                  child: widget.item.icon!,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                widget.item.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: DefensysTokens.fontFamilyInter,
                  color: currentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreadcrumbCurrent extends StatelessWidget {
  final DefensysBreadcrumbItem item;
  final bool isDark;

  const _BreadcrumbCurrent({
    required this.item,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark
        ? DefensysTokens.textPrimaryDark
        : const Color(0xFF0F172A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.icon != null) ...[
            IconTheme.merge(
              data: IconThemeData(
                size: 14,
                color: textColor,
              ),
              child: item.icon!,
            ),
            const SizedBox(width: 5),
          ],
          Text(
            item.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: DefensysTokens.fontFamilyInter,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
