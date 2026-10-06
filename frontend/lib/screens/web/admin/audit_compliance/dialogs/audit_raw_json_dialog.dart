import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/toasts/feedback_toast.dart';

class AuditRawJsonDialog extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;

  const AuditRawJsonDialog({
    super.key,
    required this.title,
    required this.data,
  });

  static void show(BuildContext context, {required String title, required Map<String, dynamic> data}) {
    showDialog(
      context: context,
      builder: (context) => AuditRawJsonDialog(title: title, data: data),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = DefensysTokens.isDark(context);
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);

    return Dialog(
      backgroundColor: DefensysTokens.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DefensysTokens.radiusLg),
        side: BorderSide(color: DefensysTokens.borderOf(context)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2932) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(DefensysTokens.radiusSm),
                    ),
                    child: const Icon(Icons.code_rounded, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    splashRadius: 18,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Code Body
            Expanded(
              child: Container(
                color: isDark ? const Color(0xFF131316) : const Color(0xFF0F172A),
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: SelectableText(
                    jsonString,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      color: Color(0xFF38BDF8),
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),

            const Divider(height: 1),
            // Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: jsonString));
                      ToastService.success(
                        context,
                        'JSON payload copied to clipboard',
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('Copy JSON'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DefensysTokens.textPrimaryOf(context),
                      side: BorderSide(color: DefensysTokens.borderOf(context)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: DefensysTokens.maroonOf(context),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
