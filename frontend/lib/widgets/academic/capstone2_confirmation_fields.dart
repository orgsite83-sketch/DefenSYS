import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../theme/defensys_tokens.dart';

String newCapstoneRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class Capstone2ConfirmationFields extends StatelessWidget {
  const Capstone2ConfirmationFields({
    super.key,
    required this.confirmed,
    required this.onChanged,
    required this.reference,
    required this.needsReference,
    this.enabled = true,
  });
  final bool confirmed, needsReference, enabled;
  final ValueChanged<bool> onChanged;
  final TextEditingController reference;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ShadCheckbox(
        value: confirmed,
        enabled: enabled,
        onChanged: onChanged,
        label: const Text(
          'I confirm that all selected members passed Capstone 1 and are eligible for Capstone 2.',
        ),
      ),
      if (needsReference) ...[
        const SizedBox(height: 14),
        const Text('School record reference'),
        const SizedBox(height: 6),
        ShadInput(
          key: const Key('capstone2-reference'),
          controller: reference,
          enabled: enabled,
          maxLength: 500,
          placeholder: const Text(
            'e.g. Capstone 1 grade sheet, BSIT-3A, A.Y. 2025–2026',
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'For members whose prior results are not in DefenSYS. One reference can cover the selected roster.',
          style: TextStyle(
            fontFamily: DefensysTokens.fontFamilyInter,
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ],
    ],
  );
}
