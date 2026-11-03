import 'package:flutter/material.dart';
import '../../../../../theme/defensys_tokens.dart';

/// Two views of one selection, inside a single parent shadcn card.
class CurriculumLinkedPanels extends StatelessWidget {
  const CurriculumLinkedPanels({
    super.key,
    required this.overview,
    required this.detail,
  });
  final Widget overview, detail;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, c) {
      final divider = DefensysTokens.borderOf(context);
      if (c.maxWidth < 820) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            overview,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Divider(height: 1, color: divider),
            ),
            detail,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: overview,
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.only(left: 24),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: divider)),
              ),
              child: detail,
            ),
          ),
        ],
      );
    },
  );
}
