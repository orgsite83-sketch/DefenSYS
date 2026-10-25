import 'package:flutter/material.dart';

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
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const DefensysLogoMark(
              size: 26,
              colorMode: DefensysLogoColorMode.brand,
            ),
          ),
          const SizedBox(width: 9),
          const Flexible(
            child: Text(
              'DefenSYS',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
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
