import 'package:flutter/material.dart';

import '../theme/defensys_tokens.dart';

/// Reusable tactile button wrapper implementing anti-slop micro-physics.
/// On tap press/active, scales down slightly (scale 0.98) to provide physical feedback.
class TactileButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry? padding;
  final BoxDecoration? decoration;
  final Color? hoverColor;
  final double pressedScale;
  final Duration animationDuration;
  final bool enabled;

  const TactileButton({
    super.key,
    required this.child,
    this.onPressed,
    this.padding,
    this.decoration,
    this.hoverColor,
    this.pressedScale = 0.98,
    this.animationDuration = const Duration(milliseconds: 100),
    this.enabled = true,
  });

  /// Standard Primary Maroon Action Button with Tactile Feedback
  factory TactileButton.primary({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    Widget? icon,
    bool isLoading = false,
    double? width,
    double height = DefensysTokens.buttonHeightPrimary,
  }) {
    return _PrimaryTactileButton(
      key: key,
      label: label,
      onPressed: onPressed,
      icon: icon,
      isLoading: isLoading,
      width: width,
      height: height,
    );
  }

  /// Standard Secondary Outline Action Button with Tactile Feedback
  factory TactileButton.secondary({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    Widget? icon,
    bool isLoading = false,
    double? width,
    double height = DefensysTokens.buttonHeightSecondary,
  }) {
    return _SecondaryTactileButton(
      key: key,
      label: label,
      onPressed: onPressed,
      icon: icon,
      isLoading: isLoading,
      width: width,
      height: height,
    );
  }

  @override
  State<TactileButton> createState() => _TactileButtonState();
}

class _TactileButtonState extends State<TactileButton> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool canInteract = widget.enabled && widget.onPressed != null;

    return MouseRegion(
      cursor: canInteract ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: canInteract ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: canInteract ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: canInteract ? () => setState(() => _isPressed = false) : null,
        onTap: canInteract ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _isPressed ? widget.pressedScale : 1.0,
          duration: widget.animationDuration,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: widget.animationDuration,
            padding: widget.padding,
            decoration: widget.decoration?.copyWith(
              color: _isHovered && canInteract && widget.hoverColor != null
                  ? widget.hoverColor
                  : widget.decoration?.color,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _PrimaryTactileButton extends TactileButton {
  _PrimaryTactileButton({
    super.key,
    required String label,
    required super.onPressed,
    Widget? icon,
    bool isLoading = false,
    double? width,
    double height = DefensysTokens.buttonHeightPrimary,
  }) : super(
          enabled: !isLoading && onPressed != null,
          child: SizedBox(
            width: width,
            height: height,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: onPressed != null && !isLoading
                    ? DefensysTokens.maroon
                    : DefensysTokens.neutralBorder,
                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                border: Border.all(
                  color: onPressed != null && !isLoading
                      ? DefensysTokens.maroonDark
                      : DefensysTokens.neutralBorder,
                  width: 1.0,
                ),
                boxShadow: onPressed != null && !isLoading
                    ? const [
                        BoxShadow(
                          color: Color(0x1A7A110A),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (icon != null) ...[
                            icon,
                            const SizedBox(width: 8),
                          ],
                          Text(
                            label,
                            style: const TextStyle(
                              fontFamily: DefensysTokens.fontFamily,
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
}

class _SecondaryTactileButton extends TactileButton {
  _SecondaryTactileButton({
    super.key,
    required String label,
    required super.onPressed,
    Widget? icon,
    bool isLoading = false,
    double? width,
    double height = DefensysTokens.buttonHeightSecondary,
  }) : super(
          enabled: !isLoading && onPressed != null,
          child: SizedBox(
            width: width,
            height: height,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: DefensysTokens.surface,
                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                border: Border.all(color: DefensysTokens.border, width: 1.0),
              ),
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(DefensysTokens.steelGrey),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (icon != null) ...[
                            icon,
                            const SizedBox(width: 6),
                          ],
                          Text(
                            label,
                            style: const TextStyle(
                              fontFamily: DefensysTokens.fontFamilyInter,
                              color: DefensysTokens.textDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
}
