import 'package:flutter/material.dart';

import '../theme/program_colors.dart';

class ProgramBadge extends StatelessWidget {
  const ProgramBadge({super.key, this.scope, this.data, this.label});

  final String? scope;
  final Map? data;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = ProgramColors.of(context, scope: scope, data: data);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: colors.tint,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label ?? colors.label,
        style: TextStyle(
          color: colors.text,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
