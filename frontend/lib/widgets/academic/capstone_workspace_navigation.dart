import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';

/// A batch keeps both phases; History contains ended batches only.
class CapstoneWorkspaceNavigation extends StatelessWidget {
  const CapstoneWorkspaceNavigation({
    super.key,
    required this.data,
    required this.onChanged,
    this.enabled = true,
  });

  final Map<String, dynamic> data;
  final bool enabled;
  final void Function(String view, String batch, String semester) onChanged;

  @override
  Widget build(BuildContext context) {
    final view = '${data['view'] ?? 'ongoing'}';
    final batch = '${data['batch_id'] ?? ''}';
    final batches = (data['batches'] as List? ?? []).whereType<Map>().toList();
    const style = TextStyle(
      fontFamily: DefensysTokens.fontFamilyInter,
      fontSize: 13,
    );
    return DefensysShadcnScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: ShadTabs<String>(
                  value: view,
                  onChanged: enabled
                      ? (value) => onChanged(value, '', '')
                      : null,
                  tabs: const [
                    ShadTab(value: 'ongoing', child: Text('Ongoing')),
                    ShadTab(value: 'history', child: Text('History')),
                  ],
                ),
              ),
              if (batches.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: ShadSelect<String>(
                    key: ValueKey('capstone-batch-$view-$batch'),
                    initialValue: batches.any((b) => '${b['value']}' == batch)
                        ? batch
                        : null,
                    enabled: enabled,
                    placeholder: const Text(
                      'Select capstone batch',
                      style: style,
                    ),
                    options: [
                      for (final b in batches)
                        ShadOption(
                          value: '${b['value']}',
                          child: Text('${b['label']}', style: style),
                        ),
                    ],
                    selectedOptionBuilder: (context, value) => Text(
                      '${batches.where((b) => '${b['value']}' == value).firstOrNull?['label'] ?? value}',
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                    onChanged: (value) {
                      if (value != null) onChanged(view, value, '');
                    },
                  ),
                ),
            ],
          ),
          if (batches.isEmpty && enabled) ...[
            const SizedBox(height: 12),
            Text(
              view == 'history'
                  ? 'No previous batches.'
                  : 'No ongoing batches.',
              style: style,
            ),
          ],
        ],
      ),
    );
  }
}
