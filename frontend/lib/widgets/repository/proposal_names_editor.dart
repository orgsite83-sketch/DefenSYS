import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../theme/defensys_tokens.dart';

/// Inline title confirmation. The caller retains the permission and review token.
class ProposalNamesEditor extends StatefulWidget {
  const ProposalNamesEditor({
    super.key,
    required this.rows,
    required this.shared,
    required this.busy,
    required this.onBack,
    required this.onConfirm,
    this.systems = false,
  });
  final List<Map<String, dynamic>> rows;
  final bool shared;
  final bool systems;
  final bool busy;
  final VoidCallback onBack;
  final Future<void> Function(List<Map<String, dynamic>>) onConfirm;

  @override
  State<ProposalNamesEditor> createState() => _ProposalNamesEditorState();
}

class _ProposalNamesEditorState extends State<ProposalNamesEditor> {
  late final editors = {
    for (final row in widget.rows)
      '${row['key']}': TextEditingController(text: '${row['title'] ?? ''}'),
  };
  bool invalid = false;

  String label(Map<String, dynamic> row, int index) {
    final key = '${row['key']}';
    final number = key.startsWith('c')
        ? int.tryParse(key.substring(1)) ?? index + 1
        : index + 1;
    final system = 'System ${String.fromCharCode(64 + number)}';
    if (widget.systems) return system;
    return widget.shared
        ? '$system · ${row['system_title'] ?? ''}'
        : 'Concept $number';
  }

  @override
  void dispose() {
    for (final editor in editors.values) {
      editor.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            'Confirm ${widget.systems
                ? 'system'
                : widget.shared
                ? 'module'
                : 'concept'} names',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: DefensysTokens.textPrimaryOf(context),
            ),
          ),
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            enabled: !widget.busy,
            onPressed: widget.onBack,
            child: const Text('Back to papers'),
          ),
        ],
      ),
      for (final (index, row) in widget.rows.indexed) ...[
        const SizedBox(height: 16),
        Text(
          label(row, index),
          style: TextStyle(
            fontSize: 12,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 6),
        ShadInput(
          controller: editors['${row['key']}'],
          enabled: !widget.busy,
          minLines: 1,
          maxLines: 3,
          maxLength: 255,
          placeholder: Text(
            widget.systems
                ? 'System name'
                : widget.shared
                ? 'Module name'
                : 'Concept name',
          ),
        ),
      ],
      if (invalid)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'Enter a name for every proposal.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: ShadButton(
          size: ShadButtonSize.sm,
          enabled: !widget.busy,
          onPressed: () async {
            if (editors.values.any((e) => e.text.trim().isEmpty)) {
              setState(() => invalid = true);
              return;
            }
            await widget.onConfirm([
              for (final row in widget.rows)
                {...row, 'title': editors['${row['key']}']!.text.trim()},
            ]);
          },
          child: const Text('Confirm names'),
        ),
      ),
    ],
  );
}
