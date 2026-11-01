import 'package:flutter/material.dart';

import '../../theme/defensys_tokens.dart';

/// University and department identity for content panels and compact footers.
class InstitutionalBrand extends StatelessWidget {
  const InstitutionalBrand({
    super.key,
    this.logoHeight = 64,
    this.compact = false,
  });

  final double logoHeight;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    header: !compact,
    label: 'USTP Oroquieta, Department of Information Technology',
    child: ExcludeSemantics(
      child: compact
          ? Row(
              children: [
                _logos(context),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'USTP Oroquieta',
                        style: TextStyle(
                          fontFamily: DefensysTokens.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Department of IT',
                        style: TextStyle(
                          fontFamily: DefensysTokens.fontFamily,
                          fontSize: 11,
                          height: 1.3,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _logos(context),
                const SizedBox(height: 12),
                Text(
                  'USTP Oroquieta',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DefensysTokens.textPrimaryOf(context),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Department of Information Technology',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamily,
                    fontSize: 12,
                    height: 1.4,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
    ),
  );

  Widget _logos(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(
        DefensysTokens.isDark(context)
            ? 'assets/logo-ustp-white.png'
            : 'assets/logo-ustp-trans.png',
        height: logoHeight,
        width: logoHeight * 0.91,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
      ),
      SizedBox(width: compact ? 10 : 20),
      if (!compact) ...[
        Container(
          width: 1,
          height: logoHeight * 0.65,
          color: DefensysTokens.borderOf(context),
        ),
        const SizedBox(width: 20),
      ],
      Image.asset(
        'assets/logo-dit-seal.png',
        height: logoHeight * 0.88,
        width: logoHeight * 0.88,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
      ),
    ],
  );
}
