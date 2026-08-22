import 'package:flutter/material.dart';

import '../../theme/defensys_tokens.dart';

/// Standard size presets for [DefensysEmptyState].
enum DefensysEmptyStateSize {
  /// Standard canvas/full-table size (large icon container, generous padding).
  standard,

  /// Compact widget/card size (for dashboard cards, modal panels, sub-tables).
  compact,

  /// Inline/minimal size (for narrow search results or sub-rows).
  inline,
}

/// Action model for [DefensysEmptyState] buttons.
class DefensysEmptyAction {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool isOutlined;

  const DefensysEmptyAction({
    required this.label,
    this.icon,
    required this.onPressed,
    this.isOutlined = false,
  });
}

/// Anti-slop, enterprise-grade unified Empty State component for DefenSYS.
///
/// Provides consistent typography hierarchy, dual-layer icon badges,
/// standardized size variants, and tactile action buttons.
class DefensysEmptyState extends StatelessWidget {
  /// Primary icon to display inside the styled badge.
  final IconData icon;

  /// Main bold heading (e.g. "No Defense Stages Configured").
  final String title;

  /// Helpful secondary text explaining the state or recovery steps.
  final String? description;

  /// Primary call-to-action button (e.g. "+ Add School Year").
  final DefensysEmptyAction? primaryAction;

  /// Secondary action button (e.g. "Reset Filters").
  final DefensysEmptyAction? secondaryAction;

  /// Size preset determining padding, badge dimensions, and font sizes.
  final DefensysEmptyStateSize size;

  /// Optional icon badge tint (defaults to neutral slate).
  final Color? iconColor;

  /// Optional icon container background color.
  final Color? iconBackgroundColor;

  /// Custom icon size override (if null, derived from [size]).
  final double? iconSize;

  /// Custom padding override.
  final EdgeInsetsGeometry? padding;

  /// Maximum width for the description text block to prevent awkward line lengths.
  final double maxContentWidth;

