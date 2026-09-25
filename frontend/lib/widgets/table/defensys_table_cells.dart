import 'package:flutter/material.dart';
import '../../theme/defensys_tokens.dart';
import 'defensys_table_tokens.dart';

/// Descriptor for items in [DefensysTableCell.actionMenu].
class DefensysActionMenuItem {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool isDestructive;
  final bool isEnabled;

  const DefensysActionMenuItem({
    required this.label,
    this.icon,
    required this.onTap,
    this.isDestructive = false,
    this.isEnabled = true,
  });
}

/// Standardized cell components for consistent typography, badges, and actions.
class DefensysTableCell {
  DefensysTableCell._();

  /// Primary title with an optional secondary subtitle, icon, and metadata line.
  static Widget titleWithMeta({
    required String title,
    String? subtitle,
    IconData? subtitleIcon,
    Widget? trailingBadge,
    int titleMaxLines = 1,
    int subtitleMaxLines = 1,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: titleMaxLines,
                overflow: TextOverflow.ellipsis,
                style: DefensysTableTokens.cellPrimaryTextStyle,
              ),
            ),
            if (trailingBadge != null) ...[
              const SizedBox(width: 6),
              trailingBadge,
            ],
          ],
        ),
        if (subtitle != null && subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (subtitleIcon != null) ...[
                Icon(
                  subtitleIcon,
                  size: 12,
                  color: DefensysTableTokens.cellSecondaryTextStyle.color,
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  subtitle,
                  maxLines: subtitleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: DefensysTableTokens.cellSecondaryTextStyle,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Subtle rounded tag badge (e.g. for Defense Stage or Course).
  static Widget stageBadge(String stageName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Text(
        stageName.isEmpty ? '-' : stageName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: DefensysTokens.fontFamily,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF334155),
        ),
      ),
    );
  }

  /// Compact pill badge for Scope (PIT / Capstone).
  static Widget scopeBadge(String scope) {
    final isPit = scope.trim().toLowerCase() == 'pit';
    final fg = isPit ? const Color(0xFF16A34A) : const Color(0xFF2563EB);
    final bg = isPit ? const Color(0xFFF0FDF4) : const Color(0xFFEFF6FF);
    final border = isPit ? const Color(0xFFBBF7D0) : const Color(0xFFBFDBFE);

    final displayLabel = scope.trim().isEmpty
        ? 'General'
        : (isPit ? 'PIT' : 'Capstone');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: border),
      ),
      child: Text(
        displayLabel,
        style: TextStyle(
          fontFamily: DefensysTokens.fontFamily,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: fg,
        ),
      ),
    );
  }

  /// Compact evaluation type badge with icon (Peer, Panel, Adviser).
  static Widget evalBadge(String evalType) {
    final type = evalType.trim().toLowerCase();
    final isPeer = type == 'peer';
    final fg = isPeer ? const Color(0xFF2563EB) : const Color(0xFFDC2626);
    final bg = isPeer ? const Color(0xFFEFF6FF) : const Color(0xFFFEF2F2);
    final border = isPeer ? const Color(0xFFBFDBFE) : const Color(0xFFFECACA);
    final icon = isPeer ? Icons.people_outline_rounded : Icons.groups_rounded;
    final label = isPeer ? 'Peer' : (type.isEmpty ? 'General' : 'Panel');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  /// Standardized 3-dots action button and popup menu.
  static Widget actionMenu({
    required List<DefensysActionMenuItem> items,
    String tooltip = 'Row actions',
  }) {
    return PopupMenuButton<int>(
      tooltip: tooltip,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      elevation: 6,
      color: Colors.white,
      padding: EdgeInsets.zero,
      icon: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Icon(
          Icons.more_horiz_rounded,
          size: 18,
          color: Color(0xFF64748B),
        ),
      ),
      onSelected: (index) {
        if (index >= 0 && index < items.length) {
          items[index].onTap();
        }
      },
      itemBuilder: (context) {
        return List.generate(items.length, (index) {
          final item = items[index];
          final color = item.isDestructive
              ? const Color(0xFFDC2626)
              : const Color(0xFF334155);

          return PopupMenuItem<int>(
            value: index,
            enabled: item.isEnabled,
            height: 38,
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: 16, color: color),
                  const SizedBox(width: 10),
                ],
                Text(
                  item.label,
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}
