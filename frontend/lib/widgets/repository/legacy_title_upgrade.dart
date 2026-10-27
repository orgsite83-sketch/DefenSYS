import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../shadcn/defensys_shadcn_scope.dart';

/// Upgrades are explicit so existing approval evidence is never reset by a read.
class LegacyTitleUpgrade extends StatefulWidget {
  const LegacyTitleUpgrade({
    super.key,
    required this.canApply,
    required this.preview,
    required this.apply,
  });
  final bool canApply;
  final Future<Map<String, dynamic>> Function() preview;
  final Future<void> Function(String token) apply;
  @override
  State<LegacyTitleUpgrade> createState() => _LegacyTitleUpgradeState();
}

class _LegacyTitleUpgradeState extends State<LegacyTitleUpgrade> {
  bool busy = false;
  String? error;
  Future<void> upgrade() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.preview();
      if (!mounted) return;
      final state = result['preflight'] as Map;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => DefensysShadcnScope(
          child: ShadDialog(
            title: const Text('Review title workflow upgrade'),
            description: Text(
              '${(state['systems'] as List).length} system titles · ${(state['teams'] as List).length} team rounds · ${(state['files'] as List).length} current files',
            ),
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ShadButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Apply title-first workflow'),
              ),
            ],
            child: Text('${result['effects']}'),
          ),
        ),
      );
      if (confirmed == true) await widget.apply('${result['token']}');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'This existing proposal uses the earlier review rules. An administrator can review its approval history and switch it to title-first review.',
        ),
        if (widget.canApply)
          Align(
            alignment: Alignment.centerRight,
            child: ShadButton.outline(
              enabled: !busy,
              onPressed: upgrade,
              child: const Text('Review workflow upgrade'),
            ),
          ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}
