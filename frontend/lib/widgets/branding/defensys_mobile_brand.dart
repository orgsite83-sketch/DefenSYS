import 'package:flutter/material.dart';

import '../../theme/defensys_tokens.dart';
import 'defensys_logo_mark.dart';

/// Identity for root mobile workspaces. Detail routes retain contextual titles.
class DefensysMobileBrand extends StatelessWidget {
  const DefensysMobileBrand({super.key});

  static bool usesMobileHeader(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 760;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'DefenSYS',
    header: true,
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DefensysLogoMark(
            size: 32,
            colorMode: DefensysTokens.isDark(context)
                ? DefensysLogoColorMode.white
                : DefensysLogoColorMode.brand,
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              'DefenSYS',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: DefensysTokens.textPrimaryOf(context),
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -.4,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
