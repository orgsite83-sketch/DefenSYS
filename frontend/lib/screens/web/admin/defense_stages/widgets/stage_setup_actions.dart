import 'package:flutter/material.dart';

/// Keep setup actions readable when the sidebar or a narrow window limits width.
class StageSetupActions extends StatelessWidget {
  const StageSetupActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= 720
        ? Row(children: children)
        : Wrap(
            alignment: WrapAlignment.end,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: children.where((child) => child is! Spacer).toList(),
          ),
  );
}
