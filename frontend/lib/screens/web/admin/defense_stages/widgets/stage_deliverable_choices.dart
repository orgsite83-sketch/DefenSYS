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

/// Post-defense requirements use Required / Optional, without verdict exemptions.
class StagePostDefenseReviewNotice extends StatelessWidget {
  const StagePostDefenseReviewNotice({super.key});

  @override
  Widget build(BuildContext context) => Text(
    'Required post-defense files need faculty acceptance for deliverable clearance.',
    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
  );
}
