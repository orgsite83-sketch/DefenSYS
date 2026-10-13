import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../../widgets/shadcn/defensys_shadcn_scope.dart';

/// The file type has enough options to warrant a select. Keep the stored
/// identifiers shared by Add Stage and Edit Stage.
class StageFileFormatPicker extends StatelessWidget {
  const StageFileFormatPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  static const formats = <String, String>{
    'any': 'Any file type',
    'pdf': 'PDF document (.pdf)',
    'video': 'Video (.mp4, .mov)',
    'image': 'Image (.png, .jpg)',
    'presentation': 'Slides (.pptx, .ppt)',
    'document': 'Word document (.docx, .doc)',
    'spreadsheet': 'Spreadsheet (.xlsx, .csv)',
    'archive': 'Archive (.zip, .rar)',
    'audio': 'Audio (.mp3, .wav)',
  };

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: ShadSelect<String>(
      key: ValueKey('stage-file-format-$value'),
      initialValue: formats.containsKey(value) ? value : 'any',
      enabled: enabled,
      minWidth: 210,
      maxWidth: 300,
      placeholder: const Text('File format'),
      options: [
        for (final option in formats.entries)
          ShadOption<String>(value: option.key, child: Text(option.value)),
      ],
      selectedOptionBuilder: (context, selected) => Text(
        formats[selected] ?? selected,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
    ),
  );
}

/// The post-defense rule is binary, so it is clearer as visible choices.
class StageVerdictConditionChoices extends StatelessWidget {
  const StageVerdictConditionChoices({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget choice(String id, String title, String explanation) {
      final selected = value == id;
      return Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected
              ? Color.alphaBlend(
                  theme.colorScheme.primary.withValues(alpha: .07),
                  theme.colorScheme.surface,
                )
              : theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: selected ? theme.colorScheme.primary : theme.dividerColor,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            onTap: enabled ? () => onChanged(id) : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(explanation, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Who needs to submit this file?',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final all = choice(
              'all_pass',
              'All passing teams',
              'Required after any passing result.',
            );
            final revisions = choice(
              'revisions_only',
              'Approved with revisions only',
              'Required only when revisions are assigned.',
            );
            return constraints.maxWidth < 540
                ? Column(children: [all, const SizedBox(height: 8), revisions])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: all),
                      const SizedBox(width: 8),
                      Expanded(child: revisions),
                    ],
                  );
          },
        ),
      ],
    );
  }
}
