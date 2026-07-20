import 'package:flutter/material.dart';
import 'package:defensys/services/student_teams_provider.dart';

List<String> formatBulkImportErrorLines(dynamic messages) {
  if (messages is List) {
    return messages.map((item) => item.toString()).toList();
  }
  if (messages is Map) {
    final lines = <String>[];
    for (final entry in messages.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is List) {
        for (final item in value) {
          lines.add('$key: $item');
        }
      } else {
        lines.add('$key: $value');
      }
    }
    return lines;
  }
  return [messages?.toString() ?? 'Unknown error'];
}

Future<void> showCapstoneCreationBlockedDialog({
  required BuildContext context,
  required StudentTeamsState state,
  required VoidCallback? onOpenStudentRecords,
}) async {
  final message = state.capstoneModeMessage?.trim();
  if (message == null || message.isEmpty) {
    return;
  }

  final isCapstone2 = state.capstoneMode == 'capstone_2_continue';

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text('Capstone team creation closed'),
      content: SizedBox(
        width: 480,
        child: Text(
          message,
          style: const TextStyle(
            color: Color(0xFF374151),
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ),
      actions: [
        if (isCapstone2 && onOpenStudentRecords != null)
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onOpenStudentRecords.call();
            },
            child: const Text('Student Records'),
          ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<void> showImportResultDialog({
  required BuildContext context,
  required Map<String, dynamic> result,
}) async {
  final errors = (result['errors'] as List? ?? const [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();

  if (errors.isEmpty) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Text('Import issues'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: errors.map((error) {
              final row = error['row'];
              final teamName = error['team_name']?.toString() ?? '-';
              final sheetRow = error['sheet_row'] ?? ((row is int) ? row + 1 : null);
              final issueLines = formatBulkImportErrorLines(error['errors']);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Row $row · $teamName${sheetRow != null ? ' (sheet row $sheetRow)' : ''}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...issueLines.map(
                      (line) => Text(
                        '• $line',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
