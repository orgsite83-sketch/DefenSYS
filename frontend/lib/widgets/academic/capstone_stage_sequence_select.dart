import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../theme/defensys_tokens.dart';
import '../shadcn/defensys_shadcn_scope.dart';

/// Stage identity includes its recorded term, even when labels are repeated.
class CapstoneStageSequenceSelect extends StatelessWidget {
  const CapstoneStageSequenceSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final List<Map<String, dynamic>> options;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final groups = <String, List<Map<String, dynamic>>>{};
      for (final option in options) {
        groups.putIfAbsent('${option['phase_label']}', () => []).add(option);
      }
      const textStyle = TextStyle(
        fontFamily: DefensysTokens.fontFamilyInter,
        fontSize: 13,
      );
      return DefensysShadcnScope(
        child: ShadSelect<String>(
          key: ValueKey('stage-sequence-$value'),
          initialValue: options.any((o) => '${o['key']}' == value)
              ? value
              : null,
          enabled: enabled && options.isNotEmpty,
          minWidth: constraints.maxWidth,
          maxWidth: constraints.maxWidth,
          maxHeight: 380,
          decoration: ShadDecoration(
            color: DefensysTokens.surfaceHigherOf(context),
            border: ShadBorder.all(
              color: DefensysTokens.borderOf(context),
              radius: BorderRadius.circular(8),
            ),
          ),
          placeholder: const Text('Stage View', style: textStyle),
          options: [
            for (final group in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Text(
                  group.key,
                  style: textStyle.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              for (final option in group.value)
                ShadOption<String>(
                  key: ValueKey('stage-option-${option['key']}'),
                  value: '${option['key']}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${option['stage_label']}', style: textStyle),
                      Text(
                        '${option['read_only'] == true ? 'Read-only · ' : ''}${option['display_semester'] ?? ''}',
                        style: textStyle.copyWith(
                          fontSize: 11,
                          color: DefensysTokens.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
          selectedOptionBuilder: (context, key) {
            final option = options.where((o) => '${o['key']}' == key).first;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stage View',
                  style: textStyle.copyWith(
                    fontSize: 10,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                ),
                Text(
                  '${option['phase_label']} · ${option['stage_label']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                ),
              ],
            );
          },
          onChanged: (key) {
            if (key != null) onChanged(key);
          },
        ),
      );
    },
  );
}
