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

  static IconData iconFor(String key) => switch (key.toLowerCase()) {
    'pdf' => Icons.picture_as_pdf_rounded,
    'video' => Icons.videocam_rounded,
    'image' => Icons.image_rounded,
    'presentation' => Icons.slideshow_rounded,
    'document' => Icons.article_rounded,
    'spreadsheet' => Icons.table_chart_rounded,
    'archive' => Icons.folder_zip_rounded,
    'audio' => Icons.audio_file_rounded,
    _ => Icons.insert_drive_file_outlined,
  };

  static Color colorFor(String key) => switch (key.toLowerCase()) {
    'pdf' => const Color(0xFFDC2626),
    'video' => const Color(0xFF7C3AED),
    'image' => const Color(0xFF0284C7),
    'presentation' => const Color(0xFFEA580C),
    'document' => const Color(0xFF2563EB),
    'spreadsheet' => const Color(0xFF16A34A),
    'archive' => const Color(0xFFD97706),
    'audio' => const Color(0xFF0D9488),
    _ => const Color(0xFF64748B),
  };

  @override
  Widget build(BuildContext context) => DefensysShadcnScope(
    child: ShadSelect<String>(
      key: ValueKey('stage-file-format-$value'),
      initialValue: formats.containsKey(value) ? value : 'any',
      enabled: enabled,
      minWidth: 210,
      maxWidth: 320,
      placeholder: const Text('File format'),
      options: [
        for (final option in formats.entries)
          ShadOption<String>(
            value: option.key,
            child: Row(
              children: [
                Icon(
                  iconFor(option.key),
                  size: 16,
                  color: colorFor(option.key),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    option.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      selectedOptionBuilder: (context, selected) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconFor(selected), size: 16, color: colorFor(selected)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              formats[selected] ?? selected,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
    final isDark = theme.brightness == Brightness.dark;
    Widget choice(String id, String title, String explanation) {
      final selected = value == id;
      return Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? () => onChanged(id) : null,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              constraints: const BoxConstraints(minHeight: 46),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                    : (isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFFAFAFA)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFE2E8F0),
                  width: selected ? 1.5 : 1,
                ),
                boxShadow: selected
                    ? const [
                        BoxShadow(
                          color: Color(0x0A000000),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFCBD5E1),
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? Center(
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? const Color(0xFF0F172A)
                                : const Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 1.5),
                        Text(
                          explanation,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF64748B),
                            height: 1.25,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
            fontSize: 12,
            color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
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
                ? Column(children: [all, const SizedBox(height: 6), revisions])
                : Row(
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
