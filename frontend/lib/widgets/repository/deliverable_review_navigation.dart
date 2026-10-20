import 'package:flutter/widgets.dart';

import 'deliverable_file_widgets.dart';

/// The same current-file/slot ordering for the checklist and focused reviewer.
List<Map<String, dynamic>> deliverableReviewEntries(Map<String, dynamic> item) {
  final submission = item['submission'] as Map? ?? {};
  final files = (submission['files'] as List? ?? [])
      .whereType<Map>()
      .where((file) => file['is_current'] != false)
      .map((file) => Map<String, dynamic>.from(file))
      .toList();
  if (!usesGroupedDocumentCard(item)) {
    final hasFile =
        '${submission['file_url'] ?? ''}'.isNotEmpty ||
        '${submission['file_name'] ?? ''}'.isNotEmpty ||
        files.isNotEmpty;
    return [
      {
        'key': 'single',
        'label': item['label'] ?? item['name'] ?? 'Deliverable',
        'required': item['required'] != false,
        if (hasFile)
          'file': {
            ...Map<String, dynamic>.from(submission),
            if (files.length == 1) ...files.single,
          },
      },
    ];
  }
  final policy = item['file_policy'] as Map? ?? {};
  if (policy['mode'] == 'multiple') {
    final minimum = (policy['min_files'] as num? ?? 1).toInt();
    return [
      for (final (index, file) in files.indexed)
        {
          'key': '${file['slot_key'] ?? file['id'] ?? 'attachment-$index'}',
          'label': 'Attachment ${index + 1}',
          'file': file,
          'required': index < minimum,
        },
      for (var i = files.length; i < minimum; i++)
        {'key': 'missing-$i', 'label': 'Attachment ${i + 1}', 'required': true},
    ];
  }
  return [
    for (final slot in (item['document_slots'] as List? ?? []).whereType<Map>())
      {
        ...Map<String, dynamic>.from(slot),
        'file': files
            .where((file) => file['slot_key'] == slot['key'])
            .firstOrNull,
      },
  ];
}

/// Owned by the team checklist so navigation can cross requirement boundaries.
class DeliverableReviewNavigation extends InheritedWidget {
  const DeliverableReviewNavigation({
    super.key,
    required this.fileKey,
    required this.onFileSelected,
    required this.onNextFile,
    required super.child,
  });
  final String? fileKey;
  final ValueChanged<String> onFileSelected;
  final VoidCallback? onNextFile;

  static DeliverableReviewNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeliverableReviewNavigation>();

  @override
  bool updateShouldNotify(DeliverableReviewNavigation oldWidget) =>
      fileKey != oldWidget.fileKey ||
      onNextFile != oldWidget.onNextFile ||
      onFileSelected != oldWidget.onFileSelected;
}