  const DefensysEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.description,
    this.primaryAction,
    this.secondaryAction,
    this.size = DefensysEmptyStateSize.standard,
    this.iconColor,
    this.iconBackgroundColor,
    this.iconSize,
    this.padding,
    this.maxContentWidth = 440,
  });

  /// Factory constructor tailored for dashboard cards (e.g., Upcoming Defenses, Team Overview).
  factory DefensysEmptyState.card({
    Key? key,
    IconData icon = Icons.event_busy_outlined,
    required String title,
    String? description,
    DefensysEmptyAction? action,
    Color? iconColor,
  }) {
    return DefensysEmptyState(
      key: key,
      icon: icon,
      title: title,
      description: description,
      primaryAction: action,
      size: DefensysEmptyStateSize.compact,
      iconColor: iconColor,
      padding: const EdgeInsets.symmetric(
        horizontal: DefensysTokens.spacingLg,
        vertical: DefensysTokens.spacingXl,
      ),
    );
  }

  /// Factory constructor tailored for empty data table bodies.
  factory DefensysEmptyState.table({
    Key? key,
    IconData icon = Icons.table_rows_outlined,
    required String title,
    String? description,
    DefensysEmptyAction? primaryAction,
    DefensysEmptyAction? secondaryAction,
    DefensysEmptyStateSize size = DefensysEmptyStateSize.standard,
    EdgeInsetsGeometry? padding,
  }) {
    return DefensysEmptyState(
      key: key,
      icon: icon,
      title: title,
      description: description,
      primaryAction: primaryAction,
      secondaryAction: secondaryAction,
      size: size,
      padding: padding ??
          (size == DefensysEmptyStateSize.compact
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 28)
              : const EdgeInsets.symmetric(horizontal: 24, vertical: 40)),
    );
  }

  /// Factory constructor tailored for search or filter queries returning 0 results.
  factory DefensysEmptyState.search({
    Key? key,
    String? query,
    String title = 'No results found',
    String? description,
    VoidCallback? onReset,
    String resetLabel = 'Reset Filters',
  }) {
    final effectiveDesc = description ??
        (query != null && query.isNotEmpty
            ? 'No matches found for "$query". Check for typos or reset your active filters.'
            : 'No records match your active search criteria or filter parameters.');

    return DefensysEmptyState(
      key: key,
      icon: Icons.search_off_rounded,
      title: title,
      description: effectiveDesc,
      secondaryAction: onReset != null
          ? DefensysEmptyAction(
              label: resetLabel,
              icon: Icons.filter_alt_off_rounded,
              isOutlined: true,
              onPressed: onReset,
            )
          : null,
      size: DefensysEmptyStateSize.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectivePadding = padding ?? _defaultPaddingForSize(size);
    final (badgeSize, resolvedIconSize) = _badgeAndIconSize(size);

    return Center(
      child: Padding(
        padding: effectivePadding,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildIconBadge(badgeSize, resolvedIconSize),
              SizedBox(height: _spacingAfterIcon(size)),
              _buildTitle(context),
              if (description != null && description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildDescription(context),
              ],
              if (primaryAction != null || secondaryAction != null) ...[
                SizedBox(height: _spacingBeforeActions(size)),
                _buildActionButtons(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconBadge(double badgeSize, double resolvedIconSize) {
    return Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        color: iconBackgroundColor ?? DefensysTokens.neutralBg,
        borderRadius: BorderRadius.circular(
          size == DefensysEmptyStateSize.compact
              ? DefensysTokens.radiusLg
              : DefensysTokens.radiusXl,
        ),
        border: Border.all(
          color: DefensysTokens.border,
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          icon,
          size: iconSize ?? resolvedIconSize,
          color: iconColor ?? DefensysTokens.steelGrey,
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    final (fontSize, fontWeight) = _titleStyleForSize(size);
    return Text(
      title,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: DefensysTokens.fontFamily,
        color: DefensysTokens.textPrimary,
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: 1.25,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _buildDescription(BuildContext context) {
    final fontSize = size == DefensysEmptyStateSize.compact ? 12.5 : 13.0;
    return Text(
      description!,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: DefensysTokens.fontFamilyInter,
        color: DefensysTokens.textSecondary,
        fontSize: fontSize,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final actions = <Widget>[];

    if (secondaryAction != null) {
      actions.add(_buildButton(secondaryAction!, isPrimary: false));
    }

    if (primaryAction != null) {
      if (actions.isNotEmpty) {
        actions.add(const SizedBox(width: 10));
      }
      actions.add(_buildButton(primaryAction!, isPrimary: true));
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: actions,
    );
  }

  Widget _buildButton(DefensysEmptyAction action, {required bool isPrimary}) {
    final isCompact = size == DefensysEmptyStateSize.compact;
    final buttonHeight = isCompact ? 34.0 : 38.0;

    if (action.isOutlined || !isPrimary) {
      return OutlinedButton(
        onPressed: action.onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: DefensysTokens.textPrimary,
          backgroundColor: Colors.white,
          side: const BorderSide(color: DefensysTokens.border),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 12 : 16,
            vertical: 0,
          ),
          minimumSize: Size(0, buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (action.icon != null) ...[
              Icon(action.icon, size: isCompact ? 14 : 16, color: DefensysTokens.steelGrey),
              const SizedBox(width: 6),
            ],
            Text(
              action.label,
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                fontSize: isCompact ? 12 : 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return ElevatedButton(
      onPressed: action.onPressed,
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: DefensysTokens.maroon,
        elevation: 0,
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 14 : 18,
          vertical: 0,
        ),
        minimumSize: Size(0, buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (action.icon != null) ...[
            Icon(action.icon, size: isCompact ? 14 : 16, color: Colors.white),
            const SizedBox(width: 6),
          ],
          Text(
            action.label,
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              fontSize: isCompact ? 12 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static EdgeInsetsGeometry _defaultPaddingForSize(DefensysEmptyStateSize size) {
    switch (size) {
      case DefensysEmptyStateSize.standard:
        return const EdgeInsets.symmetric(
          horizontal: DefensysTokens.spacing2xl,
          vertical: DefensysTokens.spacing4xl,
        );
      case DefensysEmptyStateSize.compact:
        return const EdgeInsets.symmetric(
          horizontal: DefensysTokens.spacingLg,
          vertical: DefensysTokens.spacing2xl,
        );
      case DefensysEmptyStateSize.inline:
        return const EdgeInsets.symmetric(
          horizontal: DefensysTokens.spacingMd,
          vertical: DefensysTokens.spacingLg,
        );
    }
  }

  static (double badgeSize, double iconSize) _badgeAndIconSize(
    DefensysEmptyStateSize size,
  ) {
    switch (size) {
      case DefensysEmptyStateSize.standard:
        return (52.0, 26.0);
      case DefensysEmptyStateSize.compact:
        return (42.0, 20.0);
      case DefensysEmptyStateSize.inline:
        return (32.0, 16.0);
    }
  }

  static double _spacingAfterIcon(DefensysEmptyStateSize size) {
    switch (size) {
      case DefensysEmptyStateSize.standard:
        return 14.0;
      case DefensysEmptyStateSize.compact:
        return 10.0;
      case DefensysEmptyStateSize.inline:
        return 8.0;
    }
  }

  static double _spacingBeforeActions(DefensysEmptyStateSize size) {
    switch (size) {
      case DefensysEmptyStateSize.standard:
        return 18.0;
      case DefensysEmptyStateSize.compact:
        return 14.0;
      case DefensysEmptyStateSize.inline:
        return 10.0;
    }
  }

  static (double fontSize, FontWeight weight) _titleStyleForSize(
    DefensysEmptyStateSize size,
  ) {
    switch (size) {
      case DefensysEmptyStateSize.standard:
        return (15.5, FontWeight.w700);
      case DefensysEmptyStateSize.compact:
        return (14.0, FontWeight.w700);
      case DefensysEmptyStateSize.inline:
        return (13.0, FontWeight.w600);
    }
  }
}

/// Backward-compatible adapter class wrapping [DefensysEmptyState].
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double iconSize;

  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.iconSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    return DefensysEmptyState(
      icon: icon,
      title: message,
      iconSize: iconSize,
      primaryAction: actionLabel != null && onAction != null
          ? DefensysEmptyAction(
              label: actionLabel!,
              onPressed: onAction!,
            )
          : null,
    );
  }
}
